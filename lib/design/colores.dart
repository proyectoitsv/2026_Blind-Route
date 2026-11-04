import 'package:flutter/painting.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Paleta de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Fuente de verdad de los colores de las dos apps. Ninguna pantalla define
// colores sueltos: usa estos o los mismos desde el tema (EstiloApp.de).
//
// Contraste WCAG 2.x calculado con un script (luminancia relativa sRGB) y
// truncado a dos decimales: nunca se redondea para arriba, así un 4,499 no
// pasa por 4,5. Los mínimos que rigen:
//   · texto normal ≥ 4,5:1
//   · texto importante (títulos, números clave) ≥ 7:1
//   · íconos, bordes de controles y gráficos ≥ 3:1
//
// Los cuatro fondos van de más oscuro a más claro: fondo < tarjeta < panel <
// superficie. Las tarjetas se separan del fondo por color, sin borde ni
// sombra. Antes de cambiar o agregar un color, recalcular el contraste y
// actualizar el valor anotado.
abstract final class ColoresApp {
  // ── Fondos ──────────────────────────────────────────────────────────────

  /// Fondo de todas las pantallas.
  static const Color fondo = Color(0xFF0D1117);

  /// Tarjetas y grupos de filas.
  static const Color tarjeta = Color(0xFF161B22);

  /// Hojas inferiores, diálogos y menús: un poco más claros que la tarjeta.
  static const Color panel = Color(0xFF1C2128);

  /// Campos, celdas y superficies elevadas.
  static const Color superficie = Color(0xFF21262D);

  // ── Líneas ──────────────────────────────────────────────────────────────

  /// Divisores finos dentro de tarjetas. Es decorativo: da 1,55:1 sobre el
  /// fondo y 1,41:1 sobre la tarjeta, así que no sirve para marcar el borde
  /// de un control (para eso está [borde]).
  static const Color separador = Color(0xFF30363D);

  /// Borde de controles: campos, botones con contorno, pista de interruptor,
  /// pista de deslizador y manija de las hojas. Es el gris más discreto de la
  /// familia que pasa 3:1 contra los cuatro fondos: fondo 4,11 · tarjeta
  /// 3,76 · panel 3,52 · superficie 3,31.
  static const Color borde = Color(0xFF6E7681);

  // ── Texto ───────────────────────────────────────────────────────────────

  /// Texto principal. fondo 17,38 · tarjeta 15,89 · panel 14,86 ·
  /// superficie 13,98. Sirve para texto importante sobre cualquier fondo.
  static const Color textoPrincipal = Color(0xFFF0F6FC);

  /// Texto secundario. fondo 6,15 · tarjeta 5,62 · panel 5,26 ·
  /// superficie 4,94. Sirve para texto normal; para títulos y números clave
  /// no alcanza (no llega a 7:1).
  static const Color textoSecundario = Color(0xFF8B949E);

  /// Texto e íconos sobre un relleno de acento, de éxito, de error o sobre el
  /// degradado: acento 9,31 · éxito 10,11 · error 5,55 · degradado ≥ 9,31.
  /// Es el mismo valor que el fondo. El blanco sobre el cian no pasa.
  static const Color textoSobreAcento = fondo;

  // ── Acento (cian) ───────────────────────────────────────────────────────

  /// Texto en acento, íconos, pestaña activa y foco. fondo 9,31 · tarjeta
  /// 8,51 · panel 7,96 · superficie 7,49: sirve para texto importante.
  static const Color acento = Color(0xFF00C8E0);

  /// Fondo de chips y de íconos en acento. El acento encima da 5,87 (texto
  /// normal, no importante) y el texto principal, 10,97.
  static const Color acentoSuave = Color(0xFF003D47);

  // ── Estados ─────────────────────────────────────────────────────────────

  /// Éxito y confirmación, guiado positivo. fondo 10,11 · tarjeta 9,24 ·
  /// panel 8,65 · superficie 8,13.
  static const Color exito = Color(0xFF00D97E);

  /// Fondo de la tarjeta de instrucción. Encima, el texto importante va en
  /// [textoPrincipal] (11,27); el éxito da 6,56, que sirve para texto normal
  /// pero no para el dato principal.
  static const Color exitoSuave = Color(0xFF0A3D28);

  /// Advertencia. fondo 8,81 · tarjeta 8,05 · panel 7,53 · superficie 7,08.
  static const Color advertencia = Color(0xFFF59E0B);

  /// Fondo de los avisos de advertencia. La advertencia encima da 7,47 y el
  /// texto principal, 14,75.
  static const Color advertenciaSuave = Color(0xFF2D1F00);

  /// Error, para texto e íconos. fondo 5,55 · tarjeta 5,07 · panel 4,75.
  /// Sobre la superficie da 4,46: ahí no se usa como texto (como ícono, sí).
  static const Color error = Color(0xFFFF453A);

  // ── Degradado ───────────────────────────────────────────────────────────

  /// De acento a éxito. Un solo uso fuerte por pantalla: el botón principal
  /// o el dato principal, nunca un control crítico de la navegación en vivo.
  /// El texto encima va en [textoSobreAcento] (≥ 9,31 en todo el recorrido).
  static const LinearGradient degradadoAcento = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [acento, exito],
  );

  // ── Mapa ────────────────────────────────────────────────────────────────
  // Se dibujan sobre la imagen del plano, que suele ser clara, así que se
  // anotan contra el fondo y contra un plano blanco. En mapa_widget.dart sólo
  // cambian color y estilo del dibujo (fase 5), nunca la geometría.

  /// Inicio del degradado de la ruta activa. fondo 4,75 · blanco 3,98.
  static const Color mapaRutaInicio = Color(0xFF2979FF);

  /// Fin del degradado de la ruta activa (el acento). blanco 2,03.
  static const Color mapaRutaFin = acento;

  /// Opacidad de la ruta sobre el plano.
  static const double mapaRutaOpacidad = 0.80;

  /// Relleno de zona no transitable. Sólo relleno: sobre el fondo da 2,88,
  /// así que no sirve para texto ni íconos (para eso está [error]).
  static const Color mapaZonaRelleno = Color(0xFFB71C1C);

  /// Borde de zona no transitable. fondo 5,42 · blanco 3,48.
  static const Color mapaZonaBorde = Color(0xFFEF5350);

  /// Guías del asistente de trazo. Magenta saturado: es el convencionalismo
  /// de las herramientas de diseño y contrasta sobre planos claros y sobre el
  /// naranja de los vértices en curso. fondo 5,46 · blanco 3,46.
  static const Color mapaGuia = Color(0xFFFF2D95);

  /// Marcador de beacon (el acento). Sobre un plano blanco da 2,03: el
  /// marcador necesita un contorno oscuro para llegar a 3:1.
  static const Color mapaBeacon = acento;

  /// Marcador de lugar de interés. fondo 6,95 · blanco 2,72: sobre un plano
  /// blanco necesita contorno.
  static const Color mapaLugar = Color(0xFFA78BFA);

  /// Celda y flecha del usuario. fondo 4,75 · blanco 3,98.
  static const Color mapaUsuario = Color(0xFF2979FF);
}
