import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sensors_plus/sensors_plus.dart';

enum EstadoMovimiento { desconocido, quieto, moviendo }

/// Detecta si el usuario está quieto o caminando usando el acelerómetro del
/// teléfono, y expone un [factorMovimiento] continuo en `[0, 1]` que alimenta
/// el término adaptativo de [FiltroUnEuroPosicion].
///
/// Se usa `userAccelerometerEventStream` (aceleración **sin gravedad**): con el
/// teléfono quieto en la mano la magnitud queda en ~0,05–0,2 m/s²; caminando
/// con el teléfono en la mano llega a picos de 2–6 m/s². Esa separación es
/// enorme comparada con la que ofrece la propia señal BLE, y por eso este
/// sensor es el que decide cuánto suavizar.
///
/// ── Detalle importante: la asimetría de las transiciones ───────────────────
/// Pasar a "moviendo" es inmediato (un falso positivo solo cuesta un poco de
/// jitter). Pasar a "quieto" exige [_esperaQuietoMs] de calma sostenida: entre
/// dos pasos hay instantes de aceleración casi nula, y sin esa espera el
/// filtro se congelaría a mitad de zancada.
class DetectorMovimiento {
  /// Energía (m/s²) por debajo de la cual se considera al usuario detenido.
  ///
  /// MEDIDO EN EL AULA: con estos umbrales en 0.18 / 0.60, el teléfono EN LA
  /// MANO daba "en movimiento" todo el tiempo, incluso con la persona parada.
  /// Con el régimen de "quieto" nunca activo, la zona muerta y la histéresis
  /// de celda larga no entraban nunca en juego. El ajuste es chico a
  /// propósito (0.18→0.25 y 0.60→0.80): corre el punto medio lo justo para
  /// que la mano quieta cuente como quieta, sin arriesgar latencia al
  /// caminar. Si al caminar el log muestra mov menor a 0.8, bajar
  /// umbralMoviendo a 0.70.
  static const double umbralQuieto = 0.25;

  /// Energía (m/s²) por encima de la cual se considera que camina. Caminando
  /// con el teléfono en la mano la energía suavizada queda bastante por
  /// encima de 1 m/s², así que subirlo no agrega latencia al caminar.
  static const double umbralMoviendo = 0.80;

  /// Constante de tiempo del suavizado de la energía (s). ~0,35 s promedia
  /// varias zancadas sin borrar el arranque del movimiento.
  static const double tauEnergiaSeg = 0.35;

  /// Calma sostenida necesaria para declarar "quieto".
  static const int _esperaQuietoMs = 800;

  /// Factor que se usa cuando el sensor no está disponible: valor intermedio,
  /// que deja el filtro con un comportamiento parecido al EMA anterior.
  static const double factorSinSensor = 0.45;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  bool _disponible = false;
  double _energia = 0.0;
  DateTime? _ultimoEvento;
  DateTime? _calmaDesde;
  EstadoMovimiento _estado = EstadoMovimiento.desconocido;

  /// Segundos acumulados en estado [EstadoMovimiento.quieto] desde que se
  /// inició. Restando dos lecturas se sabe cuánto estuvo parado el usuario en
  /// un intervalo (ver el aprendizaje de la velocidad en la navegación).
  double _segundosQuieto = 0;

  bool get disponible => _disponible;
  EstadoMovimiento get estado => _estado;
  double get segundosQuieto => _segundosQuieto;

  /// Energía suavizada del acelerómetro (m/s²). Expuesta para diagnóstico.
  double get energia => _energia;

  /// 0 = quieto, 1 = caminando. Interpolación suave entre los dos umbrales
  /// (no un escalón) para que el filtro no cambie de régimen de golpe.
  double get factorMovimiento {
    if (!_disponible) return factorSinSensor;
    final t = ((_energia - umbralQuieto) / (umbralMoviendo - umbralQuieto))
        .clamp(0.0, 1.0);
    return t * t * (3 - 2 * t); // smoothstep
  }

  /// Arranca la escucha del acelerómetro. Devuelve false si el dispositivo no
  /// expone el sensor: en ese caso [factorMovimiento] cae a [factorSinSensor]
  /// y el resto del pipeline sigue funcionando igual.
  Future<bool> iniciar() async {
    if (_sub != null) return _disponible;
    try {
      _sub = userAccelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval, // ~50 Hz
      ).listen(
        _procesarEvento,
        onError: (Object e) {
          debugPrint('[Movimiento] Acelerómetro no disponible: $e');
          _disponible = false;
          _estado = EstadoMovimiento.desconocido;
        },
        cancelOnError: false,
      );
      _disponible = true;
      debugPrint('[Movimiento] Acelerómetro iniciado (~50 Hz).');
      return true;
    } catch (e) {
      debugPrint('[Movimiento] No se pudo iniciar el acelerómetro: $e');
      _disponible = false;
      return false;
    }
  }

  void _procesarEvento(UserAccelerometerEvent e) {
    final ahora = DateTime.now();
    final dt = _ultimoEvento == null
        ? 0.02
        : ahora.difference(_ultimoEvento!).inMicroseconds / 1e6;
    _ultimoEvento = ahora;
    if (dt <= 0 || dt > 1.0) return; // muestra espuria o app suspendida

    if (_estado == EstadoMovimiento.quieto) _segundosQuieto += dt;

    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    // EMA con α dependiente del Δt real: el sensor no entrega a ritmo exacto.
    final alpha = dt / (tauEnergiaSeg + dt);
    _energia = _energia + alpha * (mag - _energia);

    _actualizarEstado(ahora);
  }

  void _actualizarEstado(DateTime ahora) {
    if (_energia > umbralMoviendo) {
      // Movimiento: se adopta de inmediato.
      _calmaDesde = null;
      _cambiarEstado(EstadoMovimiento.moviendo, ahora);
      return;
    }
    if (_energia < umbralQuieto) {
      // Calma: hay que sostenerla para no congelar la posición entre pasos.
      _calmaDesde ??= ahora;
      if (ahora.difference(_calmaDesde!).inMilliseconds >= _esperaQuietoMs) {
        _cambiarEstado(EstadoMovimiento.quieto, ahora);
      }
      return;
    }
    // Zona intermedia: se conserva el estado anterior (histéresis).
    _calmaDesde = null;
  }

  // ── Historial de estados ──────────────────────────────────────────────────

  /// Cambios de estado de los últimos [_historiaCambios], para saber cuánto
  /// caminó el usuario en un intervalo reciente ([segundosMoviendoEntre]).
  final List<({DateTime t, EstadoMovimiento estado})> _cambios = [];
  static const Duration _historiaCambios = Duration(seconds: 30);

  void _cambiarEstado(EstadoMovimiento nuevo, DateTime ahora) {
    if (nuevo == _estado) return;
    _estado = nuevo;
    _cambios.add((t: ahora, estado: nuevo));
    // Se conserva el último cambio anterior al corte: dice en qué estado
    // estaba al principio de la ventana.
    while (_cambios.length > 1 &&
        ahora.difference(_cambios[1].t) > _historiaCambios) {
      _cambios.removeAt(0);
    }
  }

  /// Segundos en estado [EstadoMovimiento.moviendo] entre [desde] y [hasta]
  /// (hasta 30 s atrás).
  double segundosMoviendoEntre(DateTime desde, DateTime hasta) =>
      segundosMoviendo(_cambios, desde, hasta);

  /// Lo mismo que [segundosMoviendoEntre], sobre una lista de cambios de
  /// estado ordenada en el tiempo.
  static double segundosMoviendo(
    List<({DateTime t, EstadoMovimiento estado})> cambios,
    DateTime desde,
    DateTime hasta,
  ) {
    if (!hasta.isAfter(desde)) return 0;
    var estado = EstadoMovimiento.desconocido;
    var t = desde;
    double total = 0;
    for (final c in cambios) {
      if (!c.t.isAfter(desde)) {
        estado = c.estado; // estado vigente al empezar el intervalo
        continue;
      }
      if (!c.t.isBefore(hasta)) break;
      if (estado == EstadoMovimiento.moviendo) {
        total += c.t.difference(t).inMicroseconds / 1e6;
      }
      t = c.t;
      estado = c.estado;
    }
    if (estado == EstadoMovimiento.moviendo) {
      total += hasta.difference(t).inMicroseconds / 1e6;
    }
    return total;
  }

  void detener() {
    _sub?.cancel();
    _sub = null;
    _disponible = false;
    _energia = 0;
    _ultimoEvento = null;
    _calmaDesde = null;
    _estado = EstadoMovimiento.desconocido;
    _cambios.clear();
  }
}