import 'package:blindroute/design/design.dart';
import 'package:blindroute/pantalla_mapas_online.dart';
import 'package:blindroute/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ayudas_pantallas.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CATÁLOGO DE MAPAS DEL USUARIO (fase 5.2 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// La tarjeta de cada mapa en sus tres estados (nuevo, actualizable,
// descargado) y mientras se descarga, se actualiza o se quita: qué botones
// tiene, qué dice TalkBack (las etiquetas de siempre), que nada gira, y la
// letra al 200 % con Inter de verdad (ayudas_pantallas.dart), con los botones
// apilados cuando no entran. Y la pantalla entera sin la nube, que es como
// queda en los tests: el error de conexión, con «Reintentar» y «Volver a
// cargar la lista». Va con el MaterialApp de la app, con el tema de antes,
// como en main_user.dart.
//
// ─── Lo que no anda en los tests ───
// La nube (Supabase sin iniciar) y la base local. La pantalla de verdad queda
// en el error de conexión; la lista se prueba con TarjetaMapa y mapas de
// ejemplo. La carga falla enseguida, antes del cuadro siguiente, así que
// «Cargando mapas…» no llega a verse: que «Reintentar» volvió a cargar se ve
// en que el error es otro (un texto nuevo, aunque diga lo mismo).

/// Un mapa de ejemplo.
MapaPublicadoResumen _mapa(String piso) => MapaPublicadoResumen(
  id: piso,
  edificioNombre: 'Facultad de Ingeniería',
  pisoNombre: piso,
  imagenPath: '',
  numBeacons: 4,
  numCalibraciones: 12,
  actualizadoEn: DateTime(2026, 11, 5),
);

/// Lo que se tocó en las tarjetas.
final List<String> _toques = [];

TarjetaMapa _tarjeta(
  EstadoMapa estado, {
  String piso = 'Planta baja',
  OperacionMapa? operacion,
}) => TarjetaMapa(
  mapa: _mapa(piso),
  estado: estado,
  operacion: operacion,
  alDescargar: () => _toques.add('descargar $piso'),
  alActualizar: () => _toques.add('actualizar $piso'),
  alQuitar: () => _toques.add('quitar $piso'),
);

/// Arma [tarjetas] en una lista, como en el catálogo, con la letra en
/// [escala].
Future<void> _armarTarjetas(
  WidgetTester tester,
  List<TarjetaMapa> tarjetas, {
  double escala = 1,
}) => armarPantalla(
  tester,
  AmbienteDiseno(
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: EstiloApp.de(context).fondo,
        body: ListView(
          padding: const EdgeInsets.all(EspaciadoApp.margenLateral),
          children: [
            for (final tarjeta in tarjetas)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: EspaciadoApp.entreTarjetas,
                ),
                child: tarjeta,
              ),
          ],
        ),
      ),
    ),
  ),
  escala: escala,
);

/// El botón secundario con [texto] (el primero, si hay varios).
Finder _boton(String texto) =>
    find.widgetWithText(BotonSecundario, texto).first;

/// Lo que dice el error de la pantalla, debajo del título.
String? _detalleError(WidgetTester tester) =>
    tester.widget<EstadoPantalla>(find.byType(EstadoPantalla)).detalle;

/// El texto del error trae el de la excepción de Supabase, con "palabras"
/// más largas que un renglón ('package:supabase_flutter/…').
bool _esDetalleError(String texto) =>
    texto.startsWith('No se pudieron cargar los mapas');

void main() {
  setUpAll(cargarInter);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AjustesMovimiento.instancia.reiniciarParaTests();
    _toques.clear();
  });

  group('tarjeta de un mapa', () {
    testWidgets('nuevo: la marca «Nuevo» y «Descargar», con su etiqueta de '
        'siempre; nada en cian', (tester) async {
      final semantica = tester.ensureSemantics();
      await _armarTarjetas(tester, [_tarjeta(EstadoMapa.nuevo)]);
      expect(find.text('Nuevo'), findsOneWidget);
      expect(find.byType(BotonSecundario), findsOneWidget);
      expect(find.byType(BotonPrincipal), findsNothing);
      // Arriba se lee de una vez; después, el botón.
      expect(ordenTalkBack(tester), [
        'Planta baja\n4 beacons y 12 calibraciones\nNuevo',
        'Descargar Planta baja',
      ]);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Descargar Planta baja')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text('Descargar'));
      expect(_toques, ['descargar Planta baja']);
      semantica.dispose();
    });

    testWidgets('actualizable: «Actualizable», «Actualizar» y «Quitar»; '
        'descargado: «Descargado» y sólo «Quitar», en rojo', (tester) async {
      final semantica = tester.ensureSemantics();
      await _armarTarjetas(tester, [
        _tarjeta(EstadoMapa.actualizable, piso: 'Piso 1'),
        _tarjeta(EstadoMapa.descargado, piso: 'Piso 2'),
      ]);
      expect(find.text('Actualizable'), findsOneWidget);
      // La marca de antes se leía como «ya está al día».
      expect(find.text('Actualizado'), findsNothing);
      expect(find.text('Descargado'), findsOneWidget);
      expect(ordenTalkBack(tester), [
        'Piso 1\n4 beacons y 12 calibraciones\nActualizable',
        'Actualizar Piso 1',
        'Quitar Piso 1 del teléfono',
        'Piso 2\n4 beacons y 12 calibraciones\nDescargado',
        'Quitar Piso 2 del teléfono',
      ]);
      for (final quitar in tester.widgetList<BotonSecundario>(
        find.widgetWithText(BotonSecundario, 'Quitar'),
      )) {
        expect(quitar.destructivo, isTrue);
      }
      await tester.tap(find.text('Actualizar'));
      await tester.tap(find.text('Quitar').first);
      await tester.tap(find.text('Quitar').last);
      expect(_toques, ['actualizar Piso 1', 'quitar Piso 1', 'quitar Piso 2']);
      semantica.dispose();
    });

    testWidgets('mientras se descarga, se actualiza o se quita: un recuadro '
        'quieto en lugar de los botones, que TalkBack anuncia', (tester) async {
      final semantica = tester.ensureSemantics();
      await _armarTarjetas(tester, [
        _tarjeta(
          EstadoMapa.nuevo,
          piso: 'Piso 1',
          operacion: OperacionMapa.descarga,
        ),
        _tarjeta(
          EstadoMapa.actualizable,
          piso: 'Piso 2',
          operacion: OperacionMapa.actualizacion,
        ),
        _tarjeta(
          EstadoMapa.descargado,
          piso: 'Piso 3',
          operacion: OperacionMapa.borrado,
        ),
      ]);
      expect(find.byType(BotonSecundario), findsNothing);
      for (final (texto, etiqueta) in const [
        ('Descargando…', 'Descargando Piso 1'),
        ('Actualizando…', 'Actualizando Piso 2'),
        ('Quitando…', 'Quitando Piso 3 del teléfono'),
      ]) {
        expect(find.text(texto), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel(etiqueta)),
          isSemantics(label: etiqueta, isLiveRegion: true),
        );
      }
      // Nada gira: ninguna ruedita ni animación que quede corriendo.
      expect(find.byType(ProgressIndicator), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      semantica.dispose();
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'con la letra al ${(escala * 100).round()} %: nada partido ni '
        'cortado; «Actualizar» y «Quitar» ${escala == 1 ? 'lado a lado' : 'apilados'}; '
        '48 dp, etiquetas y contraste',
        (tester) async {
          final semantica = tester.ensureSemantics();
          await _armarTarjetas(tester, [
            _tarjeta(EstadoMapa.actualizable, piso: 'Piso 1'),
            _tarjeta(EstadoMapa.nuevo, piso: 'Subsuelo 2'),
          ], escala: escala);
          expect(tester.takeException(), isNull);
          expect(palabrasPartidas(tester), isEmpty);
          expect(textosCortados(tester), isEmpty);
          final actualizar = tester.getRect(_boton('Actualizar'));
          final quitar = tester.getRect(_boton('Quitar'));
          expect(quitar.width, moreOrLessEquals(actualizar.width));
          if (escala == 1) {
            expect(quitar.top, moreOrLessEquals(actualizar.top));
            expect(
              quitar.left - actualizar.right,
              moreOrLessEquals(EspaciadoApp.medio),
            );
          } else {
            expect(
              quitar.top - actualizar.bottom,
              moreOrLessEquals(EspaciadoApp.medio),
            );
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        },
      );
    }
  });

  testWidgets('el buscador con la letra al 200 %: la ayuda se parte en '
      'renglones, no se corta, y el campo no cambia de alto al escribir', (
    tester,
  ) async {
    await armarPantalla(
      tester,
      AmbienteDiseno(
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: EstiloApp.de(context).fondo,
            body: const Padding(
              padding: EdgeInsets.all(EspaciadoApp.margenLateral),
              child: CampoTexto.busqueda(
                etiqueta: 'Buscar mapa',
                ayuda: 'Buscar mapa por nombre…',
              ),
            ),
          ),
        ),
      ),
      escala: 2,
    );
    expect(textosCortados(tester), isEmpty);
    expect(palabrasPartidas(tester), isEmpty);
    // La ayuda, en más de un renglón.
    final ayuda = tester.renderObject<RenderParagraph>(
      find.text('Buscar mapa por nombre…'),
    );
    final renglones = ayuda
        .getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: ayuda.text.toPlainText().length,
          ),
        )
        .map((caja) => caja.top.round())
        .toSet();
    expect(renglones.length, greaterThan(1));
    final vacio = tester.getSize(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Piso');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TextField)).height, vacio.height);
  });

  group('pantalla sin la nube', () {
    testWidgets('«No hay conexión con la nube», con «Reintentar» y «Volver a '
        'cargar la lista»; TalkBack lo anuncia, en orden; 48 dp, etiquetas y '
        'contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(tester, const PantallaMapasOnline());
      expect(find.text('No hay conexión con la nube'), findsOneWidget);
      expect(
        find.textContaining('No se pudieron cargar los mapas'),
        findsOneWidget,
      );
      // Nada gira.
      expect(find.byType(ProgressIndicator), findsNothing);
      final orden = ordenTalkBack(tester);
      expect(orden, hasLength(4));
      expect(orden[0], 'Mapas disponibles');
      expect(orden[1], 'Volver a cargar la lista');
      expect(
        orden[2],
        startsWith(
          'No hay conexión con la nube\nNo se pudieron cargar los mapas',
        ),
      );
      expect(orden[3], 'Reintentar');
      expect(
        tester.getSemantics(find.text('No hay conexión con la nube')),
        isSemantics(isLiveRegion: true),
      );
      expect(
        tester.getSemantics(find.text('Mapas disponibles')),
        isSemantics(isHeader: true, namesRoute: true),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('con la letra al 200 %: nada cortado ni partido y se llega a '
        '«Reintentar» desplazando', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(tester, const PantallaMapasOnline(), escala: 2);
      expect(tester.takeException(), isNull);
      expect(palabrasPartidas(tester, salvo: _esDetalleError), isEmpty);
      expect(textosCortados(tester), isEmpty);
      await tester.scrollUntilVisible(find.text('Reintentar'), 200);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('«Reintentar», el botón de la barra y tirar hacia abajo '
        'vuelven a cargar la lista', (tester) async {
      await armarPantalla(tester, const PantallaMapasOnline());
      var antes = _detalleError(tester);
      Future<void> revisarQueRecargo() async {
        await tester.pumpAndSettle();
        final ahora = _detalleError(tester);
        // El mismo error, pero de otra carga.
        expect(ahora, antes);
        expect(identical(ahora, antes), isFalse);
        antes = ahora;
      }

      await tester.tap(find.text('Reintentar'));
      await revisarQueRecargo();
      await tester.tap(find.byTooltip('Volver a cargar la lista'));
      await revisarQueRecargo();
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await revisarQueRecargo();
      expect(find.text('No hay conexión con la nube'), findsOneWidget);
    });
  });
}
