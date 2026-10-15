import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Resultado de registrar un tramo en [VelocidadUsuario].
class TramoVelocidad {
  /// Velocidad medida en el tramo (m/s).
  final double velocidadMs;

  /// true si se usó para actualizar la velocidad aprendida.
  final bool usado;

  /// Por qué se descartó, o qué se hizo. Para el log.
  final String motivo;

  const TramoVelocidad(this.velocidadMs, this.usado, this.motivo);
}

/// Velocidad de caminata de la persona que usa ESTE teléfono.
///
/// Arranca en [porDefectoMs] y se va ajustando con cada tramo medido de
/// esquina a esquina: la distancia sale del plano (exacta) y el tiempo, de
/// los giros que detecta el giroscopio en cada esquina, descontando lo que
/// estuvo parado. No usa la posición BLE para medir: salta demasiado.
///
/// Se guarda en el teléfono, así que se sigue afinando entre usos.
class VelocidadUsuario {
  /// Velocidad inicial. Una persona ciega con bastón anda entre 0,7 y 1,0.
  static const double porDefectoMs = 0.9;

  /// Rango en el que se acota la velocidad aprendida.
  static const double minimaMs = 0.4;
  static const double maximaMs = 1.5;

  /// Rango de velocidades de tramo creíbles. Fuera de esto, el tramo se
  /// midió mal (dobló en otro lado, se desvió) y no se usa.
  static const double tramoMinimoMs = 0.3;
  static const double tramoMaximoMs = 1.8;

  /// Tramos más cortos que esto no se usan: el ±0,5 m de cada punta (la
  /// persona no dobla justo en el centro de la celda) pesaría demasiado.
  static const double tramoMinimoMetros = 4.0;

  /// Tiempos de tramo aceptados (s, sin contar lo que estuvo parado).
  static const double tiempoMinimoSeg = 3.0;
  static const double tiempoMaximoSeg = 60.0;

  /// Peso mínimo de cada tramo nuevo. Los primeros pesan más (1/2, 1/3…)
  /// para alejarse rápido del valor inicial; después, cada uno corrige un
  /// cuarto de la diferencia.
  static const double pesoMinimo = 0.25;

  /// Con al menos estas mediciones, se descarta un tramo que se aleje más de
  /// [desvioMaximo] (fracción) de la velocidad aprendida.
  static const int medicionesParaDescartar = 3;
  static const double desvioMaximo = 0.5;

  static const String _claveVelocidad = 'velocidad_caminata_ms';
  static const String _claveMediciones = 'velocidad_caminata_mediciones';

  double _velocidad = porDefectoMs;
  int _mediciones = 0;

  double get velocidadMs => _velocidad;
  int get mediciones => _mediciones;

  /// Lee la velocidad guardada. Si no hay, queda [porDefectoMs].
  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _velocidad = (prefs.getDouble(_claveVelocidad) ?? porDefectoMs)
          .clamp(minimaMs, maximaMs);
      _mediciones = prefs.getInt(_claveMediciones) ?? 0;
    } catch (e) {
      debugPrint('[Velocidad] No se pudo leer la velocidad guardada: $e');
    }
  }

  /// Registra un tramo de [metros] recorrido en [segundos] caminando y, si es
  /// creíble, ajusta la velocidad aprendida y la guarda.
  TramoVelocidad registrarTramo(double metros, double segundos) {
    final v = segundos > 0 ? metros / segundos : 0.0;
    if (metros < tramoMinimoMetros) {
      return TramoVelocidad(v, false,
          'tramo corto (${metros.toStringAsFixed(1)} m)');
    }
    if (segundos < tiempoMinimoSeg || segundos > tiempoMaximoSeg) {
      return TramoVelocidad(v, false,
          'tiempo fuera de rango (${segundos.toStringAsFixed(1)} s)');
    }
    if (v < tramoMinimoMs || v > tramoMaximoMs) {
      return TramoVelocidad(v, false, 'velocidad no creíble');
    }
    if (_mediciones >= medicionesParaDescartar &&
        (v - _velocidad).abs() / _velocidad > desvioMaximo) {
      return TramoVelocidad(v, false,
          'muy distinta de la aprendida (${_velocidad.toStringAsFixed(2)} m/s)');
    }

    final peso = 1.0 / (_mediciones + 2);
    final alfa = peso > pesoMinimo ? peso : pesoMinimo;
    _velocidad = (_velocidad + alfa * (v - _velocidad)).clamp(minimaMs, maximaMs);
    _mediciones++;
    _guardar();
    return TramoVelocidad(v, true,
        'aprendida ${_velocidad.toStringAsFixed(2)} m/s ($_mediciones tramos)');
  }

  Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_claveVelocidad, _velocidad);
      await prefs.setInt(_claveMediciones, _mediciones);
    } catch (e) {
      debugPrint('[Velocidad] No se pudo guardar la velocidad: $e');
    }
  }
}
