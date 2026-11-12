import 'package:blindroute/reconocimiento_telefono.dart';
import 'package:flutter_test/flutter_test.dart';

// Qué idioma se usa para reconocer la voz en el teléfono, con lo que
// responde Android (ver reconocimiento_telefono.dart).

ConsultaIdioma _elegir({
  List<String> descargados = const [],
  List<String> descargando = const [],
  List<String> soportados = const [],
  String preferido = 'es-AR',
}) => ReconocimientoEnTelefono.elegir(
  preferido,
  descargados: descargados,
  descargando: descargando,
  soportados: soportados,
);

void main() {
  test('el preferido descargado', () {
    final c = _elegir(
      descargados: ['en-US', 'es-AR'],
      soportados: ['en-US', 'es-AR', 'es-US'],
    );
    expect(c.estado, EstadoIdioma.descargado);
    expect(c.idioma, 'es-AR');
  });

  test('sin el preferido, otro español descargado sirve más que el '
      'preferido por descargar', () {
    final c = _elegir(
      descargados: ['en-US', 'es-US'],
      soportados: ['es-AR', 'es-US'],
    );
    expect(c.estado, EstadoIdioma.descargado);
    expect(c.idioma, 'es-US');
  });

  test('sin descargar: el preferido, con guion aunque llegue con guion '
      'bajo', () {
    final c = _elegir(
      preferido: 'es_AR',
      descargados: ['en-US'],
      soportados: ['en-US', 'es-AR', 'es-US'],
    );
    expect(c.estado, EstadoIdioma.sinDescargar);
    expect(c.idioma, 'es-AR');
  });

  test('descargando', () {
    final c = _elegir(descargando: ['es-AR'], soportados: ['es-AR']);
    expect(c.estado, EstadoIdioma.descargando);
    expect(c.idioma, 'es-AR');
  });

  test('sin ningún español, no disponible', () {
    final c = _elegir(descargados: ['en-US'], soportados: ['en-US', 'fr-FR']);
    expect(c.estado, EstadoIdioma.noDisponible);
    expect(c.idioma, isNull);
  });

  test('"estonio" no es español: sólo cuenta "es" o "es-…"', () {
    final c = _elegir(soportados: ['et-EE', 'eu-ES']);
    expect(c.estado, EstadoIdioma.noDisponible);
  });

  test('fuera de Android no hay a quién preguntar: no disponible, y se da '
      'por hecho que hay conexión', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final c = await ReconocimientoEnTelefono.consultar('es-AR');
    expect(c.estado, EstadoIdioma.noDisponible);
    expect(await ReconocimientoEnTelefono.hayConexion(), isTrue);
    expect(await ReconocimientoEnTelefono.pedirDescarga('es-AR'), isFalse);
  });
}
