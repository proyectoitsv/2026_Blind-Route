import 'package:blindroute/grilla_nav.dart';
import 'package:blindroute/pathfinder.dart';
import 'package:blindroute/zona_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SIN CAMINO: ¿QUÉ PUNTA QUEDÓ ENCERRADA?
// ═══════════════════════════════════════════════════════════════════════════
//
// Plano de 10 × 10 m con celdas de 1 m. Una habitación de 2 × 2 celdas
// (columnas y filas 7 y 8) cerrada por paredes de 20 cm sobre los límites
// de celda (x = 7 y 9, y = 7 y 9): no tapan ningún centro, sólo cortan las
// conexiones. Afuera queda el área principal del piso.

const double _lado = 10.0;

Offset _n(double x, double y) => Offset(x / _lado, y / _lado);

ZonaNoTransitable _zona(double x0, double y0, double x1, double y1) =>
    ZonaNoTransitable(
      pisoId: 1,
      nombre: 'pared',
      vertices: [_n(x0, y0), _n(x1, y0), _n(x1, y1), _n(x0, y1)],
    );

ResolvedorCaminos _conHabitacionCerrada() => ResolvedorCaminos()
  ..inicializar(
    [
      _zona(6.9, 6.9, 9.1, 7.1), // arriba
      _zona(6.9, 8.9, 9.1, 9.1), // abajo
      _zona(6.9, 6.9, 7.1, 9.1), // izquierda
      _zona(8.9, 6.9, 9.1, 9.1), // derecha
    ],
    grilla: GrillaNav(metrosX: _lado, metrosY: _lado, tamCeldaMetros: 1.0),
  );

final _afuera = _n(2.5, 2.5);
final _afueraOtro = _n(5.5, 8.5);
final _adentro = _n(8.5, 8.5);

void main() {
  test('afuera se llega a todos lados; de afuera a adentro, no', () {
    final r = _conHabitacionCerrada();
    expect(r.alcanzable(_afuera, _afueraOtro), isTrue);
    expect(r.alcanzable(_afuera, _adentro), isFalse);
    expect(r.alcanzable(_adentro, _afuera), isFalse);
    expect(r.alcanzable(_adentro, _n(7.5, 7.5)), isTrue);
  });

  test('el A* no encuentra camino hasta la habitación cerrada', () async {
    final r = _conHabitacionCerrada();
    expect(await r.encontrarCamino(_afuera, _adentro), isNull);
    expect(await r.encontrarCamino(_afuera, _afueraOtro), isNotNull);
  });

  test('destino en la habitación cerrada: el encerrado es el destino', () {
    final r = _conHabitacionCerrada();
    expect(r.diagnosticarSinCamino(_afuera, _adentro),
        SinCamino.destinoEncerrado);
  });

  test('usuario en la habitación cerrada: el encerrado es el origen', () {
    final r = _conHabitacionCerrada();
    expect(r.diagnosticarSinCamino(_adentro, _afuera),
        SinCamino.origenEncerrado);
  });

  test('con camino no hay diagnóstico', () {
    final r = _conHabitacionCerrada();
    expect(r.diagnosticarSinCamino(_afuera, _afueraOtro), isNull);
  });

  test('sin inicializar no se sabe: alcanzable y sin diagnóstico', () {
    final r = ResolvedorCaminos();
    expect(r.alcanzable(_afuera, _adentro), isTrue);
    expect(r.diagnosticarSinCamino(_afuera, _adentro), isNull);
  });
}
