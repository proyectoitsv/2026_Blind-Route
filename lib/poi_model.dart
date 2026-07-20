import 'package:flutter/material.dart';
/// Representa un lugar de interés (Point of Interest) en el mapa.
/// Ejemplos: "Baño", "Terminal 5", "Escalera", "Ascensor", etc.
/// Las coordenadas se guardan normalizadas (0.0 a 1.0) relativas al tamaño
/// de la imagen del plano del piso.
class LugarInteres {
  final int? id; // null hasta que se persiste en la DB
  final int pisoId;
  final String nombre;
  final Offset posicion; // Coordenada normalizada (dx, dy entre 0.0 y 1.0)
  final String? descripcion; // Opcional: descripción adicional

  const LugarInteres({
    this.id,
    required this.pisoId,
    required this.nombre,
    required this.posicion,
    this.descripcion,
  });

  LugarInteres copyWith({int? id}) {
    return LugarInteres(
      id: id ?? this.id,
      pisoId: pisoId,
      nombre: nombre,
      posicion: posicion,
      descripcion: descripcion,
    );
  }
}