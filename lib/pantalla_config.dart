import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'database.dart';
import 'procesador_senal.dart';
import 'posicionador.dart';
import 'mapa_widget.dart';
import 'bluetooth_helper.dart';
import 'grilla_nav.dart';
import 'asistente_trazo.dart';
import 'calibracion_model.dart';
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

  // Medición interactiva de escala.
  final List<Offset> _puntosEscala = []; // P1, P2 (largo), P3 (ancho)
  Offset? _elasticoDesde;                 // origen de la línea elástica en curso
  Offset? _elasticoHasta;                 // extremo actual durante el arrastre
  int _pasoEscala = 0;                    // 0 = largo, 1 = ancho, 2 = listo
  double? _largoMetros;                   // metros del largo (P1→P2)
  double? _anchoMetros;                   // metros del ancho (P2→P3)

  // Edición de puntos ya marcados: índice del punto que se está arrastrando
  // para reacomodarlo (null = no se está moviendo ningún punto, la interacción
  // dibuja un segmento nuevo). Radio de "agarre" de un punto en coords
  // normalizadas: un toque dentro de este radio mueve el punto en vez de
  // empezar un trazo nuevo.
  int? _puntoArrastrado;
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

  // ── Asistente de trazo (líneas rectas, estilo Canva) ──────────────────────
  // Cuando el trazo se acerca a un ángulo notable el punto se corrige para que
  // la línea quede exactamente recta, se dibujan guías punteadas y se emite un
  // pulso háptico. Se puede apagar para dibujar ángulos libres a propósito.
  bool _asistenteRecto = true;
  List<GuiaTrazo> _guias = const [];
  Offset? _guiaPunto;

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
    _cargarDatosIniciales();
  }

  @override
  void dispose() {
    _etiquetaCalCtrl.dispose();
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
      final filas = await db.query('pisos', columns: ['rotacion_mapa'], where: 'id = ?', whereArgs: [widget.pisoId], limit: 1);
      final rotGuardada = filas.isNotEmpty ? ((filas.first['rotacion_mapa'] as num?)?.toDouble() ?? 0.0) : 0.0;

      if (mounted) {
        setState(() {
          _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
          _zonas = zonas;
          _lugares = lugares;
          _calibraciones = calibraciones;
          _rotacionMapa = rotGuardada;
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

  // -- Beacons ---------------------------------------------------------------

  void _borrarBeacon(String mac) async {
    try {
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

  /// MAC del beacon ubicado cuyo ícono cae dentro del radio de agarre de [n],
  /// o null. Si hay varios, el más cercano.
  String? _beaconCercano(Offset n) {
    String? mejor;
    double mejorDist = _radioAgarreBeacon;
    for (final b in _beaconsEnElMapa.values) {
      final d = (b.posicion - n).distance;
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
    final mac = _beaconCercano(n);
    if (mac != null) setState(() => _beaconArrastrado = mac);
  }

  void _onArrastreActualizarBeacon(Offset n) {
    if (!mounted || _beaconArrastrado == null) return;
    final b = _beaconsEnElMapa[_beaconArrastrado!];
    if (b == null) return;
    // posicion es mutable; recortada a [0,1]. El repintado sale del setState.
    setState(() {
      b.posicion = Offset(n.dx.clamp(0.0, 1.0), n.dy.clamp(0.0, 1.0));
    });
  }

  Future<void> _onArrastreFinBeacon() async {
    if (!mounted) return;
    final movio = _beaconArrastrado != null;
    setState(() => _beaconArrastrado = null);
    if (movio) await _sincronizarBeacons(); // persistir la nueva ubicación
  }

  void _onArrastreCancelarBeacon() {
    if (!mounted) return;
    // Segundo dedo (zoom): se deja el beacon donde quedó y se suelta el
    // arrastre; se persiste igual para no perder el reacomodo parcial.
    final movio = _beaconArrastrado != null;
    setState(() => _beaconArrastrado = null);
    if (movio) _sincronizarBeacons();
  }

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

  void _actualizarSenales(List<ScanResult> resultados) {
    if (!mounted) return;
    for (var res in resultados) {
      try {
        String mac = res.device.remoteId.str;
        // Solo procesar beacons ya marcados. El scan ve TODOS los dispositivos
        // del ambiente; filtrar los ajenos solo llenaba las ventanas del
        // ProcesadorSenal con MAC cuyo resultado nunca se lee (fuga de
        // memoria/CPU). La lista de dispositivos para marcar nuevos beacons se
        // muestra aparte, desde `_dispositivosCercanos` (resultados crudos).
        if (!_beaconsEnElMapa.containsKey(mac)) continue;

        double? rssiSuave = _procesador.filtrarYPromediar(mac, res.rssi);
        if (rssiSuave != null) {
          setState(() => _beaconsEnElMapa[mac]!.rssiFiltrado = rssiSuave);
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
    // (ver la nota en _inicioToma). _muestrasAcumuladas se sigue llevando, pero
    // ahora solo como dato informativo de cuantos lotes entraron.
    if (_tomandoMuestras) {
      // Acumular el rumbo mientras dura la toma (media circular).
      final h = _headingEnVivo;
      if (h != null) {
        final r = h * pi / 180;
        _sumSenoRumbo += sin(r);
        _sumCosRumbo += cos(r);
        _muestrasRumbo++;
      }
      setState(() => _muestrasAcumuladas++);
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
            hintText: 'Ej: Escaleras, Ascensor (deja vacio para usar nombre por defecto)',
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
    double mejorDist = _radioAgarreVertice;
    for (int i = 0; i < _verticesEnCurso.length; i++) {
      final d = (_verticesEnCurso[i] - n).distance;
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

    // 2) Sin zona en curso, un toque dentro de una zona ya guardada significa
    //    "borrar esa zona" (lo maneja el tap interno del MapaWidget): no se
    //    empieza un polígono nuevo encima.
    if (_verticesEnCurso.isEmpty) {
      for (final zona in _zonas) {
        if (zona.vertices.length >= 3 &&
            MapaWidget.puntoEnPoligono(n, zona.vertices)) {
          return;
        }
      }
    }

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

  void _agregarLugar(Offset normalizado) async {
    final controller = TextEditingController();
    final descController = TextEditingController();

    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Lugar de Interes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Nombre (ej: Bano, Terminal 5)',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                hintText: 'Descripcion opcional',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final n = controller.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, n);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nombre == null || nombre.isEmpty) return;

    try {
      final lugar = LugarInteres(
        pisoId: widget.pisoId,
        nombre: nombre,
        posicion: normalizado,
        descripcion: descController.text.trim().isEmpty ? null : descController.text.trim(),
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

  void _borrarLugar(LugarInteres lugar) async {
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
    if (_modo == _ModoEdicion.beacons) {
      if (_seleccionado == null) return;
      // Si el toque cayó sobre un beacon ya ubicado, no se coloca uno nuevo
      // encima: ese gesto es para arrastrar (lo maneja el canal de un dedo).
      if (_beaconCercano(normalizado) != null) return;
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
        setState(() => _headingEnVivo = event.heading);
      }
    });
  }

  void _detenerCompass() {
    _compassConfigSub?.cancel();
    _compassConfigSub = null;
    if (mounted) setState(() => _headingEnVivo = null);
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
      if (muestras.isEmpty) continue;

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
            'Punto clave NO guardado: solo ${lecturas.length} beacon(s) '
            'visibles y hacen falta 3. Probá desde una celda con mejor '
            'cobertura.',
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

  // -- Escala (medición interactiva con línea elástica) ----------------------

  void _reiniciarMedicion() {
    if (!mounted) return;
    setState(() {
      _puntosEscala.clear();
      _elasticoDesde = null;
      _elasticoHasta = null;
      _pasoEscala = 0;
      _largoMetros = null;
      _anchoMetros = null;
      _puntoArrastrado = null;
      _limpiarGuias();
    });
  }

  /// Devuelve el índice del punto de escala más cercano a [n] si está dentro del
  /// radio de agarre, o null si el toque no cae sobre ningún punto ya marcado.
  int? _puntoCercano(Offset n) {
    int? mejorIdx;
    double mejorDist = _radioAgarrePunto;
    for (int i = 0; i < _puntosEscala.length; i++) {
      final d = (_puntosEscala[i] - n).distance;
      if (d <= mejorDist) {
        mejorDist = d;
        mejorIdx = i;
      }
    }
    return mejorIdx;
  }

  void _onArrastreInicio(Offset n) {
    if (!mounted) return;

    // Prioridad 1: si el toque cae sobre un punto ya marcado, se arrastra ese
    // punto para reacomodarlo (en vez de empezar un trazo nuevo).
    final idx = _puntoCercano(n);
    if (idx != null) {
      final a = _anclasEscala(idx);
      final p = _aplicarAsistente(n, ancla: a.ancla, anclaSecundaria: a.sec);
      setState(() {
        _puntoArrastrado = idx;
        _puntosEscala[idx] = p;
        _elasticoDesde = null;
        _elasticoHasta = null;
      });
      return;
    }

    // Prioridad 2: trazo nuevo según el paso.
    setState(() {
      if (_pasoEscala == 0) {
        // Fijar punto inicial (violeta) y empezar la línea elástica del largo.
        // El primer punto no tiene ancla: no hay nada con qué alinearlo.
        _limpiarGuias();
        _puntosEscala
          ..clear()
          ..add(n);
        _elasticoDesde = n;
        _elasticoHasta = n;
      } else if (_pasoEscala == 1) {
        // El ancho parte del segundo punto (P2), sin importar dónde se toque.
        _elasticoDesde = _puntosEscala[1];
        _elasticoHasta = _aplicarAsistente(n, ancla: _puntosEscala[1]);
      }
      // En paso 2 (medición completa) un toque en zona libre no hace nada:
      // solo se pueden mover los puntos. Para medir de nuevo: "Reiniciar".
    });
  }

  void _onArrastreActualizar(Offset n) {
    if (!mounted) return;
    // Si estamos moviendo un punto, actualizamos su posición (imantada).
    if (_puntoArrastrado != null) {
      final a = _anclasEscala(_puntoArrastrado!);
      final p = _aplicarAsistente(n, ancla: a.ancla, anclaSecundaria: a.sec);
      setState(() => _puntosEscala[_puntoArrastrado!] = p);
      return;
    }
    if (_elasticoDesde == null) return;
    // El extremo libre de la línea elástica se imanta contra su origen: es lo
    // que hace que el largo y el ancho del plano queden perfectamente rectos.
    final p = _aplicarAsistente(n, ancla: _elasticoDesde);
    setState(() => _elasticoHasta = p);
  }

  /// El usuario apoyó un segundo dedo para hacer zoom: descartamos la línea
  /// elástica a medio dibujar sin perder lo ya confirmado (el largo en paso 1).
  void _onArrastreCancelar() {
    if (!mounted) return;
    setState(() {
      _limpiarGuias();
      // Si se estaba moviendo un punto, se deja donde quedó (no se revierte).
      if (_puntoArrastrado != null) {
        _puntoArrastrado = null;
        return;
      }
      if (_pasoEscala == 0) {
        // Todavía no se confirmó el largo: descartar el punto inicial también.
        _puntosEscala.clear();
      } else if (_pasoEscala == 1 && _puntosEscala.length >= 3) {
        // Mantener P1, P2 y el largo; descartar la tentativa de ancho.
        _puntosEscala.removeRange(2, _puntosEscala.length);
      }
      _elasticoDesde = null;
      _elasticoHasta = null;
    });
  }

  Future<void> _onArrastreFin() async {
    if (mounted) setState(_limpiarGuias);
    // Caso A: se estaba reacomodando un punto ya existente.
    if (_puntoArrastrado != null) {
      if (mounted) setState(() => _puntoArrastrado = null);
      // Si la medición ya estaba completa, recalcular y persistir la escala con
      // las posiciones corregidas (los metros de referencia no cambian).
      if (_pasoEscala == 2) {
        await _recalcularYGuardarEscala(mostrarAviso: false);
      }
      return;
    }

    if (_elasticoDesde == null || _elasticoHasta == null) return;
    final fin = _elasticoHasta!;

    if (_pasoEscala == 0) {
      // Cerrar el segmento de largo: P2.
      setState(() {
        if (_puntosEscala.length >= 2) _puntosEscala.removeRange(1, _puntosEscala.length);
        _puntosEscala.add(fin);
        _elasticoDesde = null;
        _elasticoHasta = null;
      });
      final metros = await _pedirMetros('Largo de la línea',
          'Marcaste el LARGO. ¿Cuántos metros mide en la vida real?');
      if (metros == null) {
        _reiniciarMedicion();
        return;
      }
      if (mounted) setState(() { _largoMetros = metros; _pasoEscala = 1; });
    } else if (_pasoEscala == 1) {
      // Cerrar el segmento de ancho: P3 (obligatorio).
      setState(() {
        if (_puntosEscala.length >= 3) _puntosEscala.removeRange(2, _puntosEscala.length);
        _puntosEscala.add(fin);
        _elasticoDesde = null;
        _elasticoHasta = null;
      });
      final metros = await _pedirMetros('Ancho de la línea',
          'Marcaste el ANCHO. ¿Cuántos metros mide en la vida real?');
      if (metros == null) {
        // Volver a permitir re-marcar el ancho sin perder el largo.
        if (mounted) {
          setState(() {
            if (_puntosEscala.length >= 3) _puntosEscala.removeRange(2, _puntosEscala.length);
          });
        }
        return;
      }
      if (mounted) setState(() => _anchoMetros = metros);
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
          _elasticoDesde = null;
          _elasticoHasta = null;
          _pasoEscala = 2;
        });
        if (mostrarAviso) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              'Escala guardada: ${escalaX.toStringAsFixed(1)} m × ${escalaY.toStringAsFixed(1)} m '
              '→ grilla de ${_grilla.celdasX} × ${_grilla.celdasY} celdas de ${_tamCelda.toStringAsFixed(1)} m. '
              'Podés arrastrar los puntos para ajustar.',
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

  String _hintTexto() {
    switch (_modo) {
      case _ModoEdicion.beacons:
        return 'Seleccioná un dispositivo de la lista y tocá el mapa para ubicarlo. Arrastrá la mira de un beacon para reacomodarlo (zoom con dos dedos). Long-press sobre un beacon para eliminarlo.';
      case _ModoEdicion.zonas:
        if (_verticesEnCurso.isEmpty) {
          return 'Tocá el mapa para marcar los vértices de la zona (podés arrastrar sin soltar para afinar el punto). Necesitás al menos 3. Tocá una zona existente para borrarla.';
        }
        return '${_verticesEnCurso.length} punto(s) marcado(s). Arrastrá cualquier punto naranja para corregir su ubicación. Seguí tocando para agregar más, o cerrá la zona.';
      case _ModoEdicion.lugares:
        return 'Toca el mapa para agregar un lugar de interes. Toca el icono morado para eliminarlo.';
      case _ModoEdicion.escala:
        final actual = 'Escala actual: ${_escalaX.toStringAsFixed(1)} m × ${_escalaY.toStringAsFixed(1)} m '
            '(grilla ${_grilla.celdasX}×${_grilla.celdasY}).';
        if (_pasoEscala == 0) {
          return '$actual Arrastrá desde un punto para marcar el LARGO e ingresá sus metros.';
        }
        if (_pasoEscala == 1) {
          return '$actual Largo: ${_largoMetros?.toStringAsFixed(1)} m. Arrastrá desde una zona libre para marcar el ANCHO. Podés tocar y arrastrar los puntos violetas para corregirlos.';
        }
        return '$actual Medición lista. Arrastrá cualquiera de los 3 puntos violetas para acomodarlos: la escala se recalcula sola. "Reiniciar" para medir de nuevo.';
      case _ModoEdicion.calibracion:
        if (_celdaCalSeleccionada == null) {
          return 'Tocá en el mapa la celda donde estás parado para calibrar.';
        }
        final c = _celdaCalSeleccionada!;
        return 'Celda (${c.ix},${c.iy}) seleccionada. Registrá la calibración desde el panel inferior.';
      case _ModoEdicion.brujula:
        return 'Apuntá el teléfono hacia el borde SUPERIOR del mapa y ajustá el offset hasta que la flecha coincida. Tocá Guardar cuando esté correcto.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(
          title: const Text('Configuración de Piso'),
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
                    _verticesEnCurso = [];
                    _seleccionado = null;
                    // Reiniciar la medición de escala al cambiar de modo.
                    _puntosEscala.clear();
                    _elasticoDesde = null;
                    _elasticoHasta = null;
                    _pasoEscala = 0;
                    _largoMetros = null;
                    _anchoMetros = null;
                    _puntoArrastrado = null;
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
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                child: InteractiveViewer(
                  // En escala y en zonas, UN dedo dibuja o arrastra puntos, así
                  // que se desactiva el pan de un dedo; el zoom de dos dedos
                  // queda siempre activo (al apoyar el segundo dedo el gesto en
                  // curso se cancela y el InteractiveViewer hace zoom).
                  // En escala, zonas y beacons UN dedo dibuja/arrastra puntos,
                  // así que se desactiva el pan de un dedo; el zoom de dos dedos
                  // queda siempre activo.
                  panEnabled: _modo != _ModoEdicion.escala &&
                      _modo != _ModoEdicion.zonas &&
                      _modo != _ModoEdicion.beacons,
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
                    onTapMapa: _modo == _ModoEdicion.zonas ? null : _onTapMapa,
                    onTapBeacon: _borrarBeacon,
                    onTapLugar: _borrarLugar,
                    // Borrar una zona existente solo cuando NO hay un polígono
                    // en curso: mientras se dibuja, un toque adentro de otra
                    // zona agrega un vértice (permite zonas superpuestas).
                    onTapZona: _modo == _ModoEdicion.zonas && _verticesEnCurso.isEmpty
                        ? _borrarZona
                        : null,
                    verticesEnCurso: _verticesEnCurso,
                    verticeArrastrado:
                        _modo == _ModoEdicion.zonas ? _verticeArrastrado : null,
                    // Guías del asistente de trazo (magenta punteado).
                    guias: _guias,
                    guiaPunto: _guiaPunto,
                    // Copia nueva en cada build: el painter compara por
                    // referencia, así que al mover un punto (mutación in-place)
                    // esta copia fuerza el repintado en cada frame del arrastre.
                    puntosMedicion: _modo == _ModoEdicion.escala ? List.of(_puntosEscala) : const [],
                    elasticoDesde: _modo == _ModoEdicion.escala ? _elasticoDesde : null,
                    elasticoHasta: _modo == _ModoEdicion.escala ? _elasticoHasta : null,
                    // Gestos de un dedo: la medición de escala y la edición de
                    // vértices de zonas comparten el mismo canal.
                    onArrastreInicio: _modo == _ModoEdicion.escala
                        ? _onArrastreInicio
                        : _modo == _ModoEdicion.zonas
                            ? _onArrastreInicioZona
                            : _modo == _ModoEdicion.beacons
                                ? _onArrastreInicioBeacon
                                : null,
                    onArrastreActualizar: _modo == _ModoEdicion.escala
                        ? _onArrastreActualizar
                        : _modo == _ModoEdicion.zonas
                            ? _onArrastreActualizarZona
                            : _modo == _ModoEdicion.beacons
                                ? _onArrastreActualizarBeacon
                                : null,
                    onArrastreFin: _modo == _ModoEdicion.escala
                        ? _onArrastreFin
                        : _modo == _ModoEdicion.zonas
                            ? _onArrastreFinZona
                            : _modo == _ModoEdicion.beacons
                                ? _onArrastreFinBeacon
                                : null,
                    onArrastreCancelar: _modo == _ModoEdicion.escala
                        ? _onArrastreCancelar
                        : _modo == _ModoEdicion.zonas
                            ? _onArrastreCancelarZona
                            : _modo == _ModoEdicion.beacons
                                ? _onArrastreCancelarBeacon
                                : null,
                    beaconArrastrado:
                        _modo == _ModoEdicion.beacons ? _beaconArrastrado : null,
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
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_puntosEscala.isNotEmpty || _pasoEscala != 0)
                          ? _reiniciarMedicion
                          : null,
                      icon: const Icon(Icons.undo),
                      label: const Text('Reiniciar medición'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
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
                  Expanded(
                    child: ListView.builder(
                      itemCount: _dispositivosCercanos.length,
                      itemBuilder: (context, i) {
                        final d = _dispositivosCercanos[i];
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
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place, color: Colors.purple),
                          title: Text(l.nombre),
                          subtitle: l.descripcion != null ? Text(l.descripcion!) : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _borrarLugar(l),
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
                                    ? 'Activalo en esquinas donde hay que doblar, puertas '
                                        'o el pie de una escalera.'
                                    : _headingEnVivo == null
                                        ? 'Medición larga (${_duracionFingerprint.inSeconds} s). '
                                            'SIN BRÚJULA: el patrón se va a guardar sin rumbo y '
                                            'va a ser menos preciso, porque tu cuerpo tapa los '
                                            'beacons que quedan detrás tuyo.'
                                        : 'Medición larga (${_duracionFingerprint.inSeconds} s). '
                                            'Poné el cuerpo mirando hacia donde vas a venir '
                                            'caminando (ahora: ${_headingEnVivo!.toStringAsFixed(0)}°). '
                                            'Si a esta esquina se llega desde dos lados, '
                                            'tomá un punto clave por cada sentido.',
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
                              ? '¡No te muevas ni gires! Mantené el teléfono en la misma mano '
                                  'y altura que vas a usar al navegar, y el cuerpo mirando para '
                                  'el mismo lado: el patrón se compara después contra esa misma '
                                  'postura y ese mismo rumbo. '
                                  '(${_rumboMedioToma == null ? "sin brújula" : "rumbo ${_rumboMedioToma!.toStringAsFixed(0)}°"}'
                                  ' · $_muestrasAcumuladas lotes)'
                              : '¡No te muevas de la celda! El sistema promedia las lecturas '
                                  'automáticamente. ($_muestrasAcumuladas lotes)',
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
  /// El operador apunta el teléfono hacia el borde SUPERIOR del mapa y ajusta
  /// el slider hasta que la flecha de la brújula quede paralela al eje Y de la
  /// imagen. El valor guardado (rotacion_mapa, en grados) es el offset que
  /// PantallaNavegacion resta al heading de FlutterCompass para alinear la
  /// brújula con el plano.
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
                  '1. Apuntá el borde SUPERIOR del teléfono hacia el borde SUPERIOR del mapa físico.\n'
                  '2. Ajustá el offset con el slider hasta que la flecha quede paralela al eje Y del plano.\n'
                  '3. Tocá "Guardar offset".',
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
                const SizedBox(height: 4),
                const Text(
                  'Apuntá el borde superior del teléfono al borde superior del mapa.\n'
                  'Ajustá el slider hasta que la flecha quede apuntando exactamente hacia ARRIBA.',
                  style: TextStyle(color: TemaApp.textoSecundario, fontSize: 12, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Slider de offset
          Text(
            'Offset: ${_rotacionMapa.toStringAsFixed(0)}°',
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
                  onPressed: () {
                    if (mounted) setState(() => _rotacionMapa = preset.valor);
                  },
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
          const SizedBox(height: 24),

          // Botón guardar
          SizedBox(
            width: double.infinity,
            height: TemaApp.targetTactil,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  await DatabaseHelper.instance.actualizarRotacionMapa(widget.pisoId, _rotacionMapa);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Offset de brújula guardado: ${_rotacionMapa.toStringAsFixed(0)}°')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error guardando offset: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Guardar offset de brújula'),
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