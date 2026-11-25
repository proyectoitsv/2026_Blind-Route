// MICRÓFONO DEL AURICULAR
//
// Con un auricular Bluetooth, la escucha le pide a Android su micrófono antes
// de arrancar el reconocedor y lo suelta al terminar (ver voz_service.dart y
// MainActivity.kt); la frase que sigue, también una indicación de la guía,
// espera a que el auricular vuelva a la música. Con una pregunta, el canal
// se abre antes de decirla y el
// reconocedor se pide mientras todavía suena ("PREGUNTAR Y ESCUCHAR SIN
// HUECO"). Se simulan los canales del motor de voz, del reconocedor y del
// código de Android de la app, y se anota en qué orden se los llama.
// Que el canal del auricular de verdad se abra no se puede probar acá: eso
// se prueba en el teléfono.

import 'dart:async';

import 'package:blindroute/reconocimiento_telefono.dart';
import 'package:blindroute/voz_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _canalVoz = MethodChannel('flutter_tts');
const _canalEscucha = MethodChannel('plugin.csdcorp.com/speech_to_text');
const _canalApp = MethodChannel('blindroute/reconocimiento');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Los métodos que se llamaron, de los dos canales, en orden.
  final llamadas = <String>[];
  Map<Object?, Object?>? argumentosInicio;

  /// Lo que contesta Android al pedir el micrófono del auricular. Si hay
  /// [respuestaAuricular], contesta cuando el test la completa.
  var hayAuricular = true;
  Completer<bool>? respuestaAuricular;

  final voz = VozService();

  Future<void> esperar() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  int veces(String metodo) => llamadas.where((l) => l == metodo).length;

  /// El reconocedor simulado.
  Future<Object?> atenderEscucha(MethodCall llamada) async {
    llamadas.add(llamada.method);
    switch (llamada.method) {
      case 'initialize':
        argumentosInicio = llamada.arguments as Map<Object?, Object?>?;
        return true;
      case 'has_permission':
      case 'listen':
        return true;
      case 'locales':
        return <Object>[];
    }
    return null;
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    mensajero.setMockMethodCallHandler(_canalVoz, (_) async => 1);
    mensajero.setMockMethodCallHandler(_canalEscucha, atenderEscucha);
    mensajero.setMockMethodCallHandler(_canalApp, (llamada) async {
      llamadas.add(llamada.method);
      switch (llamada.method) {
        case 'usarMicrofonoAuricular':
          return respuestaAuricular?.future ?? hayAuricular;
        case 'microfonoBloqueado':
          return false;
        case 'hayConexion':
          return true;
        case 'consultarIdiomas':
          return {'disponible': false};
      }
      return null;
    });
    await voz.inicializar();
  });

  setUp(() async {
    // Corta lo que haya quedado del test anterior, canal de voz incluido.
    voz.limpiar();
    await esperar();
    hayAuricular = true;
    respuestaAuricular = null;
    llamadas.clear();
  });

  test('el plugin de voz no usa su propia forma de abrir el auricular', () {
    expect(argumentosInicio?['noBluetooth'], isTrue);
  });

  test('con auricular: su micrófono se abre antes de arrancar el reconocedor '
      'y se suelta una vez, al cerrar la escucha', () async {
    final errores = <String>[];
    await voz.escuchar(
      onResultado: (_) {},
      onError: errores.add,
      timeout: const Duration(seconds: 1),
    );
    expect(llamadas, containsAllInOrder(['usarMicrofonoAuricular', 'listen']));
    expect(veces('soltarMicrofonoAuricular'), 0);
    await voz.detenerEscucha();
    await esperar();
    expect(
      llamadas,
      containsAllInOrder(['listen', 'soltarMicrofonoAuricular']),
    );
    expect(veces('soltarMicrofonoAuricular'), 1);
    expect(errores, [VozService.errorCancelado]);
    // Cortarla otra vez no suelta de nuevo.
    await voz.detenerEscucha();
    await esperar();
    expect(veces('soltarMicrofonoAuricular'), 1);
  });

  test('sin auricular: se escucha igual y no hay nada que soltar', () async {
    hayAuricular = false;
    await voz.escuchar(
      onResultado: (_) {},
      onError: (_) {},
      timeout: const Duration(seconds: 1),
    );
    expect(llamadas, containsAllInOrder(['usarMicrofonoAuricular', 'listen']));
    await voz.detenerEscucha();
    await esperar();
    expect(veces('soltarMicrofonoAuricular'), 0);
  });

  test('si la escucha se corta mientras se abre el canal, el reconocedor no '
      'arranca y el canal se suelta', () async {
    respuestaAuricular = Completer<bool>();
    final errores = <String>[];
    final escucha = voz.escuchar(
      onResultado: (_) {},
      onError: errores.add,
      timeout: const Duration(seconds: 1),
    );
    await esperar();
    expect(llamadas, contains('usarMicrofonoAuricular'));
    await voz.detenerEscucha();
    respuestaAuricular!.complete(true);
    await escucha;
    await esperar();
    expect(llamadas, isNot(contains('listen')));
    expect(veces('soltarMicrofonoAuricular'), 1);
    expect(errores, [VozService.errorCancelado]);
  });

  test('la frase que sigue a la escucha, también una indicación de la guía, '
      'espera a que el auricular vuelva a la música; sin auricular, sale '
      'enseguida', () async {
    final dichas = <(String, int)>[];
    final reloj = Stopwatch()..start();
    mensajero.setMockMethodCallHandler(_canalVoz, (llamada) async {
      if (llamada.method == 'speak') {
        dichas.add((llamada.arguments as String, reloj.elapsedMilliseconds));
      }
      return 1;
    });
    addTearDown(
      () => mensajero.setMockMethodCallHandler(_canalVoz, (_) async => 1),
    );
    Future<int> escucharYSoltar() async {
      await voz.escuchar(
        onResultado: (_) {},
        onError: (_) {},
        timeout: const Duration(seconds: 1),
      );
      await voz.detenerEscucha();
      return reloj.elapsedMilliseconds;
    }

    var soltado = await escucharYSoltar();
    unawaited(voz.hablar('Calculando ruta.'));
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(dichas.map((d) => d.$1), ['Calculando ruta.']);
    expect(dichas.single.$2 - soltado, greaterThanOrEqualTo(900));

    // Una indicación de la guía (hablarSinEsperar) también espera. (El motor
    // simulado no avisa que terminó: se lo para, para que la frase nueva no
    // espere el corte de la vieja.)
    await voz.detener();
    await esperar();
    dichas.clear();
    soltado = await escucharYSoltar();
    expect(voz.hablarSinEsperar('Girá a la izquierda.'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(dichas.map((d) => d.$1), ['Girá a la izquierda.']);
    expect(dichas.single.$2 - soltado, greaterThanOrEqualTo(900));

    // Sin auricular no hay espera. (El motor simulado no avisa que terminó:
    // se lo para, para que la frase nueva no espere el corte de la vieja.)
    await voz.detener();
    await esperar();
    hayAuricular = false;
    dichas.clear();
    await voz.escuchar(
      onResultado: (_) {},
      onError: (_) {},
      timeout: const Duration(seconds: 1),
    );
    await voz.detenerEscucha();
    // (pasó más de un segundo desde la vez anterior que se soltó)
    final ahora = reloj.elapsedMilliseconds;
    unawaited(voz.hablar('Seguí derecho.'));
    await esperar();
    await esperar();
    expect(dichas.map((d) => d.$1), ['Seguí derecho.']);
    expect(dichas.single.$2 - ahora, lessThan(300));
  });

  test('con una pregunta: el canal del auricular se abre antes de decirla; la '
      'primera vez el reconocedor se pide al terminarla y, con lo que se '
      'midió, mientras todavía suena', () async {
    // El motor simulado no avisa solo que terminó una frase: la del test
    // anterior sigue "sonando" y la pregunta esperaría su corte.
    await voz.detener();
    await esperar();
    llamadas.clear();
    const codec = StandardMethodCodec();
    final reloj = Stopwatch()..start();
    final momentos = <String, int>{};
    mensajero.setMockMethodCallHandler(_canalVoz, (llamada) async {
      if (llamada.method == 'speak') {
        llamadas.add('speak');
        momentos['speak'] = reloj.elapsedMilliseconds;
      }
      return 1;
    });
    mensajero.setMockMethodCallHandler(_canalEscucha, (llamada) {
      if (llamada.method == 'listen') {
        momentos['listen'] = reloj.elapsedMilliseconds;
      }
      return atenderEscucha(llamada);
    });
    addTearDown(() {
      mensajero.setMockMethodCallHandler(_canalVoz, (_) async => 1);
      mensajero.setMockMethodCallHandler(_canalEscucha, atenderEscucha);
    });
    // Lo que avisan los plugins desde Android.
    Future<void> avisar(String canal, String metodo, [Object? argumentos]) =>
        mensajero.handlePlatformMessage(
          canal,
          codec.encodeMethodCall(MethodCall(metodo, argumentos)),
          (_) {},
        );
    Future<void> terminarPregunta() => avisar('flutter_tts', 'speak.onComplete');
    // El reconocedor empieza a grabar: llega el primer nivel de sonido.
    Future<void> empezarAGrabar() async {
      await avisar(_canalEscucha.name, 'notifyStatus', 'listening');
      await avisar(_canalEscucha.name, 'soundLevelChange', 1.0);
    }

    // Primera vez: sin medidas, el reconocedor se pide al terminar.
    var preguntas = 0;
    unawaited(voz.escuchar(
      pregunta: '¿A dónde vas?',
      onResultado: (_) {},
      onError: (_) {},
      onEscuchando: (activo) {
        if (activo) preguntas++;
      },
      timeout: const Duration(seconds: 1),
    ));
    await esperar();
    expect(llamadas, containsAllInOrder(['usarMicrofonoAuricular', 'speak']));
    expect(llamadas, isNot(contains('listen')));
    expect(preguntas, 0, reason: 'todavía no se escucha');
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    await terminarPregunta();
    await esperar();
    expect(llamadas, contains('listen'));
    expect(preguntas, 1);
    // El reconocedor tarda 0,8 s en arrancar.
    final pedido = momentos['listen']!;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await empezarAGrabar();
    expect(reloj.elapsedMilliseconds - pedido, greaterThanOrEqualTo(800));
    await voz.detenerEscucha();
    await esperar();

    // Segunda vez: la pregunta duró ~1 s y el reconocedor tarda ~0,8 s; para
    // que empiece a grabar 0,4 s después del fin, se lo pide ~0,6 s después
    // de empezar a decirla. Esta vez la pregunta dura menos (~0,8 s).
    Future<int> preguntarOtraVez(int duraMs) async {
      llamadas.clear();
      momentos.clear();
      unawaited(voz.escuchar(
        pregunta: '¿A dónde vas?',
        onResultado: (_) {},
        onError: (_) {},
        timeout: const Duration(seconds: 1),
      ));
      await Future<void>.delayed(Duration(milliseconds: duraMs));
      expect(llamadas, containsAllInOrder(['usarMicrofonoAuricular', 'speak']));
      expect(llamadas, contains('listen'),
          reason: 'se pide con la pregunta sonando');
      final pedidoA = momentos['listen']! - momentos['speak']!;
      await terminarPregunta();
      await voz.detenerEscucha();
      await esperar();
      return pedidoA;
    }

    expect(await preguntarOtraVez(800), inInclusiveRange(450, 800));
    // Tercera vez: vale lo más que duró la pregunta (~1 s), no la última
    // (~0,8 s), así que se lo sigue pidiendo a ~0,6 s y no a ~0,4 s.
    expect(await preguntarOtraVez(950), inInclusiveRange(500, 950));
  });

  test('si Android no contesta, se escucha con el teléfono y se pide soltar '
      'el canal por si se abre después', () async {
    respuestaAuricular = Completer<bool>();
    final abierto = await ReconocimientoEnTelefono.usarMicrofonoAuricular();
    await esperar();
    expect(abierto, isFalse);
    expect(veces('soltarMicrofonoAuricular'), 1);
  });
}
