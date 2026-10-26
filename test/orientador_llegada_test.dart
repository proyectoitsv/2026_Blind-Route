import 'package:blindroute/orientacion_service.dart';
import 'package:blindroute/orientador_llegada.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ORIENTACIÓN AL LLEGAR
// ═══════════════════════════════════════════════════════════════════════════
//
// El lugar queda al norte (rumbo 0°). Los ciclos van cada 200 ms, como el
// posicionamiento; [_ms] da la hora de cada uno desde el inicio.

final DateTime _t0 = DateTime(2026, 10, 26, 12);

DateTime _ms(int ms) => _t0.add(Duration(milliseconds: ms));

OrientadorLlegada _nuevo() =>
    OrientadorLlegada(rumboObjetivo: 0, inicio: _t0);

PasoOrientacion _paso(OrientadorLlegada o, int ms, double? heading,
        {double velocidad = 0}) =>
    o.actualizar(heading: heading, velocidadAngular: velocidad, ahora: _ms(ms));

/// Primer paso mirando a [heading], con la indicación registrada como dicha
/// (es lo que hace la pantalla al arrancar).
OrientadorLlegada _arrancado(double heading) {
  final o = _nuevo();
  final p = _paso(o, 0, heading);
  expect(p.estado, EstadoOrientacion.girando);
  o.registrarIndicacion(p.indicacion!, _ms(0));
  return o;
}

void main() {
  test('si ya viene mirando hacia el lugar, termina en el primer paso', () {
    final p = _paso(_nuevo(), 0, 20, velocidad: 50);
    expect(p.estado, EstadoOrientacion.deFrente);
    expect(OrientadorLlegada.lado(p.giro!), 'adelante');
  });

  test('con el lugar al costado, el primer paso dice hacia dónde girar', () {
    // Mira al este: el norte le queda a la izquierda.
    final p = _paso(_nuevo(), 0, 90);
    expect(p.estado, EstadoOrientacion.girando);
    expect(p.indicacion, 'Girá a la izquierda');
    expect(p.giro, closeTo(-90, 1e-9));
  });

  test('el rumbo da la vuelta por el norte sin saltos', () {
    // 350° → 0°: son 10° a la derecha, no 350° a la izquierda.
    final p = _paso(_nuevo(), 0, 350);
    expect(p.estado, EstadoOrientacion.deFrente);
    expect(p.giro, closeTo(10, 1e-9));
  });

  test('de frente y quieto, termina recién después de sostenerlo', () {
    final o = _arrancado(90);
    expect(_paso(o, 200, 10).estado, EstadoOrientacion.girando);
    expect(_paso(o, 600, 10).estado, EstadoOrientacion.girando);
    expect(_paso(o, 800, 10).estado, EstadoOrientacion.deFrente);
  });

  test('pasando por el rumbo mientras gira rápido no termina', () {
    final o = _arrancado(90);
    for (int ms = 200; ms <= 1400; ms += 200) {
      expect(_paso(o, ms, 5, velocidad: 80).estado, EstadoOrientacion.girando);
    }
    // Frena: desde ahí cuenta el tiempo de frente.
    expect(_paso(o, 1600, 5).estado, EstadoOrientacion.girando);
    expect(_paso(o, 2200, 5).estado, EstadoOrientacion.deFrente);
  });

  test('mientras gira no dice nada; quieto y corto, corrige con "un poco"', () {
    final o = _arrancado(90);
    for (int ms = 200; ms <= 2000; ms += 200) {
      expect(_paso(o, ms, 60, velocidad: 60).indicacion, isNull);
    }
    // Se pasó: quedó mirando a 320°, 40° a la izquierda del lugar.
    expect(_paso(o, 2600, 320).indicacion, isNull);
    expect(_paso(o, 3200, 320).indicacion, isNull); // quieto 0,6 s
    expect(_paso(o, 3400, 320).indicacion, 'Girá un poco a la derecha');
  });

  test('si no se mueve, repite la misma indicación cada 5 s', () {
    final o = _arrancado(90);
    for (int ms = 200; ms < 5000; ms += 200) {
      expect(_paso(o, ms, 90).indicacion, isNull, reason: '$ms ms');
    }
    expect(_paso(o, 5000, 90).indicacion, 'Girá a la izquierda');
  });

  test('si el motor estaba ocupado, la vuelve a pedir en el ciclo siguiente',
      () {
    final o = _arrancado(90);
    for (int ms = 200; ms < 5000; ms += 200) {
      _paso(o, ms, 90);
    }
    expect(_paso(o, 5000, 90).indicacion, 'Girá a la izquierda');
    // No se registró como dicha.
    expect(_paso(o, 5200, 90).indicacion, 'Girá a la izquierda');
    o.registrarIndicacion('Girá a la izquierda', _ms(5200));
    expect(_paso(o, 5400, 90).indicacion, isNull);
  });

  test('a los 15 s se vence, con el lado donde quedó el lugar', () {
    final o = _arrancado(180);
    expect(_paso(o, 14800, 180).estado, EstadoOrientacion.girando);
    final p = _paso(o, 15000, 180);
    expect(p.estado, EstadoOrientacion.vencida);
    expect(OrientadorLlegada.lado(p.giro!), 'atrás');
  });

  test('sin brújula no hay indicaciones, y se vence igual', () {
    final o = _arrancado(90);
    final p = _paso(o, 1000, null);
    expect(p.estado, EstadoOrientacion.girando);
    expect(p.indicacion, isNull);
    expect(p.giro, isNull);
    expect(_paso(o, 15000, null).estado, EstadoOrientacion.vencida);
  });

  test('textos del giro y del lado', () {
    expect(OrientadorLlegada.textoGiro(45), 'Girá un poco a la derecha');
    expect(OrientadorLlegada.textoGiro(-100), 'Girá a la izquierda');
    expect(OrientadorLlegada.textoGiro(170), 'Date la vuelta');
    expect(OrientadorLlegada.lado(-25), 'adelante');
    expect(OrientadorLlegada.lado(90), 'a tu derecha');
    expect(OrientadorLlegada.lado(-90), 'a tu izquierda');
    expect(OrientadorLlegada.lado(-160), 'atrás');
  });

  test('rumboHacia: escala distinta por eje y rotación del mapa', () {
    // Plano de 20 × 10 m. Hacia la derecha del plano es el este si el
    // plano no está rotado.
    final este = OrientacionService.rumboHacia(
      desde: const Offset(0.5, 0.5),
      hacia: const Offset(0.6, 0.5),
      metrosX: 20,
      metrosY: 10,
    );
    expect(este, closeTo(90, 1e-9));
    // 2 m a la derecha y 2 m hacia arriba (0,1 y 0,2 normalizados): 45°.
    final diagonal = OrientacionService.rumboHacia(
      desde: const Offset(0.5, 0.5),
      hacia: const Offset(0.6, 0.3),
      metrosX: 20,
      metrosY: 10,
    );
    expect(diagonal, closeTo(45, 1e-9));
    // Con el "arriba" del plano apuntando al oeste (270°), hacia arriba es
    // el oeste.
    final arriba = OrientacionService.rumboHacia(
      desde: const Offset(0.5, 0.5),
      hacia: const Offset(0.5, 0.2),
      rotacionMapa: 270,
      metrosX: 20,
      metrosY: 10,
    );
    expect(arriba, closeTo(270, 1e-9));
  });
}
