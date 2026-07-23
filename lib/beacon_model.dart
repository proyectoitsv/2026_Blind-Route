import 'package:flutter/material.dart';

/// Beacon BLE ya ubicado en el plano de un piso. La posición se guarda
/// normalizada (0.0–1.0) relativa a la imagen del plano. [rssiFiltrado] se
/// actualiza en tiempo real desde el pipeline de posicionamiento
/// (ver ProcesadorSenal.filtrarYPromediar).
///
/// La persistencia se maneja en DatabaseHelper (guardarBeacons /
/// obtenerBeaconsPorPiso), por eso este modelo no incluye serialización propia.
class BeaconMarcado {
  Offset posicion;
  final String nombre;
  final String mac;

  /// Último RSSI filtrado (dBm). Se actualiza en cada ciclo de escaneo.
  double rssiFiltrado;

  BeaconMarcado({
    required this.posicion,
    required this.nombre,
    required this.mac,
    this.rssiFiltrado = -100.0, // Valor inicial por defecto
  });
}