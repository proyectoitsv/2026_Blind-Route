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
import 'design/design.dart';

enum _ModoEdicion { beacons, zonas, lugares, escala, calibracion, brujula }

/// Configuración de un piso (app del administrador): beacons, zonas
/// prohibidas, lugares, escala, calibración y brújula, sobre el plano.
///
/// ─── Sistema de diseño (fase 5.6 del rediseño) ───
/// Va envuelta en AmbienteDiseno: la barra con las acciones de la nube, los
/// modos en una fila de chips, el plano hundido y, debajo, el panel de cada
/// modo. Ver "UI" más abajo.
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

  /// Potencia mínima (dBm) para que un dispositivo aparezca en la lista. Con
  /// [_sinPotenciaMinima] aparecen todos.
  int _potenciaMinima = _sinPotenciaMinima;
  static const int _sinPotenciaMinima = -100;
  bool _publicando = false;

  /// Con [_publicando]: si lo que se está haciendo es eliminar el mapa de la
  /// nube (sólo cambia lo que se ve mientras tanto).
  bool _eliminandoDeLaNube = false;
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

  /// Si la lista de calibraciones guardadas está a la vista (arranca
  /// plegada, como antes).
  bool _verCalibraciones = false;

  /// Una clave por chip de modo, para centrar el elegido en la fila.
  final Map<_ModoEdicion, GlobalKey> _clavesChipModo = {
    for (final modo in _ModoEdicion.values) modo: GlobalKey(),
  };

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
    final a = atan2(
      _sumSenoRumbo / _muestrasRumbo,
      _sumCosRumbo / _muestrasRumbo,
    );
    return (a * 180 / pi + 360) % 360;
  }

  Duration get _duracionTomaActual =>
      _tomaEsFingerprint ? _duracionFingerprint : _duracionCalibracion;

  /// Progreso de la toma en `[0,1]`, por tiempo transcurrido.
  double get _progresoToma {
    final inicio = _inicioToma;
    if (inicio == null) return 0;
    final t =
        DateTime.now().difference(inicio).inMilliseconds /
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
  double? _largoMetros; // metros del largo (P1→P2)
  double? _anchoMetros; // metros del ancho (P2→P3)

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
    final p = _aplicarAsistente(
      n,
      ancla: a.ancla,
      anclaSecundaria: a.sec,
      diagonales: true,
    );
    _moverVertice(idx, p);
  }

  @override
  void initState() {
    super.initState();
    _escalaX = widget.escalaX;
    _escalaY = widget.escalaY;
    _tamCelda = widget.tamCeldaMetros;
    _grilla = GrillaNav(
      metrosX: _escalaX,
      metrosY: _escalaY,
      tamCeldaMetros: _tamCelda,
    );
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
      final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(
        widget.pisoId,
      );
      final zonas = await DatabaseHelper.instance.obtenerZonasPorPiso(
        widget.pisoId,
      );
      final lugares = await DatabaseHelper.instance.obtenerLugaresPorPiso(
        widget.pisoId,
      );
      final calibraciones = await DatabaseHelper.instance
          .obtenerCalibracionesPorPiso(widget.pisoId);

      // Leer rotación del mapa guardada.
      final db = await DatabaseHelper.instance.database;
      final filas = await db.query(
        'pisos',
        columns: ['rotacion_mapa', 'remote_id'],
        where: 'id = ?',
        whereArgs: [widget.pisoId],
        limit: 1,
      );
      final rotGuardada = filas.isNotEmpty
          ? ((filas.first['rotacion_mapa'] as num?)?.toDouble() ?? 0.0)
          : 0.0;
      final remoteId = filas.isNotEmpty
          ? filas.first['remote_id'] as String?
          : null;

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
      _avisar('Error cargando datos: $e', error: true);
    }
  }

  /// Los avisos de la pantalla (mostrarAviso): abajo, se van solos a los 4 s
  /// y TalkBack los lee. Los errores, en rojo y con el ícono.
  void _avisar(String texto, {bool error = false}) {
    if (!mounted) return;
    mostrarAviso(context, texto, error: error);
  }

  Future<void> _sincronizarBeacons() async {
    try {
      await DatabaseHelper.instance.guardarBeacons(
        widget.pisoId,
        _beaconsEnElMapa.values.toList(),
      );
    } catch (e) {
      _avisar('Error guardando beacons: $e', error: true);
    }
  }

  // -- Publicar a la nube (Supabase) -----------------------------------------

  /// Sube este piso completo (plano + beacons + zonas + lugares + calibraciones)
  /// a la nube para que los usuarios lo puedan descargar. Idempotente: si el
  /// piso ya se había publicado, reemplaza su versión remota (no duplica).
  Future<void> _publicarPiso() async {
    if (_publicando) return;

    if (!SupabaseService.instance.configurado) {
      _avisar(
        'Falta configurar Supabase (supabase_config.dart) para publicar.',
        error: true,
      );
      return;
    }

    if (_beaconsEnElMapa.isEmpty) {
      _avisar('Cargá al menos un beacon antes de publicar el mapa.');
      return;
    }

    setState(() => _publicando = true);
    try {
      // Asegurar que lo último quede persistido localmente antes de subir.
      await _sincronizarBeacons();

      final info = await DatabaseHelper.instance.obtenerPisoConEdificio(
        widget.pisoId,
      );
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

      await DatabaseHelper.instance.guardarRemoteIdPiso(
        widget.pisoId,
        remoteId,
      );

      if (!mounted) return;
      final republicado = (info['remote_id'] as String?) != null;
      setState(() => _remoteIdPublicado = remoteId);
      _avisar(
        republicado
            ? 'Mapa actualizado en la nube'
            : 'Mapa publicado. Ya se puede descargar.',
      );
    } catch (e) {
      _avisar('Error al publicar: $e', error: true);
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  /// Borra de la nube el mapa que este admin publicó. El servidor sólo lo
  /// permite si es el dueño; si es de otro administrador, devuelve error.
  Future<void> _eliminarMapaPublicado() async {
    final remoteId = _remoteIdPublicado;
    if (remoteId == null || _publicando) return;

    final confirmar = await mostrarConfirmacion(
      context,
      titulo: 'Eliminar de la nube',
      mensaje:
          'Se quita del catálogo y se borra de los teléfonos que ya lo '
          'tienen.',
      confirmar: 'Eliminar',
      destructiva: true,
      iconoConfirmar: Icons.cloud_off_rounded,
    );
    if (!confirmar || !mounted) return;

    setState(() {
      _publicando = true;
      _eliminandoDeLaNube = true;
    });
    try {
      await SupabaseService.instance.eliminarMapa(remoteId);
      await DatabaseHelper.instance.limpiarRemoteIdPiso(widget.pisoId);
      if (!mounted) return;
      setState(() => _remoteIdPublicado = null);
      _avisar('Mapa eliminado de la nube');
    } catch (e) {
      _avisar('Error al eliminar: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _publicando = false;
          _eliminandoDeLaNube = false;
        });
      }
    }
  }

  // -- Beacons ---------------------------------------------------------------

  void _borrarBeacon(String mac) async {
    try {
      final nombre = _beaconsEnElMapa[mac]?.nombre ?? 'Beacon';
      final confirmar = await mostrarConfirmacion(
        context,
        titulo: '¿Eliminar beacon?',
        mensaje: 'Se eliminará "$nombre" ($mac) de este piso.',
        confirmar: 'Eliminar',
        destructiva: true,
        iconoConfirmar: Icons.delete_rounded,
      );
      if (!confirmar || !mounted) return;
      setState(() => _beaconsEnElMapa.remove(mac));
      await _sincronizarBeacons();
      _avisar('Beacon eliminado');
    } catch (e) {
      _avisar('Error eliminando beacon: $e', error: true);
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
      b.posicion = Offset(
        destino.dx.clamp(0.0, 1.0),
        destino.dy.clamp(0.0, 1.0),
      );
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
      _avisar('Bluetooth o permisos no disponibles', error: true);
      return;
    }

    if (mounted) setState(() => _escaneando = true);

    final scanOk = await BluetoothHelper.iniciarScanSeguro(
      dueno: this,
      onResultados: (resultados) {
        if (!mounted) return;
        _actualizarPotenciaLista(resultados);
        setState(() => _dispositivosCercanos = resultados);
        _actualizarSenales(resultados);
      },
      onError: (e) => _avisar('Error en scan: $e', error: true),
    );

    if (!scanOk && mounted) {
      setState(() => _escaneando = false);
    }
  }

  // -- Potencia de la lista de dispositivos -----------------------------------
  //
  // La lista se muestra de más fuerte a más débil: el beacon que el operador
  // tiene al lado queda arriba y no hay que buscarlo entre todo el tráfico
  // Bluetooth del lugar. Ordenar por la última lectura no sirve: el RSSI salta
  // 5 a 10 dB de una lectura a la otra, la lista se reacomodaría a cada rato y
  // es fácil tocar otro dispositivo justo cuando cambia de lugar. Por eso se
  // ordena por la mediana de las lecturas de los últimos
  // [_ventanaPotenciaLista], contando sólo las nuevas (ver
  // [_ultimaLecturaBeacon]: el plugin repite la última lectura de cada
  // dispositivo en todos los callbacks).

  static const Duration _ventanaPotenciaLista = Duration(seconds: 2);
  final Map<String, List<({DateTime t, int rssi})>> _lecturasLista = {};

  void _actualizarPotenciaLista(List<ScanResult> resultados) {
    final limite = DateTime.now().subtract(_ventanaPotenciaLista);
    for (final r in resultados) {
      final lecturas = _lecturasLista.putIfAbsent(
        r.device.remoteId.str,
        () => [],
      );
      if (lecturas.isEmpty || r.timeStamp.isAfter(lecturas.last.t)) {
        lecturas.add((t: r.timeStamp, rssi: r.rssi));
      }
      lecturas.removeWhere((l) => l.t.isBefore(limite));
    }
  }

  /// Potencia con la que se ordena y se filtra [r] en la lista: la mediana de
  /// sus lecturas recientes, o la última si todavía tiene menos de 3.
  int _potenciaDe(ScanResult r) {
    final lecturas = _lecturasLista[r.device.remoteId.str];
    if (lecturas == null || lecturas.length < 3) return r.rssi;
    final ordenadas = [for (final l in lecturas) l.rssi]..sort();
    return ordenadas[ordenadas.length ~/ 2];
  }

  // -- Filtro de dispositivos por nombre y potencia ---------------------------

  bool get _filtroActivo =>
      _filtroNombre.isNotEmpty || _potenciaMinima > _sinPotenciaMinima;

  /// `true` si el nombre anunciado de [r] contiene el filtro (sin distinguir
  /// mayúsculas) y llega a la potencia mínima. Se compara contra `advName`,
  /// que es el mismo nombre que se muestra en la lista.
  ///
  /// El dispositivo elegido no se oculta por potencia: la potencia sube y baja
  /// sola, y si desapareciera de la lista justo antes de tocar el mapa se
  /// ubicaría un beacon que no se ve.
  bool _coincideFiltro(ScanResult r) {
    if (_filtroNombre.isNotEmpty &&
        !r.device.advName.toLowerCase().contains(_filtroNombre.toLowerCase())) {
      return false;
    }
    return _potenciaMinima <= _sinPotenciaMinima ||
        r == _seleccionado ||
        _potenciaDe(r) >= _potenciaMinima;
  }

  void _aplicarFiltro(String nombre, int potenciaMinima) {
    if (!mounted) return;
    setState(() {
      _filtroNombre = nombre;
      _potenciaMinima = potenciaMinima;
      // Si el dispositivo elegido quedó oculto se descarta la selección: si no,
      // un toque en el mapa ubicaría un beacon que ya no se ve en la lista.
      if (_seleccionado != null && !_coincideFiltro(_seleccionado!)) {
        _seleccionado = null;
      }
    });
  }

  /// Pide el filtro en una hoja. No se usa un campo fijo bajo el mapa: al
  /// abrirse el teclado quedaría tapado. La hoja sube con el teclado.
  Future<void> _pedirFiltro() async {
    final filtro = await mostrarHoja<({String nombre, int potencia})>(
      context,
      titulo: 'Filtrar dispositivos',
      // La cierran "Cancelar", volver o tocar afuera.
      botonCerrar: false,
      contenido: (context) => _HojaFiltro(
        nombre: _filtroNombre,
        potencia: _potenciaMinima,
        hayFiltro: _filtroActivo,
      ),
    );
    if (filtro == null) return;
    _aplicarFiltro(filtro.nombre, filtro.potencia);
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
    if (_modo == _ModoEdicion.calibracion && _celdaCalSeleccionada != null) {
      return;
    }

    try {
      var activos = _beaconsEnElMapa.values
          .where((b) => b.rssiFiltrado > -95)
          .toList();
      if (activos.length < 2) return;
      // Misma multilateración que la navegación (ver [Posicionador]): el
      // centroide ponderado se sesgaba hacia el centro del layout.
      final obs = <ObservacionRango>[];
      for (var b in activos) {
        final tx = ProcesadorSenal.txPowerCalibrado(b.mac, _calibraciones);
        final d = ProcesadorSenal.rssiADistanciaConTx(b.rssiFiltrado, tx);
        obs.add(ObservacionRango(b.posicion, d, 1.0 / (d + 1.0)));
      }
      final p = Posicionador.estimar(
        obs,
        metrosX: _grilla.metrosX,
        metrosY: _grilla.metrosY,
        posPrevia: _posicionUsuario,
        factorMovimiento: 0.5,
      );
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
      _avisar('Necesitás al menos 3 puntos para cerrar la zona.');
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
      _avisar('Error guardando zona: $e', error: true);
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
      final confirmar = await mostrarConfirmacion(
        context,
        titulo: '¿Eliminar zona?',
        mensaje: 'Se eliminará "${zona.nombre}".',
        confirmar: 'Eliminar',
        destructiva: true,
        iconoConfirmar: Icons.delete_rounded,
      );
      if (!confirmar) return;
      await DatabaseHelper.instance.eliminarZona(zona.id!);
      if (mounted) {
        setState(() => _zonas = _zonas.where((z) => z.id != zona.id).toList());
      }
    } catch (e) {
      _avisar('Error eliminando zona: $e', error: true);
    }
  }

  /// El nombre de la zona que se cierra, en una hoja. null: se canceló (y la
  /// zona en curso se descarta, como antes).
  Future<String?> _pedirNombreZona() => mostrarHoja<String>(
    context,
    titulo: 'Nombre de la zona',
    botonCerrar: false,
    contenido: (context) => const _HojaNombreZona(),
  );

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
        _verticesEnCurso = _verticesEnCurso.sublist(
          0,
          _verticesEnCurso.length - 1,
        );
      }
      _verticeArrastrado = null;
      _verticeReciente = false;
    });
  }

  /// Quita el último vértice marcado (deshacer un toque de más).
  void _quitarUltimoVertice() {
    if (!mounted || _verticesEnCurso.isEmpty) return;
    setState(() {
      _verticesEnCurso = _verticesEnCurso.sublist(
        0,
        _verticesEnCurso.length - 1,
      );
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
    final datos = await mostrarHoja<_DatosNuevoLugar>(
      context,
      titulo: 'Nuevo lugar',
      botonCerrar: false,
      contenido: (context) => const _HojaLugar(),
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
      _avisar('Error guardando lugar: $e', error: true);
    }
  }

  /// Edita un lugar ya cargado (nombre, rubro, descripción, palabras clave
  /// y, si es escalera, sus datos). Se abre tocándolo en la lista de abajo; la
  /// posición no cambia acá (para eso se arrastra en el mapa).
  Future<void> _editarLugar(LugarInteres lugar) async {
    if (lugar.id == null) return;
    final datos = await mostrarHoja<_DatosNuevoLugar>(
      context,
      titulo: !lugar.esEscalera
          ? 'Editar lugar'
          : lugar.esAscensor
          ? 'Editar ascensor'
          : 'Editar escalera',
      botonCerrar: false,
      contenido: (context) => _HojaLugar(inicial: lugar),
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
          _lugares = _lugares
              .map((l) => l.id == editado.id ? editado : l)
              .toList();
        });
      }
    } catch (e) {
      _avisar('Error guardando los cambios: $e', error: true);
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
    final mitadEscalera = lado > 0
        ? MapaWidget.anchoEscaleraMetros * 0.75 / lado
        : 0.0;
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
        final dIcono = _distanciaAgarre(
          l.posicion,
          Offset(n.dx, n.dy + bajarY),
        );
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
    final l =
        (tocado == null
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
    final nueva = Offset(
      destino.dx.clamp(0.0, 1.0),
      destino.dy.clamp(0.0, 1.0),
    );
    setState(() {
      // Se reasigna la lista (no se muta in-place) para que el mapa se
      // entere del cambio, igual que con las zonas.
      _lugares = _lugares
          .map(
            (l) => l.id == _lugarArrastrado ? l.copyWith(posicion: nueva) : l,
          )
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
      _avisar('Error guardando la nueva ubicación: $e', error: true);
    }
  }

  // Soltar el dedo y cancelar (segundo dedo para zoom) hacen lo mismo: el
  // lugar queda donde se soltó y se persiste, como con los beacons.
  void _onArrastreFinLugar() => _terminarArrastreLugar();
  void _onArrastreCancelarLugar() => _terminarArrastreLugar();

  /// Con el modo borrar activo, el toque sobre el marcador de un lugar.
  void _borrarLugar(LugarInteres lugar) async {
    if (await _eliminarLugar(lugar)) _sacarLugar(lugar);
  }

  /// Pide confirmar y elimina el lugar de la base. Devuelve si se eliminó.
  /// Lo usan el modo borrar y la tarjeta del lugar en la lista (el tacho,
  /// deslizarla y la acción "Eliminar" de TalkBack): ya no hay que
  /// distinguirlo de un arrastre.
  Future<bool> _eliminarLugar(LugarInteres lugar) async {
    try {
      final confirmar = await mostrarConfirmacion(
        context,
        titulo: '¿Eliminar lugar?',
        mensaje: 'Se eliminará "${lugar.nombre}".',
        confirmar: 'Eliminar',
        destructiva: true,
        iconoConfirmar: Icons.delete_rounded,
      );
      if (!confirmar) return false;
      await DatabaseHelper.instance.eliminarLugarInteres(lugar.id!);
      return true;
    } catch (e) {
      _avisar('Error eliminando lugar: $e', error: true);
      return false;
    }
  }

  /// Saca de la lista (y del mapa) el lugar ya eliminado de la base.
  void _sacarLugar(LugarInteres lugar) {
    if (mounted) {
      setState(() => _lugares.removeWhere((l) => l.id == lugar.id));
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
            nombre: _seleccionado!.device.advName.isEmpty
                ? 'Beacon'
                : _seleccionado!.device.advName,
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
      _avisar('Bluetooth o permisos no disponibles', error: true);
      return;
    }
    if (mounted) setState(() => _escaneando = true);
    final scanOk = await BluetoothHelper.iniciarScanSeguro(
      dueno: this,
      onResultados: (resultados) {
        if (!mounted) return;
        _actualizarPotenciaLista(resultados);
        setState(() => _dispositivosCercanos = resultados);
        _actualizarSenales(resultados);
      },
      onError: (e) => _avisar('Error en scan: $e', error: true),
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
      _avisar('Error guardando el offset: $e', error: true);
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

    if (toma.length < 3) {
      _avisar(
        'No llegaron lecturas de la brújula. Probá de nuevo.',
        error: true,
      );
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
      _avisar(
        'El teléfono se movió durante la toma. Quedate quieto y probá '
        'de nuevo.',
        error: true,
      );
      return;
    }
    final precisa = (_precisionBrujula ?? 999) <= 15;
    if (!await _fijarRotacion(atan2(s, c) * 180 / pi) || !mounted) return;
    _avisar(
      precisa
          ? 'Offset guardado: ${_rotacionMapa.toStringAsFixed(0)}°'
          : 'Offset guardado: ${_rotacionMapa.toStringAsFixed(0)}°, con la '
                'brújula imprecisa. Calibrala (un 8 en el aire) y repetí.',
    );
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
        _avisar(
          'No se acumularon lecturas válidas. Activá el escáner.',
          error: true,
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
        _avisar(
          'Punto clave no guardado: se '
          '${lecturas.length == 1 ? 've 1 beacon' : 'ven ${lecturas.length} beacons'}'
          ' y hacen falta 3.',
          error: true,
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
      final nuevas = await DatabaseHelper.instance.obtenerCalibracionesPorPiso(
        widget.pisoId,
      );
      if (mounted) {
        setState(() {
          _calibraciones = nuevas;
          _acumCal.clear();
          _muestrasAcumuladas = 0;
        });
        _avisar(
          'Calibración registrada en (${celda.ix}, ${celda.iy}) '
          'con ${lecturas.length} beacons.',
        );
      }
    } catch (e) {
      _avisar('Error guardando calibración: $e', error: true);
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
      final nuevas = await DatabaseHelper.instance.obtenerCalibracionesPorPiso(
        widget.pisoId,
      );
      if (!mounted) return;
      setState(() => _calibraciones = nuevas);
      _avisar(
        borradas == 0
            ? 'No había duplicados.'
            : borradas == 1
            ? 'Se eliminó 1 calibración duplicada.'
            : 'Se eliminaron $borradas calibraciones duplicadas.',
      );
    } catch (e) {
      _avisar('Error limpiando duplicados: $e', error: true);
    }
  }

  /// Borra de una vez todas las calibraciones y puntos clave del piso.
  ///
  /// Para cuando se mueve o se cambia un beacon: cada toma guarda lo que se
  /// oía de cada beacon desde una celda, así que con el beacon en otro lugar
  /// las calibraciones ajustan mal su modelo de rango y los puntos clave
  /// esperan un patrón de señal que ya no aparece. Borrarlas una por una con
  /// decenas guardadas era tedioso. Con una toma en curso no se borra: su
  /// guardado llegaría después y quedaría sola, sin que el admin lo note.
  Future<void> _eliminarTodasLasCalibraciones() async {
    if (_tomandoMuestras || _guardandoCalibracion) {
      _avisar('Esperá a que termine la toma en curso.');
      return;
    }
    final puntosClave = _calibraciones.where((c) => c.esFingerprint).length;
    final comunes = _calibraciones.length - puntosClave;
    final confirmar = await mostrarConfirmacion(
      context,
      titulo: '¿Borrar todas las calibraciones?',
      mensaje:
          'Se borran $comunes '
          '${comunes == 1 ? "calibración" : "calibraciones"} y $puntosClave '
          '${puntosClave == 1 ? "punto clave" : "puntos clave"} de este piso. '
          'No se puede deshacer.'
          '${_remoteIdPublicado != null ? '\n\nLa copia publicada no cambia hasta que vuelvas a publicar el piso.' : ''}',
      confirmar: 'Borrar todo',
      destructiva: true,
      iconoConfirmar: Icons.delete_sweep_rounded,
    );
    if (!confirmar) return;
    try {
      final borradas = await DatabaseHelper.instance
          .eliminarCalibracionesDelPiso(widget.pisoId);
      final nuevas = await DatabaseHelper.instance.obtenerCalibracionesPorPiso(
        widget.pisoId,
      );
      if (!mounted) return;
      setState(() => _calibraciones = nuevas);
      _avisar(
        borradas == 1
            ? 'Se borró 1 calibración.'
            : 'Se borraron $borradas calibraciones.',
      );
    } catch (e) {
      _avisar('Error borrando calibraciones: $e', error: true);
    }
  }

  Future<void> _eliminarCalibracion(CalibracionRegistro c) async {
    final confirmar = await mostrarConfirmacion(
      context,
      titulo: '¿Eliminar calibración?',
      mensaje: 'Se eliminará "${_nombreCalibracion(c)}".',
      confirmar: 'Eliminar',
      destructiva: true,
      iconoConfirmar: Icons.delete_rounded,
    );
    if (!confirmar || c.id == null) return;
    try {
      await DatabaseHelper.instance.eliminarCalibracion(c.id!);
      final nuevas = await DatabaseHelper.instance.obtenerCalibracionesPorPiso(
        widget.pisoId,
      );
      if (mounted) setState(() => _calibraciones = nuevas);
    } catch (e) {
      _avisar('Error eliminando calibración: $e', error: true);
    }
  }

  /// Cómo se nombra una calibración: su etiqueta o su celda.
  String _nombreCalibracion(CalibracionRegistro c) =>
      c.etiqueta ?? 'Celda (${c.celdaIx}, ${c.celdaIy})';

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
      final metros = await _pedirMetros(
        'Largo de la línea',
        '¿Cuántos metros mide el largo en la realidad?',
      );
      if (metros == null || !mounted) return;
      setState(() => _largoMetros = metros);
    } else if (_faltaMedidaAncho) {
      final metros = await _pedirMetros(
        'Ancho de la línea',
        '¿Cuántos metros mide el ancho en la realidad?',
      );
      if (metros == null || !mounted) return;
      setState(() => _anchoMetros = metros);
      await _recalcularYGuardarEscala(mostrarAviso: true);
    }
  }

  /// Con el largo y el ancho ya medidos (y sus metros de referencia guardados),
  /// calcula la escala por eje a partir de las posiciones ACTUALES de los puntos
  /// y persiste el resultado. No borra los puntos: quedan en pantalla para poder
  /// reacomodarlos y recalcular. [mostrarAviso] muestra el aviso de confirmación
  /// (true al completar la medición; false en los reajustes finos de puntos).
  Future<void> _recalcularYGuardarEscala({required bool mostrarAviso}) async {
    final largoMetros = _largoMetros;
    final anchoMetros = _anchoMetros;
    if (largoMetros == null ||
        anchoMetros == null ||
        _puntosEscala.length < 3) {
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
      await DatabaseHelper.instance.actualizarEscalaPiso(
        widget.pisoId,
        escalaX,
        escalaY,
      );
      if (mounted) {
        setState(() {
          _escalaX = escalaX;
          _escalaY = escalaY;
          _grilla = GrillaNav(
            metrosX: escalaX,
            metrosY: escalaY,
            tamCeldaMetros: _tamCelda,
          );
          // Medición completa: los puntos SIGUEN en pantalla para reacomodarlos.
        });
        if (mostrarAviso) {
          _avisar(
            'Escala guardada: ${_decimal(escalaX)} × ${_decimal(escalaY)} m '
            '(grilla de ${_grilla.celdasX} × ${_grilla.celdasY}, celdas de '
            '${_decimal(_tamCelda)} m).',
          );
        }
      }
    } catch (e) {
      _avisar('Error guardando escala: $e', error: true);
    }
  }

  /// Un número con un decimal y coma ("12,5"), para lo que se lee en la
  /// pantalla.
  static String _decimal(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  /// Cambia el lado de celda de la grilla (0.5–1.0 m), regenera la grilla con
  /// la escala actual y persiste el valor. No requiere re-medir la escala.
  Future<void> _cambiarTamCelda(double valor) async {
    // Redondear al paso de 0.1 m para evitar ruido de coma flotante del Slider.
    final v = (valor * 10).round() / 10;
    if (v == _tamCelda) return;
    if (mounted) {
      setState(() {
        _tamCelda = v;
        _grilla = GrillaNav(
          metrosX: _escalaX,
          metrosY: _escalaY,
          tamCeldaMetros: _tamCelda,
        );
      });
    }
    try {
      await DatabaseHelper.instance.actualizarTamCeldaPiso(
        widget.pisoId,
        _tamCelda,
      );
    } catch (e) {
      _avisar('Error guardando tamaño de celda: $e', error: true);
    }
  }

  /// Los metros del largo o del ancho, en una hoja. null: se canceló (los
  /// puntos quedan donde están).
  Future<double?> _pedirMetros(String titulo, String mensaje) =>
      mostrarHoja<double>(
        context,
        titulo: titulo,
        botonCerrar: false,
        contenido: (context) => _HojaMetros(mensaje: mensaje),
      );

  // -- UI --------------------------------------------------------------------
  //
  // ─── Sistema de diseño (fase 5.6 del rediseño) ───
  // La pantalla va envuelta en AmbienteDiseno. De arriba a abajo:
  //   · la barra, con "Publicar el mapa en la nube" y, si está publicado,
  //     "Eliminar el mapa de la nube". Mientras tanto, sin la ruedita: las
  //     dos acciones se apagan y sobre el plano aparece "Publicando…" (o
  //     "Eliminando de la nube…"), que TalkBack anuncia;
  //   · los seis modos, en una fila de chips que se desplaza (antes, un
  //     SegmentedButton);
  //   · el plano, hundido y con borde (rojo y de 2 px en el modo borrar), con
  //     el botón "Borrar" / "Listo" encima. Lo que se dibuja adentro
  //     (MapaWidget) no cambió: se comparte con la navegación y se migra en
  //     la 5.7;
  //   · debajo, un panel que se desplaza solo: la ayuda del modo y sus
  //     controles. La ayuda va acá, abajo del plano, para que el plano no se
  //     corra cuando cambia su texto.
  // El plano mide 380 como antes; sólo se achica si no entra (con el teclado
  // abierto o con letra grande), así el panel siempre tiene lugar. Su alto no
  // depende de lo que diga la ayuda: no cambia mientras se dibuja.
  //
  // Los diálogos pasaron a hojas (mostrarHoja), las confirmaciones a
  // mostrarConfirmacion y los avisos a mostrarAviso. La lógica, los gestos
  // del plano y los textos de la toma no cambiaron.

  /// Alto del plano con lugar de sobra: el de siempre.
  static const double _altoPlano = 380;

  /// Lo mínimo que se le deja al plano (con el teclado abierto).
  static const double _altoPlanoMinimo = 160;

  /// Lo mínimo que se le deja al panel de abajo, para que se vean al menos
  /// dos o tres elementos de una lista.
  static const double _altoPanelMinimo = 220;

  /// Los modos, en el orden de la fila de arriba.
  static const List<({_ModoEdicion modo, String texto})> _modos = [
    (modo: _ModoEdicion.beacons, texto: 'Beacons'),
    (modo: _ModoEdicion.zonas, texto: 'Zonas'),
    (modo: _ModoEdicion.lugares, texto: 'Lugares'),
    (modo: _ModoEdicion.escala, texto: 'Escala'),
    (modo: _ModoEdicion.calibracion, texto: 'Calibrar'),
    (modo: _ModoEdicion.brujula, texto: 'Brújula'),
  ];

  /// Pasa a [nuevoModo]. Es lo que hacía el SegmentedButton de antes al
  /// elegir otro segmento (tocar el elegido no hace nada).
  void _cambiarModo(_ModoEdicion nuevoModo) {
    if (!mounted || nuevoModo == _modo) return;
    // Detener brújula si salimos del modo brujula.
    // La brujula hace falta en el modo brujula Y en calibracion
    // (los puntos clave guardan el rumbo de captura), asi que solo
    // se apaga al salir hacia un modo que no la usa.
    const usanBrujula = {_ModoEdicion.brujula, _ModoEdicion.calibracion};
    if (usanBrujula.contains(_modo) && !usanBrujula.contains(nuevoModo)) {
      _detenerCompass();
    }
    // Al salir del modo calibración: liberar el anclado de posición.
    if (_modo == _ModoEdicion.calibracion &&
        nuevoModo != _ModoEdicion.calibracion) {
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
    _centrarChipModo(nuevoModo);
    // Las lecturas en vivo de calibración necesitan el escáner activo.
    if (nuevoModo == _ModoEdicion.calibracion) {
      _asegurarEscaneando();
      _iniciarCompass();
    }
    // Iniciar brújula en vivo al entrar al modo brujula.
    if (nuevoModo == _ModoEdicion.brujula) {
      _iniciarCompass();
    }
  }

  /// Deja el chip elegido en el medio de la fila, con sus vecinos a la vista.
  /// El de antes, al perder el tilde, se achica y corre a los que le siguen:
  /// sin esto, un chip tocado contra el borde quedaba cortado.
  void _centrarChipModo(_ModoEdicion modo) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _clavesChipModo[modo]!.currentContext;
      if (chip == null || !chip.mounted) return;
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: MovimientoApp.duracion(chip, MovimientoApp.seleccion),
        curve: MovimientoApp.curva,
      );
    });
  }

  /// Entra y sale del modo borrar (el botón sobre el plano).
  void _conmutarModoBorrar() {
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
  }

  /// "Cancelar" durante una toma de calibración.
  void _cancelarToma() {
    if (mounted) {
      setState(() {
        _tomandoMuestras = false;
        _muestrasAcumuladas = 0;
        _acumCal.clear();
        _inicioToma = null;
      });
    }
  }

  String _hintTexto() {
    if (_borrando) {
      switch (_modo) {
        case _ModoEdicion.beacons:
          return 'Modo borrar: tocá un beacon. «Listo» para salir.';
        case _ModoEdicion.zonas:
          return 'Modo borrar: tocá una zona. «Listo» para salir.';
        default:
          return 'Modo borrar: tocá un lugar, escalera o ascensor. «Listo» '
              'para salir.';
      }
    }
    switch (_modo) {
      case _ModoEdicion.beacons:
        return 'Elegí un dispositivo de la lista y tocá el mapa para ubicarlo. '
            'Arrastrá la mira de un beacon para moverlo.';
      case _ModoEdicion.zonas:
        if (_verticesEnCurso.isEmpty) {
          return 'Tocá el mapa para marcar los vértices (mínimo 3). Arrastrá '
              'sin soltar para afinar.';
        }
        final n = _verticesEnCurso.length;
        return '${n == 1 ? '1 punto' : '$n puntos'}. Tocá para agregar, '
            'arrastrá para corregir o cerrá la zona.';
      case _ModoEdicion.lugares:
        return 'Tocá el mapa para agregar un lugar, escalera o ascensor. '
            'Arrastralo para moverlo; se edita desde la lista.';
      case _ModoEdicion.escala:
        final actual =
            'Escala actual: ${_decimal(_escalaX)} × ${_decimal(_escalaY)} m '
            '(grilla de ${_grilla.celdasX} × ${_grilla.celdasY}).';
        final largo = _largoMetros;
        final textoLargo = largo == null ? '' : 'Largo: ${_decimal(largo)} m. ';
        switch (_puntosEscala.length) {
          case 0:
            return '$actual Marcá el primer punto del largo.';
          case 1:
            return '$actual Marcá el segundo punto del largo.';
          case 2:
            if (largo == null) {
              return '$actual Acomodá los puntos y tocá «Medida del largo».';
            }
            return '$actual ${textoLargo}Marcá el tercer punto: el ancho va '
                'desde el segundo.';
        }
        if (_anchoMetros == null) {
          return '$actual ${textoLargo}Acomodá el tercer punto y tocá «Medida '
              'del ancho».';
        }
        return '$actual Medición lista. Arrastrá los puntos para ajustar o '
            '«Reiniciar» para medir de nuevo.';
      case _ModoEdicion.calibracion:
        if (_celdaCalSeleccionada == null) {
          return 'Tocá la celda donde estás parado.';
        }
        final c = _celdaCalSeleccionada!;
        return 'Celda (${c.ix}, ${c.iy}). Tomá la calibración acá abajo.';
      case _ModoEdicion.brujula:
        return 'Apuntá el teléfono hacia el «arriba» del plano y tocá «Usar la '
            'dirección actual».';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Los más fuertes primero (ver _potenciaDe).
    final dispositivosVisibles =
        _dispositivosCercanos.where(_coincideFiltro).toList()
          ..sort((a, b) => _potenciaDe(b).compareTo(_potenciaDe(a)));

    return AmbienteDiseno(
      child: Builder(
        builder: (context) {
          final e = EstiloApp.de(context);
          return Scaffold(
            backgroundColor: e.fondo,
            appBar: BarraSuperior(
              titulo: 'Configuración del piso',
              acciones: [
                if (_remoteIdPublicado != null)
                  AccionBarra(
                    icono: Icons.cloud_off_rounded,
                    etiqueta: 'Eliminar el mapa de la nube',
                    alPresionar: _publicando ? null : _eliminarMapaPublicado,
                  ),
                AccionBarra(
                  icono: Icons.cloud_upload_rounded,
                  etiqueta: 'Publicar el mapa en la nube',
                  alPresionar: _publicando ? null : _publicarPiso,
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _selectorModo(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, restricciones) {
                        final alto = restricciones.maxHeight;
                        final altoPlano = min(
                          alto,
                          (alto - _altoPanelMinimo).clamp(
                            _altoPlanoMinimo,
                            _altoPlano,
                          ),
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: altoPlano,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: EspaciadoApp.margenLateral,
                                ),
                                child: _plano(e),
                              ),
                            ),
                            Expanded(
                              child: _panel(context, e, dispositivosVisibles),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Los seis modos, en una fila de chips que se desplaza de costado: elegido,
  /// en acento con la tilde. TalkBack los lee como opciones de las que se
  /// elige una.
  Widget _selectorModo() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Sin recorte: las sombras de los chips no se cortan arriba ni abajo.
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(
        EspaciadoApp.margenLateral,
        EspaciadoApp.minimo,
        EspaciadoApp.margenLateral,
        EspaciadoApp.medio,
      ),
      child: Row(
        children: [
          for (final (i, m) in _modos.indexed) ...[
            if (i > 0) const SizedBox(width: EspaciadoApp.chico),
            ChipFiltro(
              key: _clavesChipModo[m.modo],
              texto: m.texto,
              exclusivo: true,
              seleccionado: _modo == m.modo,
              alCambiar: (_) => _cambiarModo(m.modo),
            ),
          ],
        ],
      ),
    );
  }

  /// El plano, hundido: la sombra interior y el borde van encima de la
  /// imagen. En el modo borrar, el borde pasa al rojo de 2 px (antes, un
  /// marco rojo encima), que deja a la vista el modo aunque no se mire el
  /// botón.
  Widget _plano(EstiloApp e) {
    final borrando = _borrando;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Para TalkBack, el plano tiene nombre (antes, un área que se tocaba
        // sin nombre); los nombres de los lugares de adentro se leen con él.
        Semantics(
          container: true,
          label: 'Plano del piso',
          child: PanelRelieve(
            hundido: true,
            sombraEncima: true,
            relleno: EdgeInsets.zero,
            borde: BorderSide(
              color: borrando ? e.error : e.borde,
              width: borrando ? FormasApp.grosorFoco : FormasApp.grosorLinea,
            ),
            child: LayoutBuilder(
              builder: (context, restricciones) {
                _tamVisor = restricciones.biggest;
                return InteractiveViewer(
                  transformationController: _transformMapa,
                  maxScale: _zoomMaximo,
                  // En escala, zonas, beacons y lugares UN dedo dibuja o
                  // arrastra puntos, así que se desactiva el pan de un dedo; el
                  // zoom de dos dedos queda siempre activo (al apoyar el segundo
                  // dedo el gesto en curso se cancela y el InteractiveViewer
                  // hace zoom).
                  // En modo borrar nadie dibuja ni arrastra, así que un dedo
                  // vuelve a desplazar el mapa.
                  panEnabled:
                      _borrando ||
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
                    // Flecha de hacia dónde mira el operador, compensada con la
                    // rotación del mapa como en la navegación. La brújula sólo
                    // corre en Calibración y Brújula: en el resto no hay flecha.
                    // En Calibración sirve para ver, antes de tomar un punto
                    // clave, hacia dónde va a quedar guardado su rumbo.
                    headingUsuario: _headingEnVivo == null
                        ? null
                        : ((_headingEnVivo! - _rotacionMapa) % 360 + 360) % 360,
                    modoEdicion: true,
                    mostrarGrilla: true,
                    grilla: _grilla,
                    // En modo zonas los toques se atienden por los callbacks de
                    // arrastre (apoyar y corregir el vértice en un solo gesto).
                    // En modo borrar no se agrega nada: el toque sobre el
                    // plano vacío no hace nada.
                    onTapMapa:
                        _borrando ||
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
                    verticeArrastrado: _modo == _ModoEdicion.zonas
                        ? _verticeArrastrado
                        : null,
                    // Guías del asistente de trazo (magenta punteado).
                    guias: _guias,
                    guiaPunto: _guiaPunto,
                    escalaVista: _escalaVista,
                    // Copia nueva en cada build: el painter compara por
                    // referencia, así que al mover un punto (mutación in-place)
                    // esta copia fuerza el repintado en cada frame del arrastre.
                    puntosMedicion: _modo == _ModoEdicion.escala
                        ? List.of(_puntosEscala)
                        : const [],
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
                    // Calibración: celda seleccionada (amarillo) + pines de
                    // celdas calibradas.
                    celdaResaltada:
                        _modo == _ModoEdicion.calibracion &&
                            _celdaCalSeleccionada != null
                        ? Offset(
                            _grilla.centroX(_celdaCalSeleccionada!.ix),
                            _grilla.centroY(_celdaCalSeleccionada!.iy),
                          )
                        : null,
                    celdasCalibradas: _modo == _ModoEdicion.calibracion
                        ? _calibraciones
                              .map(
                                (c) => Offset(
                                  _grilla.centroX(c.celdaIx),
                                  _grilla.centroY(c.celdaIy),
                                ),
                              )
                              .toList()
                        : const [],
                  ),
                );
              },
            ),
          ),
        ),
        if (_publicando)
          Positioned(
            top: EspaciadoApp.chico,
            left: EspaciadoApp.chico,
            child: _estadoNube(),
          ),
        if (_modoAdmiteBorrar)
          Positioned(
            top: EspaciadoApp.chico,
            right: EspaciadoApp.chico,
            child: _botonBorrar(),
          ),
      ],
    );
  }

  /// Mientras se publica o se elimina de la nube: un chip quieto (sin nada
  /// que gire) sobre el plano, que TalkBack anuncia.
  Widget _estadoNube() => Semantics(
    container: true,
    liveRegion: true,
    child: ChipApp(
      texto: _eliminandoDeLaNube ? 'Eliminando de la nube…' : 'Publicando…',
      icono: _eliminandoDeLaNube
          ? Icons.cloud_off_rounded
          : Icons.cloud_upload_rounded,
    ),
  );

  /// Botón sobre el plano que entra y sale del modo borrar: "Borrar" con el
  /// tacho en rojo y, adentro del modo, "Listo". TalkBack lo lee como un
  /// interruptor, con los nombres de antes.
  Widget _botonBorrar() {
    // Con una zona a medio dibujar no se entra a borrar: primero hay que
    // cerrarla o descartarla, para no perder los puntos marcados.
    final bloqueado =
        !_modoBorrar &&
        _modo == _ModoEdicion.zonas &&
        _verticesEnCurso.isNotEmpty;
    final activo = _borrando;
    return MergeSemantics(
      child: Semantics(
        toggled: activo,
        child: BotonSecundario(
          texto: activo ? 'Listo' : 'Borrar',
          icono: activo ? Icons.check_rounded : Icons.delete_rounded,
          destructivo: !activo,
          compacto: true,
          etiquetaSemantica: activo
              ? 'Salir del modo borrar'
              : 'Entrar al modo borrar',
          alPresionar: bloqueado ? null : _conmutarModoBorrar,
        ),
      ),
    );
  }

  /// El panel de abajo del plano: la ayuda y lo del modo, con su propio
  /// desplazamiento. Cada modo arranca arriba de todo.
  Widget _panel(
    BuildContext context,
    EstiloApp e,
    List<ScanResult> dispositivosVisibles,
  ) {
    return CustomScrollView(
      key: ValueKey<_ModoEdicion>(_modo),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            EspaciadoApp.margenLateral,
            EspaciadoApp.margenLateral,
            EspaciadoApp.margenLateral,
            0,
          ),
          sliver: SliverToBoxAdapter(child: _ayuda(context, e)),
        ),
        ...switch (_modo) {
          _ModoEdicion.beacons => _sliversBeacons(
            context,
            e,
            dispositivosVisibles,
          ),
          _ModoEdicion.lugares => _sliversLugares(),
          _ModoEdicion.zonas => [_bloque(_controlesZonas())],
          _ModoEdicion.escala => [_bloque(_controlesEscala())],
          _ModoEdicion.calibracion => [_bloque(_contenidoCalibracion(e))],
          _ModoEdicion.brujula => [_bloque(_contenidoBrujula(e))],
        },
        const SliverToBoxAdapter(
          child: SizedBox(height: EspaciadoApp.entreSecciones),
        ),
      ],
    );
  }

  /// Una columna de controles del panel, con los márgenes de la pantalla.
  Widget _bloque(List<Widget> hijos) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: EspaciadoApp.margenLateral),
    sliver: SliverList.list(children: hijos),
  );

  /// La ayuda del modo, con un ícono; en el modo borrar, en rojo (5,94 sobre
  /// el fondo) y con el tacho.
  Widget _ayuda(BuildContext context, EstiloApp e) {
    final borrando = _borrando;
    final color = borrando ? e.error : e.textoSecundario;
    const estilo = TipografiaApp.subtitulo;
    // El ícono, centrado en el primer renglón, crezca o no la letra.
    final renglon =
        MediaQuery.textScalerOf(context).scale(estilo.fontSize!) *
        estilo.height!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: max(0, (renglon - FormasApp.iconoChico) / 2),
          ),
          child: ExcludeSemantics(
            child: Icon(
              borrando ? Icons.delete_rounded : Icons.info_outline_rounded,
              size: FormasApp.iconoChico,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: EspaciadoApp.chico),
        Expanded(
          child: Text(_hintTexto(), style: estilo.copyWith(color: color)),
        ),
      ],
    );
  }

  // ─── Zonas y escala ───────────────────────────────────────────────────────

  /// El asistente de trazo: sólo tiene sentido donde se dibujan líneas.
  Widget _interruptorLineasRectas() => GrupoFilas(
    filas: [
      FilaGrupo.interruptor(
        titulo: 'Líneas rectas',
        subtitulo: _modo == _ModoEdicion.zonas
            ? 'Imanta a 0°, 45° y 90°'
            : 'Imanta a 0° y 90°',
        icono: Icons.architecture_rounded,
        valor: _asistenteRecto,
        alCambiar: (v) {
          if (!mounted) return;
          setState(() {
            _asistenteRecto = v;
            _limpiarGuias();
          });
        },
      ),
    ],
  );

  /// Deshacer el último punto (un botón redondo) y los botones del modo, del
  /// mismo ancho (o apilados, si no entran).
  Widget _filaAcciones({
    required Widget deshacer,
    required List<Widget> botones,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El botón redondo (48) a la altura de los de 52.
        Padding(padding: const EdgeInsets.only(top: 2), child: deshacer),
        const SizedBox(width: EspaciadoApp.medio),
        Expanded(child: FilaBotones(children: botones)),
      ],
    );
  }

  List<Widget> _controlesZonas() => [
    const SizedBox(height: EspaciadoApp.entreSecciones),
    _interruptorLineasRectas(),
    const SizedBox(height: EspaciadoApp.margenLateral),
    _filaAcciones(
      // Deshacer el último punto: cualquier toque sobre el plano crea un
      // vértice, así que hace falta una forma de sacar uno solo sin
      // descartar la zona entera.
      deshacer: BotonRedondo(
        icono: Icons.undo_rounded,
        etiqueta: 'Quitar el último punto',
        alPresionar: _verticesEnCurso.isNotEmpty ? _quitarUltimoVertice : null,
      ),
      botones: [
        BotonSecundario(
          texto: 'Descartar',
          icono: Icons.delete_rounded,
          destructivo: true,
          alPresionar: _verticesEnCurso.isNotEmpty
              ? _descartarZonaEnCurso
              : null,
        ),
        BotonPrincipal(
          texto: 'Cerrar zona',
          icono: Icons.check_rounded,
          expandido: false,
          alPresionar: _verticesEnCurso.length >= 3 ? _cerrarZona : null,
        ),
      ],
    ),
  ];

  List<Widget> _controlesEscala() => [
    const SizedBox(height: EspaciadoApp.entreSecciones),
    _interruptorLineasRectas(),
    const SizedBox(height: EspaciadoApp.margenLateral),
    _filaAcciones(
      // Igual que en las zonas: deshacer sólo el último punto.
      deshacer: BotonRedondo(
        icono: Icons.undo_rounded,
        etiqueta: 'Quitar el último punto',
        alPresionar: _puntosEscala.isNotEmpty ? _quitarUltimoPuntoEscala : null,
      ),
      botones: [
        BotonSecundario(
          texto: 'Reiniciar',
          icono: Icons.restart_alt_rounded,
          alPresionar: _puntosEscala.isNotEmpty ? _reiniciarMedicion : null,
        ),
        BotonPrincipal(
          texto: _medicionEscalaCompleta
              ? 'Escala lista'
              : _largoMetros == null
              ? 'Medida del largo'
              : 'Medida del ancho',
          icono: Icons.straighten_rounded,
          expandido: false,
          alPresionar: _faltaMedidaLargo || _faltaMedidaAncho
              ? _ponerMedidaEscala
              : null,
        ),
      ],
    ),
    const SizedBox(height: EspaciadoApp.entreSecciones),
    // El tamaño de celda de la grilla (0,5 a 1 m): junto a la escala porque
    // define la resolución de la misma grilla.
    Deslizador(
      etiqueta: 'Tamaño de celda',
      valor: _tamCelda.clamp(0.5, 1.0),
      min: 0.5,
      max: 1.0,
      divisiones: 5, // pasos de 0,1 m: 0,5, 0,6, … 1,0
      formato: (v) => '${_decimal(v)} m',
      formatoSemantico: (v) => '${_decimal(v)} metros',
      ayuda:
          'Grilla de ${_grilla.celdasX} × ${_grilla.celdasY}. Menor, más '
          'precisión en espacios chicos; mayor, una grilla más liviana.',
      alCambiar: _cambiarTamCelda,
    ),
  ];

  // ─── Beacons ──────────────────────────────────────────────────────────────

  List<Widget> _sliversBeacons(
    BuildContext context,
    EstiloApp e,
    List<ScanResult> visibles,
  ) {
    final sinCoincidencias =
        _filtroActivo && visibles.isEmpty && _dispositivosCercanos.isNotEmpty;
    return [
      _bloque([
        const SizedBox(height: EspaciadoApp.entreSecciones),
        _filaEscaner(context, e),
        const SizedBox(height: EspaciadoApp.margenLateral),
        _filaFiltro(visibles.length),
        const SizedBox(height: EspaciadoApp.margenLateral),
      ]),
      if (sinCoincidencias)
        SliverToBoxAdapter(
          child: EstadoPantalla(
            icono: Icons.filter_alt_off_rounded,
            titulo: 'Ningún dispositivo pasa el filtro',
            accion: BotonSecundario(
              texto: 'Quitar filtro',
              icono: Icons.close_rounded,
              alPresionar: () => _aplicarFiltro('', _sinPotenciaMinima),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: EspaciadoApp.margenLateral,
          ),
          sliver: SliverList.separated(
            itemCount: visibles.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: EspaciadoApp.entreTarjetas),
            itemBuilder: (context, i) => _tarjetaDispositivo(visibles[i]),
          ),
        ),
    ];
  }

  /// El estado del escáner (que TalkBack anuncia al cambiar) y el botón para
  /// prenderlo ("Escanear", el principal) o apagarlo.
  Widget _filaEscaner(BuildContext context, EstiloApp e) {
    final estado = Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        children: [
          CuadroIcono(
            icono: _escaneando
                ? Icons.bluetooth_searching_rounded
                : Icons.bluetooth_disabled_rounded,
          ),
          const SizedBox(width: EspaciadoApp.medio),
          Expanded(
            child: Text(
              _escaneando ? 'Buscando dispositivos…' : 'Escáner detenido',
              style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
            ),
          ),
        ],
      ),
    );
    final boton = _escaneando
        ? BotonSecundario(
            texto: 'Detener',
            icono: Icons.stop_rounded,
            alPresionar: _conmutarEscaner,
          )
        : BotonPrincipal(
            texto: 'Escanear',
            icono: Icons.play_arrow_rounded,
            expandido: false,
            alPresionar: _conmutarEscaner,
          );
    if (TipografiaApp.esLetraGrande(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          estado,
          const SizedBox(height: EspaciadoApp.margenLateral),
          boton,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: estado),
        // Más aire que el alcance de la luz del botón: no cae sobre el texto.
        const SizedBox(width: EspaciadoApp.margenLateral + EspaciadoApp.minimo),
        boton,
      ],
    );
  }

  /// El filtro por nombre y potencia: una fila que abre la hoja, con lo que
  /// filtra y cuántos pasan. Con un filtro puesto, al lado, el botón para
  /// quitarlo.
  Widget _filaFiltro(int visibles) {
    final activo = _filtroActivo;
    final fila = GrupoFilas(
      filas: [
        FilaGrupo(
          icono: activo ? Icons.filter_alt_rounded : Icons.search_rounded,
          titulo: activo
              ? [
                  if (_filtroNombre.isNotEmpty)
                    'Nombre contiene «$_filtroNombre»',
                  if (_potenciaMinima > _sinPotenciaMinima)
                    'desde $_potenciaMinima dBm',
                ].join(' · ')
              : 'Filtrar por nombre o potencia',
          subtitulo: activo
              ? '$visibles de ${_dispositivosCercanos.length} dispositivos'
              : 'Los más fuertes, primero',
          navega: true,
          alTocar: _pedirFiltro,
        ),
      ],
    );
    if (!activo) return fila;
    return Row(
      children: [
        Expanded(child: fila),
        const SizedBox(width: EspaciadoApp.chico),
        BotonRedondo(
          icono: Icons.close_rounded,
          etiqueta: 'Quitar filtro',
          alPresionar: () => _aplicarFiltro('', _sinPotenciaMinima),
        ),
      ],
    );
  }

  /// Un dispositivo de la lista, que se elige para ubicarlo en el mapa (uno
  /// solo: borde y tilde en acento). Los que ya están en el mapa, apagados.
  Widget _tarjetaDispositivo(ScanResult d) {
    final mac = d.device.remoteId.str;
    final yaUbicado = _beaconsEnElMapa.containsKey(mac);
    final potencia = _potenciaDe(d);
    return TarjetaDestino(
      key: ValueKey<String>(mac),
      icono: yaUbicado ? Icons.check_circle_rounded : Icons.bluetooth_rounded,
      nombre: d.device.advName.isEmpty
          ? 'Dispositivo desconocido'
          : d.device.advName,
      detalle: yaUbicado
          ? '$mac · $potencia dBm · ya está en el mapa'
          : '$mac · $potencia dBm',
      seleccionada: _seleccionado == d,
      alTocar: yaUbicado
          ? null
          : () {
              if (mounted) setState(() => _seleccionado = d);
            },
    );
  }

  // ─── Lugares ──────────────────────────────────────────────────────────────

  List<Widget> _sliversLugares() {
    if (_lugares.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: EstadoPantalla(
            icono: Icons.place_rounded,
            titulo: 'No hay lugares de interés',
            detalle:
                'Tocá el mapa para agregar un lugar, una escalera o un '
                'ascensor.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          EspaciadoApp.margenLateral,
          EspaciadoApp.entreSecciones,
          EspaciadoApp.margenLateral,
          0,
        ),
        sliver: SliverList.separated(
          itemCount: _lugares.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: EspaciadoApp.entreTarjetas),
          itemBuilder: (context, i) {
            final l = _lugares[i];
            // Tocar la tarjeta edita el lugar (nombre, rubro, palabras
            // propias); el tacho, deslizarla o la acción "Eliminar" de
            // TalkBack lo eliminan, con la misma confirmación.
            return TarjetaLista(
              key: ValueKey<Object?>(l.id),
              icono: !l.esEscalera
                  ? Icons.place_rounded
                  : (l.esAscensor
                        ? Icons.elevator_rounded
                        : Icons.stairs_rounded),
              titulo: l.nombre,
              subtitulo: _detalleLugar(l),
              alTocar: () => _editarLugar(l),
              alEliminar: () => _eliminarLugar(l),
              alEliminada: () => _sacarLugar(l),
            );
          },
        ),
      ),
    ];
  }

  /// Lo que dice la tarjeta de un lugar debajo del nombre: el rubro y las
  /// otras palabras; en una escalera o un ascensor, para dónde va.
  String? _detalleLugar(LugarInteres l) {
    if (l.esEscalera) {
      final sentido = l.sube && l.baja
          ? 'sube y baja'
          : l.sube
          ? 'sube'
          : l.baja
          ? 'baja'
          : null;
      return [l.esAscensor ? 'Ascensor' : 'Escalera', ?sentido].join(' · ');
    }
    final rubro = Rubros.porId(l.rubro);
    final detalle = [
      if (rubro != null) 'Rubro: ${rubro.nombre}',
      if (l.palabrasClave.isNotEmpty)
        'Otras palabras: ${l.palabrasClave.join(', ')}',
    ];
    return detalle.isEmpty ? null : detalle.join('\n');
  }

  // ─── Calibración ──────────────────────────────────────────────────────────

  List<Widget> _contenidoCalibracion(EstiloApp e) {
    final celda = _celdaCalSeleccionada;
    return [
      if (celda != null) ...[
        const SizedBox(height: EspaciadoApp.entreSecciones),
        EncabezadoSeccion(titulo: 'Celda (${celda.ix}, ${celda.iy})'),
        const SizedBox(height: EspaciadoApp.medio),
        CampoTexto(
          etiqueta: 'Etiqueta (opcional)',
          ayuda: 'Por ejemplo, Entrada o Pasillo norte',
          controlador: _etiquetaCalCtrl,
          capitalizacion: TextCapitalization.sentences,
          accionTeclado: TextInputAction.done,
        ),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        _lecturasActuales(e),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        // ── PUNTO CLAVE (fingerprint) ──
        // Vive dentro del propio modo calibracion: un punto clave ES una
        // calibracion, solo que medida mas tiempo y marcada para que ademas
        // se use como patron en vivo.
        GrupoFilas(filas: [_filaPuntoClave()]),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        // ── Toma multi-muestra ──
        if (_tomandoMuestras) ..._tomaEnCurso(e) else _botonToma(),
      ],
      const SizedBox(height: EspaciadoApp.entreSecciones),
      ..._calibracionesGuardadas(e),
    ];
  }

  /// Lo que se oye ahora de cada beacon del piso: el nombre, la MAC y la
  /// potencia filtrada. Sin señal, el ícono en gris.
  Widget _lecturasActuales(EstiloApp e) {
    final beacons = _beaconsEnElMapa.values.toList();
    final titulo = 'Lecturas actuales (${beacons.length} beacons)';
    if (beacons.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EncabezadoSeccion(titulo: titulo),
          const SizedBox(height: EspaciadoApp.chico),
          Text(
            'No hay beacons configurados en este piso.',
            style: TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
          ),
        ],
      );
    }
    return GrupoFilas(
      titulo: titulo,
      filas: [
        for (final b in beacons)
          FilaGrupo(
            inicio: CuadroIcono(
              icono: b.rssiFiltrado > -95 && b.rssiFiltrado < 0
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_disabled_rounded,
              color: b.rssiFiltrado > -95 && b.rssiFiltrado < 0
                  ? null
                  : e.textoSecundario,
            ),
            titulo: b.nombre,
            subtitulo: b.mac,
            valor: '${b.rssiFiltrado.toStringAsFixed(0)} dBm',
          ),
      ],
    );
  }

  FilaGrupo _filaPuntoClave() => FilaGrupo.interruptor(
    titulo: 'Punto clave (fingerprint)',
    subtitulo: !_tomaEsFingerprint
        ? 'Para esquinas donde se dobla, puertas o el pie de una escalera.'
        : _headingEnVivo == null
        ? 'Medición de ${_duracionFingerprint.inSeconds} s. Sin brújula: se '
              'guarda sin rumbo y es menos preciso.'
        : 'Medición de ${_duracionFingerprint.inSeconds} s. Mirá hacia donde '
              'se llega caminando (ahora: '
              '${_headingEnVivo!.toStringAsFixed(0)}°). Si se llega desde dos '
              'lados, tomá uno por cada sentido.',
    icono: Icons.push_pin_rounded,
    valor: _tomaEsFingerprint,
    alCambiar: _tomandoMuestras
        ? null
        : (v) => setState(() => _tomaEsFingerprint = v),
  );

  /// Empezar la toma: el botón principal del modo.
  Widget _botonToma() => BotonPrincipal(
    texto: !_escaneando
        ? 'Activá el escáner primero'
        : _tomaEsFingerprint
        ? 'Medir punto clave (${_duracionFingerprint.inSeconds} s)'
        : 'Iniciar toma de calibración (${_duracionCalibracion.inSeconds} s)',
    icono: _tomaEsFingerprint
        ? Icons.push_pin_rounded
        : Icons.add_location_alt_rounded,
    alPresionar: _escaneando ? _iniciarTomaCalibracion : null,
  );

  /// La toma en curso: cuánto va, la barra de progreso (sin nada que gire),
  /// qué hacer mientras tanto y "Cancelar".
  List<Widget> _tomaEnCurso(EstiloApp e) {
    final total = _duracionTomaActual.inSeconds;
    final van = (_progresoToma * total).round();
    final rumbo = _rumboMedioToma;
    return [
      Text(
        _tomaEsFingerprint
            ? 'Midiendo punto clave: $van / $total s'
            : 'Tomando muestras: $van / $total s',
        style: TipografiaApp.conCifrasTabulares(
          TipografiaApp.destacado,
        ).copyWith(color: e.textoPrincipal),
      ),
      const SizedBox(height: EspaciadoApp.medio),
      BarraProgreso(
        valor: _progresoToma,
        etiqueta: _tomaEsFingerprint
            ? 'Medición del punto clave'
            : 'Toma de calibración',
        valorSemantico: '$van de $total segundos',
      ),
      const SizedBox(height: EspaciadoApp.medio),
      Text(
        _tomaEsFingerprint
            ? 'No te muevas ni gires. Teléfono como para navegar, mirando '
                  'siempre hacia el mismo lado. '
                  '(${rumbo == null ? "sin brújula" : "rumbo ${rumbo.toStringAsFixed(0)}°"}'
                  ' · $_muestrasAcumuladas lecturas)'
            : 'No te muevas de la celda. ($_muestrasAcumuladas lecturas)',
        style: TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
      ),
      const SizedBox(height: EspaciadoApp.entreSecciones),
      BotonSecundario(
        texto: 'Cancelar',
        icono: Icons.close_rounded,
        destructivo: true,
        expandido: true,
        alPresionar: _cancelarToma,
      ),
    ];
  }

  /// Las calibraciones guardadas: plegadas al entrar, como antes. "Ver" las
  /// muestra con "Quitar duplicados" y "Borrar todas" arriba, y cada una con
  /// su tacho.
  List<Widget> _calibracionesGuardadas(EstiloApp e) {
    final n = _calibraciones.length;
    return [
      EncabezadoSeccion(
        titulo: 'Calibraciones guardadas ($n)',
        accion: n == 0
            ? null
            : BotonSecundario(
                texto: _verCalibraciones ? 'Ocultar' : 'Ver',
                icono: _verCalibraciones
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                compacto: true,
                etiquetaSemantica: _verCalibraciones
                    ? 'Ocultar las calibraciones guardadas'
                    : 'Ver las calibraciones guardadas',
                alPresionar: () =>
                    setState(() => _verCalibraciones = !_verCalibraciones),
              ),
      ),
      if (n == 0) ...[
        const SizedBox(height: EspaciadoApp.chico),
        Text(
          'Todavía no hay calibraciones.',
          style: TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
        ),
      ] else if (_verCalibraciones) ...[
        const SizedBox(height: EspaciadoApp.margenLateral),
        GrupoFilas(
          filas: [
            FilaGrupo(
              icono: Icons.cleaning_services_rounded,
              titulo: 'Quitar duplicados',
              subtitulo: 'Borra las copias idénticas de una misma toma.',
              alTocar: _limpiarCalibracionesDuplicadas,
            ),
            FilaGrupo(
              icono: Icons.delete_sweep_rounded,
              titulo: 'Borrar todas',
              subtitulo:
                  'Calibraciones y puntos clave del piso. Si se movió o '
                  'cambió un beacon.',
              destructiva: true,
              alTocar: _eliminarTodasLasCalibraciones,
            ),
          ],
        ),
        const SizedBox(height: EspaciadoApp.margenLateral),
        GrupoFilas(
          filas: [
            for (final c in _calibraciones)
              _FilaCalibracion(
                puntoClave: c.esFingerprint,
                titulo: _nombreCalibracion(c),
                detalle: _detalleCalibracion(c),
                alEliminar: () => _eliminarCalibracion(c),
              ),
          ],
        ),
      ],
    ];
  }

  String _detalleCalibracion(CalibracionRegistro c) => [
    if (c.esFingerprint) 'Punto clave',
    if (c.esFingerprint)
      c.rumboCaptura != null
          ? 'rumbo ${c.rumboCaptura!.toStringAsFixed(0)}°'
          : 'sin rumbo',
    '${c.lecturasBle.length} beacons',
    _formatearTimestamp(c.timestamp),
  ].join(' · ');

  // ─── Brújula ──────────────────────────────────────────────────────────────
  //
  // Panel para calibrar la rotación del mapa respecto al norte real.
  //
  // El operador apunta el teléfono hacia lo que en el plano es "arriba" y
  // toca "Usar la dirección actual": se promedia el heading unos segundos y
  // ese es el offset. El deslizador y los atajos quedan para ajustar a mano.
  // Todo se guarda solo. El valor guardado (rotacion_mapa, en grados) es el
  // offset que PantallaNavegacion resta al heading de FlutterCompass para
  // alinear la brújula con el plano.

  List<Widget> _contenidoBrujula(EstiloApp e) {
    final heading = _headingEnVivo;
    return [
      const SizedBox(height: EspaciadoApp.entreSecciones),
      // Instrucción
      PanelRelieve(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CuadroIcono(icono: Icons.info_outline_rounded),
                const SizedBox(width: EspaciadoApp.medio),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Cómo calibrar',
                      style: TipografiaApp.destacado.copyWith(
                        color: e.textoPrincipal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: EspaciadoApp.medio),
            Text(
              '1. Si la precisión no es alta, hacé un 8 en el aire.\n'
              '2. Apuntá el borde superior del teléfono hacia el «arriba» del '
              'plano.\n'
              '3. Tocá «Usar la dirección actual» y quedate quieto 2 s.\n'
              'Se guarda solo. El ajuste fino va con el deslizador.',
              style: TipografiaApp.cuerpo.copyWith(color: e.textoPrincipal),
            ),
          ],
        ),
      ),
      const SizedBox(height: EspaciadoApp.entreSecciones),
      // La flecha muestra el heading COMPENSADO: (heading_real - offset).
      // Cuando el offset esté bien calibrado, la flecha apuntará exactamente
      // hacia ARRIBA cuando el teléfono mire el borde superior del mapa. Al
      // mover el deslizador, la flecha se mueve en tiempo real: el operador
      // ajusta hasta que la flecha quede derecha con el teléfono apuntando al
      // borde superior del plano.
      Center(
        child: _FlechaBrujula(
          grados: heading == null
              ? null
              : ((heading - _rotacionMapa) % 360 + 360) % 360,
        ),
      ),
      const SizedBox(height: EspaciadoApp.medio),
      Text(
        heading != null
            ? 'Norte magnético: ${heading.toStringAsFixed(0)}° · offset '
                  'actual: ${_rotacionMapa.toStringAsFixed(0)}°'
            : 'Sin señal de brújula',
        textAlign: TextAlign.center,
        style: TipografiaApp.conCifrasTabulares(
          TipografiaApp.subtitulo,
        ).copyWith(color: e.textoSecundario),
      ),
      if (heading != null) ...[
        const SizedBox(height: EspaciadoApp.margenLateral),
        _indicadorPrecisionBrujula(e),
      ],
      const SizedBox(height: EspaciadoApp.entreSecciones),
      // Toma promediada del rumbo: la forma principal de calibrar.
      BotonPrincipal(
        texto: _tomaRumbo != null
            ? 'Midiendo… quedate quieto'
            : 'Usar la dirección actual',
        icono: Icons.my_location_rounded,
        alPresionar: heading == null || _tomaRumbo != null
            ? null
            : _tomarDireccionActual,
      ),
      const SizedBox(height: EspaciadoApp.entreSecciones),
      // Ajuste fino. Se guarda al soltarlo.
      Deslizador(
        etiqueta: 'Ajuste fino',
        valor: _rotacionMapa.clamp(0.0, 359.0),
        min: 0,
        max: 359,
        divisiones: 359,
        formato: (v) => '${v.round()}°',
        formatoSemantico: (v) => '${v.round()} grados',
        ayuda:
            '0° = Norte arriba · 90° = Este arriba · 180° = Sur arriba · '
            '270° = Oeste arriba',
        alCambiar: (v) {
          if (mounted) setState(() => _rotacionMapa = v.roundToDouble());
        },
        alTerminar: _fijarRotacion,
      ),
      const SizedBox(height: EspaciadoApp.entreSecciones),
      // Atajos.
      FilaBotones(children: [_atajo('Norte', 0), _atajo('Este', 90)]),
      const SizedBox(height: EspaciadoApp.medio),
      FilaBotones(children: [_atajo('Sur', 180), _atajo('Oeste', 270)]),
    ];
  }

  Widget _atajo(String nombre, double grados) => BotonSecundario(
    texto: '$nombre (${grados.round()}°)',
    compacto: true,
    alPresionar: () => _fijarRotacion(grados),
  );

  /// Precisión del sensor de la brújula, con la indicación de calibrarlo
  /// cuando no es alta (ver [_precisionBrujula]): en un recuadro hundido, con
  /// la tilde o, si no es alta, en ámbar con el aviso. TalkBack la anuncia
  /// cuando cambia.
  Widget _indicadorPrecisionBrujula(EstiloApp e) {
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
    return Semantics(
      container: true,
      liveRegion: true,
      child: PanelRelieve(
        hundido: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                alta ? Icons.check_circle_rounded : Icons.warning_rounded,
                size: FormasApp.iconoChico,
                color: alta ? e.textoSecundario : e.advertencia,
              ),
            ),
            const SizedBox(width: EspaciadoApp.medio),
            Expanded(
              child: Text(
                texto,
                style: TipografiaApp.subtitulo.copyWith(
                  color: alta ? e.textoPrincipal : e.advertencia,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatearTimestamp(DateTime t) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(t.day)}/${dos(t.month)} ${dos(t.hour)}:${dos(t.minute)}';
  }
}

// ─── CALIBRACIÓN GUARDADA ───────────────────────────────────────────────────

/// Una calibración guardada en la lista: el ícono (un punto clave, el pin),
/// el nombre y el detalle, que TalkBack lee juntos, y el tacho aparte.
class _FilaCalibracion extends StatelessWidget {
  const _FilaCalibracion({
    required this.puntoClave,
    required this.titulo,
    required this.detalle,
    required this.alEliminar,
  });

  final bool puntoClave;
  final String titulo;
  final String detalle;
  final VoidCallback alEliminar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final letraGrande = TipografiaApp.esLetraGrande(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormasApp.altoFilaMinimo),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EspaciadoApp.rellenoTarjeta,
          EspaciadoApp.chico,
          EspaciadoApp.chico,
          EspaciadoApp.chico,
        ),
        child: Row(
          children: [
            // Con letra grande, sin el cuadro (decorativo): el texto se queda
            // con el ancho.
            if (!letraGrande) ...[
              CuadroIcono(
                icono: puntoClave
                    ? Icons.push_pin_rounded
                    : Icons.check_circle_rounded,
              ),
              const SizedBox(width: EspaciadoApp.medio),
            ],
            Expanded(
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TipografiaApp.destacado.copyWith(
                        color: e.textoPrincipal,
                      ),
                    ),
                    Text(
                      detalle,
                      style: TipografiaApp.subtitulo.copyWith(
                        color: e.textoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: EspaciadoApp.medio),
            BotonRedondo(
              icono: Icons.delete_rounded,
              etiqueta: 'Eliminar $titulo',
              destructivo: true,
              alPresionar: alEliminar,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── FLECHA DE LA BRÚJULA ───────────────────────────────────────────────────

/// La flecha de la brújula en un círculo hundido, en acento (9,79 sobre lo
/// hundido). Sin brújula todavía, un reloj de arena quieto (nada gira). Es
/// decorativa: lo que dice va escrito debajo.
class _FlechaBrujula extends StatefulWidget {
  const _FlechaBrujula({required this.grados});

  /// Hacia dónde apunta, en grados (0 = arriba). null: todavía no hay
  /// lecturas de la brújula.
  final double? grados;

  @override
  State<_FlechaBrujula> createState() => _FlechaBrujulaState();
}

class _FlechaBrujulaState extends State<_FlechaBrujula> {
  static const double _diametro = 140;

  /// Las vueltas que se le dan a la flecha. No se quedan en [0, 1): de 359° a
  /// 1° la flecha gira 2° hacia adelante, no una vuelta entera hacia atrás.
  late double _vueltas = (widget.grados ?? 0) / 360;

  @override
  void didUpdateWidget(covariant _FlechaBrujula anterior) {
    super.didUpdateWidget(anterior);
    final grados = widget.grados;
    if (grados == null) return;
    final destino = grados / 360;
    _vueltas = destino + (_vueltas - destino).roundToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: _diametro,
        child: DecoratedBox(
          decoration: DecoracionRelieve(
            color: e.hundido,
            circulo: true,
            elevacion: -1,
            sombraOscura: e.sombraOscura,
            sombraClara: e.sombraClara,
          ),
          child: Center(
            child: widget.grados == null
                ? Icon(
                    Icons.hourglass_empty_rounded,
                    size: FormasApp.iconoGrande,
                    color: e.textoSecundario,
                  )
                : AnimatedRotation(
                    turns: _vueltas,
                    // La brújula cambia decenas de veces por segundo: como
                    // mucho 120 ms, lo de un cambio frecuente (sección 5.1 del
                    // prompt). Con movimiento reducido, sigue al dato directo.
                    duration: MovimientoApp.duracion(
                      context,
                      MovimientoApp.cambioProgreso,
                    ),
                    curve: MovimientoApp.curva,
                    child: Icon(
                      Icons.navigation_rounded,
                      size: 80,
                      color: e.acento,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── HOJAS ──────────────────────────────────────────────────────────────────

/// La hoja "Filtrar dispositivos": el nombre y la potencia mínima. Devuelve
/// el filtro nuevo, o null si se cancela.
class _HojaFiltro extends StatefulWidget {
  const _HojaFiltro({
    required this.nombre,
    required this.potencia,
    required this.hayFiltro,
  });

  final String nombre;
  final int potencia;

  /// Si ya hay un filtro puesto: entonces está "Quitar filtro".
  final bool hayFiltro;

  @override
  State<_HojaFiltro> createState() => _HojaFiltroState();
}

class _HojaFiltroState extends State<_HojaFiltro> {
  static const int _sin = _PantallaConfiguracionState._sinPotenciaMinima;

  late final TextEditingController _nombre = TextEditingController(
    text: widget.nombre,
  );
  late double _minima = widget.potencia.toDouble();

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _filtrar() => Navigator.of(
    context,
  ).pop((nombre: _nombre.text.trim(), potencia: _minima.round()));

  static String _potencia(double v) =>
      v <= _sin ? 'Todas' : 'Desde ${v.round()} dBm';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoTexto(
          etiqueta: 'Nombre',
          ayuda: 'Por ejemplo, BlindRoute (vacío: todos)',
          controlador: _nombre,
          accionTeclado: TextInputAction.search,
          autocorrector: false,
          alEnviar: (_) => _filtrar(),
        ),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        Deslizador(
          etiqueta: 'Potencia mínima',
          valor: _minima,
          min: _sin.toDouble(),
          max: -40,
          divisiones: 12,
          formato: _potencia,
          alCambiar: (v) => setState(() => _minima = v),
        ),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        if (widget.hayFiltro) ...[
          BotonSecundario(
            texto: 'Quitar filtro',
            icono: Icons.filter_alt_off_rounded,
            expandido: true,
            alPresionar: () =>
                Navigator.of(context).pop((nombre: '', potencia: _sin)),
          ),
          const SizedBox(height: EspaciadoApp.medio),
        ],
        FilaBotones(
          children: [
            BotonSecundario(
              texto: 'Cancelar',
              alPresionar: () => Navigator.of(context).pop(),
            ),
            BotonPrincipal(
              texto: 'Filtrar',
              icono: Icons.filter_alt_rounded,
              expandido: false,
              alPresionar: _filtrar,
            ),
          ],
        ),
      ],
    );
  }
}

/// La hoja "Nombre de la zona": el nombre, que puede quedar vacío. Devuelve
/// lo escrito, o null si se cancela.
class _HojaNombreZona extends StatefulWidget {
  const _HojaNombreZona();

  @override
  State<_HojaNombreZona> createState() => _HojaNombreZonaState();
}

class _HojaNombreZonaState extends State<_HojaNombreZona> {
  final TextEditingController _nombre = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _guardar() => Navigator.of(context).pop(_nombre.text.trim());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoTexto(
          etiqueta: 'Nombre (opcional)',
          ayuda: 'Por ejemplo, Escaleras o Ascensor',
          pie: 'Si lo dejás vacío, se llama «Zona prohibida».',
          controlador: _nombre,
          autofocus: true,
          capitalizacion: TextCapitalization.sentences,
          accionTeclado: TextInputAction.done,
          alEnviar: (_) => _guardar(),
        ),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        FilaBotones(
          children: [
            BotonSecundario(
              texto: 'Cancelar',
              alPresionar: () => Navigator.of(context).pop(),
            ),
            BotonPrincipal(
              texto: 'Guardar',
              icono: Icons.check_rounded,
              expandido: false,
              alPresionar: _guardar,
            ),
          ],
        ),
      ],
    );
  }
}

/// La hoja de los metros del largo o del ancho de la escala. Devuelve los
/// metros, o null si se cancela. Si lo escrito no es un número mayor que 0,
/// lo dice debajo del campo (antes no pasaba nada).
class _HojaMetros extends StatefulWidget {
  const _HojaMetros({required this.mensaje});

  /// La pregunta ("¿Cuántos metros mide el largo en la realidad?").
  final String mensaje;

  @override
  State<_HojaMetros> createState() => _HojaMetrosState();
}

class _HojaMetrosState extends State<_HojaMetros> {
  final TextEditingController _metros = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _metros.dispose();
    super.dispose();
  }

  void _guardar() {
    final v = double.tryParse(_metros.text.trim().replaceAll(',', '.'));
    if (v != null && v > 0) {
      Navigator.of(context).pop(v);
      return;
    }
    setState(() => _error = 'Escribí un número mayor que 0.');
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.mensaje,
          style: TipografiaApp.cuerpo.copyWith(color: e.textoPrincipal),
        ),
        const SizedBox(height: EspaciadoApp.margenLateral),
        CampoTexto(
          etiqueta: 'Metros',
          ayuda: 'Por ejemplo, 12,5',
          sufijo: 'm',
          controlador: _metros,
          tipoTeclado: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          accionTeclado: TextInputAction.done,
          error: _error,
          // Escribir le borra el error.
          alCambiar: (_) {
            if (_error != null) setState(() => _error = null);
          },
          alEnviar: (_) => _guardar(),
        ),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        FilaBotones(
          children: [
            BotonSecundario(
              texto: 'Cancelar',
              alPresionar: () => Navigator.of(context).pop(),
            ),
            BotonPrincipal(
              texto: 'Guardar',
              icono: Icons.check_rounded,
              expandido: false,
              alPresionar: _guardar,
            ),
          ],
        ),
      ],
    );
  }
}

// ─── HOJA DE ALTA DE LUGAR / ESCALERA ───────────────────────────────────────

/// Resultado de la hoja de alta.
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

/// La hoja de un lugar, una escalera o un ascensor (antes, un diálogo): lo
/// mismo que antes, con los componentes del sistema de diseño. El tipo es un
/// control segmentado; el rubro, una fila que abre la lista de rubros en otra
/// hoja (antes, un desplegable); escalera o ascensor, para dónde va y hacia
/// dónde da la entrada, chips que se eligen. Lo que falta para guardar, en
/// ámbar debajo.
class _HojaLugar extends StatefulWidget {
  /// Lugar que se está editando. Null = alta de uno nuevo.
  final LugarInteres? inicial;

  const _HojaLugar({this.inicial});

  @override
  State<_HojaLugar> createState() => _HojaLugarState();
}

class _HojaLugarState extends State<_HojaLugar> {
  final _nombreCtrl = TextEditingController();
  final _clavesCtrl = TextEditingController();

  TipoLugar _tipo = TipoLugar.comun;
  _SentidoEscalera? _sentido;
  double? _direccion; // 0 arriba, 90 derecha, 180 abajo, 270 izquierda

  /// Id del rubro elegido (null = sin rubro).
  String? _rubro;

  /// Con tipo escalera: si lo que se está cargando es un ascensor.
  bool _esAscensor = false;

  /// "la escalera" / "el ascensor", para los textos de la hoja.
  String get _elMedio => _esAscensor ? 'el ascensor' : 'la escalera';

  @override
  void initState() {
    super.initState();
    final l = widget.inicial;
    if (l == null) return;
    _nombreCtrl.text = l.nombre;
    _clavesCtrl.text = LugarInteres.palabrasATexto(l.palabrasClave) ?? '';
    // Si el mapa trae un rubro que esta versión no conoce, se muestra como
    // "sin rubro" (la lista exige que el valor exista).
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

  /// Abre el catálogo de rubros. Al volver, la fila del rubro se rearma con
  /// lo que haya quedado y, si se borró el rubro elegido, queda "Sin rubro".
  Future<void> _administrarRubros() async {
    await Navigator.push(
      context,
      RutaApp<void>(builder: (_) => const PantallaRubros()),
    );
    if (!mounted) return;
    setState(() => _rubro = Rubros.porId(_rubro)?.id);
  }

  /// Elige el rubro en otra hoja, con la lista de rubros.
  Future<void> _elegirRubro() async {
    final elegido = await mostrarHoja<String>(
      context,
      titulo: 'Rubro',
      contenido: (context) => _ListaRubros(actual: _rubro),
    );
    if (elegido == null || !mounted) return;
    setState(() => _rubro = elegido.isEmpty ? null : elegido);
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
        sube:
            _sentido == _SentidoEscalera.sube ||
            _sentido == _SentidoEscalera.ambas,
        baja:
            _sentido == _SentidoEscalera.baja ||
            _sentido == _SentidoEscalera.ambas,
        direccionEntrada: _direccion,
      ),
    );
  }

  /// Una pregunta de la hoja ("¿Qué es?"), arriba de sus opciones.
  Widget _pregunta(EstiloApp e, String texto) => Text(
    texto,
    style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
  );

  /// El rubro: una fila que abre la lista de rubros, con el ícono del rubro
  /// elegido y las palabras con que se encuentra.
  Widget _selectorRubro(EstiloApp e) {
    final r = Rubros.porId(_rubro);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // TalkBack lo dice en la fila.
        ExcludeSemantics(child: _pregunta(e, 'Rubro')),
        const SizedBox(height: EspaciadoApp.medio),
        GrupoFilas(
          filas: [
            FilaGrupo(
              inicio: CuadroIcono(
                icono: r == null ? Icons.label_off_rounded : iconoRubro(r.id),
                color: r == null ? e.textoSecundario : null,
              ),
              titulo: r?.nombre ?? 'Sin rubro',
              subtitulo: _ayudaRubro,
              navega: true,
              etiquetaSemantica:
                  'Rubro: ${r?.nombre ?? 'sin rubro'}. $_ayudaRubro',
              alTocar: _elegirRubro,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final faltante = _faltante;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ControlSegmentado<TipoLugar>(
          etiqueta: 'Tipo',
          opciones: const [
            OpcionSegmento(
              valor: TipoLugar.comun,
              texto: 'Lugar',
              icono: Icons.place_rounded,
            ),
            // Escalera o ascensor: se elige abajo, al entrar acá.
            OpcionSegmento(
              valor: TipoLugar.escalera,
              texto: 'Escalera',
              icono: Icons.stairs_rounded,
              etiquetaSemantica: 'Escalera o ascensor',
            ),
          ],
          seleccionada: _tipo,
          alCambiar: (t) => setState(() => _tipo = t),
        ),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        CampoTexto(
          etiqueta: _esEscalera ? 'Nombre (opcional)' : 'Nombre',
          ayuda: !_esEscalera
              ? 'Por ejemplo, Baño o Terminal 5'
              : _esAscensor
              ? 'Por ejemplo, Ascensor norte'
              : 'Por ejemplo, Escalera norte',
          controlador: _nombreCtrl,
          capitalizacion: TextCapitalization.sentences,
          alCambiar: (_) => setState(() {}),
        ),
        if (!_esEscalera) ...[
          const SizedBox(height: EspaciadoApp.entreSecciones),
          // Rubro: trae cargadas las palabras con las que la gente pide ese
          // tipo de lugar (ver rubros.dart).
          _selectorRubro(e),
          const SizedBox(height: EspaciadoApp.medio),
          Align(
            alignment: Alignment.centerRight,
            child: BotonSecundario(
              texto: 'Editar rubros',
              icono: Icons.tune_rounded,
              compacto: true,
              alPresionar: _administrarRubros,
            ),
          ),
          const SizedBox(height: EspaciadoApp.entreSecciones),
          CampoTexto(
            etiqueta: 'Otras palabras (opcional)',
            ayuda: 'el mac, mc',
            pie:
                'Apodos o marcas de este lugar, separados por comas. Lo '
                'general ya lo pone el rubro.',
            controlador: _clavesCtrl,
            lineas: 3,
          ),
        ],
        if (_esEscalera) ...[
          const SizedBox(height: EspaciadoApp.entreSecciones),
          _pregunta(e, '¿Qué es?'),
          const SizedBox(height: EspaciadoApp.chico),
          Wrap(
            spacing: EspaciadoApp.chico,
            runSpacing: EspaciadoApp.chico,
            children: [
              ChipFiltro(
                texto: 'Escalera',
                exclusivo: true,
                seleccionado: !_esAscensor,
                alCambiar: (_) => setState(() => _esAscensor = false),
              ),
              ChipFiltro(
                texto: 'Ascensor',
                exclusivo: true,
                seleccionado: _esAscensor,
                alCambiar: (_) => setState(() => _esAscensor = true),
              ),
            ],
          ),
          const SizedBox(height: EspaciadoApp.margenLateral),
          _pregunta(e, 'Desde este piso, $_elMedio:'),
          const SizedBox(height: EspaciadoApp.chico),
          Wrap(
            spacing: EspaciadoApp.chico,
            runSpacing: EspaciadoApp.chico,
            children: [
              for (final (sentido, texto) in const [
                (_SentidoEscalera.sube, 'Sube'),
                (_SentidoEscalera.baja, 'Baja'),
                (_SentidoEscalera.ambas, 'Sube y baja'),
              ])
                ChipFiltro(
                  texto: texto,
                  exclusivo: true,
                  seleccionado: _sentido == sentido,
                  alCambiar: (_) => setState(() => _sentido = sentido),
                ),
            ],
          ),
          const SizedBox(height: EspaciadoApp.margenLateral),
          _pregunta(e, '¿Hacia qué lado del plano da la entrada?'),
          const SizedBox(height: EspaciadoApp.minimo),
          Text(
            _esAscensor
                ? 'El lado de la puerta, según el plano en pantalla.'
                : 'El lado por donde se entra a la escalera, según el plano '
                      'en pantalla.',
            style: TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
          ),
          const SizedBox(height: EspaciadoApp.chico),
          _CruzDireccion(
            direccion: _direccion,
            esAscensor: _esAscensor,
            alElegir: (grados) => setState(() => _direccion = grados),
          ),
        ],
        if (faltante != null) ...[
          const SizedBox(height: EspaciadoApp.entreSecciones),
          _Falta(texto: faltante),
        ],
        const SizedBox(height: EspaciadoApp.entreSecciones),
        FilaBotones(
          children: [
            BotonSecundario(
              texto: 'Cancelar',
              alPresionar: () => Navigator.of(context).pop(),
            ),
            BotonPrincipal(
              texto: 'Guardar',
              icono: Icons.check_rounded,
              expandido: false,
              alPresionar: faltante == null ? _guardar : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Hacia qué lado del plano da la entrada de una escalera o un ascensor:
/// cuatro chips en cruz alrededor del ícono (se elige uno). Con letra
/// grande, uno al lado del otro y, si no entran, en renglones.
class _CruzDireccion extends StatelessWidget {
  const _CruzDireccion({
    required this.direccion,
    required this.esAscensor,
    required this.alElegir,
  });

  /// En grados: 0 arriba, 90 derecha, 180 abajo, 270 izquierda.
  final double? direccion;
  final bool esAscensor;
  final ValueChanged<double> alElegir;

  Widget _opcion(double grados, String texto, String lado) => ChipFiltro(
    texto: texto,
    exclusivo: true,
    seleccionado: direccion == grados,
    etiquetaSemantica: 'Entrada hacia $lado del plano',
    alCambiar: (_) => alElegir(grados),
  );

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final arriba = _opcion(0, 'Arriba', 'arriba');
    final izquierda = _opcion(270, 'Izquierda', 'la izquierda');
    final derecha = _opcion(90, 'Derecha', 'la derecha');
    final abajo = _opcion(180, 'Abajo', 'abajo');
    if (TipografiaApp.esLetraGrande(context)) {
      return Wrap(
        spacing: EspaciadoApp.chico,
        runSpacing: EspaciadoApp.chico,
        children: [arriba, izquierda, derecha, abajo],
      );
    }
    return Column(
      children: [
        arriba,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            izquierda,
            const SizedBox(width: EspaciadoApp.medio),
            ExcludeSemantics(
              child: Icon(
                esAscensor ? Icons.elevator_rounded : Icons.stairs_rounded,
                size: 32,
                color: e.textoSecundario,
              ),
            ),
            const SizedBox(width: EspaciadoApp.medio),
            derecha,
          ],
        ),
        abajo,
      ],
    );
  }
}

/// La lista de rubros para elegir uno (en su hoja): "Sin rubro" y cada
/// rubro con su ícono y algunas de sus palabras. El elegido, con el borde y
/// la tilde en acento. Devuelve el id ("" para "Sin rubro").
class _ListaRubros extends StatelessWidget {
  const _ListaRubros({required this.actual});

  /// El id del rubro elegido ahora (null: sin rubro).
  final String? actual;

  @override
  Widget build(BuildContext context) {
    void elegir(String id) => Navigator.of(context).pop(id);
    final elegido = actual ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TarjetaDestino(
          icono: Icons.label_off_rounded,
          nombre: 'Sin rubro',
          seleccionada: elegido.isEmpty,
          alTocar: () => elegir(''),
        ),
        for (final r in Rubros.todos) ...[
          const SizedBox(height: EspaciadoApp.entreTarjetas),
          TarjetaDestino(
            icono: iconoRubro(r.id),
            nombre: r.nombre,
            detalle:
                '${r.palabras.take(3).join(', ')}'
                '${r.palabras.length > 3 ? '…' : ''}',
            seleccionada: elegido == r.id,
            alTocar: () => elegir(r.id),
          ),
        ],
      ],
    );
  }
}

/// Lo que falta para poder guardar, en ámbar (9,59 sobre la superficie) y
/// con un ícono.
class _Falta extends StatelessWidget {
  const _Falta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.info_rounded,
            size: FormasApp.iconoChico,
            color: e.advertencia,
          ),
        ),
        const SizedBox(width: EspaciadoApp.chico),
        Expanded(
          child: Text(
            texto,
            style: TipografiaApp.subtitulo.copyWith(color: e.advertencia),
          ),
        ),
      ],
    );
  }
}
