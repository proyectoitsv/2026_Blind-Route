/// Estado del filtro de Kalman por beacon
class _EstadoKalman {
  double estimacion;
  double varianzaError;

  _EstadoKalman(this.estimacion, this.varianzaError);
}

class ProcesadorSenal {
  // Filtro de Kalman por MAC
  final Map<String, _EstadoKalman> _kalman = {};

  // Promedio móvil
  final Map<String, List<double>> _historiales = {};
  final int ventanaPromedio = 15; // Aumentado para más estabilidad

  // Parámetros Kalman más conservadores
  final double _R = 5.0;   // Más desconfianza en lecturas individuales
  final double _Q = 0.1;   // Más memoria del pasado

  // Detección de outliers
  final Map<String, List<int>> _lecturasCrudas = {};
  final int _ventanaOutlier = 7;
  final double _umbralOutlier = 10.0; // dB

  /// Procesa una nueva lectura y devuelve el RSSI suavizado
  double? filtrarYPromediar(String mac, int rssiActual) {
    // Rechazo de valores absurdos
    if (rssiActual > -20 || rssiActual < -110) return null;

    // Detección de outliers con mediana
    if (!_lecturasCrudas.containsKey(mac)) {
      _lecturasCrudas[mac] = [];
    }
    final crudas = _lecturasCrudas[mac]!;
    crudas.add(rssiActual);
    if (crudas.length > _ventanaOutlier) crudas.removeAt(0);

    if (crudas.length >= 4) {
      final mediana = _calcularMediana(crudas);
      final desviacion = (rssiActual - mediana).abs();
      if (desviacion > _umbralOutlier) {
        if (_kalman.containsKey(mac)) {
          return _kalman[mac]!.estimacion;
        }
        return null;
      }
    }

    // Filtro de Kalman
    if (!_kalman.containsKey(mac)) {
      _kalman[mac] = _EstadoKalman(rssiActual.toDouble(), 1.0);
    }

    final k = _kalman[mac]!;
    k.varianzaError += _Q;
    final ganancia = k.varianzaError / (k.varianzaError + _R);
    k.estimacion = k.estimacion + ganancia * (rssiActual - k.estimacion);
    k.varianzaError = (1 - ganancia) * k.varianzaError;

    double rssiKalman = k.estimacion;

    // Promedio móvil
    if (!_historiales.containsKey(mac)) {
      _historiales[mac] = [];
    }
    final historial = _historiales[mac]!;
    historial.add(rssiKalman);
    if (historial.length > ventanaPromedio) {
      historial.removeAt(0);
    }

    return historial.reduce((a, b) => a + b) / historial.length;
  }

  int _calcularMediana(List<int> valores) {
    final ordenados = List<int>.from(valores)..sort();
    final n = ordenados.length;
    if (n % 2 == 1) return ordenados[n ~/ 2];
    return ((ordenados[n ~/ 2 - 1] + ordenados[n ~/ 2]) / 2).round();
  }

  void limpiar() {
    _kalman.clear();
    _historiales.clear();
    _lecturasCrudas.clear();
  }
}