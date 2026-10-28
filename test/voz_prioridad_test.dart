import 'dart:async';

import 'package:blindroute/voz_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PRIORIDAD DE LAS INDICACIONES SOBRE LAS FRASES SECUNDARIAS
// ═══════════════════════════════════════════════════════════════════════════
//
// "Estás en <punto clave>" es una frase secundaria: sólo arranca con el
// motor libre y cualquier indicación la corta. El motor de voz se simula
// sobre el canal de flutter_tts: anota lo que se le manda a decir y, al
// pedirle que pare, avisa la cancelación como lo hace el de Android.

const _canal = MethodChannel('flutter_tts');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final dichas = <String>[];
  var sonando = false;

  Future<void> avisar(String metodo) => mensajero.handlePlatformMessage(
        _canal.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(metodo)),
        (_) {},
      );

  /// Deja correr los avisos del motor y el corte de la frase anterior.
  Future<void> esperar() => Future.delayed(const Duration(milliseconds: 50));

  final voz = VozService();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    mensajero.setMockMethodCallHandler(_canal, (call) async {
      switch (call.method) {
        case 'speak':
          dichas.add(call.arguments as String);
          sonando = true;
        case 'stop':
          if (sonando) {
            sonando = false;
            scheduleMicrotask(() => avisar('speak.onCancel'));
          }
      }
      return 1;
    });
    await voz.inicializar();
    expect(voz.ttsDisponible, isTrue);
  });

  setUp(() async {
    await voz.detener();
    await esperar();
    voz.reiniciarFiltroInstrucciones();
    dichas.clear();
  });

  test('con una indicación sonando, la secundaria no arranca', () {
    expect(voz.hablarSinEsperar('Seguí derecho, 5 metros'), isTrue);
    expect(voz.hablarSecundaria('Estás en la esquina.'), isFalse);
    expect(dichas, ['Seguí derecho, 5 metros']);
  });

  test('una indicación corta a la secundaria y se dice', () async {
    expect(voz.hablarSecundaria('Estás en la esquina.'), isTrue);
    expect(voz.hablarSinEsperar('Seguí derecho, 5 metros'), isTrue);
    await esperar();
    expect(dichas, ['Estás en la esquina.', 'Seguí derecho, 5 metros']);
  });

  test('el giro corta a la secundaria aunque le falte poco', () async {
    expect(voz.hablarSecundaria('Estás en la esquina.'), isTrue);
    expect(
      voz.hablarUrgente('Girá a la izquierda', clave: 'Girá a la izquierda'),
      isTrue,
    );
    await esperar();
    expect(dichas, ['Estás en la esquina.', 'Girá a la izquierda']);
  });

  test('una secundaria no corta a otra frase ni a otra secundaria', () async {
    expect(voz.hablarSecundaria('Estás en la esquina.'), isTrue);
    expect(voz.hablarSecundaria('Estás en el hall.'), isFalse);
    await esperar();
    expect(dichas, ['Estás en la esquina.']);
  });

  test('mientras arranca una frase de hablar(), no arranca una secundaria',
      () async {
    unawaited(voz.hablar('Llegaste a Baño.'));
    expect(voz.hablarSecundaria('Estás en la esquina.'), isFalse);
    await esperar();
    expect(dichas, ['Llegaste a Baño.']);
  });

  test('una indicación nueva confirmándose cuenta como cercana', () async {
    expect(voz.indicacionCerca(Duration.zero), isFalse);
    await voz.hablarSiCambio('Girá a la derecha', clave: 'Girá a la derecha');
    expect(voz.indicacionCerca(Duration.zero), isTrue);
  });

  test('la duración estimada sigue la velocidad elegida', () {
    // 20 caracteres a ~80 ms cada uno, con la velocidad al 100 %.
    expect(voz.duracionEstimada('Estás en la esquina.'),
        const Duration(milliseconds: 1600));
  });
}
