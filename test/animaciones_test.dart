import 'dart:math' as math;

import 'package:blindroute/design/design.dart';
import 'package:blindroute/design/galeria_pantallas.dart';
import 'package:blindroute/pantalla_ajustes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ANIMACIONES DEL SISTEMA DE DISEÑO (fase 3 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// La tabla de movimiento de la v5 del prompt (sección 5), en código: cuánto
// dura cada animación y con qué curva, que el estado final sea el mismo con
// y sin movimiento reducido, que una animación interrumpida siga desde donde
// está (sin saltos) y termine en su estado final, que el cabezal siga la
// posición sobre la ruta, la vibración con su interruptor y la pantalla de
// Ajustes. Lo que no se puede ver acá (cómo se siente en la mano, la
// vibración de verdad) se prueba en el teléfono.
//
// El tiempo de los tests es falso: tester.pump(d) adelanta d y arma un
// cuadro. Una animación que arranca mientras se arma un cuadro cuenta el
// tiempo desde ese cuadro. Al cumplir justo su duración ya muestra el valor
// final, pero Flutter la da por terminada (y saca lo que se iba) recién en
// el cuadro siguiente. Una pantalla nueva pasa su primer cuadro fuera de
// escena (Flutter mide ahí los "hero"): se mira desde el segundo.

/// Arma [hijo] en un teléfono de 360 × 780 dp con el tema nuevo. [enLista]:
/// adentro de una lista, donde un toque se confirma a los 100 ms (o al
/// levantar el dedo); si no, en el centro, donde se confirma enseguida.
Future<void> armar(
  WidgetTester tester,
  Widget hijo, {
  bool sinAnimaciones = false,
  bool enLista = true,
  double escala = 1,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaBlindRoute.oscuro,
      builder: (context, navegador) {
        final datos = MediaQuery.of(context);
        return MediaQuery(
          data: datos.copyWith(
            textScaler: TextScaler.linear(escala),
            // Lo del teléfono (FakeAccessibilityFeatures) también vale.
            disableAnimations: datos.disableAnimations || sinAnimaciones,
          ),
          child: navegador!,
        );
      },
      home: Scaffold(
        body: enLista
            ? ListView(
                padding: const EdgeInsets.all(EspaciadoApp.margenLateral),
                children: [hijo],
              )
            : Center(child: hijo),
      ),
    ),
  );
}

/// La primera decoración con relieve debajo de [de].
DecoracionRelieve relieveDe(WidgetTester tester, Finder de) =>
    tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: de,
                matching: find.byWidgetPredicate(
                  (w) => w is DecoratedBox && w.decoration is DecoracionRelieve,
                ),
              ),
            )
            .first
            .decoration
        as DecoracionRelieve;

/// Guarda las vibraciones que pide la app (en lugar de vibrar).
List<String> escucharVibraciones(WidgetTester tester) {
  final tipos = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (llamada) async {
      if (llamada.method == 'HapticFeedback.vibrate') {
        tipos.add(llamada.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return tipos;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AjustesMovimiento.instancia.reiniciarParaTests();
  });

  // ── Presionar y soltar ──────────────────────────────────────────────────

  group('presionar y soltar', () {
    double elevacion(WidgetTester tester) =>
        relieveDe(tester, find.byType(BotonSecundario)).elevacion;
    double escala(WidgetTester tester) => tester
        .widget<AnimatedScale>(
          find.descendant(
            of: find.byType(BotonSecundario),
            matching: find.byType(AnimatedScale),
          ),
        )
        .scale;

    testWidgets('presionar: 120 ms hasta hundido y 0,97; soltar: 160 ms', (
      tester,
    ) async {
      await armar(
        tester,
        BotonSecundario(texto: 'Comenzar', alPresionar: () {}),
      );
      final dedo = await tester.startGesture(
        tester.getCenter(find.byType(BotonSecundario)),
      );
      // En una lista, el toque se confirma a los 100 ms: ahí arranca.
      await tester.pump(const Duration(milliseconds: 100));
      expect(elevacion(tester), 1);
      expect(escala(tester), MovimientoApp.escalaPresion);
      await tester.pump(const Duration(milliseconds: 60));
      // A mitad de camino: entre levantado y hundido.
      expect(elevacion(tester), inExclusiveRange(-1, 1));
      await tester.pump(const Duration(milliseconds: 60));
      expect(elevacion(tester), -1);
      // Sostenido, sigue hundido.
      await tester.pump(const Duration(milliseconds: 100));
      expect(elevacion(tester), -1);

      await dedo.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(elevacion(tester), inExclusiveRange(-1, 1));
      await tester.pump(const Duration(milliseconds: 80));
      expect(elevacion(tester), 1);
      expect(escala(tester), 1);
    });

    testWidgets('con movimiento reducido: al presionar sólo la sombra, al '
        'soltar salta, y termina igual', (tester) async {
      await armar(
        tester,
        BotonSecundario(texto: 'Comenzar', alPresionar: () {}),
        sinAnimaciones: true,
      );
      final dedo = await tester.startGesture(
        tester.getCenter(find.byType(BotonSecundario)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 60));
      // La sombra cambia en 120 ms; sin escala.
      expect(elevacion(tester), inExclusiveRange(-1, 1));
      expect(escala(tester), 1);
      await tester.pump(const Duration(milliseconds: 160));
      expect(elevacion(tester), -1);
      await dedo.up();
      await tester.pump();
      // Al soltar, de golpe.
      expect(elevacion(tester), 1);
      expect(escala(tester), 1);
    });

    testWidgets('un toque corto también se ve hundido', (tester) async {
      var veces = 0;
      await armar(
        tester,
        BotonSecundario(texto: 'Comenzar', alPresionar: () => veces++),
      );
      // En una lista, un toque corto se confirma recién al levantar el dedo.
      await tester.tap(find.byType(BotonSecundario));
      expect(veces, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(elevacion(tester), lessThan(0));
      // Cumplido el mínimo (120 ms), vuelve.
      await tester.pumpAndSettle();
      expect(elevacion(tester), 1);
      expect(escala(tester), 1);
    });

    testWidgets('interrumpido: arranca desde donde está, sin saltos', (
      tester,
    ) async {
      await armar(
        tester,
        BotonSecundario(texto: 'Comenzar', alPresionar: () {}),
        enLista: false,
      );
      final centro = tester.getCenter(find.byType(BotonSecundario));
      final dedo = await tester.startGesture(centro);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(elevacion(tester), -1);
      await dedo.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // Volviendo a levantado.
      final antes = elevacion(tester);
      expect(antes, inExclusiveRange(-1, 1));
      // Se presiona otra vez a mitad de camino: sigue desde ahí.
      final otro = await tester.startGesture(centro);
      await tester.pump();
      expect(elevacion(tester), moreOrLessEquals(antes, epsilon: 1e-9));
      await tester.pump(MovimientoApp.presion);
      expect(elevacion(tester), -1);
      await otro.up();
      await tester.pumpAndSettle();
      expect(elevacion(tester), 1);
    });
  });

  // ── Selección ───────────────────────────────────────────────────────────

  group('selección', () {
    for (final reducido in [false, true]) {
      testWidgets(
        reducido
            ? 'chip con movimiento reducido: cambia de golpe'
            : 'chip: el color y el borde cambian en 150 ms',
        (tester) async {
          final elegido = ValueNotifier(false);
          addTearDown(elegido.dispose);
          await armar(
            tester,
            ValueListenableBuilder<bool>(
              valueListenable: elegido,
              builder: (context, valor, _) => ChipFiltro(
                texto: 'Aulas',
                seleccionado: valor,
                alCambiar: (_) {},
              ),
            ),
            sinAnimaciones: reducido,
          );
          Color relleno() => relieveDe(tester, find.byType(ChipFiltro)).color;
          Color texto() =>
              tester.widget<Text>(find.text('Aulas')).style!.color!;
          expect(relleno(), ColoresApp.superficie);
          elegido.value = true;
          await tester.pump();
          if (!reducido) {
            await tester.pump(const Duration(milliseconds: 75));
            expect(relleno(), isNot(ColoresApp.superficie));
            expect(relleno(), isNot(ColoresApp.acento));
            expect(texto(), isNot(ColoresApp.textoSobreAcento));
            await tester.pump(const Duration(milliseconds: 75));
          }
          // El mismo final, con o sin movimiento reducido.
          expect(relleno(), ColoresApp.acento);
          expect(texto(), ColoresApp.textoSobreAcento);
          expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        },
      );
    }

    testWidgets('pestaña: el ícono pasa a relleno y el color a acento en '
        '150 ms', (tester) async {
      final activa = ValueNotifier(0);
      addTearDown(activa.dispose);
      await armar(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: activa,
          builder: (context, i, _) => BarraInferior(
            pestanas: const [
              PestanaBarra(
                icono: Icons.explore_rounded,
                iconoInactivo: Icons.explore_outlined,
                texto: 'Navegar',
              ),
              PestanaBarra(
                icono: Icons.map_rounded,
                iconoInactivo: Icons.map_outlined,
                texto: 'Mapas',
              ),
            ],
            seleccionada: i,
            alCambiar: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      activa.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      // Los dos íconos a la vez (el fundido) y el color a mitad de camino.
      expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      expect(find.byIcon(Icons.map_rounded), findsOneWidget);
      final color = tester.widget<Icon>(find.byIcon(Icons.map_rounded)).color;
      expect(color, isNot(ColoresApp.acento));
      expect(color, isNot(ColoresApp.textoSecundario));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      expect(find.byIcon(Icons.map_outlined), findsNothing);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.map_rounded)).color,
        ColoresApp.acento,
      );
    });

    for (final reducido in [false, true]) {
      testWidgets(
        reducido
            ? 'interruptor con movimiento reducido: el pulgar salta'
            : 'interruptor: el pulgar cruza en 150 ms',
        (tester) async {
          final prendido = ValueNotifier(false);
          addTearDown(prendido.dispose);
          await armar(
            tester,
            ValueListenableBuilder<bool>(
              valueListenable: prendido,
              builder: (context, valor, _) => GrupoFilas(
                filas: [
                  FilaGrupo.interruptor(
                    titulo: 'Reducir movimiento',
                    valor: valor,
                    alCambiar: (v) => prendido.value = v,
                  ),
                ],
              ),
            ),
            sinAnimaciones: reducido,
          );
          final interruptor = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_Interruptor',
          );
          final pulgar = find
              .descendant(
                of: interruptor,
                matching: find.byType(AnimatedContainer),
              )
              .last;
          double x() =>
              tester.getCenter(pulgar).dx - tester.getTopLeft(interruptor).dx;
          // Apagado, a 16 dp de la punta de la pista; prendido, a 36.
          expect(x(), moreOrLessEquals(16));
          await tester.tap(find.text('Reducir movimiento'));
          await tester.pump();
          if (!reducido) {
            await tester.pump(const Duration(milliseconds: 75));
            expect(x(), inExclusiveRange(16, 36));
          }
          await tester.pumpAndSettle();
          expect(x(), moreOrLessEquals(36));
          expect(prendido.value, isTrue);
        },
      );
    }
  });

  // ── Entre pantallas ─────────────────────────────────────────────────────

  group('entre pantallas', () {
    Widget abridor() => Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(
          RutaApp<void>(
            builder: (context) => Scaffold(
              appBar: const BarraSuperior(titulo: 'Nueva'),
              body: const Center(child: Text('Contenido nuevo')),
            ),
          ),
        ),
        child: const Text('Abrir'),
      ),
    );

    /// Cuánto está corrida y qué tan visible está la pantalla nueva.
    (double, double) pagina(WidgetTester tester) {
      final texto = find.text('Contenido nuevo');
      final transicion = find.ancestor(
        of: texto,
        matching: find.byType(FadeTransition),
      );
      final opacidad = tester
          .widget<FadeTransition>(transicion.first)
          .opacity
          .value;
      final corrida = tester.getTopLeft(find.byType(Scaffold).last).dx;
      return (corrida, opacidad);
    }

    testWidgets('adelante: entra 24 dp desde el costado con un fundido, en '
        '260 ms; atrás, en 200 ms', (tester) async {
      await armar(tester, abridor());
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump();
      var (corrida, opacidad) = pagina(tester);
      expect(corrida, moreOrLessEquals(MovimientoApp.desplazamientoPantalla));
      expect(opacidad, 0);
      await tester.pump(const Duration(milliseconds: 130));
      (corrida, opacidad) = pagina(tester);
      expect(corrida, inExclusiveRange(0, 24));
      expect(opacidad, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 130));
      (corrida, opacidad) = pagina(tester);
      expect(corrida, 0);
      expect(opacidad, 1);

      // Atrás: igual, al revés, en 200 ms.
      await tester.tap(find.byTooltip('Volver'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      (corrida, opacidad) = pagina(tester);
      expect(corrida, inExclusiveRange(0, 24));
      expect(opacidad, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      (corrida, opacidad) = pagina(tester);
      expect(corrida, moreOrLessEquals(MovimientoApp.desplazamientoPantalla));
      expect(opacidad, 0);
      await tester.pumpAndSettle();
      expect(find.text('Contenido nuevo'), findsNothing);
    });

    testWidgets('con «Quitar animaciones» del teléfono: un fundido de 120 ms, '
        'sin desplazamiento', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await armar(tester, abridor());
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump();
      var (corrida, opacidad) = pagina(tester);
      expect(corrida, 0);
      expect(opacidad, 0);
      await tester.pump(const Duration(milliseconds: 60));
      (corrida, opacidad) = pagina(tester);
      expect(corrida, 0);
      expect(opacidad, moreOrLessEquals(0.5, epsilon: 0.01));
      await tester.pump(const Duration(milliseconds: 60));
      (corrida, opacidad) = pagina(tester);
      expect(opacidad, 1);
    });

    testWidgets('con «Reducir movimiento» de Ajustes, también', (tester) async {
      await AjustesMovimiento.instancia.cambiarReducirMovimiento(true);
      await armar(tester, abridor());
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump();
      final (corrida, opacidad) = pagina(tester);
      expect(corrida, 0);
      expect(opacidad, 0);
      await tester.pump(MovimientoApp.fundidoReducido);
      expect(pagina(tester).$2, 1);
    });
  });

  // ── Hoja inferior ───────────────────────────────────────────────────────

  group('hoja inferior', () {
    Widget abridor() => Builder(
      builder: (context) => TextButton(
        onPressed: () => mostrarHoja<void>(
          context,
          titulo: 'Nuevo lugar',
          contenido: (_) => const Text('Contenido de la hoja'),
        ),
        child: const Text('Abrir'),
      ),
    );

    double arriba(WidgetTester tester) =>
        tester.getTopLeft(find.text('Nuevo lugar')).dy;

    Color velo(WidgetTester tester) => tester
        .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier).last)
        .color
        .value!;

    testWidgets('sube en 300 ms con su curva y el fondo se oscurece; baja en '
        '200 ms', (tester) async {
      await armar(tester, abridor());
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      final abajo = arriba(tester);
      expect(velo(tester).a, 0);
      await tester.pump(const Duration(milliseconds: 150));
      final medio = arriba(tester);
      expect(velo(tester).a, inExclusiveRange(0, ColoresApp.velo.a));
      await tester.pump(const Duration(milliseconds: 150));
      final lugar = arriba(tester);
      expect(lugar, lessThan(medio));
      expect(medio, lessThan(abajo));
      // A mitad de tiempo, lo que dice la curva de la hoja.
      expect(
        (abajo - medio) / (abajo - lugar),
        moreOrLessEquals(MovimientoApp.curvaHoja.transform(0.5), epsilon: 0.01),
      );
      expect(velo(tester), ColoresApp.velo);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(arriba(tester), greaterThan(lugar));
      await tester.pump(const Duration(milliseconds: 100));
      // A los 200 ms ya bajó del todo.
      expect(arriba(tester), moreOrLessEquals(abajo));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo lugar'), findsNothing);
    });

    testWidgets('con movimiento reducido: un fundido de 120 ms, sin subir', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await armar(tester, abridor());
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      double opacidad() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.text('Nuevo lugar'),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      final lugar = arriba(tester);
      expect(opacidad(), 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(arriba(tester), lugar);
      expect(opacidad(), moreOrLessEquals(0.5, epsilon: 0.01));
      await tester.pump(const Duration(milliseconds: 60));
      expect(arriba(tester), lugar);
      expect(opacidad(), 1);
    });

    testWidgets('arrastrada un poco vuelve a su lugar; tirada hacia abajo, '
        'se cierra', (tester) async {
      await armar(tester, abridor());
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final lugar = arriba(tester);
      await tester.timedDrag(
        find.text('Nuevo lugar'),
        const Offset(0, 30),
        const Duration(milliseconds: 300),
      );
      await tester.pump();
      expect(arriba(tester), greaterThan(lugar));
      await tester.pumpAndSettle();
      expect(arriba(tester), moreOrLessEquals(lugar));
      expect(find.text('Nuevo lugar'), findsOneWidget);

      await tester.timedDrag(
        find.text('Nuevo lugar'),
        const Offset(0, 300),
        const Duration(milliseconds: 150),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nuevo lugar'), findsNothing);
    });
  });

  // ── Cabezal ─────────────────────────────────────────────────────────────

  group('cabezal', () {
    testWidgets('sigue la posición con τ = 80 ms, sin pasarse', (tester) async {
      final m = MovimientoCabezal(vsync: const TestVSync());
      addTearDown(m.dispose);
      final vistos = <double>[];
      m.addListener(() => vistos.add(m.valor));
      m.seguir(100);
      await tester.pump(); // arranca el reloj
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      // A los 80 ms, el 63 % (1 − e^−1).
      expect(m.valor, moreOrLessEquals(100 * (1 - math.exp(-1)), epsilon: 0.5));
      await tester.pumpAndSettle();
      expect(m.valor, 100);
      expect(m.enMovimiento, isFalse);
      // Siempre hacia adelante y nunca más allá.
      for (var i = 1; i < vistos.length; i++) {
        expect(vistos[i], greaterThanOrEqualTo(vistos[i - 1]));
        expect(vistos[i], lessThanOrEqualTo(100));
      }
    });

    testWidgets('al cambiar de tramo recorre en 350 ms con su curva; si llega '
        'otra posición, termina y la sigue', (tester) async {
      final m = MovimientoCabezal(vsync: const TestVSync());
      addTearDown(m.dispose);
      m.recorrerHasta(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));
      expect(
        m.valor,
        moreOrLessEquals(
          100 * MovimientoApp.curvaCabezal.transform(0.5),
          epsilon: 0.01,
        ),
      );
      m.seguir(110);
      await tester.pump(const Duration(milliseconds: 175));
      expect(m.valor, 100);
      expect(m.enMovimiento, isTrue);
      await tester.pumpAndSettle();
      expect(m.valor, 110);
    });

    testWidgets(
      'interrumpido por otro cambio de tramo, sigue desde donde está',
      (tester) async {
        final m = MovimientoCabezal(vsync: const TestVSync());
        addTearDown(m.dispose);
        m.recorrerHasta(100);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final antes = m.valor;
        expect(antes, inExclusiveRange(0, 100));
        m.recorrerHasta(200);
        await tester.pump();
        expect(m.valor, moreOrLessEquals(antes, epsilon: 1e-9));
        await tester.pump(MovimientoApp.cabezalTramo);
        expect(m.valor, 200);
      },
    );

    testWidgets('después de un rato sin cuadros (en segundo plano), el primer '
        'cuadro lo deja en el final', (tester) async {
      final m = MovimientoCabezal(vsync: const TestVSync());
      addTearDown(m.dispose);
      m.recorrerHasta(100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      m.seguir(120);
      // Un solo cuadro después de 3 s: termina el recorrido y llega a la
      // última posición.
      await tester.pump(const Duration(seconds: 3));
      expect(m.valor, 120);
      expect(m.enMovimiento, isFalse);
    });

    // Una L en 300 × 300: 240 dp a la derecha y 240 hacia abajo.
    const ele = [
      TramoRuta(metros: 24, puntos: [Offset(0.1, 0.5), Offset(0.9, 0.5)]),
      TramoRuta(
        metros: 24,
        marca: MarcaTramo.destino,
        puntos: [Offset(0.9, 0.5), Offset(0.9, 1.3)],
      ),
    ];

    Future<ValueNotifier<(int, double)>> armarRuta(
      WidgetTester tester, {
      required int tramo,
      required double avance,
      bool sinAnimaciones = false,
    }) async {
      final estado = ValueNotifier<(int, double)>((tramo, avance));
      addTearDown(estado.dispose);
      await armar(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 300,
            child: ValueListenableBuilder<(int, double)>(
              valueListenable: estado,
              builder: (context, e, _) =>
                  LineaRuta(tramos: ele, tramoActual: e.$1, avance: e.$2),
            ),
          ),
        ),
        enLista: false,
        sinAnimaciones: sinAnimaciones,
      );
      return estado;
    }

    /// El dibujo del cabezal (la luz, la sombra y el relleno): el relleno
    /// contiene [en] y no los puntos de [no].
    void cabezalEn(
      WidgetTester tester,
      Offset en, {
      List<Offset> no = const [],
    }) {
      final capa = find
          .descendant(
            of: find.byType(LineaRuta),
            matching: find.byType(CustomPaint),
          )
          .last;
      expect(
        tester.renderObject(capa),
        paints
          ..path(color: ColoresApp.sombraClara)
          ..path(color: ColoresApp.sombraOscura)
          ..path(color: ColoresApp.superficie, includes: [en], excludes: no),
      );
    }

    testWidgets('sobre la línea de ruta, el cabezal sigue la posición', (
      tester,
    ) async {
      final estado = await armarRuta(tester, tramo: 0, avance: 0);
      cabezalEn(tester, const Offset(30, 150));
      estado.value = (0, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // Ya salió, pero todavía no llegó.
      cabezalEn(tester, const Offset(66, 150), no: [const Offset(270, 150)]);
      await tester.pumpAndSettle();
      cabezalEn(tester, const Offset(270, 150), no: [const Offset(240, 150)]);
    });

    testWidgets('al cambiar de tramo recorre la ruta (dobla en la esquina), '
        'y los tramos cambian de color en 300 ms', (tester) async {
      final estado = await armarRuta(tester, tramo: 0, avance: 0.9);
      estado.value = (1, 0.5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));
      // A mitad de tiempo, lo que dice la curva del cabezal, medido POR LA
      // RUTA: de 216 dp (en el primer tramo) a 360 (a mitad del segundo).
      // Ya dobló la esquina (270, 150); no va por la recta que la corta.
      final p = MovimientoApp.curvaCabezal.transform(0.5);
      final recorrido = 216 + (360 - 216) * p;
      final enLaRuta = recorrido <= 240
          ? Offset(30 + recorrido, 150)
          : Offset(270, 150 + recorrido - 240);
      final enLaRecta = Offset.lerp(
        const Offset(246, 150),
        const Offset(270, 270),
        p,
      )!;
      expect((enLaRuta - enLaRecta).distance, greaterThan(12));
      cabezalEn(tester, enLaRuta, no: [enLaRecta]);
      // El tramo que se completa, entre el acento y el verde.
      final ruta = find
          .descendant(
            of: find.byType(LineaRuta),
            matching: find.byType(CustomPaint),
          )
          .first;
      expect(
        tester.renderObject(ruta),
        paints..something((metodo, argumentos) {
          if (metodo != #drawPath) return false;
          final color = (argumentos[1] as Paint).color;
          return color != ColoresApp.acento &&
              color != ColoresApp.hecho &&
              color != ColoresApp.siguiente &&
              color != ColoresApp.rutaRanura &&
              color != ColoresApp.planoHabitacion;
        }),
      );
      await tester.pumpAndSettle();
      cabezalEn(tester, const Offset(270, 270));
      expect(
        tester.renderObject(ruta),
        paints
          ..path(color: ColoresApp.rutaRanura)
          ..path(color: ColoresApp.rutaRanura)
          ..path(color: ColoresApp.hecho, strokeWidth: FormasApp.grosorRuta)
          ..path(
            color: ColoresApp.acento,
            strokeWidth: FormasApp.grosorRutaActual,
          ),
      );
    });

    testWidgets('con movimiento reducido, el cabezal y los colores saltan', (
      tester,
    ) async {
      final estado = await armarRuta(
        tester,
        tramo: 0,
        avance: 0.9,
        sinAnimaciones: true,
      );
      estado.value = (1, 0.5);
      await tester.pump();
      cabezalEn(tester, const Offset(270, 270));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('en la línea de tiempo: el segmento actual se ensancha en '
        '250 ms y el cabezal recorre la pista', (tester) async {
      final tramo = ValueNotifier(0);
      addTearDown(tramo.dispose);
      await armar(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: tramo,
          builder: (context, t, _) =>
              LineaTiempo(tramos: ele, tramoActual: t, avance: 0.5),
        ),
      );
      final cabezal = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is DecoracionRelieve &&
            (w.decoration as DecoracionRelieve).circulo,
      );
      List<double> altos() => [
        for (final p in tester.widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(LineaTiempo),
            matching: find.byType(CustomPaint),
          ),
        ))
          if (p.painter != null) tester.getSize(find.byWidget(p)).height,
      ];
      final x0 = tester.getCenter(cabezal).dx;
      expect(altos(), [
        FormasApp.segmentoTiempoActual,
        FormasApp.segmentoTiempo,
      ]);
      tramo.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      for (final alto in altos()) {
        expect(
          alto,
          inExclusiveRange(
            FormasApp.segmentoTiempo,
            FormasApp.segmentoTiempoActual,
          ),
        );
      }
      final xMedio = tester.getCenter(cabezal).dx;
      await tester.pumpAndSettle();
      final x1 = tester.getCenter(cabezal).dx;
      expect(xMedio, inExclusiveRange(x0, x1));
      expect(altos(), [
        FormasApp.segmentoTiempo,
        FormasApp.segmentoTiempoActual,
      ]);
    });
  });

  // ── Progreso ────────────────────────────────────────────────────────────

  group('progreso', () {
    double avance(WidgetTester tester) {
      final pintor =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(BarraProgreso),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter
              // ignore: avoid_dynamic_calls
              as dynamic;
      // ignore: avoid_dynamic_calls
      return (pintor.avance as Animation<double>).value;
    }

    testWidgets('se llena al aparecer en 400 ms, sin que el número cuente', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await armar(
        tester,
        const BarraProgreso(valor: 0.5, etiqueta: 'Descarga'),
      );
      expect(avance(tester), 0);
      // TalkBack dice el valor final desde el principio.
      expect(
        tester.getSemantics(find.byType(BarraProgreso)),
        isSemantics(label: 'Descarga', value: textoPorcentaje(0.5)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(avance(tester), inExclusiveRange(0, 0.5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(avance(tester), 0.5);
      semantica.dispose();
    });

    testWidgets('con movimiento reducido aparece lleno; un cambio tarda '
        '120 ms (o salta)', (tester) async {
      final valor = ValueNotifier(0.5);
      addTearDown(valor.dispose);
      await armar(
        tester,
        ValueListenableBuilder<double>(
          valueListenable: valor,
          builder: (context, v, _) => BarraProgreso(valor: v),
        ),
        sinAnimaciones: true,
      );
      expect(avance(tester), 0.5);
      valor.value = 0.8;
      await tester.pump();
      expect(avance(tester), 0.8);
    });

    testWidgets('después de aparecer, un cambio tarda 120 ms', (tester) async {
      final valor = ValueNotifier(0.5);
      addTearDown(valor.dispose);
      await armar(
        tester,
        ValueListenableBuilder<double>(
          valueListenable: valor,
          builder: (context, v, _) => BarraProgreso(valor: v),
        ),
      );
      await tester.pumpAndSettle();
      valor.value = 0.8;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(avance(tester), inExclusiveRange(0.5, 0.8));
      await tester.pump(const Duration(milliseconds: 60));
      expect(avance(tester), moreOrLessEquals(0.8));
    });
  });

  // ── Movimiento reducido y vibración ─────────────────────────────────────

  group('ajustes de movimiento', () {
    test('se guardan en el teléfono y se leen al volver', () async {
      final a = AjustesMovimiento.nueva();
      expect(a.reducirMovimiento, isFalse);
      expect(a.vibracion, isTrue);
      await a.cambiarReducirMovimiento(true);
      await a.cambiarVibracion(false);
      final b = AjustesMovimiento.nueva();
      await b.cargar();
      expect(b.reducirMovimiento, isTrue);
      expect(b.vibracion, isFalse);
    });

    testWidgets('el envoltorio suma «Reducir movimiento» al del teléfono, al '
        'instante, y pone el tema nuevo', (tester) async {
      String leer(BuildContext context) =>
          MediaQuery.disableAnimationsOf(context) ? 'reducido' : 'normal';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Column(
            children: [
              AmbienteDiseno(
                child: Builder(
                  builder: (context) => Column(
                    children: [
                      Text('Adentro: ${leer(context)}'),
                      Text(
                        Theme.of(context).extension<EstiloApp>() == null
                            ? 'sin tema'
                            : 'con tema',
                      ),
                    ],
                  ),
                ),
              ),
              // Sin envoltorio, MovimientoApp.reducido lo lee directo.
              Builder(
                builder: (context) => Text(
                  'Afuera: ${MovimientoApp.reducido(context) ? 'reducido' : 'normal'}',
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.text('Adentro: normal'), findsOneWidget);
      expect(find.text('con tema'), findsOneWidget);
      await AjustesMovimiento.instancia.cambiarReducirMovimiento(true);
      await tester.pump();
      expect(find.text('Adentro: reducido'), findsOneWidget);
      // El de afuera no se vuelve a armar solo, pero pregunta bien.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Text(
              'Afuera: ${MovimientoApp.reducido(context) ? 'reducido' : 'normal'}',
            ),
          ),
        ),
      );
      expect(find.text('Afuera: reducido'), findsOneWidget);
    });

    testWidgets('la vibración sale con la fuerza pedida y el interruptor la '
        'apaga', (tester) async {
      final vibraciones = escucharVibraciones(tester);
      await HapticaApp.cambioDeTramo();
      await HapticaApp.llegada();
      await HapticaApp.media();
      await HapticaApp.fuerte();
      expect(vibraciones, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
      vibraciones.clear();
      await AjustesMovimiento.instancia.cambiarVibracion(false);
      await HapticaApp.cambioDeTramo();
      await HapticaApp.fuerte();
      expect(vibraciones, isEmpty);
    });
  });

  // ── Pantallas ───────────────────────────────────────────────────────────

  group('pantallas', () {
    testWidgets('Ajustes: los interruptores cambian el movimiento y la '
        'vibración, y TalkBack los lee', (tester) async {
      final semantica = tester.ensureSemantics();
      final vibraciones = escucharVibraciones(tester);
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // Como en la app: el MaterialApp con el tema de antes.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(primarySwatch: Colors.indigo),
          home: const PantallaAjustes(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Reducir movimiento')),
        isSemantics(
          label: 'Reducir movimiento\nSin deslizamientos, escalas ni resortes',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      expect(find.text('Ajustes de voz'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(find.text('Reducir movimiento'));
      await tester.pumpAndSettle();
      expect(AjustesMovimiento.instancia.reducirMovimiento, isTrue);
      expect(
        tester.getSemantics(find.text('Reducir movimiento')),
        isSemantics(hasToggledState: true, isToggled: true),
      );

      // Apagar la vibración no vibra; prenderla, una vez de prueba.
      await tester.tap(find.text('Vibración'));
      await tester.pumpAndSettle();
      expect(AjustesMovimiento.instancia.vibracion, isFalse);
      expect(vibraciones, isEmpty);
      await tester.tap(find.text('Vibración'));
      await tester.pumpAndSettle();
      expect(AjustesMovimiento.instancia.vibracion, isTrue);
      expect(vibraciones, ['HapticFeedbackType.mediumImpact']);
      semantica.dispose();
    });

    testWidgets('Ajustes con la letra al 200 %: sin desbordes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(primarySwatch: Colors.indigo),
          home: const PantallaAjustes(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Vibración'), findsOneWidget);
    });

    testWidgets('la simulación de la navegación: vibración suave al cambiar '
        'de tramo, media al llegar, y el aviso con un fundido', (tester) async {
      final vibraciones = escucharVibraciones(tester);
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaBlindRoute.oscuro,
          home: const PantallaNavegacionEjemplo(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Simular el recorrido'));
      await tester.pump();
      expect(find.byTooltip('Pausar la simulación'), findsOneWidget);
      var pasos = 0;
      while (find.text('Llegaste a Aula 12').evaluate().isEmpty && pasos < 40) {
        await tester.pump(PantallaNavegacionEjemplo.intervaloSimulacion);
        pasos++;
      }
      expect(vibraciones, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
      // El aviso entra con un fundido de 200 ms.
      await tester.pump(const Duration(milliseconds: 100));
      final fundido = tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.text('Llegaste a Aula 12'),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(fundido, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.text('Girá a la izquierda'), findsNothing);
      // El cabezal se queda en el destino.
      expect(
        tester.getSemantics(find.byType(LineaRuta)),
        isSemantics(label: 'Tramo 3 de 3, 0 metros, Aula 12'),
      );
      expect(find.byTooltip('Volver a empezar el recorrido'), findsOneWidget);
      semantica.dispose();
    });
  });
}
