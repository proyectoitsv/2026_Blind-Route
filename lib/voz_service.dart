import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
 
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
  static const Duration _intervaloMinimo = Duration(seconds: 15);
 
  // ─── INICIALIZACIÓN ──────────────────────────────────────────────────────────
 
  Future<void> inicializar() async {
    await _inicializarTTS();
    await _inicializarSTT();
  }
 
  Future<void> _inicializarTTS() async {
    try {
      await _tts.setLanguage('es-AR');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
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
          // Silencio o "no se entendió" llegan por acá y no por onResult:
          // hay que avisarle a quien está escuchando (ver "una sesión, un
          // aviso" más abajo).
          _cerrarSesionTrasGracia('sin texto');
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
    } catch (e) {
      _sttDisponible = false;
    }
  }
 
  // ─── TTS: TEXT TO SPEECH ─────────────────────────────────────────────────────
 
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
    await _cortarFraseEnCurso();
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
  /// interrumpir la locución en curso.
  ///
  /// Devuelve `true` si el texto se mandó al motor y `false` si se descartó.
  /// El que llama TIENE que mirar ese resultado si necesita saber si la frase
  /// se dijo: antes este método era `void` y [hablarSiCambio] daba por dicha
  /// una indicación que en realidad se había descartado (ver el comentario
  /// ahí), que es lo que demoraba ~15 s la primera indicación de cada ruta.
  bool hablarSinEsperar(String texto) {
    if (!_ttsInicializado || texto.trim().isEmpty) return false;
    // No interrumpir si ya se está hablando
    if (_hablando) return false;
    _hablando = true;
    _tts.setCompletionHandler(() => _hablando = false);
    _tts.setCancelHandler(() => _hablando = false);
    _tts.setErrorHandler((_) => _hablando = false);
    _tts.speak(texto);
    _ultimaVezHablado = DateTime.now();
    _ultimaInstruccion = texto;
    return true;
  }
 
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
      final desde = _ultimaVezHablado;
      final restanteMs = desde == null
          ? 0
          : _ultimaInstruccion.length * _msPorCaracterEstimado -
              DateTime.now().difference(desde).inMilliseconds;
      if (restanteMs <= _esperaMaxUrgenteMs) return false;
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
    _liberarEspera();
  }
 
  bool get ttsDisponible => _ttsInicializado;
 
  // ─── STT: SPEECH TO TEXT ─────────────────────────────────────────────────────
 
  bool get sttDisponible => _sttDisponible;
  bool get escuchando => _escuchando;
 
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
  Future<void> escuchar({
    required void Function(String texto) onResultado,
    void Function(String error)? onError,
    void Function(bool activo)? onEscuchando,
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

    void cerrar({String? texto, String motivo = 'sin texto'}) {
      if (cerrada) return;
      cerrada = true;
      if (sesion == _sesionEscucha) {
        _escuchando = false;
        _cerrarSesion = null;
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

    // Pequeña pausa para que el altavoz se silencie antes de abrir el micrófono
    await Future.delayed(const Duration(milliseconds: 200));
    if (cerrada) return;

    _escuchando = true;
    onEscuchando?.call(true);

    // Resolver locale de español disponible en el dispositivo
    final localeId = await _resolverLocaleEspanol();
    if (cerrada) return;

    try {
      _motorPedido = true;
      await _stt.listen(
        localeId: localeId,
        listenFor: timeout,
        // pauseFor: tiempo de silencio antes de considerar que terminó de hablar.
        // 3 segundos da margen suficiente sin hacer esperar demasiado.
        pauseFor: const Duration(seconds: 3),
        // Los parciales mantienen "vivo" al motor; el pedido se resuelve con
        // el resultado FINAL (el usuario terminó de hablar).
        listenOptions: stt.SpeechListenOptions(partialResults: true),
        onResult: (result) {
          if (cerrada) return;
          final texto = result.recognizedWords.trim();
          if (!result.finalResult) {
            if (texto.isNotEmpty) parcial = texto;
            return;
          }
          if (texto.isEmpty) {
            cerrar(); // final vacío: vale el parcial si hubo, si no 'sin texto'
          } else {
            cerrar(texto: texto);
          }
        },
      );

      // Timeout de seguridad, por si el motor no avisa nada de nada. Cierra
      // SU sesión (si ya se cerró, no hace nada).
      Future.delayed(timeout + const Duration(seconds: 3), () => cerrar());
    } catch (e) {
      cerrar(motivo: 'Error: $e');
    }
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
    _liberarEspera();
    // La pantalla se va: la escucha en curso termina como cancelada, para
    // que nadie diga "no te escuché" sobre una pantalla que ya no está.
    _cerrarSesion?.call(errorCancelado);
    _stt.stop();
    _escuchando = false;
  }
}