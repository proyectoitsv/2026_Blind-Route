import 'dart:async';
import 'dart:convert';

import 'package:blindroute/design/design.dart';
import 'package:blindroute/pantalla_mapas_admin.dart';
import 'package:blindroute/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ayudas_pantallas.dart';
import 'nube_falsa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MAPAS PUBLICADOS DEL ADMINISTRADOR (fase 5.5 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// La tarjeta de cada mapa (propio, de otro administrador y mientras se
// elimina, con su miniatura) y la pantalla de verdad, con Supabase iniciado
// como en main_admin.dart, la sesión de prueba y el MaterialApp de la app
// (el tema de antes): «Tus mapas» primero, qué dice TalkBack y en qué orden,
// «Cargando mapas…», sin conexión con «Reintentar», sin mapas, eliminar (la
// confirmación, «Eliminando…», el aviso y la lista otra vez), el error si la
// nube no deja, y la letra al 200 % con Inter de verdad
// (ayudas_pantallas.dart).
//
// ─── La nube ───
// La de prueba (nube_falsa.dart), con un catálogo en memoria (abajo) que
// contesta como Supabase: la lista de los mapas, las miniaturas (que no
// llegan: se ve el ícono) y, al eliminar uno, dónde está su imagen, la imagen
// borrada y la fila borrada.

/// Una fila de mapas_publicados como la devuelve Supabase.
Map<String, Object?> _fila(
  String id,
  String edificio,
  String piso, {
  String? dueno,
  String imagen = '',
}) => {
  'id': id,
  'edificio_nombre': edificio,
  'piso_nombre': piso,
  'imagen_path': imagen,
  'num_beacons': 4,
  'num_calibraciones': 12,
  'actualizado_en': '2026-11-05T12:00:00Z',
  'publicado_por': dueno,
};

/// Un mapa de ejemplo, para las tarjetas.
MapaPublicadoResumen _mapa(String piso, {String edificio = 'Facultad'}) =>
    MapaPublicadoResumen(
      id: piso,
      edificioNombre: edificio,
      pisoNombre: piso,
      imagenPath: '',
      numBeacons: 4,
      numCalibraciones: 12,
      actualizadoEn: DateTime(2026, 11, 5),
    );

/// Arma [tarjetas] en una lista, como en la pantalla, con la letra en
/// [escala].
Future<void> _armarTarjetas(
  WidgetTester tester,
  List<Widget> tarjetas, {
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

/// Entra con la sesión de prueba: los mapas de idAdminDePrueba son propios.
Future<void> _entrar(WidgetTester tester) async {
  await tester.runAsync(() async {
    final antes = nubeFalsa.contestar;
    nubeFalsa.contestar = contestarSesion;
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'admin@ejemplo.com',
      password: 'una clave',
    );
    nubeFalsa.contestar = antes;
  });
  nubeFalsa.pedidos.clear();
}

/// Lo que dice el error de la pantalla, debajo del título.
String? _detalleError(WidgetTester tester) =>
    tester.widget<EstadoPantalla>(find.byType(EstadoPantalla)).detalle;

/// El texto del error trae el de la excepción de Supabase, con "palabras"
/// más largas que un renglón.
bool _esDetalleError(String texto) =>
    texto.startsWith('No se pudieron cargar los mapas');

void main() {
  late _Catalogo catalogo;

  setUpAll(() async {
    await cargarInter();
    await iniciarSupabaseDePrueba();
  });

  setUp(() {
    AjustesMovimiento.instancia.reiniciarParaTests();
    nubeFalsa.reiniciar();
    catalogo = _Catalogo([
      _fila(
        'pb',
        'Facultad de Ingeniería',
        'Planta baja',
        dueno: idAdminDePrueba,
        imagen: 'pb.png',
      ),
      _fila('p1', 'Facultad de Ingeniería', 'Piso 1', dueno: 'otro-admin'),
      _fila('hc', 'Hospital Central', 'Subsuelo 1', dueno: idAdminDePrueba),
    ]);
    nubeFalsa.contestar = catalogo.contestar;
  });

  tearDown(() async {
    if (Supabase.instance.client.auth.currentSession != null) {
      nubeFalsa.contestar = contestarSesion;
      await Supabase.instance.client.auth.signOut();
    }
  });

  group('tarjeta de un mapa publicado', () {
    testWidgets('propio: «Tuyo» y «Eliminar» en rojo, que dice de qué piso '
        'es; arriba se lee de una vez; nada en cian', (tester) async {
      final semantica = tester.ensureSemantics();
      var eliminar = 0;
      await _armarTarjetas(tester, [
        TarjetaMapaAdmin(
          mapa: _mapa('Planta baja'),
          propio: true,
          alEliminar: () => eliminar++,
        ),
      ]);
      expect(ordenTalkBack(tester), [
        'Facultad\nPlanta baja\n4 beacons y 12 calibraciones\nTuyo',
        'Eliminar Planta baja de la nube',
      ]);
      expect(find.byType(ChipApp), findsOneWidget);
      final boton = tester.widget<BotonSecundario>(
        find.byType(BotonSecundario),
      );
      expect(boton.destructivo, isTrue);
      expect(find.byType(BotonPrincipal), findsNothing);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Eliminar Planta baja de la nube'),
        ),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      await tester.tap(find.text('Eliminar'));
      expect(eliminar, 1);
      // Sin plano: el ícono de un mapa.
      expect(find.byIcon(Icons.map_rounded), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('de otro administrador: sin botón, con el candado y por qué '
        'no se puede eliminar, que TalkBack lee con lo demás', (tester) async {
      final semantica = tester.ensureSemantics();
      await _armarTarjetas(tester, [
        TarjetaMapaAdmin(
          mapa: _mapa('Piso 1'),
          propio: false,
          alEliminar: () => fail('No se elimina'),
        ),
      ]);
      expect(ordenTalkBack(tester), [
        'Facultad\nPiso 1\n4 beacons y 12 calibraciones\nSólo lo puede '
            'eliminar quien lo publicó.',
      ]);
      expect(find.byType(BotonSecundario), findsNothing);
      expect(find.text('Tuyo'), findsNothing);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('mientras se elimina: «Eliminando…» en lugar del botón, '
        'quieto, que TalkBack anuncia', (tester) async {
      final semantica = tester.ensureSemantics();
      await _armarTarjetas(tester, [
        TarjetaMapaAdmin(
          mapa: _mapa('Planta baja'),
          propio: true,
          eliminando: true,
          alEliminar: () => fail('Ya se está eliminando'),
        ),
      ]);
      expect(find.byType(BotonSecundario), findsNothing);
      expect(find.text('Eliminando…'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Eliminando Planta baja de la nube'),
        ),
        isSemantics(
          label: 'Eliminando Planta baja de la nube',
          isLiveRegion: true,
        ),
      );
      expect(find.byType(ProgressIndicator), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      semantica.dispose();
    });

    testWidgets('la miniatura pide el plano a la nube; mientras llega y si no '
        'llega, el ícono, sin nada que gire', (tester) async {
      final plano = Completer<Respuesta>();
      nubeFalsa.contestar = (metodo, url) => plano.future;
      await _armarTarjetas(tester, [
        TarjetaMapaAdmin(
          mapa: _mapa('Planta baja'),
          propio: true,
          urlImagen: SupabaseService.instance.urlImagen('pb.png'),
          alEliminar: () {},
        ),
      ]);
      expect(nubeFalsa.pedidos, [
        'GET /storage/v1/object/public/map-images/pb.png',
      ]);
      expect(find.byIcon(Icons.map_rounded), findsOneWidget);
      expect(find.byType(ProgressIndicator), findsNothing);
      plano.complete(noEncontrado);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.map_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets('con la letra al ${(escala * 100).round()} %: nada partido '
          'ni cortado; 48 dp, etiquetas y contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        await _armarTarjetas(tester, [
          TarjetaMapaAdmin(
            mapa: _mapa('Planta baja', edificio: 'Facultad de Ingeniería'),
            propio: true,
            alEliminar: () {},
          ),
          TarjetaMapaAdmin(
            mapa: _mapa('Subsuelo 2', edificio: 'Hospital Central'),
            propio: false,
            alEliminar: () {},
          ),
        ], escala: escala);
        expect(tester.takeException(), isNull);
        expect(palabrasPartidas(tester), isEmpty);
        expect(textosCortados(tester), isEmpty);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  });

  group('pantalla', () {
    testWidgets('con mapas: «Tus mapas» primero y «Otros administradores» '
        'después; lo que dice TalkBack, en orden; ningún botón principal; '
        'nada gira; 48 dp, etiquetas y contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      await _entrar(tester);
      await armarPantalla(tester, const PantallaMapasAdmin());
      expect(find.byType(AmbienteDiseno), findsOneWidget);
      expect(ordenTalkBack(tester), [
        'Mapas publicados',
        'Volver a cargar la lista',
        'Tus mapas',
        'Facultad de Ingeniería\nPlanta baja\n4 beacons y 12 calibraciones'
            '\nTuyo',
        'Eliminar Planta baja de la nube',
        'Hospital Central\nSubsuelo 1\n4 beacons y 12 calibraciones\nTuyo',
        'Eliminar Subsuelo 1 de la nube',
        'Otros administradores',
        'Facultad de Ingeniería\nPiso 1\n4 beacons y 12 calibraciones\nSólo '
            'lo puede eliminar quien lo publicó.',
      ]);
      for (final grupo in ['Tus mapas', 'Otros administradores']) {
        expect(
          tester.getSemantics(find.text(grupo)),
          isSemantics(isHeader: true),
        );
      }
      expect(
        tester.getSemantics(find.text('Mapas publicados')),
        isSemantics(isHeader: true, namesRoute: true),
      );
      expect(find.byType(BotonPrincipal), findsNothing);
      expect(find.byType(ProgressIndicator), findsNothing);
      // La miniatura del mapa con plano se pidió a la nube.
      expect(
        nubeFalsa.pedidos,
        contains('GET /storage/v1/object/public/map-images/pb.png'),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('sin sesión, ninguno es propio: todos en «Otros '
        'administradores», sin «Eliminar»', (tester) async {
      await armarPantalla(tester, const PantallaMapasAdmin());
      expect(find.text('Tus mapas'), findsNothing);
      expect(find.text('Otros administradores'), findsOneWidget);
      expect(find.byType(TarjetaMapaAdmin), findsNWidgets(3));
      expect(find.byType(BotonSecundario), findsNothing);
    });

    testWidgets('mientras carga: «Cargando mapas…», quieto, que TalkBack '
        'anuncia, con «Volver a cargar la lista» deshabilitado', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final lista = Completer<Respuesta>();
      nubeFalsa.contestar = (metodo, url) => lista.future;
      await armarPantalla(tester, const PantallaMapasAdmin());
      expect(find.text('Cargando mapas…'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Cargando mapas…')),
        isSemantics(isLiveRegion: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Volver a cargar la lista')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      expect(find.byType(ProgressIndicator), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      lista.complete((estado: 200, cuerpo: '[]'));
      await tester.pumpAndSettle();
      expect(find.text('Cargando mapas…'), findsNothing);
      semantica.dispose();
    });

    testWidgets('sin mapas: «Todavía no hay mapas publicados», que TalkBack '
        'anuncia', (tester) async {
      final semantica = tester.ensureSemantics();
      catalogo.mapas.clear();
      await armarPantalla(tester, const PantallaMapasAdmin());
      expect(ordenTalkBack(tester), [
        'Mapas publicados',
        'Volver a cargar la lista',
        'Todavía no hay mapas publicados\nPublicá un piso desde la '
            'configuración para verlo acá.',
      ]);
      expect(
        tester.getSemantics(find.text('Todavía no hay mapas publicados')),
        isSemantics(isLiveRegion: true),
      );
      semantica.dispose();
    });

    testWidgets('sin conexión: «No hay conexión con la nube» con '
        '«Reintentar»; «Reintentar», el botón de la barra y tirar hacia '
        'abajo vuelven a cargar', (tester) async {
      final semantica = tester.ensureSemantics();
      nubeFalsa.contestar = (metodo, url) async =>
          (estado: 500, cuerpo: '{"message":"Sin conexión"}');
      await armarPantalla(tester, const PantallaMapasAdmin());
      expect(find.text('No hay conexión con la nube'), findsOneWidget);
      final orden = ordenTalkBack(tester);
      expect(orden, hasLength(4));
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
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      var pedidos = nubeFalsa.pedidos.length;
      var antes = _detalleError(tester);
      Future<void> revisarQueRecargo() async {
        await tester.pumpAndSettle();
        expect(nubeFalsa.pedidos.length, pedidos + 1);
        final ahora = _detalleError(tester);
        expect(identical(ahora, antes), isFalse);
        pedidos = nubeFalsa.pedidos.length;
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
      semantica.dispose();
    });

    testWidgets('eliminar uno propio: la confirmación («Cancelar» no hace '
        'nada); «Eliminando…» mientras espera a la nube; el aviso y la lista '
        'otra vez, sin el mapa', (tester) async {
      final semantica = tester.ensureSemantics();
      await _entrar(tester);
      await armarPantalla(tester, const PantallaMapasAdmin());
      final eliminarPb = find.bySemanticsLabel(
        'Eliminar Planta baja de la nube',
      );

      await tester.tap(eliminarPb);
      await tester.pumpAndSettle();
      expect(find.text('Eliminar de la nube'), findsOneWidget);
      expect(
        find.text(
          'Se quitará "Planta baja" del catálogo. Los usuarios ya no podrán '
          'descargarlo.\n\n¿Continuar?',
        ),
        findsOneWidget,
      );
      // La acción, en un botón rojo; nunca en cian.
      expect(
        tester
            .widget<BotonSecundario>(
              find.widgetWithText(BotonSecundario, 'Eliminar').last,
            )
            .destructivo,
        isTrue,
      );
      expect(find.byType(BotonPrincipal), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar de la nube'), findsNothing);
      expect(nubeFalsa.pedidos.where((p) => p.startsWith('DELETE')), isEmpty);

      catalogo.esperarBorrado = Completer<void>();
      final listas = catalogo.listas;
      await tester.tap(eliminarPb);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(FilaBotones),
              matching: find.text('Eliminar'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      // Esperando a la nube: «Eliminando…» en ese mapa, que TalkBack
      // anuncia; los demás, igual.
      expect(find.text('Eliminando…'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Eliminando Planta baja de la nube'),
        ),
        isSemantics(isLiveRegion: true),
      );
      expect(
        find.bySemanticsLabel('Eliminar Subsuelo 1 de la nube'),
        findsOneWidget,
      );
      expect(find.byType(ProgressIndicator), findsNothing);

      catalogo.esperarBorrado!.complete();
      await tester.pumpAndSettle();
      expect(find.text('"Planta baja" eliminado'), findsOneWidget);
      expect(catalogo.listas, listas + 1);
      expect(find.text('Planta baja'), findsNothing);
      expect(find.text('Eliminando…'), findsNothing);
      expect(nubeFalsa.pedidos.where((p) => p.startsWith('DELETE')), [
        'DELETE /storage/v1/object/map-images',
        'DELETE /rest/v1/mapas_publicados',
      ]);
      semantica.dispose();
    });

    testWidgets('si la nube no lo deja eliminar: el aviso de error, y el '
        'mapa vuelve con su botón', (tester) async {
      await _entrar(tester);
      catalogo.deja = false;
      await armarPantalla(tester, const PantallaMapasAdmin());
      await tester.tap(
        find.bySemanticsLabel('Eliminar Planta baja de la nube'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(FilaBotones),
              matching: find.text('Eliminar'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Error al eliminar: Exception: No autorizado: el mapa es de otro '
          'administrador.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
      expect(find.text('Eliminando…'), findsNothing);
      expect(
        find.bySemanticsLabel('Eliminar Planta baja de la nube'),
        findsOneWidget,
      );
      expect(find.text('Planta baja'), findsOneWidget);
    });

    testWidgets('con la letra al 200 %: nada partido ni cortado; 48 dp, '
        'etiquetas y contraste, también al final de la lista y sin conexión', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _entrar(tester);
      await armarPantalla(tester, const PantallaMapasAdmin(), escala: 2);
      expect(tester.takeException(), isNull);
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), isEmpty);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.scrollUntilVisible(
        find.text('Sólo lo puede eliminar quien lo publicó.'),
        200,
      );
      await tester.pumpAndSettle();
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), isEmpty);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      nubeFalsa.contestar = (metodo, url) async =>
          (estado: 500, cuerpo: '{"message":"Sin conexión"}');
      await tester.tap(find.byTooltip('Volver a cargar la lista'));
      await tester.pumpAndSettle();
      expect(find.text('No hay conexión con la nube'), findsOneWidget);
      expect(palabrasPartidas(tester, salvo: _esDetalleError), isEmpty);
      expect(textosCortados(tester), isEmpty);
      await tester.scrollUntilVisible(find.text('Reintentar'), 200);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  });
}

/// Un catálogo de mapas publicados en memoria, que contesta como Supabase.
class _Catalogo {
  _Catalogo(this.mapas);

  final List<Map<String, Object?>> mapas;

  /// false: la nube no deja borrar la fila (como con un mapa ajeno).
  bool deja = true;

  /// Cuántas veces se pidió la lista.
  int listas = 0;

  /// Si no es null, el borrado de la fila espera a que se complete.
  Completer<void>? esperarBorrado;

  Future<Respuesta> contestar(String metodo, Uri url) async {
    final camino = url.path;
    if (camino.startsWith('/auth/')) return contestarSesion(metodo, url);
    // Las miniaturas no llegan: se ve el ícono.
    if (camino.startsWith('/storage/v1/object/public/')) return noEncontrado;
    // La imagen de un mapa que se elimina.
    if (camino.startsWith('/storage/')) return (estado: 200, cuerpo: '[]');
    final id = url.queryParameters['id']?.replaceFirst('eq.', '');
    if (metodo == 'GET' && id == null) {
      listas++;
      return (estado: 200, cuerpo: jsonEncode(mapas));
    }
    if (metodo == 'GET') {
      final mapa = mapas.firstWhere((m) => m['id'] == id);
      return (
        estado: 200,
        cuerpo: jsonEncode([
          {'imagen_path': mapa['imagen_path']},
        ]),
      );
    }
    if (metodo == 'DELETE') {
      await esperarBorrado?.future;
      if (!deja) return (estado: 200, cuerpo: '[]');
      mapas.removeWhere((m) => m['id'] == id);
      return (
        estado: 200,
        cuerpo: jsonEncode([
          {'id': id},
        ]),
      );
    }
    return noEncontrado;
  }
}
