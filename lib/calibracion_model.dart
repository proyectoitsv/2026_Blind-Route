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

  /// `true` si este registro es un PUNTO CLAVE (fingerprint): una celda
  /// singular —una esquina donde hay que doblar, la puerta de un aula, el pie
  /// de una escalera— medida durante mucho mas tiempo para que su vector de
  /// RSSI sea un patron confiable.
  ///
  /// Los fingerprints se usan de forma distinta al resto de las calibraciones:
  /// una calibracion comun alimenta el ajuste del modelo de rango
  /// (ProcesadorSenal.ajustarModelosRango); un fingerprint ADEMAS se compara en
  /// vivo contra las lecturas actuales, y si el patron coincide se corrige la
  /// posicion hacia esa celda. Ver [ProcesadorSenal.compararFingerprints].
  ///
  /// La diferencia importa porque el fingerprinting no depende del modelo
  /// log-distancia: no estima una distancia y despues resuelve una geometria,
  /// sino que reconoce un patron completo. Por eso funciona justo donde la
  /// multilateracion es debil (muy cerca de un beacon, donde el modelo log se
  /// satura) y donde mas importa acertar (una esquina donde hay que doblar).
  final bool esFingerprint;

  const CalibracionRegistro({
    this.id,
    required this.pisoId,
    required this.celdaIx,
    required this.celdaIy,
    required this.lecturasBle,
    required this.txPowerAjustado,
    required this.timestamp,
    this.etiqueta,
    this.esFingerprint = false,
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
        'es_fingerprint': esFingerprint ? 1 : 0,
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
      // Instalaciones anteriores a la v9 no tienen la columna: se lee como
      // null y equivale a "calibracion comun".
      esFingerprint: ((row['es_fingerprint'] as int?) ?? 0) == 1,
    );
  }
}