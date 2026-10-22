import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugPrint, mapEquals, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Parámetro numérico de la navegación que se puede regular desde la app del
/// administrador.
class ParametroAjuste {
  /// Clave con la que se guarda, en el teléfono y en la nube.
  final String clave;
  final String nombre;

  /// Qué cambia al moverlo. Se muestra debajo del control.
  final String ayuda;

  /// Unidad que se muestra ('s', 'm', 'Hz'...). Vacía si no tiene.
  final String unidad;

  /// La unidad como la tiene que leer el lector de pantalla.
  final String unidadHablada;

  final double minimo;
  final double maximo;
  final double paso;

  /// Decimales con que se muestra (los que permite [paso]).
  final int decimales;

  /// Valor del código: rige si nadie lo cambió (ver [AjustesNavegacion]).
  final double porDefecto;

  /// true si el administrador lo puede cambiar para un edificio. Los que
  /// dependen del teléfono (el acelerómetro) o de la persona (cuándo quiere
  /// escuchar los giros) no: afinados con el teléfono del admin, dejarían el
  /// edificio ajustado a su equipo y no al del usuario.
  final bool porEdificio;

  /// Valor vigente: el que lee la navegación.
  double valor;

  ParametroAjuste({
    required this.clave,
    required this.nombre,
    required this.ayuda,
    required this.unidad,
    required this.unidadHablada,
    required this.minimo,
    required this.maximo,
    required this.paso,
    required this.porDefecto,
    this.porEdificio = false,
    this.decimales = 1,
  }) : valor = porDefecto;

  /// [v] dentro del rango permitido.
  double acotar(double v) => v.clamp(minimo, maximo).toDouble();

  int get divisiones => ((maximo - minimo) / paso).round();

  String formatear(double v) {
    final n = v.toStringAsFixed(decimales);
    return unidad.isEmpty ? n : '$n $unidad';
  }

  String get texto => formatear(valor);

  /// Lo que lee el lector de pantalla para el valor [v].
  String hablado(double v) {
    final n = v.toStringAsFixed(decimales);
    return unidadHablada.isEmpty ? n : '$n $unidadHablada';
  }
}

/// De dónde sale el valor vigente de un parámetro.
enum OrigenAjuste {
  /// Nadie lo cambió: rige [ParametroAjuste.porDefecto].
  codigo,

  /// Lo cambió un administrador para todos los edificios.
  general,

  /// Lo cambió un administrador para el edificio actual.
  edificio,
}

/// ═══════════════════════════════════════════════════════════════════════════
/// AJUSTES DE NAVEGACIÓN
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Valores que hay que afinar caminando con el teléfono, no en el escritorio:
/// cuándo se dice cada giro y cuánto se filtra la posición.
///
/// ── QUIÉN LOS CAMBIA ─────────────────────────────────────────────────────
/// El usuario no: alguien que no ve podría desconfigurar la navegación sin
/// darse cuenta. El panel (panel_ajustes_navegacion.dart) existe sólo en la
/// app del administrador, en la pantalla de navegación ("Probar navegación"
/// en la lista de pisos), para regularlos caminando.
///
/// ── TRES CAPAS ────────────────────────────────────────────────────────────
/// El valor vigente de cada parámetro sale de la primera capa que lo tenga:
///
///  1. **Edificio**: lo que un administrador cambió para el edificio actual.
///     Sólo los parámetros que dependen del edificio
///     ([ParametroAjuste.porEdificio]).
///  2. **General**: lo que un administrador cambió para todos los
///     edificios.
///  3. **Código**: [ParametroAjuste.porDefecto].
///
/// MIENTRAS SE CALIBRA, cualquier administrador cambia las dos capas (ver
/// supabase/ajustes_navegacion.sql). Hubo un rol "desarrollador" que era
/// el único que podía tocar los generales, y se sacó porque no andaba.
/// Cuando los valores queden calibrados, pasan al código y se dejan de
/// poder cambiar desde la app los que no dependen del edificio.
///
/// Cada capa guarda SÓLO lo que se cambió en ella, no una copia de todo: si
/// el edificio guardara todos los valores, un cambio posterior en los
/// generales no le llegaría nunca.
///
/// Las capas viven en la nube (tabla `ajustes_navegacion`; la lectura y la
/// subida las hace `SupabaseService`) y en el teléfono, para navegar sin
/// conexión. Los edificios se identifican por su nombre, igual que los pisos
/// publicados: si se renombra un edificio, sus ajustes quedan con el nombre
/// viejo.
///
/// Antes había "preselecciones" con nombre y calificación, guardadas en el
/// teléfono. Se eliminaron: lo que quedó guardado de ellas
/// (`nav_preselecciones`, `nav_preseleccion_activa`) no se lee más.
///
/// Es un singleton: la pantalla de navegación se vuelve a crear en cada salto
/// de piso y tiene que seguir usando los mismos valores.
class AjustesNavegacion {
  AjustesNavegacion._();
  static final AjustesNavegacion instancia = AjustesNavegacion._();

  /// Instancia aparte, sin estado compartido con [instancia]. Para tests.
  @visibleForTesting
  factory AjustesNavegacion.nueva() => AjustesNavegacion._();

  // ── Giros (ver "GIROS ANTICIPADOS" en la pantalla de navegación) ──────────

  /// Cuánto tarde llega la posición medida respecto de la real, por la
  /// ventana de RSSI y el filtro One Euro.
  final ParametroAjuste atrasoPosicion = ParametroAjuste(
    clave: 'nav_atraso_posicion_seg',
    nombre: 'Atraso de la posición',
    ayuda: 'Cuánto tarde llega la posición por el filtrado de los beacons. '
        'Si los giros se dicen con la esquina ya pasada, subirlo.',
    unidad: 's',
    unidadHablada: 'segundos',
    minimo: 0,
    maximo: 3,
    paso: 0.1,
    porDefecto: 0.8,
    porEdificio: true,
  );

  /// Cuánto antes de que el usuario llegue a la esquina EMPIEZA a decirse
  /// "Girá a la izquierda".
  final ParametroAjuste anticipoGiro = ParametroAjuste(
    clave: 'nav_anticipo_giro_seg',
    nombre: 'Anticipo del giro',
    ayuda: 'Cuánto antes de llegar a la esquina empieza a decirse "Girá". '
        'En 0 se empieza a decir al llegar, y decirlo lleva cerca de un '
        'segundo.',
    unidad: 's',
    unidadHablada: 'segundos',
    minimo: 0,
    maximo: 4,
    paso: 0.1,
    porDefecto: 0.6,
  );

  /// Cuánto antes de la esquina se dice "En N metros, girá...".
  final ParametroAjuste anticipoAviso = ParametroAjuste(
    clave: 'nav_anticipo_aviso_seg',
    nombre: 'Anticipo del aviso previo',
    ayuda: 'Cuánto antes de llegar a la esquina se dice "En N metros, '
        'girá...".',
    unidad: 's',
    unidadHablada: 'segundos',
    minimo: 2,
    maximo: 12,
    paso: 0.5,
    porDefecto: 6,
  );

  /// Con el usuario quieto no hay ritmo de avance con el que pasar segundos
  /// a metros: el giro se dice por distancia.
  final ParametroAjuste distanciaGiroQuieto = ParametroAjuste(
    clave: 'nav_distancia_giro_quieto_m',
    nombre: 'Distancia del giro, parado',
    ayuda: 'Con el usuario quieto no hay tiempos que calcular: el giro se '
        'dice al quedar a esta distancia de la esquina.',
    unidad: 'm',
    unidadHablada: 'metros',
    minimo: 0.5,
    maximo: 3,
    paso: 0.1,
    porDefecto: 1,
  );

  List<ParametroAjuste> get parametrosGiro =>
      [atrasoPosicion, anticipoGiro, anticipoAviso, distanciaGiroQuieto];

  // ── Seguimiento de la posición ────────────────────────────────────────────
  //
  // El síntoma "tarda en arrancar y después avanza de golpe, y a veces se
  // pasa" sale de cómo está armado el pipeline: mientras el acelerómetro dice
  // QUIETO, todo está frenado a propósito para que el punto no tiemble
  // (ventana de señal larga, filtro lento, zona muerta). Cuando pasa a
  // CAMINANDO se abre todo junto, y el atraso acumulado sale de una vez. Estos
  // son esos frenos. El comentario de cada uno dice cuánto valía antes de
  // este ajuste, para poder volver.

  /// Energía del acelerómetro (m/s²) a partir de la cual se toma que camina
  /// del todo ([DetectorMovimiento.umbralMoviendo]). Antes: 0,80.
  final ParametroAjuste umbralCaminata = ParametroAjuste(
    clave: 'nav_umbral_caminata',
    nombre: 'Umbral de caminata',
    ayuda: 'Cuánto tiene que sacudirse el teléfono para contar como '
        'caminando. Si la posición tarda en arrancar al caminar, bajarlo. Si '
        'se mueve estando parado, subirlo.',
    unidad: 'm/s²',
    unidadHablada: 'metros por segundo al cuadrado',
    minimo: 0.35,
    maximo: 1.5,
    paso: 0.05,
    decimales: 2,
    porDefecto: 0.6,
  );

  /// Segundos de lecturas de cada beacon que se promedian con el usuario
  /// quieto. Es también lo que guarda el buffer
  /// ([ProcesadorSenal.configurarVentanas]). Antes eran 19 lecturas (~3 s).
  ///
  /// Las ventanas eran en LECTURAS y pasaron a SEGUNDOS: el atraso depende
  /// del tiempo, y cuánto duran N lecturas depende de cada cuánto emite el
  /// beacon. Por eso cambiaron también las claves: un valor guardado en
  /// lecturas no se lee como segundos (ver [_migrarVentanas]).
  final ParametroAjuste ventanaSenalQuieto = ParametroAjuste(
    clave: 'nav_ventana_senal_quieto_seg',
    nombre: 'Ventana de señal, parado',
    ayuda: 'Cuántos segundos de lecturas de cada beacon se promedian con el '
        'usuario quieto. Más: el punto tiembla menos parado, pero tarda más '
        'en arrancar.',
    unidad: 's',
    unidadHablada: 'segundos',
    minimo: 0.5,
    maximo: 5,
    paso: 0.1,
    porDefecto: 2.0,
    porEdificio: true,
  );

  /// Lo mismo caminando. Antes eran 7 lecturas (~1,1 s).
  final ParametroAjuste ventanaSenalCaminando = ParametroAjuste(
    clave: 'nav_ventana_senal_caminando_seg',
    nombre: 'Ventana de señal, caminando',
    ayuda: 'Cuántos segundos de lecturas se promedian caminando. Es la mayor '
        'fuente de atraso (agrega la mitad de la ventana): más corta, menos '
        'atraso pero más saltos.',
    unidad: 's',
    unidadHablada: 'segundos',
    minimo: 0.2,
    maximo: 3,
    paso: 0.1,
    porDefecto: 0.8,
    porEdificio: true,
  );

  /// Frecuencia de corte del One Euro con el usuario quieto
  /// ([FiltroUnEuroPosicion.cutoffQuieto]). Antes: 0,04 Hz.
  final ParametroAjuste filtroQuieto = ParametroAjuste(
    clave: 'nav_filtro_quieto_hz',
    nombre: 'Filtro, parado',
    ayuda: 'Qué tan rápido sigue el punto a la señal con el usuario quieto. '
        'Más: empieza a moverse antes al arrancar, pero tiembla más parado.',
    unidad: 'Hz',
    unidadHablada: 'hertz',
    minimo: 0.02,
    maximo: 0.3,
    paso: 0.01,
    decimales: 2,
    porDefecto: 0.08,
    porEdificio: true,
  );

  /// Frecuencia de corte del One Euro caminando
  /// ([FiltroUnEuroPosicion.cutoffMoviendo]). Antes: 0,35 Hz.
  final ParametroAjuste filtroCaminando = ParametroAjuste(
    clave: 'nav_filtro_caminando_hz',
    nombre: 'Filtro, caminando',
    ayuda: 'Qué tan rápido sigue el punto a la señal caminando. Más: menos '
        'atraso, pero se cuela más ruido.',
    unidad: 'Hz',
    unidadHablada: 'hertz',
    minimo: 0.1,
    maximo: 1.5,
    paso: 0.05,
    decimales: 2,
    porDefecto: 0.45,
    porEdificio: true,
  );

  /// Término de velocidad del One Euro ([FiltroUnEuroPosicion.beta]).
  /// Antes: 0,15.
  final ParametroAjuste empujeVelocidad = ParametroAjuste(
    clave: 'nav_empuje_velocidad',
    nombre: 'Empuje por velocidad',
    ayuda: 'Cuánto se apura el filtro cuando el punto ya viene rápido. Es lo '
        'que lo hace "alcanzar de golpe" después de un atraso: bajarlo si '
        'avanza a los saltos.',
    unidad: '',
    unidadHablada: '',
    minimo: 0,
    maximo: 0.5,
    paso: 0.05,
    decimales: 2,
    porDefecto: 0.05,
    porEdificio: true,
  );

  /// Tope de velocidad del punto caminando (tope de paso por ciclo de la
  /// pantalla de navegación). Antes: 3,0 m/s.
  final ParametroAjuste velocidadMaxima = ParametroAjuste(
    clave: 'nav_velocidad_maxima_ms',
    nombre: 'Velocidad máxima del punto',
    ayuda: 'Lo más rápido que puede moverse el punto caminando. Bajarlo '
        'frena los saltos y que se pase de largo; muy bajo, se queda atrás.',
    unidad: 'm/s',
    unidadHablada: 'metros por segundo',
    minimo: 1,
    maximo: 4,
    paso: 0.1,
    porDefecto: 2,
    porEdificio: true,
  );

  List<ParametroAjuste> get parametrosPosicion => [
        umbralCaminata,
        ventanaSenalQuieto,
        ventanaSenalCaminando,
        filtroQuieto,
        filtroCaminando,
        empujeVelocidad,
        velocidadMaxima,
      ];

  // ── Interruptores de prueba (no se guardan ni se publican) ────────────────
  //
  // Sirven para comparar en el campo, no son configuración: viven sólo en
  // memoria, arrancan prendidos cada vez que se abre la app y en la app del
  // usuario no se pueden tocar. Así un interruptor olvidado apagado no queda
  // así para siempre.

  /// true: la brújula frena el movimiento de costado respecto de hacia
  /// dónde mira el usuario ([PuertaRumbo]). Con la brújula desviada, eso
  /// retiene parte del avance real y lo suelta de golpe al doblar: apagarlo
  /// sirve para ver si el problema viene de ahí.
  bool frenarLateralConBrujula = true;

  /// true: la posición del usuario nunca queda adentro de una zona no
  /// transitable (ver [RestriccionZonas]).
  bool restringirZonas = true;

  List<ParametroAjuste> get todos => [...parametrosGiro, ...parametrosPosicion];

  List<ParametroAjuste> get _porEdificio =>
      [for (final p in todos) if (p.porEdificio) p];

  // ── Diagnóstico de la señal (no se guarda) ────────────────────────────────

  /// Cuántas lecturas NUEVAS por segundo llegan, en promedio, de cada beacon
  /// del piso. La mide la pantalla de navegación cada pocos segundos y la
  /// muestra el panel. Depende del intervalo de emisión configurado en cada
  /// beacon, no de la app: con beacons que emiten poco, ninguna
  /// configuración puede tener a la vez poco atraso y poco ruido.
  double? lecturasPorSegundo;

  /// La misma medición en una línea legible, y cuándo se tomó.
  String? diagnosticoSenal;
  DateTime? diagnosticoSenalHora;

  // ── Capas ─────────────────────────────────────────────────────────────────
  //
  // Los [ParametroAjuste.valor] son los VIGENTES: los que lee la navegación.
  // Se recalculan desde las capas ([_aplicar]) cada vez que cambia una o se
  // cambia de edificio.

  /// Id en la nube de la capa general.
  static const String idGeneral = 'general';
  static const String _prefijoEdificio = 'edificio:';

  /// Id en la nube de la capa de un edificio.
  static String idEdificio(String nombre) => '$_prefijoEdificio$nombre';

  /// Lo cambiado para todos los edificios, por [ParametroAjuste.clave].
  Map<String, double> _general = {};

  /// Lo cambiado en cada edificio (por nombre), por clave.
  final Map<String, Map<String, double>> _edificios = {};

  String? _edificioActual;

  /// Ids de capas con cambios hechos en este teléfono que todavía no se
  /// subieron a la nube (por ejemplo, regulando en un subsuelo sin señal).
  final Set<String> _pendientes = {};

  /// Edificio cuyos ajustes rigen ahora. Null fuera de un edificio.
  String? get edificioActual => _edificioActual;

  Map<String, double> get _delEdificio {
    final nombre = _edificioActual;
    return nombre == null ? const {} : (_edificios[nombre] ?? const {});
  }

  /// De qué capa sale el valor vigente de [p].
  OrigenAjuste origen(ParametroAjuste p) {
    if (_delEdificio.containsKey(p.clave)) return OrigenAjuste.edificio;
    if (_general.containsKey(p.clave)) return OrigenAjuste.general;
    return OrigenAjuste.codigo;
  }

  /// Valor de [p] sin contar el edificio: el general, o el del código.
  double valorGeneral(ParametroAjuste p) =>
      p.acotar(_general[p.clave] ?? p.porDefecto);

  /// true si la capa general tiene un valor propio para [p].
  bool generalCambiado(ParametroAjuste p) => _general.containsKey(p.clave);

  /// Valor de [p] en el edificio actual, si lo tiene cambiado.
  double? valorDelEdificio(ParametroAjuste p) => _delEdificio[p.clave];

  void _aplicar() {
    final edificio = _delEdificio;
    for (final p in todos) {
      p.valor = p.acotar(edificio[p.clave] ?? _general[p.clave] ?? p.porDefecto);
    }
  }

  /// Pasa a usar los ajustes de [nombre] (null: sólo general y código).
  Future<void> usarEdificio(String? nombre) async {
    await cargar();
    _edificioActual = nombre;
    _aplicar();
    debugPrint('[Ajustes] ${nombre ?? "Sin edificio"}: $resumen');
  }

  // ── Edición (app del administrador) ───────────────────────────────────────
  //
  // Cada cambio rige al instante (se regula caminando), se guarda en el
  // teléfono y queda pendiente de subir a la nube.

  /// Cambia [p] sólo para el edificio actual. No hace nada si no hay
  /// edificio o si [p] no se puede cambiar por edificio.
  void cambiarEnEdificio(ParametroAjuste p, double v) {
    final nombre = _edificioActual;
    if (nombre == null || !p.porEdificio) return;
    (_edificios[nombre] ??= {})[p.clave] = p.acotar(v);
    _cambioLocal(idEdificio(nombre));
  }

  /// Saca el valor propio del edificio actual para [p]: vuelve a regir el
  /// general.
  void volverAlGeneral(ParametroAjuste p) {
    final nombre = _edificioActual;
    if (nombre == null) return;
    final valores = _edificios[nombre];
    if (valores == null || valores.remove(p.clave) == null) return;
    if (valores.isEmpty) _edificios.remove(nombre);
    _cambioLocal(idEdificio(nombre));
  }

  /// Cambia [p] para todos los edificios.
  void cambiarGeneral(ParametroAjuste p, double v) {
    _general[p.clave] = p.acotar(v);
    _cambioLocal(idGeneral);
  }

  /// Saca el valor general de [p]: vuelve a regir el del código.
  void volverAlCodigo(ParametroAjuste p) {
    if (_general.remove(p.clave) == null) return;
    _cambioLocal(idGeneral);
  }

  void _cambioLocal(String id) {
    _pendientes.add(id);
    _aplicar();
    _guardar();
  }

  // ── Nube (lo usa SupabaseService) ─────────────────────────────────────────

  Set<String> get pendientes => Set.unmodifiable(_pendientes);
  bool get hayPendientes => _pendientes.isNotEmpty;

  /// Valores de la capa [id], para subirlos.
  Map<String, double> valoresDe(String id) {
    if (id == idGeneral) return Map.of(_general);
    if (id.startsWith(_prefijoEdificio)) {
      final nombre = id.substring(_prefijoEdificio.length);
      return Map.of(_edificios[nombre] ?? const {});
    }
    return const {};
  }

  /// Lo que hay en la nube para la capa [id] (null o vacío si no hay nada).
  ///
  /// Si esa capa tiene cambios de este teléfono sin subir, no se pisan: van
  /// a la nube en la próxima subida. De un edificio sólo se toman los
  /// parámetros que se pueden cambiar por edificio, aunque la nube traiga
  /// otros.
  void recibirDeNube(String id, Object? valores) {
    if (_pendientes.contains(id)) return;
    if (id == idGeneral) {
      _general = leerValores(valores, todos);
    } else if (id.startsWith(_prefijoEdificio)) {
      final nombre = id.substring(_prefijoEdificio.length);
      final leidos = leerValores(valores, _porEdificio);
      if (leidos.isEmpty) {
        _edificios.remove(nombre);
      } else {
        _edificios[nombre] = leidos;
      }
    } else {
      return;
    }
    _aplicar();
    _guardar();
  }

  /// Avisa que la capa [id] se subió con [subidos]. Si mientras tanto se
  /// cambió otra vez, sigue pendiente.
  void subidoANube(String id, Map<String, double> subidos) {
    if (!mapEquals(valoresDe(id), subidos)) return;
    _pendientes.remove(id);
    _guardar();
  }

  /// Los valores de [json] que corresponden a [permitidos], dentro de su
  /// rango. Lo que no es un número válido, o no es de un parámetro
  /// permitido, se ignora: así un parámetro agregado o quitado en otra
  /// versión de la app no rompe nada.
  static Map<String, double> leerValores(
    Object? json,
    Iterable<ParametroAjuste> permitidos,
  ) {
    final leidos = <String, double>{};
    if (json is! Map) return leidos;
    for (final p in permitidos) {
      final x = json[p.clave];
      if (x is num && x.isFinite) leidos[p.clave] = p.acotar(x.toDouble());
    }
    return leidos;
  }

  // ── Guardado en el teléfono ───────────────────────────────────────────────

  static const String _claveGuardado = 'nav_ajustes_capas';

  Future<void>? _carga;

  /// Lee lo guardado en el teléfono. Sólo la primera vez: después todo vive
  /// en memoria y se guarda en cada cambio.
  Future<void> cargar() => _carga ??= _leer();

  Future<void> _leer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_claveGuardado);
      if (texto != null) {
        final j = jsonDecode(texto);
        if (j is Map) {
          _general = leerValores(j['general'], todos);
          final edificios = j['edificios'];
          if (edificios is Map) {
            edificios.forEach((nombre, valores) {
              if (nombre is! String) return;
              final leidos = leerValores(valores, _porEdificio);
              if (leidos.isNotEmpty) _edificios[nombre] = leidos;
            });
          }
          final pendientes = j['pendientes'];
          if (pendientes is List) _pendientes.addAll(pendientes.whereType<String>());
        }
      }
    } catch (e) {
      debugPrint('[Ajustes] No se pudieron leer los ajustes guardados: $e');
    }
    _aplicar();
  }

  Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _claveGuardado,
        jsonEncode({
          'general': _general,
          'edificios': _edificios,
          'pendientes': _pendientes.toList(),
        }),
      );
    } catch (e) {
      debugPrint('[Ajustes] No se pudieron guardar los ajustes: $e');
    }
  }

  /// Todos los valores vigentes en una línea, con su origen, para el log.
  String get resumen => [
        for (final p in todos)
          '${p.nombre} ${p.texto}'
              '${switch (origen(p)) {
                OrigenAjuste.edificio => ' (edificio)',
                OrigenAjuste.general => ' (general)',
                OrigenAjuste.codigo => '',
              }}',
        if (!frenarLateralConBrujula) 'SIN freno lateral por brújula',
        if (!restringirZonas) 'SIN restricción de zonas',
      ].join(' · ');
}
