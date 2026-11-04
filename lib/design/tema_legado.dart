import 'package:flutter/material.dart';

import 'colores.dart';
import 'formas.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TemaApp: la API de antes, mientras dura la migración
// ═══════════════════════════════════════════════════════════════════════════
//
// Es lo que había en lib/tema.dart, mudado acá sin cambiar nada de lo que se
// ve: las pantallas que todavía no se migraron (fase 5) lo siguen usando tal
// cual, y lib/tema.dart quedó como un export de este archivo para no tener
// que tocarlas.
//
// Los colores ya no tienen valor propio: salen de ColoresApp, con los mismos
// valores de antes. Las medidas y el ThemeData de abajo son los de antes y
// difieren del sistema nuevo, por eso quedan acá: cuando se migre la última
// pantalla, se borran este archivo y lib/tema.dart.
//
// Se sacaron los miembros que no usaba nadie (textoSobrePrimario, primario,
// textoSobreFondoClaro, instruccionChip, beacon y los tamaños spBrujula,
// spBrujulaGrados, spDestino y spEstado).
//
// No sumar usos nuevos: lo nuevo va con EstiloApp / ColoresApp,
// TipografiaApp, FormasApp, EspaciadoApp, MovimientoApp y TemaBlindRoute
// (lib/design/design.dart).
abstract final class TemaApp {
  // ── Fondos ──────────────────────────────────────────────────────────────
  static const Color fondo = ColoresApp.fondo;
  static const Color fondoCard = ColoresApp.tarjeta;
  static const Color fondoPanel = ColoresApp.panel;
  static const Color fondoSurface = ColoresApp.superficie;

  // ── Acento ──────────────────────────────────────────────────────────────
  static const Color acento = ColoresApp.acento;
  static const Color acentoSuave = ColoresApp.acentoSuave;

  // ── Textos ──────────────────────────────────────────────────────────────
  static const Color textoBlanco = ColoresApp.textoPrincipal;
  static const Color textoSecundario = ColoresApp.textoSecundario;

  // ── Instrucción de giro ─────────────────────────────────────────────────
  static const Color instruccion = ColoresApp.exitoSuave;
  static const Color instruccionAccent = ColoresApp.exito;

  // ── Ruta activa ─────────────────────────────────────────────────────────
  static const Color rutaActivaInicio = ColoresApp.mapaRutaInicio;
  static const Color rutaActivaFin = ColoresApp.mapaRutaFin;
  static const double rutaActivaAlpha = ColoresApp.mapaRutaOpacidad;

  // ── Zonas restringidas ──────────────────────────────────────────────────
  static const Color zonaRestringidaRelleno = ColoresApp.mapaZonaRelleno;
  static const Color zonaRestringidaBorde = ColoresApp.mapaZonaBorde;

  // ── Advertencia ─────────────────────────────────────────────────────────
  static const Color advertencia = ColoresApp.advertencia;
  static const Color fondoAdvertencia = ColoresApp.advertenciaSuave;

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
  // Idéntico al de lib/tema.dart; sólo los dos grises que estaban escritos a
  // mano salen ahora de la paleta, con el mismo valor (separador #30363D y
  // superficie #21262D).
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
        borderSide: const BorderSide(color: ColoresApp.separador),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusButton),
        borderSide: const BorderSide(color: ColoresApp.separador),
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
    dividerTheme: const DividerThemeData(
      color: ColoresApp.superficie,
      thickness: 1,
    ),
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
