import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Parámetro numérico de la navegación que se puede regular desde la app.
class ParametroAjuste {
  /// Clave con la que se guarda en el teléfono.
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

  final double porDefecto;
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
    this.decimales = 1,
  }) : valor = porDefecto;

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

/// Una configuración guardada de todos los ajustes de navegación, con nombre,
/// descripción (para anotar qué anda y qué no) y calificación de 0 a 5.
///
/// Las de fábrica ([deFabrica]) sirven de referencia: su nombre y sus valores
/// no se cambian desde la app; sí su descripción y su calificación. Para
/// probar otros valores se duplican.
class Preseleccion {
  final String id;
  final bool deFabrica;
  String nombre;
  String descripcion;

  /// 0 a 5 estrellas.
  int calificacion;

  /// Valor de cada parámetro, por [ParametroAjuste.clave]. Si falta alguno
  /// (un parámetro agregado después de guardarla) rige su valor por defecto.
  final Map<String, double> valores;

  bool frenarLateralConBrujula;
  bool restringirZonas;

  Preseleccion({
    required this.id,
    required this.deFabrica,
    required this.nombre,
    required this.descripcion,
    required this.valores,
    this.calificacion = 0,
    this.frenarLateralConBrujula = true,
    this.restringirZonas = true,
  });

  Map<String, dynamic> aJson() => {
        'id': id,
        'deFabrica': deFabrica,
        'nombre': nombre,
        'descripcion': descripcion,
        'calificacion': calificacion,
        'valores': valores,
        'frenarLateralConBrujula': frenarLateralConBrujula,
        'restringirZonas': restringirZonas,
      };

  /// Null si [j] no es una preselección válida.
  static Preseleccion? deJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    final valores = <String, double>{};
    final v = j['valores'];
    if (v is Map) {
      v.forEach((k, x) {
        if (k is String && x is num && x.isFinite) valores[k] = x.toDouble();
      });
    }
    final cal = j['calificacion'];
    return Preseleccion(
      id: id,
      deFabrica: j['deFabrica'] == true,
      nombre: j['nombre'] is String ? j['nombre'] as String : 'Sin nombre',
      descripcion: j['descripcion'] is String ? j['descripcion'] as String : '',
      calificacion: cal is num ? cal.toInt().clamp(0, 5) : 0,
      valores: valores,
      frenarLateralConBrujula: j['frenarLateralConBrujula'] != false,
      restringirZonas: j['restringirZonas'] != false,
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// AJUSTES DE NAVEGACIÓN REGULABLES
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Valores que hay que afinar caminando con el teléfono, no en el escritorio:
/// cuándo se dice cada giro, cuánto se filtra la posición y si puede entrar a
/// una zona prohibida. Se agrupan en preselecciones ([Preseleccion]) que se
/// eligen, califican y editan desde el panel de la pantalla de navegación
/// (botón "Ajustes de navegación", arriba a la derecha; ver
/// panel_ajustes_navegacion.dart). Se aplican al instante y quedan guardadas
/// en el teléfono: así se prueba una, se camina la ruta y se anota qué anduvo.
///
/// Los valores por defecto de cada parámetro son los de la preselección
/// "Equilibrada"; sólo rigen si una preselección guardada no tiene alguno.
///
/// Es un singleton: la pantalla de navegación se vuelve a crear en cada salto
/// de piso y tiene que seguir usando los mismos valores.
class AjustesNavegacion {
  AjustesNavegacion._();
  static final AjustesNavegacion instancia = AjustesNavegacion._();

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

  /// true: la brújula frena el movimiento de costado respecto de hacia
  /// dónde mira el usuario ([PuertaRumbo]). Con la brújula desviada, eso
  /// retiene parte del avance real y lo suelta de golpe al doblar: apagarlo
  /// sirve para ver si el problema viene de ahí.
  bool frenarLateralConBrujula = true;

  // ── Zonas ─────────────────────────────────────────────────────────────────

  /// true: la posición del usuario nunca queda adentro de una zona no
  /// transitable (ver [RestriccionZonas]). Se deja apagable para comparar en
  /// el campo.
  bool restringirZonas = true;

  List<ParametroAjuste> get todos => [...parametrosGiro, ...parametrosPosicion];

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

  // ── Preselecciones ────────────────────────────────────────────────────────
  //
  // Los valores de arriba son los VIGENTES: los que lee la navegación. Salen
  // siempre de la preselección activa ([activa]). Elegir otra, o cambiar un
  // valor de la activa en el editor, los vuelve a copiar ([_aplicar]).

  static const String _clavePreselecciones = 'nav_preselecciones';
  static const String _claveActiva = 'nav_preseleccion_activa';
  static const String _idPorDefecto = 'fabrica_equilibrada';

  /// Primero las de fábrica, en el orden de [_deFabrica]; después las
  /// propias, en el orden en que se crearon.
  final List<Preseleccion> preselecciones = [];
  String _idActiva = _idPorDefecto;

  Preseleccion get activa => preselecciones.firstWhere(
        (p) => p.id == _idActiva,
        orElse: () => preselecciones.first,
      );

  bool esActiva(Preseleccion p) => p.id == activa.id;

  /// Valores de una preselección con todos los parámetros, para no olvidar
  /// ninguno al definir las de fábrica.
  Map<String, double> _valores({
    required double atraso,
    required double giro,
    required double aviso,
    required double distanciaQuieto,
    required double umbral,
    required double ventanaQuieto,
    required double ventanaCaminando,
    required double corteQuieto,
    required double corteCaminando,
    required double empuje,
    required double velMax,
  }) =>
      {
        atrasoPosicion.clave: atraso,
        anticipoGiro.clave: giro,
        anticipoAviso.clave: aviso,
        distanciaGiroQuieto.clave: distanciaQuieto,
        umbralCaminata.clave: umbral,
        ventanaSenalQuieto.clave: ventanaQuieto,
        ventanaSenalCaminando.clave: ventanaCaminando,
        filtroQuieto.clave: corteQuieto,
        filtroCaminando.clave: corteCaminando,
        empujeVelocidad.clave: empuje,
        velocidadMaxima.clave: velMax,
      };

  /// ── LAS DE FÁBRICA ─────────────────────────────────────────────────────
  ///
  /// Cada una apunta a una hipótesis distinta de por qué la posición anda
  /// mal, para probarlas caminando la misma ruta y comparar. El atraso de la
  /// posición de cada una sale de sus propios filtros: ventana de señal
  /// caminando (la mitad de la ventana) + filtro caminando (1 / 2π·fc) +
  /// ~0,1 s del resto. Es una estimación: si los giros salen
  /// tarde o temprano, duplicarla y corregir el atraso.
  ///
  /// Sus valores no se editan desde la app (se actualizan con el código), pero
  /// el nombre y la descripción que escribió el usuario, y su calificación,
  /// se conservan.
  List<Preseleccion> _deFabrica() => [
        Preseleccion(
          id: _idPorDefecto,
          deFabrica: true,
          nombre: 'Equilibrada',
          descripcion: 'Punto de partida. Ventanas de señal cortas, filtro '
              'medio y poco empuje. Atraso estimado: 0,8 s.',
          valores: _valores(
            atraso: 0.8,
            giro: 0.6,
            aviso: 6,
            distanciaQuieto: 1.0,
            umbral: 0.6,
            ventanaQuieto: 2.0,
            ventanaCaminando: 0.8,
            corteQuieto: 0.08,
            corteCaminando: 0.45,
            empuje: 0.05,
            velMax: 2.0,
          ),
        ),
        Preseleccion(
          id: 'fabrica_rapida',
          deFabrica: true,
          nombre: 'Respuesta rápida',
          descripcion: 'Para cuando el punto queda atrás o tarda en arrancar. '
              'Ventanas y filtros al mínimo razonable y sin empuje: sigue '
              'rápido, pero tiembla y salta más. Atraso estimado: 0,6 s.',
          valores: _valores(
            atraso: 0.6,
            giro: 0.6,
            aviso: 6,
            distanciaQuieto: 1.0,
            umbral: 0.5,
            ventanaQuieto: 1.5,
            ventanaCaminando: 0.6,
            corteQuieto: 0.12,
            corteCaminando: 0.7,
            empuje: 0,
            velMax: 2.0,
          ),
        ),
        Preseleccion(
          id: 'fabrica_estable',
          deFabrica: true,
          nombre: 'Estable',
          descripcion: 'Para lugares donde la señal rebota (metal, mucha '
              'gente) y el punto salta. Más suavizado y velocidad máxima baja: '
              'se mueve parejo, pero con más atraso, y los giros se anuncian '
              'antes para compensarlo. Atraso estimado: 1,1 s.',
          valores: _valores(
            atraso: 1.1,
            giro: 0.6,
            aviso: 7,
            distanciaQuieto: 1.2,
            umbral: 0.7,
            ventanaQuieto: 3.0,
            ventanaCaminando: 1.1,
            corteQuieto: 0.05,
            corteCaminando: 0.3,
            empuje: 0,
            velMax: 1.6,
          ),
        ),
        Preseleccion(
          id: 'fabrica_telefono_firme',
          deFabrica: true,
          nombre: 'Teléfono firme en la mano',
          descripcion: 'Para caminar con el teléfono quieto en la mano (con '
              'bastón, por ejemplo), cuando el acelerómetro no se entera de '
              'que caminás y el punto queda frenado. Umbral de caminata bajo. '
              'Si el punto se mueve estando parado, no es esta. Atraso '
              'estimado: 0,8 s.',
          valores: _valores(
            atraso: 0.8,
            giro: 0.6,
            aviso: 6,
            distanciaQuieto: 1.0,
            umbral: 0.4,
            ventanaQuieto: 1.8,
            ventanaCaminando: 0.8,
            corteQuieto: 0.1,
            corteCaminando: 0.45,
            empuje: 0.05,
            velMax: 2.0,
          ),
        ),
        Preseleccion(
          id: 'fabrica_sin_brujula',
          deFabrica: true,
          nombre: 'Sin freno de brújula',
          descripcion: 'Igual que Equilibrada, pero la brújula no frena el '
              'movimiento de costado. Si con esta el punto deja de saltar al '
              'doblar, el problema era la brújula desviada.',
          frenarLateralConBrujula: false,
          valores: _valores(
            atraso: 0.8,
            giro: 0.6,
            aviso: 6,
            distanciaQuieto: 1.0,
            umbral: 0.6,
            ventanaQuieto: 2.0,
            ventanaCaminando: 0.8,
            corteQuieto: 0.08,
            corteCaminando: 0.45,
            empuje: 0.05,
            velMax: 2.0,
          ),
        ),
      ];

  /// Copia los valores de [p] a los vigentes.
  void _aplicar(Preseleccion p) {
    for (final def in todos) {
      final v = p.valores[def.clave] ?? def.porDefecto;
      def.valor = v.clamp(def.minimo, def.maximo).toDouble();
    }
    frenarLateralConBrujula = p.frenarLateralConBrujula;
    restringirZonas = p.restringirZonas;
  }

  /// Pasa a usar [p].
  void seleccionar(Preseleccion p) {
    _idActiva = p.id;
    _aplicar(p);
    debugPrint('[Ajustes] Configuración en uso: $resumen');
    guardar();
  }

  /// Avisa que se editó [p] (valores, nombre, descripción o calificación):
  /// si es la que está en uso, sus valores rigen desde ya. Y se guarda.
  void preseleccionCambiada(Preseleccion p) {
    if (esActiva(p)) _aplicar(p);
    guardar();
  }

  /// Nueva preselección propia con los valores de [base] (la activa si no se
  /// dice otra). Queda en uso: crearla es para probarla.
  Preseleccion crearPropia({Preseleccion? base}) {
    final origen = base ?? activa;
    final cantidad = preselecciones.where((p) => !p.deFabrica).length;
    final nueva = Preseleccion(
      id: 'propia_${DateTime.now().microsecondsSinceEpoch}',
      deFabrica: false,
      nombre: base == null
          ? 'Personalizada ${cantidad + 1}'
          : 'Copia de ${origen.nombre}',
      descripcion: 'Basada en "${origen.nombre}".',
      valores: Map.of(origen.valores),
      frenarLateralConBrujula: origen.frenarLateralConBrujula,
      restringirZonas: origen.restringirZonas,
    );
    preselecciones.add(nueva);
    seleccionar(nueva);
    return nueva;
  }

  /// Borra una preselección propia. Si estaba en uso, se pasa a la de
  /// fábrica por defecto.
  void borrar(Preseleccion p) {
    if (p.deFabrica) return;
    final estabaActiva = esActiva(p);
    preselecciones.removeWhere((x) => x.id == p.id);
    if (estabaActiva) {
      seleccionar(preselecciones.firstWhere(
        (x) => x.id == _idPorDefecto,
        orElse: () => preselecciones.first,
      ));
    } else {
      guardar();
    }
  }

  /// Las ventanas de señal se guardaban en LECTURAS y ahora van en SEGUNDOS,
  /// con otra clave. Una configuración propia guardada antes se convierte
  /// suponiendo ~6 lecturas por segundo, que era lo que esos valores daban
  /// por hecho.
  void _migrarVentanas(Preseleccion p) {
    void migrar(String claveVieja, ParametroAjuste nuevo) {
      final viejo = p.valores.remove(claveVieja);
      if (viejo == null || p.valores.containsKey(nuevo.clave)) return;
      final seg = (viejo / 6.25 * 10).round() / 10;
      p.valores[nuevo.clave] = seg.clamp(nuevo.minimo, nuevo.maximo).toDouble();
    }

    migrar('nav_ventana_senal_quieto', ventanaSenalQuieto);
    migrar('nav_ventana_senal_caminando', ventanaSenalCaminando);
  }

  // ── Guardado ──────────────────────────────────────────────────────────────

  bool _cargado = false;

  /// Lee lo guardado en el teléfono. Sólo la primera vez: después todo vive
  /// en memoria y se guarda en cada cambio.
  Future<void> cargar() async {
    if (_cargado) return;
    final fabrica = _deFabrica();
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardadas = <Preseleccion>[];
      final texto = prefs.getString(_clavePreselecciones);
      if (texto != null) {
        final lista = jsonDecode(texto);
        if (lista is List) {
          for (final j in lista) {
            final p = j is Map<String, dynamic> ? Preseleccion.deJson(j) : null;
            if (p != null) guardadas.add(p);
          }
        }
      }

      preselecciones.clear();
      // Las de fábrica: valores del código, notas y calificación del usuario.
      for (final f in fabrica) {
        final i = guardadas.indexWhere((g) => g.id == f.id);
        if (i >= 0) {
          f.descripcion = guardadas[i].descripcion;
          f.calificacion = guardadas[i].calificacion;
        }
        preselecciones.add(f);
      }
      for (final g in guardadas.where((g) => !g.deFabrica)) {
        _migrarVentanas(g);
        preselecciones.add(g);
      }

      _idActiva = prefs.getString(_claveActiva) ?? _idPorDefecto;

      // Antes de las preselecciones los valores se guardaban sueltos: si los
      // hay, se conservan como una propia para no perder lo ya probado.
      if (texto == null && prefs.containsKey(atrasoPosicion.clave)) {
        final anteriores = Preseleccion(
          id: 'propia_anteriores',
          deFabrica: false,
          nombre: 'Valores anteriores',
          descripcion: 'Los valores que estaban regulados antes de que '
              'existieran las configuraciones guardadas.',
          valores: {
            for (final def in todos)
              def.clave: prefs.getDouble(def.clave) ?? def.porDefecto,
          },
          frenarLateralConBrujula:
              prefs.getBool('nav_frenar_lateral_brujula') ?? true,
          restringirZonas: prefs.getBool('nav_restringir_zonas') ?? true,
        );
        preselecciones.add(anteriores);
        _idActiva = anteriores.id;
      }

      _cargado = true;
    } catch (e) {
      debugPrint('[Ajustes] No se pudieron leer los ajustes guardados: $e');
      if (preselecciones.isEmpty) preselecciones.addAll(fabrica);
    }
    _aplicar(activa);
    _idActiva = activa.id; // por si la guardada ya no existe
    debugPrint('[Ajustes] Configuración en uso: $resumen');
  }

  Future<void> guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _clavePreselecciones,
        jsonEncode([for (final p in preselecciones) p.aJson()]),
      );
      await prefs.setString(_claveActiva, _idActiva);
    } catch (e) {
      debugPrint('[Ajustes] No se pudieron guardar los ajustes: $e');
    }
  }

  /// La configuración en uso y todos sus valores en una línea, para el log.
  String get resumen => [
        '"${activa.nombre}"',
        for (final p in todos) '${p.nombre} ${p.texto}',
        'frenar lateral con brújula $frenarLateralConBrujula',
        'restringir zonas $restringirZonas',
      ].join(' · ');
}
