import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'ajustes_voz.dart';
import 'reconocimiento_telefono.dart';

/// Servicio central de voz para BlindRoute.
/// Centraliza Text-to-Speech (TTS) y Speech-to-Text (STT).
class VozService {
  // Singleton
  static final VozService _instancia = VozService._interno();
  factory VozService() => _instancia;
  VozService._interno();
 
  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _ttsInicializado = false;
  bool _hablando = false; // true mientras el motor TTS está reproduciendo audio
 
  // STT
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _sttDisponible = false;
  bool _escuchando = false;
 
  // ── DUEÑO ACTUAL ──────────────────────────────────────────────────────────
  // VozService es un singleton, así que `limpiar()` de una pantalla detiene el
  // TTS de TODAS. Flutter destruye la pantalla saliente después de construir la
  // entrante, así que ese `limpiar()` tardío cortaba el anuncio de la pantalla
  // nueva. Con un token de dueño, la limpieza tardía se vuelve inofensiva.
  Object? _dueno;

  /// Registra a [dueno] como pantalla activa de voz.
  void registrarDueno(Object dueno) => _dueno = dueno;

  bool esDueno(Object candidato) => identical(_dueno, candidato);

  // Control de instrucciones repetidas
  String _ultimaInstruccion = '';
  DateTime? _ultimaVezHablado;

  /// Cada cuánto se repite una indicación que no cambió: lo elige el usuario
  /// (ver [AjustesVoz.repetir]).
  Duration get _intervaloMinimo => _ajustes.intervaloRepeticion;

  /// Velocidad, volumen, tono y repetición, a gusto de cada persona.
  final AjustesVoz _ajustes = AjustesVoz.instancia;
 
  // ─── INICIALIZACIÓN ──────────────────────────────────────────────────────────
 
  Future<void> inicializar() async {
    await _inicializarTTS();
    await _inicializarSTT();
  }
 
  Future<void> _inicializarTTS() async {
    try {
      // El idioma se fija recién con el motor ya arrancado. flutter_tts
      // (Android) guarda las llamadas que llegan mientras el motor arranca,
      // las ejecuta al terminar y DESPUÉS le pone el idioma de la voz por
      // defecto del teléfono, así que el es-AR quedaba pisado. Pasaba en la
      // primera inicialización (el inicio de la app del usuario): la
      // navegación vuelve a inicializar con el motor listo y ahí se
      // escuchaba bien, pero la frase de prueba de los ajustes de voz salía
      // con la voz del teléfono ("ashi suena la voiz"). Esta consulta entra
      // en esa cola; cuando vuelve, el motor ya terminó de arrancar.
      await _tts.isLanguageAvailable('es-AR');
      final idioma = await _tts.setLanguage('es-AR');
      if (idioma != 1) {
        debugPrint('[Voz] El motor de voz no aceptó es-AR ($idioma).');
      }
      await _ajustes.cargar();
      await aplicarAjustes();
      _ttsInicializado = true;
    } catch (e) {
      _ttsInicializado = false;
    }
  }
 
  Future<void> _inicializarSTT() async {
    try {
      _sttDisponible = await _stt.initialize(
        onError: (error) {
          _escuchando = false;
          debugPrint('[Voz] Error del reconocedor: ${error.errorMsg}');
          // Una escucha en el teléfono que no arrancó sigue por internet
          // (ver "RECONOCER EN EL TELÉFONO"): no se cierra.
          if (_atenderErrorDelMotor?.call(error.errorMsg) ?? false) return;
          // Silencio o "no se entendió" llegan por acá y no por onResult:
          // hay que avisarle a quien está escuchando (ver "una sesión, un
          // aviso" más abajo). Sin conexión, con su motivo.
          _cerrarSesionTrasGracia(
            _erroresDeRed.contains(error.errorMsg)
                ? errorSinConexion
                : 'sin texto',
          );
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _escuchando = false;
          }
          // "done" = el motor terminó. Si para entonces no hubo resultado
          // final, no va a haber. ("notListening" no alcanza: llega ANTES
          // del resultado final.)
          if (status == 'done') _cerrarSesionTrasGracia('sin texto');
        },
      );
      // Se averigua ya, aparte, para que la primera escucha no lo espere.
      if (_sttDisponible) {
        _localeEspanol ??= _resolverLocaleEspanol();
        unawaited(_prepararReconocimientoEnTelefono());
      }
    } catch (e) {
      _sttDisponible = false;
    }
  }
 
  // ─── TTS: TEXT TO SPEECH ─────────────────────────────────────────────────────

  /// Pasa al motor la velocidad, el volumen y el tono de [AjustesVoz]. Rige
  /// desde la próxima frase.
  Future<void> aplicarAjustes() async {
    await _tts.setSpeechRate(_ajustes.velocidadMotor);
    await _tts.setVolume(_ajustes.volumenMotor);
    await _tts.setPitch(_ajustes.tonoMotor);
  }

  /// Completer de la frase que está sonando por [hablar]. Null si no suena
  /// nada, o si lo que suena lo lanzó [hablarSinEsperar] (nadie la espera).
  Completer<void>? _finFraseActual;

  /// Corta la frase en curso (si hay) y ESPERA el aviso de cancelación del
  /// motor antes de devolver.
  ///
  /// POR QUÉ HAY QUE ESPERARLO: los handlers del motor son globales, no por
  /// frase. Antes [hablar] hacía `stop()` y enseguida instalaba los handlers
  /// de la frase NUEVA; el aviso de cancelación de la frase VIEJA llegaba un
  /// instante después y lo recibía el handler nuevo, que entendía "terminé":
  /// ponía `_hablando = false` y completaba el Future con la frase nueva
  /// recién empezando. Con `_hablando` en false de forma espuria, la próxima
  /// indicación de guiado la pisaba (el motor corta lo que suena al recibir
  /// otro `speak`). Pasaba, por ejemplo, con "Ubicación lista." seguido de
  /// "Ubicación lista. Vamos a la escalera.". Acá el aviso viejo lo consume
  /// un handler temporal y recién después se instala el de la frase nueva.
  Future<void> _cortarFraseEnCurso() async {
    if (!_hablando) {
      await _tts.stop();
      return;
    }
    final cortada = Completer<void>();
    void soltar() {
      if (!cortada.isCompleted) cortada.complete();
    }

    _tts.setCompletionHandler(soltar);
    _tts.setCancelHandler(soltar);
    _tts.setErrorHandler((_) => soltar());
    await _tts.stop();
    // Tope corto: si el aviso no llega (frase que justo había terminado), no
    // se demora la frase nueva más que esto.
    await cortada.future
        .timeout(const Duration(milliseconds: 500), onTimeout: () {});
    _hablando = false;

    // Si alguien estaba esperando la frase cortada, ya no tiene qué esperar.
    final anterior = _finFraseActual;
    _finFraseActual = null;
    if (anterior != null && !anterior.isCompleted) anterior.complete();
  }

  /// Habla el texto y espera a que el motor TTS confirme que terminó.
  /// Usa un Completer conectado al callback onCompletionHandler del motor,
  /// con un timeout de seguridad basado en la longitud del texto.
  /// Si había otra frase sonando, la corta.
  Future<void> hablar(String texto) async {
    if (!_ttsInicializado || texto.trim().isEmpty) return;
    // Ya en este instante (antes de la espera del corte) la frase en curso
    // deja de ser secundaria: nadie más tiene que cortarla. Y mientras se
    // espera el corte no arranca ninguna secundaria (ver [hablarSecundaria]).
    _sonandoSecundaria = false;
    _arrancando++;
    try {
      await _cortarFraseEnCurso();
    } finally {
      _arrancando--;
    }
    _hablando = true;

    final completer = Completer<void>();
    _finFraseActual = completer;

    void completar() {
      // El estado global sólo se toca si ESTA sigue siendo la frase en curso:
      // el timeout de una frase que ya fue cortada por otra no tiene que
      // marcar como libre al motor mientras suena la nueva.
      if (identical(_finFraseActual, completer)) {
        _finFraseActual = null;
        _hablando = false;
      }
      if (!completer.isCompleted) completer.complete();
    }

    // Registrar el callback de finalización ANTES de llamar a speak()
    _tts.setCompletionHandler(completar);

    // También capturar cancelación/error del motor
    _tts.setCancelHandler(completar);
    _tts.setErrorHandler((msg) => completar());

    await _tts.speak(texto);
    _ultimaVezHablado = DateTime.now();
    _ultimaInstruccion = texto;

    // Timeout de seguridad: ~150ms por caracter a velocidad 0.48, mínimo 1500ms,
    // más 600ms de margen para que el altavoz se apague físicamente antes de
    // abrir el micrófono.
    final timeoutMs = (texto.length * 150).clamp(1500, 12000) + 600;
    await completer.future
        .timeout(Duration(milliseconds: timeoutMs), onTimeout: completar);
  }
 
  /// Habla sin esperar — para instrucciones de navegación que se actualizan
  /// continuamente y no deben bloquear el widget tree.
  /// Si el motor ya está reproduciendo audio, descarta el nuevo texto para no
  /// interrumpir la locución en curso, salvo que sea una frase secundaria
  /// (ver [hablarSecundaria]): a ésa la corta.
  ///
  /// Devuelve `true` si el texto se mandó al motor y `false` si se descartó.
  /// El que llama TIENE que mirar ese resultado si necesita saber si la frase
  /// se dijo: antes este método era `void` y [hablarSiCambio] daba por dicha
  /// una indicación que en realidad se había descartado (ver el comentario
  /// ahí), que es lo que demoraba ~15 s la primera indicación de cada ruta.
  bool hablarSinEsperar(String texto) {
    if (!_ttsInicializado || texto.trim().isEmpty) return false;
    if (_hablando) {
      // No interrumpir si ya se está hablando, salvo una frase secundaria:
      // ésa nunca demora a otra (ver [hablarSecundaria]).
      if (!_sonandoSecundaria) return false;
      hablar(texto);
    } else {
      _decirSinEsperar(texto);
    }
    _ultimaVezHablado = DateTime.now();
    _ultimaInstruccion = texto;
    return true;
  }

  /// Manda [texto] al motor con el motor libre, sin que nadie lo espere.
  void _decirSinEsperar(String texto) {
    _hablando = true;
    void libre() {
      _hablando = false;
      _sonandoSecundaria = false;
    }

    _tts.setCompletionHandler(libre);
    _tts.setCancelHandler(libre);
    _tts.setErrorHandler((_) => libre());
    _tts.speak(texto);
  }

  // ═══ FRASES SECUNDARIAS ═══
  //
  // "Estás en <punto clave>" es un dato útil, pero menos que cualquier
  // indicación. Antes se decía con hablarSinEsperar como una indicación
  // más: si caía justo antes del "Girá a la izquierda", el giro esperaba a
  // que terminara o lo cortaba a la mitad, y el aviso previo ("En 5 metros…")
  // directamente esperaba. Ahora es una frase SECUNDARIA: sólo arranca con
  // el motor libre, y cualquier otra frase que llegue mientras suena la
  // corta enseguida. Tampoco cuenta como "lo último que se dijo" para el
  // filtro de las indicaciones (separación entre indicaciones, repetición).

  /// true mientras suena una frase de [hablarSecundaria].
  bool _sonandoSecundaria = false;

  /// Frases de [hablar] que todavía están esperando el corte de la anterior
  /// (con `_hablando` todavía sin marcar). Una secundaria que arrancara en
  /// ese hueco se mezclaría con ellas.
  int _arrancando = 0;

  /// Dice [texto] como frase secundaria (ver arriba), sólo si el motor está
  /// libre. Devuelve `true` si lo mandó al motor.
  bool hablarSecundaria(String texto) {
    if (!_ttsInicializado || texto.trim().isEmpty) return false;
    if (_hablando || _arrancando > 0) return false;
    _decirSinEsperar(texto);
    _sonandoSecundaria = true;
    return true;
  }

  /// true si el filtro de [hablarSiCambio] tiene una indicación por decir
  /// dentro de [margen]: una nueva que se está confirmando, o la repetición
  /// de la última. Sirve para no empezar una frase secundaria que esa
  /// indicación cortaría a la mitad.
  bool indicacionCerca(Duration margen) {
    if (_instruccionCandidata.isNotEmpty &&
        _instruccionCandidata != _ultimaClaveHablada) {
      return true;
    }
    final desde = _ultimaVezHablado;
    return _ultimaClaveHablada.isNotEmpty &&
        desde != null &&
        DateTime.now().difference(desde) + margen > _intervaloMinimo;
  }

  /// Cuánto tarda en decirse [texto], aproximado, con la velocidad elegida.
  Duration duracionEstimada(String texto) => Duration(
        milliseconds: (texto.length *
                _msPorCaracterEstimado *
                100 /
                _ajustes.velocidad.valor)
            .round(),
      );
 
  // Filtro de estabilidad: la instrucción debe repetirse N veces
  // consecutivas antes de hablarse, descartando flickers de heading/posición.
  String _instruccionCandidata = '';

  /// Última clave hablada (la indicación sin la distancia). Se guarda aparte
  /// de [_ultimaInstruccion] porque el texto incluye los metros, que cambian
  /// todo el tiempo mientras el usuario camina.
  String _ultimaClaveHablada = '';
  int _contadorConfirmaciones = 0;
  static const int _confirmacionesNecesarias = 4;

  /// Además de las confirmaciones, una indicación NUEVA tiene que sostenerse
  /// este tiempo antes de decirse. Las confirmaciones solas no alcanzan: su
  /// duración depende del ritmo del scan BLE, y un error de una celda que
  /// dura un segundo puede llegar a juntar 4 ciclos y hacer que se diga un
  /// giro que no corresponde. Con el tiempo mínimo, ese tipo de rebote se
  /// descarta solo.
  static const Duration _estabilidadMinima = Duration(milliseconds: 1800);

  /// Separación mínima entre dos indicaciones DISTINTAS. Evita que, si la
  /// posición oscila entre dos celdas, la voz quede alternando órdenes
  /// contradictorias una atrás de la otra. Corto para no demorar un giro real.
  static const Duration _intervaloEntreDistintas = Duration(seconds: 2);

  /// Momento en que apareció la indicación candidata actual.
  DateTime? _candidataDesde;

  /// Habla una indicación aplicando dos filtros: estabilidad (hay que verla
  /// repetida varias veces) e intervalo mínimo entre repeticiones.
  ///
  /// [clave] es la parte que define "es la misma indicación". Si no se pasa,
  /// se usa el texto completo.
  ///
  /// POR QUÉ HACE FALTA LA CLAVE: el texto que llega es del tipo
  /// "Seguí derecho, 7 metros". Mientras la persona camina, la distancia
  /// cambia en cada ciclo, así que el texto NUNCA llegaba a repetirse las
  /// [_confirmacionesNecesarias] veces y la indicación no se hablaba nunca.
  /// Para esquivar eso, la distancia se venía redondeando a múltiplos de 5 m
  /// (lo que además producía el absurdo "a 0 metros" en todo el tramo final).
  /// Con la clave, la estabilidad se mide sobre la indicación —"Seguí
  /// derecho"— y la distancia se dice actualizada en el momento de hablar.
  Future<void> hablarSiCambio(String texto, {String? clave}) async {
    if (!_ttsInicializado || texto.trim().isEmpty) return;
    final ahora = DateTime.now();
    final k = (clave == null || clave.trim().isEmpty) ? texto : clave;

    // ── Filtro de estabilidad: confirmaciones Y tiempo ───────────────────────
    // Si la indicación cambió, reiniciar contador y reloj.
    if (k != _instruccionCandidata) {
      _instruccionCandidata = k;
      _contadorConfirmaciones = 1;
      _candidataDesde = ahora;
      return;
    }
    _contadorConfirmaciones++;
    if (_contadorConfirmaciones < _confirmacionesNecesarias) return;
    if (_candidataDesde != null &&
        ahora.difference(_candidataDesde!) < _estabilidadMinima) {
      return;
    }

    // ── Filtro de tiempo ─────────────────────────────────────────────────────
    final instruccionIgual = k == _ultimaClaveHablada;
    if (!instruccionIgual) {
      // Indicación nueva: se dice enseguida, pero nunca pisando a la anterior.
      if (_ultimaVezHablado != null &&
          ahora.difference(_ultimaVezHablado!) < _intervaloEntreDistintas) {
        return; // se dirá en el próximo ciclo, sin perder la candidata
      }
      // FIX (primera indicación a los ~15 s): la clave se anota como dicha
      // SÓLO si el motor aceptó la frase. Antes se anotaba siempre, y como
      // hablarSinEsperar() descarta el texto cuando el TTS está ocupado, una
      // indicación que caía mientras todavía sonaba "<destino>. Calculando
      // ruta." quedaba registrada como dicha sin haber sonado nunca. A partir
      // de ahí entraba en la rama de abajo ("misma indicación") y recién se
      // decía cuando vencía _intervaloMinimo: 15 segundos. Ahora, si el motor
      // está ocupado, la candidata queda viva y se reintenta en el próximo
      // ciclo (~0,2 s), o sea apenas termina la frase en curso.
      if (hablarSinEsperar(texto)) _ultimaClaveHablada = k;
      return;
    }

    // Misma indicación: sólo se repite cada _intervaloMinimo, con la
    // distancia actualizada.
    if (_ultimaVezHablado == null ||
        ahora.difference(_ultimaVezHablado!) > _intervaloMinimo) {
      hablarSinEsperar(texto);
    }
  }
 
  /// Dice YA una indicación de guiado, sin pasar por el filtro de estabilidad
  /// de [hablarSiCambio] (4 confirmaciones + 1,8 s).
  ///
  /// Es para la PRIMERA indicación de una ruta recién calculada: ahí no hay
  /// ningún rebote que filtrar —el usuario acaba de pedir el destino y está
  /// esperando que le digan para dónde ir— y cada segundo de silencio se
  /// siente como que la app no respondió.
  ///
  /// No interrumpe: si el motor está hablando devuelve `false` y no dice
  /// nada; el que llama reintenta en el próximo ciclo. Si habló, deja el
  /// filtro al día (ver [registrarInstruccionDicha]) y devuelve `true`.
  bool hablarInstruccionYa(String texto, {required String clave}) {
    if (!hablarSinEsperar(texto)) return false;
    registrarInstruccionDicha(clave);
    return true;
  }

  /// Dice un aviso que no puede esperar (el giro que hay que hacer ya).
  ///
  ///  - Motor libre → lo dice.
  ///  - Sonando una indicación común (de [hablarSinEsperar]) a la que le
  ///    falta bastante → la corta y dice el aviso: llegar tarde con un giro
  ///    es peor que dejar un "seguí derecho" por la mitad.
  ///  - Sonando una indicación que ya termina → espera (devuelve `false` y
  ///    el que llama reintenta en el próximo ciclo): cortarla para ganar
  ///    medio segundo sólo deja dos frases mochas.
  ///  - Sonando una frase de [hablar] (un anuncio, una pregunta) → espera
  ///    siempre; esas no se pisan.
  ///
  /// Si lo dijo, deja el filtro al día con [clave] y devuelve `true`.
  bool hablarUrgente(String texto, {required String clave}) {
    if (!_ttsInicializado || texto.trim().isEmpty) return false;
    if (_hablando) {
      if (_finFraseActual != null) return false;
      // Una frase secundaria se corta siempre, le falte lo que le falte.
      if (!_sonandoSecundaria) {
        final desde = _ultimaVezHablado;
        final restanteMs = desde == null
            ? 0
            : _ultimaInstruccion.length * _msPorCaracterEstimado -
                DateTime.now().difference(desde).inMilliseconds;
        if (restanteMs <= _esperaMaxUrgenteMs) return false;
      }
      // Cortar y decir. hablar() espera el aviso de corte del motor antes
      // de arrancar la frase nueva; acá no hace falta esperarla a ella.
      hablar(texto);
    } else if (!hablarSinEsperar(texto)) {
      return false;
    }
    registrarInstruccionDicha(clave);
    return true;
  }

  /// Duración estimada del habla, para saber cuánto le falta a la frase en
  /// curso (a velocidad 0.48 el motor anda por los 70-90 ms por carácter).
  static const int _msPorCaracterEstimado = 80;

  /// Si a la frase en curso le falta menos que esto, un aviso urgente la
  /// deja terminar en vez de cortarla.
  static const int _esperaMaxUrgenteMs = 600;

  /// Avisa al filtro de [hablarSiCambio] que la indicación [clave] ya se dijo
  /// por otro camino (por ejemplo dentro de una frase más larga dicha con
  /// [hablar]). Sin esto el filtro la vería como una indicación nueva y la
  /// repetiría a los dos segundos.
  void registrarInstruccionDicha(String clave) {
    _ultimaClaveHablada = clave;
    _instruccionCandidata = clave;
    _contadorConfirmaciones = _confirmacionesNecesarias;
    _candidataDesde = DateTime.now();
  }

  /// Olvida la última indicación dicha y la candidata en curso. Se llama al
  /// fijar un destino nuevo, al cancelar y al abrir la pantalla: VozService
  /// es un singleton, así que sin esto la última indicación de la navegación
  /// ANTERIOR seguía contando como "ya dicha" para la siguiente (si coincidía
  /// con la primera de la ruta nueva, no se repetía hasta pasados 15 s).
  void reiniciarFiltroInstrucciones() {
    _ultimaClaveHablada = '';
    _instruccionCandidata = '';
    _contadorConfirmaciones = 0;
    _candidataDesde = null;
  }

  /// Suelta a quien esté esperando la frase en curso de [hablar] (se usa al
  /// detener el motor desde afuera: esa frase ya no va a terminar sola).
  void _liberarEspera() {
    final c = _finFraseActual;
    _finFraseActual = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> detener() async {
    await _tts.stop();
    _hablando = false;
    _sonandoSecundaria = false;
    _liberarEspera();
  }
 
  bool get ttsDisponible => _ttsInicializado;
 
  // ─── STT: SPEECH TO TEXT ─────────────────────────────────────────────────────
 
  bool get sttDisponible => _sttDisponible;
  bool get escuchando => _escuchando;
 
  /// Locale de español del reconocedor, averiguado UNA vez.
  ///
  /// POR QUÉ: antes se averiguaba en cada escucha, con el micrófono todavía
  /// cerrado y la pantalla ya diciendo "Escuchando". En Android es una
  /// consulta de ida y vuelta al servicio de voz que puede tardar cientos de
  /// milisegundos. Quien contestaba enseguida ("sí", "no", "bar") hablaba en
  /// ese hueco y la palabra se perdía entera; en una frase larga sólo se
  /// perdía el principio y no se notaba.
  Future<String?>? _localeEspanol;

  /// Devuelve el locale de español disponible en el dispositivo,
  /// probando en orden: es_AR → es-AR → es_ES → es-ES → cualquier "es".
  /// Si no encuentra ninguno, devuelve null (usará el locale del sistema).
  Future<String?> _resolverLocaleEspanol() async {
    try {
      final locales = await _stt.locales();
      const candidatos = ['es_AR', 'es-AR', 'es_ES', 'es-ES', 'es_MX', 'es-MX'];
      for (final id in candidatos) {
        if (locales.any((l) => l.localeId == id)) return id;
      }
      // Cualquier locale que empiece con "es"
      final cualquierEs = locales.firstWhere(
        (l) => l.localeId.startsWith('es'),
        orElse: () => locales.first,
      );
      return cualquierEs.localeId;
    } catch (_) {
      return null; // Deja que el sistema elija
    }
  }
 
  // ─── ESCUCHA: una sesión, un aviso ──────────────────────────────────────────
  //
  // Cada llamada a [escuchar] es una SESIÓN y termina exactamente una vez,
  // avisando por onResultado o por onError. Antes eso no estaba garantizado:
  //
  //  • Cuando el usuario no decía nada, o no se le entendía, el motor avisa
  //    con un ERROR (no con un resultado), y ese error sólo llegaba al
  //    listener global de initialize(), que apagaba la bandera _escuchando y
  //    nada más. El timeout de seguridad de escuchar() preguntaba justamente
  //    por esa bandera, así que tampoco avisaba. Resultado: ni onResultado
  //    ni onError; quien había preguntado algo ("¿Vamos ahí?") se quedaba
  //    esperando para siempre y la pantalla quedaba "escuchando" hasta que
  //    el usuario la tocaba.
  //  • El timeout de seguridad de una escucha vieja podía dispararse durante
  //    una escucha NUEVA y cortarla (miraba la bandera global, no su sesión).
  //
  // Ahora la sesión se cierra con lo primero que pase: un resultado final,
  // un error del motor, el aviso de "terminé" sin resultado, que alguien la
  // corte, o el timeout. Todo lo que llega después se ignora.

  // ═══ CUÁNDO TERMINÓ DE HABLAR: LO DECIDE LA APP ═══
  // Medido en el teléfono: para decir "casa", el texto llegaba 5,3 s después
  // de abrirse el micrófono (la ruta, en 7 ms). El fin de lo dicho lo
  // marcaba el plugin, que tiene una sola espera (pauseFor) para el silencio
  // hasta que la persona EMPIEZA a hablar y para el silencio con el que se da
  // por TERMINADO lo que dijo. Después de cortar, además, espera el texto
  // final de Android, y si no llega, 2 s más antes de usar el último parcial.
  //
  // Ahora el plugin sólo se queda con la espera para empezar
  // ([_esperaParaEmpezar]). El final lo marca la app: con un rato sin un
  // texto parcial nuevo, se corta la escucha y vale el último parcial. El
  // rato es corto si lo dicho ya se entiende ([_silencioAlTerminar]) y más
  // largo si todavía no ([_silencioSinEntender]).
  //
  // El texto final de Android no se espera. Medido en un Pixel 9 Pro XL
  // reconociendo por internet: llegaba 1,6 a 2 s después de cortar, siempre
  // igual al último parcial. Y el primer parcial llega recién cuando la
  // persona ya terminó de decir el nombre (2,3 a 2,9 s después de empezar a
  // hablar), así que lo que se espera después de él puede ser corto.

  /// Lo que tiene la persona para empezar a hablar después de la pregunta.
  static const Duration _esperaParaEmpezar = Duration(seconds: 3);

  /// Silencio (tiempo sin un texto parcial nuevo) con el que se da por
  /// terminado lo que dijo, cuando lo dicho ya es algo que quien pregunta
  /// entiende ("casa", "sí"; ver `entiende` en [escuchar]). Con 1,5 s sobraba
  /// (ver arriba); menos que esto podría cortar a quien hace una pausa en el
  /// medio de un nombre ("aula… doce").
  static const Duration _silencioAlTerminar = Duration(milliseconds: 800);

  /// El mismo silencio cuando lo dicho todavía no se entiende ("quiero ir
  /// a…"): seguramente falta el nombre. Medido: antes del nombre del lugar,
  /// el reconocedor tardó 0,68 s en un pedido y más de 0,8 s en otro, que
  /// con [_silencioAlTerminar] se cortó en "quiero ir a".
  static const Duration _silencioSinEntender = Duration(milliseconds: 1500);

  // ═══ RECONOCER EN EL TELÉFONO, SIN INTERNET ═══
  // El reconocedor de Google, por internet, manda el audio a sus servidores:
  // sin conexión no entiende el destino. Medido en un Pixel 9 Pro XL, además,
  // el primer texto parcial llegaba 1,5 a 2,9 s después de que la persona
  // empezaba a hablar. Con el español descargado en el teléfono, se
  // reconoce ahí mismo.
  //
  // Al inicializar se averigua, SIN abrir el micrófono, si está descargado
  // (ver reconocimiento_telefono.dart). Si lo está, se escucha en el
  // teléfono. Si se puede descargar, se pide la descarga una vez por
  // ejecución y se avisa; mientras tanto, por internet. Antes se probaba
  // abriendo el micrófono en el teléfono y esperando el error: en ese Pixel
  // daba error_language_unavailable, y el cambio a internet dejaba el
  // micrófono cerrado ~0,4 s, en los que se perdía la palabra de quien
  // contestaba enseguida. Ese paso a internet ([escuchar]) queda como
  // resguardo, por si el teléfono dice que lo tiene y después no arranca.
  //
  // Sin el español descargado y sin conexión, no se escucha: se avisa
  // ([avisoSinConexion]) y se puede elegir el destino de la lista.

  /// Cómo está el español para reconocer en el teléfono, y con qué idioma.
  ConsultaIdioma _idioma = const ConsultaIdioma(EstadoIdioma.noDisponible);

  /// Ya se pidió la descarga en esta ejecución de la app.
  bool _descargaPedida = false;

  /// El reconocimiento en el teléfono no arrancó aunque estaba descargado:
  /// por lo que queda de esta ejecución, por internet.
  bool _fallaEnTelefono = false;

  /// Si la próxima escucha va en el teléfono.
  bool get _reconocerEnTelefono =>
      _idioma.estado == EstadoIdioma.descargado && !_fallaEnTelefono;

  /// Atiende un error del motor durante la escucha en curso. true si lo
  /// atendió (la escucha sigue por internet) y no hay que cerrarla.
  bool Function(String error)? _atenderErrorDelMotor;

  /// Motivo con el que termina (por onError) una escucha que no pudo
  /// entender por falta de conexión. Quien escucha dice [avisoSinConexion].
  static const String errorSinConexion = 'sin conexión';

  /// Errores del motor que quieren decir que no hay conexión.
  static const Set<String> _erroresDeRed = {
    'error_network',
    'error_network_timeout',
    'error_server',
    'error_server_disconnected',
  };

  /// Averigua cómo está el español para reconocer en el teléfono.
  Future<void> _actualizarIdioma() async {
    final local = await (_localeEspanol ?? Future<String?>.value());
    final preferido = (local ?? 'es-AR').replaceAll('_', '-');
    _idioma = await ReconocimientoEnTelefono.consultar(preferido);
    debugPrint('[Voz] Español para reconocer en el teléfono: $_idioma.');
  }

  /// Averigua si el español está descargado en el teléfono y, si falta y se
  /// puede, pide la descarga (una vez por ejecución) y lo avisa.
  Future<void> _prepararReconocimientoEnTelefono() async {
    await _actualizarIdioma();
    final idioma = _idioma.idioma;
    if (_idioma.estado != EstadoIdioma.sinDescargar ||
        idioma == null ||
        _descargaPedida) {
      return;
    }
    _descargaPedida = true;
    ReconocimientoEnTelefono.escucharDescarga(
      alTerminar: (lista) async {
        await _actualizarIdioma();
        if (lista && _idioma.estado == EstadoIdioma.descargado) {
          unawaited(hablar('Listo: ya se puede entender la voz sin internet.'));
        }
      },
    );
    final pedida = await ReconocimientoEnTelefono.pedirDescarga(idioma);
    debugPrint('[Voz] Descarga de $idioma ${pedida ? 'pedida' : 'rechazada'}.');
    if (!pedida) return;
    _idioma = ConsultaIdioma(EstadoIdioma.descargando, idioma);
    unawaited(hablar(
      'Se está descargando el español para entender la voz sin internet. '
      'Hasta que termine, para entender la voz hace falta conexión.',
    ));
  }

  /// Si ahora se puede entender la voz: con el español descargado en el
  /// teléfono, siempre; si no, sólo con conexión a internet. Si no, quien
  /// pregunta dice [avisoSinConexion] en lugar de abrir el micrófono.
  Future<bool> puedeEntenderVoz() async {
    // Sin reconocedor, el aviso lo da escuchar().
    if (!_sttDisponible) return true;
    // La descarga pudo haber terminado (con Android 13 no avisa).
    if (_idioma.estado == EstadoIdioma.descargando) await _actualizarIdioma();
    if (_reconocerEnTelefono) return true;
    return ReconocimientoEnTelefono.hayConexion();
  }

  /// Lo que se dice cuando no se puede entender la voz por falta de
  /// conexión: por qué, y qué se puede hacer.
  String get avisoSinConexion => switch (_idioma.estado) {
    EstadoIdioma.descargando =>
      'No hay conexión a internet, y el español para entender la voz sin '
          'internet todavía se está descargando. Podés elegir el destino de '
          'la lista.',
    EstadoIdioma.sinDescargar =>
      'No hay conexión a internet, y falta descargar el español para '
          'entender la voz sin internet. Podés elegir el destino de la lista.',
    EstadoIdioma.descargado || EstadoIdioma.noDisponible =>
      'No hay conexión a internet, y sin ella este teléfono no puede '
          'entender la voz. Podés elegir el destino de la lista.',
  };

  /// Diagnóstico: cuánto tiene que subir el nivel de sonido sobre el más
  /// bajo de la escucha para registrar que se empieza a oír voz.
  static const double _subidaDeVozDb = 4.0;

  /// Motivo con el que termina (por onError) una escucha que se cortó a
  /// propósito: [detenerEscucha], otra llamada a [escuchar] o [limpiar]. El
  /// que escucha lo distingue para no decir "no te escuché" cuando en
  /// realidad fue el propio usuario el que la cortó.
  static const String errorCancelado = 'cancelado';

  /// Cierra con error la sesión en curso. Null si no hay ninguna abierta.
  void Function(String motivo)? _cerrarSesion;

  /// Número de la sesión en curso (para que los avisos demorados de una
  /// sesión no toquen a la siguiente).
  int _sesionEscucha = 0;

  /// true desde que se le pidió al motor que escuche para la sesión en
  /// curso. Antes de eso, un "done" o un error que llegue del motor es la
  /// cola de la escucha ANTERIOR (por ejemplo, la que se acaba de cortar) y
  /// no tiene que cerrar la sesión nueva.
  bool _motorPedido = false;

  /// El motor avisó que terminó (error, o "done" sin resultado). Se le da un
  /// instante por si el resultado final viene atrás —en algunos equipos
  /// llega después del aviso— y, si no vino, se cierra la sesión.
  void _cerrarSesionTrasGracia(String motivo) {
    final cerrar = _cerrarSesion;
    if (cerrar == null || !_motorPedido) return;
    final sesion = _sesionEscucha;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (sesion == _sesionEscucha) cerrar(motivo);
    });
  }

  /// Escucha una frase del usuario. Termina SIEMPRE con un aviso, y uno solo:
  /// [onResultado] con lo que dijo, u [onError] con el motivo ('sin texto' si
  /// no dijo nada o no se entendió, [errorCancelado] si se la cortó).
  ///
  /// Si ya había una escucha abierta, se la corta (su dueño recibe
  /// [errorCancelado]) y arranca esta.
  ///
  /// [entiende]: el reconocedor devuelve hasta 10 interpretaciones, de la más
  /// a la menos probable, y con palabras cortas la correcta muchas veces no
  /// es la primera ("sí" sale "c", "no" sale "nos"). Si se pasa, se entrega
  /// la primera interpretación que [entiende] da por buena (recibe el texto
  /// en minúsculas); si ninguna, la más probable, como antes.
  Future<void> escuchar({
    required void Function(String texto) onResultado,
    void Function(String error)? onError,
    void Function(bool activo)? onEscuchando,
    bool Function(String texto)? entiende,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!_sttDisponible) {
      onError?.call('Reconocimiento de voz no disponible');
      return;
    }
    final anterior = _cerrarSesion;
    if (anterior != null) {
      anterior(errorCancelado);
      try {
        await _stt.stop();
      } catch (_) {}
    }

    final sesion = ++_sesionEscucha;
    _motorPedido = false;
    bool cerrada = false;
    // Lo último que el motor entendió sin darlo por final. Si la escucha
    // termina sin resultado final pero con esto cargado (pasa en algunos
    // equipos), se entrega: es mejor que descartar lo que el usuario dijo.
    String parcial = '';
    // Las interpretaciones de ese parcial, por si hay que cerrar con él.
    List<String> opcionesParcial = const [];
    // Corre desde el último parcial nuevo: si se cumple, terminó de hablar.
    Timer? finDeFrase;

    void cerrar({String? texto, String motivo = 'sin texto'}) {
      if (cerrada) return;
      cerrada = true;
      finDeFrase?.cancel();
      if (sesion == _sesionEscucha) {
        _escuchando = false;
        _cerrarSesion = null;
        _atenderErrorDelMotor = null;
      }
      onEscuchando?.call(false);
      final dicho = texto ?? (motivo == errorCancelado ? '' : parcial);
      if (dicho.isNotEmpty) {
        onResultado(dicho.toLowerCase());
      } else {
        onError?.call(motivo);
      }
    }

    _cerrarSesion = (motivo) => cerrar(motivo: motivo);

    // El micrófono se abre YA, sin pausa: quien pregunta esperó a que el
    // motor de voz avisara que terminó la frase (ver [hablar]), y ese aviso
    // llega con el audio ya reproducido. Antes había acá 200 ms "para que se
    // apague el altavoz": sumados a lo que tarda el reconocedor en arrancar,
    // quien contestaba enseguida hablaba con el micrófono todavía cerrado y
    // la palabra se perdía.
    _escuchando = true;
    onEscuchando?.call(true);
    final reloj = Stopwatch()..start();
    bool microfonoAbierto = false;

    /// De las interpretaciones del motor, la primera que [entiende] da por
    /// buena; si ninguna, [texto] (la más probable).
    String elegir(List<String> opciones, String texto) => entiende == null
        ? texto
        : opciones.firstWhere((t) => entiende(t.toLowerCase()),
            orElse: () => texto);

    // Pasó [_silencioAlTerminar] sin un parcial nuevo: terminó de hablar.
    // Vale el último parcial, y el micrófono se suelta sin esperar el texto
    // final (ver "CUÁNDO TERMINÓ DE HABLAR").
    void terminoDeHablar() {
      if (cerrada) return;
      final elegido = elegir(opcionesParcial, parcial);
      debugPrint('[Voz] ${reloj.elapsedMilliseconds} ms: silencio, vale el '
          'parcial "$elegido".');
      unawaited(_stt.cancel().catchError((Object _) {}));
      cerrar(texto: elegido);
    }

    // Locale de español del dispositivo: ya averiguado (ver _localeEspanol).
    final localeInternet = await (_localeEspanol ??= _resolverLocaleEspanol());
    if (cerrada) return;

    // En el teléfono si el español está descargado (ver "RECONOCER EN EL
    // TELÉFONO"), con el idioma descargado ("es-AR", o el español que haya).
    var enTelefono = _reconocerEnTelefono;
    final localeTelefono = _idioma.idioma;
    // Ya llegó texto: un error del motor desde acá no quiere decir que el
    // reconocimiento en el teléfono no ande.
    var huboTexto = false;
    var nivelMinimo = double.infinity;
    var vozOida = false;

    Future<void> arrancar() async {
      _motorPedido = true;
      _escuchando = true;
      await _stt.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: enTelefono ? localeTelefono : localeInternet,
          listenFor: timeout,
          // Lo que tiene la persona para empezar a hablar. El final lo
          // marca la app (ver "CUÁNDO TERMINÓ DE HABLAR").
          pauseFor: _esperaParaEmpezar,
          // Con los parciales se sabe que sigue hablando, y cuándo paró.
          partialResults: true,
          onDevice: enTelefono,
        ),
        onSoundLevelChange: (nivel) {
          // El nivel de sonido llega recién con el micrófono grabando: el
          // primero dice cuánto tardó en abrirse de verdad.
          if (!microfonoAbierto) {
            microfonoAbierto = true;
            debugPrint(
              '[Voz] Micrófono abierto a los '
              '${reloj.elapsedMilliseconds} ms de pedirlo '
              '(${enTelefono ? 'en el teléfono' : 'por internet'}).',
            );
          }
          // Diagnóstico: cuándo se empieza a oír voz, para medir cuánto
          // tarda el primer texto parcial.
          if (nivel < nivelMinimo) nivelMinimo = nivel;
          if (!vozOida && nivel >= nivelMinimo + _subidaDeVozDb) {
            vozOida = true;
            debugPrint('[Voz] ${reloj.elapsedMilliseconds} ms: se oye voz '
                '(nivel ${nivel.toStringAsFixed(1)} dB).');
          }
        },
        onResult: (result) {
          if (cerrada) return;
          huboTexto = true;
          final texto = result.recognizedWords.trim();
          final opciones = [
            for (final a in result.alternates)
              if (a.recognizedWords.trim().isNotEmpty) a.recognizedWords.trim(),
          ];
          if (!result.finalResult) {
            if (texto.isEmpty) return;
            final nuevo = texto.toLowerCase() != parcial.toLowerCase();
            parcial = texto;
            opcionesParcial = opciones;
            // Sólo un texto distinto cuenta como que sigue hablando: el
            // motor a veces repite el mismo parcial.
            if (nuevo) {
              // ¿Ya dijo algo que se entiende? Entonces el silencio que
              // falta para cerrar es corto (ver "CUÁNDO TERMINÓ DE HABLAR").
              final entendido = entiende != null &&
                  (opciones.isEmpty ? [texto] : opciones)
                      .any((t) => entiende(t.toLowerCase()));
              debugPrint('[Voz] ${reloj.elapsedMilliseconds} ms: parcial '
                  '"$texto"${entendido ? ' (se entiende)' : ''}.');
              finDeFrase?.cancel();
              finDeFrase = Timer(
                entendido ? _silencioAlTerminar : _silencioSinEntender,
                terminoDeHablar,
              );
            }
            return;
          }
          if (texto.isEmpty) {
            cerrar(); // final vacío: vale el parcial si hubo, si no 'sin texto'
            return;
          }
          final elegido = elegir(opciones, texto);
          debugPrint('[Voz] Entendido a los ${reloj.elapsedMilliseconds} ms: '
              '"$elegido" (interpretaciones: ${opciones.join(' | ')})');
          cerrar(texto: elegido);
        },
      );
    }

    // El reconocimiento en el teléfono no arrancó aunque el español estaba
    // descargado: esta escucha sigue por internet, y las que vengan en esta
    // ejecución, también. Sin conexión, se avisa (errorSinConexion).
    void pasarAInternet(String motivo) {
      enTelefono = false;
      _fallaEnTelefono = true;
      microfonoAbierto = false;
      // Lo que quede de la escucha fallida ("done", otro error) no tiene que
      // cerrar esta sesión (ver _cerrarSesionTrasGracia).
      _motorPedido = false;
      debugPrint('[Voz] ${reloj.elapsedMilliseconds} ms: el reconocimiento '
          'en el teléfono no anduvo ($motivo); sigue por internet.');
      Future.delayed(const Duration(milliseconds: 150), () async {
        if (cerrada || sesion != _sesionEscucha) return;
        if (!await ReconocimientoEnTelefono.hayConexion()) {
          cerrar(motivo: errorSinConexion);
          return;
        }
        if (cerrada || sesion != _sesionEscucha) return;
        try {
          await arrancar();
        } catch (e) {
          cerrar(motivo: 'Error: $e');
        }
      });
    }

    _atenderErrorDelMotor = (error) {
      if (!enTelefono || huboTexto || cerrada || sesion != _sesionEscucha) {
        return false;
      }
      // No dijo nada o no se le entendió: el reconocedor anduvo.
      if (error == 'error_speech_timeout' || error == 'error_no_match') {
        return false;
      }
      pasarAInternet(error);
      return true;
    };

    try {
      await arrancar();
    } catch (e) {
      if (enTelefono) {
        pasarAInternet('$e');
      } else {
        cerrar(motivo: 'Error: $e');
      }
    }
    // Timeout de seguridad, por si el motor no avisa nada de nada. Cierra
    // SU sesión (si ya se cerró, no hace nada).
    Future.delayed(timeout + const Duration(seconds: 3), () => cerrar());
  }

  /// Corta la escucha en curso. Quien la había pedido recibe
  /// onError([errorCancelado]).
  Future<void> detenerEscucha() async {
    final cerrar = _cerrarSesion;
    if (!_escuchando && cerrar == null) return;
    // Primero se cierra la sesión: lo que el motor entregue al frenar ya no
    // cuenta como respuesta.
    cerrar?.call(errorCancelado);
    _escuchando = false;
    try {
      await _stt.stop();
    } catch (_) {}
  }

  /// Detiene TTS y STT. Si se pasa [dueno], la limpieza se ignora cuando ese
  /// objeto ya no es la pantalla de voz activa (ver [_dueno]).
  void limpiar({Object? dueno}) {
    if (dueno != null && !esDueno(dueno)) return;
    _dueno = null;
    _tts.stop();
    _hablando = false;
    _sonandoSecundaria = false;
    _liberarEspera();
    // La pantalla se va: la escucha en curso termina como cancelada, para
    // que nadie diga "no te escuché" sobre una pantalla que ya no está.
    _cerrarSesion?.call(errorCancelado);
    _stt.stop();
    _escuchando = false;
  }
}