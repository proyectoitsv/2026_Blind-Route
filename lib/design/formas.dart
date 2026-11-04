import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Formas de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Radios, altos, área táctil y las medidas de los dibujos. El relieve (las
// sombras) está en relieve.dart. Radios, sólo cuatro: 12 (campos, pistas y el
// cuadro de los íconos), 14 (botones), 20 (tarjetas y grupos) y 24 (hojas y
// barras flotantes); los chips, los botones de ícono y los cabezales,
// redondos del todo.
abstract final class FormasApp {
  // ── Radios ──────────────────────────────────────────────────────────────

  /// Tarjetas y grupos de filas.
  static const double radioTarjeta = 20;

  /// Campos, pistas y el cuadro de los íconos.
  static const double radioCampo = 12;

  /// Botón principal y botones secundarios.
  static const double radioBoton = 14;

  /// Esquinas de arriba de las hojas inferiores, los diálogos y las barras
  /// flotantes.
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

  /// Las barras flotantes (la de pestañas y la de acciones): las cuatro
  /// esquinas de radio 24.
  static const BorderRadius bordeBarraFlotante = BorderRadius.all(
    Radius.circular(radioHoja),
  );

  /// Chips: totalmente redondeados.
  static const OutlinedBorder formaChip = StadiumBorder();

  // ── Altos ───────────────────────────────────────────────────────────────

  /// Área táctil mínima de cualquier control: 48 dp
  /// (kMinInteractiveDimension). Si el dibujo es más chico, el área tocable
  /// igual llega a 48.
  static const double areaTactilMinima = kMinInteractiveDimension;

  /// Alto del botón principal y del secundario.
  static const double altoBoton = 52;

  /// Alto mínimo de una fila de un grupo. Es mínimo: con letra grande, la
  /// fila crece con el texto.
  static const double altoFilaMinimo = 52;

  /// Alto mínimo de un campo de texto. Crece con la letra.
  static const double altoCampo = 52;

  /// Botón redondo de las barras (volver, acciones): 36 de dibujo, adentro
  /// de un área tocable de 48.
  static const double botonRedondo = 36;

  /// Manija de las hojas inferiores: una ranura hundida con borde.
  static const Size manijaHoja = Size(40, 6);

  // ── Íconos ──────────────────────────────────────────────────────────────
  // No crecen con la letra (como en Material): crece el texto, que es lo que
  // hay que leer, y los controles mantienen su forma.

  /// Ícono de filas, barras y botones: el tamaño de Material.
  static const double icono = 24;

  /// Ícono chico: chips, botones redondos, opciones del control segmentado,
  /// marcas de la línea de tiempo y adentro del cuadro de un ícono.
  static const double iconoChico = 20;

  /// Cuadro hundido (radio 12) con el ícono chico en acento adentro: el
  /// ícono de una tarjeta de dato, de una fila y de una tarjeta de destino.
  static const double cuadroIcono = 40;

  // ── Líneas y trazos ─────────────────────────────────────────────────────

  /// Separadores entre filas y bordes de los controles.
  static const double grosorLinea = 1;

  /// Borde de un control enfocado (con teclado o switch).
  static const double grosorFoco = 2;

  /// Anillo de progreso con un texto en el centro. Con letra grande crece
  /// junto con el texto, para que siga entrando.
  static const double diametroAnillo = 96;
  static const double grosorAnillo = 10;

  /// Anillo chico, al pie de una tarjeta de dato.
  static const double diametroAnilloChico = 40;
  static const double grosorAnilloChico = 6;

  /// Alto de la barra de progreso: una pista hundida con el avance adentro.
  static const double altoBarraProgreso = 10;

  /// Minigráfico al pie de una tarjeta de dato: alto y grosor de la línea.
  static const double altoMiniGrafico = 36;
  static const double grosorMiniGrafico = 2.5;

  // ── Línea de ruta (sobre el plano) ──────────────────────────────────────

  /// Trazo del tramo actual: el más grueso, así se distingue también sin
  /// ver el color.
  static const double grosorRutaActual = 5;

  /// Trazo de los demás tramos (el recorrido y los que faltan).
  static const double grosorRuta = 3;

  /// Cuánto se asoma la ranura oscura a cada lado del trazo.
  static const double bordeRanura = 2;

  /// Guiones del tramo siguiente: largo del guion y del hueco.
  static const double guionRuta = 6;
  static const double huecoRuta = 5;

  /// Cabezal sobre el plano: un círculo levantado (diámetro total) con un
  /// anillo de acento.
  static const double cabezalRuta = 24;
  static const double anilloCabezalRuta = 3;

  /// Cuadro del destino (y de las escaleras y ascensores) sobre el plano.
  static const double cuadroMarcaRuta = 32;

  // ── Línea de tiempo ─────────────────────────────────────────────────────

  /// Alto de la pista hundida. También es el ancho del lugar de una marca
  /// (escalera, ascensor, destino) adentro de la pista.
  static const double pistaTiempo = 28;

  /// Grosor de un segmento: el actual es más grueso.
  static const double segmentoTiempo = 6;
  static const double segmentoTiempoActual = 10;

  /// Cabezal: un botón redondo levantado con un anillo de acento, adentro
  /// de la pista.
  static const double cabezalTiempo = 24;
  static const double anilloCabezalTiempo = 2;

  /// Ancho mínimo de un tramo con la letra al 100 %: entra su número y, en
  /// el tramo actual, el cabezal con algo de lo recorrido y de lo que falta a
  /// cada lado. Crece con la letra.
  static const double anchoMinimoTramo = 56;

  // ── Barras ──────────────────────────────────────────────────────────────

  /// Alto de la barra superior con la letra al 100 % (el de Material). Con
  /// letra grande crece con el título, que no se recorta.
  static const double altoBarraSuperior = kToolbarHeight;

  /// Alto mínimo de las barras flotantes, sin los márgenes ni el borde del
  /// sistema. Con letra grande crecen con los nombres.
  static const double altoBarraInferior = 64;

  // ── Control segmentado ──────────────────────────────────────────────────

  /// Aire entre la pieza que se desliza y el borde de la opción. La pieza
  /// va adentro de la opción, así el área tocable sigue siendo la opción
  /// entera (48 dp o más). Las sombras de la pieza no pasan de este margen:
  /// no caen sobre el texto de las otras opciones.
  static const double margenPieza = 4;

  // ── Tarjetas de dato ────────────────────────────────────────────────────

  /// Ancho mínimo de una tarjeta de dato en la grilla, con la letra al
  /// 100 %; crece con la letra (TipografiaApp.escalaTexto). Si dos por fila
  /// no entran, la grilla pasa a una columna: en un teléfono de 360 dp,
  /// apenas el cuerpo crece más de un 13 %.
  static const double anchoMinimoTarjetaDato = 140;
}
