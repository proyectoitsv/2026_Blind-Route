import 'package:blindroute/design/design.dart';
import 'package:blindroute/modo_automatico.dart';
import 'package:blindroute/pantalla_ajustes.dart';
import 'package:blindroute/pantalla_mapas_online.dart';
import 'package:blindroute/pantalla_princ_usuario.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// INICIO DE LA APP DEL USUARIO (fase 5.1 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// La pantalla migrada al sistema de diseño: el botón grande que llena el
// lugar libre, las dos filas, lo que dice TalkBack y en qué orden, las guías
// de área táctil, etiquetas y contraste, la letra al 200 % y adónde lleva
// cada cosa (cortando la voz antes). Va con el MaterialApp de la app, con el
// tema de antes, como en main_user.dart.
//
// ─── Inter de verdad ───
// La letra de prueba de Flutter (cada letra, un cuadrado de 1 em) es mucho
// más ancha que Inter: con ella, al 200 % casi cualquier palabra larga se
// partiría. Acá se carga Inter, con los mismos archivos de la app, para
// medir como en el teléfono que ninguna palabra se parta.
//
// ─── Lo que no anda en los tests ───
// La voz se simula sobre el canal de flutter_tts: se anota lo que se le pide.
// ModoAutomatico arranca el Bluetooth y PantallaMapasOnline consulta la nube
// y la base local: de esas dos se mira qué ruta se abre y se saca antes de
// que se arme.

const MethodChannel _canalVoz = MethodChannel('flutter_tts');

/// Un teléfono de 360 × 780 dp.
const Size _telefono = Size(360, 780);

/// Anota las rutas que se abren.
class _Observador extends NavigatorObserver {
  final List<Route<dynamic>> abiertas = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      abiertas.add(route);
}

/// Carga Inter con sus cuatro pesos, desde los archivos de la app.
Future<void> _cargarInter() async {
  final familia = FontLoader(TipografiaApp.familia);
  for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    familia.addFont(rootBundle.load('assets/fonts/Inter/Inter-$peso.ttf'));
  }
  await familia.load();
}

/// Arma el inicio como en la app, con la letra en [escala].
Future<_Observador> _armar(WidgetTester tester, {double escala = 1}) async {
  tester.view.physicalSize = _telefono * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final observador = _Observador();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(primarySwatch: Colors.indigo),
      navigatorObservers: [observador],
      home: const PantallaPrincipalUsuario(),
    ),
  );
  await tester.pumpAndSettle();
  return observador;
}

/// Los textos de la pantalla.
Iterable<RenderParagraph> _parrafos(WidgetTester tester) =>
    tester.renderObjectList<RenderParagraph>(find.byType(RichText));

/// Las palabras que quedaron partidas en dos renglones.
List<String> _palabrasPartidas(WidgetTester tester) => [
  for (final parrafo in _parrafos(tester))
    for (final palabra in RegExp(r'\S+').allMatches(parrafo.text.toPlainText()))
      if (parrafo
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: palabra.start,
                  extentOffset: palabra.end,
                ),
              )
              .map((caja) => caja.top.round())
              .toSet()
              .length >
          1)
        palabra.group(0)!,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Lo que se le pidió al motor de voz, por nombre de método.
  final llamadasVoz = <String>[];

  setUpAll(_cargarInter);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AjustesMovimiento.instancia.reiniciarParaTests();
    llamadasVoz.clear();
    mensajero.setMockMethodCallHandler(_canalVoz, (llamada) async {
      llamadasVoz.add(llamada.method);
      return 1;
    });
  });

  tearDown(() => mensajero.setMockMethodCallHandler(_canalVoz, null));

  testWidgets('al abrirse inicializa la voz; el botón grande llena el lugar '
      'libre y las filas van abajo', (tester) async {
    await _armar(tester);
    // inicializar() fija el idioma de la voz.
    expect(llamadasVoz, contains('setLanguage'));
    // Un solo botón principal: el grande.
    expect(find.byType(BotonPrincipalGrande), findsOneWidget);
    expect(find.byType(BotonPrincipal), findsNothing);
    expect(find.byType(FilaGrupo), findsNWidgets(2));
    // No queda lugar libre: el grupo va abajo, con su margen, y el botón
    // grande ocupa todo lo demás.
    final grupo = tester.getRect(find.byType(GrupoFilas));
    final boton = tester.getRect(find.byType(BotonPrincipalGrande));
    expect(
      grupo.bottom,
      moreOrLessEquals(_telefono.height - EspaciadoApp.entreSecciones),
    );
    expect(
      grupo.top - boton.bottom,
      moreOrLessEquals(EspaciadoApp.entreSecciones),
    );
    expect(boton.height, greaterThan(_telefono.height / 2));
    // Con la letra normal entra todo, sin desplazarse.
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      0,
    );
    // Es la primera pantalla: sin botón para volver.
    expect(find.byTooltip('Volver'), findsNothing);
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
    expect(
      tester.semantics
          .simulatedAccessibilityTraversal()
          .map((nodo) => nodo.label)
          .where((etiqueta) => etiqueta.isNotEmpty)
          .toList(),
      [
        'Blind Route',
        'Navegación interior para todos',
        'Comenzar a navegar',
        'Mapas disponibles para descargar',
        'Ajustes: voz, movimiento y vibración',
      ],
    );
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
    expect(_palabrasPartidas(tester), isEmpty);
    expect(_parrafos(tester).where((p) => p.didExceedMaxLines), isEmpty);
    // No entra todo: la pantalla se desplaza y el botón grande mide lo que
    // pide su contenido, sin achicarse.
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
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(llamadasVoz, contains('stop'));
    expect(observador.abiertas.last, isA<RutaApp<void>>());
    expect(find.byType(PantallaAjustes), findsOneWidget);

    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(PantallaAjustes), findsNothing);
    expect(find.byType(BotonPrincipalGrande), findsOneWidget);
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
      expect(find.byType(BotonPrincipalGrande), findsOneWidget);
    });
  }
}
