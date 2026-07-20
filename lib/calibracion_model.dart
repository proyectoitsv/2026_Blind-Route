import 'dart:convert';

/// Registro de una calibración tomada por el operador parado en una celda
/// concreta de la grilla. Guarda las lecturas BLE del momento y el txPower
/// ajustado por beacon, derivado de la distancia real celda↔beacon.
///
/// Se persiste en la tabla `calibraciones` (ver [DatabaseHelper]). Los dos
/// campos JSON (`lecturasBle`, `txPowerAjustado`) se serializan a TEXT.
class CalibracionRegistro {
  final int? id;
  final int pisoId;
  final int celdaIx;
  final int celdaIy;

  /// Lecturas BLE del momento: `[{"mac": "AA:BB:..", "rssi": -62.5}, ...]`.
  final List<Map<String, dynamic>> lecturasBle;

  /// txPower ajustado por beacon: `{"AA:BB:..": -57.2, ...}`.
  final Map<String, double> txPowerAjustado;

  final DateTime timestamp;
  final String? etiqueta;

  const CalibracionRegistro({
    this.id,
    required this.pisoId,
    required this.celdaIx,
    required this.celdaIy,
    required this.lecturasBle,
    required this.txPowerAjustado,
    required this.timestamp,
    this.etiqueta,
  });

  /// Fila lista para `db.insert`. Omite `id` cuando es null (autoincrement).
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'piso_id': pisoId,
        'celda_ix': celdaIx,
        'celda_iy': celdaIy,
        'lecturas_ble': jsonEncode(lecturasBle),
        'tx_power_ajustado': jsonEncode(txPowerAjustado),
        'timestamp': timestamp.toIso8601String(),
        'etiqueta': etiqueta,
      };

  factory CalibracionRegistro.fromJson(Map<String, dynamic> row) {
    final lecturasRaw = jsonDecode(row['lecturas_ble'] as String) as List<dynamic>;
    final txRaw = jsonDecode(row['tx_power_ajustado'] as String) as Map<String, dynamic>;
    return CalibracionRegistro(
      id: row['id'] as int?,
      pisoId: row['piso_id'] as int,
      celdaIx: row['celda_ix'] as int,
      celdaIy: row['celda_iy'] as int,
      lecturasBle: lecturasRaw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      txPowerAjustado:
          txRaw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      timestamp: DateTime.parse(row['timestamp'] as String),
      etiqueta: row['etiqueta'] as String?,
    );
  }
}
