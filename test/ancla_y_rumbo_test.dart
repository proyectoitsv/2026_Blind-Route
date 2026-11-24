// ANCLA, PUERTA POR RUMBO Y COINCIDENCIA PERFECTA
//
// Los valores que pasaron al panel de ajustes: que con los valores de fábrica
// todo dé lo mismo que antes, y que cada uno cambie lo que dice su ayuda.
// Plano de 20 × 20 m; las posiciones son normalizadas (0 a 1).

import 'dart:math';

import 'package:blindroute/posicionador.dart';
import 'package:blindroute/procesador_senal.dart';
import 'package:flutter_test/flutter_test.dart';

const double _lado = 20;

/// Tres beacons alrededor y las distancias exactas desde [real].
List<ObservacionRango> _observaciones(Offset real) => [
  for (final b in const [Offset(0.2, 0.2), Offset(0.8, 0.2), Offset(0.5, 0.8)])
    ObservacionRango(
      b,
      sqrt(pow((b.dx - real.dx) * _lado, 2) + pow((b.dy - real.dy) * _lado, 2)),
      1.0,
    ),
];

double _metros(Offset a, Offset b) =>
    sqrt(pow((a.dx - b.dx) * _lado, 2) + pow((a.dy - b.dy) * _lado, 2));

/// Pasa un desplazamiento por la puerta, caminando y mirando al norte (hacia
/// arriba en el plano), con la puerta cerrada (primer ciclo).
Offset _porLaPuerta(Offset candidata, {double? lateral, double? atras}) {
  const previa = Offset(0.5, 0.5);
  const norte = Offset(0, -1 / _lado);
  final puerta = PuertaRumbo();
  return lateral == null && atras == null
      ? puerta.aplicar(
          posPrevia: previa,
          candidata: candidata,
          rumboPlano: norte,
          metrosX: _lado,
          metrosY: _lado,
          factorMovimiento: 1,
          dt: 0.2,
        )
      : puerta.aplicar(
          posPrevia: previa,
          candidata: candidata,
          rumboPlano: norte,
          metrosX: _lado,
          metrosY: _lado,
          factorMovimiento: 1,
          dt: 0.2,
          gananciaLateral: lateral ?? 0.03,
          gananciaAtras: atras ?? 0.15,
        );
}

void main() {
  group('ancla a la posición anterior', () {
    // La señal dice (0,5; 0,5) y la posición anterior está 2 m al este.
    const real = Offset(0.5, 0.5);
    const previa = Offset(0.6, 0.5);

    Offset estimar({double? quieto}) => quieto == null
        ? Posicionador.estimar(
            _observaciones(real),
            metrosX: _lado,
            metrosY: _lado,
            posPrevia: previa,
            factorMovimiento: 0,
          )
        : Posicionador.estimar(
            _observaciones(real),
            metrosX: _lado,
            metrosY: _lado,
            posPrevia: previa,
            factorMovimiento: 0,
            priorQuieto: quieto,
          );

    test('con los valores del panel de fábrica (3 y 0,25) da lo mismo que '
        'sin pasarlos', () {
      final sinPasar = estimar();
      final conPasar = Posicionador.estimar(
        _observaciones(real),
        metrosX: _lado,
        metrosY: _lado,
        posPrevia: previa,
        factorMovimiento: 0,
        priorQuieto: 3,
        priorMoviendo: 0.25,
      );
      expect(conPasar, sinPasar);
    });

    test('más ancla parado: la posición se queda más cerca de la anterior', () {
      final fuerte = estimar(quieto: 8);
      final debil = estimar(quieto: 0.5);
      expect(_metros(fuerte, previa), lessThan(_metros(debil, previa)));
      // Y con poca ancla, la señal pesa más: queda más cerca de los rangos.
      expect(_metros(debil, real), lessThan(_metros(fuerte, real)));
    });
  });

  group('puerta por rumbo', () {
    test('de costado pasa el 3 % de fábrica, y lo que diga el panel', () {
      // 1 m hacia el este, mirando al norte: todo es lateral.
      const alEste = Offset(0.5 + 1 / _lado, 0.5);
      expect(_porLaPuerta(alEste).dx, closeTo(0.5 + 0.03 / _lado, 1e-9));
      expect(
        _porLaPuerta(alEste, lateral: 0.5).dx,
        closeTo(0.5 + 0.5 / _lado, 1e-9),
      );
    });

    test('hacia atrás pasa el 15 % de fábrica, y lo que diga el panel', () {
      // 1 m hacia el sur, mirando al norte: todo es retroceso.
      const alSur = Offset(0.5, 0.5 + 1 / _lado);
      expect(_porLaPuerta(alSur).dy, closeTo(0.5 + 0.15 / _lado, 1e-9));
      expect(
        _porLaPuerta(alSur, atras: 0.6).dy,
        closeTo(0.5 + 0.6 / _lado, 1e-9),
      );
    });

    test('hacia adelante pasa entero, se regule como se regule', () {
      const alNorte = Offset(0.5, 0.5 - 1 / _lado);
      expect(
        _porLaPuerta(alNorte, lateral: 0.01, atras: 0).dy,
        closeTo(alNorte.dy, 1e-9),
      );
    });
  });

  group('coincidencia perfecta', () {
    test('entre la perfecta y la mínima, la confianza baja en línea recta', () {
      // De fábrica: perfecta 4 dB, mínima 10 dB.
      expect(ProcesadorSenal.confianzaFingerprint(4), 1);
      expect(ProcesadorSenal.confianzaFingerprint(7), closeTo(0.5, 1e-9));
      expect(ProcesadorSenal.confianzaFingerprint(10), 0);
      // Con la perfecta en 6 dB, 7 dB ya es bastante confiable.
      expect(
        ProcesadorSenal.confianzaFingerprint(7, dbMalo: 10, dbBueno: 6),
        closeTo(0.75, 1e-9),
      );
    });
  });
}
