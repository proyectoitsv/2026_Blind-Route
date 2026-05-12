import 'dart:math';

class ProcesadorSenal {
  // Historial de lecturas por MAC para el promedio móvil
  final Map<String, List<int>> _historiales = {};
  
  // Parámetros de configuración
  final int ventanaPromedio = 25; // Cantidad de lecturas para el promedio
  final int umbralSaltoBrusco = 15; // Diferencia máxima en dBm permitida

  /// Procesa una nueva lectura y devuelve el RSSI suavizado o null si es ruido
  double? filtrarYPromediar(String mac, int rssiActual) {
    if (!_historiales.containsKey(mac)) {
      _historiales[mac] = [rssiActual];
      return rssiActual.toDouble();
    }

    List<int> historial = _historiales[mac]!;
    
    // --- 1. FILTRO DE PICOS (Suavización) ---
    // Calculamos el promedio de lo que ya tenemos
    double promedioExistente = historial.reduce((a, b) => a + b) / historial.length;

    // Si el salto es demasiado brusco respecto al promedio, lo ignoramos
    if ((rssiActual - promedioExistente).abs() > umbralSaltoBrusco) {
      return null; // Es un error de lectura o rebote
    }

    // --- 2. ACTUALIZACIÓN DE HISTORIAL ---
    historial.add(rssiActual);
    if (historial.length > ventanaPromedio) {
      historial.removeAt(0);
    }

    // --- 3. CÁLCULO DE PROMEDIO MÓVIL ---
    return historial.reduce((a, b) => a + b) / historial.length;
  }

  // Limpia los datos cuando cambiamos de piso o edificio
  void limpiar() {
    _historiales.clear();
  }
}