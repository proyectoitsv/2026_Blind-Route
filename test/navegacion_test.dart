import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blindroute/ajustes_navegacion.dart';
import 'package:blindroute/ajustes_voz.dart';
import 'package:blindroute/beacon_model.dart';
import 'package:blindroute/design/design.dart';
import 'package:blindroute/grilla_nav.dart';
import 'package:blindroute/mapa_widget.dart';
import 'package:blindroute/modo_automatico.dart';
import 'package:blindroute/pantalla_ajustes_voz.dart';
import 'package:blindroute/panel_ajustes_navegacion.dart';
import 'package:blindroute/pantalla_naveg.dart';
import 'package:blindroute/poi_model.dart';
import 'package:blindroute/seguimiento_recorrido.dart';
import 'package:blindroute/vista_navegacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ayudas_pantallas.dart';
import 'base_falsa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LA NAVEGACIÓN (fase 5.7 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// Lo que se ve (VistaNavegacion, que recibe todo de afuera): la barra, el
// destino, la brújula, los pisos, la indicación, el plano, la línea de tiempo,
// la señal y la píldora; los dos gestos de toda la pantalla; lo que dice
// TalkBack y la letra al 200 % con Inter de verdad.
//
// Después, SeguimientoRecorrido (los tramos que se muestran, armados con la
// ruta de la navegación), el plano (MapaWidget) y la pantalla de verdad
// (PantallaNavegacion) con la base, la voz y la brújula simuladas: sin
// Bluetooth (flutter_blue_plus no tiene plataforma en los tests), así que no
// hay posición ni ruta; lo de la guía se prueba con la vista.

/// Un PNG de 1 × 1, transparente.
const String _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==';

const EventChannel _canalBrujula = EventChannel('hemanthraj/flutter_compass');
const EventChannel _canalAcelerometro = EventChannel(
  'dev.fluttercommunity.plus/sensors/user_accel',
);
const MethodChannel _canalSensores = MethodChannel(
  'dev.fluttercommunity.plus/sensors/method',
);
const MethodChannel _canalEscucha = MethodChannel(
  'plugin.csdcorp.com/speech_to_text',
);
const String _canalWakelock =
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

late String _rutaPlano;

final TestDefaultBinaryMessenger _mensajero =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Lo que se le mandó a decir al motor de voz.
final List<String> _dichas = [];

/// La plataforma simulada: la voz, el reconocedor, los sensores, la brújula y
/// el wakelock. El Bluetooth no: en los tests falla, como en un teléfono sin.
void _simularPlataforma() {
  SharedPreferences.setMockInitialValues({});
  _dichas.clear();
  _mensajero.setMockMethodCallHandler(canalVoz, (llamada) async {
    if (llamada.method == 'speak') _dichas.add(llamada.arguments as String);
    return 1;
  });
  _mensajero.setMockMethodCallHandler(_canalEscucha, (llamada) async {
    return llamada.method == 'initialize' ? false : null;
  });
  _mensajero.setMockMethodCallHandler(_canalSensores, (_) async => null);
  _mensajero.setMockStreamHandler(
    _canalAcelerometro,
    MockStreamHandler.inline(onListen: (_, _) {}),
  );
  _mensajero.setMockStreamHandler(
    _canalBrujula,
    MockStreamHandler.inline(
      onListen: (_, eventos) => eventos.success(<double>[90, 0, 15]),
    ),
  );
  _mensajero.setMockMessageHandler(
    _canalWakelock,
    (_) async => const StandardMessageCodec().encodeMessage(<Object?>[]),
  );
}

/// Lo que avisó la vista.
class _Avisos {
  int toques = 0;
  int mantenidos = 0;
  int lista = 0;
  int cancelar = 0;
  int ajustes = 0;
  int centrar = 0;
  final List<String> pisos = [];
}

const Key _clavePlano = ValueKey('plano');

const DatosIndicacion _guia = DatosIndicacion(
  tipo: TipoIndicacion.guia,
  icono: Icons.turn_left_rounded,
  titulo: 'Girá a la izquierda',
  detalle: '7 metros',
  etiqueta: 'Girá a la izquierda, 7 metros',
);

const DatosIndicacion _llegada = DatosIndicacion(
  tipo: TipoIndicacion.llegada,
  icono: Icons.flag_rounded,
  titulo: 'Llegaste',
  detalle: 'Aula 12',
  etiqueta: 'Llegaste. Aula 12',
);

const DatosIndicacion _escalera = DatosIndicacion(
  tipo: TipoIndicacion.escalera,
  icono: Icons.stairs_rounded,
  titulo: 'Subí la escalera a Piso 2',
  detalle: 'Al llegar, mantené apretada la pantalla',
  etiqueta:
      'Subí la escalera a Piso 2. Al llegar, mantené apretada la pantalla',
);

const DatosIndicacion _orientacion = DatosIndicacion(
  tipo: TipoIndicacion.orientacion,
  icono: Icons.turn_right_rounded,
  titulo: 'Girá un poco a la derecha',
  detalle: 'Hacia Aula 12',
  etiqueta: 'Girá un poco a la derecha. Hacia Aula 12',
);

/// Una ruta de ejemplo: dos tramos hechos, en el segundo de tres.
Recorrido _recorrido() => const Recorrido(
  tramos: [
    TramoRuta(metros: 5, puntos: [Offset(0.1, 0.1), Offset(0.4, 0.1)]),
    TramoRuta(metros: 8, puntos: [Offset(0.4, 0.1), Offset(0.4, 0.6)]),
    TramoRuta(
      metros: 6,
      marca: MarcaTramo.destino,
      descripcionMarca: 'Aula 12',
      puntos: [Offset(0.4, 0.6), Offset(0.9, 0.6)],
    ),
  ],
  tramoActual: 1,
  avance: 0.25,
);

Widget _vista(
  _Avisos a, {
  String? destino,
  String estadoRuta = '',
  Widget? brujula,
  List<OpcionPiso> pisos = const [],
  DatosIndicacion? indicacion,
  Recorrido? recorrido,
  String? avisoOtroPiso,
  bool buscandoUbicacion = false,
  bool siguiendo = true,
  String estadoSenal = 'Buscando beacons...',
  String? detalleSenal,
  bool escuchando = false,
  String ayuda = 'Tocá en cualquier parte de la pantalla',
  bool ayudaImportante = false,
  bool admin = false,
}) => VistaNavegacion(
  titulo: 'Planta baja',
  destino: destino,
  estadoRuta: estadoRuta,
  brujula:
      brujula ??
      const ChipOrientacion(disponible: true, grados: 45, direccion: 'NE'),
  pisos: pisos,
  indicacion: indicacion,
  recorrido: recorrido,
  plano: const ColoredBox(key: _clavePlano, color: Colors.white),
  avisoOtroPiso: avisoOtroPiso,
  buscandoUbicacion: buscandoUbicacion,
  siguiendo: siguiendo,
  alCentrar: () => a.centrar++,
  estadoSenal: estadoSenal,
  detalleSenal: detalleSenal,
  escuchando: escuchando,
  ayuda: ayuda,
  ayudaImportante: ayudaImportante,
  alTocarPantalla: () => a.toques++,
  alMantenerPantalla: () => a.mantenidos++,
  duracionMantener: const Duration(seconds: 1),
  alElegirDeLista: () => a.lista++,
  alCancelar: destino == null ? null : () => a.cancelar++,
  alAbrirAjustes: admin ? () => a.ajustes++ : null,
);

/// Un toque en la pantalla, lejos de todo control: sobre la fila de la señal.
Offset _lugarLibre(WidgetTester tester) =>
    tester.getCenter(find.text('Buscando beacons...'));

/// Si el nodo de TalkBack de [finder] se anuncia solo al cambiar.
bool _esLiveRegion(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isLiveRegion;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await cargarInter();
    final carpeta = Directory.systemTemp.createTempSync('navegacion');
    final archivo = File('${carpeta.path}/plano.png');
    archivo.writeAsBytesSync(base64Decode(_png1x1));
    _rutaPlano = archivo.path;
    // Se leen una sola vez: acá, con el reloj de verdad. Con el reloj falso
    // de un test, la lectura quedaría colgada para los que siguen.
    SharedPreferences.setMockInitialValues({});
    await AjustesVoz.instancia.cargar();
    await AjustesNavegacion.instancia.cargar();
  });

  group('la vista', () {
    testWidgets('sin destino: qué hacer, la brújula y sólo el micrófono', (
      tester,
    ) async {
      await armarPantalla(tester, _vista(_Avisos()));
      expect(find.text('Planta baja'), findsOneWidget);
      expect(find.text('Tocá la pantalla para elegir destino'), findsOneWidget);
      expect(find.text('Tocá y hablá'), findsOneWidget);
      expect(find.text('Cancelar'), findsNothing);
      expect(find.byTooltip('Seleccionar destino desde lista'), findsOneWidget);
      expect(find.byTooltip('Ajustes de navegación'), findsNothing);
      expect(find.byType(LineaTiempo), findsNothing);
      expect(find.byType(TarjetaIndicacion), findsNothing);
      expect(find.text('NE'), findsOneWidget);
      expect(find.text('45°'), findsOneWidget);
    });

    testWidgets('TalkBack sin destino: en orden y con las etiquetas de '
        'siempre; 48 dp, etiquetas y contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(tester, _vista(_Avisos(), admin: true));
      expect(ordenTalkBack(tester), [
        'Planta baja',
        'Ajustes de navegación',
        'Seleccionar destino desde lista',
        'Tocá en cualquier parte de la pantalla para elegir tu destino por voz',
        'Tocá la pantalla para elegir destino',
        'Orientación: NE, 45 grados',
        'Centrar el mapa en tu ubicación',
        'Buscando beacons...',
        'Tocá aquí y decí el destino',
      ]);
      // El nombre y los dos gestos, en un mismo nodo.
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(RegExp('^Tocá en cualquier parte')),
        ),
        isSemantics(hasTapAction: true, hasLongPressAction: true),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('toda la pantalla: un toque pide el destino por voz', (
      tester,
    ) async {
      final a = _Avisos();
      await armarPantalla(tester, _vista(a));
      await tester.tapAt(_lugarLibre(tester));
      await tester.pump(const Duration(milliseconds: 300));
      expect(a.toques, 1);
      expect(a.mantenidos, 0);
    });

    testWidgets('toda la pantalla: mantener 1 s cambia de piso; menos, no; '
        'y no es además un toque', (tester) async {
      final a = _Avisos();
      await armarPantalla(tester, _vista(a));
      var dedo = await tester.startGesture(_lugarLibre(tester));
      await tester.pump(const Duration(milliseconds: 900));
      expect(a.mantenidos, 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(a.mantenidos, 1);
      await dedo.up();
      await tester.pump();
      expect(a.toques, 0);

      // Con el dedo que se mueve, no es ninguno de los dos: es para el mapa.
      dedo = await tester.startGesture(_lugarLibre(tester));
      await dedo.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 1100));
      await dedo.up();
      await tester.pump();
      expect(a.mantenidos, 1);
      expect(a.toques, 0);
    });

    testWidgets('lo que se toca aparte se queda con su toque', (tester) async {
      final a = _Avisos();
      await armarPantalla(
        tester,
        _vista(a, destino: 'Aula 12', siguiendo: false, admin: true),
      );
      await tester.tap(find.byTooltip('Cambiar destino'));
      expect(a.lista, 1);
      await tester.tap(find.byTooltip('Ajustes de navegación'));
      expect(a.ajustes, 1);
      await tester.tap(find.byTooltip('Centrar el mapa en tu ubicación'));
      expect(a.centrar, 1);
      await tester.tap(find.text('Cancelar'));
      expect(a.cancelar, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(a.toques, 0);
    });

    testWidgets('el micrófono de la píldora hace lo mismo que tocar la '
        'pantalla, también escuchando: así se puede cortar', (tester) async {
      final a = _Avisos();
      await armarPantalla(tester, _vista(a));
      await tester.tap(find.text('Tocá y hablá'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(a.toques, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: _vista(
            a,
            escuchando: true,
            ayuda: 'Decí el nombre del lugar',
            ayudaImportante: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Escuchando...'), findsOneWidget);
      expect(find.text('Decí el nombre del lugar'), findsOneWidget);
      expect(find.byIcon(Icons.hearing_rounded), findsOneWidget);
      await tester.tap(find.text('Escuchando...'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(a.toques, 2);
    });

    testWidgets('TalkBack en la píldora: dice qué hace, escuchando o no', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(tester, _vista(_Avisos(), destino: 'Aula 12'));
      expect(
        tester.getSemantics(find.text('Tocá y hablá')),
        isSemantics(
          label: 'Tocá aquí y decí el destino',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Cancelar')),
        isSemantics(label: 'Cancelar navegación', isButton: true),
      );
      await tester.pumpWidget(
        MaterialApp(home: _vista(_Avisos(), escuchando: true)),
      );
      await tester.pumpAndSettle();
      // Con TalkBack es la única forma de cortar la escucha: no puede estar
      // apagado. Con el dedo no se nota: el toque le llegaría a la pantalla.
      expect(
        tester.getSemantics(find.text('Escuchando...')),
        isSemantics(
          label: 'Escuchando, hablá ahora',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantica.dispose();
    });

    testWidgets('guiando: el tramo, la indicación, la distancia en acento y '
        'la línea de tiempo; TalkBack dice lo de siempre', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(
        tester,
        _vista(
          _Avisos(),
          destino: 'Aula 12',
          estadoRuta: 'Ruta a Aula 12: 19.0m',
          indicacion: _guia,
          recorrido: _recorrido(),
        ),
      );
      expect(find.text('Tramo 2 de 3'), findsOneWidget);
      expect(find.text('Aula 12'), findsOneWidget);
      expect(find.text('Ruta a Aula 12: 19.0m'), findsOneWidget);
      final distancia = tester
          .renderObject<RenderParagraph>(find.text('7 metros'))
          .text
          .style!;
      expect(distancia.color, ColoresApp.acento);
      expect(distancia.fontSize, TipografiaApp.titulo.fontSize);
      final titulo = tester
          .renderObject<RenderParagraph>(find.text('Girá a la izquierda'))
          .text
          .style!;
      expect(titulo.color, ColoresApp.textoPrincipal);
      expect(titulo.fontSize, TipografiaApp.instruccion.fontSize);
      final cuadro = tester.widget<CuadroIcono>(find.byType(CuadroIcono));
      expect(cuadro.lado, FormasApp.cuadroIndicacion);
      expect(cuadro.color, ColoresApp.acento);

      final linea = tester.widget<LineaTiempo>(find.byType(LineaTiempo));
      expect(linea.tramos, hasLength(3));
      expect(linea.tramoActual, 1);
      expect(linea.avance, 0.25);
      expect(
        find.ancestor(
          of: find.byType(LineaTiempo),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );

      final nodo = find.bySemanticsLabel('Girá a la izquierda, 7 metros');
      expect(nodo, findsOneWidget);
      expect(_esLiveRegion(tester, nodo), isFalse);
      expect(find.bySemanticsLabel(RegExp('Tramo')), findsNothing);
      expect(ordenTalkBack(tester), [
        'Planta baja',
        'Cambiar destino',
        'Tocá en cualquier parte de la pantalla para elegir tu destino por voz',
        'Aula 12\nRuta a Aula 12: 19.0m',
        'Orientación: NE, 45 grados',
        'Girá a la izquierda, 7 metros',
        'Centrar el mapa en tu ubicación',
        'Buscando beacons...',
        'Tocá aquí y decí el destino',
        'Cancelar navegación',
      ]);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    for (final (nombre, datos, enVivo) in [
      ('la llegada', _llegada, true),
      ('la escalera', _escalera, true),
      ('la orientación al llegar', _orientacion, false),
    ]) {
      testWidgets(
        '$nombre: sin el tramo; TalkBack ${enVivo ? 'la anuncia' : ''
                  'no la anuncia sola, ya habla la voz'}',
        (tester) async {
          final semantica = tester.ensureSemantics();
          await armarPantalla(
            tester,
            _vista(
              _Avisos(),
              destino: 'Laboratorio',
              indicacion: datos,
              recorrido: _recorrido(),
            ),
          );
          expect(find.text('Tramo 2 de 3'), findsNothing);
          final nodo = find.bySemanticsLabel(datos.etiqueta);
          expect(nodo, findsOneWidget);
          expect(_esLiveRegion(tester, nodo), enVivo);
          expect(
            tester.widget<CuadroIcono>(find.byType(CuadroIcono)).color,
            datos.tipo == TipoIndicacion.llegada
                ? ColoresApp.hecho
                : ColoresApp.acento,
          );
          final detalle = tester
              .renderObject<RenderParagraph>(find.text(datos.detalle))
              .text
              .style!;
          expect(detalle.color, ColoresApp.textoSecundario);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        },
      );
    }

    for (final reducido in [false, true]) {
      testWidgets('al llegar, el aviso aparece con un fundido de '
          '${reducido ? '120 ms (movimiento reducido)' : '200 ms'}', (
        tester,
      ) async {
        final a = _Avisos();
        // Las dos cosas que hace el teléfono con «Quitar animaciones».
        if (reducido) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        }
        Widget armar(DatosIndicacion d) => MediaQuery(
          data: MediaQueryData(size: telefono, disableAnimations: reducido),
          child: MaterialApp(
            home: _vista(a, destino: 'Aula 12', indicacion: d),
          ),
        );
        await tester.pumpWidget(armar(_guia));
        await tester.pumpAndSettle();
        double opacidad() => tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(TarjetaIndicacion),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value;
        expect(opacidad(), 1);

        await tester.pumpWidget(armar(_llegada));
        expect(opacidad(), 0);
        final duracion = reducido
            ? MovimientoApp.fundidoReducido
            : MovimientoApp.llegada;
        await tester.pump(duracion * 0.5);
        expect(opacidad(), inExclusiveRange(0, 1));
        await tester.pump(duracion * 0.5);
        expect(opacidad(), 1);
      });
    }

    testWidgets('una indicación que cambia no hace ningún fundido', (
      tester,
    ) async {
      final a = _Avisos();
      Widget armar(DatosIndicacion d) => MaterialApp(
        home: _vista(a, destino: 'Aula 12', indicacion: d),
      );
      await tester.pumpWidget(armar(_guia));
      await tester.pumpAndSettle();
      await tester.pumpWidget(armar(_orientacion));
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(TarjetaIndicacion),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        1,
      );
    });

    testWidgets('la brújula: sin lecturas no se ve; sin brújula, el aviso', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(
        tester,
        _vista(_Avisos(), brujula: const ChipOrientacion(disponible: true)),
      );
      expect(find.byIcon(Icons.navigation_rounded), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: _vista(
            _Avisos(),
            brujula: const ChipOrientacion(disponible: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brújula no disponible'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Brújula no disponible'))
            .text
            .style!
            .color,
        ColoresApp.advertencia,
      );
      expect(
        find.bySemanticsLabel(
          'Brújula no disponible. Las instrucciones de giro pueden ser menos '
          'precisas.',
        ),
        findsOneWidget,
      );
      semantica.dispose();
    });

    testWidgets('la flecha de la brújula va por el camino corto', (
      tester,
    ) async {
      Widget armar(double grados) => MaterialApp(
        home: Scaffold(
          body: ChipOrientacion(
            disponible: true,
            grados: grados,
            direccion: 'N',
          ),
        ),
      );
      await tester.pumpWidget(armar(359));
      await tester.pumpAndSettle();
      double vueltas() =>
          tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;
      expect(vueltas(), moreOrLessEquals(359 / 360));
      await tester.pumpWidget(armar(1));
      await tester.pumpAndSettle();
      // De 359° a 1° son 2° hacia adelante, no una vuelta para atrás.
      expect(vueltas(), moreOrLessEquals(1 + 1 / 360));
    });

    testWidgets('los pisos: el del usuario con su ícono, el visto elegido, y '
        'TalkBack los nombra enteros', (tester) async {
      final semantica = tester.ensureSemantics();
      final a = _Avisos();
      await armarPantalla(
        tester,
        _vista(
          a,
          pisos: [
            OpcionPiso(
              etiqueta: 'PB',
              nombre: 'Planta baja',
              esMio: true,
              visto: false,
              alTocar: () => a.pisos.add('PB'),
            ),
            OpcionPiso(
              etiqueta: '1',
              nombre: 'Piso 1',
              esMio: false,
              visto: true,
              alTocar: () => a.pisos.add('1'),
            ),
          ],
        ),
      );
      final pb = tester.widget<ChipFiltro>(
        find.widgetWithText(ChipFiltro, 'PB'),
      );
      expect(pb.icono, Icons.my_location_rounded);
      expect(pb.seleccionado, isFalse);
      final uno = tester.widget<ChipFiltro>(
        find.widgetWithText(ChipFiltro, '1'),
      );
      expect(uno.icono, isNull);
      expect(uno.seleccionado, isTrue);
      expect(find.bySemanticsLabel('Ver Planta baja, tu piso'), findsOneWidget);
      expect(find.bySemanticsLabel('Ver Piso 1'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChipFiltro, 'PB'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(a.pisos, ['PB']);
      expect(a.toques, 0);
      semantica.dispose();
    });

    testWidgets('mirando otro piso: el cartel se anuncia y el botón vuelve al '
        'piso del usuario, resaltado', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(
        tester,
        _vista(
          _Avisos(),
          siguiendo: false,
          avisoOtroPiso: 'Viendo Piso 1 · estás en Planta baja',
        ),
      );
      final cartel = find.text('Viendo Piso 1 · estás en Planta baja');
      expect(cartel, findsOneWidget);
      expect(_esLiveRegion(tester, cartel), isTrue);
      expect(find.byTooltip('Volver a tu piso'), findsOneWidget);
      expect(
        tester
            .widget<BotonRedondo>(
              find.ancestor(
                of: find.byTooltip('Volver a tu piso'),
                matching: find.byType(BotonRedondo),
              ),
            )
            .resaltado,
        isTrue,
      );
      semantica.dispose();
    });

    testWidgets('el botón de centrar se resalta sólo si el mapa dejó de '
        'seguir; buscando ubicación, un chip sobre el plano', (tester) async {
      await armarPantalla(tester, _vista(_Avisos(), buscandoUbicacion: true));
      expect(find.text('Buscando tu ubicación...'), findsOneWidget);
      final boton = find.ancestor(
        of: find.byIcon(Icons.my_location_rounded),
        matching: find.byType(BotonRedondo),
      );
      expect(tester.widget<BotonRedondo>(boton).resaltado, isFalse);
      await tester.pumpWidget(
        MaterialApp(home: _vista(_Avisos(), siguiendo: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Buscando tu ubicación...'), findsNothing);
      final otro = find.ancestor(
        of: find.byIcon(Icons.location_searching_rounded),
        matching: find.byType(BotonRedondo),
      );
      expect(tester.widget<BotonRedondo>(otro).resaltado, isTrue);
    });

    testWidgets('el plano va hundido, con borde, y ocupa lo que sobra', (
      tester,
    ) async {
      await armarPantalla(tester, _vista(_Avisos()));
      final panel = tester.widget<PanelRelieve>(
        find.ancestor(
          of: find.byKey(_clavePlano),
          matching: find.byType(PanelRelieve),
        ),
      );
      expect(panel.hundido, isTrue);
      expect(panel.sombraEncima, isTrue);
      expect(panel.borde?.color, ColoresApp.borde);
      expect(tester.getSize(find.byKey(_clavePlano)).height, greaterThan(350));
    });

    testWidgets('la señal: sin detalle no hay botón; con detalle, se '
        'despliega; TalkBack la lee sin que se anuncie sola', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(tester, _vista(_Avisos()));
      expect(find.byTooltip('Ver el detalle de la señal'), findsNothing);
      expect(_esLiveRegion(tester, find.text('Buscando beacons...')), isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: _vista(_Avisos(), detalleSenal: 'Beacons activos: 3 / 4'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Beacons activos: 3 / 4'), findsNothing);
      await tester.tap(find.byTooltip('Ver el detalle de la señal'));
      await tester.pumpAndSettle();
      expect(find.text('Beacons activos: 3 / 4'), findsOneWidget);
      await tester.tap(find.byTooltip('Ocultar el detalle de la señal'));
      await tester.pumpAndSettle();
      expect(find.text('Beacons activos: 3 / 4'), findsNothing);
      semantica.dispose();
    });

    testWidgets('un tramo entre pisos deja a la vista cómo se cambia de piso', (
      tester,
    ) async {
      const ayuda = 'Mantené apretado para cambiar de piso';
      await armarPantalla(
        tester,
        _vista(
          _Avisos(),
          destino: 'Aula 12',
          ayuda: ayuda,
          ayudaImportante: true,
        ),
      );
      expect(find.text(ayuda), findsOneWidget);
    });

    testWidgets('con la letra al 200 %, la indicación va primero y se lee '
        'entera sin desplazar; la ayuda común se saca y la importante, no', (
      tester,
    ) async {
      await armarPantalla(
        tester,
        _vista(
          _Avisos(),
          destino: 'Aula 12',
          estadoRuta: 'Ruta a Aula 12: 19.0m',
          indicacion: _guia,
          recorrido: _recorrido(),
        ),
        escala: 2,
      );
      final plano = tester.getRect(find.byKey(_clavePlano));
      final destino = tester.getTopLeft(find.text('Aula 12'));
      final distancia = tester.getRect(find.text('7 metros'));
      expect(distancia.bottom, lessThanOrEqualTo(plano.top));
      expect(distancia.bottom, lessThan(destino.dy));
      expect(find.text('Tocá en cualquier parte de la pantalla'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: telefono,
              textScaler: TextScaler.linear(2),
            ),
            child: _vista(
              _Avisos(),
              ayuda: 'Mantené apretado para cambiar de piso',
              ayudaImportante: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Mantené apretado para cambiar de piso'),
        findsOneWidget,
      );
    });

    testWidgets('con la letra al 200 %, lo de arriba se desplaza, y un toque '
        'o mantener ahí siguen valiendo para toda la pantalla', (tester) async {
      final a = _Avisos();
      await armarPantalla(
        tester,
        _vista(
          a,
          destino: 'Laboratorio de Electrónica',
          estadoRuta: 'Ruta a Laboratorio de Electrónica: 19.0m',
          indicacion: _guia,
          recorrido: _recorrido(),
        ),
        escala: 2,
      );
      final desplazable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(desplazable.position.maxScrollExtent, greaterThan(0));

      final indicacion = tester.getCenter(find.text('Girá a la izquierda'));
      await tester.tapAt(indicacion);
      await tester.pump(const Duration(milliseconds: 300));
      expect(a.toques, 1);
      expect(a.mantenidos, 0);

      final dedo = await tester.startGesture(indicacion);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(a.mantenidos, 1);
      await dedo.up();
      await tester.pump();
      expect(a.toques, 1);

      // Arrastrar desplaza, y no es ninguno de los dos.
      await tester.dragFrom(indicacion, const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 1100));
      expect(desplazable.position.pixels, greaterThan(0));
      expect(a.toques, 1);
      expect(a.mantenidos, 1);
    });

    for (final (nombre, armar) in <(String, Widget Function(_Avisos))>[
      ('sin destino', (a) => _vista(a)),
      (
        'guiando',
        (a) => _vista(
          a,
          destino: 'Laboratorio de Electrónica',
          estadoRuta: 'Ruta a Laboratorio de Electrónica: 19.0m',
          indicacion: _guia,
          recorrido: _recorrido(),
          detalleSenal: 'Beacons activos: 3 / 4',
          estadoSenal: 'Ubicación estable (4 beacons) · en movimiento',
        ),
      ),
      (
        'la escalera',
        (a) => _vista(
          a,
          destino: 'Laboratorio de Electrónica · Piso 2',
          estadoRuta: 'Escalera norte para subir: 12.0m · destino en Piso 2',
          indicacion: _escalera,
          recorrido: _recorrido(),
          ayuda: 'Mantené apretado para cambiar de piso',
          ayudaImportante: true,
        ),
      ),
      (
        'mirando otro piso',
        (a) => _vista(
          a,
          pisos: [
            OpcionPiso(
              etiqueta: 'PB',
              nombre: 'Planta baja',
              esMio: true,
              visto: false,
              alTocar: () {},
            ),
            OpcionPiso(
              etiqueta: '1',
              nombre: 'Piso 1',
              esMio: false,
              visto: true,
              alTocar: () {},
            ),
          ],
          siguiendo: false,
          avisoOtroPiso: 'Viendo Piso 1 · estás en Planta baja',
          brujula: const ChipOrientacion(disponible: false),
        ),
      ),
      (
        'buscando y con un error largo de señal',
        (a) => _vista(
          a,
          buscandoUbicacion: true,
          estadoSenal:
              'No se detectan beacons suficientes.\n'
              'Acercate a un beacon configurado.',
        ),
      ),
    ]) {
      testWidgets('con la letra al 200 %, $nombre: sin desbordes, nada cortado '
          'ni partido, sin línea de tiempo y con lugar para el plano', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await armarPantalla(tester, armar(_Avisos()), escala: 2);
        expect(tester.takeException(), isNull);
        expect(palabrasPartidas(tester), isEmpty);
        expect(textosCortados(tester), isEmpty);
        expect(find.byType(LineaTiempo), findsNothing);
        expect(tester.getSize(find.byKey(_clavePlano)).height, greaterThan(40));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantica.dispose();
      });
    }

    testWidgets('en el teléfono real (384 × 832, letra al 115 %), guiando: el '
        'plano tiene lugar y la línea de tiempo se ve', (tester) async {
      tester.view.physicalSize = const Size(384, 832) * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.15;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: _vista(
            _Avisos(),
            destino: 'Aula 12',
            estadoRuta: 'Ruta a Aula 12: 19.0m',
            indicacion: _guia,
            recorrido: _recorrido(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LineaTiempo), findsOneWidget);
      expect(tester.getSize(find.byKey(_clavePlano)).height, greaterThan(200));
    });

    testWidgets('la lista de destinos: una hoja, un toque y da la clave', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      String? elegida;
      await armarPantalla(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  elegida = await mostrarListaDestinos(context, const [
                    OpcionDestino(
                      clave: 'aula 12',
                      nombre: 'Aula 12',
                      pisos: 'Planta baja (acá)',
                      icono: Icons.place_rounded,
                    ),
                    OpcionDestino(
                      clave: 'escalera',
                      nombre: 'Escalera norte',
                      pisos: 'Planta baja (acá) · Piso 1',
                      icono: Icons.stairs_rounded,
                    ),
                  ]);
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('¿A dónde querés ir?'), findsOneWidget);
      expect(find.byType(TarjetaLista), findsNWidgets(2));
      expect(find.text('Planta baja (acá) · Piso 1'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.tap(find.text('Escalera norte'));
      await tester.pumpAndSettle();
      expect(elegida, 'escalera');
      expect(find.text('¿A dónde querés ir?'), findsNothing);
      semantica.dispose();
    });
  });

  group('los tramos que se muestran', () {
    final grilla = GrillaNav(metrosX: 10, metrosY: 10, tamCeldaMetros: 1);
    Offset celda(int x, int y) => Offset((x + 0.5) / 10, (y + 0.5) / 10);

    /// Una L: cuatro celdas al este y tres al sur.
    final ele = [
      celda(0, 0),
      celda(1, 0),
      celda(2, 0),
      celda(3, 0),
      celda(4, 0),
      celda(4, 1),
      celda(4, 2),
      celda(4, 3),
    ];

    test(
      'corta la ruta en las esquinas, con sus metros y la marca al final',
      () {
        final r = SeguimientoRecorrido().actualizar(
          clave: 1,
          ruta: ele,
          grilla: grilla,
          marca: MarcaTramo.destino,
          descripcionMarca: 'Aula 12',
        )!;
        expect(r.tramos, hasLength(2));
        expect(r.tramos[0].metros, moreOrLessEquals(4));
        expect(r.tramos[0].marca, isNull);
        expect(r.tramos[0].puntos.first, celda(0, 0));
        expect(r.tramos[0].puntos.last, celda(4, 0));
        expect(r.tramos[1].metros, moreOrLessEquals(3));
        expect(r.tramos[1].marca, MarcaTramo.destino);
        expect(r.tramos[1].textoMarca, 'Aula 12');
        expect(r.tramos[1].puntos.first, celda(4, 0));
        expect(r.tramoActual, 0);
        expect(r.avance, 0);
      },
    );

    test('al avanzar sigue siendo la misma lista de tramos', () {
      final s = SeguimientoRecorrido();
      final inicio = s.actualizar(clave: 1, ruta: ele, grilla: grilla)!;
      final a2 = s.actualizar(clave: 1, ruta: ele.sublist(2), grilla: grilla)!;
      expect(identical(a2.tramos, inicio.tramos), isTrue);
      expect(a2.tramoActual, 0);
      expect(a2.avance, moreOrLessEquals(0.5));
      // Justo en la esquina ya va en el tramo siguiente.
      final enEsquina = s.actualizar(
        clave: 1,
        ruta: ele.sublist(4),
        grilla: grilla,
      )!;
      expect(identical(enEsquina.tramos, inicio.tramos), isTrue);
      expect(enEsquina.tramoActual, 1);
      expect(enEsquina.avance, 0);
      // En la última celda, al final del último tramo.
      final fin = s.actualizar(clave: 1, ruta: ele.sublist(7), grilla: grilla)!;
      expect(fin.tramoActual, 1);
      expect(fin.avance, 1);
    });

    test('la misma lista no se vuelve a calcular', () {
      final s = SeguimientoRecorrido();
      final a = s.actualizar(clave: 1, ruta: ele, grilla: grilla);
      final b = s.actualizar(clave: 1, ruta: ele, grilla: grilla);
      expect(identical(a, b), isTrue);
    });

    test('si la ruta cambia, lo recorrido queda hecho y lo que falta es lo '
        'nuevo', () {
      final s = SeguimientoRecorrido();
      s.actualizar(clave: 1, ruta: ele, grilla: grilla);
      // Ya dobló la esquina: va en el segundo tramo, y se recalcula.
      final antes = s.actualizar(
        clave: 1,
        ruta: ele.sublist(5),
        grilla: grilla,
      )!;
      expect(antes.tramoActual, 1);
      final otra = [
        celda(4, 1),
        celda(5, 1),
        celda(6, 1),
        celda(6, 2),
        celda(6, 3),
      ];
      final r = s.actualizar(clave: 1, ruta: otra, grilla: grilla)!;
      expect(identical(r.tramos, antes.tramos), isFalse);
      // El primero, hecho; el segundo se reemplaza por los dos nuevos.
      expect(r.tramos, hasLength(3));
      expect(r.tramoActual, 1);
      expect(r.avance, 0);
      expect(r.tramos[0].puntos.last, celda(4, 0));
      expect(r.tramos[1].puntos.first, celda(4, 1));
      expect(r.estadoDe(0), EstadoTramo.hecho);
    });

    test('otro destino empieza de cero', () {
      final s = SeguimientoRecorrido();
      s.actualizar(clave: 1, ruta: ele, grilla: grilla);
      s.actualizar(clave: 1, ruta: ele.sublist(5), grilla: grilla);
      // Con la misma clave, el primer tramo de la L quedaría como hecho.
      final otra = [celda(0, 5), celda(1, 5), celda(2, 5)];
      final r = s.actualizar(clave: 2, ruta: otra, grilla: grilla)!;
      expect(r.tramos, hasLength(1));
      expect(r.tramoActual, 0);
    });

    test('sin ruta no hay recorrido, y al volver sigue la cuenta', () {
      final s = SeguimientoRecorrido();
      s.actualizar(clave: 1, ruta: ele, grilla: grilla);
      s.actualizar(clave: 1, ruta: ele.sublist(5), grilla: grilla);
      expect(s.actualizar(clave: 1, ruta: null, grilla: grilla), isNull);
      expect(s.actualizar(clave: 1, ruta: const [], grilla: grilla), isNull);
      final r = s.actualizar(clave: 1, ruta: ele.sublist(6), grilla: grilla)!;
      expect(r.tramoActual, 1);
    });

    test('una ruta de una celda no rompe nada', () {
      final r = SeguimientoRecorrido().actualizar(
        clave: 1,
        ruta: [celda(2, 2)],
        grilla: grilla,
        marca: MarcaTramo.destino,
      )!;
      expect(r.tramos, hasLength(1));
      expect(r.tramos.single.metros, 0);
      expect(r.tramoActual, 0);
      expect(r.avance, 1);
    });
  });

  group('el plano', () {
    Widget plano({
      Recorrido? recorrido,
      Offset? posicion,
      double? heading,
      double escalaVista = 1,
      List<LugarInteres> lugares = const [],
      Map<String, BeaconMarcado> beacons = const {},
      List<Offset> vertices = const [],
    }) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: MapaWidget(
              rutaImagen: _rutaPlano,
              beacons: beacons,
              zonas: const [],
              lugares: lugares,
              grilla: GrillaNav(metrosX: 10, metrosY: 10, tamCeldaMetros: 1),
              posicionUsuario: posicion,
              headingUsuario: heading,
              recorrido: recorrido,
              escalaVista: escalaVista,
              verticesEnCurso: vertices,
            ),
          ),
        ),
      ),
    );

    testWidgets('los números de los vértices van en una pastilla oscura, así '
        'se leen sobre un plano blanco', (tester) async {
      await tester.pumpWidget(
        plano(vertices: const [Offset(0.2, 0.2), Offset(0.8, 0.2)]),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_MapaPainter',
        ),
        paints..something(
          (metodo, argumentos) =>
              metodo == #drawRRect &&
              (argumentos[1] as Paint).color.toARGB32() ==
                  ColoresApp.mapaContorno.toARGB32(),
        ),
      );
    });

    testWidgets('la ruta es la línea, sin su cabezal y sin que la lea '
        'TalkBack; sin ruta, no está', (tester) async {
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(plano(recorrido: _recorrido(), escalaVista: 2));
      await tester.pumpAndSettle();
      final linea = tester.widget<LineaRuta>(find.byType(LineaRuta));
      expect(linea.mostrarCabezal, isFalse);
      expect(linea.escalaVista, 2);
      expect(linea.tramoActual, 1);
      expect(find.bySemanticsLabel(RegExp('Tramo')), findsNothing);
      await tester.pumpWidget(plano());
      await tester.pumpAndSettle();
      expect(find.byType(LineaRuta), findsNothing);
      semantica.dispose();
    });

    Finder capaUsuario() => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_UsuarioPainter',
    );

    testWidgets('la posición: el círculo con el anillo de acento, el contorno '
        'oscuro y la flecha; sin brújula, un punto', (tester) async {
      await tester.pumpWidget(plano(posicion: const Offset(0.5, 0.5)));
      await tester.pumpAndSettle();
      expect(
        capaUsuario(),
        paints
          ..circle(color: ColoresApp.mapaContorno)
          ..circle(color: ColoresApp.acento),
      );
      await tester.pumpWidget(
        plano(posicion: const Offset(0.5, 0.5), heading: 90),
      );
      await tester.pumpAndSettle();
      expect(
        capaUsuario(),
        paints
          ..circle(color: ColoresApp.mapaContorno)
          ..something(
            (metodo, argumentos) =>
                metodo == #drawPath &&
                (argumentos[1] as Paint).color.toARGB32() ==
                    ColoresApp.textoPrincipal.toARGB32(),
          ),
      );
    });

    final lugares = [
      LugarInteres(
        id: 1,
        pisoId: 1,
        nombre: 'Laboratorio',
        posicion: const Offset(0.5, 0.5),
      ),
      LugarInteres(
        id: 2,
        pisoId: 1,
        nombre: 'Escalera',
        posicion: const Offset(0.2, 0.2),
        tipo: TipoLugar.escalera,
        sube: true,
      ),
    ];

    testWidgets('los nombres de los lugares se leen sobre cualquier plano y '
        'TalkBack los lee', (tester) async {
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(plano(lugares: lugares));
      await tester.pumpAndSettle();
      final estilo = tester
          .renderObject<RenderParagraph>(find.text('Laboratorio'))
          .text
          .style!;
      expect(estilo.color, ColoresApp.textoPrincipal);
      expect(estilo.fontSize, TipografiaApp.leyenda.fontSize);
      expect(find.bySemanticsLabel('Laboratorio'), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('con la letra al 200 %, los nombres crecen hasta 1,3', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(plano(lugares: lugares));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final nombre in ['Laboratorio', 'Escalera ↑']) {
        final escala = MediaQuery.textScalerOf(
          tester.element(find.text(nombre)),
        ).scale(10);
        expect(escala, moreOrLessEquals(13));
      }
    });
  });

  group('la pantalla de verdad', () {
    setUpAll(iniciarBaseDePrueba);

    void cargarEdificio() {
      baseFalsa.reiniciar();
      final piso = <String, Object?>{
        'id': 1,
        'edificio_id': 1,
        'numero_piso': 0,
        'nombre_piso': 'Planta baja',
        'ruta_imagen': _rutaPlano,
        'escala_metros': 30.0,
        'escala_metros_alto': 20.0,
      };
      baseFalsa.agregar('pisos', piso);
      final lugar = <String, Object?>{
        'id': 1,
        'piso_id': 1,
        'nombre': 'Aula 12',
        'x': 0.5,
        'y': 0.5,
        'descripcion': null,
        'tipo': 'comun',
        'sube': 0,
        'baja': 0,
        'direccion_entrada': null,
        'palabras_clave': null,
        'rubro': null,
        'rubro_palabras': null,
        'ascensor': 0,
      };
      baseFalsa.agregar('lugares_interes', lugar);
      baseFalsa.armadas['SELECT p.* FROM pisos p'] = () =>
          baseFalsa.filas('pisos');
      baseFalsa.armadas['SELECT l.* FROM lugares_interes l'] = () =>
          baseFalsa.filas('lugares_interes');
      baseFalsa.armadas['SELECT p.id, p.nombre_piso'] = () => [
        {...piso, 'edificio_nombre': 'Facultad'},
      ];
    }

    /// Deja correr el arranque de la pantalla: la base, la voz y los permisos.
    Future<void> arrancar(WidgetTester tester) async {
      _simularPlataforma();
      cargarEdificio();
      await _armarPantallaReal(tester);
    }

    testWidgets('arma la vista con el piso de la base y un toque en la '
        'pantalla pregunta el destino por voz', (tester) async {
      await arrancar(tester);
      expect(find.byType(VistaNavegacion), findsOneWidget);
      expect(find.text('Planta baja'), findsOneWidget);
      expect(find.text('Tocá la pantalla para elegir destino'), findsOneWidget);
      _dichas.clear();
      await tester.tapAt(_estadoSenalCentro(tester));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(_dichas, contains('¿A dónde vas?'));
      await _desarmar(tester);
    });

    testWidgets('la lista de destinos elige el lugar; «Cancelar» lo suelta y '
        'lo dice', (tester) async {
      await arrancar(tester);
      await tester.tap(find.byTooltip('Seleccionar destino desde lista'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('¿A dónde querés ir?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TarjetaLista, 'Aula 12'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      VistaNavegacion vista() =>
          tester.widget<VistaNavegacion>(find.byType(VistaNavegacion));
      expect(vista().destino, 'Aula 12');
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.byTooltip('Cambiar destino'), findsOneWidget);
      _dichas.clear();
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(_dichas, contains('Navegación cancelada.'));
      expect(vista().destino, isNull);
      expect(find.text('Cancelar'), findsNothing);
      await _desarmar(tester);
    });

    testWidgets('el panel de ajustes sólo en la app del admin', (tester) async {
      await arrancar(tester);
      expect(find.byTooltip('Ajustes de navegación'), findsNothing);
      await _desarmar(tester);
    });
  });

  group('las otras pantallas', () {
    testWidgets('Ajustes de voz: un deslizador por ajuste, «Probar la voz» y '
        'la letra al 200 %', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await armarPantalla(tester, const PantallaAjustesVoz(), escala: 2);
      await _dejarCorrer(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Deslizador), findsWidgets);
      expect(palabrasPartidas(tester), isEmpty);
      await tester.scrollUntilVisible(find.text('Probar la voz'), 200);
      await tester.pumpAndSettle();
      expect(find.byType(BotonPrincipal), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('el modo automático: el estado, sin ruedita y sin anunciarse '
        'encima de la voz', (tester) async {
      final semantica = tester.ensureSemantics();
      _simularPlataforma();
      tester.view.physicalSize = telefono * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final errores = <Object>[];
      await runZonedGuarded(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(primarySwatch: Colors.indigo),
            home: const ModoAutomatico(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
      }, (error, _) => errores.add(error));
      expect(find.byType(EstadoPantalla), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final titulo = tester.widget<EstadoPantalla>(find.byType(EstadoPantalla));
      final nodo = find.bySemanticsLabel(titulo.titulo);
      expect(nodo, findsOneWidget);
      expect(_esLiveRegion(tester, nodo), isFalse);
      expect(errores.whereType<UnsupportedError>(), hasLength(errores.length));
      semantica.dispose();
      await runZonedGuarded(() => _desarmar(tester), (_, _) {});
    });

    Future<void> abrirPanel(WidgetTester tester, {double escala = 1}) async {
      SharedPreferences.setMockInitialValues({});
      await armarPantalla(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => mostrarPanelAjustesNavegacion(context),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
        escala: escala,
      );
      await tester.tap(find.text('Abrir'));
      await _dejarCorrer(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('el panel del admin: una hoja con el alcance, los deslizadores '
        'y los interruptores de prueba', (tester) async {
      await abrirPanel(tester);
      expect(find.text('Ajustes de navegación'), findsOneWidget);
      expect(find.text('Este edificio'), findsWidgets);
      expect(find.text('General'), findsWidgets);
      expect(find.text('Giros'), findsOneWidget);
      expect(find.byType(Deslizador), findsWidgets);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(Slider), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Freno lateral por brújula'),
        300,
      );
      await tester.pumpAndSettle();
      final ajustes = AjustesNavegacion.instancia;
      final antes = ajustes.frenarLateralConBrujula;
      await tester.tap(find.text('Freno lateral por brújula'));
      await tester.pumpAndSettle();
      expect(ajustes.frenarLateralConBrujula, !antes);
      ajustes.frenarLateralConBrujula = antes;
    });

    testWidgets('el panel del admin: al soltar un deslizador guarda el valor', (
      tester,
    ) async {
      final ajustes = AjustesNavegacion.instancia;
      await tester.runAsync(() => ajustes.usarEdificio(null));
      await abrirPanel(tester);
      final atraso = ajustes.parametrosGiro.first;
      final antes = ajustes.valorGeneral(atraso);
      await tester.drag(find.byType(Slider).first, const Offset(80, 0));
      await _dejarCorrer(tester);
      await tester.pumpAndSettle();
      expect(ajustes.valorGeneral(atraso), greaterThan(antes));
      ajustes.volverAlCodigo(atraso);
    });

    testWidgets('el panel del admin con la letra al 200 %: sin desbordes', (
      tester,
    ) async {
      await abrirPanel(tester, escala: 2);
      expect(tester.takeException(), isNull);
      expect(palabrasPartidas(tester), isEmpty);
    });
  });
}

Offset _estadoSenalCentro(WidgetTester tester) =>
    tester.getCenter(find.byIcon(Icons.sensors_rounded));

/// Arma la pantalla de navegación y deja correr su arranque.
Future<void> _armarPantallaReal(WidgetTester tester) async {
  tester.view.physicalSize = telefono * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: PantallaNavegacion(
        pisoId: 1,
        rutaImagen: _rutaPlano,
        escalaX: 30,
        escalaY: 20,
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await _dejarCorrer(tester);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Deja correr lo que espera a los ajustes, que se leyeron con el reloj de
/// verdad (ver el setUpAll).
Future<void> _dejarCorrer(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

/// Saca la pantalla y deja correr lo que quedó pendiente.
Future<void> _desarmar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 15));
}
