import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'database.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'calibracion_model.dart';
import 'procesador_senal.dart';
import 'posicionador.dart';
import 'mapa_widget.dart';
import 'pathfinder.dart';
import 'bluetooth_helper.dart';
import 'orientacion_service.dart';
import 'voz_service.dart';
import 'grilla_nav.dart';
import 'filtro_un_euro.dart';
import 'detector_movimiento.dart';
import 'tema.dart';
 
class PantallaNavegacion extends StatefulWidget {
  final int pisoId;
  final String rutaImagen;
  final ProcesadorSenal? procesadorCompartido;

  /// Hacia qué punto cardinal apunta el borde SUPERIOR de la imagen del mapa.
  /// 0 = Norte (default), 90 = Este, 180 = Sur, 270 = Oeste.
  /// Se configura una sola vez al importar el plano.
  final double rotacionMapa;

  /// Metros que representa el plano en cada eje (escala configurada por piso).
  final double escalaX;
  final double escalaY;

  /// Lado de celda de la grilla (m). Configurable por piso, rango 0.5–1.0.
  final double tamCeldaMetros;

  const PantallaNavegacion({
    super.key,
    required this.pisoId,
    required this.rutaImagen,
    this.procesadorCompartido,
    this.rotacionMapa = 0,
    this.escalaX = GrillaNav.escalaPorDefecto,
    this.escalaY = GrillaNav.escalaPorDefecto,
    this.tamCeldaMetros = 1.0,
  });
 
  @override
  State<PantallaNavegacion> createState() => _PantallaNavegacionState();
}
 
class _PantallaNavegacionState extends State<PantallaNavegacion> {
  late final ProcesadorSenal _procesador;
  final ResolvedorCaminos _resolvedor = ResolvedorCaminos();
  final OrientacionService _orientacion = OrientacionService();
  final VozService _voz = VozService();
  late final GrillaNav _grilla;
 
  Map<String, BeaconMarcado> _beaconsEnElMapa = {};
  List<ZonaNoTransitable> _zonas = [];
  List<LugarInteres> _lugares = [];
  List<CalibracionRegistro> _calibraciones = [];
 
  // ── Posición ──────────────────────────────────────────────────────────────
  //
  // FILTRO ONE EURO + ACELERÓMETRO (reemplaza al EMA de α fijo).
  //
  // El EMA anterior usaba α = 0.15 (τ ≈ 1.2 s) SIEMPRE. Ese único valor tenía
  // que servir para dos situaciones opuestas y no servía bien para ninguna:
  // con el usuario parado dejaba pasar ~31 cm de jitter por ciclo (la celda
  // parpadeaba), y caminando iba ~1.2 s atrasado (≈1.4 m a paso normal).
  //
  // Ahora la frecuencia de corte se adapta: el acelerómetro dice si el usuario
  // está quieto o caminando, y el filtro interpola entre suavizado fuerte y
  // respuesta rápida. Medido en simulación con ruido BLE de 1.5 m:
  //   EMA α=0.15  → 1.19 m de error caminando | 30.5 cm/ciclo de jitter parado
  //   One Euro+acc→ 0.95 m de error caminando |  8.7 cm/ciclo de jitter parado
  late final FiltroUnEuroPosicion _filtroPosicion;
  final DetectorMovimiento _movimiento = DetectorMovimiento();

  /// Puerta direccional por rumbo (ver [PuertaRumbo] en posicionador.dart).
  /// Es la que decide si un desplazamiento perpendicular a la direccion de
  /// marcha es ruido BLE o movimiento real. Tiene estado entre ciclos: por eso
  /// es un campo y no una funcion suelta.
  final PuertaRumbo _puertaRumbo = PuertaRumbo();

  /// Calidad minima de la brujula (0..1) para dejar que el rumbo restrinja el
  /// posicionamiento. Por debajo de esto el heading se sigue usando para las
  /// instrucciones de voz y para el icono, pero NO para condicionar la
  /// posicion: un rumbo distorsionado por metal cercano clavaria la posicion
  /// sobre un eje equivocado, que es peor que no restringir nada.
  static const double _calidadRumboMinima = 0.35;

  /// Timestamp de la muestra anterior: el One Euro necesita el Δt REAL de cada
  /// muestra, porque los callbacks BLE no llegan a ritmo constante.
  DateTime? _ultimaMuestraPos;

  /// Factor de movimiento del ciclo actual (0 = quieto, 1 = caminando).
  double _factorMovimiento = 0.0;

  Offset? _posicionFiltrada;

  // Tope de velocidad de la posicion, en m/s REALES. Defensa anti-spike: un
  // beacon con una lectura anomala no puede arrastrar la posicion de golpe. Se
  // escala con el movimiento: parado, un salto grande es siempre ruido.
  //
  // ANTES estaba expresado en unidades NORMALIZADAS (0.012 y 0.04), lo que lo
  // hacia depender del tamano del plano: los mismos 0.04 son 2 m en un plano de
  // 50 m y 4 m en uno de 100 m. Y como se aplicaba sobre la distancia
  // normalizada, en un plano rectangular (metrosX != metrosY) el tope terminaba
  // siendo distinto segun la direccion, sin relacion con el rumbo. Ahora es un
  // limite de velocidad fisico y se multiplica por el dt real del ciclo.
  static const double _velMaxQuietoMs = 1.2;
  static const double _velMaxMoviendoMs = 3.0;

  /// Fraccion del tope longitudinal que se le permite al eje PERPENDICULAR al
  /// rumbo cuando el usuario camina. Es la ultima linea de defensa contra la
  /// deriva lateral, por debajo de la puerta direccional.
  static const double _facTopePerp = 0.35;

  /// Zona muerta (en metros) con el usuario detenido: si la posición filtrada
  /// se movería menos que esto, se deja clavada. Elimina el jitter residual
  /// que igual sobrevive al filtro y evita el parpadeo de celda.
  static const double _zonaMuertaQuietoMetros = 0.35;

  // _historialPosiciones/_ventanaCentroid (promedio móvil redundante) fueron
  // eliminados: sumaban una segunda capa de latencia sin reducir ruido real,
  // ver el comentario en _calcularPosicionRobusta().
  Offset? _posicionFinal;

  // Histéresis de celda: estabiliza en qué celda de la grilla está el usuario,
  // evitando el parpadeo de borde entre dos celdas adyacentes (ver clase abajo).
  final _HisteresisCelda _histeresisCelda = _HisteresisCelda();

  // Throttle de repintado: desacopla el rebuild de la UI del ritmo del scan
  // BLE (que con continuousUpdates dispara muchos callbacks por segundo).
  DateTime? _ultimoRefrescoUI;
  static const Duration _intervaloRefrescoUI = Duration(milliseconds: 250);
 
  bool _escaneando = false;
  String _estadoScan = 'Iniciando...';
 
  // Navegacion
  LugarInteres? _destinoSeleccionado;
  List<Offset>? _rutaActual;
  String _estadoRuta = '';
  Offset? _ultimaPosicionRuta;
  static const double _umbralRecalcularRuta = 0.10; // ≈ 1 celda (~1 m normalizado)
  bool _calculandoRuta = false; // evita cálculos solapados
 
  // Orientacion
  StreamSubscription<CompassEvent>? _compassSubscription;
  bool _compassDisponible = false;

  // Rotación efectiva del mapa leída desde la DB en _inicializar().
  // Puede diferir de widget.rotacionMapa si el operador la cambió en config
  // sin reiniciar la navegación.
  double _rotacionMapaEfectiva = 0.0;

  // Título del AppBar: nombre del piso cargado async en _inicializar().
  String? _nombrePiso;

  // Flag: true solo después de que _resolvedor.inicializar() completó con los
  // datos reales de la DB. Previene que _calcularRuta() corra con una grilla
  // vacía si BLE empieza antes de que termine _inicializar().
  bool _resolvedorListo = false;
 
  // Trilateracion
  static const int _minBeaconsActivos = 2;
  static const int _maxBeaconsParaCalcular = 6; // máx. beacons por espacio
  // _umbralRSSI: descarta beacons demasiado lejanos/ruidosos. Con la nueva
  //   calibración (txPower = -55 dBm, n = 2.7), -90 dBm ≈ 20 m y -95 dBm ≈ 30 m.
  //   Bajamos de -95 a -90: más allá de ~20 m la señal BLE es tan débil y ruidosa
  //   que su distancia estimada distorsiona la trilateración más de lo que aporta.
  static const double _umbralRSSI = -90;
  // Dos beacons cuyo RSSI filtrado cae en la misma banda de este ancho (dBm)
  // se consideran "igual de cercanos": ahí desempata la varianza (más estable
  // primero). Ver ordenamiento en _calcularPosicionRobusta().
  static const double _umbralRssiSimilar = 2.0;
 
  Timer? _timeoutTimer;
  Timer? _scanReinicioTimer;  // watchdog del scan BLE (ver _iniciarEscaneo)

  /// Momento en que esta pantalla empezo a esperar resultados BLE. Es la
  /// referencia del watchdog mientras todavia no llego ningun lote.
  DateTime? _inicioEscaneo;

  /// Silencio BLE tolerado antes de dar el scan por muerto y forzar reinicio.
  /// Con removeIfGone de 4 s y beacons emitiendo a ~6 Hz, 8 s sin un solo lote
  /// no es "poca senal": es que el scan dejo de entregar.
  static const Duration _silencioParaReiniciar = Duration(seconds: 8);

  /// Cada cuanto corre el watchdog.
  static const Duration _intervaloWatchdog = Duration(seconds: 3);

  /// Reinicios forzados consecutivos sin exito. Solo para informar al usuario;
  /// la cuota de arranques la administra BluetoothHelper.
  int _reiniciosSinDatos = 0;
  Timer? _compassUITimer;     // refresca el chip de brújula a 4 Hz, desacoplado del BLE

  // Último heading que efectivamente disparó un rebuild de UI. Se usa para
  // que _compassUITimer no haga setState() (rebuild de TODA la pantalla,
  // incluido el mapa) cuando el heading no cambió — ver comentario junto al
  // Timer.periodic más abajo.
  double? _ultimoHeadingUIRefrescado;
  int _contadorLecturas = 0;

  // Throttle del pipeline de posicionamiento.
  // BLE en continuousUpdates puede disparar 20-50 callbacks/segundo.
  // Ejecutar trilateración + histéresis + pathfinder en cada uno satura el hilo
  // de UI. Limitamos a una ejecución cada 180 ms (~5.5 Hz), igual que la tasa
  // real de actualización de posición. El setState de UI ya tiene su propio
  // throttle de 250 ms por encima de este.
  DateTime? _ultimoPosicionamiento;
  static const Duration _intervaloPosicionamiento = Duration(milliseconds: 180);

  // Cooldown de reintento de ruta: cuando el pathfinder devuelve null (origen o
  // destino en obstáculo, grilla aún no cargada), esperamos 1.5 s antes de
  // reintentar en lugar de disparar un compute() por cada callback BLE.
  DateTime? _ultimoIntentoRuta;
  static const Duration _cooldownRuta = Duration(milliseconds: 1500);
 
  // Voz — STT
  bool _escuchando = false;
 
  @override
  void initState() {
    super.initState();
    _procesador = widget.procesadorCompartido ?? ProcesadorSenal();
    _grilla = GrillaNav(metrosX: widget.escalaX, metrosY: widget.escalaY, tamCeldaMetros: widget.tamCeldaMetros);
    // La escala del piso entra al filtro para que la velocidad se calcule en
    // m/s reales y los parámetros no dependan del tamaño del plano.
    _filtroPosicion = FiltroUnEuroPosicion(
      metrosX: _grilla.metrosX,
      metrosY: _grilla.metrosY,
    );
    _inicializar();
  }
 
  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _scanReinicioTimer?.cancel();
    _compassUITimer?.cancel();
    _compassSubscription?.cancel();
    _orientacion.limpiar();
    // Guarda de dueño, misma razón que en BluetoothHelper: si esta pantalla se
    // destruye DESPUÉS de que la siguiente ya arrancó, limpiar el TTS acá corta
    // el anuncio de la pantalla nueva. En el log del bug se veía justamente
    // eso: "Buscando ubicación" marcado como Interrupted: true.
    _voz.limpiar(dueno: this);
    _movimiento.detener();
    _puertaRumbo.resetear();
    _histeresisCelda.resetear();
    if (widget.procesadorCompartido == null) {
      BluetoothHelper.detenerScanSeguro(dueno: this);
    } else {
      // El scan fisico sigue vivo para la proxima pantalla, pero la suscripcion
      // hay que soltarla igual: si no, el stream sigue entregando a esta State
      // ya desmontada, cuyo callback descarta todo por !mounted. El scan queda
      // "vivo pero mudo" y la pantalla siguiente puede quedarse sin datos.
      BluetoothHelper.liberarSuscripcion(this);
    }
    super.dispose();
  }
 
  Future<void> _inicializar() async {
    try {
      _voz.registrarDueno(this);
      await _voz.inicializar();

      final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
      final zonas = await DatabaseHelper.instance.obtenerZonasPorPiso(widget.pisoId);
      final lugares = await DatabaseHelper.instance.obtenerLugaresPorPiso(widget.pisoId);
      final calibraciones = await DatabaseHelper.instance.obtenerCalibracionesPorPiso(widget.pisoId);

      // Lookup del nombre del piso para el AppBar (item 7).
      // DatabaseHelper no expone un método por id, así que consultamos
      // directamente la tabla 'pisos' filtrando por id.
      final db = await DatabaseHelper.instance.database;
      final filas = await db.query(
        'pisos',
        columns: ['nombre_piso', 'rotacion_mapa'],
        where: 'id = ?',
        whereArgs: [widget.pisoId],
        limit: 1,
      );
      final nombrePiso = filas.isNotEmpty
          ? filas.first['nombre_piso'] as String?
          : null;
      // rotacion_mapa puede no existir todavía en instalaciones antiguas (v7→v8);
      // usar el valor pasado por widget como fallback.
      final rotacionDb = filas.isNotEmpty
          ? ((filas.first['rotacion_mapa'] as num?)?.toDouble() ?? widget.rotacionMapa)
          : widget.rotacionMapa;

      if (!mounted) return;
      setState(() {
        _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
        _zonas = zonas;
        _lugares = lugares;
        _calibraciones = calibraciones;
        _nombrePiso = nombrePiso;
        _rotacionMapaEfectiva = rotacionDb;
      });
 
      _resolvedor.inicializar(_zonas, grilla: _grilla);
      _resolvedorListo = true;
      // Acelerómetro: si el dispositivo no lo expone, el detector devuelve un
      // factor intermedio fijo y el filtro sigue funcionando (con un
      // comportamiento parecido al EMA anterior).
      final hayAcelerometro = await _movimiento.iniciar();
      if (!hayAcelerometro) {
        debugPrint('[Posicionamiento] Sin acelerómetro: el filtro One Euro '
            'trabaja con factor de movimiento fijo.');
      }
      await _iniciarBrujula();
 
      // Anuncio de bienvenida. NO se espera a que termine: `hablar()` bloquea
      // hasta que el motor TTS confirma la locucion (o hasta su timeout, ~3.4 s
      // para este texto). Al entrar y salir rapido de la pantalla, el TTS
      // anterior se interrumpe y esa espera retrasaba el arranque del scan
      // varios segundos justo cuando mas importa. El anuncio es informativo:
      // no tiene por que estar en el camino critico del posicionamiento.
      _voz.hablarSinEsperar('Buscando ubicación.');
 
      if (widget.procesadorCompartido != null && FlutterBluePlus.isScanningNow) {
        if (mounted) {
          setState(() {
            _escaneando = true;
            _estadoScan = 'Continuando escaneo...';
          });
        }
        // Antes esta rama llamaba a _suscribirAScan(), que se suscribia al
        // stream pero NO instalaba el watchdog del scan. Resultado: todo el
        // camino "vengo del modo automatico" corria sin vigilancia, y si el
        // scan moria no habia nada que lo reviviera. Ahora ambos caminos pasan
        // por el mismo metodo.
        await _iniciarEscaneo(reutilizandoScan: true);
        return;
      }
 
      if (!mounted) return;
      final ok = await BluetoothHelper.verificarPrecondiciones(context);
      if (!ok) {
        if (mounted) {
          setState(() => _estadoScan = 'Bluetooth o permisos no disponibles');
        }
        await _voz.hablar('Bluetooth no disponible.');
        return;
      }
 
      await _iniciarEscaneo();
    } catch (e) {
      if (mounted) {
        setState(() => _estadoScan = 'Error de inicializacion: $e');
      }
    }
  }
 
  Future<void> _iniciarBrujula() async {
    try {
      _compassDisponible = FlutterCompass.events != null;
      if (!_compassDisponible) return;

      // Si en los primeros 5 s no llega ningún heading válido, declaramos la
      // brújula no disponible y lo anunciamos por TTS (una sola vez).
      bool recibioPrimerHeadingValido = false;
      final timeoutBrujula = Timer(const Duration(seconds: 5), () {
        if (!recibioPrimerHeadingValido && mounted) {
          setState(() => _compassDisponible = false);
          _compassSubscription?.cancel();
          _compassSubscription = null;
          _voz.hablarSinEsperar(
            'Brújula no disponible, las instrucciones de giro pueden ser menos precisas',
          );
          debugPrint('[Brujula] Timeout: no se recibió heading válido en 5 s.');
        }
      });

      _compassSubscription = FlutterCompass.events!.listen(
        (CompassEvent event) {
          if (event.heading == null) {
            // El hardware no está calibrado o aún no tiene fix: loguear y seguir.
            debugPrint('[Brujula] Evento con heading null — sensor sin calibrar o sin datos.');
            return;
          }
          if (!recibioPrimerHeadingValido) {
            recibioPrimerHeadingValido = true;
            timeoutBrujula.cancel();
            // Iniciar timer de UI para el chip de brújula a 4 Hz.
            //
            // BUG ORIGINAL: `setState(() {})` acá era INCONDICIONAL, 4 veces
            // por segundo, durante TODA la sesión de navegación — sin
            // importar si el heading había cambiado o no. Eso reconstruye la
            // pantalla ENTERA (mapa con InteractiveViewer, tarjeta de
            // indicación de giro, listas de beacons/lugares, etc.) 4x/s de
            // forma perpetua, compitiendo por el isolate principal con el
            // pipeline de posicionamiento BLE (~5.5 Hz) y con la recepción
            // del resultado del compute() del A*. A mayor duración de la
            // sesión, más se acumula esta competencia por CPU — coincide con
            // que el cálculo de ruta empeoraba con el tiempo.
            //
            // FIX: solo hacer setState si el heading cambió lo suficiente
            // como para importar visualmente (>1°). Si el usuario está
            // parado/apuntando estable, no hay rebuild — el heading crudo se
            // sigue actualizando en el modelo igual, sin costo de UI.
            _compassUITimer?.cancel();
            _compassUITimer = Timer.periodic(
              const Duration(milliseconds: 250),
              (_) {
                if (!mounted) return;
                final actual = _orientacion.heading;
                if (actual == null) return;
                final anterior = _ultimoHeadingUIRefrescado;
                bool cambio;
                if (anterior == null) {
                  cambio = true;
                } else {
                  // Diferencia angular con signo en [-180, 180). Mismo patrón
                  // que _diferenciaAngular() en OrientacionService: en Dart,
                  // el % de doubles preserva el signo del dividendo, así que
                  // hay que forzar el rango [0, 360) antes de doblar.
                  double d = ((actual - anterior) % 360 + 360) % 360;
                  if (d > 180) d -= 360;
                  cambio = d.abs() > 1.0;
                }
                if (cambio) {
                  _ultimoHeadingUIRefrescado = actual;
                  setState(() {});
                }
              },
            );
          }
          // Solo actualizar el modelo — sin setState aquí.
          if (!mounted) return;
          _orientacion.actualizarHeadingBrujula(event.heading!);
        },
        onError: (e) {
          timeoutBrujula.cancel();
          _compassUITimer?.cancel();
          debugPrint('[Brujula] Error en stream: $e');
          if (!mounted) return;
          setState(() => _compassDisponible = false);
          _voz.hablarSinEsperar(
            'Brújula no disponible, las instrucciones de giro pueden ser menos precisas',
          );
        },
        // cancelOnError:false mantiene la suscripción activa después de un error
        // transitorio del sensor (p.ej. calibración en curso en Android).
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[Brujula] Excepción al iniciar: $e');
      _compassDisponible = false;
    }
  }
 
  /// Arranca (o reengancha) el escaneo BLE e instala el watchdog.
  ///
  /// [reutilizandoScan] indica que venimos de otra pantalla que dejo el scan
  /// fisico corriendo (modo automatico): no hay que volver a pedir permisos ni
  /// arrancar nada, solo suscribirse. Pero el watchdog se instala IGUAL, que es
  /// justamente lo que faltaba antes.
  Future<void> _iniciarEscaneo({bool reutilizandoScan = false}) async {
    if (!mounted) return;
    setState(() => _escaneando = true);

    _inicioEscaneo = DateTime.now();
    _reiniciosSinDatos = 0;

    final scanOk = await BluetoothHelper.iniciarScanSeguro(
      dueno: this,
      onResultados: (resultados) => _actualizarSenales(resultados),
      onError: (e) {
        if (mounted) {
          setState(() => _estadoScan = 'Error en scan: $e');
        }
      },
      removeIfGone: const Duration(seconds: 4),
    );

    if (!scanOk && !reutilizandoScan) {
      // Puede ser un fallo real o simplemente falta de cupo de arranques. El
      // watchdog de abajo se instala igual y va a reintentar cuando haya cupo,
      // asi que esto es informativo, no terminal.
      final espera = BluetoothHelper.esperaParaArrancar();
      if (mounted) {
        setState(() => _estadoScan = espera > Duration.zero
            ? 'Reintentando escaneo en ${espera.inSeconds} s...'
            : 'No se pudo iniciar el escaneo');
      }
    } else if (mounted) {
      setState(() => _estadoScan = 'Buscando beacons...');
    }

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && _posicionFinal == null) {
        setState(() => _estadoScan = 'No se detectan beacons suficientes.\nAcercate a un beacon configurado.');
      }
    });

    _instalarWatchdogScan();
  }

  /// ── WATCHDOG DEL SCAN BLE ────────────────────────────────────────────────
  ///
  /// El watchdog anterior preguntaba `if (!FlutterBluePlus.isScanningNow)` cada
  /// 20 s. Esa condicion NO detecta el modo de falla que congelaba la posicion:
  /// cuando se supera el limite de Android de 5 arranques de scan por 30 s, el
  /// sistema acepta el `startScan()`, deja de entregar advertisements, y
  /// `isScanningNow` sigue devolviendo `true`. El watchdog concluia que el scan
  /// estaba sano y no hacia nada, para siempre.
  ///
  /// La unica evidencia confiable de que el scan esta vivo es que LLEGUEN
  /// DATOS. Por eso este watchdog vigila el silencio: si pasan
  /// [_silencioParaReiniciar] sin un solo lote de resultados, fuerza un
  /// reinicio completo (stop + start) en lugar de confiar en la bandera.
  void _instalarWatchdogScan() {
    _scanReinicioTimer?.cancel();
    _scanReinicioTimer = Timer.periodic(_intervaloWatchdog, (_) async {
      if (!mounted) return;

      final referencia =
          BluetoothHelper.ultimoResultado ?? _inicioEscaneo ?? DateTime.now();
      final silencio = DateTime.now().difference(referencia);
      if (silencio < _silencioParaReiniciar) {
        _reiniciosSinDatos = 0;
        return;
      }

      // AUTOCURACIÓN: si perdimos la propiedad del scan (una pantalla anterior
      // se destruyó tarde y desarmó nuestros callbacks), no hay nada que
      // "reiniciar" — hay que volver a registrarse. Sin esto, el watchdog
      // quedaba pidiendo un reinicio que el helper rechazaba en silencio,
      // exactamente lo que mostraba el log: "Forzando reinicio" cada 3 s,
      // para siempre, sin recuperación posible.
      if (!BluetoothHelper.esDueno(this)) {
        debugPrint('[BLE] Perdimos la propiedad del scan. Re-registrando.');
        await _iniciarEscaneo(reutilizandoScan: true);
        return;
      }

      debugPrint('[BLE] Sin resultados hace ${silencio.inSeconds}s '
          '(isScanningNow=${FlutterBluePlus.isScanningNow}). Forzando reinicio.');

      final ok = await BluetoothHelper.reiniciarScanForzado();
      if (!mounted) return;

      if (ok) {
        _reiniciosSinDatos = 0;
        setState(() => _estadoScan = 'Reconectando con los beacons...');
      } else {
        _reiniciosSinDatos++;
        final espera = BluetoothHelper.esperaParaArrancar();
        setState(() {
          _estadoScan = espera > Duration.zero
              ? 'Bluetooth saturado, reintentando en ${espera.inSeconds} s...'
              : 'Sin senal de beacons, reintentando...';
        });
        // Aviso por voz una sola vez, cuando el problema deja de ser un bache
        // momentaneo. Es informacion que un usuario ciego necesita: sin esto,
        // la app simplemente deja de guiarlo sin decir nada.
        if (_reiniciosSinDatos == 3) {
          _voz.hablarSinEsperar(
            'Perdi la senal de los beacons. Estoy reintentando.',
          );
        }
      }
    });
  }
 
  void _actualizarSenales(List<ScanResult> resultados) {
    if (!mounted) return;
    _contadorLecturas++;
 
    // Decaimiento suave: si un beacon no aparece en este ciclo, su RSSI baja
    // gradualmente en lugar de caer a -100 de golpe. removeIfGone (4s) se
    // encarga de limpiar los que realmente desaparecen.
    final macsEnEsteCiclo = resultados.map((r) => r.device.remoteId.str).toSet();
    for (var beacon in _beaconsEnElMapa.values) {
      if (!macsEnEsteCiclo.contains(beacon.mac)) {
        beacon.rssiFiltrado = (beacon.rssiFiltrado - 2.0).clamp(-100.0, 0.0);
      }
    }
 
    for (var res in resultados) {
      try {
        String mac = res.device.remoteId.str;
        double? rssiSuave = _procesador.filtrarYPromediar(mac, res.rssi);
        if (rssiSuave != null && _beaconsEnElMapa.containsKey(mac)) {
          _beaconsEnElMapa[mac]!.rssiFiltrado = rssiSuave;
        }
      } catch (e) {
        // Ignorar
      }
    }
 
    if (_contadorLecturas % 10 == 0 && mounted) {
      final activos = _beaconsEnElMapa.values.where((b) => b.rssiFiltrado > _umbralRSSI).length;
      setState(() => _estadoScan = 'Beacons detectados: $activos / ${_beaconsEnElMapa.length}');
    }

    // Throttle: no ejecutar el pipeline de posicionamiento más de una vez
    // cada _intervaloPosicionamiento. BLE puede disparar mucho más rápido que eso.
    final ahora = DateTime.now();
    if (_ultimoPosicionamiento != null &&
        ahora.difference(_ultimoPosicionamiento!) < _intervaloPosicionamiento) {
      return;
    }
    _ultimoPosicionamiento = ahora;

    _calcularPosicionRobusta();
  }
 
  void _calcularPosicionRobusta() {
    if (!mounted) return;
 
    try {
      var candidatos = _beaconsEnElMapa.values
          .where((b) => b.rssiFiltrado > _umbralRSSI)
          .toList();
 
      if (candidatos.length < _minBeaconsActivos) {
        if (mounted) {
          setState(() => _estadoScan = 'Beacons cercanos: ${candidatos.length} (necesitamos $_minBeaconsActivos)');
        }
        return;
      }
 
      // Orden: primero por RSSI (más cercano) DESC, y entre beacons de fuerza
      // similar, por varianza (más estable) ASC. Cuantizamos el RSSI a bandas
      // de _umbralRssiSimilar dBm para que el desempate por varianza se active
      // realmente con valores filtrados continuos y para mantener el orden
      // transitivo (un comparador con epsilon directo no lo sería).
      candidatos.sort((a, b) {
        final bandaA = (a.rssiFiltrado / _umbralRssiSimilar).round();
        final bandaB = (b.rssiFiltrado / _umbralRssiSimilar).round();
        if (bandaA != bandaB) return bandaB.compareTo(bandaA); // RSSI DESC
        return _procesador
            .varianzaBeacon(a.mac)
            .compareTo(_procesador.varianzaBeacon(b.mac)); // varianza ASC
      });
      final activos = candidatos.take(_maxBeaconsParaCalcular).toList();
 
      // MULTILATERACIÓN por mínimos cuadrados (reemplaza al centroide ponderado
      // 1/d²). El centroide era un promedio de las POSICIONES de los beacons:
      // andaba bien pegado a un beacon (ese beacon dominaba el peso) pero
      // COLAPSABA al centro del layout cuando el usuario estaba en el medio,
      // equidistante de varios. La multilateración usa las distancias como
      // restricciones geométricas (circunferencias) y sí puede ubicar al
      // usuario en cualquier parte del plano. Ver [Posicionador] para el detalle
      // y las mediciones. Se sigue usando el txPower CALIBRADO por beacon.
      final observaciones = <ObservacionRango>[];
      for (var b in activos) {
        final txPower = ProcesadorSenal.txPowerCalibrado(b.mac, _calibraciones);
        final d = ProcesadorSenal.rssiADistanciaConTx(b.rssiFiltrado, txPower);
        // Beacon más cercano = rango más confiable: el error en metros del
        // modelo log crece con la distancia, así que pesa menos lo lejano.
        final confianza = 1.0 / (d + 1.0);
        observaciones.add(ObservacionRango(b.posicion, d, confianza));
      }
      if (observaciones.isEmpty) return;

      // El factor de movimiento (acelerómetro) se lee ANTES de estimar porque
      // gobierna el ancla temporal del posicionador, la puerta direccional y la
      // ventana de mediana del RSSI.
      _factorMovimiento = _movimiento.factorMovimiento;

      // Δt REAL entre muestras: el scan BLE no entrega a ritmo constante.
      // Se calcula ACÁ ARRIBA (antes se calculaba después de estimar) porque
      // ahora también lo necesita la puerta direccional, que convierte el
      // desplazamiento del ciclo en una velocidad en m/s.
      final ahoraMuestra = DateTime.now();
      final dt = _ultimaMuestraPos == null
          ? 0.0
          : ahoraMuestra.difference(_ultimaMuestraPos!).inMicroseconds / 1e6;
      _ultimaMuestraPos = ahoraMuestra;

      // ── ¿SE PUEDE USAR EL RUMBO PARA RESTRINGIR EL MOVIMIENTO? ───────────
      //
      // Tres condiciones, y las tres importan:
      //
      //  1. Hay brújula y ya entregó un heading.
      //
      //  2. El heading es ESTABLE ([OrientacionService.calidadRumbo]). En
      //     interiores el campo magnético está distorsionado por estructura
      //     metálica, ascensores y tableros. Un heading basura no "restringe"
      //     el movimiento: clava la posición sobre un eje EQUIVOCADO, que es
      //     peor que no restringir nada. Esta condición no existía antes y es
      //     una de las razones por las que el sistema andaba de forma errática:
      //     bastaba pasar cerca de una columna con hierro para que el eje
      //     privilegiado se fuera 40° y la posición quedara trabada de costado.
      //
      //  3. Hay acelerómetro. Sin él, [DetectorMovimiento] devuelve un factor
      //     fijo de 0.45 y no se puede distinguir "caminando" de "parado".
      //     "Dirección de marcha" de alguien que quizás no está marchando no
      //     significa nada, así que se prefiere el ancla isotrópica.
      //
      // El rumbo se lleva al marco del PLANO (se descuenta la rotación del
      // mapa, igual que en _buildOrientacion) y se expresa como versor en
      // coordenadas normalizadas de pantalla (x→derecha, y→abajo):
      //   rumbo 0° = arriba en pantalla = (0, -1).
      Offset? rumboPlano;
      if (_compassDisponible &&
          _movimiento.disponible &&
          _orientacion.calidadRumbo >= _calidadRumboMinima) {
        final h = _orientacion.heading;
        if (h != null) {
          final hp = ((h - _rotacionMapaEfectiva) % 360 + 360) % 360;
          final rad = hp * pi / 180.0;
          rumboPlano = Offset(sin(rad), -cos(rad));
        }
      }

      // Multilateración RECURSIVA: se le pasa la posición filtrada previa
      // como ancla temporal y arranque en caliente. Eso mata los saltos
      // (un outlier de un frame ya no la mueve) y estabiliza geometrías
      // malas, sin reintroducir el sesgo al centro. El rumbo sólo SESGA acá
      // (ver el comentario de _factorPerpMax en Posicionador); la decisión
      // dura la toma la puerta de abajo.
      var nuevaPosicionRaw = Posicionador.estimar(
        observaciones,
        metrosX: _grilla.metrosX,
        metrosY: _grilla.metrosY,
        posPrevia: _posicionFiltrada,
        factorMovimiento: _factorMovimiento,
        rumboPlano: rumboPlano,
      );

      // ── PUERTA DIRECCIONAL ───────────────────────────────────────────────
      // Descompone el desplazamiento propuesto en "a lo largo del rumbo" y
      // "perpendicular", y deja pasar el lateral sólo si viene sostenido en el
      // mismo sentido durante ~1 s (ver [PuertaRumbo]). El ruido BLE alterna
      // de signo ciclo a ciclo, así que nunca junta esa evidencia; una persona
      // que se corre de verdad hacia el costado, sí.
      if (rumboPlano != null && _posicionFiltrada != null) {
        nuevaPosicionRaw = _puertaRumbo.aplicar(
          posPrevia: _posicionFiltrada!,
          candidata: nuevaPosicionRaw,
          rumboPlano: rumboPlano,
          metrosX: _grilla.metrosX,
          metrosY: _grilla.metrosY,
          factorMovimiento: _factorMovimiento,
          dt: dt,
          velocidadAngularGrados: _orientacion.velocidadAngularGrados,
        );
      } else {
        // Sin rumbo confiable la puerta no debe conservar evidencia vieja: al
        // volver a haber brújula, esa evidencia pertenecería a otro eje.
        _puertaRumbo.resetear();
      }

      // ── FILTRO ONE EURO GOBERNADO POR EL ACELERÓMETRO ────────────────────
      //
      // La ventana de mediana del RSSI también se acorta al caminar: es la
      // mayor fuente de latencia de todo el pipeline (3 s de ventana ≈ 1.5 s
      // de retardo de grupo, ~1.8 m a paso normal).
      _procesador.ajustarPorMovimiento(_factorMovimiento);

      final filtrada = _filtroPosicion.filtrar(
        nuevaPosicionRaw,
        dt: dt,
        factorMovimiento: _factorMovimiento,
      );

      Offset nuevaPosicionFiltrada;
      if (_posicionFiltrada == null) {
        nuevaPosicionFiltrada = filtrada;
      } else {
        // ── TOPE DE PASO POR CICLO, EN METROS Y ANISOTRÓPICO ───────────────
        // Es la última defensa anti-spike, por debajo de la puerta. Antes era
        // isotrópico y en unidades normalizadas, así que "deshacía" parte de la
        // anisotropía que el rumbo había logrado más arriba: un pico lateral
        // que el solver había frenado seguía teniendo permiso de moverse tanto
        // de costado como hacia adelante.
        final dtPaso =
            (dt.isFinite && dt > 0) ? dt.clamp(0.05, 1.0) : 0.18;
        final velMax = _velMaxQuietoMs +
            (_velMaxMoviendoMs - _velMaxQuietoMs) * _factorMovimiento;
        final topeAlong = velMax * dtPaso;

        double dxM = (filtrada.dx - _posicionFiltrada!.dx) * _grilla.metrosX;
        double dyM = (filtrada.dy - _posicionFiltrada!.dy) * _grilla.metrosY;

        if (rumboPlano != null) {
          // Versor del rumbo en marco métrico (mx≠my ⇒ hay que renormalizar).
          double hx = rumboPlano.dx * _grilla.metrosX;
          double hy = rumboPlano.dy * _grilla.metrosY;
          final hn = sqrt(hx * hx + hy * hy);
          if (hn > 1e-6) {
            hx /= hn;
            hy /= hn;
            final nx = -hy, ny = hx;
            final topePerp = topeAlong *
                (1.0 + (_facTopePerp - 1.0) * _factorMovimiento);
            final a = (dxM * hx + dyM * hy).clamp(-topeAlong, topeAlong);
            final l = (dxM * nx + dyM * ny).clamp(-topePerp, topePerp);
            dxM = a * hx + l * nx;
            dyM = a * hy + l * ny;
          }
        } else {
          final dm = sqrt(dxM * dxM + dyM * dyM);
          if (dm > topeAlong) {
            final s = topeAlong / dm;
            dxM *= s;
            dyM *= s;
          }
        }

        nuevaPosicionFiltrada = Offset(
          _posicionFiltrada!.dx + dxM / _grilla.metrosX,
          _posicionFiltrada!.dy + dyM / _grilla.metrosY,
        );

        // Zona muerta con el usuario detenido: por debajo de este
        // desplazamiento no se mueve nada. Es lo que termina de eliminar el
        // parpadeo del ícono cuando la persona está parada. Se desactiva de
        // forma progresiva apenas el acelerómetro detecta movimiento.
        if (_factorMovimiento < 0.25) {
          final movMetros =
              _distanciaMetros(_posicionFiltrada!, nuevaPosicionFiltrada);
          if (movMetros < _zonaMuertaQuietoMetros) {
            nuevaPosicionFiltrada = _posicionFiltrada!;
          }
        }
      }
      _posicionFiltrada = nuevaPosicionFiltrada;

      // BUG ARQUITECTONICO (causaba TANTO el congelamiento como los saltos de
      // 10 m -- son el mismo defecto visto en dos momentos distintos):
      //
      // Antes, para "confirmar" una posicion nueva se exigian 5 ciclos
      // CONSECUTIVOS con delta de EMA < 1.25 m, y recien ahi _posicionConfirmada
      // saltaba DIRECTO al valor del EMA en ese instante (sin interpolar desde
      // el valor viejo). El EMA esta clampeado a 2 m/ciclo -- con ruido BLE
      // moderado, es comun que se mueva entre 1.25 m y 2 m por ciclo de forma
      // sostenida: siempre por encima del umbral de "estable", asi que los 5
      // ciclos seguidos nunca se juntaban y la posicion quedaba congelada. Y
      // cuando por fin habia 5 ciclos tranquilos, el salto directo al EMA
      // actual podia ser de hasta 5 ciclos x 2 m = 10 m si venia congelada
      // mientras la persona caminaba. Mismo bug, dos sintomas.
      //
      // FIX: la posicion filtrada (con su propio clamp de paso maximo por
      // ciclo, que YA evita saltos bruscos por spikes de RSSI) alimenta la
      // posicion directamente, todos los ciclos. Sin gate extra encima. Esto
      // da seguimiento continuo y en tiempo real.
      //
      // NOTA: aquel gate era un intento de resolver por fuerza bruta lo que
      // ahora resuelve el filtro adaptativo. Un umbral fijo de "estabilidad"
      // no puede distinguir ruido de movimiento real porque en BLE ambos
      // tienen la misma amplitud; el acelerometro si puede, y por eso el
      // criterio de cuanto suavizar salio del propio pipeline BLE.
      final nuevaPosicionFinal = nuevaPosicionFiltrada;

      {
        final bool primeraUbicacion = _posicionFinal == null;

        // Mantener SIEMPRE la posicion mas reciente para que el pathfinder y la
        // voz usen el valor actual, pero desacoplar el rebuild de la UI del
        // ritmo del scan BLE: refrescar como mucho cada _intervaloRefrescoUI.
        // Sin este throttle el callback de scan dispara decenas de setState por
        // segundo y, durante la navegacion, el repintado del mapa + ruta satura
        // el hilo de UI y la pantalla se congela.
        //
        // Histeresis de celda: SOLO filtra el parpadeo de un unico ciclo
        // ruidoso justo en el borde entre dos celdas (2 ciclos ~ 0.36 s). No es
        // un gate de velocidad: si la posicion real cambia de celda de forma
        // sostenida, confirma casi de inmediato.
        final ix = _grilla.indiceX(nuevaPosicionFinal.dx);
        final iy = _grilla.indiceY(nuevaPosicionFinal.dy);
        // Histéresis de celda adaptativa: parado exige más confirmaciones
        // (nada debería cambiar de celda), caminando confirma casi de
        // inmediato para no agregar latencia sobre el filtro.
        final ciclosConfirmar = _factorMovimiento > 0.5 ? 1 : 3;
        final celdaFirme =
            _histeresisCelda.actualizar(ix, iy, _grilla, ciclosConfirmar);
        final posicionSnap = celdaFirme != null
            ? Offset(_grilla.centroX(celdaFirme.ix), _grilla.centroY(celdaFirme.iy))
            : nuevaPosicionFinal;
        _posicionFinal = posicionSnap;

        final ahora = DateTime.now();
        final bool debeRefrescarUI = primeraUbicacion ||
            _ultimoRefrescoUI == null ||
            ahora.difference(_ultimoRefrescoUI!) > _intervaloRefrescoUI;
        if (mounted && debeRefrescarUI) {
          _ultimoRefrescoUI = ahora;
          setState(() {
            final modo = !_movimiento.disponible
                ? ''
                : (_factorMovimiento > 0.5 ? ' · en movimiento' : ' · quieto');
            _estadoScan = 'Ubicacion estable (${activos.length} beacons)$modo';
          });
        }

        // Actualizar la instruccion de voz aca (no en build()) para que hablar()
        // no sea un efecto colateral del repintado del widget.
        _actualizarInstruccionVoz();

        // Anunciar cuando se obtiene la primera ubicacion estable.
        // hablarSinEsperar para NO bloquear el loop de posicionamiento BLE.
        if (primeraUbicacion) {
          _voz.hablarSinEsperar('Ubicación lista.');
        }
      }
 
      if (_destinoSeleccionado != null && _posicionFinal != null) {
        final ahora = DateTime.now();
        final debeRecalcular = _ultimaPosicionRuta == null ||
            (_posicionFinal! - _ultimaPosicionRuta!).distance > _umbralRecalcularRuta;
        // Cooldown: si el último intento de ruta falló (null), no reintentar
        // antes de _cooldownRuta para no saturar con compute() isolates.
        final fueraDeCooldown = _ultimoIntentoRuta == null ||
            ahora.difference(_ultimoIntentoRuta!) >= _cooldownRuta;

        if (debeRecalcular && fueraDeCooldown) {
          _ultimaPosicionRuta = _posicionFinal;
          _ultimoIntentoRuta = ahora;
          _calcularRuta();
        }
      }
    } catch (e) {
      // Antes esto se ignoraba en silencio. Si algo del pipeline de
      // posicionamiento (trilateración, EMA, histéresis de celda) tira una
      // excepción en un ciclo, ahora al menos queda logueado: sin esto era
      // imposible distinguir "no llegan datos BLE" de "llegan pero el cálculo
      // explota siempre" — ambos se ven igual desde la UI (ícono congelado).
      debugPrint('[Posicionamiento] Error en _calcularPosicionRobusta: $e');
    }
  }
 
  /// Distancia real (m) entre dos posiciones normalizadas, usando la escala
  /// del piso en cada eje. Los ejes pueden tener escalas muy distintas, así
  /// que una distancia en unidades normalizadas no es comparable entre planos.
  double _distanciaMetros(Offset a, Offset b) {
    final dx = (a.dx - b.dx) * _grilla.metrosX;
    final dy = (a.dy - b.dy) * _grilla.metrosY;
    return sqrt(dx * dx + dy * dy);
  }

  Future<void> _calcularRuta() async {
    if (_posicionFinal == null || _destinoSeleccionado == null) {
      debugPrint('[Ruta] _calcularRuta abortada: posicionFinal o destino null.');
      return;
    }
    if (_calculandoRuta) {
      debugPrint('[Ruta] _calcularRuta abortada: ya hay un cálculo en curso (_calculandoRuta=true).');
      return;
    }
    if (!_resolvedorListo) {
      debugPrint('[Ruta] _calcularRuta abortada: _resolvedorListo=false.');
      return;
    }

    _calculandoRuta = true;
    debugPrint('[Ruta] Iniciando cálculo hacia "${_destinoSeleccionado!.nombre}"...');
    try {
      // Clampear la posición a [0, 1) en ambos ejes antes de pasarla al
      // pathfinder. La trilateración puede devolver valores ligeramente fuera
      // de [0, 1] cuando el usuario está cerca del borde del mapa; el
      // _aStarIsolate los clampea con clampX/clampY, pero si esa celda de
      // borde es un obstáculo, _celdaLibreCercana puede no encontrar alternativa
      // y retornar null, haciendo que la ruta nunca aparezca.
      final origen = Offset(
        _posicionFinal!.dx.clamp(0.001, 0.999),
        _posicionFinal!.dy.clamp(0.001, 0.999),
      );
      final destino = Offset(
        _destinoSeleccionado!.posicion.dx.clamp(0.001, 0.999),
        _destinoSeleccionado!.posicion.dy.clamp(0.001, 0.999),
      );

      final camino = await _resolvedor.encontrarCamino(origen, destino);

      if (!mounted) return;
      setState(() {
        _rutaActual = camino;
        if (camino == null) {
          _estadoRuta = 'No se encontró ruta disponible';
          // Resetear para que el pathfinder reintente cuando el usuario se mueva
          // a una celda diferente. El cooldown (_cooldownRuta) evita que cada
          // callback BLE dispare un nuevo compute() durante el período de espera.
          _ultimaPosicionRuta = null;
        } else {
          final distancia = _calcularDistancia(camino);
          _estadoRuta = 'Ruta a ${_destinoSeleccionado!.nombre}: ${distancia.toStringAsFixed(1)}m';
        }
      });
    } catch (e) {
      // BUG ORIGINAL: este catch no hacía nada. Si encontrarCamino() (el A*
      // que corre en un isolate vía compute()) tiraba cualquier excepción,
      // _estadoRuta se quedaba pegado en "Calculando ruta..." para siempre:
      // no se actualizaba el texto, y como _ultimaPosicionRuta tampoco se
      // reseteaba, el gate de recálculo en _calcularPosicionRobusta jamás
      // volvía a intentarlo. Resultado: "queda siempre pensando".
      debugPrint('[Pathfinder] Error calculando ruta: $e');
      if (mounted) {
        setState(() {
          _estadoRuta = 'Error calculando ruta. Reintentando...';
        });
      }
      // Permitir que el próximo ciclo de posicionamiento reintente en vez de
      // quedar bloqueado por el gate de "posición sin cambios".
      _ultimaPosicionRuta = null;
    } finally {
      _calculandoRuta = false;
    }
  }
 
  double _calcularDistancia(List<Offset> camino) {
    // El camino es una secuencia de celdas adyacentes (1 celda ≈ 1 m real en
    // ambos ejes), así que la distancia ≈ cantidad de pasos × tamaño de celda.
    if (camino.length < 2) return 0;
    return (camino.length - 1) * _grilla.tamCeldaMetros;
  }
 
  // ─── SELECCIÓN DE DESTINO POR VOZ ─────────────────────────────────────────
 
  /// Activa el micrófono, escucha el destino y busca la mejor coincidencia.
  Future<void> _seleccionarDestinoPorVoz() async {
    if (_lugares.isEmpty) {
      await _voz.hablar('No hay lugares configurados.');
      return;
    }
 
    // Primero hablar y esperar que termine el audio (hablar() ya usa el
    // callback real del motor TTS + margen de 600ms). Añadimos 200ms extra
    // por si el altavoz del dispositivo tiene latencia de apagado alta.
    await _voz.hablar('¿A dónde vas?');
    await Future.delayed(const Duration(milliseconds: 200));
 
    // Solo ahora activar el indicador visual de escucha
    if (!mounted) return;
    setState(() => _escuchando = true);
 
    await _voz.escuchar(
      timeout: const Duration(seconds: 8),
      onEscuchando: (activo) {
        if (mounted) setState(() => _escuchando = activo);
      },
      onResultado: (textoReconocido) async {
        if (!mounted) return;
        setState(() => _escuchando = false);
 
        final destino = _buscarMejorCoincidencia(textoReconocido);
 
        if (destino != null) {
          setState(() {
            _destinoSeleccionado = destino;
            _rutaActual = null;
            _estadoRuta = 'Calculando ruta...';
            _ultimaPosicionRuta = null;
          });
          _calcularRuta();
          await _voz.hablar('${destino.nombre}. Calculando ruta.');
        } else {
          await _voz.hablar('No encontré "$textoReconocido". Intentá de nuevo.');
        }
      },
      onError: (error) async {
        if (mounted) setState(() => _escuchando = false);
        await _voz.hablar('No te escuché. Intentá de nuevo.');
      },
    );
  }
 
  /// Busca el lugar cuyo nombre tenga mayor similitud con el texto reconocido.
  LugarInteres? _buscarMejorCoincidencia(String texto) {
    final textoNorm = _normalizar(texto);
 
    // Búsqueda exacta primero
    for (final lugar in _lugares) {
      if (_normalizar(lugar.nombre) == textoNorm) return lugar;
    }
 
    // Búsqueda por contención
    for (final lugar in _lugares) {
      final nombreNorm = _normalizar(lugar.nombre);
      if (nombreNorm.contains(textoNorm) || textoNorm.contains(nombreNorm)) {
        return lugar;
      }
    }
 
    // Búsqueda por palabras individuales
    final palabras = textoNorm.split(' ').where((p) => p.length > 2).toList();
    LugarInteres? mejorCandidato;
    int mejorPuntaje = 0;
 
    for (final lugar in _lugares) {
      final nombreNorm = _normalizar(lugar.nombre);
      int puntaje = 0;
      for (final palabra in palabras) {
        if (nombreNorm.contains(palabra)) puntaje++;
      }
      if (puntaje > mejorPuntaje) {
        mejorPuntaje = puntaje;
        mejorCandidato = lugar;
      }
    }
 
    return mejorPuntaje > 0 ? mejorCandidato : null;
  }
 
  String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim();
  }
 
  // ─── SELECCIÓN DE DESTINO POR LISTA (fallback táctil) ─────────────────────
 
  void _seleccionarDestinoLista() async {
    if (_lugares.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay lugares de interes configurados')),
        );
      }
      return;
    }
 
    // La lista se muestra visualmente; no leer todos los nombres por voz
 
    final seleccion = await showDialog<LugarInteres>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿A dónde querés ir?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _lugares.length,
            itemBuilder: (context, i) {
              final l = _lugares[i];
              return ListTile(
                leading: const Icon(Icons.place, color: Colors.purple),
                title: Text(l.nombre, style: const TextStyle(fontSize: 18)),
                subtitle: l.descripcion != null ? Text(l.descripcion!) : null,
                onTap: () => Navigator.pop(ctx, l),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
 
    if (seleccion != null && mounted) {
      setState(() {
        _destinoSeleccionado = seleccion;
        _rutaActual = null;
        _estadoRuta = 'Calculando ruta...';
        _ultimaPosicionRuta = null;
      });
      _calcularRuta();
      await _voz.hablar('${seleccion.nombre}. Calculando ruta.');
    }
  }
 
  void _cancelarNavegacion() {
    if (mounted) {
      setState(() {
        _destinoSeleccionado = null;
        _rutaActual = null;
        _estadoRuta = '';
        _ultimaPosicionRuta = null;
      });
      _voz.hablar('Navegación cancelada.');
    }
  }

  /// Punto de entrada accesible: tocar CUALQUIER parte de la pantalla inicia la
  /// selección de destino por voz. Pensado para personas ciegas: no hay que
  /// buscar un botón chico. Los controles con su propio onTap (lista, cancelar,
  /// barra de micrófono) siguen funcionando porque capturan el toque primero;
  /// el zoom/desplazamiento del mapa está desactivado, así que el toque siempre
  /// llega. Si ya se estaba escuchando (o el estado quedó trabado), el toque lo
  /// detiene para poder reintentar sin quedar bloqueado.
  void _iniciarSeleccionDestinoPorPantalla() {
    if (_escuchando) {
      _voz.detenerEscucha();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    _seleccionarDestinoPorVoz();
  }
 
  // ─── INSTRUCCIONES POR VOZ (OUTPUT) ───────────────────────────────────────
 
  /// Habla la indicación actual solo si cambió o pasó el tiempo mínimo.
  void _hablarInstruccionActual(String instruccion) {
    _voz.hablarSiCambio(instruccion);
  }

  /// Calcula la indicación de giro actual y la pasa al filtro de voz.
  /// Se invoca desde el loop de posicionamiento (NO desde build()) para que
  /// hablar() no sea un efecto colateral del repintado del widget y para que
  /// el filtro de confirmaciones de VozService reciba un ritmo estable.
  void _actualizarInstruccionVoz() {
    final heading = _orientacion.heading;
    if (heading == null || _posicionFinal == null || _destinoSeleccionado == null) {
      return;
    }
    final indicacion = OrientacionService.calcularIndicacion(
      headingUsuario: heading,
      posicionUsuario: _posicionFinal!,
      posicionDestino: _objetivoNavegacion(),
      rotacionMapa: _rotacionMapaEfectiva,
      metrosX: widget.escalaX,
      metrosY: widget.escalaY,
    );
    final distMetros = (indicacion.distanciaMetros / 5).round() * 5;
    _hablarInstruccionActual('${indicacion.instruccion}, $distMetros metros');
  }

  /// Punto al que deben apuntar las instrucciones: la próxima esquina del camino
  /// pintado (sigue las cuadrículas). Si todavía no hay ruta, el destino directo.
  Offset _objetivoNavegacion() {
    if (_rutaActual != null && _rutaActual!.isNotEmpty && _posicionFinal != null) {
      return OrientacionService.proximoObjetivo(_rutaActual!, _posicionFinal!);
    }
    return _destinoSeleccionado!.posicion;
  }
 
  // ─── WIDGETS ──────────────────────────────────────────────────────────────
 
  Widget _buildOrientacion() {
    // Si la brújula no está disponible, mostrar mensaje informativo en lugar
    // de ocultar silenciosamente el widget (el TTS ya lo anunció en _iniciarBrujula).
    if (!_compassDisponible) {
      return Semantics(
        label: 'Brújula no disponible. Las instrucciones de giro pueden ser menos precisas.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: TemaApp.fondoAdvertencia,
            borderRadius: BorderRadius.circular(TemaApp.radiusChip),
            border: Border.all(color: TemaApp.advertencia.withValues(alpha: 0.6), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.compass_calibration, color: TemaApp.advertencia, size: 20),
              const SizedBox(width: 6),
              Text(
                'Brújula no disponible',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: TemaApp.advertencia,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final headingRaw = _orientacion.heading;
    if (headingRaw == null) return const SizedBox.shrink();

    // _buildOrientacion muestra la dirección del dispositivo relativa al plano:
    // restamos rotacionMapa para que "arriba en pantalla" sea el Norte del plano.
    // Este valor compensado es el correcto para el icono y la etiqueta de texto,
    // NO para calcularIndicacion() (que recibe el heading crudo de la brújula).
    final heading = ((headingRaw - _rotacionMapaEfectiva) % 360 + 360) % 360;

    final direccion = OrientacionService.direccionCardinal(heading);

    // Item 2: Semantics con label descriptivo para TalkBack/VoiceOver.
    return Semantics(
      label: 'Orientación: $direccion, ${heading.toStringAsFixed(0)} grados',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: TemaApp.acentoSuave,
          borderRadius: BorderRadius.circular(TemaApp.radiusChip),
          border: Border.all(color: TemaApp.acento.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bug 3 fix: usar siempre Icons.navigation (flecha arriba) y rotar
            // heading/360 en sentido HORARIO (positivo). Antes se usaba -heading
            // (antihorario) + ícono variable, que daba dirección opuesta/aleatoria.
            AnimatedRotation(
              turns: heading / 360,
              duration: const Duration(milliseconds: 250),
              // Item 9: ícono de brújula 28 px.
              child: const Icon(Icons.navigation, color: TemaApp.acento, size: 24),
            ),
            const SizedBox(width: 6),
            Text(
              direccion,
              style: const TextStyle(
                // Item 9: texto de dirección 18 sp.
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: TemaApp.acento,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${heading.toStringAsFixed(0)}°',
              style: const TextStyle(
                // Item 9: grados 16 sp (piso absoluto).
                fontSize: 13,
                color: TemaApp.textoSecundario,
              ),
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _buildIndicacionGiro() {
    final heading = _orientacion.heading;
    if (heading == null || _posicionFinal == null || _destinoSeleccionado == null) {
      return const SizedBox.shrink();
    }
 
    final indicacion = OrientacionService.calcularIndicacion(
      headingUsuario: heading,
      posicionUsuario: _posicionFinal!,
      posicionDestino: _objetivoNavegacion(),
      rotacionMapa: _rotacionMapaEfectiva,
      metrosX: widget.escalaX,
      metrosY: widget.escalaY,
    );

    // La instrucción por voz se dispara en _actualizarInstruccionVoz() desde el
    // loop de posicionamiento, no acá: build() debe ser libre de efectos.

    // Item 2: Semantics con descripción completa para lectores de pantalla.
    return Semantics(
      label: '${indicacion.instruccion}, ${indicacion.distanciaMetros.toStringAsFixed(0)} metros',
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: TemaApp.instruccion,
          borderRadius: BorderRadius.circular(TemaApp.radiusCard),
          border: Border.all(color: TemaApp.instruccionAccent.withValues(alpha: 0.4), width: 1),
          boxShadow: [
            BoxShadow(
              color: TemaApp.instruccionAccent.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: TemaApp.instruccionAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                indicacion.instruccion == 'Seguí derecho'
                    ? Icons.arrow_upward_rounded
                    : indicacion.instruccion == 'Date la vuelta'
                        ? Icons.u_turn_left_rounded
                        : indicacion.giroNecesario > 0
                            ? Icons.turn_right_rounded
                            : Icons.turn_left_rounded,
                color: TemaApp.instruccionAccent,
                size: 36,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    indicacion.instruccion,
                    style: const TextStyle(
                      color: TemaApp.textoBlanco,
                      fontSize: TemaApp.spInstruccion,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${indicacion.distanciaMetros.toStringAsFixed(0)} metros',
                    style: TextStyle(
                      color: TemaApp.instruccionAccent.withValues(alpha: 0.85),
                      fontSize: TemaApp.spDistancia,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _buildBarraMicrofono() {
    final bool escuchando = _escuchando;
    return Semantics(
      label: escuchando ? 'Escuchando, hablá ahora' : 'Tocá aquí y decí el destino',
      button: true,
      child: GestureDetector(
        onTap: escuchando ? null : _seleccionarDestinoPorVoz,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: double.infinity,
          height: 100,
          decoration: BoxDecoration(
            color: escuchando
                ? const Color(0xFF1A0A00)
                : TemaApp.fondoCard,
            border: Border(
              top: BorderSide(
                color: escuchando ? TemaApp.advertencia : TemaApp.acento,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: escuchando
                      ? TemaApp.advertencia.withValues(alpha: 0.15)
                      : TemaApp.acento.withValues(alpha: 0.12),
                  border: Border.all(
                    color: escuchando ? TemaApp.advertencia : TemaApp.acento,
                    width: 2,
                  ),
                ),
                child: Icon(
                  escuchando ? Icons.hearing_rounded : Icons.mic_rounded,
                  color: escuchando ? TemaApp.advertencia : TemaApp.acento,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    escuchando ? 'Escuchando...' : 'TOCÁ Y HABLÁ',
                    style: TextStyle(
                      color: escuchando ? TemaApp.advertencia : TemaApp.acento,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    escuchando ? 'Decí el nombre del lugar' : 'Tocá en cualquier parte de la pantalla',
                    style: const TextStyle(color: TemaApp.textoSecundario, fontSize: 14),
                  ),
                ],
              ),
              if (escuchando) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: TemaApp.advertencia,
                    strokeWidth: 2.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(
          backgroundColor: TemaApp.fondoCard,
          foregroundColor: TemaApp.textoBlanco,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFF21262D)),
          ),
          title: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: TemaApp.acento,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: TemaApp.acento.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 1)],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _nombrePiso ?? 'Navegación',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: TemaApp.textoBlanco),
              ),
            ],
          ),
          actions: [
            if (_destinoSeleccionado != null)
              Semantics(
                label: 'Cancelar navegación',
                button: true,
                child: SizedBox(
                  width: TemaApp.targetTactil,
                  height: TemaApp.targetTactil,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: TemaApp.textoSecundario),
                    tooltip: 'Cancelar navegación',
                    onPressed: _cancelarNavegacion,
                  ),
                ),
              ),
          ],
        ),

        body: Semantics(
          label: 'Tocá en cualquier parte de la pantalla para elegir tu destino por voz',
          explicitChildNodes: true,
          child: GestureDetector(
            // Toque en cualquier parte → selección de destino por voz.
            // translucent deja pasar los eventos a los hijos (mapa, botones,
            // barra de micrófono), que capturan sus propios toques y gestos.
            behavior: HitTestBehavior.translucent,
            onTap: _iniciarSeleccionDestinoPorPantalla,
            child: Column(
              children: [
            // Panel de destino + brújula
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: TemaApp.fondoCard,
                border: const Border(bottom: BorderSide(color: Color(0xFF21262D))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _destinoSeleccionado != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.place_rounded, color: TemaApp.poi, size: 20),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _destinoSeleccionado!.nombre,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 17,
                                        color: TemaApp.textoBlanco,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (_estadoRuta.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2, left: 26),
                                  child: Text(
                                    _estadoRuta,
                                    style: const TextStyle(fontSize: 13, color: TemaApp.textoSecundario),
                                  ),
                                ),
                            ],
                          )
                        : Text(
                            'Tocá la pantalla para elegir destino',
                            style: TextStyle(fontSize: 15, color: TemaApp.textoSecundario),
                          ),
                  ),
                  const SizedBox(width: 8),
                  _buildOrientacion(),
                  Semantics(
                    label: _destinoSeleccionado != null ? 'Cambiar destino' : 'Seleccionar destino desde lista',
                    button: true,
                    child: SizedBox(
                      width: TemaApp.targetTactil,
                      height: TemaApp.targetTactil,
                      child: IconButton(
                        icon: Icon(
                          _destinoSeleccionado != null ? Icons.edit_location_alt_rounded : Icons.format_list_bulleted_rounded,
                          color: TemaApp.acento,
                          size: 28,
                        ),
                        tooltip: 'Seleccionar destino desde lista',
                        onPressed: _seleccionarDestinoLista,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Indicacion de giro
            if (_destinoSeleccionado != null) _buildIndicacionGiro(),

            // Banner buscando ubicación
            if (_posicionFinal == null && _escaneando)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: TemaApp.acentoSuave,
                child: Row(
                  children: [
                    SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: TemaApp.acento,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Buscando tu ubicación...',
                      style: const TextStyle(fontSize: 15, color: TemaApp.acento, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

            // Mapa
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF21262D), width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                // Sin InteractiveViewer en navegación: la persona no manipula el
                // mapa, así el mapa no compite por los gestos y el toque en
                // cualquier parte de la pantalla siempre inicia la selección.
                child: MapaWidget(
                  rutaImagen: widget.rutaImagen,
                  beacons: _beaconsEnElMapa,
                  zonas: _zonas,
                  lugares: _lugares,
                  posicionUsuario: _posicionFinal,
                  modoEdicion: false,
                  mostrarGrilla: true,
                  grilla: _grilla,
                  ruta: _rutaActual,
                  headingUsuario: _orientacion.heading != null
                      ? ((_orientacion.heading! - _rotacionMapaEfectiva) % 360 + 360) % 360
                      : null,
                ),
              ),
            ),

            // Estado beacons colapsable
            Semantics(
              liveRegion: true,
              child: Theme(
                data: TemaApp.tema.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minTileHeight: 38,
                  leading: Icon(Icons.sensors_rounded, color: TemaApp.acento, size: 18),
                  title: Text(
                    _estadoScan,
                    style: const TextStyle(fontSize: 14, color: TemaApp.textoSecundario),
                  ),
                  children: [
                    if (_posicionFinal != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'Beacons activos: ${_beaconsEnElMapa.values.where((b) => b.rssiFiltrado > _umbralRSSI).length} / ${_beaconsEnElMapa.length} configurados',
                          style: const TextStyle(fontSize: 14, color: TemaApp.textoSecundario),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Barra de micrófono
            _buildBarraMicrofono(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Histéresis de celda para estabilizar el punto del usuario en la grilla.
///
/// Sin esto, cuando el usuario está cerca del borde entre dos celdas la posición
/// oscila entre ellas con cada lectura BLE, generando saltos en el mapa e
/// instrucciones de voz alternadas ("girá a la derecha" / "girá a la izquierda")
/// en segundos. Esta clase solo confirma una celda nueva tras
/// [ciclosParaConfirmar] lecturas consecutivas en ella, y mientras tanto mantiene
/// la celda anterior. (Nombre sin acento: los identificadores Dart son ASCII.)
class _HisteresisCelda {
  // Celda actualmente confirmada como posición del usuario.
  ({int ix, int iy})? _celdaConfirmada;

  // Conteo de lecturas consecutivas que proponen una celda distinta.
  int _ciclosEnCeldaNueva = 0;
  ({int ix, int iy})? _celdaCandidataActual;

  // Lecturas consecutivas en la misma celda candidata antes de confirmarla como
  // nueva posición. Reducido de 5 a 2 (~0.36 s a ~5.5 Hz): esta era la
  // TERCERA capa de espera apilada sobre el pipeline de posicionamiento (EMA
  // + gate de confirmación de ~5 ciclos ya filtran el ruido real antes de
  // llegar acá). Con 5 ciclos acá también, un solo movimiento del usuario
  // podía tardar >1.5 s extra en reflejarse en el mapa ENCIMA de la demora
  // del gate anterior — la suma de ambas es lo que hacía ver el ícono
  // congelado en movimiento continuo. 2 ciclos alcanza para filtrar el
  // parpadeo de un único frame ruidoso justo en el borde de una celda.
  static const int ciclosParaConfirmar = 2;

  /// Propone una nueva celda. Retorna la celda confirmada vigente.
  ///
  /// [grilla] queda disponible para futuras reglas dependientes del tamaño de
  /// celda (p. ej. histéresis variable); hoy la lógica es puramente por índice.
  ({int ix, int iy})? actualizar(int ix, int iy, GrillaNav grilla,
      [int? ciclosRequeridos]) {
    final requeridos = ciclosRequeridos ?? ciclosParaConfirmar;
    if (_celdaConfirmada == null) {
      _celdaConfirmada = (ix: ix, iy: iy);
      return _celdaConfirmada;
    }
    if (ix == _celdaConfirmada!.ix && iy == _celdaConfirmada!.iy) {
      // Sigue en la misma celda → resetear candidata.
      _ciclosEnCeldaNueva = 0;
      _celdaCandidataActual = null;
      return _celdaConfirmada;
    }
    // Celda distinta: ¿es la misma candidata que la lectura anterior?
    if (_celdaCandidataActual?.ix == ix && _celdaCandidataActual?.iy == iy) {
      _ciclosEnCeldaNueva++;
    } else {
      // Cambió de candidata → empezar a contar desde 1.
      _celdaCandidataActual = (ix: ix, iy: iy);
      _ciclosEnCeldaNueva = 1;
    }
    if (_ciclosEnCeldaNueva >= requeridos) {
      _celdaConfirmada = _celdaCandidataActual;
      _ciclosEnCeldaNueva = 0;
      _celdaCandidataActual = null;
    }
    return _celdaConfirmada;
  }

  void resetear() {
    _celdaConfirmada = null;
    _ciclosEnCeldaNueva = 0;
    _celdaCandidataActual = null;
  }
}