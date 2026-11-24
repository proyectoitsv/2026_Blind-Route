// Beacon ubicado en el plano de un piso (BeaconMarcado): posición, nombre,
// MAC, altura de instalación y el último RSSI filtrado.

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

  /// Altura de instalación (m sobre el piso), o null si no se indicó.
  ///
  /// El plano es 2D, pero la señal recorre la distancia en 3D: un beacon en
  /// el techo está a más de un metro del teléfono aunque la persona esté justo
  /// debajo. Sin la altura, la distancia de la calibración y la del
  /// posicionamiento salen del plano y el modelo de rango se deforma (ver
  /// ProcesadorSenal.alturaRelativa). Null equivale a "a la altura del
  /// teléfono": así se leen los mapas guardados antes de existir el campo.
  double? altura;

  /// Último RSSI filtrado (dBm). Se actualiza en cada ciclo de escaneo.
  double rssiFiltrado;

  BeaconMarcado({
    required this.posicion,
    required this.nombre,
    required this.mac,
    this.altura,
    this.rssiFiltrado = -100.0, // Valor inicial por defecto
  });
}
