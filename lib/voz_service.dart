// Voz de la app: hablar (TTS) y escuchar (reconocimiento de voz).
//
// VozService es un singleton que comparten todas las pantallas. Ordena qué se
// dice y cuándo: las indicaciones de guiado pasan por un filtro anti-rebote,
// los giros urgentes cortan lo que suena y las frases secundarias ("Estás
// en…") ceden ante cualquier otra. Para escuchar, cada pregunta es una sesión
// que termina una sola vez, y el fin de lo dicho lo decide la app. Con un
// auricular Bluetooth conectado, la escucha usa su micrófono (ver
// "MICRÓFONO DEL AURICULAR"). Una pregunta y su escucha van juntas, para que
// el micrófono grabe desde que termina la pregunta (ver "PREGUNTAR Y
// ESCUCHAR SIN HUECO").

import 'dart:async';
import 'dart:math' as math;
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

  // ── MICRÓFONO DEL AURICULAR ───────────────────────────────────────────────
  // Android graba con el micrófono del teléfono aunque haya un auricular
  // Bluetooth conectado, salvo que la app pida el del auricular. El auricular
  // recibe el audio por uno de dos canales que no andan a la vez: el de la
  // música (sólo del teléfono al auricular, en buena calidad) y el de voz (de
  // ida y vuelta, con calidad de llamada: el único por el que llega su
  // micrófono). Pasar de uno a otro tarda: abrir el de voz, entre 0,25 y
  // 0,7 s en la prueba del 24/11/2026.
  //
  // Al empezar cada escucha se pide el canal de voz
  // (ReconocimientoEnTelefono.usarMicrofonoAuricular, que espera a que quede
  // abierto) y al cerrarla se suelta, para que la música y la voz de la app
  // vuelvan al canal de la música. La frase que sigue, también una
  // indicación de la guía, espera a que el auricular vuelva
  // ([_esperaVueltaMusica]). Sin auricular, o si no se abre, se escucha con
  // el micrófono del teléfono y no hay esperas.
  //
  // El canal no se deja abierto para la respuesta ni para la pregunta
  // siguiente, aunque eso ahorraría la espera: Android sólo deja que una app
  // mantenga el modo llamada mientras ella misma reproduce o graba audio, y
  // la voz de la app la reproduce el motor de voz del teléfono, que es otra
  // app. En la prueba del 25/11/2026, 1,5 s después de que el reconocedor
  // dejó de grabar Android dio a BlindRoute por inactiva, le sacó el modo
  // llamada y a los 6 s cortó el canal; las escuchas siguientes, que creían
  // tenerlo abierto, grabaron con el micrófono del teléfono.
  // El plugin de voz tiene otra forma de usar el auricular, que se apaga al
  // inicializarlo (androidNoBluetooth; ver MainActivity.kt).

  /// Si el micrófono del auricular está abierto para la escucha en curso.
  bool _microfonoAuricular = false;

  /// Cuándo se soltó por última vez el micrófono del auricular.
  DateTime? _auricularSoltadoEn;

  /// Lo que se espera, después de soltar el micrófono del auricular, antes
  /// de la frase siguiente: el auricular tiene que pasar del canal de voz al
  /// de la música, y lo que se diga mientras tanto se pierde (en la prueba
  /// del 24/11/2026 se escuchó "…lando ruta" en lugar de "Calculando
  /// ruta"). Elegido sin medir: ajustarlo con lo que muestre el log ("[Voz]
  /// Espera … ms").
  static const Duration _esperaVueltaMusica = Duration(milliseconds: 1000);

  /// Suelta el micrófono del auricular, si estaba abierto.
  void _soltarMicrofonoAuricular() {
    if (!_microfonoAuricular) return;
    _microfonoAuricular = false;
    _auricularSoltadoEn = DateTime.now();
    unawaited(ReconocimientoEnTelefono.soltarMicrofonoAuricular());
  }

  /// Si el auricular todavía está volviendo al canal de la música (ver
  /// [_esperaVueltaMusica]).
  bool get _musicaVolviendo {
    final soltado = _auricularSoltadoEn;
    return soltado != null &&
        DateTime.now().difference(soltado) < _esperaVueltaMusica;
  }

  /// Si el micrófono del auricular se soltó hace menos de
  /// [_esperaVueltaMusica], espera lo que falta. Sin auricular, nada.
  Future<void> _esperarVueltaDeLaMusica() async {
    final soltado = _auricularSoltadoEn;
    if (soltado == null) return;
    final falta = _esperaVueltaMusica - DateTime.now().difference(soltado);
    if (falta <= Duration.zero) return;
    debugPrint('[Voz] Espera ${falta.inMilliseconds} ms a que el auricular '
        'vuelva a la música.');
    await Future<void>.delayed(falta);
  }

  // ── PREGUNTAR Y ESCUCHAR SIN HUECO ────────────────────────────────────────
  // El reconocedor de Android empieza a grabar recién un rato después de
  // pedírselo: en un Pixel 9 Pro XL, entre 1,06 y 1,24 s (24/11/2026). Si se
  // lo pidiera al terminar la pregunta, lo que la persona contesta en ese
  // segundo se perdería: un "hola" dicho enseguida no llegaba. Por eso
  // [escuchar] con una pregunta:
  //  1. Con auricular, abre su canal de voz ANTES de la pregunta, que se oye
  //     por ese canal: abrirlo con la frase sonando la cortaría al cambiar de
  //     canal, y abrirlo después sumaría ~0,7 s de hueco.
  //  2. Pide el reconocedor mientras la pregunta todavía suena, para que
  //     empiece a grabar poco después de que termina. Cuándo, sale de dos
  //     medidas tomadas en el mismo teléfono: lo que duró esa pregunta (lo
  //     más que duró las últimas veces que se dijo entera) y lo que tarda el
  //     reconocedor en arrancar (lo menos que tardó las últimas veces), y
  //     [_margenFinPregunta]. Así sirve en teléfonos que arrancan más rápido
  //     o más lento, y con cualquier velocidad de la voz. Sin esas medidas
  //     (la primera pregunta de cada ejecución), el reconocedor se pide al
  //     terminar la pregunta.
  // Las dos medidas se toman del lado que hace empezar más tarde, porque
  // grabar el final de la pregunta es peor que perder un instante: con
  // auricular, su micrófono está pegado al parlante y oye la pregunta, y en
  // preguntas como "¿De hombres o de mujeres?" o "¿Vamos ahí?" lo último que
  // se dice es una respuesta válida: la app se contestaría sola. Ningún
  // filtro del texto puede distinguir ese eco de una respuesta de verdad.
  // El log "[Voz] El micrófono empezó a grabar … ms después del fin de la
  // pregunta" dice cómo salió.

  /// Lo que duró cada pregunta las últimas veces que el motor la dijo
  /// entera, desde que se le mandó hasta su aviso de fin. La clave lleva la
  /// velocidad de la voz, que cambia la duración.
  final Map<String, List<int>> _duracionPreguntas = {};

  /// Lo que tardó el reconocedor en empezar a grabar (desde que se le pide
  /// hasta el primer nivel de sonido) las últimas veces, en el teléfono
  /// (true) y por internet (false), que arrancan distinto.
  final Map<bool, List<int>> _arranquesReconocedor = {true: [], false: []};

  /// Cuántas medidas se guardan, de cada pregunta y del arranque del
  /// reconocedor.
  static const int _medidasGuardadas = 5;

  /// Lo mínimo que se quiere entre el fin de la pregunta y el momento en
  /// que el reconocedor empieza a grabar. En la prueba del 24/11/2026 con
  /// auricular (23:41), el micrófono grabó la propia pregunta las dos veces
  /// que empezó a grabar 150 ms o menos después de su fin, y ninguna de las
  /// cuatro en que fue 316 ms o más: por el Bluetooth, la pregunta se sigue
  /// oyendo un rato después de que el motor avisa que terminó.
  static const Duration _margenFinPregunta = Duration(milliseconds: 400);

  /// Agrega [ms] a [lista], que guarda las últimas [_medidasGuardadas].
  static void _anotar(List<int> lista, int ms) {
    lista.add(ms);
    if (lista.length > _medidasGuardadas) lista.removeAt(0);
  }

  /// Anota lo que tardó el reconocedor en arrancar.
  void _anotarArranque(bool enTelefono, int ms) =>
      _anotar(_arranquesReconocedor[enTelefono]!, ms);

  /// Cuántos milisegundos después de mandar [pregunta] al motor hay que
  /// pedir el reconocedor para que empiece a grabar [_margenFinPregunta]
  /// después de que ella termina (o algo más, nunca menos, si esta vez la
  /// pregunta dura menos o el reconocedor tarda más que otras veces). Null si
  /// todavía no hay medidas: entonces se lo pide al terminar.
  int? _pedirReconocedorA(String pregunta, bool enTelefono) {
    final duraciones = _duracionPreguntas[_clavePregunta(pregunta)];
    final arranques = _arranquesReconocedor[enTelefono]!;
    if (duraciones == null || duraciones.isEmpty || arranques.isEmpty) {
      return null;
    }
    final adelanto =
        arranques.reduce(math.min) - _margenFinPregunta.inMilliseconds;
    if (adelanto <= 0) return null;
    return math.max(0, duraciones.reduce(math.max) - adelanto);
  }

  String _clavePregunta(String pregunta) =>
      '${_ajustes.velocidad.valor}|$pregunta';

  // ── DUEÑO ACTUAL ──────────────────────────────────────────────────────────
  // VozService es un singleton, así que `limpiar()` de una pantalla detiene el
  // TTS de TODAS. Flutter destruye la pantalla saliente después de construir la
  // entrante, así que ese `limpiar()` tardío cortaría el anuncio de la
  // pantalla nueva. Con un token de dueño, la limpieza tardía es inofensiva.
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
        // El micrófono del auricular lo abre la app (ver "MICRÓFONO DEL
        // AURICULAR"); el plugin, por su lado, no. Así tampoco pide el
        // permiso de dispositivos cercanos para eso.
        options: [stt.SpeechToText.androidNoBluetooth],
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
  /// frase. Si [hablar] hiciera `stop()` y enseguida instalara los handlers
  /// de la frase NUEVA, el aviso de cancelación de la frase VIEJA llegaría un
  /// instante después y lo recibiría el handler nuevo, que entendería
  /// "terminé": pondría `_hablando = false` con la frase nueva recién
  /// empezando, y la próxima indicación de guiado la pisaría (el motor corta
  /// lo que suena al recibir otro `speak`). Acá el aviso viejo lo consume un
  /// handler temporal y recién después se instala el de la frase nueva.
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
  Future<void> hablar(String texto) => _decir(texto);

  /// [hablar], avisándole a [alEmpezar] en el instante en que la frase se
  /// manda al motor. Devuelve true si el motor avisó que la terminó, y false
  /// si no se dijo, se cortó, falló o venció el tope (ver "PREGUNTAR Y
  /// ESCUCHAR SIN HUECO", que sólo mide las frases dichas enteras).
  Future<bool> _decir(String texto, {void Function()? alEmpezar}) async {
    if (!_ttsInicializado || texto.trim().isEmpty) return false;
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
    var entera = false;
    _tts.setCompletionHandler(() {
      if (identical(_finFraseActual, completer)) entera = true;
      completar();
    });

    // También capturar cancelación/error del motor
    _tts.setCancelHandler(completar);
    _tts.setErrorHandler((msg) => completar());

    // Recién soltado el micrófono del auricular, se le da tiempo a volver a
    // la música (ver "MICRÓFONO DEL AURICULAR"). Si mientras tanto otra
    // frase reemplazó a ésta, ésta ya no se dice.
    await _esperarVueltaDeLaMusica();
    if (!identical(_finFraseActual, completer)) return false;

    alEmpezar?.call();
    await _tts.speak(texto);
    _ultimaVezHablado = DateTime.now();
    _ultimaInstruccion = texto;

    // Timeout de seguridad, por si el motor no avisa que terminó: ~150 ms por
    // carácter con la voz al 100 % (el doble de lo que tarda de verdad),
    // mínimo 1500 ms, más 600 ms de margen para que el altavoz se apague
    // físicamente antes de abrir el micrófono.
    //
    // Se escala con la velocidad elegida y el tope es largo a propósito: con
    // un tope fijo de 12 s, una frase larga (la lista de opciones) o
    // cualquiera de más de ~95 caracteres con la voz al 60 % se daría por
    // terminada mientras todavía suena. El micrófono se abriría con la app
    // hablando y la frase siguiente la pisaría.
    final msPorCaracter = 150 * 100 / _ajustes.velocidad.valor;
    final timeoutMs =
        (texto.length * msPorCaracter).round().clamp(1500, 40000) + 600;
    await completer.future
        .timeout(Duration(milliseconds: timeoutMs), onTimeout: completar);
    return entera;
  }
 
  /// Habla sin esperar — para instrucciones de navegación que se actualizan
  /// continuamente y no deben bloquear el widget tree.
  /// Si el motor ya está reproduciendo audio, descarta el nuevo texto para no
  /// interrumpir la locución en curso, salvo que sea una frase secundaria
  /// (ver [hablarSecundaria]): a ésa la corta.
  ///
  /// Devuelve `true` si el texto se mandó al motor y `false` si se descartó.
  /// El que llama TIENE que mirar ese resultado si necesita saber si la frase
  /// se dijo (ver [hablarSiCambio]).
  bool hablarSinEsperar(String texto) {
    if (!_ttsInicializado || texto.trim().isEmpty) return false;
    if (_hablando) {
      // No interrumpir si ya se está hablando, salvo una frase secundaria:
      // ésa nunca demora a otra (ver [hablarSecundaria]).
      if (!_sonandoSecundaria) return false;
      hablar(texto);
    } else if (_musicaVolviendo) {
      // Recién soltado el canal de voz: dicha ya, se perdería el comienzo.
      // [hablar] espera lo que falta (ver "MICRÓFONO DEL AURICULAR").
      unawaited(hablar(texto));
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
  // indicación. Dicho como una indicación más, si cae justo antes del "Girá
  // a la izquierda", el giro tendría que esperar a que termine o cortarlo a
  // la mitad. Por eso es una frase SECUNDARIA: sólo arranca con el motor
  // libre, y cualquier otra frase que llegue mientras suena la corta
  // enseguida. Tampoco cuenta como "lo último que se dijo" para el
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
    // Recién soltado el canal de voz del auricular se perdería el comienzo:
    // como con el motor ocupado, no se dice.
    if (_hablando || _arrancando > 0 || _musicaVolviendo) return false;
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
      // La clave se anota como dicha SÓLO si el motor aceptó la frase:
      // hablarSinEsperar() la descarta si el TTS está ocupado. Si se anotara
      // igual, la indicación quedaría como dicha sin haber sonado, caería en
      // la rama de abajo ("misma indicación") y recién se diría al vencer
      // _intervaloMinimo (15 s). Así, con el motor ocupado la candidata queda
      // viva y se reintenta en el próximo ciclo (~0,2 s), apenas termina la
      // frase en curso.
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
        // Con la velocidad elegida: con la voz lenta, a la frase le falta
        // más de lo que diría la cuenta al 100 %.
        final restanteMs = desde == null
            ? 0
            : duracionEstimada(_ultimaInstruccion).inMilliseconds -
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

  /// Duración estimada del habla con la voz al 100 % (a velocidad 0.48 el
  /// motor anda por los 70-90 ms por carácter). Ver [duracionEstimada].
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

  // ═══ SIN MICRÓFONO ═══
  // Si el reconocedor no se pudo inicializar (permiso de micrófono negado, o
  // el teléfono no tiene servicio de reconocimiento), hay que decir que el
  // problema es el micrófono y volver a probar si el permiso se da después.
  // Con un error genérico, la pantalla contestaría "No te escuché. Intentá de
  // nuevo." a cada toque, para siempre.

  /// Motivo con el que termina (por onError) una escucha que no pudo ni
  /// empezar porque no hay reconocedor. Quien escucha dice
  /// [avisoSinMicrofono].
  static const String errorNoDisponible = 'no disponible';

  // El micrófono también puede estar desactivado en el teléfono (el botón
  // "Acceso al micrófono" del panel rápido, Android 12 o más). Ahí el
  // permiso sigue dado y el reconocedor arranca, pero recibe silencio: la
  // app decía "No te escuché" y nunca que el micrófono estaba desactivado,
  // ni Android preguntaba si activarlo (ver MainActivity.kt).

  /// El micrófono está desactivado en el teléfono, según la última vez que
  /// se miró ([microfonoDisponible]).
  bool _microfonoBloqueado = false;
  bool get microfonoBloqueado => _microfonoBloqueado;

  /// Lo que se dice cuando no se puede usar el micrófono: por qué, y qué se
  /// puede hacer.
  String get avisoSinMicrofono => _microfonoBloqueado
      ? 'El micrófono del teléfono está desactivado. Activalo y tocá de '
          'nuevo para hablar, o elegí el destino de la lista.'
      : 'No puedo usar el micrófono. Revisá el permiso en los ajustes del '
          'teléfono, o elegí el destino de la lista.';

  /// Dice [avisoSinMicrofono] y, si el micrófono está desactivado en el
  /// teléfono, hace que Android pregunte si se lo activa. Después de la
  /// frase, para que no se pise con TalkBack leyendo el aviso del sistema.
  Future<void> avisarSinMicrofono() async {
    await hablar(avisoSinMicrofono);
    if (_microfonoBloqueado) {
      await ReconocimientoEnTelefono.pedirDesbloquearMicrofono();
    }
  }

  /// Si se puede escuchar. Si el reconocedor no estaba disponible lo vuelve
  /// a inicializar: el permiso pudo haberse dado después (y si todavía se
  /// puede pedir, Android lo vuelve a preguntar). Con el reconocedor listo,
  /// mira si el micrófono está desactivado en el teléfono.
  Future<bool> microfonoDisponible() async {
    if (!_sttDisponible) await _inicializarSTT();
    if (!_sttDisponible) {
      _microfonoBloqueado = false;
      return false;
    }
    _microfonoBloqueado = await ReconocimientoEnTelefono.microfonoBloqueado();
    if (_microfonoBloqueado) {
      debugPrint('[Voz] El micrófono está desactivado en el teléfono.');
    }
    return !_microfonoBloqueado;
  }
 
  /// Locale de español del reconocedor, averiguado UNA vez.
  ///
  /// POR QUÉ: en Android es una consulta de ida y vuelta al servicio de voz
  /// que puede tardar cientos de milisegundos. Hecha en cada escucha, con el
  /// micrófono todavía cerrado y la pantalla ya diciendo "Escuchando", quien
  /// contesta enseguida ("sí", "no", "bar") hablaría en ese hueco y la
  /// palabra se perdería entera.
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
      // Cualquier locale que empiece con "es". Si no hay ninguno, null: el
      // reconocedor usa el idioma del sistema (no el primero de la lista,
      // que puede ser cualquier idioma).
      for (final l in locales) {
        if (l.localeId.startsWith('es')) return l.localeId;
      }
      return null;
    } catch (_) {
      return null; // Deja que el sistema elija
    }
  }
 
  // ─── ESCUCHA: una sesión, un aviso ──────────────────────────────────────────
  //
  // Cada llamada a [escuchar] es una SESIÓN y termina exactamente una vez,
  // avisando por onResultado o por onError. Se cierra con lo primero que
  // pase: un resultado final, un error del motor, el aviso de "terminé" sin
  // resultado, que alguien la corte, o el timeout. Todo lo que llega después
  // se ignora. Hace falta porque:
  //
  //  • Cuando el usuario no dice nada, o no se le entiende, el motor avisa
  //    con un ERROR (no con un resultado), y ese error llega al listener
  //    global de initialize(), no al que preguntó. Sin la sesión, quien
  //    preguntó algo ("¿Vamos ahí?") se quedaría esperando para siempre.
  //  • El timeout de una escucha vieja no puede cortar una escucha NUEVA:
  //    cada uno mira su propia sesión, no una bandera global.

  // ═══ CUÁNDO TERMINÓ DE HABLAR: LO DECIDE LA APP ═══
  // Medido en el teléfono: para decir "casa", el texto llegaba 5,3 s después
  // de abrirse el micrófono (la ruta, en 7 ms). El fin de lo dicho lo
  // marcaba el plugin, que tiene una sola espera (pauseFor) para el silencio
  // hasta que la persona EMPIEZA a hablar y para el silencio con el que se da
  // por TERMINADO lo que dijo. Después de cortar, además, espera el texto
  // final de Android, y si no llega, 2 s más antes de usar el último parcial.
  //
  // Por eso el plugin sólo se queda con la espera para empezar
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
  // ejecución y se avisa; mientras tanto, por internet. No se averigua
  // abriendo el micrófono y esperando el error (en un Pixel da
  // error_language_unavailable): el cambio a internet deja el micrófono
  // cerrado ~0,4 s, en los que se pierde la palabra de quien contesta
  // enseguida. Ese paso a internet ([escuchar]) queda como resguardo, por si
  // el teléfono dice que lo tiene y después no arranca.
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
    // Sin reconocedor no es un problema de conexión: eso lo dice
    // [microfonoDisponible] (y, si no, escuchar() con [errorNoDisponible]).
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
  /// no dijo nada o no se entendió, [errorCancelado] si se la cortó,
  /// [errorSinConexion] si no hay cómo entender la voz sin internet,
  /// [errorNoDisponible] si no se puede usar el micrófono).
  ///
  /// Si ya había una escucha abierta, se la corta (su dueño recibe
  /// [errorCancelado]) y arranca esta.
  ///
  /// [entiende]: el reconocedor devuelve hasta 10 interpretaciones, de la más
  /// a la menos probable, y con palabras cortas la correcta muchas veces no
  /// es la primera ("sí" sale "c", "no" sale "nos"). Si se pasa, se entrega
  /// la primera interpretación que [entiende] da por buena (recibe el texto
  /// en minúsculas); si ninguna, la más probable.
  ///
  /// [pregunta]: lo que se le pregunta a la persona antes de escucharla. La
  /// dice esta misma función, que pide el reconocedor mientras todavía suena
  /// (ver "PREGUNTAR Y ESCUCHAR SIN HUECO"). [onEscuchando] avisa recién
  /// cuando se pide el reconocedor.
  Future<void> escuchar({
    required void Function(String texto) onResultado,
    void Function(String error)? onError,
    void Function(bool activo)? onEscuchando,
    bool Function(String texto)? entiende,
    String? pregunta,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!await microfonoDisponible()) {
      onError?.call(errorNoDisponible);
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
        _soltarMicrofonoAuricular();
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

    // Sin pausas: lo que tarda el reconocedor en arrancar ya alcanza para que
    // quien contesta enseguida hable con el micrófono todavía cerrado (ver
    // "PREGUNTAR Y ESCUCHAR SIN HUECO"). Sin pregunta, el que llama esperó a
    // que terminara su frase, y el reconocedor se pide enseguida.
    _escuchando = true;
    if (pregunta == null) onEscuchando?.call(true);
    final reloj = Stopwatch()..start();
    bool microfonoAbierto = false;
    // En ms del reloj: cuándo se pidió el reconocedor, cuándo empezó a
    // grabar y cuándo terminó la pregunta (para el log del hueco).
    var reconocedorPedido = 0;
    int? grabandoDesde;
    int? finPregunta;
    var huecoInformado = false;
    void informarHueco() {
      final grabando = grabandoDesde, fin = finPregunta;
      if (huecoInformado || grabando == null || fin == null) return;
      huecoInformado = true;
      debugPrint('[Voz] El micrófono empezó a grabar ${grabando - fin} ms '
          'después del fin de la pregunta.');
    }

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
      reconocedorPedido = reloj.elapsedMilliseconds;
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
            final ahora = reloj.elapsedMilliseconds;
            final arranque = ahora - reconocedorPedido;
            _anotarArranque(enTelefono, arranque);
            grabandoDesde = ahora;
            debugPrint(
              '[Voz] Micrófono abierto a los $ahora ms: el reconocedor '
              'tardó $arranque ms en arrancar '
              '(${enTelefono ? 'en el teléfono' : 'por internet'}).',
            );
            informarHueco();
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

    // Con un auricular Bluetooth, su micrófono (ver "MICRÓFONO DEL
    // AURICULAR"). Se espera a que el canal quede abierto antes de arrancar
    // el reconocedor (si no, lo primero que dice la persona se grabaría con
    // el micrófono del teléfono) y antes de la pregunta (ver "PREGUNTAR Y
    // ESCUCHAR SIN HUECO"). Sin auricular responde enseguida.
    final conAuricular = await ReconocimientoEnTelefono.usarMicrofonoAuricular();
    if (conAuricular) {
      // La sesión se cerró mientras se abría el canal (la cortaron).
      if (cerrada || sesion != _sesionEscucha) {
        unawaited(ReconocimientoEnTelefono.soltarMicrofonoAuricular());
        return;
      }
      _microfonoAuricular = true;
      // Con el canal de voz abierto, la pregunta sale por él: no hay que
      // esperar la vuelta a la música de una escucha anterior.
      _auricularSoltadoEn = null;
      debugPrint('[Voz] ${reloj.elapsedMilliseconds} ms: micrófono del '
          'auricular abierto.');
    } else {
      debugPrint('[Voz] ${reloj.elapsedMilliseconds} ms: sin micrófono del '
          'auricular, se escucha con el del teléfono.');
    }
    if (cerrada) return;

    // La pregunta, con el reconocedor pedido mientras todavía suena (ver
    // "PREGUNTAR Y ESCUCHAR SIN HUECO").
    if (pregunta != null) {
      final pedirA = _pedirReconocedorA(pregunta, enTelefono);
      final clave = _clavePregunta(pregunta);
      final dicha = Stopwatch();
      final empezo = Completer<void>();
      final frase = _decir(pregunta, alEmpezar: () {
        dicha.start();
        empezo.complete();
      });
      final termino = frase.then((entera) {
        if (entera) {
          _anotar(
            _duracionPreguntas.putIfAbsent(clave, () => []),
            dicha.elapsedMilliseconds,
          );
        }
        finPregunta = reloj.elapsedMilliseconds;
        informarHueco();
      });
      await Future.any([empezo.future, termino]);
      if (pedirA != null && empezo.isCompleted) {
        final falta = pedirA - dicha.elapsedMilliseconds;
        debugPrint('[Voz] ${reloj.elapsedMilliseconds} ms: "$pregunta"; el '
            'reconocedor se pide a los $pedirA ms de empezar a decirla.');
        await Future.any([
          termino,
          Future<void>.delayed(Duration(milliseconds: math.max(0, falta))),
        ]);
      } else {
        await termino;
      }
      if (cerrada || sesion != _sesionEscucha) return;
      onEscuchando?.call(true);
    }

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