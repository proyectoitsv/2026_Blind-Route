import 'dart:math';
import 'calibracion_model.dart';

class ProcesadorSenal {
  // ─── VENTANA DE MEDIANAS ──────────────────────────────────────────────────
  //
  // Mediana truncada sobre ventana deslizante. Más robusta que Kalman para
  // ruido bimodal/asimétrico del multipath BLE.
  //
  // _tamVentana: ventana de exactamente 3 s de señal. Con emisión a 160 ms/beacon
  //   (≈6,25 Hz) → ceil(3000 / 160) = 19 muestras. Subir en entornos con
  //   hormigón/metal si se quiere más suavizado (a costa de latencia).
  // _corteMediana: descarta 20% en cada extremo antes de promediar.

  static const int _tamVentana = 19;
  static const double _corteMediana = 0.20;

  /// Ventana mínima cuando el usuario está caminando: 7 muestras ≈ 1,1 s.
  /// La ventana larga de 3 s da mucha estabilidad con el usuario parado, pero
  /// su retardo de grupo (~1,5 s) es la MAYOR fuente de latencia del pipeline:
  /// a 1,2 m/s son ~1,8 m de atraso antes de que la posición siquiera entre al
  /// filtro. Con el usuario en movimiento conviene resignar suavizado —el
  /// filtro One Euro ya se encarga— a cambio de reducir ese retardo a ~0,55 s.
  static const int _ventanaMin = 7;

  final Map<String, List<double>> _ventanaRssi = {};
  final Map<String, double> _varianzaRssi = {};

  /// Cantidad de muestras (las más recientes del buffer) que efectivamente se
  /// promedian. La controla [ajustarPorMovimiento].
  int _ventanaEfectiva = _tamVentana;

  int get ventanaEfectiva => _ventanaEfectiva;

  /// Acorta la ventana de mediana a medida que el usuario se mueve.
  /// [factor]: 0 = quieto (ventana completa, máxima estabilidad),
  ///           1 = caminando (ventana mínima, mínima latencia).
  /// El buffer sigue guardando [_tamVentana] muestras: solo cambia cuántas se
  /// usan, así volver al estado "quieto" recupera el suavizado al instante,
  /// sin tener que re-llenar nada.
  void ajustarPorMovimiento(double factor) {
    final f = factor.clamp(0.0, 1.0);
    final v = (_tamVentana + (_ventanaMin - _tamVentana) * f).round();
    _ventanaEfectiva = v.clamp(_ventanaMin, _tamVentana);
  }

  // ─── MODELO DE DISTANCIA ──────────────────────────────────────────────────
  //
  // _txPower: RSSI de referencia a 1 m, calibrado = -55 dBm (rango aceptable
  //   por beacon: -50 a -60 dBm). Es la *ordenada al origen* del modelo log.
  //   Para calibración por beacon usar rssiADistanciaConTx(rssi, txPower).
  //
  // _pathLossExponent: es la *pendiente* del modelo y depende del entorno, no
  //   de la referencia de 1 m. La calibración 1 m = -55 dBm fija txPower pero
  //   NO altera n, así que 2.7 (interior típico) sigue siendo el valor correcto.
  //   2.0 = pasillo despejado  |  2.5 = oficina abierta
  //   2.7 = interior típico    |  3.0 = varias paredes
  //   3.5 = hormigón/subterráneo

  static const double _txPower = -55.0;
  static const double _pathLossExponent = 2.7;

  /// Exponente de pérdida de propagación (n) del modelo log-distancia. Expuesto
  /// para que la calibración use el mismo valor al despejar txPower.
  static double get pathLossExponent => _pathLossExponent;

  static double rssiADistanciaConTx(double rssiFiltrado, double txPower) {
    if (rssiFiltrado >= 0) return 0.1;
    final d = pow(10.0, (txPower - rssiFiltrado) / (10.0 * _pathLossExponent))
        .toDouble();
    return d.clamp(0.1, 30.0);
  }

  /// Devuelve el txPower ajustado para [mac] promediando todas las calibraciones
  /// disponibles que tienen una lectura para ese beacon.
  /// Si no hay calibraciones, devuelve [txPowerDefault].
  static double txPowerCalibrado(
    String mac,
    List<CalibracionRegistro> calibraciones, {
    double txPowerDefault = _txPower,
  }) {
    final valores = calibraciones
        .where((c) => c.txPowerAjustado.containsKey(mac))
        .map((c) => c.txPowerAjustado[mac]!)
        .toList();
    if (valores.isEmpty) return txPowerDefault;
    return valores.reduce((a, b) => a + b) / valores.length;
  }

  // ─── FILTRADO PRINCIPAL ───────────────────────────────────────────────────

  double? filtrarYPromediar(String mac, int rssiActual) {
    if (rssiActual > -20 || rssiActual < -110) return null;

    _ventanaRssi.putIfAbsent(mac, () => []);
    final v = _ventanaRssi[mac]!;
    v.add(rssiActual.toDouble());
    if (v.length > _tamVentana) v.removeAt(0);
    // Mínimo de muestras antes de devolver un valor: 25% de la ventana
    // (≈ ceil(19 * 0.25) = 5 muestras ≈ 0,8 s). Fórmula, no hardcodeado:
    // escala automáticamente si se cambia _tamVentana.
    final minMuestras = (_tamVentana * 0.25).ceil();
    if (v.length < minMuestras) return null;

    // Solo las N muestras más recientes (N = ventana efectiva según movimiento).
    final desde = v.length > _ventanaEfectiva ? v.length - _ventanaEfectiva : 0;
    final usadas = desde == 0 ? v : v.sublist(desde);

    // Hot path: se ejecuta por cada beacon en cada callback BLE (~6 Hz × N
    // beacons). Se evitan las asignaciones de sublist() y map()/reduce()
    // recorriendo el rango interior con índices directos. El resultado numérico
    // (media truncada + varianza sobre el interior) es idéntico al anterior.
    final ordenados = List<double>.from(usadas)..sort();
    final corte =
        (usadas.length * _corteMediana).round().clamp(1, usadas.length ~/ 3);
    final hasta = ordenados.length - corte;
    final cuenta = hasta - corte;

    double suma = 0;
    for (int i = corte; i < hasta; i++) {
      suma += ordenados[i];
    }
    final media = suma / cuenta;

    double sumaCuadrados = 0;
    for (int i = corte; i < hasta; i++) {
      final dif = ordenados[i] - media;
      sumaCuadrados += dif * dif;
    }
    _varianzaRssi[mac] = (sumaCuadrados / cuenta).clamp(0.1, 999.0);

    return media;
  }

  double varianzaBeacon(String mac) => _varianzaRssi[mac] ?? 999.0;

  // ─── UTILIDADES ───────────────────────────────────────────────────────────

  void limpiar() {
    _ventanaRssi.clear();
    _varianzaRssi.clear();
    _ventanaEfectiva = _tamVentana;
  }
}