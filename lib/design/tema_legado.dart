import 'package:flutter/material.dart';

import 'colores.dart';
import 'formas.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TemaApp: la API de antes, mientras dura la migración
// ═══════════════════════════════════════════════════════════════════════════
//
// Es lo que había en lib/tema.dart, mudado acá: las pantallas que todavía no
// se migraron (fase 5) lo siguen usando tal cual, y lib/tema.dart quedó como
// un export de este archivo para no tener que tocarlas.
//
// Los colores salen de ColoresApp, así que cuando cambia la paleta cambian
// también estas pantallas, con la misma estructura. La paleta del relieve
// (fase 2, v5) tiene dos niveles (fondo y superficie) y estas pantallas usan
// tres (fondo, tarjeta y superficie): la tarjeta pasa a la superficie y lo que
// iba encima de las tarjetas, a un escalón más claro (el gris del
// separador), para que se siga viendo. Los colores "suaves" que la paleta
// nueva no tiene (relleno de chips, de la instrucción y de los avisos) quedan
// acá, con sus pares de contraste, que no cambian. Las medidas y el ThemeData
// de abajo son los de antes y difieren del sistema nuevo: cuando se migre la
// última pantalla, se borran este archivo y lib/tema.dart.
//
// No sumar usos nuevos: lo nuevo va con EstiloApp / ColoresApp,
// TipografiaApp, FormasApp, EspaciadoApp, MovimientoApp, RelieveApp y
// TemaBlindRoute (lib/design/design.dart).
abstract final class TemaApp {
  // ── Fondos ──────────────────────────────────────────────────────────────
  static const Color fondo = ColoresApp.fondo;
  static const Color fondoCard = ColoresApp.superficie;
  static const Color fondoPanel = ColoresApp.superficie;

  /// Lo que va encima de las tarjetas (pistas de deslizadores, chips sin
  /// elegir, recuadros): un escalón más claro que la superficie, el gris del
  /// separador. Encima: texto principal 12,29 · texto secundario 8,08 ·
  /// acento 7,77.
  static const Color fondoSurface = Color(0xFF2A313C);

  // ── Acento ──────────────────────────────────────────────────────────────
  static const Color acento = ColoresApp.acento;

  /// Relleno de chips y elementos elegidos de las pantallas de antes. Acento
  /// encima 7,08 · texto principal 11,21 · texto secundario 7,36.
  static const Color acentoSuave = Color(0xFF003D47);

  // ── Textos ──────────────────────────────────────────────────────────────
  static const Color textoBlanco = ColoresApp.textoPrincipal;
  static const Color textoSecundario = ColoresApp.textoSecundario;

  // ── Instrucción de giro ─────────────────────────────────────────────────
  /// Fondo de la tarjeta de instrucción. El verde encima da 8,70 y el texto
  /// principal, 11,52.
  static const Color instruccion = Color(0xFF0A3D28);
  static const Color instruccionAccent = ColoresApp.hecho;

  // ── Ruta activa ─────────────────────────────────────────────────────────
  static const Color rutaActivaInicio = ColoresApp.mapaRutaInicio;
  static const Color rutaActivaFin = ColoresApp.mapaRutaFin;
  static const double rutaActivaAlpha = ColoresApp.mapaRutaOpacidad;

  // ── Zonas restringidas ──────────────────────────────────────────────────
  static const Color zonaRestringidaRelleno = ColoresApp.mapaZonaRelleno;
  static const Color zonaRestringidaBorde = ColoresApp.mapaZonaBorde;

  // ── Advertencia ─────────────────────────────────────────────────────────
  static const Color advertencia = ColoresApp.advertencia;

  /// Fondo de los avisos de advertencia. La advertencia encima da 10,44 y el
  /// texto principal, 15,07.
  static const Color fondoAdvertencia = Color(0xFF2D1F00);

  // ── Mapa ────────────────────────────────────────────────────────────────
  static const Color guiaAlineacion = ColoresApp.mapaGuia;
  static const Color guiaEtiqueta = ColoresApp.mapaGuia;
  static const Color poi = ColoresApp.mapaLugar;
  static const Color posicionUsuario = ColoresApp.mapaUsuario;

  // ── Medidas de antes ────────────────────────────────────────────────────
  // Difieren de la escala nueva (TipografiaApp, FormasApp): son las que usan
  // hoy las pantallas sin migrar.
  static const double _spBase = 18.0;
  static const double spInstruccion = 28.0;
  static const double spDistancia = 20.0;
  static const double targetTactil = 56.0;
  static const double radiusCard = 16.0;
  static const double radiusChip = 24.0;
  static const double radiusButton = FormasApp.radioBoton; // 14, el mismo

  // ── ThemeData de antes ──────────────────────────────────────────────────
  // El de lib/tema.dart. Con la paleta del relieve, el borde de los campos
  // pasa al gris de los bordes (antes, el separador: con el escalón nuevo
  // quedaba del mismo color que el relleno) y los divisores, al escalón más
  // claro.
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
        foregroundColor: ColoresApp.textoSobreAcento,
        minimumSize: const Size(0, targetTactil),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton),
        ),
        textStyle: const TextStyle(
          fontSize: _spBase,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: acento,
        minimumSize: const Size(0, targetTactil),
        textStyle: const TextStyle(fontSize: _spBase),
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
        borderSide: const BorderSide(color: ColoresApp.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusButton),
        borderSide: const BorderSide(color: ColoresApp.borde),
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
    dividerTheme: const DividerThemeData(color: fondoSurface, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: fondoSurface,
      contentTextStyle: const TextStyle(color: textoBlanco, fontSize: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusButton),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
