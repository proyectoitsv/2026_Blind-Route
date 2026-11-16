import 'package:flutter/painting.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Paleta de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Fuente de verdad de los colores de las dos apps. Ninguna pantalla define
// colores sueltos: usa estos o los mismos desde el tema (EstiloApp.de).
//
// ─── Dirección: editor con relieve (fase 2, v5 del prompt) ───
// Los paneles oscuros de un editor de precisión (orden, plano, línea de
// tiempo, barra flotante) con controles en relieve: lo que se toca se ve
// levantado o hundido. El plano y la ruta van hundidos, como grabados en la
// superficie; los botones y las tarjetas, levantados. El relieve son dos
// sombras (oscura abajo a la derecha, clara arriba a la izquierda) que arma
// relieve.dart con los dos colores de sombra de acá.
//
// Reglas de color:
//   · El cian es el único acento. Un solo botón principal cian por pantalla.
//   · Verde y violeta, sólo para los estados de la ruta (hecho y siguiente).
//     No decoran.
//   · Sin degradados en fondos ni en controles. Sin brillos, halos, vidrio
//     ni sombras de color.
//
// Contraste WCAG 2.x calculado con un script (luminancia relativa sRGB) y
// truncado a dos decimales: nunca se redondea para arriba, así un 4,499 no
// pasa por 4,5 (por eso algunos valores dan una centésima menos que en la
// tabla del prompt, que los redondeaba). Los mínimos que rigen:
//   · texto normal ≥ 4,5:1
//   · texto importante (títulos, números clave) ≥ 7:1
//   · íconos, bordes de controles y gráficos ≥ 3:1
// El relieve solo no llega a 3:1 (la superficie da 1,12 contra el fondo): por
// eso todo control interactivo lleva además el borde de 1 px. Antes de
// cambiar o agregar un color, recalcular el contraste y anotarlo.
abstract final class ColoresApp {
  // ── Fondos ──────────────────────────────────────────────────────────────

  /// Fondo de todas las pantallas: un azul muy oscuro, del lado del logo.
  /// Siempre sólido. Texto principal encima: 17,77.
  static const Color fondo = Color(0xFF0B1020);

  /// Superficie elevada: tarjetas, botones, barras, hojas y diálogos. Va
  /// levantada (con las dos sombras). Texto principal encima: 15,84.
  static const Color superficie = Color(0xFF151C32);

  /// Relleno de lo hundido: el plano, los campos, las pistas (control
  /// segmentado, línea de tiempo, progreso) y el cuadro de los íconos. Es el
  /// color del fondo; lo hunde la sombra interior. Texto principal encima:
  /// 17,77.
  static const Color hundido = fondo;

  // ── Relieve ─────────────────────────────────────────────────────────────
  // Las dos sombras del relieve (relieve.dart). Son decorativas: no llevan
  // contraste mínimo y nunca van debajo de un texto.

  /// Sombra del relieve, abajo a la derecha de lo levantado y arriba a la
  /// izquierda (por dentro) de lo hundido. 1,09 contra el fondo.
  static const Color sombraOscura = Color(0xFF010205);

  /// Luz del relieve, arriba a la izquierda de lo levantado y abajo a la
  /// derecha (por dentro) de lo hundido. 1,19 contra el fondo.
  static const Color sombraClara = Color(0xFF19213B);

  // ── Líneas ──────────────────────────────────────────────────────────────

  /// Divisores entre las filas de un grupo. Decorativo (1,11 sobre la
  /// superficie): no transmite información, así que no necesita 3:1.
  static const Color separador = Color(0xFF1D2541);

  /// Borde de 1 px de todo control interactivo: botones, chips, campos,
  /// pistas, tarjetas que se tocan, barras. Superficie 4,50 · fondo 5,05 ·
  /// corredor del plano 5,30.
  static const Color borde = Color(0xFF7A8594);

  // ── Texto ───────────────────────────────────────────────────────────────

  /// Títulos y texto. Fondo 17,77 · superficie 15,84.
  static const Color textoPrincipal = Color(0xFFF5F8FC);

  /// Subtítulos y datos secundarios. Fondo 11,68 · superficie 10,41: pasa
  /// 7:1 en los dos, también para texto importante.
  static const Color textoSecundario = Color(0xFFC3CCD9);

  /// Texto e íconos sobre un relleno claro (el botón principal, el chip
  /// elegido): acento 11,47 · hecho 13,70 · advertencia 12,56 · error 6,96.
  static const Color textoSobreAcento = Color(0xFF0B0E13);

  // ── Acento (cian) ───────────────────────────────────────────────────────

  /// El único acento: tramo actual, botón principal, cabezal y lo elegido.
  /// Como texto o ícono: fondo 11,23 · superficie 10,01 · corredor del plano
  /// 11,77 · ranura de la ruta 12,46.
  static const Color acento = Color(0xFF29D9FF);

  // ── Ruta ────────────────────────────────────────────────────────────────
  // Sólo para los estados de la ruta, en la línea de ruta y la línea de
  // tiempo. El estado nunca depende sólo del color: el tramo siguiente va
  // punteado, el actual más grueso, y cada tramo lleva su número.

  /// Hecho: el tramo recorrido y el destino. Habitación del plano 12,36 ·
  /// corredor 14,06 · ranura 14,88 · fondo 13,42.
  static const Color hecho = Color(0xFF3DF5B0);

  /// Siguiente: el tramo que falta. Habitación del plano 7,65 · corredor
  /// 8,70 · ranura 9,21 · fondo 8,30.
  static const Color siguiente = Color(0xFFB79CFF);

  // ── Avisos ──────────────────────────────────────────────────────────────

  /// Avisos que no son críticos. Fondo 12,30 · superficie 10,97.
  static const Color advertencia = Color(0xFFFFC857);

  /// Errores y lo destructivo. Fondo 6,82 · superficie 6,08: pasa como texto
  /// en los dos.
  static const Color error = Color(0xFFFF6B6B);

  // ── Plano ───────────────────────────────────────────────────────────────
  // El plano va hundido, como grabado en la superficie. Los muros pasan 3:1
  // sobre los tres fondos que tienen alrededor.

  /// Corredor: el fondo del plano.
  static const Color planoCorredor = Color(0xFF060916);

  /// Habitación: las salas dentro del plano.
  static const Color planoHabitacion = Color(0xFF12192E);

  /// Muros: paredes y contorno del edificio. Corredor 4,55 · habitación
  /// 4,00 · fondo 4,35.
  static const Color planoMuro = Color(0xFF6E7A8C);

  /// Nombres de las salas. Habitación 8,04 · corredor 9,14.
  static const Color planoTexto = Color(0xFFA7B1BF);

  /// Ranura de la ruta: la sombra debajo del trazo, que la hace ver grabada
  /// en el plano.
  static const Color rutaRanura = Color(0xFF000000);

  // ── Capa de foco ────────────────────────────────────────────────────────
  // Los componentes responden al toque con el relieve (levantado → hundido),
  // sin capa ni onda. Los widgets de Material sueltos (los de un diálogo, por
  // ejemplo) toman del tema una capa tenue de acento al presionar o enfocar,
  // que no baja ningún texto del mínimo: sobre la superficie, texto
  // secundario 9,50 · acento 9,13 · error 5,54; sobre el fondo, error 6,31.
  static const double opacidadPresion = 0.05;

  // ── Velo ────────────────────────────────────────────────────────────────

  /// Lo que oscurece la pantalla detrás de una hoja inferior: negro al 54 %,
  /// el de Material. Decorativo, sin contraste mínimo: lo que se lee va en la
  /// hoja.
  static const Color velo = Color(0x8A000000);

  // ── Sobre la imagen del plano ───────────────────────────────────────────
  // El plano de verdad es una imagen que carga el admin y suele ser clara,
  // así que estos se anotan también contra un plano blanco. Los colores
  // claros de la paleta se pierden sobre el blanco (el acento da 1,68): lo
  // que se dibuja encima lleva un contorno oscuro, o un fondo oscuro.

  /// Contorno oscuro de lo que se dibuja sobre el plano: las miras, las
  /// líneas de medición y de zona y los íconos. Blanco 21 · acento 12,46 ·
  /// advertencia 13,65.
  static const Color mapaContorno = rutaRanura;

  /// Grilla sobre el plano: negro al 30 %. Decorativa, sin contraste mínimo.
  static const Color mapaGrilla = Color(0x4D000000);

  /// Relleno de zona no transitable. Sólo relleno, con borde o patrón: sobre
  /// el fondo da 2,88, así que nunca va como texto ni ícono (para eso está
  /// [error]).
  static const Color mapaZonaRelleno = Color(0xFFB71C1C);

  /// Borde de zona no transitable. Fondo 5,43 · blanco 3,48.
  static const Color mapaZonaBorde = Color(0xFFEF5350);

  /// Guías del asistente de trazo. Magenta saturado: es el convencionalismo
  /// de las herramientas de diseño y contrasta sobre planos claros y sobre el
  /// naranja de los vértices en curso. Fondo 5,46 · blanco 3,46.
  static const Color mapaGuia = Color(0xFFFF2D95);
}
