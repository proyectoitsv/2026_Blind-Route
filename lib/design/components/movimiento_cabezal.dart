import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../movimiento.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Movimiento del cabezal
// ═══════════════════════════════════════════════════════════════════════════
//
// Dónde se dibuja el cabezal de la ruta (sobre el plano o en la línea de
// tiempo), como un solo número: la distancia en píxeles a lo largo de la ruta
// o de la pista. Se mueve de dos maneras, según la tabla de movimiento:
//   · Con cada actualización de la posición (seguir), suavizado exponencial
//     con τ = 80 ms: en cada cuadro recorre la fracción 1 − e^(−dt/τ) de lo
//     que falta, con el dt real del cuadro (igual a 60 Hz que a 120 Hz), sin
//     pasarse ni rebotar. Si llega otra posición a mitad de camino, sigue
//     hacia la nueva sin cortes.
//   · Al cambiar de tramo (recorrerHasta), recorre la ruta en 350 ms con
//     cubic-bezier(0.77, 0, 0.175, 1). Si mientras tanto llega otra posición,
//     termina el recorrido y sigue hasta ella con el suavizado; si cambia de
//     tramo otra vez, arranca un recorrido nuevo desde donde está.
// Con movimiento reducido, quien lo usa llama a saltarA: sigue el dato
// directo.
//
// Sin setState por cuadro: avisa a quien escucha (el painter del cabezal,
// que repinta sólo su capa). En segundo plano no hay cuadros: al volver, el
// primero trae todo el tiempo que pasó y el cabezal queda en su lugar final.

/// El movimiento del cabezal de la ruta: un valor (píxeles a lo largo de la
/// ruta) que sigue a la posición. Lo usan la línea de ruta y la línea de
/// tiempo; [valor] es lo que se dibuja.
class MovimientoCabezal extends ChangeNotifier {
  MovimientoCabezal({required TickerProvider vsync, double valor = 0})
    : _valor = valor,
      _objetivo = valor {
    _ticker = vsync.createTicker(_alCuadro);
  }

  late final Ticker _ticker;

  double _valor;
  double _objetivo;

  // El recorrido al cambiar de tramo.
  bool _recorriendo = false;
  double _desde = 0;
  double _hasta = 0;
  Duration? _inicio;

  /// El cuadro anterior, para el dt del suavizado.
  Duration? _anterior;

  /// Lo que se dibuja ahora.
  double get valor => _valor;

  /// Adónde va (la última posición).
  double get objetivo => _objetivo;

  /// Si se está moviendo.
  bool get enMovimiento => _ticker.isActive;

  /// Va directo a [objetivo]: con movimiento reducido, o con una ruta nueva.
  void saltarA(double objetivo) {
    _ticker.stop();
    _recorriendo = false;
    _objetivo = objetivo;
    if (_valor == objetivo) return;
    _valor = objetivo;
    notifyListeners();
  }

  /// Una posición nueva del mismo tramo: la sigue con el suavizado.
  void seguir(double objetivo) {
    _objetivo = objetivo;
    if (_valor == objetivo && !_recorriendo) return;
    _arrancar();
  }

  /// Un cambio de tramo: recorre la ruta desde donde está hasta [objetivo].
  void recorrerHasta(double objetivo) {
    _objetivo = objetivo;
    _desde = _valor;
    _hasta = objetivo;
    _recorriendo = true;
    // Arranca en este cuadro: si el reloj ya corría, desde el último cuadro;
    // si no, desde que arranca.
    _inicio = _ticker.isActive ? _anterior : Duration.zero;
    _arrancar();
  }

  /// Pone en marcha el reloj. Si se llama mientras se arma un cuadro (lo
  /// común: desde didUpdateWidget), el tiempo cuenta desde ese cuadro, así
  /// el movimiento ya se ve en el siguiente.
  void _arrancar() {
    if (_ticker.isActive) return;
    _anterior = Duration.zero;
    _ticker.start();
  }

  void _alCuadro(Duration ahora) {
    final previo = _anterior ?? ahora;
    _anterior = ahora;
    var dt = ahora - previo;

    if (_recorriendo) {
      final inicio = _inicio ??= ahora;
      final transcurrido = ahora - inicio;
      final t =
          (transcurrido.inMicroseconds /
                  MovimientoApp.cabezalTramo.inMicroseconds)
              .clamp(0.0, 1.0);
      _valor = lerpDouble(
        _desde,
        _hasta,
        MovimientoApp.curvaCabezal.transform(t),
      )!;
      if (t < 1) {
        notifyListeners();
        return;
      }
      // Terminó. Si mientras recorría llegó otra posición, sigue hasta
      // ella con lo que sobró del cuadro: después de mucho tiempo sin
      // cuadros (en segundo plano), queda directo en el final.
      _recorriendo = false;
      _valor = _hasta;
      dt = transcurrido - MovimientoApp.cabezalTramo;
    }

    _suavizar(dt);
    notifyListeners();
  }

  /// Recorre la fracción 1 − e^(−dt/τ) de lo que falta. Con el dt real del
  /// cuadro, lo recorrido sólo depende del tiempo que pasó, sea a 60 o a
  /// 120 Hz.
  void _suavizar(Duration dt) {
    final segundos = math.max(0, dt.inMicroseconds) / 1e6;
    final tau = MovimientoApp.tauCabezal.inMicroseconds / 1e6;
    final k = 1 - math.exp(-segundos / tau);
    _valor += (_objetivo - _valor) * k;
    // ¿Llegó? (menos de una décima de píxel)
    if ((_objetivo - _valor).abs() < 0.1) {
      _valor = _objetivo;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
