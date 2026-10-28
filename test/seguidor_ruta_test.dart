import 'package:blindroute/grilla_nav.dart';
import 'package:blindroute/seguidor_ruta.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RECÁLCULO: ¿CAMBIÓ LO QUE HAY QUE HACER?
// ═══════════════════════════════════════════════════════════════════════════
//
// Plano de 10 × 10 m con celdas de 1 m. Las rutas se escriben como celdas
// (columna, fila); el pathfinder del empalme es un doble que devuelve el
// camino que se le pasa, así cada caso arma exactamente la situación que
// prueba.

final _g = GrillaNav(metrosX: 10, metrosY: 10, tamCeldaMetros: 1.0);

List<Offset> _ruta(List<(int, int)> celdas) =>
    [for (final (x, y) in celdas) Offset(_g.centroX(x), _g.centroY(y))];

/// Celdas de una fila, de [x0] a [x1] (incluidas, en cualquier sentido).
List<(int, int)> _fila(int y, int x0, int x1) => [
      for (int x = x0; x != x1 + (x1 >= x0 ? 1 : -1); x += (x1 >= x0 ? 1 : -1))
        (x, y),
    ];

/// Celdas de una columna, de [y0] a [y1] (incluidas, en cualquier sentido).
List<(int, int)> _columna(int x, int y0, int y1) => [
      for (int y = y0; y != y1 + (y1 >= y0 ? 1 : -1); y += (y1 >= y0 ? 1 : -1))
        (x, y),
    ];

Future<List<Offset>?> Function(Offset, Offset) _empalme(List<(int, int)> c) =>
    (_, _) async => _ruta(c);

Future<List<Offset>?> _sinEmpalme(Offset _, Offset _) async =>
    throw StateError('este caso no tendría que buscar un empalme');

void main() {
  test('primera ruta: es nueva, pero no un cambio de fondo', () async {
    final d = await SeguidorRuta.decidir(
      nueva: _ruta(_fila(5, 2, 9)),
      vieja: null,
      grilla: _g,
      buscarCamino: _sinEmpalme,
    );
    expect(d.esNueva, isTrue);
    expect(d.cambioDeFondo, isFalse);
  });

  test('la misma ruta corrida una celda no es un cambio de fondo', () async {
    final d = await SeguidorRuta.decidir(
      nueva: _ruta([(2, 6), ..._fila(5, 2, 9)]),
      vieja: _ruta(_fila(5, 2, 9)),
      grilla: _g,
      buscarCamino: _sinEmpalme,
    );
    expect(d.esNueva, isTrue);
    expect(d.cambioDeFondo, isFalse);
  });

  test('se pasó de la esquina y hay que volver: cambio de fondo', () async {
    // Lo que quedaba: doblar en (5, 5) hacia el oeste. Siguió derecho hacia
    // el norte hasta (5, 2); el camino nuevo vuelve a la esquina.
    final d = await SeguidorRuta.decidir(
      nueva: _ruta([..._columna(5, 2, 5), ..._fila(5, 4, 1)]),
      vieja: _ruta(_fila(5, 5, 1)),
      grilla: _g,
      buscarCamino: _sinEmpalme,
    );
    expect(d.motivo, 'vuelve a la ruta anterior');
    expect(d.cambioDeFondo, isTrue);
  });

  test('camino por otro lado que no ahorra: se conserva, sin cambio de fondo',
      () async {
    // Lo que quedaba: la fila 5 de (2, 5) a (9, 5). Está en (2, 9); el
    // camino nuevo va por la fila 9 y sube por la columna 9 (11 m); volver
    // a la fila 5 y seguirla también son 11 m.
    final d = await SeguidorRuta.decidir(
      nueva: _ruta([..._fila(9, 2, 9), ..._columna(9, 8, 5)]),
      vieja: _ruta(_fila(5, 2, 9)),
      grilla: _g,
      buscarCamino: _empalme(_columna(2, 9, 5)),
    );
    expect(d.esNueva, isFalse);
    expect(d.cambioDeFondo, isFalse);
  });

  test('camino por otro lado que ahorra 3 m o más: cambio de fondo', () async {
    // Igual que el anterior, pero volver a la fila 5 obliga a un rodeo por
    // la columna 0 (15 m en total contra 11 m del camino nuevo).
    final d = await SeguidorRuta.decidir(
      nueva: _ruta([..._fila(9, 2, 9), ..._columna(9, 8, 5)]),
      vieja: _ruta(_fila(5, 2, 9)),
      grilla: _g,
      buscarCamino: _empalme(
          [..._fila(9, 2, 0), ..._columna(0, 8, 5), ..._fila(5, 1, 2)]),
    );
    expect(d.esNueva, isTrue);
    expect(d.cambioDeFondo, isTrue);
  });

  test('cambió el objetivo: cambio de fondo', () async {
    final d = await SeguidorRuta.decidir(
      nueva: _ruta(_fila(5, 2, 7)),
      vieja: _ruta(_fila(5, 2, 9)),
      grilla: _g,
      buscarCamino: _sinEmpalme,
    );
    expect(d.cambioDeFondo, isTrue);
  });
}
