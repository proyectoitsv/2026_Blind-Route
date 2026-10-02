import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'database.dart';
import 'procesador_senal.dart';
import 'bluetooth_helper.dart';
import 'pantalla_naveg.dart';
import 'supabase_service.dart';
import 'voz_service.dart';
import 'tema.dart';
import 'piso_util.dart';
 
class ModoAutomatico extends StatefulWidget {
  const ModoAutomatico({super.key});
 
  @override
  State<ModoAutomatico> createState() => _ModoAutomaticoState();
}
 
class _ModoAutomaticoState extends State<ModoAutomatico> {
  bool _navegando = false;
  bool _resolviendo = false; // en medio de resolver una llegada (chequeo/descarga)
  String _estado = 'Iniciando...';
  int _beaconsDetectados = 0;

  // Optimización de red: no consultar la nube en cada barrido. Se recuerdan las
  // MACs que ya se consultaron sin resultado y se limita la frecuencia.
  final Set<String> _macsSinMapa = {};
  DateTime? _ultimaConsultaNube;

  Timer? _timeoutTimer;
  Timer? _mapaTimer;

  // ── ELECCIÓN DEL PISO DE LLEGADA ───────────────────────────────────────────
  //
  // En un edificio de varios pisos se ven beacons de más de un piso a la vez
  // (el hormigón atenúa, no bloquea). Antes se entraba al piso del PRIMER
  // beacon que aparecía en el barrido, que es un orden arbitrario: estando en
  // el piso 1 podía arrancar en el 2.
  //
  // Ahora se acumulan unos segundos de señal y se elige el piso con la señal
  // más fuerte: los beacons del piso donde está el usuario llegan bastante
  // más fuerte que los de arriba o abajo.

  /// Índice "MAC de beacon → id de piso" de TODOS los mapas guardados, y los
  /// datos de cada piso. Se carga una sola vez (una consulta) al arrancar y
  /// se recarga sólo si se descarga un mapa nuevo. Evita consultar la base
  /// por cada dispositivo de cada barrido: en un lugar concurrido se ven
  /// decenas de dispositivos ajenos por segundo.
  Map<String, int> _pisoDeMac = {};
  Map<int, Map<String, dynamic>> _infoPiso = {};

  /// Momento en que se vio por primera vez un beacon con mapa local.
  DateTime? _inicioVentanaPiso;

  /// Tiempo mínimo de escucha antes de elegir piso. La diferencia de señal
  /// entre pisos es grande, así que alcanza con unos pocos barridos.
  static const Duration _ventanaEleccionPiso = Duration(seconds: 3);

  /// Tope: si a los 6 s sigue habiendo empate, se elige igual el más fuerte.
  static const Duration _ventanaMaxEleccionPiso = Duration(seconds: 6);

  /// Diferencia (dB) a partir de la cual un piso se considera claramente más
  /// fuerte que el segundo. Por debajo de esto se sigue escuchando.
  static const double _margenPisoDb = 4.0;

  /// Beacons por piso que se promedian para puntuar (los más fuertes).
  static const int _beaconsPorPiso = 3;

  /// Cuántas MACs desconocidas se mandan a la nube al preguntar si este lugar
  /// tiene mapa. Se eligen las más fuertes: las lejanas no aportan y agrandan
  /// el pedido (uso de datos móviles).
  static const int _maxMacsConsultaNube = 10;

  /// Tope del set de MACs ya descartadas, para que no crezca sin límite en un
  /// lugar concurrido.
  static const int _maxMacsSinMapa = 500;

  /// Último texto de estado escrito, para no llamar a setState (y redibujar)
  /// en cada barrido cuando el texto no cambió.
  String _ultimoEstadoEscrito = '';
 
  // Procesador compartido que se pasara a PantallaNavegacion
  final ProcesadorSenal _procesador = ProcesadorSenal();
  final VozService _voz = VozService();
 
  @override
  void initState() {
    super.initState();
    _iniciarBusqueda();
  }
 
  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _mapaTimer?.cancel();
    // NO detenemos el scan aqui - PantallaNavegacion lo necesita activo
    // Solo cancelamos si no navegamos
    if (!_navegando) {
      BluetoothHelper.detenerScanSeguro(dueno: this);
    }
    super.dispose();
  }
 
  /// Carga (o recarga) el índice de beacons locales. También le declara al
  /// procesador cuáles son las MACs de beacons conocidos: sin esa lista
  /// acumula historial de RSSI de todos los dispositivos del ambiente.
  Future<void> _cargarIndiceBeacons() async {
    try {
      final filas = await DatabaseHelper.instance.obtenerIndiceBeaconsLocales();
      final pisoDeMac = <String, int>{};
      final infoPiso = <int, Map<String, dynamic>>{};
      for (final f in filas) {
        final pisoId = f['id'] as int;
        pisoDeMac[f['mac'] as String] = pisoId;
        infoPiso.putIfAbsent(pisoId, () => f);
      }
      _pisoDeMac = pisoDeMac;
      _infoPiso = infoPiso;
      _procesador.definirBeaconsRelevantes(pisoDeMac.keys);
      debugPrint('[Índice] ${pisoDeMac.length} beacons en '
          '${infoPiso.length} piso(s) local(es).');
    } catch (e) {
      debugPrint('[Índice] No se pudo cargar: $e');
    }
  }

  /// Actualiza el estado de la pantalla sólo si el texto cambió.
  void _mostrarEstado(String texto, {int? beacons}) {
    if (!mounted || texto == _ultimoEstadoEscrito) return;
    _ultimoEstadoEscrito = texto;
    setState(() {
      _estado = texto;
      if (beacons != null) _beaconsDetectados = beacons;
    });
  }

  Future<void> _iniciarBusqueda() async {
    await _cargarIndiceBeacons();
    if (!mounted) return;
    final ok = await BluetoothHelper.verificarPrecondiciones(context);
    if (!ok) {
      if (mounted) {
        setState(() => _estado = 'Bluetooth o permisos no disponibles.');
      }
      return;
    }
 
    if (mounted) {
      setState(() => _estado = 'Buscando beacons de BlindRoute...');
    }
 
    final scanOk = await BluetoothHelper.iniciarScanSeguro(
      dueno: this,
      onResultados: (resultados) => _procesarResultados(resultados),
      onError: (e) {
        if (mounted) {
          setState(() => _estado = 'Error en scan: $e');
        }
      },
      removeIfGone: const Duration(seconds: 3),
    );
 
    if (!scanOk && mounted) {
      setState(() => _estado = 'No se pudo iniciar el escaneo');
      return;
    }
 
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_navegando && _beaconsDetectados == 0) {
        setState(() => _estado = 'No se encontraron mapas.');
        _voz.hablar('No se encontraron mapas.');
      }
    });
  }
 
  Future<void> _procesarResultados(List<ScanResult> resultados) async {
    if (_navegando || _resolviendo) return;
 
    // Procesar señales para ir llenando la ventana de mediana de cada beacon,
    // así al pasar a PantallaNavegacion (mismo ProcesadorSenal compartido) el
    // filtro ya tiene historial y la ubicación se estabiliza más rápido.
    //
    // En el mismo recorrido se agrupan los beacons conocidos POR PISO con su
    // RSSI filtrado. Todo sale del índice en memoria: cero consultas a la base
    // por barrido.
    final macsDesconocidas = <String, int>{}; // mac → rssi crudo
    final evidencia = <int, _EvidenciaPiso>{};
    for (var res in resultados) {
      final mac = res.device.remoteId.str;
      final pisoId = _pisoDeMac[mac];
      if (pisoId == null) {
        macsDesconocidas[mac] = res.rssi;
        continue;
      }
      // Mediana del procesador si ya tiene historial; si no, la lectura cruda.
      final rssi =
          _procesador.filtrarYPromediar(mac, res.rssi) ?? res.rssi.toDouble();
      final info = _infoPiso[pisoId];
      if (info == null) continue;
      evidencia
          .putIfAbsent(pisoId, () => _EvidenciaPiso(info))
          .rssiPorMac[mac] = rssi;
    }

    // 1) Elegir el piso con más señal, tras unos segundos de escucha.
    if (evidencia.isNotEmpty) {
      final ahoraEv = DateTime.now();
      _inicioVentanaPiso ??= ahoraEv;
      final escuchado = ahoraEv.difference(_inicioVentanaPiso!);

      final ranking = evidencia.values.toList()
        ..sort((a, b) => b.puntaje(_beaconsPorPiso)
            .compareTo(a.puntaje(_beaconsPorPiso)));
      final mejor = ranking.first;
      final ventaja = ranking.length == 1
          ? double.infinity
          : mejor.puntaje(_beaconsPorPiso) -
              ranking[1].puntaje(_beaconsPorPiso);
      final decidido = escuchado >= _ventanaEleccionPiso &&
          (ventaja >= _margenPisoDb || escuchado >= _ventanaMaxEleccionPiso);

      if (!decidido) {
        // Todavía escuchando: mostrar el candidato actual.
        _mostrarEstado(
          'Detectando piso: ${mejor.nombrePiso} '
          '(${mejor.puntaje(_beaconsPorPiso).toStringAsFixed(0)} dBm)...',
          beacons: evidencia.values
              .fold<int>(0, (n, e) => n + e.rssiPorMac.length),
        );
        return;
      }

      final detalle = ranking
          .map((e) =>
              '${e.nombrePiso} ${e.puntaje(_beaconsPorPiso).toStringAsFixed(1)} dBm '
              '(${e.rssiPorMac.length})')
          .join(' | ');
      debugPrint('[Piso] Elegido ${mejor.nombrePiso}. Candidatos: $detalle');

      _resolviendo = true;
      await _resolverLlegadaLocal(mejor.info);
      return;
    }

    // Sin beacons con mapa local: se reinicia la ventana de elección.
    _inicioVentanaPiso = null;

    // 2) No hay mapa local. Buscar en la nube y autodescargar. Optimización:
    //    se consulta una sola vez por conjunto de MACs (se recuerdan las que no
    //    tienen mapa) y como mucho cada 10 s, para no golpear el servidor en
    //    cada barrido si el lugar no tiene mapa o no hay conexión.
    // Se consultan sólo las MACs desconocidas MÁS FUERTES: las lejanas no
    // aportan y agrandan el pedido.
    final candidatas = macsDesconocidas.entries
        .where((e) => !_macsSinMapa.contains(e.key))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final macs = candidatas
        .take(_maxMacsConsultaNube)
        .map((e) => e.key)
        .toList();

    final ahora = DateTime.now();
    final hayMacsNuevas = macs.isNotEmpty;
    final pasoThrottle = _ultimaConsultaNube == null ||
        ahora.difference(_ultimaConsultaNube!) > const Duration(seconds: 10);
    if (macs.isNotEmpty &&
        hayMacsNuevas &&
        pasoThrottle &&
        SupabaseService.instance.configurado) {
      _ultimaConsultaNube = ahora;
      _resolviendo = true;
      try {
        final remoteId = await SupabaseService.instance.buscarMapaPorMacs(macs);
        if (remoteId != null && !_navegando) {
          if (mounted) {
            setState(() => _estado = 'Descargando mapa de este lugar...');
          }
          _voz.hablar('Descargando el mapa de este lugar.');
          await SupabaseService.instance.descargarMapa(remoteId);
          // No se navega acá: el mapa ya es local, así que el próximo barrido
          // entra por la rama de arriba y elige el piso por señal (el mapa
          // descargado puede tener beacons de varios pisos).
          await _cargarIndiceBeacons();
          _inicioVentanaPiso = null;
          _mostrarEstado('Mapa descargado. Detectando piso...');
          return;
        } else if (remoteId == null) {
          // No hay mapa para estas MACs: no volver a consultarlas.
          if (_macsSinMapa.length > _maxMacsSinMapa) _macsSinMapa.clear();
          _macsSinMapa.addAll(macs);
        }
      } catch (e) {
        // Error / sin datos: no se marcan como "sin mapa" para poder reintentar
        // cuando vuelva la conexión (limitado por el throttle de 10 s).
      } finally {
        if (!_navegando) _resolviendo = false;
      }
    }
 
    // 3) Feedback de dispositivos detectados sin mapa (comportamiento de siempre)
    if (mounted && !_navegando && !_resolviendo && macsDesconocidas.isNotEmpty) {
      _mostrarEstado(
        'Detectados ${macsDesconocidas.length} dispositivo(s)...',
        beacons: macsDesconocidas.length,
      );
      // Iniciar timer de mapa solo una vez, cuando aparecen beacons sin mapa
      _mapaTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted && !_navegando && !_resolviendo) {
          setState(() => _estado = 'Mapa no encontrado.');
          _voz.hablar('Mapa no encontrado.');
        }
      });
    }
  }

  /// Resuelve la llegada a un lugar con mapa ya descargado.
  ///
  /// Con conexión, pone al día el edificio contra la nube en una sola
  /// consulta (ver [SupabaseService.sincronizarEdificio]):
  ///  - si el admin ELIMINÓ el mapa de este piso, ya se quitó del teléfono:
  ///    no se navega con él y se vuelve a escuchar beacons;
  ///  - si hay una versión más nueva de este piso, avisa por voz y la baja;
  ///  - si faltan o cambiaron otros pisos del edificio, los baja (para ir a
  ///    un lugar de otro piso hacen falta todos).
  ///
  /// Sin conexión, si tarda demasiado o si falla, navega con lo que ya está
  /// en el teléfono: nunca deja al usuario esperando.
  Future<void> _resolverLlegadaLocal(Map<String, dynamic> info) async {
    final pisoId = info['id'] as int;
    final remoteId = info['remote_id'] as String?;
    final edificioId = info['edificio_id'] as int?;
    final edificio = info['edificio_nombre'] as String?;

    // true si ya se avisó por voz que se está bajando el mapa de este lugar.
    var avisoDescarga = false;

    if (edificioId != null &&
        edificio != null &&
        SupabaseService.instance.configurado) {
      try {
        final resultado = await SupabaseService.instance.sincronizarEdificio(
          edificioId: edificioId,
          edificioNombre: edificio,
        );
        avisoDescarga = await _descargarPendientes(
          resultado.pendientes,
          remoteId: remoteId,
          reemplazo: remoteId != null && resultado.eliminados.contains(remoteId),
        );
      } catch (e) {
        // Sin datos / timeout / error: se sigue con lo que haya en el teléfono.
        debugPrint('[Llegada] No se pudo sincronizar con la nube: $e');
      }
    }

    // La base local manda. Se relee el piso: si se re-descargó trae los datos
    // nuevos (mismo id local, la descarga actualiza en el lugar), y si ya no
    // está es que el admin lo eliminó.
    final fresco = await DatabaseHelper.instance.obtenerPisoInfo(pisoId);

    if (fresco == null) {
      // Mapa eliminado: no se navega con él. Se recarga el índice (sus beacons
      // dejan de ser conocidos) y se vuelve a escuchar. Si el admin publicó
      // otro en su lugar, ya se bajó recién o lo encuentra la autodescarga
      // por beacon del próximo barrido.
      await _cargarIndiceBeacons();
      if (!mounted) return;
      _inicioVentanaPiso = null;
      if (!avisoDescarga) {
        _voz.hablar('El mapa de este lugar ya no está disponible.');
      }
      _mostrarEstado('Buscando el mapa de este lugar...');
      _resolviendo = false;
      return;
    }

    _irANavegacion({
      ...info,
      'ruta_imagen': fresco.rutaImagen,
      'escala_metros': fresco.escalaX,
      'escala_metros_alto': fresco.escalaY,
      'tam_celda_metros': fresco.tamCeldaMetros,
      'rotacion_mapa': fresco.rotacionMapa,
    });
  }

  /// Baja los pisos [pendientes] del edificio: los que faltan en el teléfono
  /// o tienen una versión más nueva. El piso donde está el usuario va primero.
  /// Devuelve true si se avisó por voz que se baja el mapa de ESTE lugar.
  ///
  /// Nunca bloquea la llegada: tiene un tope de tiempo y, si no hay conexión
  /// o falla, se sigue con los pisos que ya estén en el teléfono. Lo que se
  /// haya bajado antes del corte queda guardado (cada piso es una transacción
  /// aparte).
  ///
  /// [reemplazo]: el mapa de este piso fue eliminado por el admin, así que lo
  /// que se baja es lo que haya publicado en su lugar.
  Future<bool> _descargarPendientes(
    List<String> pendientes, {
    required String? remoteId,
    required bool reemplazo,
  }) async {
    if (pendientes.isEmpty) return false;

    final estePendiente = remoteId != null && pendientes.contains(remoteId);
    final esEsteLugar = estePendiente || reemplazo;
    if (mounted) {
      setState(() => _estado = esEsteLugar
          ? 'Actualizando mapa...'
          : 'Descargando los otros pisos del edificio...');
    }
    _voz.hablar(esEsteLugar
        ? 'Actualizando el mapa de este lugar.'
        : 'Descargando los otros pisos.');

    try {
      if (remoteId != null && estePendiente) {
        await SupabaseService.instance
            .descargarMapa(remoteId)
            .timeout(const Duration(seconds: 20));
      }
      final limite = DateTime.now().add(const Duration(seconds: 30));
      for (final id in pendientes) {
        if (id == remoteId) continue;
        final restante = limite.difference(DateTime.now());
        if (restante <= Duration.zero) break;
        await SupabaseService.instance.descargarMapa(id).timeout(restante);
      }
    } catch (e) {
      // Sin datos / timeout / error: se sigue con lo que haya en el teléfono.
      debugPrint('[Edificio] No se pudieron completar los pisos: $e');
    }
    return esEsteLugar;
  }

  /// Pasa a la pantalla de navegación con los datos del piso (local).
  void _irANavegacion(Map<String, dynamic> info) {
    _navegando = true;
    _timeoutTimer?.cancel();
    _mapaTimer?.cancel();

    // IMPORTANTE: Indicar que NO se detenga el scan al dispose
    BluetoothHelper.mantenerScanActivo = true;

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PantallaNavegacion(
            pisoId: info['id'],
            rutaImagen: info['ruta_imagen'],
            escalaX: (info['escala_metros'] as num?)?.toDouble() ?? 50,
            escalaY: (info['escala_metros_alto'] as num?)?.toDouble() ?? 50,
            tamCeldaMetros:
                (info['tam_celda_metros'] as num?)?.toDouble() ?? 1.0,
            rotacionMapa: (info['rotacion_mapa'] as num?)?.toDouble() ?? 0.0,
            procesadorCompartido: _procesador, // Pasar el mismo procesador
          ),
        ),
      );
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: TemaApp.acento,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _estado,
                style: const TextStyle(fontSize: 22, color: TemaApp.textoBlanco, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              if (_beaconsDetectados > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '$_beaconsDetectados dispositivo(s) en rango',
                    style: const TextStyle(fontSize: 15, color: TemaApp.textoSecundario),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Señal acumulada de un piso durante la ventana de elección.
class _EvidenciaPiso {
  /// Fila del piso (la que devuelve obtenerInfoPorBeacon).
  final Map<String, dynamic> info;

  /// RSSI filtrado (dBm) de cada beacon de ESTE piso que se está viendo.
  final Map<String, double> rssiPorMac = {};

  _EvidenciaPiso(this.info);

  /// Promedio de los [cantidad] beacons más fuertes del piso. Se promedian
  /// varios en vez de usar sólo el más fuerte para que un rebote puntual no
  /// decida el piso, y se toman los más fuertes para no castigar a un piso
  /// por tener beacons lejanos cargados.
  double puntaje(int cantidad) {
    if (rssiPorMac.isEmpty) return -999;
    final valores = rssiPorMac.values.toList()..sort((a, b) => b.compareTo(a));
    final n = valores.length < cantidad ? valores.length : cantidad;
    var suma = 0.0;
    for (int i = 0; i < n; i++) {
      suma += valores[i];
    }
    return suma / n;
  }

  String get nombrePiso {
    final numero = info['numero_piso'] as int?;
    if (numero != null) return PisoUtil.nombre(numero);
    return (info['nombre_piso'] as String?) ?? 'Piso';
  }
}