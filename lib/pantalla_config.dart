import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'rubros.dart';
import 'pantalla_rubros.dart';
import 'database.dart';
import 'procesador_senal.dart';
import 'posicionador.dart';
import 'mapa_widget.dart';
import 'bluetooth_helper.dart';
import 'grilla_nav.dart';
import 'asistente_trazo.dart';
import 'calibracion_model.dart';
import 'supabase_service.dart';
import 'tema.dart';

enum _ModoEdicion { beacons, zonas, lugares, escala, calibracion, brujula }

class PantallaConfiguracion extends StatefulWidget {
  final int pisoId;
  final String rutaImagen;
  final double escalaX;
  final double escalaY;

  /// Lado de celda de la grilla (m). Configurable por piso, rango 0.5–1.0.
  final double tamCeldaMetros;

  const PantallaConfiguracion({
    super.key,
    required this.pisoId,
    required this.rutaImagen,
    this.escalaX = GrillaNav.escalaPorDefecto,
    this.escalaY = GrillaNav.escalaPorDefecto,
    this.tamCeldaMetros = 1.0,
  });

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  final ProcesadorSenal _procesador = ProcesadorSenal();

  Map<String, BeaconMarcado> _beaconsEnElMapa = {};
  List<ZonaNoTransitable> _zonas = [];
  List<LugarInteres> _lugares = [];
  List<ScanResult> _dispositivosCercanos = [];
  ScanResult? _seleccionado;
  bool _escaneando = false;

  /// Filtro por nombre de la lista de dispositivos BLE (modo beacons). Vacío =
  /// sin filtro. Sirve para ver solo los beacons propios entre todo el tráfico
  /// Bluetooth del lugar (celulares, auriculares, relojes, etc.).
  String _filtroNombre = '';
  bool _publicando = false;
  String? _remoteIdPublicado;
  Offset? _posicionUsuario;

  _ModoEdicion _modo = _ModoEdicion.beacons;
  // NO 'final': se reasigna (no se muta in-place) en cada cambio para que
  // _MapaPainter.shouldRepaint (que compara listas por referencia) detecte
  // el cambio y repinte el polígono en construcción mientras se dibuja.
  List<Offset> _verticesEnCurso = [];

  // Calibración: celda seleccionada por el operador + registros guardados.
  ({int ix, int iy})? _celdaCalSeleccionada;
  List<CalibracionRegistro> _calibraciones = [];
  final TextEditingController _etiquetaCalCtrl = TextEditingController();

  // Escala configurable por eje + grilla derivada.
  late double _escalaX;
  late double _escalaY;
  late double _tamCelda;
  late GrillaNav _grilla;

  // Rotación de la brújula: grados que hay que sumar al heading del dispositivo
  // para que 0° coincida con el Norte real del plano. Se persiste en la DB.
  double _rotacionMapa = 0.0;

  // ── Brújula en vivo (solo activa en modo brujula) ─────────────────────────
  StreamSubscription<CompassEvent>? _compassConfigSub;
  double? _headingEnVivo; // heading crudo del sensor, sin compensar

  /// Error estimado del sensor según el sistema, en grados (en Android: 15 =
  /// alta, 30 = media, 45 = baja). Null = desconocida o "no confiable": el
  /// plugin no distingue esos dos casos.
  ///
  /// Importa porque un offset tomado con el magnetómetro sin calibrar absorbe
  /// su error: cuando el sistema lo recalibra solo, el rumbo se corre y el
  /// offset guardado queda mal.
  double? _precisionBrujula;

  /// Lecturas de la toma en curso de "Usar la dirección actual". Null = no
  /// hay toma en curso.
  List<double>? _tomaRumbo;

  /// Duración de la toma de "Usar la dirección actual".
  static const Duration _duracionTomaRumbo = Duration(seconds: 2);

  /// Consistencia mínima (longitud de la media circular) de las lecturas de
  /// la toma. 0.97 equivale a una dispersión de ~14°: más que eso es que el
  /// teléfono se movió.
  static const double _consistenciaMinTomaRumbo = 0.97;

  // ── Calibración de posición: toma continua de N muestras ─────────────────
  // Mientras el operador esté parado en la celda seleccionada, el sistema
  // acumula muestras BLE por beacon durante _duracionTomaSeg segundos y luego
  // promedía con la misma mediana truncada que el modo navegación.
  bool _tomandoMuestras = false;
  int _muestrasAcumuladas = 0;

  /// BUG CORREGIDO: antes la toma terminaba a los 30
  /// "ciclos de scan", con el comentario "~5 s a 6 Hz". Pero el scan corre con
  /// `continuousUpdates: true`, y ese callback NO dispara a 6 Hz: dispara cada
  /// vez que llega un lote de advertisements, que en un ambiente con trafico
  /// BLE son decenas por segundo. Por eso la toma terminaba en ~1 s en vez de
  /// los 5 s previstos, y con muchas menos muestras independientes de las que
  /// se creia. La duracion ahora se mide en TIEMPO REAL, que es lo unico que
  /// no depende del ambiente.
  DateTime? _inicioToma;

  /// Duracion de una calibracion comun. Alimenta el ajuste del modelo de rango.
  static const Duration _duracionCalibracion = Duration(seconds: 10);

  /// Duracion de un PUNTO CLAVE (fingerprint). Mas larga a proposito: el
  /// patron guardado se compara despues en vivo contra lecturas ruidosas, asi
  /// que cuanto mejor promediado este, mas confiable es el reconocimiento. A
  /// ~6 advertisements/s por beacon son ~150 muestras por beacon.
  static const Duration _duracionFingerprint = Duration(seconds: 25);

  /// Si la proxima toma se guarda como punto clave (fingerprint).
  bool _tomaEsFingerprint = false;

  /// Acumuladores de la MEDIA CIRCULAR del rumbo durante la toma.
  ///
  /// No se puede promediar grados directamente: el promedio aritmetico de 350 y
  /// 10 da 180 (exactamente el sentido opuesto) en vez de 0. Se acumulan seno y
  /// coseno y al final se hace atan2, que es la forma correcta de promediar
  /// angulos. Es el mismo criterio que usa OrientacionService.
  double _sumSenoRumbo = 0;
  double _sumCosRumbo = 0;
  int _muestrasRumbo = 0;

  /// Rumbo medio de la toma, o `null` si no hubo lecturas de brujula.
  double? get _rumboMedioToma {
    if (_muestrasRumbo == 0) return null;
    final a = atan2(_sumSenoRumbo / _muestrasRumbo, _sumCosRumbo / _muestrasRumbo);
    return (a * 180 / pi + 360) % 360;
  }

  Duration get _duracionTomaActual =>
      _tomaEsFingerprint ? _duracionFingerprint : _duracionCalibracion;

  /// Progreso de la toma en `[0,1]`, por tiempo transcurrido.
  double get _progresoToma {
    final inicio = _inicioToma;
    if (inicio == null) return 0;
    final t = DateTime.now().difference(inicio).inMilliseconds /
        _duracionTomaActual.inMilliseconds;
    return t.clamp(0.0, 1.0);
  }
  // Acumulador: mac → lista de lecturas RSSI durante la toma
  final Map<String, List<double>> _acumCal = {};

  /// Lecturas mínimas de un beacon en una toma para usarlo. Emitiendo cada
  /// 160 ms, en una toma de 10 s se esperan ~60; con menos de 5 (una cada 2
  /// segundos) el beacon apenas se oye. También evita la media recortada con
  /// menos de 3 muestras, que no tiene qué recortar.
  static const int _minMuestrasCalibracion = 5;

  // Medición interactiva de escala: P1 → P2 es el LARGO y P2 → P3 el ANCHO.
  // Se marca igual que una zona prohibida (ver "Escala" más abajo).
  final List<Offset> _puntosEscala = []; // P1, P2 (largo), P3 (ancho)
  double? _largoMetros;                   // metros del largo (P1→P2)
  double? _anchoMetros;                   // metros del ancho (P2→P3)

  // Punto de escala que se está arrastrando (null = ninguno) y si se creó en
  // el gesto actual (para descartarlo si el gesto se cancela por un zoom de
  // dos dedos). Radio de "agarre" en coords normalizadas: un toque dentro de
  // este radio mueve el punto en vez de agregar uno nuevo.
  int? _puntoArrastrado;
  bool _puntoEscalaReciente = false;
  static const double _radioAgarrePunto = 0.045;

  // Edición de vértices de zonas prohibidas: índice del vértice que se está
  // arrastrando (null = no se está moviendo ninguno) y si ese vértice se creó
  // en el gesto actual (para poder descartarlo si el gesto se cancela por un
  // zoom de dos dedos). Radio de agarre en coordenadas normalizadas.
  int? _verticeArrastrado;
  bool _verticeReciente = false;
  static const double _radioAgarreVertice = 0.05;

  // Arrastre de beacons ya ubicados (modo beacons): MAC del beacon que se está
  // moviendo (null = ninguno) y radio de "agarre" en coordenadas normalizadas.
  // El arrastre entra por el mismo canal de un dedo que zonas/escala, así el
  // zoom de dos dedos sigue disponible sin conflicto.
  String? _beaconArrastrado;
  static const double _radioAgarreBeacon = 0.05;

  // Igual que con los lugares: desfasaje entre el dedo y el beacon (para que
  // no "salte" bajo el dedo al agarrarlo), punto donde empezó el gesto y si
  // ya superó el umbral de movimiento. Un toque limpio cerca de un beacon NO
  // tiene que moverlo: ese toque puede ser para ubicar otro al lado.
  Offset _desfaseAgarreBeacon = Offset.zero;
  Offset? _inicioAgarreBeacon;
  bool _beaconEnMovimiento = false;

  /// Beacon / lugar cuyo MARCADOR tocó el dedo en el gesto actual (lo avisa
  /// el MapaWidget). Tiene prioridad sobre la búsqueda por distancia: lo que
  /// se arrastra es lo que se tocó, no lo que quedó más cerca en coordenadas
  /// del plano (que en un plano apaisado no coincide con lo que se ve).
  String? _beaconTocado;
  int? _lugarTocado;
  bool _ultimoGestoBeaconFueArrastre = false;
  static const double _umbralMovimientoBeacon = 0.012;

  // ── MODO BORRAR ───────────────────────────────────────────────────────────
  // Antes se borraba tocando el elemento (o con long-press en los beacons), y
  // el mismo toque servía para agregar: al querer poner dos cosas pegadas, el
  // toque caía sobre la anterior y se ofrecía borrarla. Ahora las dos cosas
  // están separadas:
  //   · modo normal → tocar AGREGA y arrastrar MUEVE; nada se borra tocando.
  //   · modo borrar (botón "Borrar" sobre el mapa) → tocar un elemento lo
  //     elimina; no se agrega ni se mueve nada.
  bool _modoBorrar = false;

  /// El modo borrar sólo existe donde hay algo que borrar sobre el mapa.
  bool get _modoAdmiteBorrar =>
      _modo == _ModoEdicion.beacons ||
      _modo == _ModoEdicion.zonas ||
      _modo == _ModoEdicion.lugares;

  bool get _borrando => _modoBorrar && _modoAdmiteBorrar;

  // Arrastre de lugares de interés y escaleras (modo lugares). Mismo canal de
  // un dedo que beacons/zonas. Se guarda el id del lugar agarrado, el
  // desfasaje entre el dedo y el punto (para que no "salte" bajo el dedo) y
  // si ya superó el umbral de movimiento: un toque limpio NO debe moverlo,
  // porque ese toque es el que abre el diálogo de eliminar.
  int? _lugarArrastrado;
  Offset _desfaseAgarreLugar = Offset.zero;
  Offset? _inicioAgarreLugar;
  bool _lugarEnMovimiento = false;

  /// true si el último gesto sobre un lugar fue un arrastre real. El tap del
  /// marcador (que abre "eliminar") se resuelve DESPUÉS de soltar el dedo,
  /// cuando el estado del arrastre ya se limpió; esta marca le avisa que ese
  /// gesto no era un toque. Se limpia al empezar el próximo gesto.
  bool _ultimoGestoLugarFueArrastre = false;
  static const double _radioAgarreLugar = 0.05;
  static const double _umbralMovimientoLugar = 0.012;

  // ── Asistente de trazo (líneas rectas, estilo Canva) ──────────────────────
  // Cuando el trazo se acerca a un ángulo notable el punto se corrige para que
  // la línea quede exactamente recta, se dibujan guías punteadas y se emite un
  // pulso háptico. Se puede apagar para dibujar ángulos libres a propósito.
  bool _asistenteRecto = true;
  List<GuiaTrazo> _guias = const [];
  Offset? _guiaPunto;

  // ── Zoom del mapa de edición ──────────────────────────────────────────────
  // Para dibujar detalles chicos (una pared de 20 cm) hace falta acercarse
  // mucho, y que lo que depende del dedo se mida en la PANTALLA y no en el
  // plano: el radio para agarrar un vértice y las tolerancias del imán. Antes
  // se medían en el plano y no achicaban con el zoom: tocar a menos de ~2 m de
  // un vértice (en un plano de 40 m) lo agarraba en vez de crear otro, y la
  // guía de cierre tiraba todo lo que estuviera a menos de 40 cm.

  final TransformationController _transformMapa = TransformationController();

  /// Zoom con que se está viendo el mapa. Se actualiza con un margen (ver
  /// [_alCambiarZoom]) porque cambiarlo redibuja el mapa.
  double _escalaVista = 1.0;

  /// Tamaño del recuadro del mapa (lo deja el LayoutBuilder).
  Size? _tamVisor;

  /// Escala que se alcanza con el zoom máximo: con 200 px por metro, una
  /// pared de 20 cm mide 40 px en pantalla.
  static const double _pixelesPorMetroMaxEdicion = 200;

  /// Radio de agarre de un vértice o de un punto de escala, en píxeles de
  /// pantalla. Nunca más que el radio normalizado de siempre, así que sin
  /// zoom se agarra igual que antes.
  static const double _radioAgarrePx = 22;

  void _alCambiarZoom() {
    final z = _transformMapa.value.getMaxScaleOnAxis();
    if (!mounted || z <= 0) return;
    // 4 % alcanza para que manijas y trazos no se vean cambiar de tamaño, y
    // evita redibujar el mapa en cada cuadro de un pellizco.
    if ((z / _escalaVista - 1).abs() > 0.04) setState(() => _escalaVista = z);
  }

  /// Tamaño del plano dentro del recuadro, sin zoom (como lo arma MapaWidget).
  Size? get _tamPlanoBase {
    final visor = _tamVisor;
    if (visor == null || visor.isEmpty) return null;
    return MapaWidget.calcularTamanoContenido(
      visor,
      visor,
      aspectoForzado: _escalaY > 0 ? _escalaX / _escalaY : null,
    );
  }

  /// Metros del plano que mide un píxel de pantalla con el zoom actual.
  double? get _metrosPorPixel {
    final plano = _tamPlanoBase;
    final zoom = _transformMapa.value.getMaxScaleOnAxis();
    if (plano == null || plano.width <= 0 || zoom <= 0 || _escalaX <= 0) {
      return null;
    }
    return _escalaX / (plano.width * zoom);
  }

  /// Zoom máximo: el que lleva el plano a [_pixelesPorMetroMaxEdicion], y
  /// nunca menos que el 2,5 de siempre (el de InteractiveViewer).
  double get _zoomMaximo {
    final plano = _tamPlanoBase;
    if (plano == null || plano.width <= 0 || _escalaX <= 0) return 2.5;
    final pixelesPorMetro = plano.width / _escalaX;
    return max(2.5, _pixelesPorMetroMaxEdicion / pixelesPorMetro);
  }

  /// Qué tan lejos está [b] de [a] para agarrarlo, en "radios de agarre" (1
  /// o menos es adentro). Se mide en píxeles de pantalla; [radioNormalizado]
  /// es el radio de siempre en coordenadas normalizadas, que queda de tope.
  double _distanciaEnRadios(Offset a, Offset b, double radioNormalizado) {
    final plano = _tamPlanoBase;
    final zoom = _transformMapa.value.getMaxScaleOnAxis();
    if (plano == null || zoom <= 0) return (a - b).distance / radioNormalizado;
    final dx = (a.dx - b.dx) * plano.width * zoom;
    final dy = (a.dy - b.dy) * plano.height * zoom;
    final radioPx = min(_radioAgarrePx, radioNormalizado * plano.width * zoom);
    return sqrt(dx * dx + dy * dy) / radioPx;
  }

  /// Pasa [n] por el asistente y actualiza las guías a dibujar. Devuelve el
  /// punto ya corregido. No llama a setState: los llamadores lo hacen (o
  /// invocan _moverVertice, que ya repinta).
  Offset _aplicarAsistente(
    Offset n, {
    Offset? ancla,
    Offset? anclaSecundaria,
    bool diagonales = false,
  }) {
    final r = AsistenteTrazo.ajustar(
      punto: n,
      metrosX: _escalaX,
      metrosY: _escalaY,
      ancla: ancla,
      anclaSecundaria: anclaSecundaria,
      diagonales: diagonales,
      activo: _asistenteRecto,
      metrosPorPixel: _metrosPorPixel,
    );
    final habiaGuia = _guias.isNotEmpty;
    _guias = r.guias;
    _guiaPunto = r.hayAjuste ? r.punto : null;
    // Pulso háptico solo en el flanco de "enganche", no en cada frame.
    if (!habiaGuia && r.hayAjuste) HapticFeedback.selectionClick();
    return r.punto;
  }

  void _limpiarGuias() {
    _guias = const [];
    _guiaPunto = null;
  }

  /// Puntos de referencia para imantar el punto [idx] de la medición de escala:
  /// el extremo opuesto del segmento que lo contiene y, para el vértice del
  /// medio, también el otro extremo (así el ancho queda perpendicular al largo).
  ({Offset? ancla, Offset? sec}) _anclasEscala(int idx) {
    Offset? ancla, sec;
    if (idx == 0) {
      if (_puntosEscala.length > 1) ancla = _puntosEscala[1];
    } else if (idx == 1) {
      if (_puntosEscala.isNotEmpty) ancla = _puntosEscala[0];
      if (_puntosEscala.length > 2) sec = _puntosEscala[2];
    } else if (idx == 2) {
      if (_puntosEscala.length > 1) ancla = _puntosEscala[1];
    }
    return (ancla: ancla, sec: sec);
  }

  /// Puntos de referencia para imantar el vértice [i] de la zona en curso: el
  /// vértice anterior (la arista que se está trazando) y el siguiente. Cuando
  /// [i] es el último y ya hay 3 o más vértices, el "siguiente" es el primero:
  /// eso es lo que hace que el cierre de un rectángulo caiga exacto.
  ({Offset? ancla, Offset? sec}) _anclasVertice(int i) {
    final n = _verticesEnCurso.length;
    Offset? ancla, sec;
    if (i - 1 >= 0) {
      ancla = _verticesEnCurso[i - 1];
    } else if (n >= 3) {
      ancla = _verticesEnCurso[n - 1];
    }
    if (i + 1 < n) {
      sec = _verticesEnCurso[i + 1];
    } else if (n >= 3) {
      sec = _verticesEnCurso[0];
    }
    return (ancla: ancla, sec: sec);
  }

  /// Aplica el asistente al vértice [idx] y lo reubica.
  void _aplicarAsistenteEnVertice(int idx, Offset n) {
    final a = _anclasVertice(idx);
    final p = _aplicarAsistente(n,
        ancla: a.ancla, anclaSecundaria: a.sec, diagonales: true);
    _moverVertice(idx, p);
  }

  @override
  void initState() {
    super.initState();
    _escalaX = widget.escalaX;
    _escalaY = widget.escalaY;
    _tamCelda = widget.tamCeldaMetros;
    _grilla = GrillaNav(metrosX: _escalaX, metrosY: _escalaY, tamCeldaMetros: _tamCelda);
    _transformMapa.addListener(_alCambiarZoom);
    _cargarDatosIniciales();
  }

  @override
  void dispose() {
    _etiquetaCalCtrl.dispose();
    _transformMapa.dispose();
    _compassConfigSub?.cancel();
    BluetoothHelper.detenerScanSeguro(dueno: this);
    super.dispose();
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
      final zonas = await DatabaseHelper.instance.obtenerZonasPorPiso(widget.pisoId);
      final lugares = await DatabaseHelper.instance.obtenerLugaresPorPiso(widget.pisoId);
      final calibraciones = await DatabaseHelper.instance.obtenerCalibracionesPorPiso(widget.pisoId);

      // Leer rotación del mapa guardada.
      final db = await DatabaseHelper.instance.database;
      final filas = await db.query('pisos', columns: ['rotacion_mapa', 'remote_id'], where: 'id = ?', whereArgs: [widget.pisoId], limit: 1);
      final rotGuardada = filas.isNotEmpty ? ((filas.first['rotacion_mapa'] as num?)?.toDouble() ?? 0.0) : 0.0;
      final remoteId = filas.isNotEmpty ? filas.first['remote_id'] as String? : null;

      if (mounted) {
        setState(() {
          _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
          _zonas = zonas;
          _lugares = lugares;
          _calibraciones = calibraciones;
          _rotacionMapa = rotGuardada;
          _remoteIdPublicado = remoteId;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    }
  }

  Future<void> _sincronizarBeacons() async {
    try {
      await DatabaseHelper.instance.guardarBeacons(widget.pisoId, _beaconsEnElMapa.values.toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando beacons: $e')),
        );
      }
    }
  }

  // -- Publicar a la nube (Supabase) -----------------------------------------

  /// Sube este piso completo (plano + beacons + zonas + lugares + calibraciones)
  /// a la nube para que los usuarios lo puedan descargar. Idempotente: si el
  /// piso ya se había publicado, reemplaza su versión remota (no duplica).
  Future<void> _publicarPiso() async {
    if (_publicando) return;

    if (!SupabaseService.instance.configurado) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Falta configurar Supabase (supabase_config.dart) para publicar.',
          ),
        ),
      );
      return;
    }

    if (_beaconsEnElMapa.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cargá al menos un beacon antes de publicar el mapa.'),
        ),
      );
      return;
    }

    setState(() => _publicando = true);
    try {
      // Asegurar que lo último quede persistido localmente antes de subir.
      await _sincronizarBeacons();

      final info =
          await DatabaseHelper.instance.obtenerPisoConEdificio(widget.pisoId);
      if (info == null) throw Exception('No se encontró el piso.');

      final remoteId = await SupabaseService.instance.publicarPiso(
        edificioNombre: (info['edificio_nombre'] as String?) ?? 'Edificio',
        pisoNombre: (info['nombre_piso'] as String?) ?? 'Piso',
        rutaImagen: widget.rutaImagen,
        escalaX: _escalaX,
        escalaY: _escalaY,
        tamCelda: _tamCelda,
        rotacion: _rotacionMapa,
        beacons: _beaconsEnElMapa.values,
        zonas: _zonas,
        lugares: _lugares,
        calibraciones: _calibraciones,
        remoteIdExistente: info['remote_id'] as String?,
      );

      await DatabaseHelper.instance
          .guardarRemoteIdPiso(widget.pisoId, remoteId);

      if (!mounted) return;
      final republicado = (info['remote_id'] as String?) != null;
      setState(() => _remoteIdPublicado = remoteId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(republicado
              ? 'Mapa actualizado en la nube'
              : 'Mapa publicado. Ya se puede descargar.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al publicar: $e')),
      );
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  /// Borra de la nube el mapa que este admin publicó. El servidor sólo lo
  /// permite si es el dueño; si es de otro administrador, devuelve error.
  Future<void> _eliminarMapaPublicado() async {
    final remoteId = _remoteIdPublicado;
    if (remoteId == null || _publicando) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar de la nube'),
        content: const Text(
          'Se quita del catálogo y se borra de los teléfonos que ya lo '
          'tienen.\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _publicando = true);
    try {
      await SupabaseService.instance.eliminarMapa(remoteId);
      await DatabaseHelper.instance.limpiarRemoteIdPiso(widget.pisoId);
      if (!mounted) return;
      setState(() => _remoteIdPublicado = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mapa eliminado de la nube')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e')),
      );
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  // -- Beacons ---------------------------------------------------------------

  void _borrarBeacon(String mac) async {
    try {
      final nombre = _beaconsEnElMapa[mac]?.nombre ?? 'Beacon';
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eliminar beacon?'),
          content: Text('Se eliminara "$nombre" ($mac) de este piso.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;
      setState(() => _beaconsEnElMapa.remove(mac));
      await _sincronizarBeacons();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beacon eliminado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error eliminando beacon: $e')),
        );
      }
    }
  }

  /// Distancia entre dos puntos del plano para comparar contra los radios de
  /// agarre, expresada como fracción del lado MAYOR del piso.
  ///
  /// No se usa la distancia en coordenadas normalizadas directamente porque
  /// 0.05 "de ancho" y 0.05 "de alto" sólo miden lo mismo en pantalla si el
  /// piso es cuadrado: en un plano de 30 × 12 m, 0.05 de alto son menos de la
  /// mitad de píxeles que 0.05 de ancho, y el radio de agarre quedaba chato.
  /// En un piso cuadrado da exactamente lo mismo que antes.
  double _distanciaAgarre(Offset a, Offset b) {
    final lado = max(_grilla.metrosX, _grilla.metrosY);
    if (lado <= 0) return (a - b).distance;
    final dx = (a.dx - b.dx) * _grilla.metrosX;
    final dy = (a.dy - b.dy) * _grilla.metrosY;
    return sqrt(dx * dx + dy * dy) / lado;
  }

  /// MAC del beacon ubicado cuyo ícono cae dentro del radio de agarre de [n],
  /// o null. Si hay varios, el más cercano.
  String? _beaconCercano(Offset n) {
    String? mejor;
    double mejorDist = _radioAgarreBeacon;
    for (final b in _beaconsEnElMapa.values) {
      final d = _distanciaAgarre(b.posicion, n);
      if (d <= mejorDist) {
        mejorDist = d;
        mejor = b.mac;
      }
    }
    return mejor;
  }

  // ── Arrastre de beacons (modo beacons) ────────────────────────────────────
  // Comparte el canal de un dedo con zonas/escala. Un dedo apoyado sobre un
  // beacon lo agarra y lo mueve; en zona libre no hace nada (la colocación de
  // un beacon nuevo sigue siendo por tap con un dispositivo seleccionado). El
  // segundo dedo cancela el arrastre y deja que el InteractiveViewer haga zoom.

  void _onArrastreInicioBeacon(Offset n) {
    if (!mounted) return;
    _ultimoGestoBeaconFueArrastre = false;
    _inicioAgarreBeacon = n;
    _beaconEnMovimiento = false;
    // 1) El beacon cuyo marcador se tocó; 2) si el dedo cayó apenas afuera,
    //    el más cercano dentro del radio de agarre.
    final tocado = _beaconTocado;
    _beaconTocado = null;
    final mac = (tocado != null && _beaconsEnElMapa.containsKey(tocado))
        ? tocado
        : _beaconCercano(n);
    final b = mac == null ? null : _beaconsEnElMapa[mac];
    // Todavía no se resalta: recién cuando el dedo se mueva de verdad (ver
    // _onArrastreActualizarBeacon). Así un toque al lado de un beacon no lo
    // resalta ni lo corre.
    _beaconArrastrado = b == null ? null : mac;
    _desfaseAgarreBeacon = b == null ? Offset.zero : b.posicion - n;
  }

  /// El dedo se apoyó sobre la mira de un beacon (aviso del MapaWidget).
  /// Funciona llegue antes o después que _onArrastreInicioBeacon: si el
  /// gesto todavía no se abrió, se deja anotado; si ya se abrió, se corrige
  /// lo que había elegido la búsqueda por distancia.
  void _onAgarreBeacon(String mac) {
    final b = _beaconsEnElMapa[mac];
    if (b == null || _beaconEnMovimiento) return;
    if (_inicioAgarreBeacon != null) {
      _beaconArrastrado = mac;
      _desfaseAgarreBeacon = b.posicion - _inicioAgarreBeacon!;
    } else {
      _beaconTocado = mac;
    }
  }

  void _onArrastreActualizarBeacon(Offset n) {
    if (!mounted || _beaconArrastrado == null) return;
    final b = _beaconsEnElMapa[_beaconArrastrado!];
    if (b == null) return;
    // Hasta superar el umbral el gesto se trata como toque (no se mueve).
    if (!_beaconEnMovimiento) {
      if (_inicioAgarreBeacon == null ||
          (n - _inicioAgarreBeacon!).distance < _umbralMovimientoBeacon) {
        return;
      }
      _beaconEnMovimiento = true;
    }
    final destino = n + _desfaseAgarreBeacon;
    // posicion es mutable; recortada a [0,1]. El repintado sale del setState.
    setState(() {
      b.posicion =
          Offset(destino.dx.clamp(0.0, 1.0), destino.dy.clamp(0.0, 1.0));
    });
  }

  /// Soltar el dedo y cancelar (segundo dedo para zoom) hacen lo mismo: el
  /// beacon queda donde se dejó y, si se movió, se persiste.
  Future<void> _terminarArrastreBeacon() async {
    if (!mounted) return;
    final movio = _beaconArrastrado != null && _beaconEnMovimiento;
    _ultimoGestoBeaconFueArrastre = movio;
    _beaconTocado = null;
    setState(() {
      _beaconArrastrado = null;
      _inicioAgarreBeacon = null;
      _beaconEnMovimiento = false;
    });
    if (movio) await _sincronizarBeacons(); // persistir la nueva ubicación
  }

  Future<void> _onArrastreFinBeacon() => _terminarArrastreBeacon();
  void _onArrastreCancelarBeacon() => _terminarArrastreBeacon();

  void _conmutarEscaner() async {
    if (_escaneando) {
      await BluetoothHelper.detenerScanSeguro(dueno: this);
      if (mounted) setState(() => _escaneando = false);
      return;
    }

    final ok = await BluetoothHelper.verificarPrecondiciones(context);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth o permisos no disponibles')),
        );
      }
      return;
    }

    if (mounted) setState(() => _escaneando = true);

    final scanOk = await BluetoothHelper.iniciarScanSeguro(
      dueno: this,
      onResultados: (resultados) {
        if (!mounted) return;
        setState(() => _dispositivosCercanos = resultados);
        _actualizarSenales(resultados);
      },
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error en scan: $e')),
          );
        }
      },
    );

    if (!scanOk && mounted) {
      setState(() => _escaneando = false);
    }
  }

  // -- Filtro de dispositivos por nombre --------------------------------------

  /// `true` si el nombre anunciado de [r] contiene el filtro (sin distinguir
  /// mayúsculas). Se compara contra `advName`, que es el mismo nombre que se
  /// muestra en la lista.
  bool _coincideFiltro(ScanResult r) {
    if (_filtroNombre.isEmpty) return true;
    return r.device.advName.toLowerCase().contains(_filtroNombre.toLowerCase());
  }

  void _aplicarFiltroNombre(String filtro) {
    if (!mounted) return;
    setState(() {
      _filtroNombre = filtro;
      // Si el dispositivo elegido quedó oculto se descarta la selección: si no,
      // un toque en el mapa ubicaría un beacon que ya no se ve en la lista.
      if (_seleccionado != null && !_coincideFiltro(_seleccionado!)) {
        _seleccionado = null;
      }
    });
  }

  /// Pide el texto del filtro en un diálogo. No se usa un campo fijo bajo el
  /// mapa porque el body es un Column con el mapa de 380 px: al abrirse el
  /// teclado ese campo quedaría tapado y el Column desbordaría.
  Future<void> _pedirFiltroNombre() async {
    final controller = TextEditingController(text: _filtroNombre);
    final filtro = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Filtrar dispositivos por nombre'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Ej: BlindRoute (vacío: todos)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          if (_filtroNombre.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Quitar filtro'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Filtrar'),
          ),
        ],
      ),
    );
    if (filtro == null) return;
    _aplicarFiltroNombre(filtro);
  }

  /// Hora de la última lectura NUEVA procesada de cada beacon del piso.
  ///
  /// flutter_blue_plus entrega en cada callback la lista ACUMULADA de
  /// dispositivos, y cada uno trae su ÚLTIMA lectura aunque no haya vuelto a
  /// emitir. Antes se tomaba la lista entera en cada callback, así que la
  /// misma lectura entraba muchas veces: a la ventana del punto de posición y
  /// a la toma de calibración. En la toma eso inflaba la cantidad de muestras
  /// y hacía pesar más a las lecturas que tardaban en renovarse (y cuántas
  /// copias entraban dependía de cuántos dispositivos BLE hubiera alrededor).
  /// Ahora una lectura cuenta sólo si es posterior a la última de ese beacon,
  /// igual que en la navegación: calibración y navegación miden lo mismo.
  final Map<String, DateTime> _ultimaLecturaBeacon = {};

  void _actualizarSenales(List<ScanResult> resultados) {
    if (!mounted) return;
    var nuevas = 0;
    for (var res in resultados) {
      try {
        final mac = res.device.remoteId.str;
        final beacon = _beaconsEnElMapa[mac];
        // Sólo interesan los beacons del piso: los demás dispositivos se ven
        // en la lista con su lectura cruda.
        if (beacon == null) continue;
        final ultima = _ultimaLecturaBeacon[mac];
        if (ultima != null && !res.timeStamp.isAfter(ultima)) continue;
        _ultimaLecturaBeacon[mac] = res.timeStamp;
        nuevas++;

        final rssiSuave = _procesador.filtrarYPromediar(mac, res.rssi);
        if (rssiSuave != null) {
          setState(() => beacon.rssiFiltrado = rssiSuave);
        }

        // Acumulación de muestras para calibración multi-muestra.
        if (_tomandoMuestras) {
          _acumCal.putIfAbsent(mac, () => []).add(res.rssi.toDouble());
        }
      } catch (e) {
        // Ignorar
      }
    }

    // La toma termina por TIEMPO transcurrido, no por cantidad de callbacks
    // (ver la nota en _inicioToma). _muestrasAcumuladas cuenta las lecturas
    // nuevas que entraron, sumando todos los beacons: es informativo.
    if (_tomandoMuestras) {
      // Acumular el rumbo mientras dura la toma (media circular).
      final h = _headingEnVivo;
      if (h != null) {
        final r = h * pi / 180;
        _sumSenoRumbo += sin(r);
        _sumCosRumbo += cos(r);
        _muestrasRumbo++;
      }
      if (nuevas > 0) setState(() => _muestrasAcumuladas += nuevas);
      final inicio = _inicioToma;
      if (inicio != null &&
          DateTime.now().difference(inicio) >= _duracionTomaActual) {
        _guardarCalibracionAcumulada();
      }
    }

    _calcularPosicion();
  }

  void _calcularPosicion() {
    // En modo calibración con celda seleccionada: NO actualizar la posición
    // desde BLE. El operador declaró dónde está; BLE solo se usa para
    // acumular muestras, no para mover el ícono.
    if (_modo == _ModoEdicion.calibracion && _celdaCalSeleccionada != null) return;

    try {
      var activos = _beaconsEnElMapa.values.where((b) => b.rssiFiltrado > -95).toList();
      if (activos.length < 2) return;
      // Misma multilateración que la navegación (ver [Posicionador]): el
      // centroide ponderado se sesgaba hacia el centro del layout.
      final obs = <ObservacionRango>[];
      for (var b in activos) {
        final tx = ProcesadorSenal.txPowerCalibrado(b.mac, _calibraciones);
        final d = ProcesadorSenal.rssiADistanciaConTx(b.rssiFiltrado, tx);
        obs.add(ObservacionRango(b.posicion, d, 1.0 / (d + 1.0)));
      }
      final p = Posicionador.estimar(obs,
          metrosX: _grilla.metrosX,
          metrosY: _grilla.metrosY,
          posPrevia: _posicionUsuario,
          factorMovimiento: 0.5);
      if (mounted) setState(() => _posicionUsuario = p);
    } catch (e) {
      // Ignorar
    }
  }

  // -- Zonas -----------------------------------------------------------------

  void _agregarVertice(Offset normalizado) {
    if (mounted) {
      setState(() => _verticesEnCurso = [..._verticesEnCurso, normalizado]);
    }
  }

  void _cerrarZona() async {
    if (_verticesEnCurso.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Necesitas al menos 3 puntos para cerrar la zona')),
        );
      }
      return;
    }

    final nombre = await _pedirNombreZona();
    if (nombre == null) {
      _descartarZonaEnCurso();
      return;
    }
    final nombreFinal = nombre.isEmpty ? 'Zona prohibida' : nombre;

    try {
      final zona = ZonaNoTransitable(
        pisoId: widget.pisoId,
        nombre: nombreFinal,
        vertices: List.from(_verticesEnCurso),
      );
      final id = await DatabaseHelper.instance.crearZona(zona);
      if (mounted) {
        setState(() {
          _zonas = [..._zonas, zona.copyWith(id: id)];
          _verticesEnCurso = [];
          _verticeArrastrado = null;
          _verticeReciente = false;
          _limpiarGuias();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando zona: $e')),
        );
      }
    }
  }

  void _descartarZonaEnCurso() {
    if (!mounted) return;
    setState(() {
      _verticesEnCurso = [];
      _verticeArrastrado = null;
      _verticeReciente = false;
      _limpiarGuias();
    });
  }

  void _borrarZona(ZonaNoTransitable zona) async {
    try {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eliminar zona?'),
          content: Text('Se eliminara "${zona.nombre}".'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
      await DatabaseHelper.instance.eliminarZona(zona.id!);
      if (mounted) {
        setState(() => _zonas = _zonas.where((z) => z.id != zona.id).toList());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error eliminando zona: $e')),
        );
      }
    }
  }

  Future<String?> _pedirNombreZona() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre de la zona (opcional)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Ej: Escaleras, Ascensor (vacío: nombre por defecto)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // -- Zonas: arrastre de vértices -------------------------------------------
  //
  // El editor de zonas usa el mismo mecanismo de un dedo que la medición de
  // escala (Listener crudo dentro de MapaWidget), de modo que los vértices se
  // puedan reacomodar ANTES de cerrar la zona:
  //   · Tocar sobre un vértice ya marcado y arrastrar → lo mueve.
  //   · Tocar en cualquier otro lado → agrega un vértice nuevo, que queda
  //     enganchado al dedo y se puede afinar sin levantarlo.
  //   · Apoyar un segundo dedo → zoom; si el vértice se acababa de crear en
  //     ese gesto, se descarta.

  int? _verticeCercano(Offset n) {
    int? mejorIdx;
    double mejorDist = 1.0;
    for (int i = 0; i < _verticesEnCurso.length; i++) {
      final d = _distanciaEnRadios(_verticesEnCurso[i], n, _radioAgarreVertice);
      if (d <= mejorDist) {
        mejorDist = d;
        mejorIdx = i;
      }
    }
    return mejorIdx;
  }

  void _moverVertice(int idx, Offset n) {
    if (idx < 0 || idx >= _verticesEnCurso.length) return;
    // Copia nueva (no mutación in-place): el painter compara las listas por
    // referencia, así que sin la copia el arrastre no se repintaría.
    final nuevos = List<Offset>.from(_verticesEnCurso);
    nuevos[idx] = n;
    setState(() => _verticesEnCurso = nuevos);
  }

  void _onArrastreInicioZona(Offset n) {
    if (!mounted) return;

    // 1) ¿El dedo cayó sobre un vértice ya marcado? → se arrastra ese punto
    //    en lugar de crear uno nuevo.
    final idx = _verticeCercano(n);
    if (idx != null) {
      setState(() {
        _verticeArrastrado = idx;
        _verticeReciente = false;
      });
      _aplicarAsistenteEnVertice(idx, n);
      return;
    }

    // 2) (Ya no existe.) Antes, sin zona en curso, un toque dentro de una
    //    zona guardada significaba "borrar esa zona" y no se podía empezar
    //    un polígono nuevo ahí. Borrar ahora es un modo aparte (botón
    //    "Borrar"), así que una zona puede arrancar pegada a otra o encima.

    // 3) Vértice nuevo, enganchado al dedo para poder corregirlo en el mismo
    //    gesto sin tener que soltarlo y volver a agarrarlo.
    final idxNuevo = _verticesEnCurso.length;
    setState(() {
      _verticesEnCurso = [..._verticesEnCurso, n];
      _verticeArrastrado = idxNuevo;
      _verticeReciente = true;
    });
    // El imantado se evalúa recién con el vértice ya en la lista, para que el
    // asistente pueda mirar también el primer vértice (arista de cierre).
    _aplicarAsistenteEnVertice(idxNuevo, n);
  }

  void _onArrastreActualizarZona(Offset n) {
    if (!mounted || _verticeArrastrado == null) return;
    _aplicarAsistenteEnVertice(_verticeArrastrado!, n);
  }

  void _onArrastreFinZona() {
    if (!mounted) return;
    setState(() {
      _verticeArrastrado = null;
      _verticeReciente = false;
      _limpiarGuias();
    });
  }

  /// Segundo dedo apoyado (gesto de zoom): si el vértice se acababa de crear en
  /// este gesto se descarta; si era uno ya existente se deja donde quedó.
  void _onArrastreCancelarZona() {
    if (!mounted) return;
    setState(() {
      _limpiarGuias();
      if (_verticeReciente && _verticesEnCurso.isNotEmpty) {
        _verticesEnCurso =
            _verticesEnCurso.sublist(0, _verticesEnCurso.length - 1);
      }
      _verticeArrastrado = null;
      _verticeReciente = false;
    });
  }

  /// Quita el último vértice marcado (deshacer un toque de más).
  void _quitarUltimoVertice() {
    if (!mounted || _verticesEnCurso.isEmpty) return;
    setState(() {
      _verticesEnCurso =
          _verticesEnCurso.sublist(0, _verticesEnCurso.length - 1);
      _verticeArrastrado = null;
      _verticeReciente = false;
      _limpiarGuias();
    });
  }

  // -- Lugares de Interes (POI) ----------------------------------------------

  /// Alta de un lugar de interés o de una escalera.
  ///
  /// Las escaleras se cargan POR PISO (no vinculadas entre pisos): cada una
  /// dice si desde este piso sube, baja o ambas, y hacia qué lado del plano
  /// da su entrada. La navegación sólo necesita las escaleras del piso donde
  /// está el usuario, y así cada piso sigue siendo un mapa independiente.
  void _agregarLugar(Offset normalizado) async {
    final datos = await showDialog<_DatosNuevoLugar>(
      context: context,
      builder: (ctx) => const _DialogoNuevoLugar(),
    );
    if (datos == null) return;

    try {
      final lugar = LugarInteres(
        pisoId: widget.pisoId,
        nombre: datos.nombre,
        posicion: normalizado,
        tipo: datos.tipo,
        sube: datos.sube,
        baja: datos.baja,
        direccionEntrada: datos.direccionEntrada,
        palabrasClave: datos.palabrasClave,
        rubro: datos.rubro,
        esAscensor: datos.esAscensor,
      );
      final id = await DatabaseHelper.instance.crearLugarInteres(lugar);
      if (mounted) {
        setState(() => _lugares.add(lugar.copyWith(id: id)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando lugar: $e')),
        );
      }
    }
  }

  /// Edita un lugar ya cargado (nombre, rubro, descripción, palabras clave
  /// y, si es escalera, sus datos). Se abre tocándolo en la lista de abajo; la
  /// posición no cambia acá (para eso se arrastra en el mapa).
  Future<void> _editarLugar(LugarInteres lugar) async {
    if (lugar.id == null) return;
    final datos = await showDialog<_DatosNuevoLugar>(
      context: context,
      builder: (ctx) => _DialogoNuevoLugar(inicial: lugar),
    );
    if (datos == null || !mounted) return;

    // Se parte de la versión ACTUAL del lugar en la lista (no de la que se
    // pasó al diálogo): si lo movieron mientras tanto, se conserva la
    // posición nueva.
    final actual = _lugares.where((l) => l.id == lugar.id).firstOrNull ?? lugar;
    final editado = LugarInteres(
      id: actual.id,
      pisoId: actual.pisoId,
      nombre: datos.nombre,
      posicion: actual.posicion,
      // La descripción ya no se carga desde la app; se conserva la que tenga
      // un lugar viejo para no borrarla sin aviso.
      descripcion: actual.descripcion,
      tipo: datos.tipo,
      sube: datos.sube,
      baja: datos.baja,
      direccionEntrada: datos.direccionEntrada,
      palabrasClave: datos.palabrasClave,
      rubro: datos.rubro,
      esAscensor: datos.esAscensor,
    );
    try {
      await DatabaseHelper.instance.actualizarLugarInteres(editado);
      if (mounted) {
        setState(() {
          _lugares =
              _lugares.map((l) => l.id == editado.id ? editado : l).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando los cambios: $e')),
        );
      }
    }
  }

  // ── Arrastre de lugares y escaleras (modo lugares) ────────────────────────

  /// Lugar cuyo marcador cae dentro del radio de agarre de [n], o null. Si
  /// hay varios, el más cercano.
  ///  - Lugar común: el pin se dibuja ARRIBA del punto (la punta es la
  ///    posición), así que también se acepta tocar el ícono, un poco más arriba.
  ///  - Escalera: el cuadrado está centrado en la posición y mide 1 m, así que
  ///    el radio cubre todo el cuadrado aunque sea más grande que el normal.
  LugarInteres? _lugarCercano(Offset n) {
    LugarInteres? mejor;
    double mejorDist = double.infinity;
    // Todo en la misma unidad que _distanciaAgarre: fracción del lado mayor.
    final lado = max(_grilla.metrosX, _grilla.metrosY);
    final mitadEscalera =
        lado > 0 ? MapaWidget.anchoEscaleraMetros * 0.75 / lado : 0.0;
    // Cuánto hay que bajar el dedo (en y normalizado) para compararlo con el
    // ícono, que está por encima de la punta.
    final bajarY = _grilla.metrosY > 0
        ? _radioAgarreLugar * 0.6 * lado / _grilla.metrosY
        : _radioAgarreLugar * 0.6;
    for (final l in _lugares) {
      if (l.id == null) continue;
      final double d;
      final double radio;
      if (l.esEscalera) {
        d = _distanciaAgarre(l.posicion, n);
        radio = max(_radioAgarreLugar, mitadEscalera);
      } else {
        final dPunto = _distanciaAgarre(l.posicion, n);
        final dIcono =
            _distanciaAgarre(l.posicion, Offset(n.dx, n.dy + bajarY));
        d = min(dPunto, dIcono);
        radio = _radioAgarreLugar;
      }
      if (d <= radio && d < mejorDist) {
        mejorDist = d;
        mejor = l;
      }
    }
    return mejor;
  }

  void _onArrastreInicioLugar(Offset n) {
    if (!mounted) return;
    _ultimoGestoLugarFueArrastre = false;
    _inicioAgarreLugar = n;
    _lugarEnMovimiento = false;
    // 1) El lugar cuyo marcador (ícono o etiqueta) se tocó; 2) si el dedo
    //    cayó apenas afuera, el más cercano dentro del radio de agarre.
    final tocado = _lugarTocado;
    _lugarTocado = null;
    final l = (tocado == null
            ? null
            : _lugares.where((x) => x.id == tocado).firstOrNull) ??
        _lugarCercano(n);
    // Sin setState: el marcador se resalta recién cuando empieza a moverse.
    _lugarArrastrado = l?.id;
    _desfaseAgarreLugar = l == null ? Offset.zero : l.posicion - n;
  }

  /// El dedo se apoyó sobre el marcador de un lugar (aviso del MapaWidget).
  /// Funciona llegue antes o después que _onArrastreInicioLugar: si el gesto
  /// todavía no se abrió, se deja anotado; si ya se abrió, se corrige lo que
  /// había elegido la búsqueda por distancia.
  void _onAgarreLugar(LugarInteres lugar) {
    if (lugar.id == null || _lugarEnMovimiento) return;
    if (_inicioAgarreLugar != null) {
      _lugarArrastrado = lugar.id;
      _desfaseAgarreLugar = lugar.posicion - _inicioAgarreLugar!;
    } else {
      _lugarTocado = lugar.id;
    }
  }

  void _onArrastreActualizarLugar(Offset n) {
    if (!mounted || _lugarArrastrado == null) return;
    // Hasta superar el umbral el gesto se trata como toque (no se mueve).
    if (!_lugarEnMovimiento) {
      if (_inicioAgarreLugar == null ||
          (n - _inicioAgarreLugar!).distance < _umbralMovimientoLugar) {
        return;
      }
      _lugarEnMovimiento = true;
    }
    final destino = n + _desfaseAgarreLugar;
    final nueva = Offset(destino.dx.clamp(0.0, 1.0), destino.dy.clamp(0.0, 1.0));
    setState(() {
      // Se reasigna la lista (no se muta in-place) para que el mapa se
      // entere del cambio, igual que con las zonas.
      _lugares = _lugares
          .map((l) => l.id == _lugarArrastrado ? l.copyWith(posicion: nueva) : l)
          .toList();
    });
  }

  Future<void> _terminarArrastreLugar() async {
    if (!mounted) return;
    final id = _lugarArrastrado;
    final movio = _lugarEnMovimiento;
    _ultimoGestoLugarFueArrastre = movio;
    _lugarTocado = null;
    setState(() {
      _lugarArrastrado = null;
      _inicioAgarreLugar = null;
      _lugarEnMovimiento = false;
    });
    if (id == null || !movio) return;
    final lugar = _lugares.where((l) => l.id == id).firstOrNull;
    if (lugar == null) return;
    try {
      await DatabaseHelper.instance.actualizarPosicionLugar(id, lugar.posicion);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando la nueva ubicación: $e')),
        );
      }
    }
  }

  // Soltar el dedo y cancelar (segundo dedo para zoom) hacen lo mismo: el
  // lugar queda donde se soltó y se persiste, como con los beacons.
  void _onArrastreFinLugar() => _terminarArrastreLugar();
  void _onArrastreCancelarLugar() => _terminarArrastreLugar();

  void _borrarLugar(LugarInteres lugar) async {
    // Sólo se llega acá con el modo borrar activo (toque sobre el marcador) o
    // desde el tacho de la lista: ya no hay que distinguirlo de un arrastre.
    try {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eliminar lugar?'),
          content: Text('Se eliminara "${lugar.nombre}".'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
      await DatabaseHelper.instance.eliminarLugarInteres(lugar.id!);
      if (mounted) {
        setState(() => _lugares.removeWhere((l) => l.id == lugar.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error eliminando lugar: $e')),
        );
      }
    }
  }

  // -- Tap en el mapa --------------------------------------------------------

  void _onTapMapa(Offset normalizado) {
    // El toque llega al LEVANTAR el dedo (ver MapaWidget.onTapMapa), después
    // de que el canal de un dedo cerró su gesto. Regla única: tocar agrega,
    // en cualquier lugar, aunque sea pegado a un elemento existente. Lo único
    // que se descarta es el "toque" con que termina un arrastre corto.
    if (_modo == _ModoEdicion.beacons) {
      if (_ultimoGestoBeaconFueArrastre) {
        _ultimoGestoBeaconFueArrastre = false;
        return;
      }
      if (_seleccionado == null) return;
      String mac = _seleccionado!.device.remoteId.str;
      if (mounted) {
        setState(() {
          _beaconsEnElMapa[mac] = BeaconMarcado(
            posicion: normalizado,
            nombre: _seleccionado!.device.advName.isEmpty ? 'Beacon' : _seleccionado!.device.advName,
            mac: mac,
          );
          _seleccionado = null;
        });
      }
      _sincronizarBeacons();
    } else if (_modo == _ModoEdicion.zonas) {
      // En modo zonas los toques ya NO llegan por acá: se manejan en
      // _onArrastreInicioZona, para poder apoyar el vértice y corregir su
      // ubicación dentro del mismo gesto. Se conserva la rama por si el
      // callback se vuelve a conectar.
      _agregarVertice(normalizado);
    } else if (_modo == _ModoEdicion.lugares) {
      if (_ultimoGestoLugarFueArrastre) {
        _ultimoGestoLugarFueArrastre = false;
        return;
      }
      _agregarLugar(normalizado);
    } else if (_modo == _ModoEdicion.calibracion) {
      // Seleccionar la celda donde el operador dice estar parado.
      // El ícono de posición salta INMEDIATAMENTE a esa celda y deja de
      // moverse con el BLE mientras se toman muestras: la calibración parte
      // de la premisa de que el operador declaró dónde está.
      final ix = _grilla.indiceX(normalizado.dx);
      final iy = _grilla.indiceY(normalizado.dy);
      if (mounted) {
        setState(() {
          _celdaCalSeleccionada = (ix: ix, iy: iy);
          // Anclar la posición visible al centro de la celda seleccionada.
          _posicionUsuario = Offset(_grilla.centroX(ix), _grilla.centroY(iy));
        });
      }
    }
    // En modo escala la interacción es por arrastre (no por tap).
  }

  // -- Calibración -----------------------------------------------------------

  /// Asegura que el escáner BLE esté activo (necesario para ver lecturas en
  /// tiempo real al calibrar). No-op si ya está escaneando.
  Future<void> _asegurarEscaneando() async {
    if (_escaneando) return;
    final ok = await BluetoothHelper.verificarPrecondiciones(context);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth o permisos no disponibles')),
        );
      }
      return;
    }
    if (mounted) setState(() => _escaneando = true);
    final scanOk = await BluetoothHelper.iniciarScanSeguro(
      dueno: this,
      onResultados: (resultados) {
        if (!mounted) return;
        setState(() => _dispositivosCercanos = resultados);
        _actualizarSenales(resultados);
      },
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error en scan: $e')),
          );
        }
      },
    );
    if (!scanOk && mounted) setState(() => _escaneando = false);
  }

  // -- Brújula en vivo -------------------------------------------------------

  void _iniciarCompass() {
    if (_compassConfigSub != null) return; // ya activa
    if (FlutterCompass.events == null) return;
    _compassConfigSub = FlutterCompass.events!.listen((CompassEvent event) {
      if (!mounted) return;
      if (event.heading != null) {
        _tomaRumbo?.add(event.heading!);
        setState(() {
          _headingEnVivo = event.heading;
          _precisionBrujula = event.accuracy;
        });
      }
    });
  }

  void _detenerCompass() {
    _compassConfigSub?.cancel();
    _compassConfigSub = null;
    if (mounted) {
      setState(() {
        _headingEnVivo = null;
        _precisionBrujula = null;
        _tomaRumbo = null; // cancela una toma a medias
      });
    }
  }

  /// Cambia el offset de la brújula y lo guarda enseguida, como el resto de
  /// la configuración del piso. Devuelve si se pudo guardar.
  ///
  /// BUG CORREGIDO: antes el offset sólo se guardaba con un botón aparte. Si
  /// se salía sin tocarlo, el cambio se perdía sin aviso y al volver a entrar
  /// estaba el viejo; y "Publicar" subía el valor de pantalla, no el guardado,
  /// así que la nube y el teléfono podían quedar distintos.
  Future<bool> _fijarRotacion(double grados) async {
    final v = ((grados.roundToDouble() % 360) + 360) % 360;
    if (mounted) setState(() => _rotacionMapa = v);
    try {
      await DatabaseHelper.instance.actualizarRotacionMapa(widget.pisoId, v);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando el offset: $e')),
        );
      }
      return false;
    }
  }

  /// Toma el rumbo durante [_duracionTomaRumbo], con el teléfono apuntando a
  /// lo que en el plano es "arriba", y lo guarda como offset. Se promedia
  /// (media circular) porque la lectura cruda tiembla varios grados; si las
  /// lecturas están muy dispersas es que el teléfono se movió y se descarta.
  Future<void> _tomarDireccionActual() async {
    if (_tomaRumbo != null || _headingEnVivo == null) return;
    final toma = <double>[];
    setState(() => _tomaRumbo = toma);
    await Future.delayed(_duracionTomaRumbo);
    // Cancelada (se salió del modo brújula) o pantalla cerrada.
    if (!mounted || !identical(_tomaRumbo, toma)) return;
    setState(() => _tomaRumbo = null);

    void avisar(String texto) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));

    if (toma.length < 3) {
      avisar('No llegaron lecturas de la brújula. Probá de nuevo.');
      return;
    }
    double s = 0, c = 0;
    for (final h in toma) {
      s += sin(h * pi / 180);
      c += cos(h * pi / 180);
    }
    s /= toma.length;
    c /= toma.length;
    if (sqrt(s * s + c * c) < _consistenciaMinTomaRumbo) {
      avisar('El teléfono se movió durante la toma. Quedate quieto y probá '
          'de nuevo.');
      return;
    }
    final precisa = (_precisionBrujula ?? 999) <= 15;
    if (!await _fijarRotacion(atan2(s, c) * 180 / pi) || !mounted) return;
    avisar(precisa
        ? 'Offset guardado: ${_rotacionMapa.toStringAsFixed(0)}°'
        : 'Offset guardado: ${_rotacionMapa.toStringAsFixed(0)}°, con la '
            'brújula imprecisa. Calibrala (un 8 en el aire) y repetí.');
  }

  // -- Calibración de posición: toma multi-muestra ---------------------------

  /// Inicia la acumulación de lecturas BLE por beacon durante
  /// [_duracionTomaActual].
  /// Cada llamada a [_actualizarSenales] incrementa el contador mientras
  /// [_tomandoMuestras] es true.
  void _iniciarTomaCalibracion() {
    if (_celdaCalSeleccionada == null) return;
    _acumCal.clear();
    _inicioToma = DateTime.now();
    _sumSenoRumbo = 0;
    _sumCosRumbo = 0;
    _muestrasRumbo = 0;
    if (mounted) {
      setState(() {
        _tomandoMuestras = true;
        _muestrasAcumuladas = 0;
      });
    }
  }

  /// Registra una calibración en la celda seleccionada usando las muestras
  /// acumuladas. Calcula la mediana truncada por beacon (igual que
  /// [ProcesadorSenal.filtrarYPromediar]) para obtener un RSSI representativo
  /// y luego deriva el txPower con el modelo log-distancia.
  /// BUG CORREGIDO (la calibracion "se trababa" tras cargar varias):
  /// [_guardarCalibracionAcumulada] se llama desde el callback de scan SIN
  /// await y no tenia guardia de reentrada. `_tomandoMuestras` recien pasaba a
  /// false DESPUES de los dos awaits (insert + relectura de la tabla), asi que
  /// durante esa ventana cada nuevo callback —decenas por segundo con
  /// `continuousUpdates`— volvia a entrar y disparaba OTRO insert de la misma
  /// medicion. Una sola toma generaba decenas de filas duplicadas.
  ///
  /// Y el problema se realimentaba: cuantas mas filas tenia la tabla, mas
  /// tardaba `obtenerCalibracionesPorPiso`, mas larga era la ventana de
  /// reentrada y mas duplicados se insertaban. Con la cola de sqflite saturada
  /// y el hilo de UI decodificando cientos de filas JSON por segundo, la
  /// pantalla se congelaba y la toma nunca llegaba a "guardada". Por eso
  /// aparecia recien "tras haber cargado unas cuantas".
  ///
  /// Se arregla con dos cosas: una guardia [_guardandoCalibracion] y, sobre
  /// todo, apagar `_tomandoMuestras` de forma SINCRONICA antes del primer
  /// await, que es lo que cierra la ventana de raiz.
  bool _guardandoCalibracion = false;

  Future<void> _guardarCalibracionAcumulada() async {
    if (_guardandoCalibracion) return;
    final celda = _celdaCalSeleccionada;
    if (celda == null || _acumCal.isEmpty) return;

    // Antes de cualquier await: el callback de scan no puede volver a entrar.
    _guardandoCalibracion = true;
    _tomandoMuestras = false;
    _inicioToma = null;

    final cx = _grilla.centroX(celda.ix);
    final cy = _grilla.centroY(celda.iy);
    final nExp = ProcesadorSenal.pathLossExponent;

    final lecturas = <Map<String, dynamic>>[];
    final txAjustado = <String, double>{};

    for (final entry in _acumCal.entries) {
      final mac = entry.key;
      final muestras = entry.value;
      // Ahora son lecturas reales (sin las copias que antes inflaban la
      // cuenta): un beacon oído menos de [_minMuestrasCalibracion] veces en
      // toda la toma está en el límite del alcance y su promedio es ruido.
      // Antes cualquier beacon que figurara en la lista sumaba decenas de
      // copias, y pasaba aunque se hubiera oído una sola vez.
      if (muestras.length < _minMuestrasCalibracion) continue;

      // Mediana truncada al 20% en cada extremo (igual que ProcesadorSenal).
      final ord = List<double>.from(muestras)..sort();
      final corte = (ord.length * 0.20).round().clamp(1, ord.length ~/ 3);
      final interior = ord.length > 2 * corte
          ? ord.sublist(corte, ord.length - corte)
          : ord;
      final rssiMedio = interior.reduce((a, b) => a + b) / interior.length;

      if (rssiMedio <= -95 || rssiMedio >= 0) continue;
      lecturas.add({'mac': mac, 'rssi': rssiMedio});

      final b = _beaconsEnElMapa[mac];
      if (b != null) {
        final dxm = (b.posicion.dx - cx) * _escalaX;
        final dym = (b.posicion.dy - cy) * _escalaY;
        final dRaw = sqrt(dxm * dxm + dym * dym);
        final d = dRaw < 0.1 ? 0.1 : dRaw;
        txAjustado[mac] = rssiMedio + 10 * nExp * (log(d) / ln10);
      }
    }

    if (lecturas.isEmpty) {
      _guardandoCalibracion = false;
      if (mounted) {
        setState(() {
          _muestrasAcumuladas = 0;
          _acumCal.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se acumularon lecturas válidas. Activá el escáner.')),
        );
      }
      return;
    }

    // Un fingerprint con pocos beacons no identifica una celda: cualquier punto
    // del pasillo daria parecido. Mejor rechazarlo que guardar un patron que
    // despues va a mandar la posicion a la celda equivocada.
    if (_tomaEsFingerprint && lecturas.length < 3) {
      _guardandoCalibracion = false;
      if (mounted) {
        setState(() {
          _muestrasAcumuladas = 0;
          _acumCal.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            'Punto clave no guardado: se ven ${lecturas.length} beacon(s) y '
            'hacen falta 3.',
          )),
        );
      }
      return;
    }

    final etiqueta = _etiquetaCalCtrl.text.trim();
    final registro = CalibracionRegistro(
      pisoId: widget.pisoId,
      celdaIx: celda.ix,
      celdaIy: celda.iy,
      lecturasBle: lecturas,
      txPowerAjustado: txAjustado,
      timestamp: DateTime.now(),
      etiqueta: etiqueta.isEmpty ? null : etiqueta,
      esFingerprint: _tomaEsFingerprint,
      // Solo tiene sentido en un punto clave: en una calibracion comun el
      // rumbo no se usa para nada.
      rumboCaptura: _tomaEsFingerprint ? _rumboMedioToma : null,
    );

    try {
      await DatabaseHelper.instance.guardarCalibracion(registro);
      final nuevas = await DatabaseHelper.instance.obtenerCalibracionesPorPiso(widget.pisoId);
      if (mounted) {
        setState(() {
          _calibraciones = nuevas;
          _acumCal.clear();
          _muestrasAcumuladas = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            'Calibración registrada en (${celda.ix},${celda.iy}) '
            'con ${lecturas.length} beacons.',
          )),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando calibración: $e')),
        );
      }
    } finally {
      // Pase lo que pase, la guardia se libera: si quedara trabada en true,
      // no se podria calibrar nunca mas sin reiniciar la pantalla.
      _guardandoCalibracion = false;
    }
  }

  /// Elimina las filas duplicadas que dejo el bug de reentrada descrito en
  /// [_guardarCalibracionAcumulada].
  ///
  /// Los duplicados son identicos en celda y en lecturas (salen del mismo
  /// `_acumCal`), solo cambia el id y el timestamp por milisegundos. Se conserva
  /// el de menor id de cada grupo. Dos calibraciones legitimas de la misma
  /// celda tomadas en momentos distintos NUNCA tienen lecturas identicas al
  /// dBm, asi que no corren riesgo.
  Future<void> _limpiarCalibracionesDuplicadas() async {
    try {
      final borradas = await DatabaseHelper.instance
          .eliminarCalibracionesDuplicadas(widget.pisoId);
      final nuevas = await DatabaseHelper.instance
          .obtenerCalibracionesPorPiso(widget.pisoId);
      if (!mounted) return;
      setState(() => _calibraciones = nuevas);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(borradas == 0
            ? 'No había duplicados.'
            : 'Se eliminaron $borradas calibraciones duplicadas.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error limpiando duplicados: $e')),
        );
      }
    }
  }

  Future<void> _eliminarCalibracion(CalibracionRegistro c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar calibración?'),
        content: Text(c.etiqueta ?? 'Celda (${c.celdaIx},${c.celdaIy})'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || c.id == null) return;
    try {
      await DatabaseHelper.instance.eliminarCalibracion(c.id!);
      final nuevas = await DatabaseHelper.instance.obtenerCalibracionesPorPiso(widget.pisoId);
      if (mounted) setState(() => _calibraciones = nuevas);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error eliminando calibración: $e')),
        );
      }
    }
  }

  // -- Escala (puntos desplazables, como las zonas) --------------------------
  //
  // Antes el largo y el ancho se marcaban ARRASTRANDO una línea elástica y
  // los metros se pedían apenas se soltaba el dedo: no había forma de afinar
  // un extremo antes de cargar la medida. Ahora es el mismo sistema que el de
  // las zonas prohibidas:
  //   1. Tocar → primer punto, enganchado al dedo para afinarlo sin soltar.
  //   2. Tocar → segundo punto (imantado al primero). "Medida del largo".
  //   3. Tocar → tercer punto (imantado al segundo, perpendicular al largo).
  //      "Medida del ancho" calcula y guarda la escala.
  // Cualquier punto ya marcado se arrastra para corregirlo; con la medición
  // completa, soltarlo recalcula y guarda la escala. Un segundo dedo hace
  // zoom (y descarta el punto si se acababa de crear en ese gesto).

  /// Se puede agregar un punto: los dos del largo, y el del ancho una vez que
  /// el largo tiene su medida.
  bool get _admitePuntoEscala =>
      _puntosEscala.length < 2 ||
      (_puntosEscala.length == 2 && _largoMetros != null);

  bool get _faltaMedidaLargo =>
      _puntosEscala.length >= 2 && _largoMetros == null;

  bool get _faltaMedidaAncho =>
      _puntosEscala.length >= 3 && _anchoMetros == null;

  bool get _medicionEscalaCompleta =>
      _puntosEscala.length >= 3 && _largoMetros != null && _anchoMetros != null;

  void _reiniciarMedicion() {
    if (!mounted) return;
    setState(() {
      _puntosEscala.clear();
      _largoMetros = null;
      _anchoMetros = null;
      _puntoArrastrado = null;
      _puntoEscalaReciente = false;
      _limpiarGuias();
    });
  }

  /// Quita el último punto marcado, y con él la medida que dependía de él.
  void _quitarUltimoPuntoEscala() {
    if (!mounted || _puntosEscala.isEmpty) return;
    setState(() {
      _puntosEscala.removeLast();
      if (_puntosEscala.length < 3) _anchoMetros = null;
      if (_puntosEscala.length < 2) _largoMetros = null;
      _puntoArrastrado = null;
      _puntoEscalaReciente = false;
      _limpiarGuias();
    });
  }

  /// Devuelve el índice del punto de escala más cercano a [n] si está dentro del
  /// radio de agarre, o null si el toque no cae sobre ningún punto ya marcado.
  int? _puntoCercano(Offset n) {
    int? mejorIdx;
    double mejorDist = 1.0;
    for (int i = 0; i < _puntosEscala.length; i++) {
      final d = _distanciaEnRadios(_puntosEscala[i], n, _radioAgarrePunto);
      if (d <= mejorDist) {
        mejorDist = d;
        mejorIdx = i;
      }
    }
    return mejorIdx;
  }

  /// Lleva el punto [idx] a [n], imantado contra sus vecinos.
  void _moverPuntoEscala(int idx, Offset n) {
    if (idx < 0 || idx >= _puntosEscala.length) return;
    final a = _anclasEscala(idx);
    final p = _aplicarAsistente(n, ancla: a.ancla, anclaSecundaria: a.sec);
    setState(() => _puntosEscala[idx] = p);
  }

  void _onArrastreInicio(Offset n) {
    if (!mounted) return;

    // 1) ¿El dedo cayó sobre un punto ya marcado? → se arrastra ese.
    final idx = _puntoCercano(n);
    if (idx != null) {
      setState(() {
        _puntoArrastrado = idx;
        _puntoEscalaReciente = false;
      });
      _moverPuntoEscala(idx, n);
      return;
    }

    // 2) Punto nuevo, si en este paso corresponde uno, enganchado al dedo.
    //    Con el largo marcado pero sin medida, primero va la medida.
    if (!_admitePuntoEscala) return;
    final idxNuevo = _puntosEscala.length;
    setState(() {
      _puntosEscala.add(n);
      _puntoArrastrado = idxNuevo;
      _puntoEscalaReciente = true;
    });
    // El imantado se evalúa con el punto ya en la lista, para que el
    // asistente lo alinee con el anterior.
    _moverPuntoEscala(idxNuevo, n);
  }

  void _onArrastreActualizar(Offset n) {
    if (!mounted || _puntoArrastrado == null) return;
    _moverPuntoEscala(_puntoArrastrado!, n);
  }

  /// El usuario apoyó un segundo dedo para hacer zoom: si el punto se acababa
  /// de crear en este gesto se descarta; si ya existía se deja donde quedó.
  void _onArrastreCancelar() {
    if (!mounted) return;
    setState(() {
      _limpiarGuias();
      if (_puntoEscalaReciente && _puntosEscala.isNotEmpty) {
        _puntosEscala.removeLast();
      }
      _puntoArrastrado = null;
      _puntoEscalaReciente = false;
    });
  }

  Future<void> _onArrastreFin() async {
    if (!mounted) return;
    final movido = _puntoArrastrado != null;
    setState(() {
      _puntoArrastrado = null;
      _puntoEscalaReciente = false;
      _limpiarGuias();
    });
    // Con la medición completa, reacomodar un punto recalcula y guarda la
    // escala (los metros de referencia no cambian).
    if (movido && _medicionEscalaCompleta) {
      await _recalcularYGuardarEscala(mostrarAviso: false);
    }
  }

  /// Pide los metros del segmento que los está esperando: el largo (P1→P2) o
  /// el ancho (P2→P3). Con el ancho la medición queda completa y la escala se
  /// guarda. Si se cancela el diálogo, los puntos quedan donde están.
  Future<void> _ponerMedidaEscala() async {
    if (_faltaMedidaLargo) {
      final metros = await _pedirMetros('Largo de la línea',
          '¿Cuántos metros mide el largo en la realidad?');
      if (metros == null || !mounted) return;
      setState(() => _largoMetros = metros);
    } else if (_faltaMedidaAncho) {
      final metros = await _pedirMetros('Ancho de la línea',
          '¿Cuántos metros mide el ancho en la realidad?');
      if (metros == null || !mounted) return;
      setState(() => _anchoMetros = metros);
      await _recalcularYGuardarEscala(mostrarAviso: true);
    }
  }

  /// Con el largo y el ancho ya medidos (y sus metros de referencia guardados),
  /// calcula la escala por eje a partir de las posiciones ACTUALES de los puntos
  /// y persiste el resultado. No borra los puntos: quedan en pantalla para poder
  /// reacomodarlos y recalcular. [mostrarAviso] muestra el SnackBar de confirmación
  /// (true al completar la medición; false en los reajustes finos de puntos).
  Future<void> _recalcularYGuardarEscala({required bool mostrarAviso}) async {
    final largoMetros = _largoMetros;
    final anchoMetros = _anchoMetros;
    if (largoMetros == null || anchoMetros == null || _puntosEscala.length < 3) {
      return;
    }

    final largoSeg = _puntosEscala[1] - _puntosEscala[0];
    final anchoSeg = _puntosEscala[2] - _puntosEscala[1];

    // Componente normalizada mínima para no dividir por ~0 (segmento perpendicular).
    const eps = 0.02;
    double comp(double c) => c.abs() < eps ? eps : c.abs();

    // Cada segmento define la escala del eje en el que es dominante: la escala
    // (metros por unidad normalizada completa) se extrapola desde la fracción
    // del plano que cubre el segmento.
    final bool largoEsX = largoSeg.dx.abs() >= largoSeg.dy.abs();
    double escalaX, escalaY;
    if (largoEsX) {
      escalaX = largoMetros / comp(largoSeg.dx);
      escalaY = anchoMetros / comp(anchoSeg.dy);
    } else {
      escalaY = largoMetros / comp(largoSeg.dy);
      escalaX = anchoMetros / comp(anchoSeg.dx);
    }

    try {
      await DatabaseHelper.instance.actualizarEscalaPiso(widget.pisoId, escalaX, escalaY);
      if (mounted) {
        setState(() {
          _escalaX = escalaX;
          _escalaY = escalaY;
          _grilla = GrillaNav(metrosX: escalaX, metrosY: escalaY, tamCeldaMetros: _tamCelda);
          // Medición completa: los puntos SIGUEN en pantalla para reacomodarlos.
        });
        if (mostrarAviso) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              'Escala guardada: ${escalaX.toStringAsFixed(1)} × ${escalaY.toStringAsFixed(1)} m '
              '(grilla de ${_grilla.celdasX} × ${_grilla.celdasY}, celdas de ${_tamCelda.toStringAsFixed(1)} m).',
            )),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando escala: $e')),
        );
      }
    }
  }

  /// Cambia el lado de celda de la grilla (0.5–1.0 m), regenera la grilla con
  /// la escala actual y persiste el valor. No requiere re-medir la escala.
  Future<void> _cambiarTamCelda(double valor) async {
    // Redondear al paso de 0.1 m para evitar ruido de coma flotante del Slider.
    final v = (valor * 10).round() / 10;
    if (v == _tamCelda) return;
    if (mounted) {
      setState(() {
        _tamCelda = v;
        _grilla = GrillaNav(metrosX: _escalaX, metrosY: _escalaY, tamCeldaMetros: _tamCelda);
      });
    }
    try {
      await DatabaseHelper.instance.actualizarTamCeldaPiso(widget.pisoId, _tamCelda);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando tamaño de celda: $e')),
        );
      }
    }
  }

  Future<double?> _pedirMetros(String titulo, String mensaje) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mensaje, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'Ej: 12.5',
                suffixText: 'm',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim().replaceAll(',', '.'));
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // -- UI --------------------------------------------------------------------

  /// Botón flotante sobre el mapa que entra y sale del modo borrar. Va encima
  /// del mapa (y no en una fila propia) porque el alto de esta pantalla está
  /// contado: una fila más desbordaría en teléfonos chicos.
  Widget _buildBotonBorrar() {
    // Con una zona a medio dibujar no se entra a borrar: primero hay que
    // cerrarla o descartarla, para no perder los puntos marcados.
    final bloqueado =
        !_modoBorrar && _modo == _ModoEdicion.zonas && _verticesEnCurso.isNotEmpty;
    final activo = _borrando;
    final Color fondo = activo
        ? TemaApp.zonaRestringidaRelleno
        : TemaApp.fondoSurface.withValues(alpha: 0.92);
    final Color frente = bloqueado
        ? TemaApp.textoSecundario
        : (activo ? Colors.white : TemaApp.zonaRestringidaBorde);
    return Semantics(
      button: true,
      toggled: activo,
      label: activo ? 'Salir del modo borrar' : 'Entrar al modo borrar',
      child: Material(
        color: fondo,
        elevation: 3,
        shape: StadiumBorder(
          side: BorderSide(color: frente.withValues(alpha: 0.7), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: bloqueado
              ? null
              : () {
                  if (!mounted) return;
                  setState(() {
                    _modoBorrar = !_modoBorrar;
                    // Entrar a borrar suelta lo que hubiera a medio hacer.
                    _seleccionado = null;
                    _beaconArrastrado = null;
                    _beaconEnMovimiento = false;
                    _beaconTocado = null;
                    _inicioAgarreBeacon = null;
                    _lugarArrastrado = null;
                    _lugarEnMovimiento = false;
                    _lugarTocado = null;
                    _inicioAgarreLugar = null;
                  });
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  activo ? Icons.check_rounded : Icons.delete_outline_rounded,
                  size: 20,
                  color: frente,
                ),
                const SizedBox(width: 6),
                ExcludeSemantics(
                  child: Text(
                    activo ? 'Listo' : 'Borrar',
                    style: TextStyle(
                      color: frente,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _hintTexto() {
    if (_borrando) {
      switch (_modo) {
        case _ModoEdicion.beacons:
          return 'BORRAR: tocá un beacon. "Listo" para salir.';
        case _ModoEdicion.zonas:
          return 'BORRAR: tocá una zona. "Listo" para salir.';
        default:
          return 'BORRAR: tocá un lugar, escalera o ascensor. "Listo" para salir.';
      }
    }
    switch (_modo) {
      case _ModoEdicion.beacons:
        return 'Elegí un dispositivo de la lista y tocá el mapa para ubicarlo. Arrastrá la mira de un beacon para moverlo.';
      case _ModoEdicion.zonas:
        if (_verticesEnCurso.isEmpty) {
          return 'Tocá el mapa para marcar los vértices (mínimo 3). Arrastrá sin soltar para afinar.';
        }
        return '${_verticesEnCurso.length} punto(s). Tocá para agregar, arrastrá para corregir o cerrá la zona.';
      case _ModoEdicion.lugares:
        return 'Tocá el mapa para agregar un lugar, escalera o ascensor. Arrastralo para moverlo; se edita desde la lista.';
      case _ModoEdicion.escala:
        final actual = 'Escala actual: ${_escalaX.toStringAsFixed(1)} m × ${_escalaY.toStringAsFixed(1)} m '
            '(grilla ${_grilla.celdasX}×${_grilla.celdasY}).';
        switch (_puntosEscala.length) {
          case 0:
            return '$actual Marcá el primer punto del LARGO.';
          case 1:
            return '$actual Marcá el segundo punto del LARGO.';
          case 2:
            if (_largoMetros == null) {
              return '$actual Acomodá los puntos y tocá "Medida del largo".';
            }
            return '$actual Largo: ${_largoMetros!.toStringAsFixed(1)} m. Marcá el tercer punto: el ANCHO va desde el segundo.';
        }
        if (_anchoMetros == null) {
          return '$actual Largo: ${_largoMetros?.toStringAsFixed(1)} m. Acomodá el tercer punto y tocá "Medida del ancho".';
        }
        return '$actual Medición lista. Arrastrá los puntos para ajustar o "Reiniciar" para medir de nuevo.';
      case _ModoEdicion.calibracion:
        if (_celdaCalSeleccionada == null) {
          return 'Tocá la celda donde estás parado.';
        }
        final c = _celdaCalSeleccionada!;
        return 'Celda (${c.ix},${c.iy}). Tomá la calibración desde el panel de abajo.';
      case _ModoEdicion.brujula:
        return 'Apuntá el teléfono hacia el "arriba" del plano y tocá "Usar la dirección actual".';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dispositivosVisibles =
        _dispositivosCercanos.where(_coincideFiltro).toList();
    final filtroActivo = _filtroNombre.isNotEmpty;

    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(
          title: const Text('Configuración de Piso'),
          actions: [
            if (_publicando)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: TemaApp.acento,
                    ),
                  ),
                ),
              )
            else ...[
              if (_remoteIdPublicado != null)
                IconButton(
                  onPressed: _eliminarMapaPublicado,
                  icon: const Icon(Icons.cloud_off_rounded),
                  tooltip: 'Eliminar mapa de la nube',
                ),
              IconButton(
                onPressed: _publicarPiso,
                icon: const Icon(Icons.cloud_upload_rounded),
                tooltip: 'Publicar mapa a la nube',
              ),
            ],
          ],
        ),
        body: Column(
        children: [
          // Selector de modo
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            // Scroll horizontal: con 5 modos los segmentos no entran en pantallas
            // angostas. Permite desplazarlos en lugar de provocar overflow.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_ModoEdicion>(
                segments: const [
                  ButtonSegment(
                    value: _ModoEdicion.beacons,
                    icon: Icon(Icons.router),
                    label: Text('Beacons'),
                  ),
                  ButtonSegment(
                    value: _ModoEdicion.zonas,
                    icon: Icon(Icons.block),
                    label: Text('Zonas'),
                  ),
                  ButtonSegment(
                    value: _ModoEdicion.lugares,
                    icon: Icon(Icons.place),
                    label: Text('Lugares'),
                  ),
                  ButtonSegment(
                    value: _ModoEdicion.escala,
                    icon: Icon(Icons.straighten),
                    label: Text('Escala'),
                  ),
                  ButtonSegment(
                    value: _ModoEdicion.calibracion,
                    icon: Icon(Icons.gps_fixed),
                    label: Text('Calibrar'),
                  ),
                  ButtonSegment(
                    value: _ModoEdicion.brujula,
                    icon: Icon(Icons.explore),
                    label: Text('Brújula'),
                  ),
                ],
                selected: {_modo},
                onSelectionChanged: (s) {
                  if (!mounted) return;
                  final nuevoModo = s.first;
                  // Detener brújula si salimos del modo brujula.
                  // La brujula hace falta en el modo brujula Y en calibracion
                  // (los puntos clave guardan el rumbo de captura), asi que solo
                  // se apaga al salir hacia un modo que no la usa.
                  const usanBrujula = {
                    _ModoEdicion.brujula,
                    _ModoEdicion.calibracion,
                  };
                  if (usanBrujula.contains(_modo) &&
                      !usanBrujula.contains(nuevoModo)) {
                    _detenerCompass();
                  }
                  // Al salir del modo calibración: liberar el anclado de posición.
                  if (_modo == _ModoEdicion.calibracion && nuevoModo != _ModoEdicion.calibracion) {
                    _celdaCalSeleccionada = null;
                    _posicionUsuario = null;
                    _tomandoMuestras = false;
                    _acumCal.clear();
                    _muestrasAcumuladas = 0;
                  }
                  setState(() {
                    _modo = nuevoModo;
                    _modoBorrar = false;
                    // Gesto de arrastre que hubiera quedado a medias.
                    _beaconArrastrado = null;
                    _beaconEnMovimiento = false;
                    _beaconTocado = null;
                    _inicioAgarreBeacon = null;
                    _lugarArrastrado = null;
                    _lugarEnMovimiento = false;
                    _lugarTocado = null;
                    _inicioAgarreLugar = null;
                    _verticesEnCurso = [];
                    _seleccionado = null;
                    // Reiniciar la medición de escala al cambiar de modo.
                    _puntosEscala.clear();
                    _largoMetros = null;
                    _anchoMetros = null;
                    _puntoArrastrado = null;
                    _puntoEscalaReciente = false;
                    _verticeArrastrado = null;
                    _verticeReciente = false;
                    _limpiarGuias();
                  });
                  // Las lecturas en vivo de calibración necesitan el escáner activo.
                  if (nuevoModo == _ModoEdicion.calibracion) {
                    _asegurarEscaneando();
                    _iniciarCompass();
                  }
                  // Iniciar brújula en vivo al entrar al modo brujula.
                  if (nuevoModo == _ModoEdicion.brujula) {
                    _iniciarCompass();
                  }
                },
              ),
            ),
          ),

          // Hint contextual
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              _hintTexto(),
              style: TextStyle(
                fontSize: 12,
                color: _borrando
                    ? TemaApp.zonaRestringidaBorde
                    : Colors.grey[600],
                fontWeight: _borrando ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Asistente de trazo: solo tiene sentido donde se dibujan líneas.
          if (_modo == _ModoEdicion.escala || _modo == _ModoEdicion.zonas)
            SizedBox(
              // Alto acotado: el body es un Column con un Expanded abajo y el
              // mapa ocupa 380 px fijos, así que esta fila tiene que sumar lo
              // mínimo para no desbordar en pantallas chicas.
              height: 36,
              child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.architecture,
                    size: 18,
                    color: _asistenteRecto
                        ? TemaApp.guiaAlineacion
                        : TemaApp.textoSecundario,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _modo == _ModoEdicion.zonas
                          ? 'Líneas rectas: imanta a 0°, 45° y 90°'
                          : 'Líneas rectas: imanta a 0° y 90°',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Switch(
                    value: _asistenteRecto,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) {
                      if (!mounted) return;
                      setState(() {
                        _asistenteRecto = v;
                        _limpiarGuias();
                      });
                    },
                  ),
                ],
              ),
              ),
            ),

          // Mapa
          SizedBox(
            height: 380,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                LayoutBuilder(builder: (context, restricciones) {
                _tamVisor = restricciones.biggest;
                return InteractiveViewer(
                  transformationController: _transformMapa,
                  maxScale: _zoomMaximo,
                  // En escala y en zonas, UN dedo dibuja o arrastra puntos, así
                  // que se desactiva el pan de un dedo; el zoom de dos dedos
                  // queda siempre activo (al apoyar el segundo dedo el gesto en
                  // curso se cancela y el InteractiveViewer hace zoom).
                  // En escala, zonas y beacons UN dedo dibuja/arrastra puntos,
                  // así que se desactiva el pan de un dedo; el zoom de dos dedos
                  // queda siempre activo.
                  // En modo borrar nadie dibuja ni arrastra, así que un dedo
                  // vuelve a desplazar el mapa.
                  panEnabled: _borrando ||
                      (_modo != _ModoEdicion.escala &&
                          _modo != _ModoEdicion.zonas &&
                          _modo != _ModoEdicion.beacons &&
                          _modo != _ModoEdicion.lugares),
                  scaleEnabled: true,
                  child: MapaWidget(
                    rutaImagen: widget.rutaImagen,
                    beacons: _beaconsEnElMapa,
                    zonas: _zonas,
                    lugares: _lugares,
                    posicionUsuario: _posicionUsuario,
                    modoEdicion: true,
                    mostrarGrilla: true,
                    grilla: _grilla,
                    // En modo zonas los toques se atienden por los callbacks de
                    // arrastre (apoyar y corregir el vértice en un solo gesto).
                    // En modo borrar no se agrega nada: el toque sobre el
                    // plano vacío no hace nada.
                    onTapMapa: _borrando ||
                            _modo == _ModoEdicion.zonas ||
                            _modo == _ModoEdicion.escala
                        ? null
                        : _onTapMapa,
                    // Tocar un elemento lo borra SÓLO en modo borrar, y sólo
                    // los del modo en que se está (en "Lugares" no se borran
                    // beacons ni zonas por error).
                    onTapBeacon: _borrando && _modo == _ModoEdicion.beacons
                        ? _borrarBeacon
                        : null,
                    onTapLugar: _borrando && _modo == _ModoEdicion.lugares
                        ? _borrarLugar
                        : null,
                    onTapZona: _borrando && _modo == _ModoEdicion.zonas
                        ? _borrarZona
                        : null,
                    // Qué marcador tocó el dedo, para saber qué arrastrar.
                    onAgarreBeacon: !_borrando && _modo == _ModoEdicion.beacons
                        ? _onAgarreBeacon
                        : null,
                    onAgarreLugar: !_borrando && _modo == _ModoEdicion.lugares
                        ? _onAgarreLugar
                        : null,
                    verticesEnCurso: _verticesEnCurso,
                    verticeArrastrado:
                        _modo == _ModoEdicion.zonas ? _verticeArrastrado : null,
                    // Guías del asistente de trazo (magenta punteado).
                    guias: _guias,
                    guiaPunto: _guiaPunto,
                    escalaVista: _escalaVista,
                    // Copia nueva en cada build: el painter compara por
                    // referencia, así que al mover un punto (mutación in-place)
                    // esta copia fuerza el repintado en cada frame del arrastre.
                    puntosMedicion: _modo == _ModoEdicion.escala ? List.of(_puntosEscala) : const [],
                    // Gestos de un dedo: la medición de escala y la edición de
                    // vértices de zonas comparten el mismo canal.
                    // (En modo borrar no hay arrastres: los cuatro quedan
                    // en null.)
                    onArrastreInicio: _borrando
                        ? null
                        : _modo == _ModoEdicion.escala
                        ? _onArrastreInicio
                        : _modo == _ModoEdicion.zonas
                            ? _onArrastreInicioZona
                            : _modo == _ModoEdicion.beacons
                                ? _onArrastreInicioBeacon
                                : _modo == _ModoEdicion.lugares
                                    ? _onArrastreInicioLugar
                                    : null,
                    onArrastreActualizar: _borrando
                        ? null
                        : _modo == _ModoEdicion.escala
                        ? _onArrastreActualizar
                        : _modo == _ModoEdicion.zonas
                            ? _onArrastreActualizarZona
                            : _modo == _ModoEdicion.beacons
                                ? _onArrastreActualizarBeacon
                                : _modo == _ModoEdicion.lugares
                                    ? _onArrastreActualizarLugar
                                    : null,
                    onArrastreFin: _borrando
                        ? null
                        : _modo == _ModoEdicion.escala
                        ? _onArrastreFin
                        : _modo == _ModoEdicion.zonas
                            ? _onArrastreFinZona
                            : _modo == _ModoEdicion.beacons
                                ? _onArrastreFinBeacon
                                : _modo == _ModoEdicion.lugares
                                    ? _onArrastreFinLugar
                                    : null,
                    onArrastreCancelar: _borrando
                        ? null
                        : _modo == _ModoEdicion.escala
                        ? _onArrastreCancelar
                        : _modo == _ModoEdicion.zonas
                            ? _onArrastreCancelarZona
                            : _modo == _ModoEdicion.beacons
                                ? _onArrastreCancelarBeacon
                                : _modo == _ModoEdicion.lugares
                                    ? _onArrastreCancelarLugar
                                    : null,
                    // Se resaltan recién cuando el dedo se movió de verdad:
                    // un toque al lado de un marcador no lo "agarra" a la vista.
                    beaconArrastrado:
                        _modo == _ModoEdicion.beacons && _beaconEnMovimiento
                            ? _beaconArrastrado
                            : null,
                    lugarArrastrado:
                        _modo == _ModoEdicion.lugares && _lugarEnMovimiento
                            ? _lugarArrastrado
                            : null,
                    // Calibración: celda seleccionada (amarillo) + pines de celdas calibradas.
                    celdaResaltada: _modo == _ModoEdicion.calibracion && _celdaCalSeleccionada != null
                        ? Offset(_grilla.centroX(_celdaCalSeleccionada!.ix),
                            _grilla.centroY(_celdaCalSeleccionada!.iy))
                        : null,
                    celdasCalibradas: _modo == _ModoEdicion.calibracion
                        ? _calibraciones
                            .map((c) => Offset(_grilla.centroX(c.celdaIx), _grilla.centroY(c.celdaIy)))
                            .toList()
                        : const [],
                  ),
                );
                }),
                    // Marco rojo: deja a la vista que el mapa está en modo
                    // borrar aunque no se esté mirando el botón.
                    if (_borrando)
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: TemaApp.zonaRestringidaBorde,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    if (_modoAdmiteBorrar)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _buildBotonBorrar(),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Botones de accion para zonas
          if (_modo == _ModoEdicion.zonas)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  // Deshacer el último punto: ahora cualquier toque sobre el
                  // plano crea un vértice, así que hace falta una forma de
                  // sacar uno solo sin descartar la zona entera.
                  IconButton(
                    onPressed: _verticesEnCurso.isNotEmpty ? _quitarUltimoVertice : null,
                    icon: const Icon(Icons.undo),
                    tooltip: 'Quitar último punto',
                    color: Colors.orange,
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _verticesEnCurso.isNotEmpty ? _descartarZonaEnCurso : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Descartar'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _verticesEnCurso.length >= 3 ? _cerrarZona : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Cerrar zona'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]),
                    ),
                  ),
                ],
              ),
            ),

          // Botones de accion para escala
          if (_modo == _ModoEdicion.escala)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  // Igual que en las zonas: deshacer sólo el último punto.
                  IconButton(
                    onPressed: _puntosEscala.isNotEmpty ? _quitarUltimoPuntoEscala : null,
                    icon: const Icon(Icons.undo),
                    tooltip: 'Quitar último punto',
                    color: Colors.orange,
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _puntosEscala.isNotEmpty ? _reiniciarMedicion : null,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reiniciar'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _faltaMedidaLargo || _faltaMedidaAncho
                          ? _ponerMedidaEscala
                          : null,
                      icon: const Icon(Icons.straighten),
                      label: Text(
                        _medicionEscalaCompleta
                            ? 'Escala lista'
                            : _largoMetros == null
                                ? 'Medida del largo'
                                : 'Medida del ancho',
                      ),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]),
                    ),
                  ),
                ],
              ),
            ),

          // Selector de tamaño de celda de la grilla (0.5–1.0 m). Junto a los
          // controles de escala porque define la resolución de la misma grilla.
          if (_modo == _ModoEdicion.escala)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tamaño de celda: ${_tamCelda.toStringAsFixed(1)} m '
                    '(grilla ${_grilla.celdasX}×${_grilla.celdasY})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Slider(
                    value: _tamCelda.clamp(0.5, 1.0),
                    min: 0.5,
                    max: 1.0,
                    divisions: 5, // pasos de 0.1 m: 0.5, 0.6, … 1.0
                    label: '${_tamCelda.toStringAsFixed(1)} m',
                    onChanged: _cambiarTamCelda,
                  ),
                  Text(
                    'Menor = más precisión en espacios chicos. Mayor = grilla más liviana.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

          // Lista de dispositivos BLE
          if (_modo == _ModoEdicion.beacons)
            Expanded(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      _escaneando ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                      color: _escaneando ? Colors.teal : Colors.grey,
                    ),
                    title: Text(_escaneando ? 'Buscando dispositivos...' : 'Escaner detenido'),
                    trailing: ElevatedButton.icon(
                      onPressed: _conmutarEscaner,
                      icon: Icon(_escaneando ? Icons.stop : Icons.play_arrow),
                      label: Text(_escaneando ? 'Detener' : 'Escanear'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _escaneando ? Colors.red : Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  // Filtro por nombre. Mismo alto acotado que la fila del
                  // asistente de trazo (que no aparece en este modo), para no
                  // sumar altura al Column en pantallas chicas.
                  SizedBox(
                    height: 36,
                    child: InkWell(
                      onTap: _pedirFiltroNombre,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 4),
                        child: Row(
                          children: [
                            Icon(
                              filtroActivo ? Icons.filter_alt : Icons.search,
                              size: 18,
                              color: filtroActivo ? Colors.teal : TemaApp.textoSecundario,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                filtroActivo
                                    ? 'Nombre contiene "$_filtroNombre" · '
                                        '${dispositivosVisibles.length} de ${_dispositivosCercanos.length}'
                                    : 'Filtrar por nombre',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (filtroActivo)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Quitar filtro',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _aplicarFiltroNombre(''),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtroActivo &&
                            dispositivosVisibles.isEmpty &&
                            _dispositivosCercanos.isNotEmpty
                        ? Center(
                            child: Text(
                              'Ningún dispositivo coincide con "$_filtroNombre"',
                              style: const TextStyle(color: TemaApp.textoSecundario),
                            ),
                          )
                        : ListView.builder(
                      itemCount: dispositivosVisibles.length,
                      itemBuilder: (context, i) {
                        final d = dispositivosVisibles[i];
                        final mac = d.device.remoteId.str;
                        final yaUbicado = _beaconsEnElMapa.containsKey(mac);
                        final seleccionado = _seleccionado == d;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            yaUbicado ? Icons.check_circle : Icons.bluetooth,
                            color: yaUbicado ? Colors.green : (seleccionado ? Colors.teal : Colors.grey),
                          ),
                          title: Text(d.device.advName.isEmpty ? 'Dispositivo desconocido' : d.device.advName),
                          subtitle: Text('MAC: $mac  |  RSSI: ${d.rssi} dBm'),
                          trailing: seleccionado
                              ? const Icon(Icons.touch_app, color: Colors.teal)
                              : null,
                          onTap: yaUbicado
                              ? null
                              : () {
                                  if (mounted) setState(() => _seleccionado = d);
                                },
                          tileColor: seleccionado ? Colors.teal.withValues(alpha: 0.1) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Lista de lugares de interes
          if (_modo == _ModoEdicion.lugares)
            Expanded(
              child: _lugares.isEmpty
                  ? const Center(child: Text('No hay lugares de interes agregados'))
                  : ListView.builder(
                      itemCount: _lugares.length,
                      itemBuilder: (context, i) {
                        final l = _lugares[i];
                        // Rubro y palabras propias, lo que haya.
                        final rubro = Rubros.porId(l.rubro);
                        final detalle = [
                          if (rubro != null) 'Rubro: ${rubro.nombre}',
                          if (l.palabrasClave.isNotEmpty)
                            'Otras palabras: ${l.palabrasClave.join(', ')}',
                        ].join('\n');
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            !l.esEscalera
                                ? Icons.place
                                : (l.esAscensor ? Icons.elevator : Icons.stairs),
                            color: l.esEscalera ? Colors.orange : Colors.purple,
                          ),
                          title: Text(l.nombre),
                          subtitle: detalle.isEmpty ? null : Text(detalle),
                          // Tocar la fila edita el lugar (nombre, rubro,
                          // descripción, palabras propias).
                          onTap: () => _editarLugar(l),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: TemaApp.acento),
                                tooltip: 'Editar',
                                onPressed: () => _editarLugar(l),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Eliminar',
                                onPressed: () => _borrarLugar(l),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

          // Panel de calibración
          if (_modo == _ModoEdicion.calibracion)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_celdaCalSeleccionada == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Tocá una celda en el mapa para empezar a calibrar.',
                          style: TextStyle(fontSize: 14),
                        ),
                      )
                    else ...[
                      Text(
                        'Celda seleccionada: (${_celdaCalSeleccionada!.ix}, ${_celdaCalSeleccionada!.iy})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _etiquetaCalCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Etiqueta (opcional)',
                          hintText: 'Ej: Entrada, Pasillo norte',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Lecturas BLE actuales (${_beaconsEnElMapa.length} beacons):',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      if (_beaconsEnElMapa.isEmpty)
                        const Text('No hay beacons configurados en este piso.',
                            style: TextStyle(fontSize: 12, color: Colors.grey))
                      else
                        ..._beaconsEnElMapa.values.map((b) {
                          final valido = b.rssiFiltrado > -95 && b.rssiFiltrado < 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(
                                  valido ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                                  size: 16,
                                  color: valido ? TemaApp.acento : TemaApp.textoSecundario,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${b.nombre}  ·  ${b.mac}',
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${b.rssiFiltrado.toStringAsFixed(0)} dBm',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: valido ? TemaApp.textoBlanco : TemaApp.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 12),

                      // ── PUNTO CLAVE (fingerprint) ───────────────────────
                      // Vive dentro del propio modo calibracion: un punto clave
                      // ES una calibracion, solo que medida mas tiempo y
                      // marcada para que ademas se use como patron en vivo.
                      Container(
                        decoration: BoxDecoration(
                          color: _tomaEsFingerprint
                              ? TemaApp.acentoSuave
                              : TemaApp.fondoSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _tomaEsFingerprint
                                ? TemaApp.acento.withValues(alpha: 0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              dense: true,
                              value: _tomaEsFingerprint,
                              onChanged: _tomandoMuestras
                                  ? null
                                  : (v) => setState(() => _tomaEsFingerprint = v),
                              secondary: Icon(
                                Icons.push_pin,
                                color: _tomaEsFingerprint
                                    ? TemaApp.acento
                                    : TemaApp.textoSecundario,
                              ),
                              title: const Text(
                                'Punto clave (fingerprint)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Text(
                                !_tomaEsFingerprint
                                    ? 'Para esquinas donde se dobla, puertas o el pie de '
                                        'una escalera.'
                                    : _headingEnVivo == null
                                        ? 'Medición de ${_duracionFingerprint.inSeconds} s. '
                                            'Sin brújula: se guarda sin rumbo y es menos '
                                            'preciso.'
                                        : 'Medición de ${_duracionFingerprint.inSeconds} s. '
                                            'Mirá hacia donde se llega caminando (ahora: '
                                            '${_headingEnVivo!.toStringAsFixed(0)}°). Si se llega '
                                            'desde dos lados, tomá uno por cada sentido.',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Toma multi-muestra ──────────────────────────────
                      if (_tomandoMuestras) ...[
                        // Barra de progreso y botón cancelar
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _tomaEsFingerprint
                                        ? 'Midiendo punto clave: '
                                            '${(_progresoToma * _duracionTomaActual.inSeconds).round()}'
                                            ' / ${_duracionTomaActual.inSeconds} s'
                                        : 'Tomando muestras: '
                                            '${(_progresoToma * _duracionTomaActual.inSeconds).round()}'
                                            ' / ${_duracionTomaActual.inSeconds} s',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: _progresoToma,
                                    backgroundColor: TemaApp.fondoSurface,
                                    color: TemaApp.acento,
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              onPressed: () {
                                if (mounted) {
                                  setState(() {
                                    _tomandoMuestras = false;
                                    _muestrasAcumuladas = 0;
                                    _acumCal.clear();
                                    _inicioToma = null;
                                  });
                                }
                              },
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text('Cancelar'),
                              style: TextButton.styleFrom(foregroundColor: TemaApp.zonaRestringidaBorde),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _tomaEsFingerprint
                              ? 'No te muevas ni gires. Teléfono como para navegar, '
                                  'mirando siempre hacia el mismo lado. '
                                  '(${_rumboMedioToma == null ? "sin brújula" : "rumbo ${_rumboMedioToma!.toStringAsFixed(0)}°"}'
                                  ' · $_muestrasAcumuladas lecturas)'
                              : 'No te muevas de la celda. '
                                  '($_muestrasAcumuladas lecturas)',
                          style: const TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _escaneando ? _iniciarTomaCalibracion : null,
                            icon: Icon(_tomaEsFingerprint
                                ? Icons.push_pin
                                : Icons.add_location_alt),
                            label: Text(
                              !_escaneando
                                  ? 'Activá el escáner primero'
                                  : _tomaEsFingerprint
                                      ? 'Medir punto clave '
                                          '(${_duracionFingerprint.inSeconds} s)'
                                      : 'Iniciar toma de calibración '
                                          '(${_duracionCalibracion.inSeconds} s)',
                            ),
                          ),
                        ),
                      ],
                    ],
                    const Divider(height: 24),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Calibraciones guardadas (${_calibraciones.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      children: _calibraciones.isEmpty
                          ? [
                              const ListTile(
                                dense: true,
                                title: Text('Todavía no hay calibraciones.'),
                              )
                            ]
                          : <Widget>[
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.cleaning_services,
                                    color: TemaApp.textoSecundario),
                                title: const Text('Quitar duplicados',
                                    style: TextStyle(fontSize: 14)),
                                subtitle: const Text(
                                  'Borra las copias idénticas de una misma toma.',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onTap: _limpiarCalibracionesDuplicadas,
                              ),
                              const Divider(height: 1),
                            ] + _calibraciones.map((c) {
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  c.esFingerprint
                                      ? Icons.push_pin
                                      : Icons.check_circle,
                                  color: c.esFingerprint
                                      ? TemaApp.acento
                                      : Colors.green,
                                ),
                                title: Text(c.etiqueta ?? 'Celda (${c.celdaIx},${c.celdaIy})'),
                                subtitle: Text(
                                    '${c.esFingerprint ? "PUNTO CLAVE · " : ""}'
                                    '${c.esFingerprint && c.rumboCaptura != null ? "rumbo ${c.rumboCaptura!.toStringAsFixed(0)}° · " : ""}'
                                    '${c.esFingerprint && c.rumboCaptura == null ? "sin rumbo · " : ""}'
                                    '${c.lecturasBle.length} beacons · ${_formatearTimestamp(c.timestamp)}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _eliminarCalibracion(c),
                                ),
                              );
                            }).toList(),
                    ),
                  ],
                ),
              ),
            ),

          // ── Panel de calibración de brújula ────────────────────────────────
          if (_modo == _ModoEdicion.brujula)
            Expanded(
              child: _buildPanelBrujula(),
            ),
        ],
      ),
    ),
    );
  }

  /// Panel para calibrar la rotación del mapa respecto al norte real.
  ///
  /// El operador apunta el teléfono hacia lo que en el plano es "arriba" y
  /// toca "Usar la dirección actual": se promedia el heading unos segundos y
  /// ese es el offset. El slider y los presets quedan para ajustar a mano.
  /// Todo se guarda solo. El valor guardado (rotacion_mapa, en grados) es el
  /// offset que PantallaNavegacion resta al heading de FlutterCompass para
  /// alinear la brújula con el plano.
  Widget _buildPanelBrujula() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instrucción
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TemaApp.acentoSuave,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TemaApp.acento.withValues(alpha: 0.4)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, color: TemaApp.acento, size: 18),
                  SizedBox(width: 8),
                  Text('Cómo calibrar', style: TextStyle(color: TemaApp.acento, fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
                SizedBox(height: 6),
                Text(
                  '1. Si la precisión no es alta, hacé un 8 en el aire.\n'
                  '2. Apuntá el borde superior del teléfono hacia el "arriba" del plano.\n'
                  '3. Tocá "Usar la dirección actual" y quedate quieto 2 s.\n'
                  'Se guarda solo. El ajuste fino va con el slider.',
                  style: TextStyle(color: TemaApp.textoBlanco, fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Visualizador de flecha en vivo
          Center(
            child: Column(
              children: [
                Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TemaApp.fondoSurface,
                    border: Border.all(color: TemaApp.acento.withValues(alpha: 0.4), width: 2),
                  ),
                  child: Center(
                    child: _headingEnVivo == null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 28, height: 28,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: TemaApp.acento),
                              ),
                              const SizedBox(height: 8),
                              const Text('Esperando\nbrújula...', textAlign: TextAlign.center,
                                  style: TextStyle(color: TemaApp.textoSecundario, fontSize: 12)),
                            ],
                          )
                        : AnimatedRotation(
                            // La flecha muestra el heading COMPENSADO: (heading_real - offset).
                            // Cuando el offset esté bien calibrado, la flecha apuntará exactamente
                            // hacia ARRIBA cuando el teléfono mire el borde superior del mapa.
                            // Al mover el slider, la flecha se mueve en tiempo real → el operador
                            // ajusta hasta que la flecha quede derecha con el teléfono apuntando
                            // al borde superior del plano.
                            turns: ((_headingEnVivo! - _rotacionMapa) % 360 + 360) % 360 / 360,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.navigation, color: TemaApp.acento, size: 80),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _headingEnVivo != null
                      ? 'Norte magnético: ${_headingEnVivo!.toStringAsFixed(0)}°  |  Offset actual: ${_rotacionMapa.toStringAsFixed(0)}°'
                      : 'Sin señal de brújula',
                  style: const TextStyle(color: TemaApp.textoSecundario, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _indicadorPrecisionBrujula(),
          const SizedBox(height: 16),

          // Toma promediada del rumbo: la forma principal de calibrar.
          SizedBox(
            width: double.infinity,
            height: TemaApp.targetTactil,
            child: ElevatedButton.icon(
              onPressed: _headingEnVivo == null || _tomaRumbo != null
                  ? null
                  : _tomarDireccionActual,
              icon: _tomaRumbo != null
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: TemaApp.fondo),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: Text(_tomaRumbo != null
                  ? 'Midiendo… quedate quieto'
                  : 'Usar la dirección actual'),
            ),
          ),
          const SizedBox(height: 24),

          // Slider de offset: ajuste fino. Se guarda al soltarlo.
          Text(
            'Ajuste fino: ${_rotacionMapa.toStringAsFixed(0)}°',
            style: const TextStyle(color: TemaApp.textoBlanco, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '0° = Norte arriba · 90° = Este arriba · 180° = Sur arriba · 270° = Oeste arriba',
            style: const TextStyle(color: TemaApp.textoSecundario, fontSize: 12),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: TemaApp.acento,
              thumbColor: TemaApp.acento,
              inactiveTrackColor: TemaApp.fondoSurface,
              overlayColor: TemaApp.acento.withValues(alpha: 0.15),
              valueIndicatorColor: TemaApp.acento,
              valueIndicatorTextStyle: const TextStyle(color: TemaApp.fondo, fontWeight: FontWeight.bold),
            ),
            child: Slider(
              value: _rotacionMapa.clamp(0.0, 359.0),
              min: 0,
              max: 359,
              divisions: 359,
              label: '${_rotacionMapa.toStringAsFixed(0)}°',
              onChanged: (v) {
                if (mounted) setState(() => _rotacionMapa = v.roundToDouble());
              },
              onChangeEnd: _fijarRotacion,
            ),
          ),

          // Botones de presets rápidos
          const SizedBox(height: 4),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              for (final preset in [
                (label: 'Norte (0°)', valor: 0.0),
                (label: 'Este (90°)', valor: 90.0),
                (label: 'Sur (180°)', valor: 180.0),
                (label: 'Oeste (270°)', valor: 270.0),
              ])
                OutlinedButton(
                  onPressed: () => _fijarRotacion(preset.valor),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TemaApp.acento,
                    side: BorderSide(color: TemaApp.acento.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(preset.label, style: const TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Precisión del sensor de la brújula, con la indicación de calibrarlo
  /// cuando no es alta (ver [_precisionBrujula]).
  Widget _indicadorPrecisionBrujula() {
    if (_headingEnVivo == null) return const SizedBox.shrink();
    final p = _precisionBrujula;
    final alta = p != null && p <= 15;
    final texto = alta
        ? 'Precisión de la brújula: alta.'
        : p == null
            ? 'Precisión de la brújula: desconocida. Hacé un 8 en el aire '
                'antes de calibrar.'
            : p <= 30
                ? 'Precisión de la brújula: media. Hacé un 8 en el aire hasta '
                    'que sea alta.'
                : 'Precisión de la brújula: baja. Hacé un 8 en el aire hasta '
                    'que sea alta.';
    final color = alta ? TemaApp.instruccionAccent : TemaApp.advertencia;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alta ? TemaApp.instruccion : TemaApp.fondoAdvertencia,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            alta ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: color, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  String _formatearTimestamp(DateTime t) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(t.day)}/${dos(t.month)} ${dos(t.hour)}:${dos(t.minute)}';
  }
}


// ─── DIÁLOGO DE ALTA DE LUGAR / ESCALERA ────────────────────────────────────

/// Resultado del diálogo de alta.
class _DatosNuevoLugar {
  final String nombre;
  final TipoLugar tipo;
  final bool sube;
  final bool baja;
  final double? direccionEntrada;
  final List<String> palabrasClave;
  final String? rubro;
  final bool esAscensor;

  const _DatosNuevoLugar({
    required this.nombre,
    this.tipo = TipoLugar.comun,
    this.sube = false,
    this.baja = false,
    this.direccionEntrada,
    this.palabrasClave = const [],
    this.rubro,
    this.esAscensor = false,
  });
}

/// Conexiones posibles de una escalera desde el piso donde se carga.
enum _SentidoEscalera { sube, baja, ambas }

class _DialogoNuevoLugar extends StatefulWidget {
  /// Lugar que se está editando. Null = alta de uno nuevo.
  final LugarInteres? inicial;

  const _DialogoNuevoLugar({this.inicial});

  @override
  State<_DialogoNuevoLugar> createState() => _DialogoNuevoLugarState();
}

class _DialogoNuevoLugarState extends State<_DialogoNuevoLugar> {
  final _nombreCtrl = TextEditingController();
  final _clavesCtrl = TextEditingController();

  TipoLugar _tipo = TipoLugar.comun;
  _SentidoEscalera? _sentido;
  double? _direccion; // 0 arriba, 90 derecha, 180 abajo, 270 izquierda

  /// Id del rubro elegido (null = sin rubro).
  String? _rubro;

  /// Con tipo escalera: si lo que se está cargando es un ascensor.
  bool _esAscensor = false;

  /// "la escalera" / "el ascensor", para los textos del diálogo.
  String get _elMedio => _esAscensor ? 'el ascensor' : 'la escalera';

  bool get _editando => widget.inicial != null;

  @override
  void initState() {
    super.initState();
    final l = widget.inicial;
    if (l == null) return;
    _nombreCtrl.text = l.nombre;
    _clavesCtrl.text = LugarInteres.palabrasATexto(l.palabrasClave) ?? '';
    // Si el mapa trae un rubro que esta versión no conoce, se muestra como
    // "sin rubro" (el desplegable exige que el valor exista en la lista).
    _rubro = Rubros.porId(l.rubro)?.id;
    _tipo = l.tipo;
    if (l.esEscalera) {
      _esAscensor = l.esAscensor;
      _sentido = l.sube && l.baja
          ? _SentidoEscalera.ambas
          : l.sube
              ? _SentidoEscalera.sube
              : l.baja
                  ? _SentidoEscalera.baja
                  : null;
      _direccion = l.direccionEntrada;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _clavesCtrl.dispose();
    super.dispose();
  }

  bool get _esEscalera => _tipo == TipoLugar.escalera;

  /// Muestra de las palabras que trae el rubro elegido, para que el admin
  /// vea con qué se va a encontrar el lugar.
  String get _ayudaRubro {
    final r = Rubros.porId(_rubro);
    if (r == null) {
      return 'Permite encontrarlo por lo que es ("quiero comer", "un '
          'kiosco").';
    }
    const muestra = 6;
    final palabras = r.palabras.take(muestra).join(', ');
    return 'Se encuentra diciendo: $palabras'
        '${r.palabras.length > muestra ? '…' : ''}';
  }

  /// Abre el catálogo de rubros. Al volver, el desplegable se rearma con lo
  /// que haya quedado y, si se borró el rubro elegido, queda "Sin rubro".
  Future<void> _administrarRubros() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PantallaRubros()),
    );
    if (!mounted) return;
    setState(() => _rubro = Rubros.porId(_rubro)?.id);
  }

  /// Qué falta para poder guardar (null = se puede guardar).
  String? get _faltante {
    if (!_esEscalera) {
      return _nombreCtrl.text.trim().isEmpty ? 'Escribí un nombre' : null;
    }
    if (_sentido == null) return 'Elegí si sube, baja o ambas';
    if (_direccion == null) return 'Elegí hacia dónde da la entrada';
    return null;
  }

  void _guardar() {
    if (_faltante != null) return;
    if (!_esEscalera) {
      Navigator.pop(
        context,
        _DatosNuevoLugar(
          nombre: _nombreCtrl.text.trim(),
          palabrasClave: LugarInteres.palabrasDesdeTexto(_clavesCtrl.text),
          rubro: _rubro,
        ),
      );
      return;
    }
    final nombre = _nombreCtrl.text.trim();
    Navigator.pop(
      context,
      _DatosNuevoLugar(
        nombre: nombre.isEmpty
            ? (_esAscensor ? 'Ascensor' : 'Escalera')
            : nombre,
        tipo: TipoLugar.escalera,
        esAscensor: _esAscensor,
        sube: _sentido == _SentidoEscalera.sube ||
            _sentido == _SentidoEscalera.ambas,
        baja: _sentido == _SentidoEscalera.baja ||
            _sentido == _SentidoEscalera.ambas,
        direccionEntrada: _direccion,
      ),
    );
  }

  Widget _botonDireccion(double grados, IconData icono, String etiqueta) {
    final elegido = _direccion == grados;
    return Semantics(
      button: true,
      selected: elegido,
      label: 'Entrada hacia $etiqueta del plano',
      child: SizedBox(
        width: 56,
        height: 56,
        child: ElevatedButton(
          onPressed: () => setState(() => _direccion = grados),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: elegido ? TemaApp.acento : TemaApp.acentoSuave,
            foregroundColor: elegido ? TemaApp.fondo : TemaApp.textoBlanco,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Icon(icono, size: 28),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(!_esEscalera
          ? (_editando ? 'Editar lugar' : 'Nuevo lugar de interés')
          : _esAscensor
              ? (_editando ? 'Editar ascensor' : 'Nuevo ascensor')
              : (_editando ? 'Editar escalera' : 'Nueva escalera')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<TipoLugar>(
              segments: const [
                ButtonSegment(
                  value: TipoLugar.comun,
                  icon: Icon(Icons.place),
                  label: Text('Lugar'),
                ),
                ButtonSegment(
                  value: TipoLugar.escalera,
                  icon: Icon(Icons.stairs),
                  // Escalera o ascensor: se elige abajo, al entrar acá.
                  label: Text('Escalera'),
                ),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nombreCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: !_esEscalera
                    ? 'Nombre (ej: Baño, Terminal 5)'
                    : _esAscensor
                        ? 'Nombre (opcional, ej: Ascensor norte)'
                        : 'Nombre (opcional, ej: Escalera norte)',
                border: const OutlineInputBorder(),
              ),
            ),
            if (!_esEscalera) ...[
              const SizedBox(height: 12),
              // Rubro: trae cargadas las palabras con las que la gente pide
              // ese tipo de lugar (ver rubros.dart).
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Rubro',
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  helperText: _ayudaRubro,
                  helperMaxLines: 3,
                ),
                child: DropdownButtonHideUnderline(
                  // "Sin rubro" va como texto vacío y no como null: para el
                  // desplegable, null significa "no hay nada elegido" y
                  // dejaría el campo EN BLANCO en vez de mostrar "Sin rubro".
                  child: DropdownButton<String>(
                    value: _rubro ?? '',
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: _OpcionRubro(
                          icono: Icons.label_off_outlined,
                          nombre: 'Sin rubro',
                          apagada: true,
                        ),
                      ),
                      for (final r in Rubros.todos)
                        DropdownMenuItem<String>(
                          value: r.id,
                          child: _OpcionRubro(
                            icono: iconoRubro(r.id),
                            nombre: r.nombre,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(
                        () => _rubro = (v == null || v.isEmpty) ? null : v),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _administrarRubros,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  icon: const Icon(Icons.tune, size: 20),
                  label: const Text('Editar rubros'),
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _clavesCtrl,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  labelText: 'Otras palabras (opcional)',
                  hintText: 'el mac, mc',
                  helperText:
                      'Apodos o marcas de este lugar, separados por comas. Lo '
                      'general ya lo pone el rubro.',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_esEscalera) ...[
              const SizedBox(height: 16),
              const Text('¿Qué es?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Escalera'),
                    avatar: const Icon(Icons.stairs, size: 18),
                    selected: !_esAscensor,
                    onSelected: (_) => setState(() => _esAscensor = false),
                  ),
                  ChoiceChip(
                    label: const Text('Ascensor'),
                    avatar: const Icon(Icons.elevator, size: 18),
                    selected: _esAscensor,
                    onSelected: (_) => setState(() => _esAscensor = true),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Desde este piso, $_elMedio:',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Sube'),
                    avatar: const Icon(Icons.north, size: 18),
                    selected: _sentido == _SentidoEscalera.sube,
                    onSelected: (_) =>
                        setState(() => _sentido = _SentidoEscalera.sube),
                  ),
                  ChoiceChip(
                    label: const Text('Baja'),
                    avatar: const Icon(Icons.south, size: 18),
                    selected: _sentido == _SentidoEscalera.baja,
                    onSelected: (_) =>
                        setState(() => _sentido = _SentidoEscalera.baja),
                  ),
                  ChoiceChip(
                    label: const Text('Sube y baja'),
                    avatar: const Icon(Icons.swap_vert, size: 18),
                    selected: _sentido == _SentidoEscalera.ambas,
                    onSelected: (_) =>
                        setState(() => _sentido = _SentidoEscalera.ambas),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('¿Hacia qué lado del plano da la entrada?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                _esAscensor
                    ? 'El lado de la puerta, según el plano en pantalla.'
                    : 'El lado por donde se entra a la escalera, según el '
                        'plano en pantalla.',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Center(
                child: Column(
                  children: [
                    _botonDireccion(0, Icons.arrow_upward, 'arriba'),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _botonDireccion(270, Icons.arrow_back, 'la izquierda'),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(
                            _esAscensor ? Icons.elevator : Icons.stairs,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _botonDireccion(90, Icons.arrow_forward, 'la derecha'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _botonDireccion(180, Icons.arrow_downward, 'abajo'),
                  ],
                ),
              ),
            ],
            if (_faltante != null) ...[
              const SizedBox(height: 12),
              Text(
                _faltante!,
                style: const TextStyle(color: TemaApp.advertencia, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _faltante == null ? _guardar : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Opción del desplegable de rubros: ícono del rubro y su nombre.
class _OpcionRubro extends StatelessWidget {
  final IconData icono;
  final String nombre;

  /// Para "Sin rubro": ícono y texto en gris.
  final bool apagada;

  const _OpcionRubro({
    required this.icono,
    required this.nombre,
    this.apagada = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icono,
          size: 20,
          color: apagada ? TemaApp.textoSecundario : TemaApp.acento,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            nombre,
            overflow: TextOverflow.ellipsis,
            style: apagada
                ? const TextStyle(color: TemaApp.textoSecundario)
                : null,
          ),
        ),
      ],
    );
  }
}