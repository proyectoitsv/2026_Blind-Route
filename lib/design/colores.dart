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
// El relieve solo no llega a 3:1 (la superficie da 1,11 contra el fondo): por
// eso todo control interactivo lleva además el borde de 1 px. Antes de
// cambiar o agregar un color, recalcular el contraste y anotarlo.
abstract final class ColoresApp {
  // ── Fondos ──────────────────────────────────────────────────────────────

  /// Fondo de todas las pantallas. Siempre sólido. Texto principal encima:
  /// 15,50.
  static const Color fondo = Color(0xFF1A1F29);

  /// Superficie elevada: tarjetas, botones, barras, hojas y diálogos. Va
  /// levantada (con las dos sombras). Texto principal encima: 13,85.
  static const Color superficie = Color(0xFF222835);

  /// Relleno de lo hundido: el plano, los campos, las pistas (control
  /// segmentado, línea de tiempo, progreso) y el cuadro de los íconos. Es el
  /// color del fondo; lo hunde la sombra interior. Texto principal encima:
  /// 15,50.
  static const Color hundido = fondo;

  // ── Relieve ─────────────────────────────────────────────────────────────
  // Las dos sombras del relieve (relieve.dart). Son decorativas: no llevan
  // contraste mínimo y nunca van debajo de un texto.

  /// Sombra del relieve, abajo a la derecha de lo levantado y arriba a la
  /// izquierda (por dentro) de lo hundido. 1,09 contra el fondo.
  static const Color sombraOscura = Color(0xFF12161E);

  /// Luz del relieve, arriba a la izquierda de lo levantado y abajo a la
  /// derecha (por dentro) de lo hundido. 1,19 contra el fondo.
  static const Color sombraClara = Color(0xFF262D3B);

  // ── Líneas ──────────────────────────────────────────────────────────────

  /// Divisores entre las filas de un grupo. Decorativo (1,12 sobre la
  /// superficie): no transmite información, así que no necesita 3:1.
  static const Color separador = Color(0xFF2A313C);

  /// Borde de 1 px de todo control interactivo: botones, chips, campos,
  /// pistas, tarjetas que se tocan, barras. Superficie 3,94 · fondo 4,41 ·
  /// corredor del plano 4,61.
  static const Color borde = Color(0xFF7A8594);

  // ── Texto ───────────────────────────────────────────────────────────────

  /// Títulos y texto. Fondo 15,50 · superficie 13,85.
  static const Color textoPrincipal = Color(0xFFF5F8FC);

  /// Subtítulos y datos secundarios. Fondo 10,18 · superficie 9,10: pasa
  /// 7:1 en los dos, también para texto importante.
  static const Color textoSecundario = Color(0xFFC3CCD9);

  /// Texto e íconos sobre un relleno claro (el botón principal, el chip
  /// elegido): acento 11,47 · hecho 13,70 · advertencia 12,56 · error 6,96.
  static const Color textoSobreAcento = Color(0xFF0B0E13);

  // ── Acento (cian) ───────────────────────────────────────────────────────

  /// El único acento: tramo actual, botón principal, cabezal y lo elegido.
  /// Como texto o ícono: fondo 9,79 · superficie 8,75 · corredor del plano
  /// 10,24 · ranura de la ruta 11,14.
  static const Color acento = Color(0xFF29D9FF);

  // ── Ruta ────────────────────────────────────────────────────────────────
  // Sólo para los estados de la ruta, en la línea de ruta y la línea de
  // tiempo. El estado nunca depende sólo del color: el tramo siguiente va
  // punteado, el actual más grueso, y cada tramo lleva su número.

  /// Hecho: el tramo recorrido y el destino. Habitación del plano 10,78 ·
  /// corredor 12,23 · ranura 13,31 · fondo 11,70.
  static const Color hecho = Color(0xFF3DF5B0);

  /// Siguiente: el tramo que falta. Habitación del plano 6,67 · corredor
  /// 7,57 · ranura 8,23 · fondo 7,24.
  static const Color siguiente = Color(0xFFB79CFF);

  // ── Avisos ──────────────────────────────────────────────────────────────

  /// Avisos que no son críticos. Fondo 10,73 · superficie 9,59.
  static const Color advertencia = Color(0xFFFFC857);

  /// Errores y lo destructivo. Fondo 5,94 · superficie 5,31: pasa como texto
  /// en los dos.
  static const Color error = Color(0xFFFF6B6B);

  // ── Plano ───────────────────────────────────────────────────────────────
  // El plano va hundido, como grabado en la superficie. Los muros pasan 3:1
  // sobre los tres fondos que tienen alrededor.

  /// Corredor: el fondo del plano.
  static const Color planoCorredor = Color(0xFF161B24);

  /// Habitación: las salas dentro del plano.
  static const Color planoHabitacion = Color(0xFF1F2631);

  /// Muros: paredes y contorno del edificio. Corredor 3,96 · habitación
  /// 3,49 · fondo 3,79.
  static const Color planoMuro = Color(0xFF6E7A8C);

  /// Nombres de las salas. Habitación 7,01 · corredor 7,96.
  static const Color planoTexto = Color(0xFFA7B1BF);

  /// Ranura de la ruta: la sombra debajo del trazo, que la hace ver grabada
  /// en el plano.
  static const Color rutaRanura = Color(0xFF0E1218);

  // ── Capa de foco ────────────────────────────────────────────────────────
  // Los componentes responden al toque con el relieve (levantado → hundido),
  // sin capa ni onda. Los widgets de Material sueltos (los de un diálogo, por
  // ejemplo) toman del tema una capa tenue de acento al presionar o enfocar,
  // que no baja ningún texto del mínimo: sobre la superficie, texto
  // secundario 8,20 · acento 7,89 · error 4,79; sobre el fondo, error 5,40.
  static const double opacidadPresion = 0.05;

  // ── Mapa de las pantallas sin migrar ────────────────────────────────────
  // Se dibujan sobre la imagen del plano, que suele ser clara, así que se
  // anotan contra el fondo y contra un plano blanco. Los usa mapa_widget.dart
  // hasta la fase 5; ahí cambian color y estilo del dibujo, nunca la
  // geometría.

  /// Trazo de la ruta en el plano (inicio del degradado de la ruta). Fondo
  /// 6,72 · blanco 2,45 (al 80 % de opacidad, 2,03). Sobre un plano blanco no
  /// llega a 3:1: en la fase 5, la ruta lleva la ranura oscura debajo.
  static const Color mapaRutaInicio = Color(0xFF5AA9FF);

  /// Fin del degradado de la ruta activa (el acento). Blanco 1,68.
  static const Color mapaRutaFin = acento;

  /// Opacidad de la ruta sobre el plano.
  static const double mapaRutaOpacidad = 0.80;

  /// Relleno de zona no transitable. Sólo relleno, con borde o patrón: sobre
  /// el fondo da 2,51, así que nunca va como texto ni ícono (para eso está
  /// [error]).
  static const Color mapaZonaRelleno = Color(0xFFB71C1C);

  /// Borde de zona no transitable. Fondo 4,73 · blanco 3,48.
  static const Color mapaZonaBorde = Color(0xFFEF5350);

  /// Guías del asistente de trazo. Magenta saturado: es el convencionalismo
  /// de las herramientas de diseño y contrasta sobre planos claros y sobre el
  /// naranja de los vértices en curso. Fondo 4,76 · blanco 3,46.
  static const Color mapaGuia = Color(0xFFFF2D95);

  /// Marcador de beacon (el acento). Sobre un plano blanco da 1,68: el
  /// marcador necesita un contorno oscuro para llegar a 3:1 (fase 5).
  static const Color mapaBeacon = acento;

  /// Marcador de lugar de interés. Fondo 6,06 · blanco 2,72: sobre un plano
  /// blanco necesita contorno.
  static const Color mapaLugar = Color(0xFFA78BFA);

  /// Celda y flecha del usuario. Fondo 4,14 · blanco 3,98. Más oscura que la
  /// ruta, así la celda del usuario se distingue del primer tramo.
  static const Color mapaUsuario = Color(0xFF2979FF);
}
