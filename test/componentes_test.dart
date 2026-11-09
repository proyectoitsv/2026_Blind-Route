import 'package:blindroute/design/design.dart';
import 'package:blindroute/design/galeria_componentes.dart';
import 'package:blindroute/design/galeria_pantallas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COMPONENTES DEL SISTEMA DE DISEÑO (fases 2 y 3 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// Lo que tiene que cumplir cada componente para ser accesible: área táctil
// de 48 dp, semántica para TalkBack, nada roto con la letra al 200 % (lineal,
// más exigente que el 200 % de Android 14) y, con "Quitar animaciones", sin
// resorte ni achique. También la paleta de la v5 del prompt, con el
// contraste anotado en colores.dart, el relieve (levantado y hundido, con las
// medidas de CSS), la línea de ruta sobre el plano y la línea de tiempo.
// Desde la fase 3 los cambios de estado se animan: donde importa el estado
// final, se espera a que termine (pumpAndSettle). Los tiempos y las curvas
// de cada animación se prueban en animaciones_test.dart.
//
// En los tests la letra es la de prueba de Flutter (cada letra, un cuadrado
// de 1 em), más ancha que Inter: si acá no se desborda, en el teléfono menos.

/// Contraste WCAG 2.x entre dos colores opacos.
double contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
  return (claro + 0.05) / (oscuro + 0.05);
}

/// Arma [hijo] en un teléfono de 360 × 780 dp, con el tema nuevo y la letra
/// en [escala].
Future<void> armar(
  WidgetTester tester,
  Widget hijo, {
  double escala = 1,
  bool sinAnimaciones = false,
  ThemeData? tema,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: tema ?? TemaBlindRoute.oscuro,
      builder: (context, navegador) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(escala),
          disableAnimations: sinAnimaciones,
        ),
        child: navegador!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(EspaciadoApp.margenLateral),
          children: [hijo],
        ),
      ),
    ),
  );
}

/// Las decoraciones con relieve debajo de [de], en orden.
List<DecoracionRelieve> relieves(WidgetTester tester, Finder de) => [
  for (final w in tester.widgetList<DecoratedBox>(
    find.descendant(
      of: de,
      matching: find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.decoration is DecoracionRelieve,
      ),
    ),
  ))
    w.decoration as DecoracionRelieve,
];

/// La primera decoración con relieve debajo de [de].
DecoracionRelieve relieveDe(WidgetTester tester, Finder de) =>
    relieves(tester, de).first;

void main() {
  // Los ajustes de movimiento, de fábrica y sin leer el teléfono de verdad.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AjustesMovimiento.instancia.reiniciarParaTests();
  });

  // ── Paleta y relieve ────────────────────────────────────────────────────

  group('paleta y relieve', () {
    test('los valores son los de la tabla del prompt', () {
      expect(ColoresApp.fondo, const Color(0xFF1A1F29));
      expect(ColoresApp.superficie, const Color(0xFF222835));
      expect(ColoresApp.hundido, ColoresApp.fondo);
      expect(ColoresApp.sombraOscura, const Color(0xFF12161E));
      expect(ColoresApp.sombraClara, const Color(0xFF262D3B));
      expect(ColoresApp.borde, const Color(0xFF7A8594));
      expect(ColoresApp.textoPrincipal, const Color(0xFFF5F8FC));
      expect(ColoresApp.textoSecundario, const Color(0xFFC3CCD9));
      expect(ColoresApp.acento, const Color(0xFF29D9FF));
      expect(ColoresApp.textoSobreAcento, const Color(0xFF0B0E13));
      expect(ColoresApp.hecho, const Color(0xFF3DF5B0));
      expect(ColoresApp.siguiente, const Color(0xFFB79CFF));
      expect(ColoresApp.advertencia, const Color(0xFFFFC857));
      expect(ColoresApp.error, const Color(0xFFFF6B6B));
      expect(ColoresApp.planoCorredor, const Color(0xFF161B24));
      expect(ColoresApp.planoHabitacion, const Color(0xFF1F2631));
      expect(ColoresApp.planoMuro, const Color(0xFF6E7A8C));
      expect(ColoresApp.planoTexto, const Color(0xFFA7B1BF));
      expect(ColoresApp.rutaRanura, const Color(0xFF0E1218));
    });

    test('la paleta pasa los mínimos', () {
      for (final fondo in [ColoresApp.fondo, ColoresApp.superficie]) {
        // Los dos textos pasan 7:1: sirven también para texto importante.
        expect(
          contraste(ColoresApp.textoPrincipal, fondo),
          greaterThanOrEqualTo(7),
        );
        expect(
          contraste(ColoresApp.textoSecundario, fondo),
          greaterThanOrEqualTo(7),
        );
        for (final color in [
          ColoresApp.acento,
          ColoresApp.advertencia,
          ColoresApp.error,
        ]) {
          expect(contraste(color, fondo), greaterThanOrEqualTo(4.5));
        }
        expect(contraste(ColoresApp.borde, fondo), greaterThanOrEqualTo(3));
      }
      expect(
        contraste(ColoresApp.textoSobreAcento, ColoresApp.acento),
        greaterThanOrEqualTo(7),
      );
      // La ruta, contra todo lo que puede tener debajo en el plano.
      for (final fondo in [
        ColoresApp.planoCorredor,
        ColoresApp.planoHabitacion,
        ColoresApp.rutaRanura,
        ColoresApp.hundido,
      ]) {
        for (final color in [
          ColoresApp.hecho,
          ColoresApp.siguiente,
          ColoresApp.acento,
        ]) {
          expect(contraste(color, fondo), greaterThanOrEqualTo(3));
        }
      }
      // Los muros, sobre los tres fondos que los rodean; los nombres de las
      // salas, como texto importante.
      for (final fondo in [
        ColoresApp.planoCorredor,
        ColoresApp.planoHabitacion,
        ColoresApp.fondo,
      ]) {
        expect(contraste(ColoresApp.planoMuro, fondo), greaterThanOrEqualTo(3));
      }
      expect(
        contraste(ColoresApp.planoTexto, ColoresApp.planoHabitacion),
        greaterThanOrEqualTo(7),
      );
      // El relieve solo no llega a 3:1: por eso los controles llevan borde.
      expect(contraste(ColoresApp.superficie, ColoresApp.fondo), lessThan(3));
    });

    test('el relieve tiene las medidas de CSS (sigma = desenfoque / 2)', () {
      expect(RelieveApp.levantado.desplazamiento, 6);
      expect(RelieveApp.levantado.desenfoque, 12);
      expect(RelieveApp.levantado.sigma, 6);
      expect(RelieveApp.levantado.alcance, 18);
      expect(RelieveApp.levantadoChico.desplazamiento, 4);
      expect(RelieveApp.levantadoChico.desenfoque, 8);
      expect(RelieveApp.hundido.desplazamiento, 4);
      expect(RelieveApp.hundido.desenfoque, 8);
      expect(RelieveApp.hundidoChico.desplazamiento, 2);
      expect(RelieveApp.hundidoChico.desenfoque, 4);
      expect(
        RelieveApp.sombra(levantado: false, tamano: TamanoRelieve.chico),
        same(RelieveApp.hundidoChico),
      );
    });

    test('de levantado a hundido pasa por plano', () {
      const levantado = DecoracionRelieve(color: ColoresApp.superficie);
      const hundido = DecoracionRelieve(
        color: ColoresApp.hundido,
        elevacion: -1,
      );
      expect(DecoracionRelieve.lerp(levantado, hundido, 0)!.elevacion, 1);
      expect(DecoracionRelieve.lerp(levantado, hundido, 0.5)!.elevacion, 0);
      expect(DecoracionRelieve.lerp(levantado, hundido, 1)!.elevacion, -1);
      expect(
        DecoracionRelieve.lerp(levantado, hundido, 1)!.color,
        ColoresApp.hundido,
      );
      // Desde nada, aparece de a poco.
      expect(DecoracionRelieve.lerp(null, levantado, 0.25)!.elevacion, 0.25);
    });

    testWidgets('levantado: sombras afuera; hundido: sombras adentro', (
      tester,
    ) async {
      const clave = Key('relieve');
      Future<RenderObject> con(DecoracionRelieve d) async {
        await armar(
          tester,
          Center(
            child: DecoratedBox(
              key: clave,
              decoration: d,
              child: const SizedBox(width: 100, height: 50),
            ),
          ),
        );
        return tester.renderObject(find.byKey(clave));
      }

      final levantado = await con(
        const DecoracionRelieve(color: ColoresApp.superficie),
      );
      // La luz, la oscura encima y el relleno sobre las dos.
      expect(
        levantado,
        paints
          ..path(color: ColoresApp.sombraClara)
          ..path(color: ColoresApp.sombraOscura)
          ..path(color: ColoresApp.superficie),
      );
      expect(levantado, isNot(paints..clipPath()));

      final hundido = await con(
        const DecoracionRelieve(color: ColoresApp.hundido, elevacion: -1),
      );
      // El relleno y, recortadas a la forma, la luz y la oscura.
      expect(
        hundido,
        paints
          ..path(color: ColoresApp.hundido)
          ..clipPath()
          ..path(color: ColoresApp.sombraClara)
          ..clipPath()
          ..path(color: ColoresApp.sombraOscura),
      );
    });

    test('el tema: sin onda, capa tenue y sin verde ni violeta', () {
      final tema = TemaBlindRoute.oscuro;
      expect(tema.splashFactory, same(NoSplash.splashFactory));
      expect(
        tema.highlightColor,
        ColoresApp.acento.withValues(alpha: ColoresApp.opacidadPresion),
      );
      final esquema = tema.colorScheme;
      for (final color in [
        esquema.primary,
        esquema.secondary,
        esquema.tertiary,
      ]) {
        expect(color, ColoresApp.acento);
      }
      expect(tema.scaffoldBackgroundColor, ColoresApp.fondo);
      expect(tema.extension<EstiloApp>(), same(EstiloApp.oscuro));
    });
  });

  // ── Botones ─────────────────────────────────────────────────────────────

  group('botones', () {
    testWidgets('el principal: acento plano, levantado, 52 de alto', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      var veces = 0;
      await armar(
        tester,
        BotonPrincipal(
          texto: 'Comenzar a navegar',
          icono: Icons.navigation_rounded,
          alPresionar: () => veces++,
        ),
      );
      final boton = find.byType(BotonPrincipal);
      expect(tester.getSize(boton).height, greaterThanOrEqualTo(52));
      final d = relieveDe(tester, boton);
      expect(d.color, ColoresApp.acento);
      expect(d.elevacion, 1);
      // El acento ya pasa 3:1 contra el fondo: sin el borde gris.
      expect(d.borde, BorderSide.none);
      final estilo = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(estilo.style!.textStyle!.resolve({})!.fontWeight, FontWeight.w500);
      expect(
        estilo.style!.foregroundColor!.resolve({}),
        ColoresApp.textoSobreAcento,
      );
      expect(
        tester.getSemantics(find.byType(FilledButton)),
        isSemantics(
          label: 'Comenzar a navegar',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(boton);
      expect(veces, 1);
      semantica.dispose();
    });

    testWidgets('deshabilitado queda plano y se sigue leyendo', (tester) async {
      await armar(
        tester,
        const BotonPrincipal(texto: 'Descargar', alPresionar: null),
      );
      final d = relieveDe(tester, find.byType(BotonPrincipal));
      expect(d.elevacion, 0);
      expect(d.color, ColoresApp.superficie);
      final estilo = tester.widget<FilledButton>(find.byType(FilledButton));
      final texto = estilo.style!.foregroundColor!.resolve({
        WidgetState.disabled,
      });
      expect(texto, ColoresApp.textoSecundario);
      expect(
        contraste(texto!, ColoresApp.superficie),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('el principal grande: llena el lugar, acento levantado con '
        'radio 20, y TalkBack lee el texto sin la aclaración', (tester) async {
      final semantica = tester.ensureSemantics();
      var veces = 0;
      await armar(
        tester,
        SizedBox(
          height: 400,
          child: BotonPrincipalGrande(
            icono: Icons.explore_rounded,
            texto: 'Comenzar a navegar',
            detalle: 'Tocá para comenzar',
            alPresionar: () => veces++,
          ),
        ),
      );
      final boton = find.byType(BotonPrincipalGrande);
      expect(tester.getSize(boton).height, 400);
      final d = relieveDe(tester, boton);
      expect(d.color, ColoresApp.acento);
      expect(d.elevacion, 1);
      expect(d.radio, FormasApp.bordeTarjeta);
      expect(d.borde, BorderSide.none);
      // El ícono y los textos, del color del texto del botón (11,47 sobre el
      // acento).
      final icono = find.byIcon(Icons.explore_rounded);
      expect(tester.widget<Icon>(icono).size, FormasApp.iconoGrande);
      expect(
        IconTheme.of(tester.element(icono)).color,
        ColoresApp.textoSobreAcento,
      );
      final titulo = tester
          .renderObject<RenderParagraph>(find.text('Comenzar a navegar'))
          .text
          .style!;
      expect(titulo.color, ColoresApp.textoSobreAcento);
      expect(titulo.fontSize, TipografiaApp.titulo.fontSize);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Tocá para comenzar'))
            .text
            .style!
            .color,
        ColoresApp.textoSobreAcento,
      );
      expect(
        tester.getSemantics(find.byType(FilledButton)),
        isSemantics(
          label: 'Comenzar a navegar',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Tocá')), findsNothing);
      await tester.tap(boton);
      expect(veces, 1);
      semantica.dispose();
    });

    for (final reducido in [false, true]) {
      testWidgets('el principal grande presionado se hunde sin la luz'
          '${reducido ? '; con movimiento reducido, sin achicarse' : ' y se '
                    'achica a 0,97'}', (tester) async {
        await armar(
          tester,
          BotonPrincipalGrande(
            icono: Icons.explore_rounded,
            texto: 'Comenzar a navegar',
            alPresionar: () {},
          ),
          sinAnimaciones: reducido,
        );
        final boton = find.byType(BotonPrincipalGrande);
        double escala() => tester
            .widget<AnimatedScale>(
              find.descendant(of: boton, matching: find.byType(AnimatedScale)),
            )
            .scale;
        final dedo = await tester.startGesture(tester.getCenter(boton));
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(MovimientoApp.presion);
        final hundido = relieveDe(tester, boton);
        expect(hundido.elevacion, -1);
        expect(hundido.sombraClara, isNull);
        expect(escala(), reducido ? 1 : MovimientoApp.escalaPresion);
        await dedo.up();
        await tester.pumpAndSettle();
        expect(relieveDe(tester, boton).elevacion, 1);
        expect(escala(), 1);
      });
    }

    testWidgets('el principal grande con la letra al 200 %: mide lo que pide '
        'su contenido, sin desbordes', (tester) async {
      await armar(
        tester,
        BotonPrincipalGrande(
          icono: Icons.explore_rounded,
          texto: 'Comenzar a navegar',
          detalle: 'Tocá para comenzar',
          alPresionar: () {},
        ),
        escala: 2,
      );
      expect(tester.takeException(), isNull);
      // En una lista no le dan alto: mide el ícono y los textos, con su aire.
      expect(
        tester.getSize(find.byType(BotonPrincipalGrande)).height,
        greaterThan(
          FormasApp.iconoGrande +
              tester.getSize(find.text('Comenzar a navegar')).height +
              tester.getSize(find.text('Tocá para comenzar')).height,
        ),
      );
    });

    testWidgets('el principal grande deshabilitado queda plano y se sigue '
        'leyendo', (tester) async {
      await armar(
        tester,
        const BotonPrincipalGrande(
          icono: Icons.explore_rounded,
          texto: 'Comenzar a navegar',
          alPresionar: null,
        ),
      );
      final d = relieveDe(tester, find.byType(BotonPrincipalGrande));
      expect(d.elevacion, 0);
      expect(d.color, ColoresApp.superficie);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Comenzar a navegar'))
            .text
            .style!
            .color,
        ColoresApp.textoSecundario,
      );
    });

    testWidgets('el secundario: levantado, con borde y texto principal', (
      tester,
    ) async {
      await armar(
        tester,
        Column(
          children: [
            BotonSecundario(texto: 'Mapas', alPresionar: () {}),
            BotonSecundario(
              texto: 'Borrar',
              destructivo: true,
              compacto: true,
              alPresionar: () {},
            ),
          ],
        ),
      );
      final secundarios = find.byType(BotonSecundario);
      final d = relieveDe(tester, secundarios.first);
      expect(d.color, ColoresApp.superficie);
      expect(d.elevacion, 1);
      expect(d.borde.color, ColoresApp.borde);
      expect(d.borde.width, 1);
      final botones = tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      );
      expect(
        botones.first.style!.foregroundColor!.resolve({}),
        ColoresApp.textoPrincipal,
      );
      expect(
        botones.last.style!.foregroundColor!.resolve({}),
        ColoresApp.error,
      );
      // El compacto mide 48: el área táctil justa.
      expect(tester.getSize(secundarios.last).height, 48);
      // El destructivo se lee levantado y hundido.
      expect(
        contraste(ColoresApp.error, ColoresApp.superficie),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contraste(ColoresApp.error, ColoresApp.hundido),
        greaterThanOrEqualTo(4.5),
      );
    });

    for (final sinAnimaciones in [false, true]) {
      testWidgets(
        sinAnimaciones
            ? 'con "Quitar animaciones": se hunde, no se achica, y termina '
                  'igual'
            : 'al presionar se hunde y se achica; al soltar vuelve',
        (tester) async {
          await armar(
            tester,
            BotonSecundario(texto: 'Comenzar', alPresionar: () {}),
            sinAnimaciones: sinAnimaciones,
          );
          final boton = find.byType(BotonSecundario);
          double escala() => tester
              .widget<AnimatedScale>(
                find.descendant(
                  of: boton,
                  matching: find.byType(AnimatedScale),
                ),
              )
              .scale;
          expect(escala(), 1);
          expect(relieveDe(tester, boton).elevacion, 1);
          final dedo = await tester.startGesture(tester.getCenter(boton));
          // Adentro de una lista, el toque se confirma a los 100 ms; el paso
          // a hundido dura 120 ms (también con movimiento reducido).
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pump(MovimientoApp.presion);
          expect(escala(), sinAnimaciones ? 1 : MovimientoApp.escalaPresion);
          final presionado = relieveDe(tester, boton);
          expect(presionado.elevacion, -1);
          expect(presionado.color, ColoresApp.hundido);
          await dedo.up();
          await tester.pumpAndSettle();
          // El mismo estado final, con o sin movimiento reducido.
          expect(escala(), 1);
          expect(relieveDe(tester, boton).elevacion, 1);
        },
      );
    }

    testWidgets('el redondo: 36 de dibujo, 48 para tocar y su nombre', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      var veces = 0;
      await armar(
        tester,
        Center(
          child: BotonRedondo(
            icono: Icons.search_rounded,
            etiqueta: 'Buscar',
            alPresionar: () => veces++,
          ),
        ),
      );
      final boton = find.byType(BotonRedondo);
      expect(tester.getSize(boton), const Size.square(48));
      final dibujo = find.descendant(
        of: boton,
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && w.decoration is DecoracionRelieve,
        ),
      );
      expect(tester.getSize(dibujo), const Size.square(36));
      final d = relieveDe(tester, boton);
      expect(d.circulo, isTrue);
      expect(d.tamano, TamanoRelieve.chico);
      expect(d.borde.color, ColoresApp.borde);
      expect(find.byTooltip('Buscar'), findsOneWidget);
      // Se toca también fuera del dibujo, dentro de los 48.
      await tester.tapAt(tester.getTopLeft(boton) + const Offset(3, 3));
      expect(veces, 1);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    });

    testWidgets('los secundarios miden 48 o más para tocar', (tester) async {
      await armar(
        tester,
        Column(
          children: [
            BotonSecundario(texto: 'Relleno', alPresionar: () {}),
            BotonSecundario(
              texto: 'Compacto',
              compacto: true,
              alPresionar: () {},
            ),
          ],
        ),
      );
      final semantica = tester.ensureSemantics();
      await tester.pump();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantica.dispose();
    });

    testWidgets('la fila de botones: lado a lado y del mismo ancho; si no '
        'entran, apilados a todo el ancho', (tester) async {
      final semantica = tester.ensureSemantics();
      final toques = <String>[];
      // Con la letra de prueba (1 em por letra), «Otro» al 200 % ya no entra
      // en media fila.
      Widget fila() => FilaBotones(
        children: [
          BotonSecundario(texto: 'Uno', alPresionar: () => toques.add('uno')),
          BotonSecundario(
            texto: 'Otro',
            destructivo: true,
            alPresionar: () => toques.add('otro'),
          ),
        ],
      );
      const ancho = 360 - 2 * EspaciadoApp.margenLateral;
      List<String> orden() => tester.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.label)
          .where((l) => l.isNotEmpty)
          .toList();

      await armar(tester, fila());
      var uno = tester.getRect(find.widgetWithText(BotonSecundario, 'Uno'));
      var otro = tester.getRect(find.widgetWithText(BotonSecundario, 'Otro'));
      expect(otro.top, uno.top);
      expect(otro.width, moreOrLessEquals(uno.width));
      expect(otro.left - uno.right, moreOrLessEquals(EspaciadoApp.medio));
      expect(otro.right - uno.left, moreOrLessEquals(ancho));
      expect(uno.height, FormasApp.altoBoton);
      expect(orden(), ['Uno', 'Otro']);
      await tester.tap(find.text('Otro'));
      expect(toques, ['otro']);

      await armar(tester, fila(), escala: 2);
      await tester.pumpAndSettle();
      uno = tester.getRect(find.widgetWithText(BotonSecundario, 'Uno'));
      otro = tester.getRect(find.widgetWithText(BotonSecundario, 'Otro'));
      expect(otro.top - uno.bottom, moreOrLessEquals(EspaciadoApp.medio));
      expect(uno.width, moreOrLessEquals(ancho));
      expect(otro.width, moreOrLessEquals(ancho));
      expect(orden(), ['Uno', 'Otro']);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      // Con uno solo, a todo el ancho.
      await armar(
        tester,
        FilaBotones(
          children: [BotonSecundario(texto: 'Solo', alPresionar: () {})],
        ),
      );
      expect(
        tester.getRect(find.byType(BotonSecundario)).width,
        moreOrLessEquals(ancho),
      );
      semantica.dispose();
    });
  });

  // ── Tarjeta de dato ─────────────────────────────────────────────────────

  group('tarjeta de dato', () {
    testWidgets('se lee de una vez y se toca entera', (tester) async {
      final semantica = tester.ensureSemantics();
      var veces = 0;
      await armar(
        tester,
        TarjetaDato(
          icono: Icons.signal_cellular_alt_rounded,
          etiqueta: 'Señal',
          valor: '−67',
          unidad: 'dBm',
          valorSemantico: 'menos 67 dBm',
          detalle: 'Buena',
          alTocar: () => veces++,
          pistaToque: 'ver el detalle',
        ),
      );
      expect(
        tester.getSemantics(find.byType(TarjetaDato)),
        isSemantics(
          label: 'Señal, menos 67 dBm, Buena',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // Tocada en el borde, lejos del número: igual cuenta.
      final caja = tester.getRect(find.byType(TarjetaDato));
      await tester.tapAt(caja.bottomRight - const Offset(8, 8));
      expect(veces, 1);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('levantadas; sólo la que se toca lleva borde y flecha', (
      tester,
    ) async {
      await armar(
        tester,
        Column(
          children: [
            TarjetaDato(
              icono: Icons.map_rounded,
              etiqueta: 'Mapas',
              valor: '3',
              alTocar: () {},
            ),
            const TarjetaDato(
              icono: Icons.route_rounded,
              etiqueta: 'Distancia',
              valor: '48',
            ),
          ],
        ),
      );
      final tocable = relieveDe(tester, find.byType(TarjetaDato).at(0));
      final fija = relieveDe(tester, find.byType(TarjetaDato).at(1));
      for (final d in [tocable, fija]) {
        expect(d.elevacion, 1);
        expect(d.color, ColoresApp.superficie);
        expect(d.radio, FormasApp.bordeTarjeta);
      }
      expect(tocable.borde.color, ColoresApp.borde);
      expect(fija.borde, BorderSide.none);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      // El ícono va en su cuadro hundido de 40, en acento.
      final cuadros = find.byType(CuadroIcono);
      expect(cuadros, findsNWidgets(2));
      expect(tester.getSize(cuadros.first), const Size.square(40));
      final cuadro = relieveDe(tester, cuadros.first);
      expect(cuadro.elevacion, -1);
      expect(cuadro.tamano, TamanoRelieve.chico);
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: cuadros.first, matching: find.byType(Icon)),
            )
            .color,
        ColoresApp.acento,
      );
    });

    test('sin valor hablado, se lee como se ve; el pie también cuenta', () {
      const tarjeta = TarjetaDato(
        icono: Icons.map_rounded,
        etiqueta: 'Mapas',
        valor: '3',
        unidad: 'de 5',
        descripcionPie: '60 % descargado',
      );
      expect(tarjeta.textoSemantico, 'Mapas, 3 de 5, 60 % descargado');
    });

    test('la grilla pasa a una columna cuando dos no entran', () {
      // Un teléfono de 360 dp, con los márgenes: 328 de ancho.
      expect(GrillaTarjetas.columnasPara(328, 1), 2);
      expect(GrillaTarjetas.columnasPara(328, 1.1), 2);
      expect(GrillaTarjetas.columnasPara(328, 1.2), 1);
      expect(GrillaTarjetas.columnasPara(328, 2), 1);
      // Una tablet: dos columnas aun con la letra al 200 %.
      expect(GrillaTarjetas.columnasPara(800, 2), 2);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets('grilla con la letra al ${(escala * 100).round()} %', (
        tester,
      ) async {
        await armar(
          tester,
          const GrillaTarjetas(
            tarjetas: [
              TarjetaDato(
                icono: Icons.route_rounded,
                etiqueta: 'Distancia',
                valor: '1.234',
                unidad: 'm',
              ),
              TarjetaDato(
                icono: Icons.map_rounded,
                etiqueta: 'Mapas',
                valor: '3',
                unidad: 'de 5',
                detalle: 'Descargados',
                pie: AnilloProgreso(
                  valor: 0.6,
                  diametro: FormasApp.diametroAnilloChico,
                  grosor: FormasApp.grosorAnilloChico,
                ),
              ),
              TarjetaDato(
                icono: Icons.my_location_rounded,
                etiqueta: 'Precisión',
                valor: '1,2',
                unidad: 'm',
                pie: MiniGrafico(valores: [3, 2, 2.5, 1.2]),
              ),
            ],
          ),
          escala: escala,
        );
        final primera = tester.getRect(find.byType(TarjetaDato).at(0));
        final segunda = tester.getRect(find.byType(TarjetaDato).at(1));
        if (escala == 1) {
          // Lado a lado y del mismo alto.
          expect(segunda.top, primera.top);
          expect(segunda.height, primera.height);
        } else {
          // Una debajo de la otra.
          expect(segunda.top, greaterThan(primera.bottom));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── Grupo de filas ──────────────────────────────────────────────────────

  group('grupo de filas', () {
    Widget grupo({bool vibrar = false, ValueChanged<bool>? alCambiar}) =>
        GrupoFilas(
          titulo: 'Ajustes',
          filas: [
            FilaGrupo(
              icono: Icons.map_rounded,
              titulo: 'Mapas disponibles',
              navega: true,
              alTocar: () {},
            ),
            const FilaGrupo(
              titulo: 'Edificio',
              subtitulo: 'Facultad de Ingeniería',
              valor: '3 pisos',
            ),
            FilaGrupo.interruptor(
              icono: Icons.vibration_rounded,
              titulo: 'Vibrar al llegar',
              valor: vibrar,
              alCambiar: alCambiar ?? (_) {},
            ),
          ],
        );

    testWidgets('filas de 52 o más; separador desde el texto; con borde', (
      tester,
    ) async {
      await armar(tester, grupo());
      for (final fila in tester.widgetList(find.byType(FilaGrupo))) {
        expect(
          tester.getSize(find.byWidget(fila)).height,
          greaterThanOrEqualTo(FormasApp.altoFilaMinimo),
        );
      }
      final separadores = tester
          .widgetList<Divider>(find.byType(Divider))
          .toList();
      expect(separadores, hasLength(2));
      // Debajo de una fila con ícono: margen + cuadro + espacio.
      expect(
        separadores[0].indent,
        EspaciadoApp.rellenoTarjeta +
            FormasApp.cuadroIcono +
            EspaciadoApp.medio,
      );
      // Debajo de una fila sin ícono: el margen.
      expect(separadores[1].indent, EspaciadoApp.rellenoTarjeta);
      expect(separadores[0].color, ColoresApp.separador);
      expect(
        tester.getSemantics(find.text('Ajustes')),
        isSemantics(label: 'Ajustes', isHeader: true),
      );
      // La tarjeta, levantada; como tiene filas que se tocan, con borde.
      final tarjeta = relieves(tester, find.byType(GrupoFilas));
      expect(
        tarjeta.any(
          (d) => d.elevacion == 1 && d.color == ColoresApp.superficie,
        ),
        isTrue,
      );
      expect(tarjeta.any((d) => d.borde.color == ColoresApp.borde), isTrue);
    });

    testWidgets('sin filas que se toquen, la tarjeta no lleva borde', (
      tester,
    ) async {
      await armar(
        tester,
        const GrupoFilas(
          filas: [FilaGrupo(titulo: 'Edificio', valor: '3 pisos')],
        ),
      );
      expect(
        relieves(
          tester,
          find.byType(GrupoFilas),
        ).every((d) => d.borde == BorderSide.none),
        isTrue,
      );
    });

    testWidgets('la fila presionada se hunde', (tester) async {
      await armar(tester, grupo());
      final fila = find.byType(FilaGrupo).first;
      expect(relieveDe(tester, fila).elevacion, 0);
      final dedo = await tester.startGesture(tester.getCenter(fila));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(MovimientoApp.presion);
      final presionada = relieveDe(tester, fila);
      expect(presionada.elevacion, -1);
      expect(presionada.color, ColoresApp.hundido);
      await dedo.up();
      await tester.pumpAndSettle();
      expect(relieveDe(tester, fila).elevacion, 0);
    });

    testWidgets('la fila con interruptor se prende tocando cualquier parte', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      bool? nuevo;
      await armar(tester, grupo(alCambiar: (v) => nuevo = v));
      expect(
        tester.getSemantics(find.text('Vibrar al llegar')),
        isSemantics(
          label: 'Vibrar al llegar',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('Vibrar al llegar'));
      expect(nuevo, isTrue);
      semantica.dispose();
    });

    testWidgets('con etiqueta propia, TalkBack dice sólo esa', (tester) async {
      final semantica = tester.ensureSemantics();
      await armar(
        tester,
        GrupoFilas(
          filas: [
            FilaGrupo(
              icono: Icons.settings_rounded,
              titulo: 'Ajustes',
              subtitulo: 'Voz, movimiento y vibración',
              valor: '3',
              etiquetaSemantica: 'Ajustes: voz, movimiento y vibración',
              navega: true,
              alTocar: () {},
            ),
          ],
        ),
      );
      expect(
        tester.getSemantics(find.text('Ajustes')),
        isSemantics(
          label: 'Ajustes: voz, movimiento y vibración',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // Lo que se ve no cambia.
      expect(find.text('Voz, movimiento y vibración'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('con letra grande, el texto se queda con todo el ancho', (
      tester,
    ) async {
      await armar(tester, grupo(), escala: 2);
      // Sin cuadros de ícono (son decorativos).
      expect(find.byIcon(Icons.map_rounded), findsNothing);
      expect(find.byIcon(Icons.vibration_rounded), findsNothing);
      // El valor y el interruptor, debajo del título.
      expect(
        tester.getRect(find.text('3 pisos')).top,
        greaterThan(tester.getRect(find.text('Edificio')).bottom),
      );
      final interruptor = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_Interruptor',
      );
      expect(interruptor, findsOneWidget);
      expect(
        tester.getRect(interruptor).top,
        greaterThanOrEqualTo(
          tester.getRect(find.text('Vibrar al llegar')).bottom,
        ),
      );
      for (final separador in tester.widgetList<Divider>(
        find.byType(Divider),
      )) {
        expect(separador.indent, EspaciadoApp.rellenoTarjeta);
      }
      expect(tester.takeException(), isNull);
    });
  });

  // ── Chips ───────────────────────────────────────────────────────────────

  group('chips', () {
    testWidgets('el de filtro se prende, mide 48 y se lee elegido', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      bool? nuevo;
      await armar(
        tester,
        Wrap(
          children: [
            const ChipApp(texto: 'Descargado', icono: Icons.download_rounded),
            ChipFiltro(
              texto: 'Todos',
              seleccionado: true,
              exclusivo: true,
              alCambiar: (_) {},
            ),
            ChipFiltro(
              texto: 'Descargados',
              seleccionado: false,
              exclusivo: true,
              alCambiar: (v) => nuevo = v,
            ),
          ],
        ),
      );
      expect(
        tester.getSemantics(find.text('Todos')),
        isSemantics(
          label: 'Todos',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Descargados')),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true),
      );
      await tester.tap(find.text('Descargados'));
      expect(nuevo, isTrue);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantica.dispose();
    });

    testWidgets('elegido en acento con tilde; sin elegir, levantado con borde; '
        'el de dato, hundido', (tester) async {
      await armar(
        tester,
        Wrap(
          children: [
            const ChipApp(texto: 'Piso 2'),
            ChipFiltro(texto: 'Todos', seleccionado: true, alCambiar: (_) {}),
            ChipFiltro(texto: 'Aulas', seleccionado: false, alCambiar: (_) {}),
          ],
        ),
      );
      final dato = relieveDe(tester, find.byType(ChipApp));
      expect(dato.elevacion, -1);
      expect(dato.borde, BorderSide.none);
      final elegido = relieveDe(tester, find.byType(ChipFiltro).at(0));
      expect(elegido.color, ColoresApp.acento);
      final otro = relieveDe(tester, find.byType(ChipFiltro).at(1));
      expect(otro.color, ColoresApp.superficie);
      expect(otro.elevacion, 1);
      expect(otro.borde.color, ColoresApp.borde);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  // ── Control segmentado ──────────────────────────────────────────────────

  group('control segmentado', () {
    const dos = [
      OpcionSegmento(valor: 'edificio', texto: 'Este edificio'),
      OpcionSegmento(valor: 'general', texto: 'General'),
    ];

    /// El objeto que dibuja las opciones y la pieza.
    RenderObject opciones(WidgetTester tester) => tester.renderObject(
      find.descendant(
        of: find.byType(ControlSegmentado<String>),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString().startsWith('_Opciones'),
        ),
      ),
    );

    /// Que la pieza (el relleno de la superficie) esté sobre la opción
    /// [indice] de dos: contiene el centro de su texto y no el de la otra.
    /// Con la letra de prueba, más ancha, las dos opciones van apiladas.
    PaintPattern piezaEn(WidgetTester tester, int indice) {
      final origen = tester.getTopLeft(
        find.descendant(
          of: find.byType(ControlSegmentado<String>),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString().startsWith('_Opciones'),
          ),
        ),
      );
      Offset centro(int i) =>
          tester.getCenter(find.text(dos[i].texto).first) - origen;
      // La pieza: la luz, la sombra y el relleno, en ese orden.
      return paints
        ..path(color: ColoresApp.sombraClara)
        ..path(color: ColoresApp.sombraOscura)
        ..path(
          color: ColoresApp.superficie,
          includes: [centro(indice)],
          excludes: [centro(1 - indice)],
        );
    }

    testWidgets('avisa la opción tocada y TalkBack ve cuál está elegida', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      String? tocada;
      await armar(
        tester,
        ControlSegmentado<String>(
          etiqueta: 'Alcance',
          opciones: dos,
          seleccionada: 'edificio',
          alCambiar: (v) => tocada = v,
        ),
      );
      // Cada opción se dibuja dos veces (la copia clara va encima): la
      // primera es la de abajo, la que se toca y lee TalkBack.
      expect(
        tester.getSemantics(find.text('Este edificio').first),
        isSemantics(
          label: 'Este edificio',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('General').first),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true),
      );
      // La copia de encima no la lee TalkBack: una sola por opción.
      expect(find.bySemanticsLabel('General'), findsOneWidget);
      await tester.tap(find.text('General').first);
      expect(tocada, 'general');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantica.dispose();
    });

    testWidgets('pista hundida con borde y pieza levantada con borde de '
        'acento', (tester) async {
      await armar(
        tester,
        ControlSegmentado<String>(
          opciones: dos,
          seleccionada: 'edificio',
          alCambiar: (_) {},
        ),
      );
      final pista = relieveDe(tester, find.byType(ControlSegmentado<String>));
      expect(pista.elevacion, -1);
      expect(pista.borde.color, ColoresApp.borde);
      final pieza =
          tester.widget(
                find.descendant(
                  of: find.byType(ControlSegmentado<String>),
                  matching: find.byWidgetPredicate(
                    (w) => w.runtimeType.toString().startsWith('_Opciones'),
                  ),
                ),
              )
              // ignore: avoid_dynamic_calls
              as dynamic;
      // ignore: avoid_dynamic_calls
      final DecoracionRelieve deco = pieza.pieza as DecoracionRelieve;
      expect(deco.elevacion, 1);
      expect(deco.borde.color, ColoresApp.acento);
      expect(opciones(tester), piezaEn(tester, 0));
    });

    for (final sinAnimaciones in [false, true]) {
      testWidgets(
        sinAnimaciones
            ? 'con "Quitar animaciones", la pieza salta'
            : 'la pieza se desliza con resorte, sin pasarse',
        (tester) async {
          final elegida = ValueNotifier('edificio');
          addTearDown(elegida.dispose);
          await armar(
            tester,
            ValueListenableBuilder<String>(
              valueListenable: elegida,
              builder: (context, valor, _) => ControlSegmentado<String>(
                opciones: dos,
                seleccionada: valor,
                alCambiar: (v) => elegida.value = v,
              ),
            ),
            sinAnimaciones: sinAnimaciones,
          );
          elegida.value = 'general';
          final cuadros = await tester.pumpAndSettle();
          if (sinAnimaciones) {
            expect(cuadros, 1);
          } else {
            expect(cuadros, greaterThan(5));
          }
          // El mismo estado final, con o sin movimiento reducido.
          expect(opciones(tester), piezaEn(tester, 1));
        },
      );
    }

    testWidgets('interrumpida a mitad de camino, termina en la última', (
      tester,
    ) async {
      final elegida = ValueNotifier('edificio');
      addTearDown(elegida.dispose);
      await armar(
        tester,
        ValueListenableBuilder<String>(
          valueListenable: elegida,
          builder: (context, valor, _) => ControlSegmentado<String>(
            opciones: dos,
            seleccionada: valor,
            alCambiar: (v) => elegida.value = v,
          ),
        ),
      );
      elegida.value = 'general';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // A mitad de camino, vuelve.
      elegida.value = 'edificio';
      await tester.pumpAndSettle();
      expect(opciones(tester), piezaEn(tester, 0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('si las opciones no entran en una fila, se apilan', (
      tester,
    ) async {
      const tres = [
        OpcionSegmento(valor: 1, texto: 'Calibración', icono: Icons.tune),
        OpcionSegmento(valor: 2, texto: 'Brújula', icono: Icons.explore),
        OpcionSegmento(valor: 3, texto: 'Escala', icono: Icons.straighten),
      ];
      await armar(
        tester,
        ControlSegmentado<int>(
          opciones: tres,
          seleccionada: 1,
          alCambiar: (_) {},
        ),
        escala: 2,
      );
      expect(
        tester.getCenter(find.text('Escala').first).dy,
        greaterThan(tester.getCenter(find.text('Calibración').first).dy),
      );
      // Apiladas, cada opción tiene todo el ancho y 48 dp o más.
      final opcion = tester.getRect(
        find
            .ancestor(
              of: find.text('Calibración').first,
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(opcion.height, greaterThanOrEqualTo(48));
      expect(opcion.width, greaterThan(300));
      expect(tester.takeException(), isNull);
    });
  });

  // ── Barras ──────────────────────────────────────────────────────────────

  group('barras', () {
    Future<void> pantallaConBarras(WidgetTester tester, double escala) async {
      await armar(tester, const SizedBox(), escala: escala);
      final navegador = tester.state<NavigatorState>(find.byType(Navigator));
      navegador.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            extendBody: true,
            appBar: BarraSuperior(
              titulo: 'Mapas disponibles',
              acciones: [
                AccionBarra(
                  icono: Icons.search_rounded,
                  etiqueta: 'Buscar',
                  alPresionar: () {},
                ),
              ],
            ),
            bottomNavigationBar: BarraInferior(
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
                PestanaBarra(
                  icono: Icons.settings_rounded,
                  iconoInactivo: Icons.settings_outlined,
                  texto: 'Configuración',
                ),
              ],
              seleccionada: 1,
              alCambiar: (_) {},
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('arriba: título centrado y chico, botones redondos', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await pantallaConBarras(tester, 1);
      final titulo = find.text('Mapas disponibles');
      expect(
        tester.getSemantics(titulo),
        isSemantics(
          label: 'Mapas disponibles',
          isHeader: true,
          namesRoute: true,
        ),
      );
      // Centrado en la pantalla (360 dp) y de 14.
      expect(tester.getCenter(titulo).dx, moreOrLessEquals(180, epsilon: 1));
      expect(
        tester.widget<Text>(titulo).style!.fontSize,
        TipografiaApp.tituloBarra.fontSize,
      );
      expect(find.byTooltip('Volver'), findsOneWidget);
      expect(find.byTooltip('Buscar'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BarraSuperior),
          matching: find.byType(BotonRedondo),
        ),
        findsNWidgets(2),
      );
      expect(
        tester.getSize(find.byType(BarraSuperior)).height,
        FormasApp.altoBarraSuperior,
      );
      // Sin vidrio en ninguna barra.
      expect(find.byType(BackdropFilter), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(find.byType(BarraSuperior), findsNothing);
      semantica.dispose();
    });

    testWidgets('abajo: píldora levantada con borde y "pestaña 2 de 3"', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      var tocada = -1;
      await armar(
        tester,
        BarraInferior(
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
          seleccionada: 1,
          alCambiar: (i) => tocada = i,
        ),
      );
      expect(
        tester.getSemantics(find.text('Mapas')),
        isSemantics(
          label: 'Mapas\npestaña 2 de 2',
          isSelected: true,
          isButton: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Navegar')),
        isSemantics(label: 'Navegar\npestaña 1 de 2', isSelected: false),
      );
      // Elegida: ícono relleno en acento; la otra, de contorno en gris.
      expect(
        tester.widget<Icon>(find.byIcon(Icons.map_rounded)).color,
        ColoresApp.acento,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.explore_outlined)).color,
        ColoresApp.textoSecundario,
      );
      final pildora = relieves(tester, find.byType(BarraInferior));
      expect(
        pildora.any(
          (d) => d.elevacion == 1 && d.color == ColoresApp.superficie,
        ),
        isTrue,
      );
      expect(pildora.any((d) => d.borde.color == ColoresApp.borde), isTrue);
      await tester.tap(find.text('Navegar'));
      expect(tocada, 0);
      semantica.dispose();
    });

    testWidgets('con letra grande: la barra de arriba crece y nada se parte', (
      tester,
    ) async {
      await pantallaConBarras(tester, 2);
      expect(
        tester.getSize(find.byType(BarraSuperior)).height,
        greaterThan(FormasApp.altoBarraSuperior),
      );
      // "Configuración" no entra en su pestaña: se achica en un renglón.
      final nombre = find.text('Configuración');
      final caja = find.ancestor(of: nombre, matching: find.byType(FittedBox));
      expect(
        tester.getSize(caja).width,
        lessThan(tester.getSize(nombre).width),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('acciones: la principal en acento y cada una con su nombre', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      var repetidas = 0;
      await armar(
        tester,
        BarraAcciones(
          acciones: [
            AccionPildora(
              icono: Icons.replay_rounded,
              texto: 'Repetir',
              etiquetaSemantica: 'Repetir la indicación',
              principal: true,
              alPresionar: () => repetidas++,
            ),
            AccionPildora(
              icono: Icons.close_rounded,
              texto: 'Cancelar',
              alPresionar: () {},
            ),
          ],
        ),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.replay_rounded)).color,
        ColoresApp.acento,
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.close_rounded)).color,
        ColoresApp.textoPrincipal,
      );
      expect(
        tester.getSemantics(find.text('Repetir')),
        isSemantics(
          label: 'Repetir la indicación',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Cancelar')),
        isSemantics(label: 'Cancelar', isButton: true),
      );
      await tester.tap(find.text('Repetir'));
      expect(repetidas, 1);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    });
  });

  // ── Campo de texto ──────────────────────────────────────────────────────

  group('campo de texto', () {
    testWidgets('con la unidad al final, varios renglones y una aclaración '
        'debajo, que TalkBack dice con el campo; con un error, el error en su '
        'lugar', (tester) async {
      final semantica = tester.ensureSemantics();
      String? error;
      late StateSetter cambiar;
      await armar(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            cambiar = setState;
            return Column(
              children: [
                const CampoTexto(etiqueta: 'Largo', ayuda: '12,5', sufijo: 'm'),
                CampoTexto(
                  etiqueta: 'Otras palabras',
                  lineas: 3,
                  pie: 'Separadas por comas.',
                  error: error,
                ),
              ],
            );
          },
        ),
      );
      expect(find.text('m'), findsOneWidget);
      final palabras = find.byType(TextField).last;
      expect(tester.widget<TextField>(palabras).maxLines, 3);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).maxLines,
        1,
      );
      // La aclaración se ve y TalkBack la dice con el campo, no aparte.
      expect(find.text('Separadas por comas.'), findsOneWidget);
      expect(
        tester.getSemantics(palabras),
        isSemantics(
          label: 'Otras palabras',
          hint: 'Separadas por comas.',
          isTextField: true,
        ),
      );
      expect(find.bySemanticsLabel('Separadas por comas.'), findsNothing);
      // Crece al escribir, hasta tres renglones.
      final alto = tester.getSize(palabras).height;
      await tester.enterText(palabras, 'uno\ndos');
      await tester.pumpAndSettle();
      final dos = tester.getSize(palabras).height;
      expect(dos, greaterThan(alto));
      await tester.enterText(palabras, 'uno\ndos\ntres\ncuatro\ncinco');
      await tester.pumpAndSettle();
      final tres = tester.getSize(palabras).height;
      expect(tres, moreOrLessEquals(alto + 2 * (dos - alto), epsilon: 1));
      // Con un error, va el error en lugar de la aclaración.
      cambiar(() => error = 'Faltan palabras.');
      await tester.pumpAndSettle();
      expect(find.text('Faltan palabras.'), findsOneWidget);
      expect(find.text('Separadas por comas.'), findsNothing);
      semantica.dispose();
    });

    testWidgets('hundido, con borde; enfocado, borde de acento', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await armar(
        tester,
        const Column(
          children: [
            CampoTexto(etiqueta: 'Nombre del lugar', ayuda: 'Aula 12'),
            CampoTexto.busqueda(
              etiqueta: 'Buscar un destino',
              ayuda: 'Aula, baño, bar…',
            ),
          ],
        ),
      );
      final campo = find.byType(CampoTexto).first;
      var d = relieveDe(tester, campo);
      expect(d.elevacion, -1);
      expect(d.color, ColoresApp.hundido);
      expect(d.borde.color, ColoresApp.borde);
      // La etiqueta, a la vista arriba; el buscador no la muestra.
      expect(find.text('Nombre del lugar'), findsOneWidget);
      expect(find.text('Buscar un destino'), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      // TalkBack dice la etiqueta en los dos.
      expect(
        tester.getSemantics(find.byType(TextField).first).label,
        contains('Nombre del lugar'),
      );
      expect(
        tester.getSemantics(find.byType(TextField).last).label,
        contains('Buscar un destino'),
      );
      await tester.tap(find.byType(TextField).first);
      // El borde pasa al acento en 150 ms.
      await tester.pumpAndSettle();
      d = relieveDe(tester, campo);
      expect(d.borde.color, ColoresApp.acento);
      expect(d.borde.width, FormasApp.grosorFoco);
      semantica.dispose();
    });

    testWidgets('el buscador: con algo escrito, «Borrar búsqueda» lo borra y '
        'avisa el cambio', (tester) async {
      final semantica = tester.ensureSemantics();
      final cambios = <String>[];
      await armar(
        tester,
        CampoTexto.busqueda(
          etiqueta: 'Buscar mapa',
          ayuda: 'Por nombre',
          alCambiar: cambios.add,
        ),
      );
      // Vacío, sin el botón.
      expect(find.byTooltip('Borrar búsqueda'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Piso');
      await tester.pumpAndSettle();
      expect(cambios, ['Piso']);
      expect(find.byTooltip('Borrar búsqueda'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Borrar búsqueda')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      // Adentro del campo, levantado y con borde, con 48 para tocar.
      expect(
        find.descendant(
          of: find.byType(CampoTexto),
          matching: find.byType(BotonRedondo),
        ),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.byTooltip('Borrar búsqueda'));
      await tester.pumpAndSettle();
      expect(cambios, ['Piso', '']);
      expect(find.text('Piso'), findsNothing);
      expect(find.byTooltip('Borrar búsqueda'), findsNothing);

      // Con un controlador de afuera, igual.
      final controlador = TextEditingController(text: 'Aula');
      addTearDown(controlador.dispose);
      await armar(
        tester,
        CampoTexto.busqueda(
          etiqueta: 'Buscar',
          ayuda: 'Por nombre',
          controlador: controlador,
        ),
      );
      expect(find.byTooltip('Borrar búsqueda'), findsOneWidget);
      await tester.tap(find.byTooltip('Borrar búsqueda'));
      await tester.pumpAndSettle();
      expect(controlador.text, isEmpty);
      expect(find.byTooltip('Borrar búsqueda'), findsNothing);

      // Un campo común no lo trae.
      await armar(tester, const CampoTexto(etiqueta: 'Nombre'));
      await tester.enterText(find.byType(TextField), 'Aula 12');
      await tester.pumpAndSettle();
      expect(find.byType(BotonRedondo), findsNothing);
      semantica.dispose();
    });

    testWidgets('la contraseña, oculta y sin autocorrector ni sugerencias; el '
        'email, sin autocorrector; los dos, con sus pistas para autocompletar '
        'en un mismo grupo', (tester) async {
      final semantica = tester.ensureSemantics();
      await armar(
        tester,
        const AutofillGroup(
          child: Column(
            children: [
              CampoTexto(
                etiqueta: 'Email',
                tipoTeclado: TextInputType.emailAddress,
                autocorrector: false,
                pistasAutocompletar: [AutofillHints.email],
              ),
              CampoTexto(
                etiqueta: 'Contraseña',
                oculto: true,
                pistasAutocompletar: [AutofillHints.password],
              ),
            ],
          ),
        ),
      );
      // Lo que recibe el teclado del teléfono.
      await tester.showKeyboard(find.byType(TextField).first);
      var teclado = tester.testTextInput.setClientArgs!;
      expect(teclado['obscureText'], isFalse);
      expect(teclado['autocorrect'], isFalse);
      expect(teclado['enableSuggestions'], isTrue);
      expect(
        (teclado['inputType'] as Map)['name'],
        'TextInputType.emailAddress',
      );
      expect((teclado['autofill'] as Map)['hints'], [AutofillHints.email]);
      // Los dos van juntos: el administrador de contraseñas los completa (y
      // los guarda) de una vez.
      expect(teclado['fields'], hasLength(2));
      await tester.enterText(find.byType(TextField).last, 'clave');
      await tester.pump();
      teclado = tester.testTextInput.setClientArgs!;
      expect(teclado['obscureText'], isTrue);
      expect(teclado['autocorrect'], isFalse);
      expect(teclado['enableSuggestions'], isFalse);
      expect((teclado['autofill'] as Map)['hints'], [AutofillHints.password]);
      // Lo escrito se ve como puntos, y TalkBack sabe que está oculto.
      expect(
        tester
            .state<EditableTextState>(find.byType(EditableText).last)
            .renderEditable
            .text!
            .toPlainText(),
        '•••••',
      );
      expect(
        tester.getSemantics(find.byType(TextField).last),
        isSemantics(isTextField: true, isObscured: true),
      );
      expect(
        tester.getSemantics(find.byType(TextField).last).label,
        contains('Contraseña'),
      );
      semantica.dispose();
    });

    testWidgets('deshabilitado: no se puede escribir y TalkBack dice que está '
        'desactivado; sigue hundido, con el borde apagado y el texto y la '
        'etiqueta en gris', (tester) async {
      final semantica = tester.ensureSemantics();
      final controlador = TextEditingController(text: 'admin@ejemplo.com');
      addTearDown(controlador.dispose);
      await armar(
        tester,
        CampoTexto(
          etiqueta: 'Email',
          controlador: controlador,
          habilitado: false,
        ),
      );
      final d = relieveDe(tester, find.byType(CampoTexto));
      expect(d.elevacion, -1);
      expect(d.borde.color, ColoresApp.separador);
      final campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.enabled, isFalse);
      expect(campo.style!.color, ColoresApp.textoSecundario);
      expect(
        tester.widget<Text>(find.text('Email')).style!.color,
        ColoresApp.textoSecundario,
      );
      expect(
        tester.getSemantics(find.byType(TextField)),
        isSemantics(isTextField: true, hasEnabledState: true, isEnabled: false),
      );
      // Tocarlo no lo enfoca ni abre el teclado.
      await tester.tap(find.byType(TextField), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(
        relieveDe(tester, find.byType(CampoTexto)).borde.color,
        d.borde.color,
      );
      semantica.dispose();
    });

    testWidgets('con un error: debajo del campo, con el ícono y en rojo; el '
        'borde, rojo (2 px con el foco); TalkBack lo anuncia y lo lee después '
        'del campo; al irse, el campo sigue con lo escrito y el foco', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      String? error = 'Completá el email.';
      late StateSetter cambiar;
      await armar(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            cambiar = setState;
            return CampoTexto(etiqueta: 'Email', error: error);
          },
        ),
      );
      final campo = find.byType(CampoTexto);
      var d = relieveDe(tester, campo);
      expect(d.borde.color, ColoresApp.error);
      expect(d.borde.width, FormasApp.grosorLinea);
      // Debajo del campo, en rojo y con el ícono.
      final textoError = find.text('Completá el email.');
      expect(
        tester.getRect(textoError).top,
        greaterThan(tester.getRect(find.byType(TextField)).bottom),
      );
      expect(tester.widget<Text>(textoError).style!.color, ColoresApp.error);
      expect(
        find.descendant(of: campo, matching: find.byIcon(Icons.error_rounded)),
        findsOneWidget,
      );
      // TalkBack: el campo y después el error, que se anuncia al aparecer.
      expect(
        tester.getSemantics(textoError),
        isSemantics(label: 'Completá el email.', isLiveRegion: true),
      );
      expect(
        tester.semantics
            .simulatedAccessibilityTraversal()
            .map((nodo) => nodo.label)
            .where((etiqueta) => etiqueta.isNotEmpty),
        ['Email', 'Completá el email.'],
      );
      // Con el foco, el borde sigue rojo, de 2 px.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      d = relieveDe(tester, campo);
      expect(d.borde.color, ColoresApp.error);
      expect(d.borde.width, FormasApp.grosorFoco);
      // Se escribe con el error a la vista y, cuando se va, el campo es el
      // mismo: sigue lo escrito, con el foco (y el teclado).
      await tester.enterText(find.byType(TextField), 'admin@');
      final editable = tester.state(find.byType(EditableText));
      cambiar(() => error = null);
      await tester.pumpAndSettle();
      expect(textoError, findsNothing);
      expect(find.byIcon(Icons.error_rounded), findsNothing);
      expect(tester.state(find.byType(EditableText)), same(editable));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'admin@',
      );
      expect(tester.testTextInput.hasAnyClients, isTrue);
      d = relieveDe(tester, campo);
      expect(d.borde.color, ColoresApp.acento);

      // Con la letra al 200 %: se parte en renglones, sin cortarse, y el
      // ícono queda centrado en el primero.
      await armar(
        tester,
        const CampoTexto(
          etiqueta: 'Contraseña',
          oculto: true,
          error: 'No se pudo iniciar sesión: revisá la conexión.',
        ),
        escala: 2,
      );
      expect(tester.takeException(), isNull);
      final largo = find.textContaining('No se pudo iniciar sesión');
      final parrafo = tester.renderObject<RenderParagraph>(largo);
      expect(parrafo.didExceedMaxLines, isFalse);
      final renglon =
          2 *
          TipografiaApp.subtitulo.fontSize! *
          TipografiaApp.subtitulo.height!;
      expect(tester.getSize(largo).height, greaterThan(renglon));
      expect(
        tester.getCenter(find.byIcon(Icons.error_rounded)).dy,
        moreOrLessEquals(tester.getTopLeft(largo).dy + renglon / 2, epsilon: 1),
      );
      semantica.dispose();
    });
  });

  // ── Estado de pantalla ──────────────────────────────────────────────────

  group('estado de pantalla', () {
    testWidgets('el título y la aclaración de una vez, anunciados al '
        'aparecer; el ícono no se lee; el botón, aparte; nada gira', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      var reintentos = 0;
      await armar(
        tester,
        EstadoPantalla(
          icono: Icons.cloud_off_rounded,
          titulo: 'No hay conexión con la nube',
          detalle: 'Revisá la conexión.',
          accion: BotonSecundario(
            texto: 'Reintentar',
            alPresionar: () => reintentos++,
          ),
        ),
      );
      expect(
        tester.getSemantics(find.text('No hay conexión con la nube')),
        isSemantics(
          label: 'No hay conexión con la nube\nRevisá la conexión.',
          isLiveRegion: true,
        ),
      );
      expect(
        find.ancestor(
          of: find.byIcon(Icons.cloud_off_rounded),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      // En gris, sin relieve: no es un control.
      final icono = tester.widget<Icon>(find.byIcon(Icons.cloud_off_rounded));
      expect(icono.color, ColoresApp.textoSecundario);
      expect(icono.size, FormasApp.iconoGrande);
      expect(find.byType(ProgressIndicator), findsNothing);
      await tester.tap(find.text('Reintentar'));
      expect(reintentos, 1);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('con la letra al 200 %, el texto crece sin desbordarse', (
      tester,
    ) async {
      await armar(
        tester,
        const EstadoPantalla(
          icono: Icons.search_off_rounded,
          titulo: 'Sin resultados',
          detalle: 'No hay mapas que coincidan con la búsqueda.',
        ),
        escala: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Sin resultados'), findsOneWidget);
    });
  });

  // ── Hoja inferior ───────────────────────────────────────────────────────

  group('hoja inferior', () {
    testWidgets('título, "Cerrar" y el tema nuevo aunque se abra del viejo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      ThemeData? temaAdentro;
      Future<String?>? resultado;
      // El tema claro de MaterialApp, sin el sistema de diseño: como cuando
      // se abre con un contexto por encima del Theme de la pantalla.
      await armar(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => resultado = mostrarHoja<String>(
              context,
              titulo: 'Nuevo lugar',
              contenido: (context) {
                temaAdentro = Theme.of(context);
                return TextButton(
                  onPressed: () => Navigator.of(context).pop('listo'),
                  child: const Text('Guardar'),
                );
              },
            ),
            child: const Text('Abrir'),
          ),
        ),
        tema: ThemeData.light(),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Nuevo lugar')),
        isSemantics(label: 'Nuevo lugar', isHeader: true),
      );
      expect(find.byTooltip('Cerrar'), findsOneWidget);
      expect(temaAdentro!.extension<EstiloApp>(), isNotNull);
      // Para TalkBack, la hoja se nombra con su título (no "Dialog").
      expect(find.bySemanticsLabel('Nuevo lugar'), findsWidgets);
      expect(find.bySemanticsLabel('Dialog'), findsNothing);
      // Levantada, en la superficie, con la manija hundida y con borde.
      final hoja = relieves(tester, find.byType(Overlay).first);
      expect(
        hoja.any(
          (d) =>
              d.elevacion == 1 &&
              d.color == ColoresApp.superficie &&
              d.radio == FormasApp.bordeHoja,
        ),
        isTrue,
      );
      expect(
        hoja.any(
          (d) =>
              d.pildora &&
              d.elevacion == -1 &&
              d.borde.color == ColoresApp.borde,
        ),
        isTrue,
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(await resultado, 'listo');
      expect(find.text('Nuevo lugar'), findsNothing);

      // De nuevo, y se cierra con "Cerrar".
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo lugar'), findsNothing);
      expect(await resultado, isNull);
      semantica.dispose();
    });
  });

  // ── Confirmación ────────────────────────────────────────────────────────

  group('confirmación', () {
    /// Un botón que abre la confirmación y anota lo que devuelve.
    Widget abridor(
      List<bool> resultados, {
      bool destructiva = true,
      String confirmar = 'Quitar',
    }) => Builder(
      builder: (context) => TextButton(
        onPressed: () async => resultados.add(
          await mostrarConfirmacion(
            context,
            titulo: 'Quitar del teléfono',
            mensaje: 'Se borrará "Planta baja" de este teléfono.',
            confirmar: confirmar,
            destructiva: destructiva,
          ),
        ),
        child: const Text('Abrir'),
      ),
    );

    testWidgets('una hoja con su título, el mensaje, «Cancelar» y la acción '
        'en rojo; da true sólo al confirmar', (tester) async {
      final semantica = tester.ensureSemantics();
      final resultados = <bool>[];
      // Con el tema viejo, como desde una pantalla sin migrar.
      await armar(tester, abridor(resultados), tema: ThemeData.light());
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      // Para TalkBack se nombra con su título, en español.
      expect(find.bySemanticsLabel('Quitar del teléfono'), findsWidgets);
      expect(find.bySemanticsLabel('Dialog'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Se borrará "Planta baja" de este teléfono.'), findsOne);
      // Sin el botón redondo de cerrar: «Cancelar» ya lo es.
      expect(find.byTooltip('Cerrar'), findsNothing);
      // La acción destructiva, en un secundario rojo; nada en cian.
      expect(
        tester
            .widget<BotonSecundario>(
              find.widgetWithText(BotonSecundario, 'Quitar'),
            )
            .destructivo,
        isTrue,
      );
      expect(find.byType(BotonPrincipal), findsNothing);
      // «Cancelar» primero.
      final orden = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((n) => n.label)
          .toList();
      expect(orden.indexOf('Cancelar'), lessThan(orden.indexOf('Quitar')));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(resultados, [false]);
      expect(find.text('Quitar del teléfono'), findsNothing);

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar'));
      await tester.pumpAndSettle();
      expect(resultados, [false, true]);

      // Tocar afuera también es que no.
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(180, 40));
      await tester.pumpAndSettle();
      expect(resultados, [false, true, false]);
      semantica.dispose();
    });

    testWidgets('si la acción no es destructiva, va en el botón principal', (
      tester,
    ) async {
      final resultados = <bool>[];
      await armar(
        tester,
        abridor(resultados, destructiva: false, confirmar: 'Publicar'),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(BotonPrincipal, 'Publicar'), findsOneWidget);
      await tester.tap(find.text('Publicar'));
      await tester.pumpAndSettle();
      expect(resultados, [true]);
    });

    testWidgets('con la letra al 200 %, los botones se apilan y nada se '
        'desborda', (tester) async {
      final resultados = <bool>[];
      await armar(tester, abridor(resultados), escala: 2);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final cancelar = tester.getRect(
        find.widgetWithText(BotonSecundario, 'Cancelar'),
      );
      final quitar = tester.getRect(
        find.widgetWithText(BotonSecundario, 'Quitar'),
      );
      expect(quitar.top, greaterThan(cancelar.bottom));
      expect(quitar.width, moreOrLessEquals(cancelar.width));
    });
  });

  // ── Aviso ───────────────────────────────────────────────────────────────

  group('aviso', () {
    /// Un botón que muestra el aviso.
    Widget avisador(String texto, {bool error = false}) => Builder(
      builder: (context) => TextButton(
        onPressed: () => mostrarAviso(context, texto, error: error),
        child: const Text('Avisar'),
      ),
    );

    testWidgets('abajo, levantado y con borde; TalkBack lo lee sin nada en '
        'inglés; se va solo a los 4 s', (tester) async {
      final semantica = tester.ensureSemantics();
      await armar(tester, avisador('"Planta baja" descargado'));
      await tester.tap(find.text('Avisar'));
      await tester.pumpAndSettle();
      final texto = find.text('"Planta baja" descargado');
      expect(texto, findsOneWidget);
      final d = relieveDe(tester, find.byType(SnackBar));
      expect(d.elevacion, 1);
      expect(d.color, ColoresApp.superficie);
      expect(d.borde.color, ColoresApp.borde);
      expect(d.radio, FormasApp.bordeTarjeta);
      expect(find.byIcon(Icons.error_rounded), findsNothing);
      // Abajo, a 16 dp de los costados.
      final caja = tester.getRect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(PanelRelieve),
        ),
      );
      expect(caja.left, moreOrLessEquals(EspaciadoApp.margenLateral));
      expect(caja.right, moreOrLessEquals(360 - EspaciadoApp.margenLateral));
      expect(caja.bottom, greaterThan(780 / 2));
      // Se anuncia al aparecer (región en vivo).
      expect(
        tester.getSemantics(texto),
        isSemantics(label: '"Planta baja" descargado', isLiveRegion: true),
      );
      expect(find.bySemanticsLabel(RegExp('Close|Dismiss')), findsNothing);
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(texto, findsNothing);
      semantica.dispose();
    });

    testWidgets('el de error lleva el ícono y el borde en rojo', (
      tester,
    ) async {
      await armar(
        tester,
        avisador('Error al quitar: sin conexión', error: true),
      );
      await tester.tap(find.text('Avisar'));
      await tester.pumpAndSettle();
      final icono = tester.widget<Icon>(find.byIcon(Icons.error_rounded));
      expect(icono.color, ColoresApp.error);
      expect(
        relieveDe(tester, find.byType(SnackBar)).borde.color,
        ColoresApp.error,
      );
    });

    for (final sinAnimaciones in [false, true]) {
      testWidgets('no se mueve al aparecer: queda quieto en su lugar'
          '${sinAnimaciones ? ', también con «Reducir movimiento»' : ''}', (
        tester,
      ) async {
        await armar(
          tester,
          avisador('"Planta baja" descargado'),
          sinAnimaciones: sinAnimaciones,
        );
        await tester.tap(find.text('Avisar'));
        await tester.pump();
        final texto = find.text('"Planta baja" descargado');
        final primero = tester.getRect(texto);
        await tester.pump(const Duration(milliseconds: 60));
        final medio = tester.getRect(texto);
        await tester.pumpAndSettle();
        final ultimo = tester.getRect(texto);
        expect(medio, primero);
        expect(ultimo, primero);
      });
    }
  });

  // ── Progreso ────────────────────────────────────────────────────────────

  group('progreso', () {
    test('el porcentaje se acota y no se parte', () {
      expect(textoPorcentaje(0.45), '45 %');
      expect(textoPorcentaje(1.7), '100 %');
      expect(textoPorcentaje(-0.2), '0 %');
    });

    testWidgets('anillo y barra: TalkBack lee el nombre y el porcentaje', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await armar(
        tester,
        const Column(
          children: [
            AnilloProgreso(valor: 0.45, etiqueta: 'Descarga'),
            BarraProgreso(valor: 0.3, etiqueta: 'Planos'),
            MiniGrafico(valores: [1, 2, 3]),
            MiniGrafico(valores: [3, 2, 1], descripcion: 'Bajando'),
          ],
        ),
      );
      expect(
        tester.getSemantics(find.byType(AnilloProgreso)),
        isSemantics(label: 'Descarga', value: '45 %'),
      );
      expect(
        tester.getSemantics(find.byType(BarraProgreso)),
        isSemantics(label: 'Planos', value: '30 %'),
      );
      // Sin descripción, el minigráfico es decorativo.
      expect(find.bySemanticsLabel('Bajando'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(MiniGrafico).first).label,
        isNot(contains('Bajando')),
      );
      semantica.dispose();
    });

    testWidgets('pista hundida y avance en acento, sin degradado', (
      tester,
    ) async {
      await armar(tester, const BarraProgreso(valor: 0.5));
      // Se llena al aparecer (400 ms).
      await tester.pumpAndSettle();
      final dibujo = tester.renderObject(
        find.descendant(
          of: find.byType(BarraProgreso),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(
        dibujo,
        paints
          ..path(color: ColoresApp.hundido)
          ..clipPath()
          ..path(color: ColoresApp.sombraClara)
          ..clipPath()
          ..path(color: ColoresApp.sombraOscura)
          ..rrect(color: ColoresApp.acento),
      );
    });

    testWidgets('el anillo con texto adentro crece con la letra', (
      tester,
    ) async {
      for (final escala in [1.0, 2.0]) {
        await armar(
          tester,
          const Center(child: AnilloProgreso(valor: 0.5, centro: Text('50 %'))),
          escala: escala,
        );
        expect(
          tester.getSize(find.byType(AnilloProgreso)).width,
          FormasApp.diametroAnillo * escala,
        );
      }
    });
  });

  // ── Línea de ruta (sobre el plano) ──────────────────────────────────────

  group('línea de ruta', () {
    const tramos = [
      TramoRuta(
        metros: 14,
        marca: MarcaTramo.ascensor,
        descripcionMarca: 'ascensor al piso 1',
      ),
      TramoRuta(
        metros: 8,
        marca: MarcaTramo.escalera,
        descripcionMarca: 'escalera al piso 2',
      ),
      TramoRuta(
        metros: 22,
        marca: MarcaTramo.destino,
        descripcionMarca: 'Aula 12',
      ),
    ];

    test('el resumen dice el tramo, los metros que faltan y la marca', () {
      expect(
        const Recorrido(tramos: tramos, tramoActual: 1).resumen,
        'Tramo 2 de 3, 8 metros, escalera al piso 2',
      );
      expect(
        const Recorrido(tramos: tramos, tramoActual: 1, avance: 0.5).resumen,
        'Tramo 2 de 3, 4 metros, escalera al piso 2',
      );
      // Un tramo fuera de rango queda en el último.
      expect(
        const Recorrido(tramos: tramos, tramoActual: 9).resumen,
        'Tramo 3 de 3, 22 metros, Aula 12',
      );
      // Singular, y la marca sin descripción propia.
      expect(
        const Recorrido(
          tramos: [TramoRuta(metros: 1, marca: MarcaTramo.escalera)],
          tramoActual: 0,
        ).resumen,
        'Tramo 1 de 1, 1 metro, escalera',
      );
      expect(
        const LineaRuta(tramos: tramos, tramoActual: 1).resumen,
        'Tramo 2 de 3, 8 metros, escalera al piso 2',
      );
    });

    test('el cabezal va por la ruta, a lo largo de la línea', () {
      // Una L: 50 a la derecha y 100 hacia abajo, en 100 × 100.
      const ele = [
        TramoRuta(metros: 5, puntos: [Offset(0, 0), Offset(0.5, 0)]),
        TramoRuta(metros: 10, puntos: [Offset(0.5, 0), Offset(0.5, 1)]),
      ];
      const tamano = Size(100, 100);
      expect(
        LineaRuta.posicionCabezal(ele, 0, 0.5, tamano),
        offsetMoreOrLessEquals(const Offset(25, 0)),
      );
      expect(
        LineaRuta.posicionCabezal(ele, 1, 0, tamano),
        offsetMoreOrLessEquals(const Offset(50, 0)),
      );
      expect(
        LineaRuta.posicionCabezal(ele, 1, 0.5, tamano),
        offsetMoreOrLessEquals(const Offset(50, 50)),
      );
      expect(
        LineaRuta.posicionCabezal(ele, 1, 1, tamano),
        offsetMoreOrLessEquals(const Offset(50, 100)),
      );
      // Sin puntos, no hay cabezal.
      expect(LineaRuta.posicionCabezal(tramos, 0, 0, tamano), isNull);
    });

    testWidgets('ranura debajo; hecho, actual más grueso, siguiente y '
        'destino', (tester) async {
      final semantica = tester.ensureSemantics();
      await armar(
        tester,
        const SizedBox(
          height: 240,
          child: LineaRuta(tramos: tramosEjemplo, tramoActual: 1, avance: 0.5),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSemantics(find.byType(LineaRuta)),
        isSemantics(label: 'Tramo 2 de 3, 4 metros'),
      );
      final ruta = tester.renderObject(
        find
            .descendant(
              of: find.byType(LineaRuta),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(
        ruta,
        paints
          // Las tres ranuras primero.
          ..path(color: ColoresApp.rutaRanura)
          ..path(color: ColoresApp.rutaRanura)
          ..path(color: ColoresApp.rutaRanura)
          // Lo hecho fino, lo siguiente fino (punteado) y el actual grueso,
          // encima.
          ..path(color: ColoresApp.hecho, strokeWidth: FormasApp.grosorRuta)
          ..path(color: ColoresApp.siguiente, strokeWidth: FormasApp.grosorRuta)
          ..path(
            color: ColoresApp.acento,
            strokeWidth: FormasApp.grosorRutaActual,
          )
          // El cuadro del destino, con borde verde.
          ..path(color: ColoresApp.planoHabitacion)
          ..path(color: ColoresApp.hecho),
      );
      // El cabezal: levantado, con el anillo de acento.
      final cabezal = tester.renderObject(
        find
            .descendant(
              of: find.byType(LineaRuta),
              matching: find.byType(CustomPaint),
            )
            .last,
      );
      expect(
        cabezal,
        paints
          ..path(color: ColoresApp.sombraClara)
          ..path(color: ColoresApp.sombraOscura)
          ..path(color: ColoresApp.superficie)
          ..path(color: ColoresApp.acento),
      );
      semantica.dispose();
    });
  });

  // ── Línea de tiempo ─────────────────────────────────────────────────────

  group('línea de tiempo', () {
    const tramos = [
      TramoRuta(
        metros: 14,
        marca: MarcaTramo.ascensor,
        descripcionMarca: 'ascensor al piso 1',
      ),
      TramoRuta(
        metros: 8,
        marca: MarcaTramo.escalera,
        descripcionMarca: 'escalera al piso 2',
      ),
      TramoRuta(
        metros: 22,
        marca: MarcaTramo.destino,
        descripcionMarca: 'Aula 12',
      ),
    ];

    test('cada tramo, proporcional a sus metros, con un mínimo', () {
      expect(LineaTiempo.anchosDeTramos([10, 30], 200, 32), [50, 150]);
      expect(LineaTiempo.anchosDeTramos([1, 99], 200, 32), [32, 168]);
      // Si ni con el mínimo entran, todos iguales.
      expect(LineaTiempo.anchosDeTramos([10, 10, 10], 60, 32), [20, 20, 20]);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets('TalkBack lee el resumen y se arma sin desbordes al '
          '${(escala * 100).round()} %', (tester) async {
        final semantica = tester.ensureSemantics();
        await armar(
          tester,
          const LineaTiempo(tramos: tramos, tramoActual: 1),
          escala: escala,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSemantics(find.byType(LineaTiempo)),
          isSemantics(label: 'Tramo 2 de 3, 8 metros, escalera al piso 2'),
        );
        // Una marca por escalera, ascensor y destino, y un número por
        // tramo.
        expect(find.byIcon(Icons.elevator_rounded), findsOneWidget);
        expect(find.byIcon(Icons.stairs_rounded), findsOneWidget);
        expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
        for (final numero in ['1', '2', '3']) {
          expect(find.text(numero), findsOneWidget);
        }
        // La pista, hundida.
        expect(
          relieves(
            tester,
            find.byType(LineaTiempo),
          ).any((d) => d.pildora && d.elevacion == -1),
          isTrue,
        );
        semantica.dispose();
      });
    }

    testWidgets('el actual es más grueso; el cabezal va al tramo actual', (
      tester,
    ) async {
      final cabezal = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is DecoracionRelieve &&
            (w.decoration as DecoracionRelieve).circulo,
      );
      final xs = <double>[];
      for (final actual in [0, 1, 2]) {
        await armar(
          tester,
          LineaTiempo(tramos: tramos, tramoActual: actual, avance: 0.5),
        );
        // El cambio de tramo se anima: el estado final, al terminar.
        await tester.pumpAndSettle();
        expect(cabezal, findsOneWidget);
        final d =
            tester.widget<DecoratedBox>(cabezal).decoration
                as DecoracionRelieve;
        expect(d.elevacion, 1);
        expect(d.borde.color, ColoresApp.acento);
        expect(d.borde.width, FormasApp.anilloCabezalTiempo);
        xs.add(tester.getCenter(cabezal).dx);
        // Los segmentos: uno grueso (el actual) y los demás finos.
        final altos = [
          for (final p in tester.widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(LineaTiempo),
              matching: find.byType(CustomPaint),
            ),
          ))
            if (p.painter != null) tester.getSize(find.byWidget(p)).height,
        ];
        expect(
          altos.where((a) => a == FormasApp.segmentoTiempoActual),
          hasLength(1),
        );
        expect(altos.where((a) => a == FormasApp.segmentoTiempo), hasLength(2));
      }
      expect(xs[1], greaterThan(xs[0]));
      expect(xs[2], greaterThan(xs[1]));
    });
  });

  // ── Tarjeta de destino ──────────────────────────────────────────────────

  group('tarjeta de destino', () {
    testWidgets('elegida: borde y tilde en acento; TalkBack la lee elegida', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      var tocada = '';
      await armar(
        tester,
        Column(
          children: [
            TarjetaDestino(
              icono: Icons.school_rounded,
              nombre: 'Aula 12',
              detalle: 'Piso 1 · a 25 m',
              detalleSemantico: 'Piso 1, a 25 metros',
              seleccionada: true,
              alTocar: () => tocada = 'aula',
            ),
            TarjetaDestino(
              icono: Icons.wc_rounded,
              nombre: 'Baño',
              detalle: 'Planta baja · a 12 m',
              seleccionada: false,
              alTocar: () => tocada = 'baño',
            ),
          ],
        ),
      );
      final tarjetas = find.byType(TarjetaDestino);
      expect(
        tester.getSemantics(tarjetas.first),
        isSemantics(
          label: 'Aula 12, Piso 1, a 25 metros',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(tarjetas.last),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true),
      );
      final elegida = relieveDe(tester, tarjetas.first);
      final otra = relieveDe(tester, tarjetas.last);
      expect(elegida.borde.color, ColoresApp.acento);
      expect(elegida.borde.width, 1);
      expect(otra.borde.color, ColoresApp.borde);
      expect(elegida.elevacion, 1);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded)).color,
        ColoresApp.acento,
      );
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
      await tester.tap(tarjetas.last);
      expect(tocada, 'baño');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantica.dispose();
    });
  });

  // ── Tarjeta de una lista ────────────────────────────────────────────────

  group('tarjeta de lista', () {
    const eliminar = CustomSemanticsAction(label: 'Eliminar');

    /// Lo que dice TalkBack, en orden (sin los nodos que no dicen nada).
    List<String> orden(WidgetTester tester) => tester.semantics
        .simulatedAccessibilityTraversal()
        .map((nodo) => nodo.getSemanticsData().label)
        .where((etiqueta) => etiqueta.isNotEmpty)
        .toList();

    testWidgets('levantada y con borde; se lee de una vez (con su etiqueta) y '
        'se toca entera; la acción va aparte, después, y tocarla no la hunde', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final toques = <String>[];
      await armar(
        tester,
        TarjetaLista(
          icono: Icons.layers_rounded,
          titulo: 'Planta baja',
          subtitulo: 'Deslizá para eliminar',
          etiquetaSemantica: 'Planta baja',
          acciones: [
            BotonRedondo(
              icono: Icons.edit_rounded,
              etiqueta: 'Cambiar número de Planta baja',
              alPresionar: () => toques.add('número'),
            ),
          ],
          alTocar: () => toques.add('tarjeta'),
        ),
      );
      final tarjeta = find.byType(TarjetaLista);
      final d = relieveDe(tester, tarjeta);
      expect(d.elevacion, 1);
      expect(d.color, ColoresApp.superficie);
      expect(d.radio, FormasApp.bordeTarjeta);
      expect(d.borde.color, ColoresApp.borde);
      expect(find.byType(CuadroIcono), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(orden(tester), ['Planta baja', 'Cambiar número de Planta baja']);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Planta baja')),
        isSemantics(label: 'Planta baja', isButton: true, hasTapAction: true),
      );
      // Sin alEliminar, sin la acción ni el deslizar.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Planta baja'))
            .getSemanticsData()
            .customSemanticsActionIds,
        anyOf(isNull, isEmpty),
      );
      expect(find.byType(Dismissible), findsNothing);

      // Se toca en el texto y en el borde.
      await tester.tapAt(tester.getCenter(find.text('Planta baja')));
      await tester.tapAt(
        tester.getRect(tarjeta).bottomLeft + const Offset(8, -8),
      );
      expect(toques, ['tarjeta', 'tarjeta']);

      // Presionada la acción, la tarjeta no se hunde.
      final accion = await tester.startGesture(
        tester.getCenter(find.byTooltip('Cambiar número de Planta baja')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(relieveDe(tester, tarjeta).elevacion, 1);
      await accion.up();
      await tester.pumpAndSettle();
      expect(toques, ['tarjeta', 'tarjeta', 'número']);

      // Presionada la tarjeta, sí.
      final dedo = await tester.startGesture(
        tester.getCenter(find.text('Planta baja')),
      );
      await tester.pumpAndSettle();
      expect(relieveDe(tester, tarjeta).elevacion, -1);
      expect(relieveDe(tester, tarjeta).color, ColoresApp.hundido);
      await dedo.up();
      await tester.pumpAndSettle();
      expect(relieveDe(tester, tarjeta).elevacion, 1);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    });

    testWidgets('el subtítulo en ámbar, algo para mirar; con la letra al '
        '200 %, sin el cuadro del ícono y la acción debajo del texto', (
      tester,
    ) async {
      await armar(
        tester,
        TarjetaLista(
          icono: Icons.layers_rounded,
          titulo: 'Entrepiso',
          subtitulo: 'Sin número de piso',
          tonoSubtitulo: TonoDato.advertencia,
          acciones: [
            BotonRedondo(
              icono: Icons.edit_rounded,
              etiqueta: 'Cambiar número de Entrepiso',
              alPresionar: () {},
            ),
          ],
          alTocar: () {},
        ),
        escala: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text('Sin número de piso')).style!.color,
        ColoresApp.advertencia,
      );
      expect(find.byType(CuadroIcono), findsNothing);
      expect(
        tester.getRect(find.byTooltip('Cambiar número de Entrepiso')).top,
        greaterThan(tester.getRect(find.text('Sin número de piso')).bottom),
      );
    });

    testWidgets('con alEliminar: el tacho («Eliminar Planta baja», en rojo, '
        'después de la tarjeta) y la acción «Eliminar» de TalkBack piden '
        'confirmar y, si se confirma, avisan que se eliminó', (tester) async {
      final semantica = tester.ensureSemantics();
      var confirmar = false;
      var pedidos = 0;
      var eliminada = 0;
      await armar(
        tester,
        TarjetaLista(
          key: const ValueKey<String>('pb'),
          icono: Icons.layers_rounded,
          titulo: 'Planta baja',
          alTocar: () {},
          alEliminar: () async {
            pedidos++;
            return confirmar;
          },
          alEliminada: () => eliminada++,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Planta baja')),
        isSemantics(isButton: true, customActions: [eliminar]),
      );
      tester.semantics.customAction(
        find.semantics.byLabel('Planta baja'),
        eliminar,
      );
      await tester.pumpAndSettle();
      expect((pedidos, eliminada), (1, 0));
      confirmar = true;
      tester.semantics.customAction(
        find.semantics.byLabel('Planta baja'),
        eliminar,
      );
      await tester.pumpAndSettle();
      expect((pedidos, eliminada), (2, 1));

      // El tacho: un botón aparte, después de la tarjeta, en rojo.
      expect(orden(tester), ['Planta baja', 'Eliminar Planta baja']);
      final tacho = find.byTooltip('Eliminar Planta baja');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Eliminar Planta baja')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      final estilo = tester
          .widget<FilledButton>(
            find.descendant(of: tacho, matching: find.byType(FilledButton)),
          )
          .style!;
      expect(estilo.foregroundColor!.resolve({}), ColoresApp.error);
      await tester.tap(tacho);
      await tester.pumpAndSettle();
      expect((pedidos, eliminada), (3, 2));
      confirmar = false;
      await tester.tap(tacho);
      await tester.pumpAndSettle();
      expect((pedidos, eliminada), (4, 2));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
    });

    testWidgets('los botones van al lado del texto si le dejan 140 dp; si no, '
        'debajo, alineados con el texto, con el tacho aparte en la otra '
        'punta', (tester) async {
      final semantica = tester.ensureSemantics();
      Widget tarjeta(String titulo, {required bool conAcciones}) =>
          TarjetaLista(
            key: ValueKey<String>(titulo),
            icono: Icons.layers_rounded,
            titulo: titulo,
            alTocar: () {},
            acciones: [
              if (conAcciones) ...[
                BotonRedondo(
                  icono: Icons.navigation_rounded,
                  etiqueta: 'Probar navegación en $titulo',
                  alPresionar: () {},
                ),
                BotonRedondo(
                  icono: Icons.edit_rounded,
                  etiqueta: 'Cambiar número de $titulo',
                  alPresionar: () {},
                ),
              ],
            ],
            alEliminar: () async => false,
          );
      await armar(
        tester,
        Column(
          children: [
            tarjeta('Hospital', conAcciones: false),
            tarjeta('Piso 1', conAcciones: true),
          ],
        ),
      );
      // Sólo el tacho: al lado del texto.
      final hospital = tester.getRect(find.text('Hospital'));
      final tachoHospital = tester.getRect(find.byTooltip('Eliminar Hospital'));
      expect(tachoHospital.center.dy, closeTo(hospital.center.dy, 12));
      expect(tachoHospital.left, greaterThan(hospital.right));
      // Tres botones: debajo; el primero, con su dibujo alineado con el texto
      // (36 en el medio de 48); el tacho, en la otra punta.
      final piso = tester.getRect(find.text('Piso 1'));
      final probar = tester.getRect(
        find.byTooltip('Probar navegación en Piso 1'),
      );
      final tachoPiso = tester.getRect(find.byTooltip('Eliminar Piso 1'));
      expect(probar.top, greaterThan(piso.bottom));
      expect(probar.left + 6, moreOrLessEquals(piso.left));
      expect(tachoPiso.top, moreOrLessEquals(probar.top));
      final tarjetaPiso = tester.getRect(
        find.widgetWithText(TarjetaLista, 'Piso 1'),
      );
      expect(
        tachoPiso.right,
        moreOrLessEquals(tarjetaPiso.right - EspaciadoApp.rellenoTarjeta),
      );
      expect(orden(tester), [
        'Hospital',
        'Eliminar Hospital',
        'Piso 1',
        'Probar navegación en Piso 1',
        'Cambiar número de Piso 1',
        'Eliminar Piso 1',
      ]);
      semantica.dispose();
    });

    for (final reducido in [false, true]) {
      testWidgets('deslizada${reducido ? ', con movimiento reducido,' : ''}: '
          'detrás, el tacho y «Eliminar» en rojo sobre lo hundido; sin '
          'confirmar, vuelve; confirmada, se va'
          '${reducido ? ' sin cerrar el lugar de a poco' : ''}', (
        tester,
      ) async {
        var confirmar = false;
        var visible = true;
        await armar(
          tester,
          StatefulBuilder(
            builder: (context, setState) => visible
                ? TarjetaLista(
                    key: const ValueKey<String>('pb'),
                    icono: Icons.layers_rounded,
                    titulo: 'Planta baja',
                    alTocar: () {},
                    alEliminar: () async => confirmar,
                    alEliminada: () => setState(() => visible = false),
                  )
                : const SizedBox.shrink(),
          ),
          sinAnimaciones: reducido,
        );
        final tarjeta = find.byType(TarjetaLista);
        final lugar = tester.getRect(tarjeta);

        // A mitad de camino.
        final dedo = await tester.startGesture(tester.getCenter(tarjeta));
        await dedo.moveBy(const Offset(-40, 0));
        await tester.pump();
        await dedo.moveBy(const Offset(-100, 0));
        await tester.pump();
        final texto = tester.widget<Text>(find.text('Eliminar'));
        expect(texto.style!.color, ColoresApp.error);
        expect(
          tester
              .widget<Icon>(
                find.descendant(
                  of: find.ancestor(
                    of: find.text('Eliminar'),
                    matching: find.byType(Row),
                  ),
                  matching: find.byIcon(Icons.delete_rounded),
                ),
              )
              .color,
          ColoresApp.error,
        );
        final fondo =
            tester
                    .widget<DecoratedBox>(
                      find
                          .ancestor(
                            of: find.text('Eliminar'),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as DecoracionRelieve;
        expect(fondo.elevacion, -1);
        expect(fondo.color, ColoresApp.hundido);
        expect(
          contraste(ColoresApp.error, ColoresApp.hundido),
          greaterThan(4.5),
        );
        // Soltada despacio pasado el 40 %: pide confirmar; no, y vuelve.
        await dedo.moveBy(const Offset(-60, 0));
        await tester.pump(const Duration(seconds: 1));
        await dedo.up();
        await tester.pumpAndSettle();
        expect(tester.getRect(tarjeta), lugar);
        expect(visible, isTrue);

        // Confirmada: se va.
        confirmar = true;
        await tester.timedDrag(
          tarjeta,
          const Offset(-250, 0),
          const Duration(seconds: 1),
        );
        await tester.pump();
        await tester.pump();
        if (reducido) {
          // Sin deslizarse ni cerrar el lugar de a poco: ya se fue.
          expect(visible, isFalse);
        } else {
          // Todavía se está yendo.
          expect(visible, isTrue);
          await tester.pumpAndSettle();
          expect(visible, isFalse);
        }
        await tester.pump();
        expect(tarjeta, findsNothing);
      });
    }
  });

  // ── Galería y pantallas de referencia ───────────────────────────────────

  group('deslizador', () {
    testWidgets('el nombre y el valor escritos, que TalkBack no repite: dice '
        'el nombre y el valor con su unidad, y lo sube y lo baja; al soltarlo '
        'avisa; 48 dp de alto', (tester) async {
      final semantica = tester.ensureSemantics();
      var valor = 0.8;
      final soltados = <double>[];
      await armar(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Deslizador(
            etiqueta: 'Tamaño de celda',
            valor: valor,
            min: 0.5,
            max: 1,
            divisiones: 5,
            formato: (v) => '${v.toStringAsFixed(1)} m',
            formatoSemantico: (v) => '${v.toStringAsFixed(1)} metros',
            ayuda: 'Menor, más precisión.',
            alCambiar: (v) => setState(() => valor = v),
            alTerminar: soltados.add,
          ),
        ),
      );
      expect(find.text('Tamaño de celda'), findsOneWidget);
      expect(find.text('0.8 m'), findsOneWidget);
      final nodo = find.bySemanticsLabel('Tamaño de celda');
      expect(
        tester.getSemantics(nodo),
        isSemantics(
          label: 'Tamaño de celda',
          value: '0.8 metros',
          increasedValue: '0.9 metros',
          decreasedValue: '0.7 metros',
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      // Lo escrito arriba no se lee aparte.
      expect(find.bySemanticsLabel('0.8 m'), findsNothing);
      tester.semantics.increase(find.semantics.byLabel('Tamaño de celda'));
      await tester.pumpAndSettle();
      expect(valor, closeTo(0.9, 1e-9));
      expect(find.text('0.9 m'), findsOneWidget);
      // Arrastrado hasta el final y soltado.
      await tester.drag(find.byType(Slider), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(valor, 1);
      expect(soltados.last, 1);
      expect(tester.getSize(find.byType(Slider)).height, 48);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantica.dispose();
    });

    testWidgets('sin el globo, las marcas ni el halo de Material; '
        'deshabilitado, apagado', (tester) async {
      final semantica = tester.ensureSemantics();
      await armar(
        tester,
        Deslizador(
          etiqueta: 'Potencia mínima',
          valor: -70,
          min: -100,
          max: -40,
          divisiones: 12,
          formato: (v) => 'Desde ${v.round()} dBm',
          alCambiar: null,
        ),
      );
      final tema = tester
          .widget<SliderTheme>(
            find.ancestor(
              of: find.byType(Slider),
              matching: find.byType(SliderTheme),
            ),
          )
          .data;
      expect(tema.showValueIndicator, ShowValueIndicator.never);
      expect(tema.tickMarkShape, SliderTickMarkShape.noTickMark);
      expect(tema.overlayColor, Colors.transparent);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Potencia mínima')),
        isSemantics(
          value: 'Desde -70 dBm',
          isSlider: true,
          isEnabled: false,
          hasEnabledState: true,
        ),
      );
      // El nombre y el valor, en gris.
      expect(
        tester.widget<Text>(find.text('Desde -70 dBm')).style!.color,
        ColoresApp.textoSecundario,
      );
      semantica.dispose();
    });

    testWidgets('con la letra al 200 %: el valor baja debajo del nombre, '
        'nada se desborda', (tester) async {
      await armar(
        tester,
        Deslizador(
          etiqueta: 'Ajuste fino',
          valor: 90,
          min: 0,
          max: 359,
          divisiones: 359,
          formato: (v) => '${v.round()}°',
          alCambiar: (_) {},
        ),
        escala: 2,
      );
      expect(tester.takeException(), isNull);
      final nombre = tester.getRect(find.text('Ajuste fino'));
      final valor = tester.getRect(find.text('90°'));
      expect(valor.top, greaterThanOrEqualTo(nombre.bottom));
      expect(valor.left, nombre.left);
    });
  });

  group('galería', () {
    /// Recorre la lista de la pantalla hasta el final.
    Future<void> recorrer(WidgetTester tester) async {
      final lista = find.byType(Scrollable).first;
      for (var i = 0; i < 80; i++) {
        final antes = tester.state<ScrollableState>(lista).position.pixels;
        await tester.drag(lista, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (tester.state<ScrollableState>(lista).position.pixels == antes) {
          return;
        }
      }
    }

    /// Abre la pantalla de referencia [nombre] desde la pestaña Componentes.
    Future<void> abrir(WidgetTester tester, String nombre) async {
      final fila = find.text(nombre);
      // Desde el principio de la lista, hasta que esté armada (con letra
      // grande puede quedar lejos) y arriba, lejos de la barra flotante.
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        fila,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(fila);
      await tester.pumpAndSettle();
      await tester.tap(fila);
      await tester.pumpAndSettle();
    }

    Future<void> volver(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
    }

    void configurar(WidgetTester tester, double escala) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 72, bottom: 72);
      tester.platformDispatcher.textScaleFactorTestValue = escala;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'se arma entera con la letra al ${(escala * 100).round()} %, sin '
        'desbordes, con 48 dp y etiquetas',
        (tester) async {
          configurar(tester, escala);
          final semantica = tester.ensureSemantics();

          await tester.pumpWidget(const AppGaleria());
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await recorrer(tester);

          for (final pestana in ['Texto', 'Colores', 'Componentes']) {
            await tester.tap(find.text(pestana));
            await tester.pumpAndSettle();
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await recorrer(tester);
          }
          semantica.dispose();
        },
      );

      testWidgets('las pantallas de referencia, con la letra al '
          '${(escala * 100).round()} %', (tester) async {
        configurar(tester, escala);
        final semantica = tester.ensureSemantics();
        await tester.pumpWidget(const AppGaleria());
        await tester.pumpAndSettle();

        await abrir(tester, 'Navegación');
        expect(find.byType(BarraAcciones), findsOneWidget);
        // Con letra grande, el plano y la línea de tiempo quedan más abajo:
        // se arman al llegar.
        final lista = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.byType(LineaTiempo),
          300,
          scrollable: lista,
        );
        expect(find.byType(LineaTiempo), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byType(LineaRuta),
          -300,
          scrollable: lista,
        );
        expect(
          tester.getSemantics(find.byType(LineaRuta)),
          isSemantics(label: 'Tramo 2 de 3, 6 metros'),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await recorrer(tester);
        await volver(tester);

        await abrir(tester, 'Elegir destino');
        expect(find.text('Ir a Aula 12'), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        // Elegir otro lugar cambia el botón.
        await tester.scrollUntilVisible(
          find.text('Bar'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Bar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bar'));
        await tester.pumpAndSettle();
        expect(find.text('Ir a Bar'), findsOneWidget);
        // El filtro deja sólo los de su rubro.
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Baños'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Baños'));
        await tester.pumpAndSettle();
        expect(find.byType(TarjetaDestino), findsOneWidget);
        await recorrer(tester);
        semantica.dispose();
      });
    }

    testWidgets('el texto pasa el contraste de WCAG en todas las pantallas', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(const AppGaleria());
      await tester.pumpAndSettle();

      Future<void> revisar() async {
        final lista = find.byType(Scrollable).first;
        for (var i = 0; i < 50; i++) {
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          final antes = tester.state<ScrollableState>(lista).position.pixels;
          await tester.drag(lista, const Offset(0, -500));
          await tester.pumpAndSettle();
          if (tester.state<ScrollableState>(lista).position.pixels == antes) {
            break;
          }
        }
      }

      for (final pestana in ['Texto', 'Colores', 'Componentes']) {
        await tester.tap(find.text(pestana));
        await tester.pumpAndSettle();
        await revisar();
      }
      for (final pantalla in ['Navegación', 'Elegir destino']) {
        await abrir(tester, pantalla);
        await revisar();
        await volver(tester);
      }
      semantica.dispose();
    });

    testWidgets('la vista previa fuerza la letra en toda la galería', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const AppGaleria());
      await tester.pumpAndSettle();
      double escalaDe(String texto) => tester
          .renderObject<RenderParagraph>(find.text(texto).first)
          .textScaler
          .scale(1);
      expect(escalaDe('Vista previa'), 1);
      await tester.tap(find.text('200 %').first);
      await tester.pumpAndSettle();
      expect(escalaDe('Vista previa'), 2);
      // También en las barras.
      expect(escalaDe('Galería de componentes'), 2);
      expect(tester.takeException(), isNull);
    });
  });
}
