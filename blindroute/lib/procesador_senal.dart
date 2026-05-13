/// Estado del filtro de Kalman por beacon
class _EstadoKalman {
  double estimacion;      // Valor estimado actual
  double varianzaError;   // Incertidumbre de la estimación

  _EstadoKalman(this.estimacion, this.varianzaError);
}

class ProcesadorSenal {
  // Filtro de Kalman por MAC
  final Map<String, _EstadoKalman> _kalman = {};

  // Promedio móvil como segunda pasada (ventana reducida, Kalman ya suaviza bastante)
  final Map<String, List<double>> _historiales = {};
  final int ventanaPromedio = 8;

  // Parámetros del filtro de Kalman
  // R: ruido de medición (mayor = más desconfianza en cada lectura nueva → más suave)
  // Q: ruido de proceso (mayor = el sistema "olvida" el pasado más rápido)
  final double _R = 3.0;
  final double _Q = 0.3;

  /// Procesa una nueva lectura y devuelve el RSSI suavizado, o null si es ruido extremo
  double? filtrarYPromediar(String mac, int rssiActual) {
    // --- 1. RECHAZO DE VALORES ABSURDOS ---
    // RSSI por encima de -20 o por debajo de -110 son claramente errores del hardware
    if (rssiActual > -20 || rssiActual < -110) return null;

    // --- 2. FILTRO DE KALMAN ---
    if (!_kalman.containsKey(mac)) {
      _kalman[mac] = _EstadoKalman(rssiActual.toDouble(), 1.0);
    }

    final k = _kalman[mac]!;

    // Predicción: la señal puede haber derivado un poco (sumamos Q a la incertidumbre)
    k.varianzaError += _Q;

    // Ganancia de Kalman: cuánto peso le damos a la nueva medición
    final ganancia = k.varianzaError / (k.varianzaError + _R);

    // Corrección: combinamos la estimación con la medición
    k.estimacion = k.estimacion + ganancia * (rssiActual - k.estimacion);
    k.varianzaError = (1 - ganancia) * k.varianzaError;

    double rssiKalman = k.estimacion;

    // --- 3. PROMEDIO MÓVIL como segunda pasada ---
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

  void limpiar() {
    _kalman.clear();
    _historiales.clear();
  }
}
