import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Formas de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Radios, altos y área táctil. Tarjetas sin borde ni sombra: la forma la da
// el radio y la separación del fondo, el color.
abstract final class FormasApp {
  // ── Radios ──────────────────────────────────────────────────────────────

  /// Tarjetas y grupos de filas.
  static const double radioTarjeta = 20;

  /// Campos y celdas.
  static const double radioCampo = 12;

  /// Botón principal y botones secundarios.
  static const double radioBoton = 14;

  /// Esquinas de arriba de las hojas inferiores, y de los diálogos.
  static const double radioHoja = 24;

  static const BorderRadius bordeTarjeta = BorderRadius.all(
    Radius.circular(radioTarjeta),
  );
  static const BorderRadius bordeCampo = BorderRadius.all(
    Radius.circular(radioCampo),
  );
  static const BorderRadius bordeBoton = BorderRadius.all(
    Radius.circular(radioBoton),
  );
  static const BorderRadius bordeHoja = BorderRadius.vertical(
    top: Radius.circular(radioHoja),
  );

  /// Chips: totalmente redondeados.
  static const OutlinedBorder formaChip = StadiumBorder();

  // ── Altos ───────────────────────────────────────────────────────────────

  /// Área táctil mínima de cualquier control: 48 dp
  /// (kMinInteractiveDimension). Si el dibujo es más chico, el área tocable
  /// igual llega a 48.
  static const double areaTactilMinima = kMinInteractiveDimension;

  /// Alto del botón principal.
  static const double altoBoton = 52;

  /// Alto mínimo de una fila de un grupo. Es mínimo: con letra grande, la
  /// fila crece con el texto.
  static const double altoFilaMinimo = 52;

  /// Manija de las hojas inferiores. Va en el color `borde` de la paleta, que
  /// da 3,52 sobre el panel de la hoja.
  static const Size manijaHoja = Size(36, 4);
}
