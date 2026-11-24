// BEACONS A DISTINTAS ALTURAS
//
// Plano de 20 × 20 m con celdas de 1 m. La señal se simula con el modelo
// log-distancia sobre la distancia 3D (txPower −59 dBm a 1 m, n = 2), con el
// teléfono a ProcesadorSenal.alturaTelefonoM: es lo que mide un teléfono de
// verdad. Dos beacons en el techo (2,6 y 3 m), uno a la altura del teléfono
// y uno a media altura.

import 'dart:math';

import 'package:blindroute/calibracion_model.dart';
import 'package:blindroute/grilla_nav.dart';
import 'package:blindroute/posicionador.dart';
import 'package:blindroute/procesador_senal.dart';
import 'package:flutter_test/flutter_test.dart';

const double _lado = 20;
const double _tx = -59;
const double _n = 2;

final GrillaNav _grilla =
    GrillaNav(metrosX: _lado, metrosY: _lado, tamCeldaMetros: 1);

/// Beacons: celda donde está (en su centro) y altura.
const Map<String, ({int ix, int iy, double altura})> _beacons = {
  'B1': (ix: 2, iy: 2, altura: 2.6),
  'B2': (ix: 17, iy: 3, altura: 3.0),
  'B3': (ix: 10, iy: 16, altura: ProcesadorSenal.alturaTelefonoM),
  'B4': (ix: 3, iy: 15, altura: 1.8),
};

Offset _centro(int ix, int iy) => Offset(_grilla.centroX(ix), _grilla.centroY(iy));

Offset _pos(String mac) => _centro(_beacons[mac]!.ix, _beacons[mac]!.iy);

/// Distancia 3D (m) entre el teléfono en [p] (normalizado) y [mac].
double _distancia(Offset p, String mac) {
  final b = _pos(mac);
  return ProcesadorSenal.distanciaReal(
    (b.dx - p.dx) * _lado,
    (b.dy - p.dy) * _lado,
    _beacons[mac]!.altura,
  );
}

double _rssi(double d) => _tx - 10 * _n * log(d) / ln10;

CalibracionRegistro _calibracion(int ix, int iy, {Iterable<String>? macs}) {
  final p = _centro(ix, iy);
  return CalibracionRegistro(
    pisoId: 1,
    celdaIx: ix,
    celdaIy: iy,
    lecturasBle: [
      for (final mac in macs ?? _beacons.keys)
        {'mac': mac, 'rssi': _rssi(_distancia(p, mac))},
    ],
    txPowerAjustado: const {},
    timestamp: DateTime(2026, 11, 23),
  );
}

/// Calibraciones repartidas por el plano, a distancias variadas de cada
/// beacon (algunas justo debajo de uno).
final List<CalibracionRegistro> _calibraciones = [
  for (final (ix, iy) in [
    (2, 2), (3, 4), (6, 2), (9, 5), (12, 8), (17, 3), (15, 7), (10, 16),
    (8, 13), (4, 11), (3, 15), (14, 14), (18, 18), (1, 9), (11, 1),
  ])
    _calibracion(ix, iy),
];

Map<String, ModeloRangoBeacon> _modelos({required bool conAlturas}) =>
    ProcesadorSenal.ajustarModelosRango(
      calibraciones: _calibraciones,
      posicionesBeacons: {for (final mac in _beacons.keys) mac: _pos(mac)},
      alturasBeacons: conAlturas
          ? {for (final e in _beacons.entries) e.key: e.value.altura}
          : const {},
      grilla: _grilla,
    );

/// Posición estimada parado en [real], con las distancias que da cada
/// modelo para el RSSI que se mediría ahí.
Offset _estimar(Offset real, {required bool conAlturas}) {
  final modelos = _modelos(conAlturas: conAlturas);
  final obs = [
    for (final mac in _beacons.keys)
      ObservacionRango(
        _pos(mac),
        modelos[mac]!.distancia(_rssi(_distancia(real, mac))),
        1.0,
        alturaRelativa: conAlturas
            ? ProcesadorSenal.alturaRelativa(_beacons[mac]!.altura)
            : 0,
      ),
  ];
  return Posicionador.estimar(obs, metrosX: _lado, metrosY: _lado);
}

double _errorM(Offset a, Offset b) =>
    sqrt(pow((a.dx - b.dx) * _lado, 2) + pow((a.dy - b.dy) * _lado, 2));

void main() {
  group('alturas de los beacons', () {
    test('sin altura indicada, todo queda como antes (Δh = 0)', () {
      expect(ProcesadorSenal.alturaRelativa(null), 0);
      expect(ProcesadorSenal.distanciaReal(3, 4, null), closeTo(5, 1e-9));
      expect(
        ProcesadorSenal.alturaRelativa(ProcesadorSenal.alturaTelefonoM),
        0,
      );
    });

    test('el ajuste de un beacon en el techo recupera n y txPower reales '
        'solo con la altura', () {
      final con = _modelos(conAlturas: true)['B1']!;
      expect(con.ajustado, isTrue);
      expect(con.n, closeTo(_n, 0.01));
      expect(con.txPower, closeTo(_tx, 0.1));

      // Sin la altura, la pendiente sale deformada y, parado justo debajo del
      // beacon, el rango "sobre el plano" pasa de 1 m: la multilateración no
      // puede poner a la persona debajo de él.
      final sin = _modelos(conAlturas: false)['B1']!;
      expect((sin.n - _n).abs(), greaterThan(0.1));
      final rssiDebajo = _rssi(_distancia(_pos('B1'), 'B1'));
      expect(sin.distancia(rssiDebajo), greaterThan(1.0));
    });

    test('el beacon a la altura del teléfono no cambia con o sin alturas', () {
      final con = _modelos(conAlturas: true)['B3']!;
      final sin = _modelos(conAlturas: false)['B3']!;
      expect(con.n, closeTo(sin.n, 1e-9));
      expect(con.txPower, closeTo(sin.txPower, 1e-9));
    });

    test('la posición con beacons a distintas alturas: precisa con las '
        'alturas, corrida sin ellas', () {
      for (final real in [
        _centro(5, 5),
        _centro(12, 10),
        _centro(7, 14),
        _centro(16, 16),
      ]) {
        final con = _errorM(_estimar(real, conAlturas: true), real);
        final sin = _errorM(_estimar(real, conAlturas: false), real);
        expect(con, lessThan(0.15), reason: 'con alturas en $real');
        expect(sin, greaterThan(con), reason: 'sin alturas en $real');
      }
    });

    test('parado justo debajo de un beacon del techo, la posición cae '
        'debajo de él', () {
      final real = _pos('B1');
      expect(_errorM(_estimar(real, conAlturas: true), real), lessThan(0.3));
    });

    test('el modelo por defecto (pocas calibraciones) también usa la '
        'altura, y cambiarla no exige volver a calibrar', () {
      // Solo dos calibraciones ven a B2: no alcanza para la regresión.
      final pocas = [
        _calibracion(17, 3, macs: ['B2']),
        _calibracion(12, 8, macs: ['B2']),
      ];
      ModeloRangoBeacon modelo(double? altura) =>
          ProcesadorSenal.ajustarModelosRango(
            calibraciones: pocas,
            posicionesBeacons: {'B2': _pos('B2')},
            alturasBeacons: {'B2': altura},
            grilla: _grilla,
          )['B2']!;

      final conAltura = modelo(_beacons['B2']!.altura);
      expect(conAltura.ajustado, isFalse);
      expect(conAltura.n, ProcesadorSenal.pathLossExponent);
      expect(conAltura.puntos, 2);
      // txPower promedio de los dos puntos, con la distancia 3D.
      double tx(int ix, int iy) {
        final d = _distancia(_centro(ix, iy), 'B2');
        return _rssi(d) + 10 * ProcesadorSenal.pathLossExponent * log(d) / ln10;
      }

      expect(conAltura.txPower, closeTo((tx(17, 3) + tx(12, 8)) / 2, 1e-9));

      // Otra altura, mismas lecturas: otro txPower, sin calibrar de nuevo.
      expect(modelo(null).txPower, isNot(closeTo(conAltura.txPower, 0.5)));
    });
  });
}
