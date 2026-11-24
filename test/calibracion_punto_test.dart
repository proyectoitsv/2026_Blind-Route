// CALIBRACIÓN EN EL PUNTO EXACTO
//
// Cada calibración guarda dónde estaba parado el admin (el punto que tocó en
// el plano o el de un beacon, si calibró justo debajo), y el ajuste de la
// recta mide las distancias desde ahí. Plano de 20 × 20 m con celdas de 1 m;
// la señal se simula con txPower −59 dBm y n = 2 sobre la distancia 3D, con
// los cuatro beacons a 2,6 m de altura.

import 'dart:math';

import 'package:blindroute/calibracion_model.dart';
import 'package:blindroute/grilla_nav.dart';
import 'package:blindroute/procesador_senal.dart';
import 'package:flutter_test/flutter_test.dart';

const double _lado = 20;
const double _tx = -59;
const double _n = 2;
const double _altura = 2.6;

final GrillaNav _grilla = GrillaNav(
  metrosX: _lado,
  metrosY: _lado,
  tamCeldaMetros: 1,
);

/// Beacons en metros (no en el centro de una celda).
const Map<String, Offset> _beaconsM = {
  'B1': Offset(2.3, 2.8),
  'B2': Offset(17.1, 3.4),
  'B3': Offset(10.6, 16.2),
  'B4': Offset(3.4, 10.9),
};

Offset _norm(Offset m) => Offset(m.dx / _lado, m.dy / _lado);

Map<String, Offset> get _posiciones => {
  for (final e in _beaconsM.entries) e.key: _norm(e.value),
};

double _rssiDesde(Offset puntoM, String mac) {
  final b = _beaconsM[mac]!;
  final d = ProcesadorSenal.distanciaReal(
    b.dx - puntoM.dx,
    b.dy - puntoM.dy,
    _altura,
  );
  return _tx - 10 * _n * log(d) / ln10;
}

/// Calibración tomada parado en [puntoM] (metros). Con [guardarPunto] en
/// false queda como una calibración vieja: sólo la celda.
CalibracionRegistro _calibracion(Offset puntoM, {bool guardarPunto = true}) {
  final p = _norm(puntoM);
  return CalibracionRegistro(
    pisoId: 1,
    celdaIx: _grilla.indiceX(p.dx),
    celdaIy: _grilla.indiceY(p.dy),
    lecturasBle: [
      for (final mac in _beaconsM.keys)
        {'mac': mac, 'rssi': _rssiDesde(puntoM, mac)},
    ],
    txPowerAjustado: const {},
    timestamp: DateTime(2026, 11, 24),
    posicion: guardarPunto ? p : null,
  );
}

Map<String, ModeloRangoBeacon> _ajustar(List<CalibracionRegistro> cals) =>
    ProcesadorSenal.ajustarModelosRango(
      calibraciones: cals,
      posicionesBeacons: _posiciones,
      alturasBeacons: {for (final mac in _beaconsM.keys) mac: _altura},
      grilla: _grilla,
    );

void main() {
  group('el punto se guarda', () {
    test('ida y vuelta por la base y la nube', () {
      final c = _calibracion(const Offset(5.83, 7.21));
      final leida = CalibracionRegistro.fromJson(c.toJson());
      expect(leida.posicion!.dx, closeTo(5.83 / _lado, 1e-12));
      expect(leida.posicion!.dy, closeTo(7.21 / _lado, 1e-12));
      expect(leida.celdaIx, 5);
      expect(leida.celdaIy, 7);
    });

    test('una calibración vieja, sin punto, usa el centro de su celda', () {
      final fila = _calibracion(const Offset(5.83, 7.21)).toJson()
        ..remove('pos_x')
        ..remove('pos_y');
      final vieja = CalibracionRegistro.fromJson(fila);
      expect(vieja.posicion, isNull);
      final centro = vieja.centro(
        (ix, iy) => Offset(_grilla.centroX(ix), _grilla.centroY(iy)),
      );
      expect(centro.dx * _lado, closeTo(5.5, 1e-9));
      expect(centro.dy * _lado, closeTo(7.5, 1e-9));
    });

    test('un punto mal formado se ignora', () {
      final fila = _calibracion(const Offset(5.83, 7.21)).toJson()
        ..['pos_x'] = 'no es un número';
      expect(CalibracionRegistro.fromJson(fila).posicion, isNull);
    });
  });

  group('el ajuste mide desde el punto exacto', () {
    // Parado corrido del centro de cada celda, hasta 0,4 m.
    const puntos = [
      Offset(3.1, 4.4),
      Offset(6.9, 2.1),
      Offset(9.6, 5.8),
      Offset(12.2, 8.6),
      Offset(15.4, 7.3),
      Offset(8.3, 13.1),
      Offset(4.6, 11.6),
      Offset(14.1, 14.4),
      Offset(17.8, 17.9),
      Offset(1.2, 8.7),
      Offset(11.4, 1.3),
      Offset(5.1, 16.6),
    ];

    test('con el punto, la recta sale exacta aunque no se esté en el centro '
        'de la celda', () {
      final modelos = _ajustar([for (final p in puntos) _calibracion(p)]);
      for (final mac in _beaconsM.keys) {
        expect(modelos[mac]!.ajustado, isTrue, reason: mac);
        expect(modelos[mac]!.n, closeTo(_n, 1e-6), reason: mac);
        expect(modelos[mac]!.txPower, closeTo(_tx, 1e-6), reason: mac);
      }
    });

    test(
      'sin el punto (el centro de la celda), la misma toma corre la recta',
      () {
        final modelos = _ajustar([
          for (final p in puntos) _calibracion(p, guardarPunto: false),
        ]);
        final peor = _beaconsM.keys
            .map((mac) => (modelos[mac]!.n - _n).abs())
            .reduce(max);
        expect(peor, greaterThan(0.01));
      },
    );
  });

  test('calibrando sólo justo debajo de cada beacon alcanza para ajustarlos '
      'a todos', () {
    final modelos = _ajustar([
      for (final b in _beaconsM.values) _calibracion(b),
    ]);
    for (final mac in _beaconsM.keys) {
      expect(modelos[mac]!.ajustado, isTrue, reason: mac);
      expect(modelos[mac]!.puntos, 4, reason: mac);
      expect(modelos[mac]!.n, closeTo(_n, 1e-6), reason: mac);
      expect(modelos[mac]!.txPower, closeTo(_tx, 1e-6), reason: mac);
    }
  });
}
