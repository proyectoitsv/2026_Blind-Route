import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:blindroute/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LA NUBE DE PRUEBA
// ═══════════════════════════════════════════════════════════════════════════
//
// Supabase de verdad (supabase_flutter, como en main_admin.dart) hablando con
// una nube de prueba en lugar de la de verdad, para los tests de las
// pantallas del administrador (el login, las listas de edificios y pisos y
// los mapas publicados).
//
// flutter_test contesta cualquier pedido con un 400 vacío, y antes del cuadro
// siguiente: una espera («Ingresando…», «Cargando mapas…») no llegaría a
// verse. Acá lo reemplaza una nube de prueba, con HttpOverrides de dart:io
// (sin paquetes nuevos: package:http no es una dependencia directa y el
// analizador avisaría), puesta antes de iniciar Supabase, que arma un
// cliente nuevo para cada pedido. Cada pedido lo contesta el test, cuando
// quiere (con un Completer), como lo contestaría Supabase.
//
// También contesta los pedidos de Image.network (las miniaturas de los
// mapas publicados): con los bytes de una imagen o con un error.
//
// No termina en _test.dart: flutter test no lo corre solo.

/// Lo que contesta la nube de prueba a un pedido: el estado HTTP y el
/// cuerpo, un texto (JSON) o los bytes de un archivo.
typedef Respuesta = ({int estado, Object cuerpo});

/// Lo que contesta la nube de prueba si el test no dice otra cosa.
const Respuesta noEncontrado = (
  estado: 404,
  cuerpo: '{"message":"No está en la nube de prueba"}',
);

/// Como contesta Supabase a un email o una contraseña que no van.
const Respuesta credencialesInvalidas = (
  estado: 400,
  cuerpo:
      '{"code":400,"error_code":"invalid_credentials",'
      '"msg":"Invalid login credentials"}',
);

/// El id del administrador de la sesión de prueba.
const String idAdminDePrueba = 'admin-de-prueba';

/// La sesión que da Supabase al entrar. El token no es un JWT: así no
/// vence nunca y Supabase no intenta renovarlo.
const Map<String, Object> sesionDePrueba = {
  'access_token': 'token-de-prueba',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'renovacion-de-prueba',
  'user': {
    'id': idAdminDePrueba,
    'aud': 'authenticated',
    'email': 'admin@ejemplo.com',
    'created_at': '2026-11-05T00:00:00Z',
    'app_metadata': <String, Object>{},
    'user_metadata': <String, Object>{},
  },
};

/// Como contesta Supabase a un email y una contraseña que van (la sesión de
/// prueba) y al salir.
Future<Respuesta> contestarSesion(String metodo, Uri url) async =>
    url.path.endsWith('/token')
    ? (estado: 200, cuerpo: jsonEncode(sesionDePrueba))
    : (estado: 204, cuerpo: '');

/// La nube de prueba, una para todo el archivo de tests.
final NubeFalsa nubeFalsa = NubeFalsa();

/// Pone la nube de prueba e inicia Supabase como en main_admin.dart. Va en el
/// setUpAll: Supabase se inicia una sola vez por archivo.
Future<void> iniciarSupabaseDePrueba() async {
  HttpOverrides.global = nubeFalsa;
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
}

/// La nube de prueba: cada pedido lo contesta [contestar].
class NubeFalsa extends HttpOverrides {
  /// Los pedidos que llegaron: método y camino ("POST /auth/v1/token").
  final List<String> pedidos = [];

  /// Cómo se contesta un pedido.
  Future<Respuesta> Function(String metodo, Uri url) contestar =
      (metodo, url) async => noEncontrado;

  /// Sin pedidos y contestando [noEncontrado], para el test siguiente.
  void reiniciar() {
    pedidos.clear();
    contestar = (metodo, url) async => noEncontrado;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Cliente(this);
}

// ─── Lo justo de HttpClient ─────────────────────────────────────────────────
//
// Para el cliente de http que usa Supabase y para Image.network: abre el
// pedido, se traga lo que se manda y, al cerrarlo, espera a que el test
// conteste. Lo que no se usa cae en noSuchMethod.

class _Cliente implements HttpClient {
  _Cliente(this._nube);

  final NubeFalsa _nube;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Pedido(_nube, method, url);

  /// El de Image.network.
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Pedido implements HttpClientRequest {
  _Pedido(this._nube, this.method, this.uri);

  final NubeFalsa _nube;

  @override
  final String method;

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _Cabeceras();

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() async {
    _nube.pedidos.add('$method ${uri.path}');
    final respuesta = await _nube.contestar(method, uri);
    final cuerpo = respuesta.cuerpo;
    return _Respuesta(
      respuesta.estado,
      cuerpo is String ? utf8.encode(cuerpo) : cuerpo as List<int>,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Respuesta extends Stream<List<int>> implements HttpClientResponse {
  _Respuesta(this.statusCode, this._cuerpo);

  final List<int> _cuerpo;

  @override
  final int statusCode;

  @override
  int get contentLength => _cuerpo.length;

  /// Lo pregunta Image.network al juntar los bytes.
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _Cabeceras();

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => '';

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_cuerpo).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Las cabeceras: las del pedido no se guardan; las de la respuesta dicen
/// que es JSON.
class _Cabeceras implements HttpHeaders {
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      action('content-type', ['application/json; charset=utf-8']);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
