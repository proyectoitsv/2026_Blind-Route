import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blindroute/design/design.dart';
import 'package:blindroute/pantalla_config.dart';
import 'package:blindroute/pantalla_rubros.dart';
import 'package:blindroute/rubros.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudas_pantallas.dart';
import 'base_falsa.dart';
import 'nube_falsa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURACIÓN DEL PISO Y RUBROS (fase 5.6 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// La configuración de un piso de verdad, con el MaterialApp de la app (el
// tema de antes, como en main_admin.dart): la barra, los seis modos en chips,
// el plano hundido con el botón «Borrar», el panel de cada modo, las hojas que
// reemplazan a los diálogos, las confirmaciones y los avisos, lo que dice
// TalkBack y la letra al 200 % con Inter de verdad (ayudas_pantallas.dart).
// También los rubros (pantalla_rubros.dart), que se abren desde la hoja de un
// lugar.
//
// ─── La base, la nube, la brújula y el Bluetooth ───
// La base es la de prueba (base_falsa.dart) y Supabase habla con la nube de
// prueba (nube_falsa.dart). La brújula se simula sobre su canal
// (hemanthraj/flutter_compass): el test manda las lecturas. El Bluetooth no
// se puede simular sin un paquete más: en los tests, flutter_blue_plus no
// tiene plataforma y su primera llamada falla. Entrar a «Calibrar» (que
// prende el escáner) se hace atrapando ese error, que se revisa; el escáner
// queda apagado, como en un teléfono sin Bluetooth.
//
// ─── El plano ───
// Un PNG de 1 × 1 en un archivo temporal: MapaWidget lo lee de verdad. Lo que
// se dibuja adentro (los marcadores, la grilla) es el MapaWidget de siempre,
// que se migra en la 5.7: acá no se revisa su contraste.

/// Un PNG de 1 × 1, transparente.
const String _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==';

/// El canal de la brújula (flutter_compass).
const EventChannel _canalBrujula = EventChannel('hemanthraj/flutter_compass');

/// La acción de TalkBack de cada tarjeta de lugar.
const CustomSemanticsAction _eliminar = CustomSemanticsAction(
  label: 'Eliminar',
);

late String _rutaPlano;

/// Por donde se mandan las lecturas de la brújula, mientras la pantalla la
/// escucha.
MockStreamHandlerEventSink? _brujula;

/// Una lectura de la brújula: el rumbo y el error en grados (15 = alta).
void _leerBrujula(double rumbo, {double error = 15}) =>
    _brujula!.success(<double>[rumbo, 0, error]);

/// Carga el piso de prueba (30 × 20 m, publicado si [publicado]) con cuatro
/// beacons, una zona, los lugares (si [conLugares]) y tres calibraciones.
void _cargarPiso({bool conLugares = true, bool publicado = true}) {
  baseFalsa.agregar('edificios', {'id': 1, 'nombre': 'Facultad de Ingeniería'});
  baseFalsa.agregar('pisos', {
    'id': 1,
    'edificio_id': 1,
    'numero_piso': 0,
    'nombre_piso': 'Planta baja',
    'ruta_imagen': _rutaPlano,
    'escala_metros': 30.0,
    'escala_metros_alto': 20.0,
    'remote_id': publicado ? 'mapa-1' : null,
  });
  for (final (mac, x, y, nombre) in [
    ('C3:00:00:1A:2B:01', 0.10, 0.18, 'Holy-IOT-B1'),
    ('C3:00:00:1A:2B:02', 0.62, 0.22, 'Holy-IOT-B2'),
    ('C3:00:00:1A:2B:03', 0.30, 0.80, 'Holy-IOT-B3'),
    ('C3:00:00:1A:2B:04', 0.88, 0.75, 'Holy-IOT-B4'),
  ]) {
    baseFalsa.agregar('beacons', {
      'piso_id': 1,
      'mac': mac,
      'x': x,
      'y': y,
      'nombre_beacon': nombre,
    });
  }
  baseFalsa.agregar('zonas_no_transitables', {
    'piso_id': 1,
    'nombre': 'Escaleras',
    'vertices_json': jsonEncode([
      {'dx': 0.86, 'dy': 0.44},
      {'dx': 0.97, 'dy': 0.44},
      {'dx': 0.97, 'dy': 0.57},
      {'dx': 0.86, 'dy': 0.57},
    ]),
  });
  if (conLugares) {
    _cargarLugar('Baño', 0.40, 0.28, rubro: Rubros.bano);
    _cargarLugar(
      'Bar',
      0.75,
      0.25,
      rubro: 'comida',
      palabras: 'el bar, cafetería',
    );
    _cargarLugar(
      'Escalera norte',
      0.83,
      0.50,
      escalera: true,
      sube: true,
      direccion: 270,
    );
  }
  for (final (ix, iy, etiqueta, puntoClave, rumbo, dia) in [
    (3, 4, 'Entrada', false, null, 3),
    (12, 9, null, true, 92.0, 4),
    (20, 10, 'Pasillo norte', true, null, 5),
  ]) {
    baseFalsa.agregar('calibraciones', {
      'piso_id': 1,
      'celda_ix': ix,
      'celda_iy': iy,
      'lecturas_ble': jsonEncode([
        {'mac': 'C3:00:00:1A:2B:01', 'rssi': -61.0},
        {'mac': 'C3:00:00:1A:2B:02', 'rssi': -70.0},
        {'mac': 'C3:00:00:1A:2B:03', 'rssi': -74.0},
      ]),
      'tx_power_ajustado': jsonEncode(<String, double>{}),
      'timestamp': DateTime(2026, 11, dia, 14, 30).toIso8601String(),
      'etiqueta': etiqueta,
      'es_fingerprint': puntoClave ? 1 : 0,
      'rumbo_captura': rumbo,
    });
  }
}

/// Carga un lugar (o una escalera) en el piso de prueba, con todas las
/// columnas de la tabla.
void _cargarLugar(
  String nombre,
  double x,
  double y, {
  String? rubro,
  String? palabras,
  bool escalera = false,
  bool sube = false,
  bool baja = false,
  double? direccion,
  bool ascensor = false,
}) => baseFalsa.agregar('lugares_interes', {
  'piso_id': 1,
  'nombre': nombre,
  'x': x,
  'y': y,
  'descripcion': null,
  'tipo': escalera ? 'escalera' : 'comun',
  'sube': sube ? 1 : 0,
  'baja': baja ? 1 : 0,
  'direccion_entrada': direccion,
  'palabras_clave': palabras,
  'rubro': rubro,
  'rubro_palabras': null,
  'ascensor': ascensor ? 1 : 0,
});

/// El catálogo de rubros de fábrica en la base, como lo deja la app.
void _cargarRubros() {
  for (final (i, r) in Rubros.deFabrica.indexed) {
    baseFalsa.agregar('rubros', {
      'id': r.id,
      'nombre': r.nombre,
      'palabras': r.palabras.join(', '),
      'orden': i,
    });
  }
}

/// La configuración del piso de prueba, como la abre la lista de pisos.
PantallaConfiguracion _pantalla() => PantallaConfiguracion(
  pisoId: 1,
  rutaImagen: _rutaPlano,
  escalaX: 30,
  escalaY: 20,
);

/// Arma la configuración del piso de prueba como en la app, con la brújula
/// simulada. La brújula se pone acá, adentro del test: setMockStreamHandler
/// cierra su canal al terminar el test (o el setUpAll) en que se puso, y lo
/// que manda tiene que pasar por el reloj del test.
Future<void> _armar(WidgetTester tester, {double escala = 1}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
        _canalBrujula,
        MockStreamHandler.inline(
          onListen: (_, eventos) {
            _brujula = eventos;
          },
          onCancel: (_) {
            _brujula = null;
          },
        ),
      );
  await armarPantalla(tester, _pantalla(), escala: escala);
}

/// Elige el modo [nombre] en la fila de chips (lo trae a la vista antes).
/// Devuelve los errores que quedaron sin atrapar: al entrar a «Calibrar», el
/// de flutter_blue_plus, que en los tests no tiene plataforma.
Future<List<Object>> _elegirModo(WidgetTester tester, String nombre) async {
  final chip = find.widgetWithText(ChipFiltro, nombre);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  final errores = <Object>[];
  await runZonedGuarded(() async {
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }, (error, _) => errores.add(error));
  await tester.pumpAndSettle();
  return errores;
}

/// Un punto del plano, en coordenadas normalizadas (0 a 1). El plano (30 ×
/// 20 m) va centrado en el recuadro del mapa, con su proporción.
Offset _enPlano(WidgetTester tester, double x, double y) {
  final r = tester.getRect(find.byType(InteractiveViewer));
  const proporcion = 30 / 20;
  var ancho = r.width, alto = r.width / proporcion;
  if (alto > r.height) {
    alto = r.height;
    ancho = alto * proporcion;
  }
  return Offset(
    r.left + (r.width - ancho) / 2 + x * ancho,
    r.top + (r.height - alto) / 2 + y * alto,
  );
}

/// Toca el plano en (x, y).
Future<void> _tocarPlano(WidgetTester tester, double x, double y) async {
  await tester.tapAt(_enPlano(tester, x, y));
  await tester.pumpAndSettle();
}

/// Desplaza el panel de abajo del plano hasta que se vea [buscado] (hacia
/// abajo o, con [arriba], hacia arriba): lo que queda lejos no está armado.
Future<void> _verEnPanel(
  WidgetTester tester,
  Finder buscado, {
  bool arriba = false,
}) async {
  await tester.scrollUntilVisible(
    buscado,
    arriba ? -120 : 120,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// La tarjeta del lugar [nombre] en la lista (el nombre también va sobre el
/// plano).
Finder _tarjetaLugar(String nombre) =>
    find.widgetWithText(TarjetaLista, nombre);

/// El texto de la ayuda del modo.
String _ayuda(WidgetTester tester) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Text),
          )
          .first,
    )
    .data!;

/// El borde del plano hundido.
BorderSide _bordePlano(WidgetTester tester) => tester
    .widget<PanelRelieve>(
      find.ancestor(
        of: find.byType(InteractiveViewer),
        matching: find.byType(PanelRelieve),
      ),
    )
    .borde!;

/// El aviso que se ve ahora (mostrarAviso).
Finder _aviso(String texto) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(texto));

/// Lo que se pidió a la base que escribe.
Iterable<String> _escrituras() => baseFalsa.pedidos.where(
  (p) =>
      p.startsWith('INSERT') ||
      p.startsWith('UPDATE') ||
      p.startsWith('DELETE'),
);

/// El nodo de TalkBack de [buscado].
SemanticsNode _nodo(WidgetTester tester, Finder buscado) =>
    tester.getSemantics(buscado);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await cargarInter();
    iniciarBaseDePrueba();
    await iniciarSupabaseDePrueba();
    final carpeta = Directory.systemTemp.createTempSync('plano_prueba');
    _rutaPlano = '${carpeta.path}${Platform.pathSeparator}plano.png';
    File(_rutaPlano).writeAsBytesSync(base64Decode(_png1x1));
  });

  setUp(() {
    _brujula = null;
    AjustesMovimiento.instancia.reiniciarParaTests();
    baseFalsa.reiniciar();
    nubeFalsa.reiniciar();
    Rubros.usarCatalogo(Rubros.deFabrica);
    _cargarRubros();
  });

  group('configuración del piso', () {
    testWidgets('al entrar (Beacons): la barra con las acciones de la nube, '
        'los seis modos, el plano con «Borrar», la ayuda, el escáner y el '
        'filtro; lo que dice TalkBack, en orden; un solo botón principal; '
        'nada gira; 48 dp, etiquetas y contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      // Sin lugares: sus nombres sobre el plano son del MapaWidget de
      // siempre (5.7), que no pasa el contraste.
      _cargarPiso(conLugares: false);
      await _armar(tester);
      expect(find.byType(AmbienteDiseno), findsOneWidget);
      // Es la primera pantalla del test: sin «Volver» (en la app, la abre la
      // lista de pisos).
      expect(ordenTalkBack(tester), [
        'Configuración del piso',
        'Eliminar el mapa de la nube',
        'Publicar el mapa en la nube',
        'Beacons',
        'Zonas',
        'Lugares',
        'Escala',
        'Calibrar',
        'Brújula',
        'Entrar al modo borrar',
        'Plano del piso',
        'Elegí un dispositivo de la lista y tocá el mapa para ubicarlo. '
            'Arrastrá la mira de un beacon para moverlo.',
        'Escáner detenido',
        'Escanear',
        'Filtrar por nombre o potencia\nLos más fuertes, primero',
      ]);
      expect(
        _nodo(tester, find.text('Configuración del piso')),
        isSemantics(isHeader: true, namesRoute: true),
      );
      expect(
        _nodo(tester, find.widgetWithText(ChipFiltro, 'Beacons')),
        isSemantics(
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        _nodo(tester, find.bySemanticsLabel('Escáner detenido')),
        isSemantics(isLiveRegion: true),
      );
      // «Escanear», el único botón principal; nada gira (antes, la ruedita
      // mientras publicaba y mientras esperaba la brújula).
      expect(find.byType(BotonPrincipal), findsOneWidget);
      expect(find.byType(ProgressIndicator), findsNothing);
      expect(find.byType(SegmentedButton<Object>), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // El plano: hundido, con el borde de los controles.
      final e = EstiloApp.de(tester.element(find.byType(InteractiveViewer)));
      expect(_bordePlano(tester).color, e.borde);
      expect(_bordePlano(tester).width, FormasApp.grosorLinea);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('los modos: chips de los que se elige uno; cambiar de modo '
        'cambia el panel; tocar el elegido no borra lo que se está '
        'dibujando', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Zonas');
      expect(
        _nodo(tester, find.widgetWithText(ChipFiltro, 'Zonas')),
        isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true),
      );
      expect(
        _nodo(tester, find.widgetWithText(ChipFiltro, 'Beacons')),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true),
      );
      // Tocado contra el borde, el chip no queda cortado: el de antes, al
      // perder el tilde, lo corre hacia afuera.
      expect(
        tester.getRect(find.widgetWithText(ChipFiltro, 'Zonas')).left,
        greaterThanOrEqualTo(0),
      );
      await _tocarPlano(tester, 0.2, 0.2);
      await _tocarPlano(tester, 0.4, 0.2);
      expect(_ayuda(tester), startsWith('2 puntos.'));
      // Como el SegmentedButton de antes: tocar el modo elegido no hace nada.
      await _elegirModo(tester, 'Zonas');
      expect(_ayuda(tester), startsWith('2 puntos.'));
      // Otro modo, otro panel (y la zona a medio dibujar se descarta, como
      // antes).
      await _elegirModo(tester, 'Escala');
      expect(_ayuda(tester), startsWith('Escala actual: 30,0 × 20,0 m'));
      await _elegirModo(tester, 'Zonas');
      expect(_ayuda(tester), startsWith('Tocá el mapa para marcar'));
      semantica.dispose();
    });

    testWidgets('modo borrar: un interruptor con los nombres de antes, que '
        'pasa a «Listo»; el borde del plano en rojo de 2 px y la ayuda en '
        'rojo; con una zona a medio dibujar no se entra', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      final e = EstiloApp.de(tester.element(find.byType(InteractiveViewer)));
      expect(
        _nodo(tester, find.bySemanticsLabel('Entrar al modo borrar')),
        isSemantics(
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(find.text('Listo'), findsOneWidget);
      expect(
        _nodo(tester, find.bySemanticsLabel('Salir del modo borrar')),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true),
      );
      expect(_bordePlano(tester).color, e.error);
      expect(_bordePlano(tester).width, FormasApp.grosorFoco);
      expect(
        _ayuda(tester),
        'Modo borrar: tocá un beacon. «Listo» para salir.',
      );
      final ayuda = tester.widget<Text>(
        find.text('Modo borrar: tocá un beacon. «Listo» para salir.'),
      );
      expect(ayuda.style!.color, e.error);
      await tester.tap(find.text('Listo'));
      await tester.pumpAndSettle();
      expect(_bordePlano(tester).color, e.borde);
      // Con una zona a medio dibujar, «Borrar» no se puede tocar.
      await _elegirModo(tester, 'Zonas');
      await _tocarPlano(tester, 0.2, 0.2);
      expect(
        _nodo(tester, find.bySemanticsLabel('Entrar al modo borrar')),
        isSemantics(isEnabled: false, hasEnabledState: true),
      );
      semantica.dispose();
    });

    testWidgets('zonas: «Líneas rectas», deshacer, «Descartar» y «Cerrar '
        'zona» (el principal, desde tres puntos); el nombre, en una hoja; '
        'guarda la zona', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Zonas');
      expect(
        _nodo(tester, find.bySemanticsLabel(RegExp('^Líneas rectas'))),
        isSemantics(hasToggledState: true, isToggled: true),
      );
      expect(
        _nodo(tester, find.bySemanticsLabel('Quitar el último punto')),
        isSemantics(isEnabled: false, hasEnabledState: true),
      );
      expect(
        tester.widget<BotonPrincipal>(find.byType(BotonPrincipal)).alPresionar,
        isNull,
      );
      for (final (x, y) in [(0.2, 0.2), (0.4, 0.2), (0.4, 0.4)]) {
        await _tocarPlano(tester, x, y);
      }
      expect(_ayuda(tester), startsWith('3 puntos. Tocá para agregar'));
      // Deshacer saca uno solo.
      await tester.tap(find.bySemanticsLabel('Quitar el último punto'));
      await tester.pumpAndSettle();
      expect(_ayuda(tester), startsWith('2 puntos.'));
      await _tocarPlano(tester, 0.4, 0.4);
      await tester.tap(find.text('Cerrar zona'));
      await tester.pumpAndSettle();
      // La hoja, que TalkBack nombra con su título (no «Dialog»).
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        _nodo(tester, find.text('Nombre de la zona')),
        isSemantics(isHeader: true),
      );
      expect(
        find.text('Si lo dejás vacío, se llama «Zona prohibida».'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Columna');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final zonas = baseFalsa.filas('zonas_no_transitables');
      expect(zonas.map((z) => z['nombre']), ['Escaleras', 'Columna']);
      expect(
        jsonDecode(zonas.last['vertices_json']! as String) as List,
        hasLength(3),
      );
      expect(_ayuda(tester), startsWith('Tocá el mapa para marcar'));
      semantica.dispose();
    });

    testWidgets('zonas: «Cancelar» en la hoja del nombre descarta la zona, '
        'como antes; «Descartar» también', (tester) async {
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Zonas');
      for (final (x, y) in [(0.2, 0.2), (0.4, 0.2), (0.4, 0.4)]) {
        await _tocarPlano(tester, x, y);
      }
      await tester.tap(find.text('Cerrar zona'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('zonas_no_transitables'), hasLength(1));
      expect(_ayuda(tester), startsWith('Tocá el mapa para marcar'));
      await _tocarPlano(tester, 0.2, 0.2);
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(_ayuda(tester), startsWith('Tocá el mapa para marcar'));
      expect(_escrituras(), isEmpty);
    });

    testWidgets('escala: los metros del largo en una hoja, con la unidad y el '
        'error debajo si no es un número; el tamaño de celda con un '
        'deslizador que TalkBack dice en metros', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Escala');
      expect(find.text('Medida del largo'), findsOneWidget);
      expect(
        tester.widget<BotonPrincipal>(find.byType(BotonPrincipal)).alPresionar,
        isNull,
      );
      await _tocarPlano(tester, 0.1, 0.5);
      await _tocarPlano(tester, 0.9, 0.5);
      expect(_ayuda(tester), endsWith('tocá «Medida del largo».'));
      await tester.tap(find.text('Medida del largo'));
      await tester.pumpAndSettle();
      expect(
        _nodo(tester, find.text('Largo de la línea')),
        isSemantics(isHeader: true),
      );
      expect(
        find.text('¿Cuántos metros mide el largo en la realidad?'),
        findsOneWidget,
      );
      expect(find.text('m'), findsOneWidget);
      // Vacío: el error debajo del campo (antes no pasaba nada).
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Escribí un número mayor que 0.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '24,5');
      await tester.pumpAndSettle();
      expect(find.text('Escribí un número mayor que 0.'), findsNothing);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Largo de la línea'), findsNothing);
      expect(_ayuda(tester), contains('Largo: 24,5 m. Marcá el tercer punto'));
      expect(find.text('Medida del ancho'), findsOneWidget);
      // El tamaño de celda, al final del panel: TalkBack lo dice en metros y
      // lo sube y baja.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final deslizador = find.bySemanticsLabel('Tamaño de celda');
      expect(
        _nodo(tester, deslizador),
        isSemantics(
          isSlider: true,
          value: '1,0 metros',
          decreasedValue: '0,9 metros',
          hasDecreaseAction: true,
        ),
      );
      expect(find.text('1,0 m'), findsOneWidget);
      tester.semantics.decrease(find.semantics.byLabel('Tamaño de celda'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('pisos').single['tam_celda_metros'], 0.9);
      expect(find.text('0,9 m'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('lugares: una tarjeta por lugar (el tacho aparte, sin el '
        'lápiz); tocarla edita en una hoja; el rubro se elige de una lista en '
        'otra hoja', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Lugares');
      // El plano tiene nombre, y los nombres de sus lugares se leen con él.
      expect(
        _nodo(tester, find.bySemanticsLabel(RegExp('^Plano del piso'))),
        isSemantics(
          label: 'Plano del piso\nBaño\nBar\nEscalera norte ↑',
          hasTapAction: true,
        ),
      );
      await _verEnPanel(tester, _tarjetaLugar('Escalera norte'));
      expect(find.byType(TarjetaLista), findsNWidgets(3));
      expect(
        find.text(
          'Rubro: ${Rubros.porId('comida')!.nombre}\n'
          'Otras palabras: el bar, cafetería',
        ),
        findsOneWidget,
      );
      expect(find.text('Escalera · sube'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(
        _nodo(tester, find.bySemanticsLabel(RegExp(r'^Bar\n'))),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          customActions: [_eliminar],
        ),
      );
      await tester.tap(_tarjetaLugar('Bar'));
      await tester.pumpAndSettle();
      expect(
        _nodo(tester, find.text('Editar lugar')),
        isSemantics(isHeader: true),
      );
      expect(find.byType(ControlSegmentado<Object>), findsNothing);
      expect(find.text('Bar'), findsWidgets);
      expect(find.text('el bar, cafetería'), findsOneWidget);
      // El rubro: una fila que abre la lista.
      final rubro = find.bySemanticsLabel(RegExp('^Rubro: '));
      expect(_nodo(tester, rubro), isSemantics(isButton: true));
      await tester.tap(rubro);
      await tester.pumpAndSettle();
      // La hoja de los rubros, encima de la del lugar (que también dice
      // «Rubro»).
      expect(
        _nodo(tester, find.text('Rubro').last),
        isSemantics(isHeader: true),
      );
      expect(
        find.byType(TarjetaDestino),
        findsNWidgets(Rubros.todos.length + 1),
      );
      final cafe = Rubros.porId('cafe')!;
      await tester.scrollUntilVisible(
        find.widgetWithText(TarjetaDestino, cafe.nombre),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.widgetWithText(TarjetaDestino, cafe.nombre));
      await tester.pumpAndSettle();
      expect(find.text('Editar lugar'), findsOneWidget);
      expect(find.text(cafe.nombre), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final bar = baseFalsa
          .filas('lugares_interes')
          .firstWhere((l) => l['nombre'] == 'Bar');
      expect(bar['rubro'], 'cafe');
      expect(bar['palabras_clave'], 'el bar, cafetería');
      semantica.dispose();
    });

    testWidgets('lugares: una escalera nueva, desde el plano; lo que falta, '
        'en ámbar; si sube o baja y hacia dónde da la entrada, con chips', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Lugares');
      await _tocarPlano(tester, 0.5, 0.9);
      expect(find.text('Nuevo lugar'), findsOneWidget);
      final e = EstiloApp.de(tester.element(find.text('Nuevo lugar')));
      expect(find.text('Escribí un nombre'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Escribí un nombre')).style!.color,
        e.advertencia,
      );
      Finder guardar() => find.widgetWithText(BotonPrincipal, 'Guardar');
      expect(tester.widget<BotonPrincipal>(guardar()).alPresionar, isNull);
      await tester.tap(find.bySemanticsLabel('Escalera o ascensor'));
      await tester.pumpAndSettle();
      expect(find.text('Elegí si sube, baja o ambas'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChipFiltro, 'Baja'));
      await tester.pumpAndSettle();
      expect(find.text('Elegí hacia dónde da la entrada'), findsOneWidget);
      final abajo = find.bySemanticsLabel('Entrada hacia abajo del plano');
      await tester.ensureVisible(abajo);
      expect(
        _nodo(tester, abajo),
        isSemantics(
          isButton: true,
          isSelected: false,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      await tester.tap(abajo);
      await tester.pumpAndSettle();
      expect(_nodo(tester, abajo), isSemantics(isSelected: true));
      expect(tester.widget<BotonPrincipal>(guardar()).alPresionar, isNotNull);
      await tester.ensureVisible(guardar());
      await tester.tap(guardar());
      await tester.pumpAndSettle();
      final nuevo = baseFalsa.filas('lugares_interes').last;
      expect(nuevo['nombre'], 'Escalera');
      expect(nuevo['tipo'], 'escalera');
      expect(nuevo['baja'], 1);
      expect(nuevo['sube'], 0);
      expect(nuevo['direccion_entrada'], 180.0);
      await _verEnPanel(tester, _tarjetaLugar('Escalera'));
      expect(find.text('Escalera · baja'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('lugares: se eliminan con el tacho, con la acción «Eliminar» '
        'de TalkBack o tocándolos en el modo borrar, con la misma '
        'confirmación en una hoja', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Lugares');
      // El tacho: «Cancelar» no borra nada.
      await tester.tap(find.bySemanticsLabel('Eliminar Baño'));
      await tester.pumpAndSettle();
      expect(
        _nodo(tester, find.text('¿Eliminar lugar?')),
        isSemantics(isHeader: true),
      );
      expect(find.text('Se eliminará "Baño".'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('lugares_interes'), hasLength(3));
      await tester.tap(find.bySemanticsLabel('Eliminar Baño'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(BotonSecundario, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('lugares_interes').map((l) => l['nombre']), [
        'Bar',
        'Escalera norte',
      ]);
      expect(find.byType(TarjetaLista), findsNWidgets(2));
      // La acción de TalkBack.
      tester.semantics.customAction(
        find.semantics.byLabel(RegExp(r'^Bar\n')),
        _eliminar,
      );
      await tester.pumpAndSettle();
      expect(find.text('Se eliminará "Bar".'), findsOneWidget);
      await tester.tap(find.widgetWithText(BotonSecundario, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('lugares_interes').map((l) => l['nombre']), [
        'Escalera norte',
      ]);
      semantica.dispose();
    });

    testWidgets('calibrar: sin Bluetooth (en el test, flutter_blue_plus no '
        'tiene plataforma); la celda, la etiqueta, las lecturas y el punto '
        'clave; «Activá el escáner primero», apagado', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      final errores = await _elegirModo(tester, 'Calibrar');
      expect(errores, [isA<UnsupportedError>()]);
      expect(_ayuda(tester), 'Tocá la celda donde estás parado.');
      expect(find.text('Calibraciones guardadas (3)'), findsOneWidget);
      await _tocarPlano(tester, 0.45, 0.42);
      expect(_ayuda(tester), 'Celda (13, 8). Tomá la calibración acá abajo.');
      expect(
        _nodo(tester, find.text('Celda (13, 8)')),
        isSemantics(isHeader: true),
      );
      expect(find.text('Lecturas actuales (4 beacons)'), findsOneWidget);
      expect(find.text('Holy-IOT-B1'), findsWidgets);
      final puntoClave = find.bySemanticsLabel(
        RegExp(r'^Punto clave \(fingerprint\)'),
      );
      await _verEnPanel(tester, puntoClave);
      expect(
        _nodo(tester, puntoClave),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      await tester.tap(puntoClave);
      await tester.pumpAndSettle();
      expect(_nodo(tester, puntoClave), isSemantics(isToggled: true));
      // Sin la brújula todavía: se guarda sin rumbo.
      expect(
        find.textContaining('Sin brújula: se guarda sin rumbo'),
        findsOneWidget,
      );
      final boton = find.widgetWithText(
        BotonPrincipal,
        'Activá el escáner primero',
      );
      await _verEnPanel(tester, boton);
      expect(boton, findsOneWidget);
      expect(tester.widget<BotonPrincipal>(boton).alPresionar, isNull);
      // Con la brújula, el rumbo de ahora.
      _leerBrujula(80);
      await tester.pumpAndSettle();
      expect(find.textContaining('(ahora: 80°)'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('calibraciones guardadas: plegadas al entrar; «Ver» las '
        'muestra; cada una con su tacho; «Borrar todas» con la confirmación '
        'y el aviso', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Calibrar');
      expect(find.text('Quitar duplicados'), findsNothing);
      final ver = find.bySemanticsLabel('Ver las calibraciones guardadas');
      await _verEnPanel(tester, ver);
      await tester.tap(ver);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Ocultar las calibraciones guardadas'),
        findsOneWidget,
      );
      expect(find.text('Quitar duplicados'), findsOneWidget);
      await _verEnPanel(
        tester,
        find.text('Punto clave · rumbo 92° · 3 beacons · 04/11 14:30'),
      );
      expect(find.text('Celda (12, 9)'), findsOneWidget);
      expect(
        _nodo(
          tester,
          find.bySemanticsLabel(
            'Celda (12, 9)\nPunto clave · rumbo 92° · 3 '
            'beacons · 04/11 14:30',
          ),
        ),
        isSemantics(isButton: false),
      );
      // Una sola.
      final tacho = find.bySemanticsLabel('Eliminar Entrada');
      await _verEnPanel(tester, tacho);
      await tester.tap(tacho);
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar calibración?'), findsOneWidget);
      expect(find.text('Se eliminará "Entrada".'), findsOneWidget);
      await tester.tap(find.widgetWithText(BotonSecundario, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('calibraciones'), hasLength(2));
      await _verEnPanel(
        tester,
        find.text('Calibraciones guardadas (2)'),
        arriba: true,
      );
      // Todas.
      await _verEnPanel(tester, find.text('Borrar todas'));
      await tester.tap(find.text('Borrar todas'));
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar todas las calibraciones?'), findsOneWidget);
      expect(
        find.text(
          'Se borran 0 calibraciones y 2 puntos clave de este piso. No se '
          'puede deshacer.\n\nLa copia publicada no cambia hasta que vuelvas '
          'a publicar el piso.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(BotonSecundario, 'Borrar todo'));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('calibraciones'), isEmpty);
      expect(_aviso('Se borraron 2 calibraciones.'), findsOneWidget);
      expect(find.text('Todavía no hay calibraciones.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('brújula: esperando, un reloj de arena quieto (sin ruedita); '
        'con lecturas, la flecha en acento (que de 350° a 10° no da la vuelta '
        'larga), la precisión en ámbar si no es alta y el ajuste fino en '
        'grados', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Brújula');
      expect(find.byType(ProgressIndicator), findsNothing);
      await _verEnPanel(tester, find.byIcon(Icons.hourglass_empty_rounded));
      expect(find.text('Sin señal de brújula'), findsOneWidget);
      final usar = find.widgetWithText(
        BotonPrincipal,
        'Usar la dirección actual',
      );
      await _verEnPanel(tester, usar);
      expect(tester.widget<BotonPrincipal>(usar).alPresionar, isNull);
      _leerBrujula(350);
      await tester.pumpAndSettle();
      expect(tester.widget<BotonPrincipal>(usar).alPresionar, isNotNull);
      final flecha = find.byType(AnimatedRotation);
      await _verEnPanel(tester, flecha, arriba: true);
      expect(
        find.text('Norte magnético: 350° · offset actual: 0°'),
        findsOneWidget,
      );
      double vueltas() => tester.widget<AnimatedRotation>(flecha).turns;
      expect(vueltas(), closeTo(350 / 360, 1e-9));
      _leerBrujula(10);
      await tester.pumpAndSettle();
      // 20° hacia adelante, no 340° hacia atrás.
      expect(vueltas(), closeTo(370 / 360, 1e-9));
      final e = EstiloApp.de(tester.element(flecha));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.navigation_rounded)).color,
        e.acento,
      );
      await _verEnPanel(tester, find.text('Precisión de la brújula: alta.'));
      _leerBrujula(10, error: 30);
      await tester.pumpAndSettle();
      final media = find.text(
        'Precisión de la brújula: media. Hacé un 8 en el aire hasta que sea '
        'alta.',
      );
      expect(tester.widget<Text>(media).style!.color, e.advertencia);
      expect(_nodo(tester, media), isSemantics(isLiveRegion: true));
      // Los atajos guardan enseguida; el deslizador lo dice en grados.
      final este = find.text('Este (90°)');
      await _verEnPanel(tester, este);
      await tester.tap(este);
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('pisos').single['rotacion_mapa'], 90.0);
      final ajuste = find.bySemanticsLabel('Ajuste fino');
      await _verEnPanel(tester, ajuste, arriba: true);
      expect(
        _nodo(tester, ajuste),
        isSemantics(
          isSlider: true,
          value: '90 grados',
          increasedValue: '91 grados',
        ),
      );
      expect(find.text('90°'), findsOneWidget);
      await _verEnPanel(
        tester,
        find.text('Norte magnético: 10° · offset actual: 90°'),
        arriba: true,
      );
      semantica.dispose();
    });

    testWidgets('brújula: «Usar la dirección actual» mide 2 s («Midiendo… '
        'quedate quieto», sin ruedita) y guarda el offset', (tester) async {
      _cargarPiso();
      await _armar(tester);
      await _elegirModo(tester, 'Brújula');
      _leerBrujula(52);
      await tester.pumpAndSettle();
      final usar = find.text('Usar la dirección actual');
      await _verEnPanel(tester, usar);
      await tester.tap(usar);
      await tester.pump();
      expect(find.text('Midiendo… quedate quieto'), findsOneWidget);
      expect(find.byType(ProgressIndicator), findsNothing);
      for (var i = 0; i < 5; i++) {
        _leerBrujula(52);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(baseFalsa.filas('pisos').single['rotacion_mapa'], 52.0);
      expect(_aviso('Offset guardado: 52°'), findsOneWidget);
      expect(find.text('Usar la dirección actual'), findsOneWidget);
    });

    testWidgets('filtro: la hoja con el nombre y la potencia mínima (en dBm '
        'para TalkBack); puesto, la fila lo dice y «Quitar filtro» lo saca', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      await _armar(tester);
      await tester.tap(find.text('Filtrar por nombre o potencia'));
      await tester.pumpAndSettle();
      expect(
        _nodo(tester, find.text('Filtrar dispositivos')),
        isSemantics(isHeader: true),
      );
      expect(find.text('Quitar filtro'), findsNothing);
      final potencia = find.bySemanticsLabel('Potencia mínima');
      expect(
        _nodo(tester, potencia),
        isSemantics(
          isSlider: true,
          value: 'Todas',
          increasedValue: 'Desde -95 dBm',
        ),
      );
      for (var i = 0; i < 2; i++) {
        tester.semantics.increase(find.semantics.byLabel('Potencia mínima'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Desde -90 dBm'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Holy ');
      await tester.tap(find.text('Filtrar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nombre contiene «Holy» · desde -90 dBm'),
        findsOneWidget,
      );
      expect(find.text('0 de 0 dispositivos'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Quitar filtro'));
      await tester.pumpAndSettle();
      expect(find.text('Filtrar por nombre o potencia'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('eliminar de la nube: la confirmación en una hoja; mientras '
        'espera a la nube, «Eliminando de la nube…» quieto sobre el plano '
        '(TalkBack lo anuncia) y las acciones apagadas; después, el aviso', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso();
      final espera = Completer<void>();
      nubeFalsa.contestar = (metodo, url) async {
        await espera.future;
        if (url.path.startsWith('/storage/')) {
          return (estado: 200, cuerpo: '[]');
        }
        if (metodo == 'GET') {
          return (estado: 200, cuerpo: '[{"imagen_path":"plano.png"}]');
        }
        return (estado: 200, cuerpo: '[{"id":"borrado"}]');
      };
      await _armar(tester);
      await tester.tap(find.bySemanticsLabel('Eliminar el mapa de la nube'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar de la nube'), findsOneWidget);
      expect(
        find.text(
          'Se quita del catálogo y se borra de los teléfonos que ya lo '
          'tienen.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(BotonSecundario, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminando de la nube…'), findsOneWidget);
      expect(
        _nodo(tester, find.text('Eliminando de la nube…')),
        isSemantics(isLiveRegion: true),
      );
      expect(find.byType(ProgressIndicator), findsNothing);
      for (final accion in [
        'Eliminar el mapa de la nube',
        'Publicar el mapa en la nube',
      ]) {
        expect(
          _nodo(tester, find.bySemanticsLabel(accion)),
          isSemantics(isEnabled: false, hasEnabledState: true),
        );
      }
      espera.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eliminando de la nube…'), findsNothing);
      expect(_aviso('Mapa eliminado de la nube'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Eliminar el mapa de la nube'),
        findsNothing,
      );
      expect(baseFalsa.filas('pisos').single['remote_id'], isNull);
      semantica.dispose();
    });

    testWidgets('publicar sin beacons: el aviso de siempre', (tester) async {
      baseFalsa.agregar('pisos', {'id': 1, 'nombre_piso': 'Planta baja'});
      await _armar(tester);
      expect(
        find.bySemanticsLabel('Eliminar el mapa de la nube'),
        findsNothing,
      );
      await tester.tap(find.bySemanticsLabel('Publicar el mapa en la nube'));
      await tester.pumpAndSettle();
      expect(
        _aviso('Cargá al menos un beacon antes de publicar el mapa.'),
        findsOneWidget,
      );
    });

    testWidgets('con la letra al 200 %: nada partido ni cortado en los seis '
        'modos (salvo el título de la barra, que TalkBack lee entero); 48 dp '
        'y etiquetas', (tester) async {
      final semantica = tester.ensureSemantics();
      _cargarPiso(conLugares: false);
      await _armar(tester, escala: 2);
      expect(tester.takeException(), isNull);
      List<String> cortadosSalvoBarra() => [
        for (final t in textosCortados(tester))
          if (t != 'Configuración del piso') t,
      ];
      Future<void> revisar(String modo) async {
        expect(palabrasPartidas(tester), isEmpty, reason: modo);
        expect(cortadosSalvoBarra(), isEmpty, reason: modo);
        // Hasta el final del panel.
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(palabrasPartidas(tester), isEmpty, reason: modo);
        expect(cortadosSalvoBarra(), isEmpty, reason: modo);
        expect(tester.takeException(), isNull, reason: modo);
      }

      await revisar('Beacons');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      for (final modo in ['Zonas', 'Lugares', 'Escala', 'Brújula']) {
        await _elegirModo(tester, modo);
        await revisar(modo);
      }
      _leerBrujula(30, error: 45);
      await tester.pumpAndSettle();
      await revisar('Brújula con lecturas');
      await _elegirModo(tester, 'Calibrar');
      await _tocarPlano(tester, 0.45, 0.42);
      await _verEnPanel(
        tester,
        find.bySemanticsLabel('Ver las calibraciones guardadas'),
      );
      await tester.tap(
        find.bySemanticsLabel('Ver las calibraciones guardadas'),
      );
      await tester.pumpAndSettle();
      await revisar('Calibrar');
      semantica.dispose();
    });

    testWidgets('con la letra al 200 %: las hojas (un lugar, una escalera, '
        'el filtro, los metros) sin partir ni cortar', (tester) async {
      _cargarPiso();
      await _armar(tester, escala: 2);
      // El título de la barra (detrás de la hoja) se corta: TalkBack lo lee
      // entero.
      List<String> cortadosSalvoBarra() => [
        for (final t in textosCortados(tester))
          if (t != 'Configuración del piso') t,
      ];
      Future<void> revisar(String hoja) async {
        expect(palabrasPartidas(tester), isEmpty, reason: hoja);
        expect(cortadosSalvoBarra(), isEmpty, reason: hoja);
        // Hasta el final de la hoja.
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        expect(palabrasPartidas(tester), isEmpty, reason: hoja);
        expect(cortadosSalvoBarra(), isEmpty, reason: hoja);
        expect(tester.takeException(), isNull, reason: hoja);
      }

      Future<void> cancelar() async {
        await tester.ensureVisible(find.text('Cancelar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      }

      // El filtro.
      await _verEnPanel(tester, find.text('Filtrar por nombre o potencia'));
      await tester.tap(find.text('Filtrar por nombre o potencia'));
      await tester.pumpAndSettle();
      await revisar('Filtro');
      await cancelar();
      // Un lugar y una escalera.
      await _elegirModo(tester, 'Lugares');
      await _verEnPanel(tester, _tarjetaLugar('Bar'));
      await tester.tap(_tarjetaLugar('Bar'));
      await tester.pumpAndSettle();
      await revisar('Lugar');
      await cancelar();
      await _verEnPanel(tester, _tarjetaLugar('Escalera norte'));
      await tester.tap(_tarjetaLugar('Escalera norte'));
      await tester.pumpAndSettle();
      await revisar('Escalera');
      await cancelar();
      // Los metros.
      await _elegirModo(tester, 'Escala');
      await _tocarPlano(tester, 0.1, 0.5);
      await _tocarPlano(tester, 0.9, 0.5);
      await _verEnPanel(tester, find.text('Medida del largo'));
      await tester.tap(find.text('Medida del largo'));
      await tester.pumpAndSettle();
      await revisar('Metros');
    });
  });

  group('rubros', () {
    testWidgets('la lista: una tarjeta por rubro con algunas de sus palabras; '
        '«Nuevo rubro», el botón principal (antes, uno flotante); TalkBack, '
        '48 dp, etiquetas y contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(tester, const PantallaRubros());
      expect(find.byType(AmbienteDiseno), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(BotonPrincipal), findsOneWidget);
      final comida = Rubros.porId('comida')!;
      final orden = ordenTalkBack(tester);
      expect(orden.take(3), [
        'Rubros',
        'Las palabras de cada rubro sirven para pedir sus lugares por voz. Los '
            'cambios llegan al volver a publicar el mapa.',
        '${comida.nombre}\n${comida.palabras.take(5).join(', ')} y '
            '${comida.palabras.length - 5} más',
      ]);
      expect(orden.last, 'Nuevo rubro');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('nuevo rubro: «Guardar», en la barra, apagado hasta tener el '
        'nombre y una palabra; las palabras en chips, cada uno con su botón '
        'para quitarla; guarda y avisa', (tester) async {
      final semantica = tester.ensureSemantics();
      await armarPantalla(tester, const PantallaRubros());
      await tester.tap(find.text('Nuevo rubro'));
      await tester.pumpAndSettle();
      expect(
        _nodo(tester, find.text('Nuevo rubro')),
        isSemantics(isHeader: true, namesRoute: true),
      );
      final guardar = find.bySemanticsLabel('Guardar');
      expect(
        _nodo(tester, guardar),
        isSemantics(isEnabled: false, hasEnabledState: true),
      );
      await tester.enterText(find.byType(TextField).first, 'Ferretería');
      await tester.pumpAndSettle();
      expect(find.text('Agregá al menos una palabra.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'tornillo, clavos');
      await tester.pumpAndSettle();
      // La coma suma lo de antes.
      expect(find.widgetWithText(ChipApp, 'tornillo'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Agregar'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChipApp, 'clavos'), findsOneWidget);
      expect(find.text('2 palabras'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Quitar «clavos»'));
      await tester.pumpAndSettle();
      expect(find.text('1 palabra'), findsOneWidget);
      expect(_nodo(tester, guardar), isSemantics(isEnabled: true));
      await tester.tap(guardar);
      await tester.pumpAndSettle();
      final nuevo = baseFalsa.filas('rubros').last;
      expect(nuevo['nombre'], 'Ferretería');
      expect(nuevo['palabras'], 'tornillo');
      expect(Rubros.todos.last.nombre, 'Ferretería');
      expect(_aviso('Rubro creado'), findsOneWidget);
      expect(find.text('Rubros'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('borrar un rubro: la confirmación en una hoja (cuántos '
        'lugares lo usan); el del baño no se borra', (tester) async {
      _cargarPiso();
      await armarPantalla(tester, const PantallaRubros());
      final comida = Rubros.porId('comida')!;
      await tester.tap(find.text(comida.nombre));
      await tester.pumpAndSettle();
      expect(find.text('Editar rubro'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Borrar rubro'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar rubro'));
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar "${comida.nombre}"?'), findsOneWidget);
      expect(
        find.text(
          'Un lugar lo usa y va a quedar sin rubro. Republicá sus mapas para '
          'que llegue a los usuarios.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(BotonSecundario, 'Borrar'));
      await tester.pumpAndSettle();
      expect(
        baseFalsa.filas('rubros').map((r) => r['id']),
        isNot(contains('comida')),
      );
      expect(_aviso('Rubro borrado'), findsOneWidget);
      // El baño: no se puede borrar, y lo dice.
      final bano = Rubros.porId(Rubros.bano)!;
      await tester.tap(find.text(bano.nombre));
      await tester.pumpAndSettle();
      expect(find.text('Borrar rubro'), findsNothing);
      expect(
        find.textContaining('No se puede borrar: se usa para preguntar'),
        findsOneWidget,
      );
    });

    testWidgets('con la letra al 200 %: la lista y el editor sin partir ni '
        'cortar', (tester) async {
      await armarPantalla(tester, const PantallaRubros(), escala: 2);
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), isEmpty);
      await tester.tap(find.text(Rubros.porId('comida')!.nombre));
      await tester.pumpAndSettle();
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), isEmpty);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(palabrasPartidas(tester), isEmpty);
      expect(textosCortados(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una frase larga en un chip va en renglones y deja a la vista '
        'el botón para quitarla', (tester) async {
      await armarPantalla(tester, const PantallaRubros(), escala: 2);
      await tester.tap(find.text('Nuevo rubro'));
      await tester.pumpAndSettle();
      const frase = 'repuestos para bicicletas y monopatines eléctricos';
      // Al 200 % la lista arma recién lo que está por verse.
      final lista = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      final campo = find.descendant(
        of: find.widgetWithText(CampoTexto, 'Palabra o frase'),
        matching: find.byType(TextField),
      );
      await tester.scrollUntilVisible(campo, 200, scrollable: lista);
      await tester.pumpAndSettle();
      await tester.enterText(campo, '$frase,');
      await tester.pumpAndSettle();
      final chip = find.widgetWithText(ChipApp, frase);
      await tester.scrollUntilVisible(chip, 200, scrollable: lista);
      await tester.pumpAndSettle();
      expect(chip, findsOneWidget);
      expect(tester.takeException(), isNull);
      final ancho = tester.getSize(find.byType(Scaffold).first).width;
      expect(
        tester.getRect(find.byTooltip('Quitar «$frase»')).right,
        lessThanOrEqualTo(ancho),
      );
    });
  });
}
