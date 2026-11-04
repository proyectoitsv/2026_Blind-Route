import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Tipografía de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Inter (licencia OFL, assets/fonts/Inter/OFL.txt), empaquetada en la app: se
// ve igual sin internet. Se usan los pesos estáticos 400, 500, 600 y 700
// (declarados en pubspec.yaml) y no la versión variable, que en Flutter da
// problemas con los pesos.
//
// ─── Escalado ───
// Los tamaños son lógicos y escalan con el tamaño de letra del teléfono
// (MediaQuery.textScaler). Por eso el interlineado (height) va proporcional
// al tamaño, y quien use estos estilos no tiene que encerrar el texto en
// alturas fijas: con la letra al 200 % se cortaría.
//
// ─── Espaciado entre letras ───
// Inter recomienda cerrarlo en los tamaños grandes. Acá se cierra sólo de 20
// para arriba, un poco menos de lo recomendado, y del cuerpo para abajo queda
// en 0: con baja visión, las letras un poco más sueltas se leen mejor.
//
// ─── Color ───
// Los estilos no llevan color. Lo pone el tema (TemaBlindRoute) o quien los
// usa, con un color de la paleta.
//
// Entre paréntesis, el nombre de cada estilo en la escala del rediseño.
abstract final class TipografiaApp {
  /// Familia declarada en pubspec.yaml.
  static const String familia = 'Inter';

  /// Cifras de ancho fijo: un número que cambia (distancia, RSSI,
  /// porcentaje) no hace bailar el texto de al lado.
  static const List<FontFeature> cifrasTabulares = [
    FontFeature.tabularFigures(),
  ];

  /// El mismo estilo, con cifras de ancho fijo. Para números que cambian
  /// dentro de un texto común.
  static TextStyle conCifrasTabulares(TextStyle estilo) =>
      estilo.copyWith(fontFeatures: cifrasTabulares);

  // ── Letra grande ────────────────────────────────────────────────────────

  /// Desde esta escala (medida en el cuerpo), los componentes se
  /// reacomodan: el valor de una fila baja debajo del título, en vez de
  /// pelearle el ancho. El corte cae entre el 115 % y el 130 % de los
  /// ajustes del teléfono, también con la escala no lineal de Android 14 (el
  /// cuerpo crece algo menos que el porcentaje elegido).
  static const double escalaLetraGrande = 1.2;

  /// Cuánto agranda el teléfono el texto, medido en el cuerpo (17). Desde
  /// Android 14 la escala no es lineal (los tamaños grandes crecen menos),
  /// por eso se mide en un tamaño concreto y no con un factor fijo.
  static double escalaTexto(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(cuerpo.fontSize!) /
      cuerpo.fontSize!;

  /// Si la letra del teléfono está agrandada (ver [escalaLetraGrande]).
  static bool esLetraGrande(BuildContext context) =>
      escalaTexto(context) >= escalaLetraGrande;

  // ── Títulos ─────────────────────────────────────────────────────────────

  /// (largeTitle) 34, bold. Título grande del encabezado de una pantalla.
  static const TextStyle tituloGrande = TextStyle(
    fontFamily: familia,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.7,
  );

  /// (title) 22, semibold. Título de barra, de diálogo y de hoja.
  static const TextStyle titulo = TextStyle(
    fontFamily: familia,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.27,
    letterSpacing: -0.35,
  );

  /// (sectionTitle) 20, semibold. Título de una sección dentro de la
  /// pantalla.
  static const TextStyle tituloSeccion = TextStyle(
    fontFamily: familia,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.3,
  );

  /// (navTitle) 14, semibold. Título centrado de la barra superior, chico
  /// como en un editor: el título grande, si hace falta, va en el contenido.
  static const TextStyle tituloBarra = TextStyle(
    fontFamily: familia,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // ── Texto ───────────────────────────────────────────────────────────────

  /// (headline) 17, semibold. Cuerpo destacado: título de una fila, etiqueta
  /// de un botón.
  static const TextStyle destacado = TextStyle(
    fontFamily: familia,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// (button) 17, medium. Etiqueta de los botones.
  static const TextStyle boton = TextStyle(
    fontFamily: familia,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// (body) 17, regular. Texto de lectura.
  static const TextStyle cuerpo = TextStyle(
    fontFamily: familia,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// (subhead) 15, regular. Segunda línea de una fila, texto de apoyo.
  static const TextStyle subtitulo = TextStyle(
    fontFamily: familia,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  /// (footnote) 13, regular. Aclaraciones al pie, ayuda de un campo.
  static const TextStyle nota = TextStyle(
    fontFamily: familia,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// (caption) 12, medium. Etiquetas chicas: pestañas, unidades, rótulos de
  /// gráficos. Es el tamaño mínimo de la escala.
  static const TextStyle leyenda = TextStyle(
    fontFamily: familia,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  // ── Números ─────────────────────────────────────────────────────────────

  /// (metricLarge) 40, semibold, cifras de ancho fijo. El dato principal de
  /// una tarjeta.
  static const TextStyle metricaGrande = TextStyle(
    fontFamily: familia,
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -0.8,
    fontFeatures: cifrasTabulares,
  );

  /// (metricMedium) 28, semibold, cifras de ancho fijo. Un dato secundario
  /// grande.
  static const TextStyle metricaMediana = TextStyle(
    fontFamily: familia,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.5,
    fontFeatures: cifrasTabulares,
  );

  // ── La escala en los roles de Material 3 ────────────────────────────────
  // Para que los widgets de Material (botones, campos, diálogos, filas)
  // tomen la escala sin configurarlos uno por uno. bodyMedium es el estilo
  // de un Text sin estilo; bodyLarge, el del texto de un campo y del título
  // de un ListTile; labelLarge, el de la etiqueta de los botones.
  static const TextTheme textTheme = TextTheme(
    displayLarge: metricaGrande,
    displayMedium: tituloGrande,
    displaySmall: metricaMediana,
    headlineLarge: tituloGrande,
    headlineMedium: metricaMediana,
    headlineSmall: titulo,
    titleLarge: titulo,
    titleMedium: destacado,
    titleSmall: TextStyle(
      fontFamily: familia,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    bodyLarge: cuerpo,
    bodyMedium: subtitulo,
    bodySmall: nota,
    labelLarge: boton,
    labelMedium: leyenda,
    labelSmall: leyenda,
  );
}
