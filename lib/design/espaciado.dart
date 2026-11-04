import 'package:flutter/painting.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Espaciado de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Márgenes y separaciones, en dp. Con letra grande el contenido crece hacia
// abajo; los márgenes laterales no cambian, para no robarle ancho al texto.
abstract final class EspaciadoApp {
  /// Entre un ícono y su texto, o entre un número y su unidad.
  static const double minimo = 4;

  /// Entre elementos chicos dentro de una tarjeta.
  static const double chico = 8;

  /// Entre las tarjetas de una grilla.
  static const double entreTarjetas = 12;

  /// Margen a los costados de la pantalla.
  static const double margenLateral = 16;

  /// Relleno interno de las tarjetas.
  static const double rellenoTarjeta = 16;

  /// Entre una sección y la siguiente.
  static const double entreSecciones = 28;

  static const EdgeInsets margenPantalla = EdgeInsets.symmetric(
    horizontal: margenLateral,
  );
  static const EdgeInsets rellenoInternoTarjeta = EdgeInsets.all(
    rellenoTarjeta,
  );
}
