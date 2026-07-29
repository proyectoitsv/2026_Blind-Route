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
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _escuchando = false;
          }
        },
      );
    } catch (e) {
      _sttDisponible = false;
    }
  }
 
  // ─── TTS: TEXT TO SPEECH ─────────────────────────────────────────────────────
 
  /// Habla el texto y espera a que el motor TTS confirme que terminó.
  /// Usa un Completer conectado al callback onCompletionHandler del motor,
  /// con un timeout de seguridad basado en la longitud del texto.
  Future<void> hablar(String texto) async {
    if (!_ttsInicializado || texto.trim().isEmpty) return;
    await _tts.stop();
    _hablando = true;

    final completer = Completer<void>();

    void completar() {
      _hablando = false;
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
        .timeout(Duration(milliseconds: timeoutMs), onTimeout: () {
      _hablando = false;
    });
  }
 
  /// Habla sin esperar — para instrucciones de navegación que se actualizan
  /// continuamente y no deben bloquear el widget tree.
  /// Si el motor ya está reproduciendo audio, descarta silenciosamente el
  /// nuevo texto para no interrumpir la locución en curso.
  void hablarSinEsperar(String texto) {
    if (!_ttsInicializado || texto.trim().isEmpty) return;
    // No interrumpir si ya se está hablando
    if (_hablando) return;
    _hablando = true;
    _tts.setCompletionHandler(() => _hablando = false);
    _tts.setCancelHandler(() => _hablando = false);
    _tts.setErrorHandler((_) => _hablando = false);
    _tts.speak(texto);
    _ultimaVezHablado = DateTime.now();
    _ultimaInstruccion = texto;
  }
 
  // Filtro de estabilidad: la instrucción debe repetirse N veces
  // consecutivas antes de hablarse, descartando flickers de heading/posición.
  String _instruccionCandidata = '';
  int _contadorConfirmaciones = 0;
  static const int _confirmacionesNecesarias = 4;

  Future<void> hablarSiCambio(String texto) async {
    if (!_ttsInicializado || texto.trim().isEmpty) return;
    final ahora = DateTime.now();

    // \u2500\u2500 Filtro de estabilidad \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    // Si el texto cambió, reiniciar contador y esperar confirmaciones.
    if (texto != _instruccionCandidata) {
      _instruccionCandidata = texto;
      _contadorConfirmaciones = 1;
      return;
    }
    _contadorConfirmaciones++;
    if (_contadorConfirmaciones < _confirmacionesNecesarias) return;

    // \u2500\u2500 Filtro de tiempo \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    // Aunque la instrucción sea estable, respetar el intervalo mínimo,
    // salvo que sea distinta a la última hablada (nueva instrucción real).
    final instruccionIgual = texto == _ultimaInstruccion;
    final tiempoSuficiente = _ultimaVezHablado == null ||
        ahora.difference(_ultimaVezHablado!) > _intervaloMinimo;

    if (!instruccionIgual || tiempoSuficiente) {
      hablarSinEsperar(texto);
    }
  }
 
  Future<void> detener() async {
    await _tts.stop();
    _hablando = false;
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
 
  /// Escucha una frase del usuario y la devuelve via [onResultado].
  /// Solo dispara el callback cuando el motor marca el resultado como final
  /// (flag finalResult = true), lo que garantiza que el usuario terminó de
  /// hablar. Los resultados parciales con texto vacío que llegan al arrancar
  /// se descartan silenciosamente.
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
    if (_escuchando) {
      await detenerEscucha();
      return;
    }
 
    // Pequeña pausa para que el altavoz se silencie antes de abrir el micrófono
    await Future.delayed(const Duration(milliseconds: 200));
 
    _escuchando = true;
    onEscuchando?.call(true);
 
    bool resultadoEntregado = false;
 
    // Resolver locale de español disponible en el dispositivo
    final localeId = await _resolverLocaleEspanol();
 
    try {
      await _stt.listen(
        localeId: localeId,
        listenFor: timeout,
        // pauseFor: tiempo de silencio antes de considerar que terminó de hablar.
        // 3 segundos da margen suficiente sin hacer esperar demasiado.
        pauseFor: const Duration(seconds: 3),
        // Activamos parciales solo para que el motor quede "vivo",
        // pero SOLO procesamos el resultado cuando finalResult == true.
        listenOptions: stt.SpeechListenOptions(partialResults: true),
        onResult: (result) {
          // Ignorar resultados parciales — solo nos interesa el resultado final.
          if (!result.finalResult) return;
 
          // Descartar si no hay texto reconocido.
          final texto = result.recognizedWords.trim();
          if (texto.isEmpty) {
            _escuchando = false;
            onEscuchando?.call(false);
            onError?.call('sin texto');
            return;
          }
 
          if (!resultadoEntregado) {
            resultadoEntregado = true;
            _escuchando = false;
            onEscuchando?.call(false);
            onResultado(texto.toLowerCase());
          }
        },
      );
 
      // Timeout de seguridad: si el motor nunca dispara finalResult
      // (puede pasar en algunos dispositivos), informar al caller.
      // Solo se activa si aún no se entregó ningún resultado.
      Future.delayed(timeout + const Duration(seconds: 3), () {
        if (!resultadoEntregado && _escuchando) {
          _escuchando = false;
          onEscuchando?.call(false);
          onError?.call('sin texto');
        }
      });
    } catch (e) {
      _escuchando = false;
      onEscuchando?.call(false);
      if (!resultadoEntregado) {
        onError?.call('Error: $e');
      }
    }
  }
 
  Future<void> detenerEscucha() async {
    if (_escuchando) {
      await _stt.stop();
      _escuchando = false;
    }
  }
 
  /// Detiene TTS y STT. Si se pasa [dueno], la limpieza se ignora cuando ese
  /// objeto ya no es la pantalla de voz activa (ver [_dueno]).
  void limpiar({Object? dueno}) {
    if (dueno != null && !esDueno(dueno)) return;
    _dueno = null;
    _tts.stop();
    _hablando = false;
    _stt.stop();
    _escuchando = false;
  }
}