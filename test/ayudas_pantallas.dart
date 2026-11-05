import 'package:blindroute/design/design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AYUDAS PARA LOS TESTS DE LAS PANTALLAS MIGRADAS (fase 5 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// Lo que comparten los tests de las pantallas: armarlas como en la app (con
// el MaterialApp de los entrypoints, que sigue con el tema de antes) en un
// teléfono de 360 × 780 dp y con la letra en la escala que se pida; Inter de
// verdad para medir; las palabras partidas; lo que dice TalkBack y en qué
// orden; y las rutas que se abren.
//
// ─── Inter de verdad ───
// La letra de prueba de Flutter (cada letra, un cuadrado de 1 em) es mucho
// más ancha que Inter: con ella, al 200 % casi cualquier palabra larga se
// partiría. Acá se carga Inter, con los mismos archivos de la app, para
// medir como en el teléfono que ninguna palabra se parta.
//
// No termina en _test.dart: flutter test no lo corre solo.

/// El canal de flutter_tts. Los tests de las pantallas que hablan lo
/// simulan.
const MethodChannel canalVoz = MethodChannel('flutter_tts');

/// Un teléfono de 360 × 780 dp.
const Size telefono = Size(360, 780);

/// Anota las rutas que se abren.
class ObservadorRutas extends NavigatorObserver {
  /// Todas, también las que se abren en lugar de otra.
  final List<Route<dynamic>> abiertas = [];

  /// Las que se abren en lugar de la pantalla (pushReplacement, como el
  /// login al entrar).
  final List<Route<dynamic>> reemplazantes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      abiertas.add(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) return;
    abiertas.add(newRoute);
    reemplazantes.add(newRoute);
  }
}

/// Carga Inter con sus cuatro pesos, desde los archivos de la app.
Future<void> cargarInter() async {
  final familia = FontLoader(TipografiaApp.familia);
  for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    familia.addFont(rootBundle.load('assets/fonts/Inter/Inter-$peso.ttf'));
  }
  await familia.load();
}

/// Arma [pantalla] como en la app (el MaterialApp de main_user.dart y de
/// main_admin.dart, con el tema de antes), en un teléfono de 360 × 780 dp y
/// con la letra en [escala]. Devuelve el observador de las rutas.
Future<ObservadorRutas> armarPantalla(
  WidgetTester tester,
  Widget pantalla, {
  double escala = 1,
}) async {
  tester.view.physicalSize = telefono * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final observador = ObservadorRutas();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(primarySwatch: Colors.indigo),
      navigatorObservers: [observador],
      home: pantalla,
    ),
  );
  await tester.pumpAndSettle();
  return observador;
}

/// Los textos de la pantalla.
Iterable<RenderParagraph> parrafos(WidgetTester tester) =>
    tester.renderObjectList<RenderParagraph>(find.byType(RichText));

/// Las palabras que quedaron partidas en dos renglones. Los párrafos para los
/// que [salvo] da true no se revisan: un texto técnico (el de una excepción)
/// puede tener "palabras" más largas que un renglón.
List<String> palabrasPartidas(
  WidgetTester tester, {
  bool Function(String texto)? salvo,
}) => [
  for (final parrafo in parrafos(tester))
    if (!(salvo?.call(parrafo.text.toPlainText()) ?? false))
      for (final palabra in RegExp(
        r'\S+',
      ).allMatches(parrafo.text.toPlainText()))
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

/// Los textos que quedaron cortados (con más renglones de los que tienen).
List<String> textosCortados(WidgetTester tester) => [
  for (final parrafo in parrafos(tester))
    if (parrafo.didExceedMaxLines) parrafo.text.toPlainText(),
];

/// Lo que dice TalkBack, en el orden en que recorre la pantalla (sin los
/// nodos que no dicen nada). Un nodo que junta a los de adentro
/// (MergeSemantics alrededor de un botón) dice lo de todos: por eso se lee
/// la etiqueta de sus datos y no la propia, que queda vacía.
List<String> ordenTalkBack(WidgetTester tester) => tester.semantics
    .simulatedAccessibilityTraversal()
    .map((nodo) => nodo.getSemanticsData().label)
    .where((etiqueta) => etiqueta.isNotEmpty)
    .toList();
