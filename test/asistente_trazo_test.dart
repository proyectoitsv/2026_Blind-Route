import 'package:blindroute/asistente_trazo.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// IMÁN DE TRAZO: TOLERANCIAS QUE ACHICAN CON EL ZOOM
// ═══════════════════════════════════════════════════════════════════════════
//
// Plano de 10 × 10 m. Se dibuja una pared de 5 m × 20 cm: A(2; 2), B(7; 2) y
// el tercer vértice C a 20 cm de B, hacia abajo. La guía de cierre compara C
// con A (el primer vértice).

const double _lado = 10.0;

Offset _n(double x, double y) => Offset(x / _lado, y / _lado);

AjusteTrazo _ajustarC(Offset punto, {double? metrosPorPixel}) =>
    AsistenteTrazo.ajustar(
      punto: punto,
      metrosX: _lado,
      metrosY: _lado,
      ancla: _n(7, 2),
      anclaSecundaria: _n(2, 2),
      diagonales: true,
      metrosPorPixel: metrosPorPixel,
    );

Matcher _cercaDe(Offset esperado) => predicate<Offset>(
      (p) =>
          (p.dx - esperado.dx).abs() < 1e-9 && (p.dy - esperado.dy).abs() < 1e-9,
      'cerca de $esperado',
    );

void main() {
  test('sin saber el zoom, la guía de cierre aplasta una pared de 20 cm', () {
    // Es el problema de antes: 20 cm está dentro de los 40 cm de alineación,
    // así que C cae sobre la línea de A y la pared queda sin ancho.
    final r = _ajustarC(_n(7.003, 2.2));
    expect(r.punto, _cercaDe(_n(7, 2)));
  });

  test('con zoom (5 mm por píxel), la pared de 20 cm queda recta y con ancho',
      () {
    final r = _ajustarC(_n(7.003, 2.2), metrosPorPixel: 0.005);
    // Se imanta a 90° (queda debajo de B) pero no se alinea con A.
    expect(r.punto, _cercaDe(_n(7, 2.2)));
    expect(r.guias.map((g) => g.anguloGrados), [90]);
  });

  test('sin zoom (5 cm por píxel) el imán anda igual que antes', () {
    // 12 px serían 60 cm: se usa el tope de 40 cm, como sin el dato.
    final r = _ajustarC(_n(7.003, 2.2), metrosPorPixel: 0.05);
    expect(r.punto, _cercaDe(_n(7, 2)));
  });

  test('con zoom, una pared de 10 cm también se puede dibujar', () {
    // Sin el dato, el tramo no llega a los 20 cm mínimos para imantar el
    // ángulo, y la guía de cierre igual lo aplasta contra la línea de A.
    final aplastado = _ajustarC(_n(7.004, 2.1));
    expect(aplastado.punto, _cercaDe(_n(7.004, 2)));

    final recto = _ajustarC(_n(7.004, 2.1), metrosPorPixel: 0.005);
    expect(recto.punto, _cercaDe(_n(7, 2.1)));
  });

  test('un metros por píxel inválido se ignora', () {
    final r = _ajustarC(_n(7.003, 2.2), metrosPorPixel: 0);
    expect(r.punto, _cercaDe(_n(7, 2)));
  });
}
