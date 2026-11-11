import 'dart:math' as math;

import 'package:blindroute/design/design.dart';
import 'package:blindroute/modo_automatico.dart';
import 'package:blindroute/pantalla_ajustes.dart';
import 'package:blindroute/pantalla_mapas_online.dart';
import 'package:blindroute/pantalla_princ_usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ayudas_pantallas.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INICIO DE LA APP DEL USUARIO (fase 5.1 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// La pantalla migrada al sistema de diseño: el botón con pulso que ocupa la
// primera vista, las dos filas debajo (a la vista desplazando), lo que dice TalkBack y en qué orden, las guías
// de área táctil, etiquetas y contraste, la letra al 200 % (con Inter de
// verdad, ayudas_pantallas.dart) y adónde lleva cada cosa (cortando la voz
// antes). Va con el MaterialApp de la app, con el tema de antes, como en
// main_user.dart.
//
// ─── Lo que no anda en los tests ───
// La voz se simula sobre el canal de flutter_tts: se anota lo que se le pide.
// ModoAutomatico arranca el Bluetooth y PantallaMapasOnline consulta la nube
// y la base local: de esas dos se mira qué ruta se abre y se saca antes de
// que se arme.
//
// Las ondas del botón se repiten sin parar: con ellas, pumpAndSettle no
// termina nunca. Los tests van con «Reducir movimiento» prendido, salvo el
// de las ondas, que lo apaga.

/// Arma el inicio como en la app, con la letra en [escala].
Future<ObservadorRutas> _armar(WidgetTester tester, {double escala = 1}) =>
    armarPantalla(tester, const PantallaPrincipalUsuario(), escala: escala);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Lo que se le pidió al motor de voz, por nombre de método.
  final llamadasVoz = <String>[];

  setUpAll(cargarInter);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AjustesMovimiento.instancia.reiniciarParaTests();
    await AjustesMovimiento.instancia.cambiarReducirMovimiento(true);
    llamadasVoz.clear();
    mensajero.setMockMethodCallHandler(canalVoz, (llamada) async {
      llamadasVoz.add(llamada.method);
      return 1;
    });
  });

  tearDown(() => mensajero.setMockMethodCallHandler(canalVoz, null));

  testWidgets('al abrirse inicializa la voz; el botón con pulso ocupa la '
      'primera vista y las filas quedan debajo', (tester) async {
    await _armar(tester);
    // inicializar() fija el idioma de la voz.
    expect(llamadasVoz, contains('setLanguage'));
    // Un solo botón principal: el del pulso.
    expect(find.byType(BotonPulso), findsOneWidget);
    expect(find.byType(BotonPrincipalGrande), findsNothing);
    expect(find.byType(BotonPrincipal), findsNothing);
    // Las filas ya están armadas (TalkBack las encuentra), aunque no se vean.
    expect(find.byType(FilaGrupo, skipOffstage: false), findsNWidgets(2));
    // El círculo va en el medio, a lo ancho.
    final circulo = tester.getCenter(find.byType(BotonPulso));
    expect(circulo.dx, moreOrLessEquals(telefono.width / 2));
    // Las filas no se ven de entrada: empiezan debajo de la pantalla.
    final grupo = tester.getRect(find.byType(GrupoFilas, skipOffstage: false));
    expect(grupo.top, greaterThanOrEqualTo(telefono.height));
    final desplazable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(desplazable.position.maxScrollExtent, greaterThan(0));
    // Desplazando, aparecen enteras.
    await tester.scrollUntilVisible(find.text('Ajustes'), 200);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(GrupoFilas)).bottom,
      lessThanOrEqualTo(telefono.height),
    );
    // Es la primera pantalla: sin botón para volver.
    expect(find.byTooltip('Volver'), findsNothing);
  });

  testWidgets('las ondas se mueven sólo sin «Reducir movimiento» y se '
      'frenan con otra pantalla encima', (tester) async {
    // Lo guardado se escribe con el reloj de verdad: con el falso del test
    // no termina nunca.
    await tester.runAsync(
      () => AjustesMovimiento.instancia.cambiarReducirMovimiento(false),
    );
    final observador = await armarPantalla(
      tester,
      const PantallaPrincipalUsuario(),
      asentar: false,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    // Con Ajustes encima, el ticker se apaga y la pantalla se asienta.
    await tester.scrollUntilVisible(find.text('Ajustes'), 200);
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(observador.abiertas.last, isA<RutaApp<void>>());
    expect(tester.binding.hasScheduledFrame, isFalse);
    // Con «Reducir movimiento», al volver no se mueven.
    await tester.runAsync(
      () => AjustesMovimiento.instancia.cambiarReducirMovimiento(true),
    );
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(BotonPulso), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('toda la primera vista lleva a navegar: el círculo, sus '
      'costados, la frase de arriba y la pista de abajo', (tester) async {
    final observador = await _armar(tester);
    final circulo = tester.getCenter(find.byIcon(Icons.navigation_rounded));
    for (final lugar in [
      circulo,
      // A un costado del círculo, cerca del borde de la pantalla.
      Offset(24, circulo.dy),
      Offset(telefono.width - 24, circulo.dy + 120),
      tester.getCenter(find.text('Navegación interior para todos')),
      tester.getCenter(find.text('Mapas y ajustes')),
    ]) {
      final antes = observador.abiertas.length;
      await tester.tapAt(lugar);
      expect(observador.abiertas.length, antes + 1, reason: '$lugar');
      final ruta = observador.abiertas.last as RutaApp<void>;
      final contexto = tester.element(find.byType(PantallaPrincipalUsuario));
      expect(ruta.builder(contexto).runtimeType, ModoAutomatico);
      Navigator.of(contexto).removeRoute(ruta);
      await tester.pumpAndSettle();
    }
  });

  test('la flecha del círculo va y viene a los costados y se asienta', () {
    expect(BotonPulso.giroFlecha(0), 0);
    final giros = [
      for (var i = 0; i <= 100; i++) BotonPulso.giroFlecha(i / 100),
    ];
    // Va hacia los dos lados, sin pasar de 12°.
    expect(giros.reduce(math.max), greaterThan(0));
    expect(giros.reduce(math.min), lessThan(0));
    for (final g in giros) {
      expect(g.abs(), lessThanOrEqualTo(BotonPulso.vaivenFlecha));
    }
    // Al terminar el pulso está casi quieta: no salta al empezar el otro.
    expect(giros.last.abs(), lessThan(0.05 * BotonPulso.vaivenFlecha));
  });

  testWidgets('TalkBack: el título, la frase, el botón grande y las filas, en '
      'ese orden y con las etiquetas de siempre; 48 dp, etiquetas y '
      'contraste', (tester) async {
    final semantica = tester.ensureSemantics();
    await _armar(tester);
    expect(
      tester.getSemantics(find.text('Blind Route')),
      isSemantics(label: 'Blind Route', isHeader: true, namesRoute: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Comenzar a navegar')),
      isSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    // Las filas, a la vista desplazando.
    await tester.scrollUntilVisible(find.text('Ajustes'), 200);
    await tester.pumpAndSettle();
    for (final etiqueta in [
      'Mapas disponibles para descargar',
      'Ajustes: voz, movimiento y vibración',
    ]) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(etiqueta)),
        isSemantics(label: etiqueta, isButton: true, hasTapAction: true),
      );
    }
    // La aclaración del botón y los subtítulos son para quien ve: lo que
    // dicen ya está en las etiquetas.
    expect(find.bySemanticsLabel(RegExp('Tocá')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Descargá')), findsNothing);
    expect(ordenTalkBack(tester), [
      'Blind Route',
      'Navegación interior para todos',
      'Comenzar a navegar',
      'Mapas disponibles para descargar',
      'Ajustes: voz, movimiento y vibración',
    ]);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantica.dispose();
  });

  testWidgets('con la letra al 200 %: sin desbordes, nada cortado ni partido '
      'y todo al alcance desplazando', (tester) async {
    final semantica = tester.ensureSemantics();
    await _armar(tester, escala: 2);
    expect(tester.takeException(), isNull);
    expect(palabrasPartidas(tester), isEmpty);
    expect(textosCortados(tester), isEmpty);
    // No entra todo: la pantalla se desplaza.
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      greaterThan(0),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.scrollUntilVisible(find.text('Ajustes'), 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantica.dispose();
  });

  testWidgets('«Ajustes» corta la voz y abre Ajustes con la transición del '
      'sistema de diseño; al volver, el inicio sigue igual', (tester) async {
    final observador = await _armar(tester);
    llamadasVoz.clear();
    await tester.scrollUntilVisible(find.text('Ajustes'), 200);
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(llamadasVoz, contains('stop'));
    expect(observador.abiertas.last, isA<RutaApp<void>>());
    expect(find.byType(PantallaAjustes), findsOneWidget);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(PantallaAjustes), findsNothing);
    expect(find.byType(BotonPulso), findsOneWidget);
  });

  for (final (texto, pantalla) in const [
    ('Comenzar a navegar', ModoAutomatico),
    ('Mapas disponibles', PantallaMapasOnline),
  ]) {
    testWidgets('«$texto» corta la voz y abre $pantalla con RutaApp', (
      tester,
    ) async {
      final observador = await _armar(tester);
      llamadasVoz.clear();
      await tester.scrollUntilVisible(find.text(texto), 200);
      await tester.tap(find.text(texto));
      // El toque ya abrió la ruta, que se arma recién en el cuadro
      // siguiente: se mira qué pantalla abre y se saca antes.
      final ruta = observador.abiertas.last;
      expect(ruta, isA<RutaApp<void>>());
      final contexto = tester.element(find.byType(PantallaPrincipalUsuario));
      expect((ruta as RutaApp<void>).builder(contexto).runtimeType, pantalla);
      Navigator.of(contexto).removeRoute(ruta);
      await tester.pumpAndSettle();
      expect(llamadasVoz, contains('stop'));
      expect(find.byType(pantalla), findsNothing);
      expect(find.byType(BotonPulso), findsOneWidget);
    });
  }
}
