import 'package:flutter/material.dart';

/// Tokens de diseño de Blind Route — v2.
///
/// Identidad visual: navegación táctil nocturna. Fondo oscuro (#0D1117),
/// acento cian eléctrico (#00C8E0), ruta en azul vibrante (#2979FF).
/// Contraste WCAG AA verificado en todos los pares texto/fondo.
abstract final class TemaApp {
  // ── Fondo principal ──────────────────────────────────────────────────────
  static const Color fondo            = Color(0xFF0D1117); // casi negro
  static const Color fondoCard        = Color(0xFF161B22); // card dark
  static const Color fondoPanel       = Color(0xFF1C2128); // panel ligeramente más claro
  static const Color fondoSurface     = Color(0xFF21262D); // superficie elevada

  // ── Acento principal (cian eléctrico) ────────────────────────────────────
  static const Color acento           = Color(0xFF00C8E0);
  static const Color acentoSuave      = Color(0xFF003D47); // acento con 20% opacity sobre fondo

  // ── Textos ───────────────────────────────────────────────────────────────
  static const Color textoBlanco      = Color(0xFFF0F6FC); // blanco casi puro, ratio 14:1 sobre fondo
  static const Color textoSecundario  = Color(0xFF8B949E); // gris claro, ratio 4.6:1 sobre fondo
  static const Color textoSobrePrimario = Colors.white;

  // ── Compatibilidad con código existente ──────────────────────────────────
  static const Color primario            = Color(0xFF0D1117);
  static const Color textoSobreFondoClaro = textoBlanco;

  // ── Instrucción de giro ──────────────────────────────────────────────────
  static const Color instruccion      = Color(0xFF0A3D28); // verde oscuro card
  static const Color instruccionAccent = Color(0xFF00D97E); // verde vibrante texto
  static const Color instruccionChip  = Color(0xFF0A3D28);

  // ── Ruta activa ──────────────────────────────────────────────────────────
  static const Color rutaActivaInicio = Color(0xFF2979FF);
  static const Color rutaActivaFin    = Color(0xFF00C8E0);
  static const double rutaActivaAlpha = 0.80;

  // ── Zonas restringidas ───────────────────────────────────────────────────
  static const Color zonaRestringidaRelleno = Color(0xFFB71C1C);
  static const Color zonaRestringidaBorde   = Color(0xFFEF5350);

  // ── Advertencia ──────────────────────────────────────────────────────────
  static const Color advertencia      = Color(0xFFF59E0B);
  static const Color fondoAdvertencia = Color(0xFF2D1F00);

  // ── Mapa ─────────────────────────────────────────────────────────────────
  static const Color beacon           = Color(0xFF00C8E0);
  static const Color poi              = Color(0xFFA78BFA);
  static const Color posicionUsuario  = Color(0xFF2979FF);

  // ── Tipografía ───────────────────────────────────────────────────────────
  static const double spBase          = 18.0;
  static const double spInstruccion   = 28.0;
  static const double spDistancia     = 20.0;
  static const double spBrujula       = 18.0;
  static const double spBrujulaGrados = 16.0;
  static const double spDestino       = 18.0;
  static const double spEstado        = 16.0;

  // ── Targets táctiles ─────────────────────────────────────────────────────
  static const double targetTactil    = 56.0;

  // ── Radio de bordes ──────────────────────────────────────────────────────
  static const double radiusCard      = 16.0;
  static const double radiusChip      = 24.0;
  static const double radiusButton    = 14.0;

  // ── ThemeData ─────────────────────────────────────────────────────────────
  static ThemeData get tema => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: fondo,
    colorScheme: const ColorScheme.dark(
      primary: acento,
      secondary: instruccionAccent,
      surface: fondoCard,
      onPrimary: fondo,
      onSurface: textoBlanco,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: fondoCard,
      foregroundColor: textoBlanco,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textoBlanco,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: acento,
        foregroundColor: fondo,
        minimumSize: const Size(0, targetTactil),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
        textStyle: const TextStyle(fontSize: spBase, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: acento,
        minimumSize: const Size(0, targetTactil),
        textStyle: const TextStyle(fontSize: spBase),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: fondoSurface,
        selectedBackgroundColor: acentoSuave,
        selectedForegroundColor: acento,
        foregroundColor: textoSecundario,
        minimumSize: const Size(0, 44),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fondoSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusButton),
        borderSide: const BorderSide(color: Color(0xFF30363D)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusButton),
        borderSide: const BorderSide(color: Color(0xFF30363D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusButton),
        borderSide: const BorderSide(color: acento, width: 2),
      ),
      labelStyle: const TextStyle(color: textoSecundario),
      hintStyle: const TextStyle(color: textoSecundario),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: fondoCard,
      textColor: textoBlanco,
      iconColor: acento,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF21262D), thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: fondoSurface,
      contentTextStyle: const TextStyle(color: textoBlanco, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusButton)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
