import 'dart:async';

import 'package:blindroute/design/design.dart';
import 'package:blindroute/lista_edificios.dart';
import 'package:blindroute/pantalla_login_admin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ayudas_pantallas.dart';
import 'nube_falsa.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LOGIN DEL ADMINISTRADOR (fase 5.3 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// La pantalla de verdad, con Supabase iniciado como en main_admin.dart y el
// MaterialApp de la app, con el tema de antes: qué dice TalkBack y en qué
// orden, la letra al 200 % con Inter de verdad (ayudas_pantallas.dart), los
// errores debajo de cada campo, «Ingresando…» mientras espera a la nube, el
// teclado («Siguiente» y «Listo»), la entrada a la lista de edificios y el
// aviso de Supabase sin configurar.
//
// ─── La nube de prueba ───
// flutter_test contesta cualquier pedido con un 400 vacío, y antes del cuadro
// siguiente: «Ingresando…» no llegaría a verse. Acá contesta la nube de
// prueba (nube_falsa.dart, la misma de los tests de las listas y de los mapas
// publicados): cada pedido lo contesta el test, cuando quiere, como lo
// contestaría Supabase.
//
// ─── Sin la lista de edificios ───
// Al entrar se abre ListaEdificios, que lee la base del teléfono (en los
// tests no anda). Ahí el test mira la ruta que se abre y no deja dibujar otro
// cuadro: la lista no llega a armarse.

/// Escribe el email y la contraseña.
Future<void> _escribir(
  WidgetTester tester,
  String email,
  String contrasena,
) async {
  await tester.enterText(find.byType(TextField).first, email);
  await tester.enterText(find.byType(TextField).last, contrasena);
  await tester.pump();
}

/// Arma el login como en la app y dibuja sólo el primer cuadro. Lo arma de
/// cero (otro MaterialApp), aunque ya hubiera otro.
Future<ObservadorRutas> _armarPrimerCuadro(WidgetTester tester) async {
  tester.view.physicalSize = telefono * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final observador = ObservadorRutas();
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: ThemeData(primarySwatch: Colors.indigo),
      navigatorObservers: [observador],
      home: const PantallaLoginAdmin(),
    ),
  );
  return observador;
}

/// Que [observador] vio abrirse la lista de edificios, con la transición del
/// sistema de diseño y en lugar del login.
void _revisarEntrada(ObservadorRutas observador, BuildContext contexto) {
  final ruta = observador.reemplazantes.single;
  expect(ruta, isA<RutaApp<void>>());
  expect((ruta as RutaApp<void>).builder(contexto), isA<ListaEdificios>());
}

void main() {
  setUpAll(() async {
    await cargarInter();
    await iniciarSupabaseDePrueba();
  });

  setUp(() {
    AjustesMovimiento.instancia.reiniciarParaTests();
    nubeFalsa
      ..reiniciar()
      ..contestar = (metodo, url) async => credencialesInvalidas;
  });

  // Si un test entró y falló antes de salir, sale acá: los demás empiezan
  // sin sesión (si no, el login entraría directo).
  tearDown(() async {
    if (Supabase.instance.client.auth.currentSession != null) {
      nubeFalsa.contestar = contestarSesion;
      await Supabase.instance.client.auth.signOut();
    }
  });

  testWidgets('con la letra al 100 %: lo que dice TalkBack, en orden; los '
      'encabezados; el ícono en su cuadro; un solo botón principal; 48 dp, '
      'etiquetas y contraste', (tester) async {
    final semantica = tester.ensureSemantics();
    await armarPantalla(tester, const PantallaLoginAdmin());
    expect(find.byType(AmbienteDiseno), findsOneWidget);
    expect(ordenTalkBack(tester), [
      'Blind Route — Administrador',
      'Acceso de administrador',
      'Ingresá con tu cuenta para cargar y publicar mapas.',
      'Email',
      'Contraseña',
      'Ingresar',
    ]);
    expect(
      tester.getSemantics(find.text('Blind Route — Administrador')),
      isSemantics(isHeader: true, namesRoute: true),
    );
    expect(
      tester.getSemantics(find.text('Acceso de administrador')),
      isSemantics(isHeader: true),
    );
    // Es la primera pantalla: sin volver.
    expect(find.byTooltip('Volver'), findsNothing);
    expect(
      find.widgetWithIcon(CuadroIcono, Icons.admin_panel_settings_rounded),
      findsOneWidget,
    );
    expect(find.byType(BotonPrincipal), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Ingresar')),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
        isLiveRegion: false,
      ),
    );
    // Nada gira ni queda andando.
    expect(find.byType(ProgressIndicator), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantica.dispose();
  });

  testWidgets('con la letra al 200 %: nada partido ni cortado (salvo el título '
      'de la barra, que va en un renglón y TalkBack lee entero), también con '
      'los errores, y se llega a «Ingresar» desplazando', (tester) async {
    final semantica = tester.ensureSemantics();
    await armarPantalla(tester, const PantallaLoginAdmin(), escala: 2);
    expect(tester.takeException(), isNull);
    expect(palabrasPartidas(tester), isEmpty);
    expect(textosCortados(tester), ['Blind Route — Administrador']);
    expect(
      tester.getSemantics(find.text('Blind Route — Administrador')).label,
      'Blind Route — Administrador',
    );
    // El desplazamiento de la pantalla (cada campo tiene el suyo, adentro).
    await tester.scrollUntilVisible(
      find.text('Ingresar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(find.text('Completá el email.'), findsOneWidget);
    expect(find.text('Completá la contraseña.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(palabrasPartidas(tester), isEmpty);
    expect(textosCortados(tester), ['Blind Route — Administrador']);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantica.dispose();
  });

  testWidgets('mientras revisa si hay una sesión guardada (un cuadro): sólo la '
      'barra, sin nada que gire; después, el formulario', (tester) async {
    await _armarPrimerCuadro(tester);
    expect(find.text('Blind Route — Administrador'), findsOneWidget);
    expect(find.byType(CampoTexto), findsNothing);
    expect(find.byType(BotonPrincipal), findsNothing);
    expect(find.byType(ProgressIndicator), findsNothing);
    await tester.pump();
    expect(find.byType(CampoTexto), findsNWidgets(2));
    expect(find.text('Ingresar'), findsOneWidget);
  });

  testWidgets('sin email ni contraseña: «Completá el email.» y «Completá la '
      'contraseña.» debajo de cada campo, que TalkBack anuncia y lee después '
      'del suyo, sin ir a la nube; escribir en un campo le borra el error', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await armarPantalla(tester, const PantallaLoginAdmin());
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    final errorEmail = find.text('Completá el email.');
    final errorContrasena = find.text('Completá la contraseña.');
    final campos = find.byType(TextField);
    expect(errorEmail, findsOneWidget);
    expect(errorContrasena, findsOneWidget);
    // Cada uno, debajo de su campo.
    expect(
      tester.getRect(errorEmail).top,
      greaterThan(tester.getRect(campos.first).bottom),
    );
    expect(
      tester.getRect(errorEmail).bottom,
      lessThan(tester.getRect(campos.last).top),
    );
    expect(
      tester.getRect(errorContrasena).top,
      greaterThan(tester.getRect(campos.last).bottom),
    );
    expect(ordenTalkBack(tester).sublist(3), [
      'Email',
      'Completá el email.',
      'Contraseña',
      'Completá la contraseña.',
      'Ingresar',
    ]);
    for (final error in [errorEmail, errorContrasena]) {
      expect(tester.getSemantics(error), isSemantics(isLiveRegion: true));
    }
    // Ni la nube ni un SnackBar.
    expect(nubeFalsa.pedidos, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // Escribir el email le borra el suyo; el de la contraseña sigue.
    await tester.enterText(campos.first, 'admin@ejemplo.com');
    await tester.pump();
    expect(errorEmail, findsNothing);
    expect(errorContrasena, findsOneWidget);
    // Con el email, falta sólo la contraseña.
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(errorEmail, findsNothing);
    expect(errorContrasena, findsOneWidget);
    expect(nubeFalsa.pedidos, isEmpty);
    // Y al revés.
    await tester.enterText(campos.first, '');
    await tester.enterText(campos.last, 'una clave');
    await tester.pump();
    expect(errorContrasena, findsNothing);
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(errorEmail, findsOneWidget);
    expect(errorContrasena, findsNothing);
    expect(nubeFalsa.pedidos, isEmpty);
    semantica.dispose();
  });

  testWidgets('mientras ingresa: «Ingresando…», sin nada que gire, que '
      'TalkBack anuncia, y los campos deshabilitados; si Supabase no lo deja '
      'entrar, el error debajo de la contraseña y todo vuelve', (tester) async {
    final semantica = tester.ensureSemantics();
    await armarPantalla(tester, const PantallaLoginAdmin());
    final respuesta = Completer<Respuesta>();
    nubeFalsa.contestar = (metodo, url) => respuesta.future;
    await _escribir(tester, 'admin@ejemplo.com', 'una clave');
    await tester.tap(find.text('Ingresar'));
    await tester.pump();

    // Esperando a la nube.
    expect(nubeFalsa.pedidos, ['POST /auth/v1/token']);
    expect(find.text('Ingresando…'), findsOneWidget);
    expect(find.text('Ingresar'), findsNothing);
    final boton = tester.widget<BotonPrincipal>(find.byType(BotonPrincipal));
    expect(boton.alPresionar, isNull);
    expect(boton.icono, isNull);
    expect(
      tester.getSemantics(find.text('Ingresando…')),
      isSemantics(
        label: 'Ingresando…',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        isLiveRegion: true,
      ),
    );
    for (final campo in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(campo.enabled, isFalse);
    }
    // Nada gira: ninguna ruedita ni animación que quede corriendo.
    await tester.pumpAndSettle();
    expect(find.byType(ProgressIndicator), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Ingresando…'), findsOneWidget);

    // Supabase no lo deja entrar: el error, debajo de la contraseña.
    respuesta.complete(credencialesInvalidas);
    await tester.pumpAndSettle();
    final error = find.text('Invalid login credentials');
    expect(error, findsOneWidget);
    expect(
      tester.getRect(error).top,
      greaterThan(tester.getRect(find.byType(TextField).last).bottom),
    );
    expect(
      tester.getRect(error).bottom,
      lessThan(tester.getRect(find.byType(BotonPrincipal)).top),
    );
    expect(
      tester.getSemantics(error),
      isSemantics(label: 'Invalid login credentials', isLiveRegion: true),
    );
    expect(find.text('Completá el email.'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // Todo vuelve; el botón ya no es una región en vivo: de lo que cambió,
    // TalkBack anuncia sólo el error.
    expect(find.text('Ingresar'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Ingresar')),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
        isLiveRegion: false,
      ),
    );
    for (final campo in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(campo.enabled, isTrue);
    }
    // Escribir en la contraseña le borra el error.
    await tester.enterText(find.byType(TextField).last, 'otra clave');
    await tester.pump();
    expect(error, findsNothing);
    expect(nubeFalsa.pedidos, hasLength(1));
    semantica.dispose();
  });

  testWidgets('en el teclado: el email sin autocorrector y la contraseña '
      'oculta, juntos para autocompletar; «Siguiente» pasa a la contraseña y '
      '«Listo» ingresa', (tester) async {
    await armarPantalla(tester, const PantallaLoginAdmin());
    final campos = find.byType(TextField);
    await tester.showKeyboard(campos.first);
    var teclado = tester.testTextInput.setClientArgs!;
    expect(teclado['inputAction'], 'TextInputAction.next');
    expect((teclado['inputType'] as Map)['name'], 'TextInputType.emailAddress');
    expect(teclado['autocorrect'], isFalse);
    expect((teclado['autofill'] as Map)['hints'], [AutofillHints.email]);
    // Los dos, en el mismo grupo: el teléfono los completa (y al entrar
    // ofrece guardarlos) de una vez.
    expect(teclado['fields'], hasLength(2));
    await tester.enterText(campos.first, 'admin@ejemplo.com');

    // «Siguiente»: a la contraseña.
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(tester.widget<TextField>(campos.last).focusNode!.hasFocus, isTrue);
    teclado = tester.testTextInput.setClientArgs!;
    expect(teclado['inputAction'], 'TextInputAction.done');
    expect(teclado['obscureText'], isTrue);
    expect(teclado['autocorrect'], isFalse);
    expect(teclado['enableSuggestions'], isFalse);
    expect((teclado['autofill'] as Map)['hints'], [AutofillHints.password]);
    expect(nubeFalsa.pedidos, isEmpty);

    // «Listo»: ingresa.
    await tester.enterText(campos.last, 'una clave');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(nubeFalsa.pedidos, ['POST /auth/v1/token']);
    expect(find.text('Invalid login credentials'), findsOneWidget);
  });

  testWidgets('al entrar: la lista de edificios en lugar del login, con la '
      'transición del sistema de diseño, sin volver a «Ingresar» mientras se '
      'va; con la sesión guardada, entra directo', (tester) async {
    final observador = await armarPantalla(tester, const PantallaLoginAdmin());
    final respuesta = Completer<Respuesta>();
    nubeFalsa.contestar = (metodo, url) => url.path.endsWith('/token')
        ? respuesta.future
        : contestarSesion(metodo, url);
    await _escribir(tester, 'admin@ejemplo.com', 'una clave');
    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('Ingresando…'), findsOneWidget);

    // Supabase lo deja entrar. Desde acá no se dibuja otro cuadro (la lista
    // de edificios leería la base del teléfono): idle sólo deja terminar lo
    // que estaba esperando a la nube.
    respuesta.complete(
      await contestarSesion('POST', Uri(path: '/auth/v1/token')),
    );
    await tester.idle();
    expect(
      Supabase.instance.client.auth.currentSession?.user.email,
      'admin@ejemplo.com',
    );
    final login = tester.element(find.byType(PantallaLoginAdmin));
    _revisarEntrada(observador, login);
    // Sigue en «Ingresando…»: nada pidió volver a dibujarla.
    expect(login.dirty, isFalse);
    expect(find.text('Ingresando…'), findsOneWidget);

    // Con la sesión guardada (la de recién), el login de cero entra directo:
    // el primer cuadro, sólo la barra, y enseguida la lista.
    final deNuevo = await _armarPrimerCuadro(tester);
    expect(find.byType(CampoTexto), findsNothing);
    _revisarEntrada(deNuevo, tester.element(find.byType(PantallaLoginAdmin)));

    // Sale, para los demás tests. Con el reloj falso del test, salir de
    // Supabase no termina nunca: va con el de verdad (runAsync), como el
    // tearDown.
    await tester.runAsync(() => Supabase.instance.client.auth.signOut());
    expect(nubeFalsa.pedidos.last, 'POST /auth/v1/logout');
    expect(Supabase.instance.client.auth.currentSession, isNull);
  });

  testWidgets('sin Supabase configurado: «Falta configurar Supabase», que '
      'TalkBack anuncia, sin los campos; con la letra al 200 %, sin cortarse', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await armarPantalla(tester, const PantallaLoginAdmin(configurado: false));
    expect(find.text('Falta configurar Supabase'), findsOneWidget);
    expect(find.byType(CampoTexto), findsNothing);
    expect(find.byType(BotonPrincipal), findsNothing);
    expect(ordenTalkBack(tester), [
      'Blind Route — Administrador',
      'Falta configurar Supabase\nCargá url y anonKey en supabase_config.dart '
          'para usar la app de administrador.',
    ]);
    expect(
      tester.getSemantics(find.text('Falta configurar Supabase')),
      isSemantics(isLiveRegion: true),
    );
    expect(find.byType(ProgressIndicator), findsNothing);
    expect(nubeFalsa.pedidos, isEmpty);
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await armarPantalla(
      tester,
      const PantallaLoginAdmin(configurado: false),
      escala: 2,
    );
    expect(tester.takeException(), isNull);
    expect(textosCortados(tester), ['Blind Route — Administrador']);
    // «supabase_config.dart» es una sola «palabra», más larga que un
    // renglón: puede partirse.
    expect(
      palabrasPartidas(tester, salvo: (texto) => texto.startsWith('Cargá')),
      isEmpty,
    );
    semantica.dispose();
  });
}
