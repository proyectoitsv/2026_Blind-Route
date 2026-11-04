import 'package:flutter/material.dart';

/// Representa una zona no transitable definida por un polígono de vértices.
/// Las coordenadas se guardan normalizadas (0.0 a 1.0) relativas al tamaño
/// de la imagen, para que sean independientes del tamaño de pantalla.
class ZonaNoTransitable {
  final int? id; // null hasta que se persiste en la DB
  final int pisoId;
  final String nombre;
  // Cada punto es un Offset normalizado: dx y dy entre 0.0 y 1.0
  final List<Offset> vertices;

  const ZonaNoTransitable({
    this.id,
    required this.pisoId,
    required this.nombre,
    required this.vertices,
  });

  ZonaNoTransitable copyWith({int? id}) {
    return ZonaNoTransitable(
      id: id ?? this.id,
      pisoId: pisoId,
      nombre: nombre,
      vertices: vertices,
    );
  }
}
