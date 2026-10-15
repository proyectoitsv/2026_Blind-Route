import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sensors_plus/sensors_plus.dart';

import 'seguidor_ruta.dart' show SentidoGiro;

/// Un giro del cuerpo detectado con el giroscopio.
class GiroDetectado {
  final SentidoGiro sentido;

  /// Cuánto giró, en grados (siempre positivo).
  final double grados;

  /// Cuándo empezó y cuándo terminó la rotación.
  final DateTime inicio;
  final DateTime fin;

  const GiroDetectado({
    required this.sentido,
    required this.grados,
    required this.inicio,
    required this.fin,
  });

  @override
  String toString() =>
      '${sentido == SentidoGiro.izquierda ? "izquierda" : "derecha"} '
      '${grados.toStringAsFixed(0)}° '
      'en ${(fin.difference(inicio).inMilliseconds / 1000).toStringAsFixed(1)} s';
}

/// Corta la velocidad de giro alrededor de la vertical en giros sueltos.
///
/// Está separado de [DetectorGiros] (que lee los sensores) para poder
/// probarlo con datos armados.
///
/// Un giro empieza cuando la velocidad de giro (suavizada, ver
/// [tauSuavizadoSeg]) pasa [umbralInicioGradosSeg] y termina cuando se queda
/// por debajo de [umbralFinGradosSeg] durante [calmaParaTerminarMs]. Lo que
/// cuenta es el ángulo NETO entre las dos
/// puntas: el bamboleo del cuerpo y de la mano al caminar va y vuelve, así
/// que suma casi cero y no llega a [gradosMinimos].
class SegmentadorGiros {
  /// Velocidad de giro (°/s) a partir de la cual empieza un giro. Caminando
  /// derecho, el bamboleo de la mano queda casi siempre por debajo.
  static const double umbralInicioGradosSeg = 30;

  /// Por debajo de esta velocidad (°/s), sostenida, el giro terminó.
  static const double umbralFinGradosSeg = 15;

  /// Calma (ms) necesaria para dar el giro por terminado.
  static const int calmaParaTerminarMs = 300;

  /// Ángulo neto mínimo (°) para que sea un giro. Doblar en una esquina de
  /// 90° da, en la práctica, entre 70° y 110°; ajustar la dirección al
  /// arrancar a caminar suele quedar por debajo.
  static const double gradosMinimos = 60;

  /// Ángulo neto máximo (°). Más que esto es darse vuelta, no doblar.
  static const double gradosMaximos = 200;

  /// Duración máxima (ms) de un giro. Más es mirar alrededor o dar vueltas.
  static const int duracionMaximaMs = 4000;

  /// Si después de este tiempo (ms) el ángulo neto sigue siendo menor a
  /// [_gradosMinimosVivo], el "giro" era bamboleo: se descarta para que no
  /// tape el arranque de un giro real.
  static const int _plazoArranqueMs = 1000;
  static const double _gradosMinimosVivo = 20;

  /// Constante de tiempo (s) del suavizado de la velocidad de giro con la
  /// que se decide dónde empieza y dónde termina un giro.
  ///
  /// Caminando, la mano y el cuerpo se bambolean unas dos veces por segundo
  /// (±20°/s o más). Sin suavizar, ese vaivén nunca dejaba la velocidad en
  /// calma el tiempo suficiente: el giro no se daba por terminado y se
  /// descartaba por largo, o sea que un giro hecho CAMINANDO no se detectaba.
  /// Suavizado, el vaivén queda en un tercio y un giro real sigue pasando el
  /// umbral. El ángulo se integra con la velocidad SIN suavizar.
  static const double tauSuavizadoSeg = 0.25;

  /// Ventana (ms) de ángulo crudo que se recupera al detectar el inicio: el
  /// suavizado cruza el umbral un poco después de que empezó el giro.
  static const int _recuperoInicioMs = 500;

  double _suavizada = 0;
  final List<({DateTime t, double grados})> _reciente = [];

  DateTime? _inicio;
  double _acumulado = 0; // grados, con signo (+ = izquierda)
  DateTime? _calmaDesde;

  bool get girando => _inicio != null;

  /// Procesa una muestra: [gradosSeg] es la velocidad de giro alrededor de
  /// la vertical (+ = izquierda), [dt] los segundos desde la anterior.
  /// Devuelve el giro si con esta muestra terminó uno válido.
  GiroDetectado? procesar(double gradosSeg, double dt, DateTime ahora) {
    final a = dt / (tauSuavizadoSeg + dt);
    _suavizada += a * (gradosSeg - _suavizada);
    final ws = _suavizada;
    // El suavizado atrasa los cruces de umbral más o menos τ.
    final atraso =
        Duration(milliseconds: (tauSuavizadoSeg * 1000).round());

    if (_inicio == null) {
      _reciente.add((t: ahora, grados: gradosSeg * dt));
      _reciente.removeWhere((m) =>
          ahora.difference(m.t).inMilliseconds > _recuperoInicioMs);
      if (ws.abs() >= umbralInicioGradosSeg) {
        _inicio = ahora.subtract(atraso);
        // Lo que ya giró antes de que el suavizado cruzara el umbral.
        _acumulado = _reciente.fold(0.0, (s, m) => s + m.grados);
        _reciente.clear();
        _calmaDesde = null;
      }
      return null;
    }

    _acumulado += gradosSeg * dt;
    final duracionMs = ahora.difference(_inicio!).inMilliseconds;

    if (ws.abs() < umbralFinGradosSeg) {
      _calmaDesde ??= ahora;
      if (ahora.difference(_calmaDesde!).inMilliseconds >=
          calmaParaTerminarMs) {
        final total = _acumulado;
        final inicio = _inicio!;
        final fin = _calmaDesde!.subtract(atraso);
        _reiniciar();
        final grados = total.abs();
        if (grados >= gradosMinimos && grados <= gradosMaximos) {
          return GiroDetectado(
            sentido: total > 0 ? SentidoGiro.izquierda : SentidoGiro.derecha,
            grados: grados,
            inicio: inicio,
            fin: fin,
          );
        }
        return null;
      }
    } else {
      _calmaDesde = null;
    }

    if (duracionMs > duracionMaximaMs ||
        (duracionMs > _plazoArranqueMs &&
            _acumulado.abs() < _gradosMinimosVivo)) {
      _reiniciar();
    }
    return null;
  }

  void _reiniciar() {
    _inicio = null;
    _acumulado = 0;
    _calmaDesde = null;
  }
}

/// Detecta cuándo la persona DOBLA, con el giroscopio del teléfono.
///
/// Se usa el giroscopio y no la brújula porque mide la rotación directamente:
/// no lo afectan el hierro de la estructura ni los tableros eléctricos, que
/// en interiores corren la brújula decenas de grados. Para un giro sólo
/// importa cuánto rotó, no hacia dónde apunta.
///
/// Mide la rotación alrededor de la VERTICAL, sin importar cómo se sostenga
/// el teléfono: la vertical sale del acelerómetro (la gravedad, filtrada) y
/// la velocidad de giro es la proyección del giroscopio sobre ella. Con la
/// convención de Android (rotación positiva antihoraria, gravedad medida
/// hacia arriba) el resultado es positivo al doblar a la izquierda.
class DetectorGiros {
  /// Constante de tiempo (s) del filtro de la gravedad. Promedia el vaivén
  /// de los pasos (~2 Hz) sin atrasarse cuando cambia la inclinación.
  static const double tauGravedadSeg = 0.5;

  final void Function(GiroDetectado giro) onGiro;

  DetectorGiros({required this.onGiro});

  final SegmentadorGiros _segmentador = SegmentadorGiros();
  StreamSubscription<GyroscopeEvent>? _subGiro;
  StreamSubscription<AccelerometerEvent>? _subAcel;
  bool _disponible = false;

  double? _gx, _gy, _gz;
  DateTime? _ultimoAcel;
  DateTime? _ultimoGiro;
  double _velocidadGiro = 0;

  bool get disponible => _disponible;

  /// Velocidad de giro alrededor de la vertical (°/s, + = izquierda).
  /// Expuesta para diagnóstico.
  double get velocidadGiroGradosSeg => _velocidadGiro;

  /// Arranca la escucha. Devuelve false si el teléfono no tiene giroscopio:
  /// en ese caso nunca se detectan giros y la navegación sigue como antes.
  Future<bool> iniciar() async {
    if (_subGiro != null) return _disponible;
    try {
      _subAcel = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_procesarAcel, onError: (_) {}, cancelOnError: false);
      _subGiro = gyroscopeEventStream(
        samplingPeriod: SensorInterval.gameInterval, // ~50 Hz
      ).listen(
        _procesarGiro,
        onError: (Object e) {
          debugPrint('[Giros] Giroscopio no disponible: $e');
          _disponible = false;
        },
        cancelOnError: false,
      );
      _disponible = true;
      debugPrint('[Giros] Giroscopio iniciado (~50 Hz).');
      return true;
    } catch (e) {
      debugPrint('[Giros] No se pudo iniciar el giroscopio: $e');
      _disponible = false;
      return false;
    }
  }

  void _procesarAcel(AccelerometerEvent e) {
    final ahora = DateTime.now();
    if (_gx == null) {
      _gx = e.x;
      _gy = e.y;
      _gz = e.z;
      _ultimoAcel = ahora;
      return;
    }
    final dt = ahora.difference(_ultimoAcel!).inMicroseconds / 1e6;
    _ultimoAcel = ahora;
    if (dt <= 0 || dt > 1.0) return;
    final a = dt / (tauGravedadSeg + dt);
    _gx = _gx! + a * (e.x - _gx!);
    _gy = _gy! + a * (e.y - _gy!);
    _gz = _gz! + a * (e.z - _gz!);
  }

  void _procesarGiro(GyroscopeEvent e) {
    final ahora = DateTime.now();
    final dt = _ultimoGiro == null
        ? 0.0
        : ahora.difference(_ultimoGiro!).inMicroseconds / 1e6;
    _ultimoGiro = ahora;
    final gx = _gx, gy = _gy, gz = _gz;
    if (gx == null || gy == null || gz == null) return;
    if (dt <= 0 || dt > 0.5) return; // muestra espuria o app suspendida
    final norma = sqrt(gx * gx + gy * gy + gz * gz);
    if (norma < 1.0) return; // en caída libre no hay vertical

    // Proyección de la rotación (rad/s) sobre la vertical.
    final w = (e.x * gx + e.y * gy + e.z * gz) / norma;
    _velocidadGiro = w * 180 / pi;

    final giro = _segmentador.procesar(_velocidadGiro, dt, ahora);
    if (giro != null) onGiro(giro);
  }

  void detener() {
    _subGiro?.cancel();
    _subAcel?.cancel();
    _subGiro = null;
    _subAcel = null;
    _disponible = false;
    _gx = _gy = _gz = null;
    _ultimoAcel = null;
    _ultimoGiro = null;
  }
}
