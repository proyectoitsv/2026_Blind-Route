import 'package:blindroute/design/design.dart';
import 'package:blindroute/lista_edificios.dart';
import 'package:blindroute/lista_pisos.dart';
import 'package:blindroute/pantalla_config.dart';
import 'package:blindroute/pantalla_login_admin.dart';
import 'package:blindroute/pantalla_mapas_admin.dart';
import 'package:blindroute/pantalla_naveg.dart';
import 'package:blindroute/piso_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ayudas_pantallas.dart';
import 'base_falsa.dart';
import 'nube_falsa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// EDIFICIOS Y PISOS DEL ADMINISTRADOR (fase 5.4 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// Las dos listas de verdad, con el MaterialApp de la app (el tema de antes,
// como en main_admin.dart): qué dice TalkBack y en qué orden, la acción
// «Eliminar» de cada tarjeta (con TalkBack no se puede deslizar), deslizar
// para eliminar, las confirmaciones y los avisos, la hoja «Nuevo edificio»
// con su error, la hoja del número de piso, la letra al 200 % con Inter de
// verdad (ayudas_pantallas.dart) y adónde lleva cada cosa.
//
// ─── La base y la nube ───
// La base del teléfono es la de prueba (base_falsa.dart: el canal de sqflite
// atendido en memoria) y Supabase habla con la nube de prueba
// (nube_falsa.dart): borrar un edificio o un piso publicado quita sus mapas
// de la nube, y «Cerrar sesión» sale de verdad.
//
// ─── Lo que no se arma ───
// La configuración y la navegación de un piso (todavía sin migrar) y los
// mapas publicados (fase 5.5, con su test): de esas se mira qué ruta se abre
// y se saca antes de que se arme. La galería del teléfono se simula sobre el
// canal de image_picker: se cancela.

/// El canal de image_picker: la galería del teléfono.
const MethodChannel _canalGaleria = MethodChannel(
  'plugins.flutter.io/image_picker',
);

/// La acción de TalkBack de cada tarjeta.
const CustomSemanticsAction _eliminar = CustomSemanticsAction(
  label: 'Eliminar',
);

/// Carga un edificio en la base de prueba. Devuelve su id.
int _cargarEdificio(String nombre) =>
    baseFalsa.agregar('edificios', {'nombre': nombre});

/// Carga un piso en la base de prueba, como lo deja la app: con [numero],
/// el nombre derivado; sin número (un piso viejo), [nombre]. [remoto]: el
/// id del mapa publicado. Devuelve su id.
int _cargarPiso(int edificio, int? numero, {String? nombre, String? remoto}) =>
    baseFalsa.agregar('pisos', {
      'edificio_id': edificio,
      'numero_piso': numero,
      'nombre_piso': nombre ?? PisoUtil.nombre(numero!),
      'ruta_imagen': '/planos/piso_$numero.png',
      'remote_id': remoto,
    });

/// Como contesta Supabase al quitar un mapa publicado (SupabaseService
/// .eliminarMapa): dónde está la imagen, la imagen borrada y la fila
/// borrada.
Future<Respuesta> _quitaMapas(String metodo, Uri url) async {
  if (url.path.startsWith('/storage/')) return (estado: 200, cuerpo: '[]');
  if (metodo == 'GET') {
    return (estado: 200, cuerpo: '[{"imagen_path":"plano.png"}]');
  }
  return (estado: 200, cuerpo: '[{"id":"borrado"}]');
}

/// Una nube que no anda.
Future<Respuesta> _nubeCaida(String metodo, Uri url) async =>
    (estado: 500, cuerpo: '{"message":"Sin conexión"}');

/// Lo que pidió el test a la base de prueba que escribe.
Iterable<String> _escrituras() => baseFalsa.pedidos.where(
  (p) =>
      p.startsWith('INSERT') ||
      p.startsWith('UPDATE') ||
      p.startsWith('DELETE'),
);

/// La tarjeta con [titulo].
Finder _tarjeta(String titulo) => find.widgetWithText(TarjetaLista, titulo);

/// Que los botones de la hoja del número van en una grilla pareja: todos del
/// mismo ancho, los renglones (menos el último) con la misma cantidad y de
/// punta a punta. Devuelve cuántos hay por renglón.
int _revisarGrilla(WidgetTester tester) {
  final botones = find.descendant(
    of: find.byType(Wrap),
    matching: find.byWidgetPredicate(
      (w) => w is BotonSecundario || w is BotonPrincipal,
    ),
  );
  final cajas = [
    for (var i = 0; i < botones.evaluate().length; i++)
      tester.getRect(botones.at(i)),
  ];
  expect(cajas, hasLength(PisoUtil.maximo - PisoUtil.minimo + 1));
  for (final caja in cajas) {
    expect(caja.width, moreOrLessEquals(cajas.first.width, epsilon: 0.1));
  }
  final renglones = <double, List<Rect>>{};
  for (final caja in cajas) {
    renglones.putIfAbsent(caja.top, () => []).add(caja);
  }
  final cuantos = [for (final r in renglones.values) r.length];
  for (final n in cuantos.sublist(0, cuantos.length - 1)) {
    expect(n, cuantos.first);
  }
  expect(cuantos.last, lessThanOrEqualTo(cuantos.first));
  final grilla = tester.getRect(find.byType(Wrap));
  final primero = renglones.values.first;
  expect(primero.first.left, moreOrLessEquals(grilla.left, epsilon: 0.1));
  expect(primero.last.right, moreOrLessEquals(grilla.right, epsilon: 0.2));
  return cuantos.first;
}

/// Arma [pantalla] como en la app y dibuja sólo el primer cuadro, sin
/// esperar a la base.
Future<void> _armarPrimerCuadro(WidgetTester tester, Widget pantalla) async {
  tester.view.physicalSize = telefono * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: pantalla,
    ),
  );
}

/// Que el toque recién abrió, con RutaApp, la pantalla que arma [esperada];
/// la saca antes de que se arme. Devuelve la pantalla.
T _revisarYSacar<T extends Widget>(
  WidgetTester tester,
  ObservadorRutas observador,
  BuildContext contexto,
) {
  final ruta = observador.abiertas.last;
  expect(ruta, isA<RutaApp<void>>());
  final pantalla = (ruta as RutaApp<void>).builder(contexto);
  expect(pantalla, isA<T>());
  Navigator.of(contexto).removeRoute(ruta);
  return pantalla as T;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mensajero =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Lo que se le pidió a la galería del teléfono.
  final pedidosGaleria = <String>[];

  setUpAll(() async {
    await cargarInter();
    iniciarBaseDePrueba();
    await iniciarSupabaseDePrueba();
  });

  setUp(() {
    AjustesMovimiento.instancia.reiniciarParaTests();
    baseFalsa.reiniciar();
    nubeFalsa.reiniciar();
    pedidosGaleria.clear();
    mensajero.setMockMethodCallHandler(_canalGaleria, (llamada) async {
      pedidosGaleria.add(llamada.method);
      return null;
    });
  });

  tearDown(() async {
    mensajero.setMockMethodCallHandler(_canalGaleria, null);
    if (Supabase.instance.client.auth.currentSession != null) {
      nubeFalsa.contestar = contestarSesion;
      await Supabase.instance.client.auth.signOut();
    }
  });

  group('lista de edificios', () {
    testWidgets('con edificios: lo que dice TalkBack, en orden (sin «Deslizá '
        'para eliminar»: cada tarjeta tiene la acción «Eliminar»); un solo '
        'botón principal; nada gira; 48 dp, etiquetas y contraste', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      _cargarEdificio('Facultad de Ingeniería');
      _cargarEdificio('Hospital Central');
      await armarPantalla(tester, const ListaEdificios());
      expect(find.byType(AmbienteDiseno), findsOneWidget);
      expect(find.byType(TarjetaLista), findsNWidgets(2));
      expect(ordenTalkBack(tester), [
        'Blind Route — Edificios',
        'Mapas publicados en la nube',
        'Cerrar sesión',
        'Facultad de Ingeniería',
        'Eliminar Facultad de Ingeniería',
        'Hospital Central',
        'Eliminar Hospital Central',
        'Agregar edificio',
      ]);
      expect(
        tester.getSemantics(find.text('Blind Route — Edificios')),
        isSemantics(isHeader: true, namesRoute: true),
      );
      for (final nombre in ['Facultad de Ingeniería', 'Hospital Central']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(nombre)),
          isSemantics(
            label: nombre,
            isButton: true,
            hasTapAction: true,
            customActions: [_eliminar],
          ),
        );
      }
      // Se ve, pero TalkBack no lo dice: con TalkBack no se desliza.
      expect(find.text('Deslizá para eliminar'), findsNWidgets(2));
      expect(find.bySemanticsLabel(RegExp('Deslizá')), findsNothing);
      // Es la pantalla de entrada: sin volver.
      expect(find.byTooltip('Volver'), findsNothing);
      // «Agregar edificio», el único botón principal (antes, un «+» flotante
      // sin nombre).
      expect(find.byType(BotonPrincipal), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Agregar edificio')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      expect(find.byType(ProgressIndicator), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('sin edificios: mientras lee la base, nada (ni «No hay '
        'edificios registrados», que TalkBack anunciaría); después, el '
        'estado vacío, que TalkBack anuncia', (tester) async {
      final semantica = tester.ensureSemantics();
      await _armarPrimerCuadro(tester, const ListaEdificios());
      expect(find.byType(EstadoPantalla), findsNothing);
      expect(find.byType(TarjetaLista), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('No hay edificios registrados'), findsOneWidget);
      expect(ordenTalkBack(tester), [
        'Blind Route — Edificios',
        'Mapas publicados en la nube',
        'Cerrar sesión',
        'No hay edificios registrados\nTocá «Agregar edificio» para cargar '
            'el primero.',
        'Agregar edificio',
      ]);
      expect(
        tester.getSemantics(find.text('No hay edificios registrados')),
        isSemantics(isLiveRegion: true),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('con la letra al 200 %: nada partido ni cortado (salvo el '
        'título de la barra, que TalkBack lee entero), tampoco en la hoja '
        '«Nuevo edificio» con su error; 48 dp, etiquetas y contraste', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      _cargarEdificio('Facultad de Ingeniería');
      _cargarEdificio('Hospital Central');
      await armarPantalla(tester, const ListaEdificios(), escala: 2);
      expect(tester.takeException(), isNull);
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), ['Blind Route — Edificios']);
      // El cuadro del ícono no se muestra: el título se queda con el ancho.
      expect(find.byType(CuadroIcono), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(find.text('Agregar edificio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Escribí el nombre del edificio.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), ['Blind Route — Edificios']);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('tocar un edificio abre sus pisos con RutaApp; «Volver» '
        'vuelve', (tester) async {
      final id = _cargarEdificio('Facultad de Ingeniería');
      _cargarPiso(id, 0);
      final observador = await armarPantalla(tester, const ListaEdificios());
      await tester.tap(_tarjeta('Facultad de Ingeniería'));
      await tester.pumpAndSettle();
      expect(observador.abiertas.last, isA<RutaApp<void>>());
      final pisos = tester.widget<ListaPisos>(find.byType(ListaPisos));
      expect(pisos.edificioId, id);
      expect(pisos.nombreEdificio, 'Facultad de Ingeniería');
      expect(_tarjeta('Planta baja'), findsOneWidget);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(find.byType(ListaPisos), findsNothing);
      expect(_tarjeta('Facultad de Ingeniería'), findsOneWidget);
    });

    testWidgets('«Mapas publicados en la nube» abre los mapas publicados con '
        'RutaApp', (tester) async {
      final observador = await armarPantalla(tester, const ListaEdificios());
      await tester.tap(find.byTooltip('Mapas publicados en la nube'));
      _revisarYSacar<PantallaMapasAdmin>(
        tester,
        observador,
        tester.element(find.byType(ListaEdificios)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListaEdificios), findsOneWidget);
    });

    testWidgets('«Agregar edificio»: la hoja «Nuevo edificio»; vacío, el '
        'error debajo del campo, sin tocar la base; con el nombre, lo guarda '
        'y aparece; «Cancelar» no guarda', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(tester, const ListaEdificios());
      await tester.tap(find.text('Agregar edificio'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo edificio'), findsOneWidget);
      // Sin el botón redondo para cerrar: lo cierra «Cancelar».
      expect(find.byTooltip('Cerrar'), findsNothing);
      expect(ordenTalkBack(tester), [
        'Nuevo edificio',
        'Nombre\nPor ejemplo, Facultad de Ingeniería',
        'Cancelar',
        'Guardar',
        // Tocar afuera.
        'Cerrar',
      ]);

      // Vacío: el error debajo del campo, que TalkBack anuncia.
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final error = find.text('Escribí el nombre del edificio.');
      expect(error, findsOneWidget);
      expect(
        tester.getRect(error).top,
        greaterThan(tester.getRect(find.byType(TextField)).bottom),
      );
      expect(tester.getSemantics(error), isSemantics(isLiveRegion: true));
      expect(_escrituras(), isEmpty);

      // Escribir le borra el error; «Guardar» lo guarda y cierra la hoja.
      await tester.enterText(find.byType(TextField), 'Biblioteca');
      await tester.pump();
      expect(error, findsNothing);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo edificio'), findsNothing);
      expect(baseFalsa.filas('edificios').single['nombre'], 'Biblioteca');
      expect(_tarjeta('Biblioteca'), findsOneWidget);

      // «Cancelar» no guarda.
      await tester.tap(find.text('Agregar edificio'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Otro');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo edificio'), findsNothing);
      expect(baseFalsa.filas('edificios'), hasLength(1));

      // «Listo» en el teclado guarda.
      await tester.tap(find.text('Agregar edificio'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Rectorado');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Nuevo edificio'), findsNothing);
      expect(baseFalsa.filas('edificios').map((f) => f['nombre']), [
        'Biblioteca',
        'Rectorado',
      ]);
      semantica.dispose();
    });

    testWidgets('«Eliminar» de TalkBack: la confirmación en una hoja; '
        '«Cancelar» no borra; «Eliminar todo» quita sus mapas de la nube, lo '
        'borra con sus pisos y avisa', (tester) async {
      final semantica = tester.ensureSemantics();
      final id = _cargarEdificio('Facultad de Ingeniería');
      _cargarPiso(id, 0, remoto: 'mapa-pb');
      _cargarPiso(id, 1);
      _cargarEdificio('Hospital Central');
      nubeFalsa.contestar = _quitaMapas;
      await armarPantalla(tester, const ListaEdificios());

      tester.semantics.customAction(
        find.semantics.byLabel('Facultad de Ingeniería'),
        _eliminar,
      );
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar edificio?'), findsOneWidget);
      expect(
        find.text(
          'Se eliminará "Facultad de Ingeniería", incluyendo todos sus pisos '
          'y beacons. Esta acción es permanente.',
        ),
        findsOneWidget,
      );
      // La acción, en un botón rojo; nunca en cian.
      final eliminarTodo = tester.widget<BotonSecundario>(
        find.widgetWithText(BotonSecundario, 'Eliminar todo'),
      );
      expect(eliminarTodo.destructivo, isTrue);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar edificio?'), findsNothing);
      expect(baseFalsa.filas('edificios'), hasLength(2));
      expect(nubeFalsa.pedidos, isEmpty);
      expect(_escrituras(), isEmpty);

      tester.semantics.customAction(
        find.semantics.byLabel('Facultad de Ingeniería'),
        _eliminar,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar todo'));
      await tester.pumpAndSettle();
      // Primero la nube (la imagen y la fila del piso publicado), después
      // el teléfono.
      expect(nubeFalsa.pedidos, [
        'GET /rest/v1/mapas_publicados',
        'DELETE /storage/v1/object/map-images',
        'DELETE /rest/v1/mapas_publicados',
      ]);
      expect(baseFalsa.filas('edificios').map((f) => f['nombre']), [
        'Hospital Central',
      ]);
      expect(baseFalsa.filas('pisos'), isEmpty);
      expect(
        find.text('Se eliminó Facultad de Ingeniería y todos sus datos'),
        findsOneWidget,
      );
      expect(_tarjeta('Facultad de Ingeniería'), findsNothing);
      expect(_tarjeta('Hospital Central'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('el tacho de cada edificio («Eliminar Hospital Central», en '
        'rojo) pide la misma confirmación y lo borra', (tester) async {
      _cargarEdificio('Facultad de Ingeniería');
      _cargarEdificio('Hospital Central');
      await armarPantalla(tester, const ListaEdificios());
      final tacho = find.byTooltip('Eliminar Hospital Central');
      expect(
        tester
            .widget<BotonRedondo>(
              find.ancestor(of: tacho, matching: find.byType(BotonRedondo)),
            )
            .destructivo,
        isTrue,
      );
      await tester.tap(tacho);
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar edificio?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('edificios'), hasLength(2));
      await tester.tap(tacho);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar todo'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('edificios').map((f) => f['nombre']), [
        'Facultad de Ingeniería',
      ]);
      expect(_tarjeta('Hospital Central'), findsNothing);
      expect(
        find.text('Se eliminó Hospital Central y todos sus datos'),
        findsOneWidget,
      );
    });

    testWidgets('si no se puede quitar un mapa de la nube: avisa con un '
        'error y no borra nada', (tester) async {
      final semantica = tester.ensureSemantics();
      final id = _cargarEdificio('Facultad de Ingeniería');
      _cargarPiso(id, 0, remoto: 'mapa-pb');
      nubeFalsa.contestar = _nubeCaida;
      await armarPantalla(tester, const ListaEdificios());
      tester.semantics.customAction(
        find.semantics.byLabel('Facultad de Ingeniería'),
        _eliminar,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar todo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          RegExp(
            r'^No se pudo quitar un mapa de la nube: .*\nNo se eliminó el '
            r'edificio\.$',
            dotAll: true,
          ),
        ),
        findsOneWidget,
      );
      // Un aviso de error: con el ícono.
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
      expect(baseFalsa.filas('edificios'), hasLength(1));
      expect(baseFalsa.filas('pisos'), hasLength(1));
      expect(_escrituras(), isEmpty);
      expect(_tarjeta('Facultad de Ingeniería'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('deslizar hacia la izquierda: detrás, «Eliminar» en rojo y '
        'la misma confirmación; cancelada, la tarjeta vuelve; confirmada, se '
        'va y se borra', (tester) async {
      _cargarEdificio('Facultad de Ingeniería');
      _cargarEdificio('Hospital Central');
      await armarPantalla(tester, const ListaEdificios());
      final tarjeta = _tarjeta('Facultad de Ingeniería');
      final lugar = tester.getRect(tarjeta);

      await tester.drag(tarjeta, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar edificio?'), findsOneWidget);
      final detras = find.text('Eliminar');
      expect(detras, findsOneWidget);
      expect(tester.widget<Text>(detras).style!.color, ColoresApp.error);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.getRect(tarjeta), lugar);
      expect(baseFalsa.filas('edificios'), hasLength(2));

      await tester.drag(tarjeta, const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar todo'));
      await tester.pumpAndSettle();
      expect(tarjeta, findsNothing);
      expect(baseFalsa.filas('edificios').map((f) => f['nombre']), [
        'Hospital Central',
      ]);
      // La otra sube a su lugar.
      expect(tester.getRect(_tarjeta('Hospital Central')).top, lugar.top);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Cerrar sesión» sale de Supabase y vuelve al login, con '
        'RutaApp, en lugar de la lista', (tester) async {
      await tester.runAsync(() async {
        nubeFalsa.contestar = contestarSesion;
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'admin@ejemplo.com',
          password: 'una clave',
        );
      });
      expect(Supabase.instance.client.auth.currentSession, isNotNull);
      final observador = await armarPantalla(tester, const ListaEdificios());
      nubeFalsa.pedidos.clear();
      await tester.tap(find.byTooltip('Cerrar sesión'));
      // Salir de Supabase pasa por el almacenamiento del teléfono, que anda
      // con el reloj de verdad (se armó en el setUpAll): se le da tiempo.
      for (var i = 0; i < 20 && observador.reemplazantes.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(nubeFalsa.pedidos, ['POST /auth/v1/logout']);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      expect(observador.reemplazantes.single, isA<RutaApp<void>>());
      await tester.pumpAndSettle();
      expect(find.byType(PantallaLoginAdmin), findsOneWidget);
      expect(find.byType(ListaEdificios), findsNothing);
    });
  });

  group('lista de pisos', () {
    /// Arma los pisos del edificio [id], como en la app.
    Future<ObservadorRutas> armarPisos(
      WidgetTester tester,
      int id, {
      double escala = 1,
    }) => armarPantalla(
      tester,
      ListaPisos(edificioId: id, nombreEdificio: 'Facultad de Ingeniería'),
      escala: escala,
    );

    testWidgets('con pisos, en orden (los sin número al final): lo que dice '
        'TalkBack, con «Probar navegación» y «Cambiar número» de cada piso; '
        'el piso sin número, en ámbar; 48 dp, etiquetas y contraste', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final id = _cargarEdificio('Facultad de Ingeniería');
      _cargarPiso(id, 1);
      _cargarPiso(id, null, nombre: 'Entrepiso');
      _cargarPiso(id, 0);
      await armarPisos(tester, id);
      expect(find.byType(AmbienteDiseno), findsOneWidget);
      expect(ordenTalkBack(tester), [
        'Facultad de Ingeniería',
        'Planta baja',
        'Probar navegación en Planta baja',
        'Cambiar número de Planta baja',
        'Eliminar Planta baja',
        'Piso 1',
        'Probar navegación en Piso 1',
        'Cambiar número de Piso 1',
        'Eliminar Piso 1',
        'Entrepiso, sin número de piso',
        'Probar navegación en Entrepiso',
        'Cambiar número de Entrepiso',
        'Eliminar Entrepiso',
        'Agregar piso',
      ]);
      for (final nombre in ['Planta baja', 'Entrepiso, sin número de piso']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(nombre)),
          isSemantics(
            label: nombre,
            isButton: true,
            hasTapAction: true,
            customActions: [_eliminar],
          ),
        );
      }
      final aviso = tester.widget<Text>(
        find.text('Sin número de piso: tocá el lápiz para asignarlo'),
      );
      expect(aviso.style!.color, ColoresApp.advertencia);
      expect(find.text('Deslizá para eliminar'), findsNWidgets(2));
      expect(find.byType(BotonPrincipal), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(ProgressIndicator), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('sin pisos: «No hay pisos agregados», que TalkBack anuncia; '
        'mientras lee la base, nada', (tester) async {
      final semantica = tester.ensureSemantics();
      final id = _cargarEdificio('Facultad de Ingeniería');
      await _armarPrimerCuadro(
        tester,
        ListaPisos(edificioId: id, nombreEdificio: 'Facultad de Ingeniería'),
      );
      expect(find.byType(EstadoPantalla), findsNothing);
      await tester.pumpAndSettle();
      expect(ordenTalkBack(tester), [
        'Facultad de Ingeniería',
        'No hay pisos agregados\nTocá «Agregar piso» para cargar la imagen '
            'del plano.',
        'Agregar piso',
      ]);
      expect(
        tester.getSemantics(find.text('No hay pisos agregados')),
        isSemantics(isLiveRegion: true),
      );
      semantica.dispose();
    });

    testWidgets('con la letra al 200 %: nada partido ni cortado, con los '
        'botones de cada piso debajo del nombre, tampoco en la hoja del '
        'número; 48 dp, etiquetas y contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      final id = _cargarEdificio('Facultad de Ingeniería');
      _cargarPiso(id, 0);
      _cargarPiso(id, -2);
      _cargarPiso(id, null, nombre: 'Entrepiso');
      await armarPisos(tester, id, escala: 2);
      expect(tester.takeException(), isNull);
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), isEmpty);
      // Los botones de cada piso, debajo del nombre.
      final nombre = tester.getRect(find.text('Subsuelo 2'));
      final probar = tester.getRect(
        find.byTooltip('Probar navegación en Subsuelo 2'),
      );
      expect(probar.top, greaterThan(nombre.bottom));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await tester.tap(find.byTooltip('Cambiar número de Planta baja'));
      await tester.pumpAndSettle();
      expect(find.text('Cambiar número de piso'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), isEmpty);
      // Con la letra al 200 %, menos por renglón, pero parejos.
      expect(_revisarGrilla(tester), lessThan(5));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('«Agregar piso»: primero el número, en una hoja con un botón '
        'por piso y los ya cargados deshabilitados; elegido, la galería del '
        'teléfono (cancelada, no se carga nada); cerrada la hoja, ni la '
        'galería', (tester) async {
      final semantica = tester.ensureSemantics();
      final id = _cargarEdificio('Facultad de Ingeniería');
      _cargarPiso(id, 0);
      _cargarPiso(id, 1);
      await armarPisos(tester, id);
      await tester.tap(find.text('Agregar piso'));
      await tester.pumpAndSettle();
      expect(find.text('¿Qué piso es?'), findsOneWidget);
      // Del subsuelo 3 al piso 20, sin uno «actual».
      expect(
        find.byType(BotonSecundario),
        findsNWidgets(PisoUtil.maximo - PisoUtil.minimo + 1),
      );
      for (final cargado in ['Planta baja', 'Piso 1']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel('$cargado, ya cargado')),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
        );
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('Subsuelo 3')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      expect(
        find.bySemanticsLabel('PB es planta baja y S, subsuelo.'),
        findsOne,
      );

      expect(_revisarGrilla(tester), 5);

      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(find.text('¿Qué piso es?'), findsNothing);
      expect(pedidosGaleria, ['pickImage']);
      expect(_escrituras(), isEmpty);

      await tester.tap(find.text('Agregar piso'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Qué piso es?'), findsNothing);
      expect(pedidosGaleria, hasLength(1));
      semantica.dispose();
    });

    testWidgets('«Cambiar número»: el actual en acento; elegido otro, lo '
        'cambia y, si el piso está publicado, avisa que hay que volver a '
        'publicarlo', (tester) async {
      final semantica = tester.ensureSemantics();
      final id = _cargarEdificio('Facultad de Ingeniería');
      final pb = _cargarPiso(id, 0, remoto: 'mapa-pb');
      _cargarPiso(id, 1);
      await armarPisos(tester, id);
      await tester.tap(find.byTooltip('Cambiar número de Planta baja'));
      await tester.pumpAndSettle();
      expect(find.text('Cambiar número de piso'), findsOneWidget);
      expect(find.widgetWithText(BotonPrincipal, 'PB'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Planta baja, el actual')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Piso 1, ya cargado')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );

      await tester.tap(find.text('S1'));
      await tester.pumpAndSettle();
      final fila = baseFalsa.filas('pisos').firstWhere((f) => f['id'] == pb);
      expect(fila['numero_piso'], -1);
      expect(fila['nombre_piso'], 'Subsuelo 1');
      expect(_tarjeta('Subsuelo 1'), findsOneWidget);
      expect(_tarjeta('Planta baja'), findsNothing);
      expect(
        find.text(
          'Número actualizado. Volvé a publicar el piso para que llegue a los '
          'usuarios.',
        ),
        findsOneWidget,
      );
      semantica.dispose();
    });

    testWidgets('«Probar navegación» y tocar el piso abren la navegación y la '
        'configuración de ese piso con RutaApp', (tester) async {
      final id = _cargarEdificio('Facultad de Ingeniería');
      final pb = _cargarPiso(id, 0);
      final observador = await armarPisos(tester, id);
      final contexto = tester.element(find.byType(ListaPisos));

      await tester.tap(find.byTooltip('Probar navegación en Planta baja'));
      final navegacion = _revisarYSacar<PantallaNavegacion>(
        tester,
        observador,
        contexto,
      );
      expect(navegacion.pisoId, pb);
      expect(navegacion.rutaImagen, '/planos/piso_0.png');
      await tester.pumpAndSettle();

      await tester.tap(_tarjeta('Planta baja'));
      final configuracion = _revisarYSacar<PantallaConfiguracion>(
        tester,
        observador,
        contexto,
      );
      expect(configuracion.pisoId, pb);
      expect(configuracion.escalaX, 50);
      await tester.pumpAndSettle();
      expect(find.byType(ListaPisos), findsOneWidget);
    });

    testWidgets('el tacho de cada piso («Eliminar Piso 1», debajo, en la '
        'otra punta) pide la misma confirmación y lo borra', (tester) async {
      final id = _cargarEdificio('Facultad de Ingeniería');
      _cargarPiso(id, 0);
      _cargarPiso(id, 1);
      await armarPisos(tester, id);
      await tester.tap(find.byTooltip('Eliminar Piso 1'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar piso?'), findsOneWidget);
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('pisos').map((f) => f['nombre_piso']), [
        'Planta baja',
      ]);
      expect(_tarjeta('Piso 1'), findsNothing);
      expect(find.text('Piso 1 eliminado'), findsOneWidget);
    });

    testWidgets('eliminar un piso publicado: la confirmación; lo quita de la '
        'nube, lo borra y avisa; si la nube no anda, avisa con un error y no '
        'lo borra', (tester) async {
      final semantica = tester.ensureSemantics();
      final id = _cargarEdificio('Facultad de Ingeniería');
      _cargarPiso(id, 0, remoto: 'mapa-pb');
      _cargarPiso(id, 1, remoto: 'mapa-1');
      nubeFalsa.contestar = _quitaMapas;
      await armarPisos(tester, id);

      tester.semantics.customAction(
        find.semantics.byLabel('Planta baja'),
        _eliminar,
      );
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar piso?'), findsOneWidget);
      expect(
        find.text(
          'Esto borrará "Planta baja" y todos sus beacons configurados.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(nubeFalsa.pedidos, [
        'GET /rest/v1/mapas_publicados',
        'DELETE /storage/v1/object/map-images',
        'DELETE /rest/v1/mapas_publicados',
      ]);
      expect(baseFalsa.filas('pisos').map((f) => f['nombre_piso']), ['Piso 1']);
      expect(find.text('Planta baja eliminado'), findsOneWidget);
      expect(_tarjeta('Planta baja'), findsNothing);

      // Se va el aviso.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      nubeFalsa.contestar = _nubeCaida;
      tester.semantics.customAction(
        find.semantics.byLabel('Piso 1'),
        _eliminar,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          RegExp(
            r'^No se pudo quitar de la nube: .*\nNo se eliminó el piso\.$',
            dotAll: true,
          ),
        ),
        findsOneWidget,
      );
      expect(baseFalsa.filas('pisos'), hasLength(1));
      expect(_tarjeta('Piso 1'), findsOneWidget);
      semantica.dispose();
    });
  });
}
