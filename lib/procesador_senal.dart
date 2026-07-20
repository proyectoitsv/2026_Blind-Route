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

  final Map<String, List<double>> _ventanaRssi = {};
  final Map<String, double> _varianzaRssi = {};

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

  static double rssiADistancia(double rssiFiltrado) =>
      rssiADistanciaConTx(rssiFiltrado, _txPower);

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

    final ordenados = List<double>.from(v)..sort();
    final corte = (v.length * _corteMediana).round().clamp(1, v.length ~/ 3);
    final interior = ordenados.sublist(corte, ordenados.length - corte);
    final media = interior.reduce((a, b) => a + b) / interior.length;

    final varianza = interior
            .map((x) => pow(x - media, 2).toDouble())
            .reduce((a, b) => a + b) /
        interior.length;
    _varianzaRssi[mac] = varianza.clamp(0.1, 999.0);

    return media;
  }

  double varianzaBeacon(String mac) => _varianzaRssi[mac] ?? 999.0;

  // ─── TRILATERACIÓN ────────────────────────────────────────────────────────
  //
  // [beacons]: lista de mapas { 'x', 'y', 'distancia', 'varianza'(opcional) }
  // Peso WLS = 1 / (distancia² × varianza): cercanos y estables dominan.

  static Map<String, double>? trilaterar(List<Map<String, double>> beacons) {
    final validos = beacons.where((b) => b['distancia']! > 0).toList();
    if (validos.length < 2) return null;

    if (validos.length == 2) {
      final v0 = validos[0]['varianza'] ?? 1.0;
      final v1 = validos[1]['varianza'] ?? 1.0;
      final w0 = 1.0 / (validos[0]['distancia']! * sqrt(v0) + 0.01);
      final w1 = 1.0 / (validos[1]['distancia']! * sqrt(v1) + 0.01);
      final totalW = w0 + w1;
      return {
        'x': (validos[0]['x']! * w0 + validos[1]['x']! * w1) / totalW,
        'y': (validos[0]['y']! * w0 + validos[1]['y']! * w1) / totalW,
      };
    }

    final n = validos.length;
    final ref = validos[n - 1];
    final xr = ref['x']!, yr = ref['y']!, dr = ref['distancia']!;

    double sumWA00 = 0, sumWA01 = 0, sumWA11 = 0, sumWB0 = 0, sumWB1 = 0;

    for (int i = 0; i < n - 1; i++) {
      final b = validos[i];
      final xi = b['x']!, yi = b['y']!, di = b['distancia']!;
      final vi = b['varianza'] ?? 1.0;
      final peso = 1.0 / (di * di * vi + 0.01);
      final a0 = 2 * (xi - xr);
      final a1 = 2 * (yi - yr);
      final bVal = xi * xi - xr * xr + yr * yr - yi * yi + dr * dr - di * di;
      sumWA00 += peso * a0 * a0;
      sumWA01 += peso * a0 * a1;
      sumWA11 += peso * a1 * a1;
      sumWB0 += peso * a0 * bVal;
      sumWB1 += peso * a1 * bVal;
    }

    final det = sumWA00 * sumWA11 - sumWA01 * sumWA01;
    if (det.abs() < 1e-10) return null;

    return {
      'x': (sumWB0 * sumWA11 - sumWB1 * sumWA01) / det,
      'y': (sumWA00 * sumWB1 - sumWA01 * sumWB0) / det,
    };
  }

  // ─── FILTRO DE POSICIÓN (visual) ──────────────────────────────────────────
  //
  // EMA suave para mostrar en el mapa. NO usar para calcular indicaciones.
  // Para navegación usar posicionNavegacion (ver más abajo).
  //
  // _alphaPos: 0.15 = interior típico. Bajar a 0.10 en entornos muy ruidosos.
  // _umbralMovimientoPos: 0.010 ≈ 0.5m en mapa de 50m.
  // _umbralSaltoMaximo: 0.25 ≈ 12.5m. Saltos mayores = error de trilateración.

  static const double _alphaPos = 0.15;
  static const double _umbralMovimientoPos = 0.010;
  static const double _umbralSaltoMaximo = 0.25;

  Map<String, double>? _posicionFiltrada;

  Map<String, double>? filtrarPosicion(Map<String, double>? nuevaPos) {
    if (nuevaPos == null) return _posicionFiltrada;
    if (_posicionFiltrada == null) {
      _posicionFiltrada = Map.from(nuevaPos);
      _navActualizar(nuevaPos); // inicializar navegación también
      return _posicionFiltrada;
    }

    final dx = nuevaPos['x']! - _posicionFiltrada!['x']!;
    final dy = nuevaPos['y']! - _posicionFiltrada!['y']!;
    final distancia = sqrt(dx * dx + dy * dy);

    if (distancia < _umbralMovimientoPos) return _posicionFiltrada;
    if (distancia > _umbralSaltoMaximo) return _posicionFiltrada;

    _posicionFiltrada = {
      'x': _alphaPos * nuevaPos['x']! + (1 - _alphaPos) * _posicionFiltrada!['x']!,
      'y': _alphaPos * nuevaPos['y']! + (1 - _alphaPos) * _posicionFiltrada!['y']!,
    };

    _navActualizar(nuevaPos);
    return _posicionFiltrada;
  }

  Map<String, double>? get posicionActual => _posicionFiltrada;
  void resetearPosicion() {
    _posicionFiltrada = null;
    _navReset();
  }

  // ─── POSICIÓN DE NAVEGACIÓN ───────────────────────────────────────────────
  //
  // Posición estabilizada exclusivamente para calcular indicaciones de ruta.
  // Desacoplada de la posición visual para que el jitter de ~3m no genere
  // instrucciones de voz erróneas ("girá a la derecha" cuando el usuario
  // está quieto).
  //
  // Mecanismo — zona de confianza con histéresis:
  //   1. EMA muy agresiva (_alphaNav = 0.05): ~20 ciclos para moverse 63%
  //      de la distancia real. Muy estable en reposo.
  //   2. Confirmación de movimiento (_ciclosParaConfirmar = 8): la posición
  //      de navegación solo se actualiza cuando la EMA se alejó del centro
  //      actual por MÁS de _radioConfianza Y eso ocurrió en 8 ciclos
  //      consecutivos. Un pico de 3m que dura 1-2 ciclos no activa nada.
  //   3. Una vez confirmado el movimiento, el centro se reubica en la EMA
  //      actual y el contador se resetea.
  //
  // _radioConfianza: radio en coords normalizadas dentro del cual se ignoran
  //   cambios. 0.06 ≈ 3m en mapa de 50m (coincide con el margen de error
  //   reportado). Ajustar si la escala del mapa es diferente.
  //
  // _alphaNav: EMA de navegación. Más bajo = más estable, más lento al mover.
  //   0.05 recomendado. Bajar a 0.03 solo si el jitter sigue siendo problemático.
  //
  // _ciclosParaConfirmar: cuántos ciclos consecutivos fuera del radio antes
  //   de considerar que el usuario realmente se movió.
  //   8 ciclos a 5Hz = 1.6 segundos. Subir si sigue generando falsas alertas.

  static const double _radioConfianza = 0.06;
  static const double _alphaNav = 0.05;
  static const int _ciclosParaConfirmar = 8;

  Map<String, double>? _posNavEma;      // EMA lenta de navegación
  Map<String, double>? _posNavEstable;  // posición confirmada (la que se expone)
  int _ciclosFueraDeZona = 0;

  void _navActualizar(Map<String, double> nuevaPos) {
    // Inicialización
    if (_posNavEma == null) {
      _posNavEma = Map.from(nuevaPos);
      _posNavEstable = Map.from(nuevaPos);
      _ciclosFueraDeZona = 0;
      return;
    }

    // 1. Actualizar EMA lenta
    _posNavEma = {
      'x': _alphaNav * nuevaPos['x']! + (1 - _alphaNav) * _posNavEma!['x']!,
      'y': _alphaNav * nuevaPos['y']! + (1 - _alphaNav) * _posNavEma!['y']!,
    };

    // 2. Distancia entre EMA y centro estable actual
    final dx = _posNavEma!['x']! - _posNavEstable!['x']!;
    final dy = _posNavEma!['y']! - _posNavEstable!['y']!;
    final dist = sqrt(dx * dx + dy * dy);

    if (dist > _radioConfianza) {
      _ciclosFueraDeZona++;
      // 3. Solo confirmar movimiento si persiste N ciclos consecutivos
      if (_ciclosFueraDeZona >= _ciclosParaConfirmar) {
        _posNavEstable = Map.from(_posNavEma!);
        _ciclosFueraDeZona = 0;
      }
    } else {
      // Volvió al radio → resetear contador (fue ruido transitorio)
      _ciclosFueraDeZona = 0;
    }
  }

  void _navReset() {
    _posNavEma = null;
    _posNavEstable = null;
    _ciclosFueraDeZona = 0;
  }

  /// Posición estabilizada para navegación. Usar esta —y solo esta— al
  /// calcular indicaciones de ruta (progreso en camino, instrucción de giro,
  /// detección de llegada al destino).
  ///
  /// Retorna null hasta que haya suficientes lecturas iniciales.
  Map<String, double>? get posicionNavegacion => _posNavEstable;

  // ─── UTILIDADES ───────────────────────────────────────────────────────────

  void limpiar() {
    _ventanaRssi.clear();
    _varianzaRssi.clear();
    _posicionFiltrada = null;
    _navReset();
  }
}