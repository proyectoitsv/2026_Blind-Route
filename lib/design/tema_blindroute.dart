import 'package:flutter/material.dart';

import 'espaciado.dart';
import 'estilo.dart';
import 'formas.dart';
import 'tipografia.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Tema oscuro de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Material 3 con identidad propia:
//   · Sin Dynamic Color ni Material You: el esquema se arma a mano con la
//     paleta. No sale de fromSeed ni de los colores del teléfono.
//   · Sin el tinte de elevación de Material 3 (surfaceTint transparente): las
//     tarjetas se separan del fondo por color, sin borde ni sombra.
//   · Inter en toda la escala (TipografiaApp).
//
// Las pantallas lo toman a medida que se migran (fase 5). Hasta entonces
// siguen con TemaApp.tema, el de antes, que no cambió.
//
// ─── Esquema de colores (roles de Material 3) ───
//   surface                  fondo        fondo de las pantallas
//   surfaceContainerLow      tarjeta      Card
//   surfaceContainer         panel        barra de navegación, menús
//   surfaceContainerHigh     superficie
//   surfaceContainerHighest  separador    pistas de interruptor y de progreso
//   secondaryContainer       superficie   botón tonal: relleno gris con texto
//                                         en acento
//   outline                  borde        bordes de controles (≥ 3:1)
//   outlineVariant           separador    divisores, decorativos
//
// ─── Área táctil ───
// materialTapTargetSize.padded lleva a 48 dp el área tocable de los
// controles chicos (chips, casillas, botones de ícono) aunque el dibujo sea
// menor. Los botones grandes miden 52 de alto.
abstract final class TemaBlindRoute {
  /// El tema oscuro, el principal. Se arma una sola vez.
  static final ThemeData oscuro = _armar(EstiloApp.oscuro);

  static ThemeData _armar(EstiloApp e) {
    final esquema = ColorScheme(
      brightness: Brightness.dark,
      primary: e.acento,
      onPrimary: e.textoSobreAcento,
      primaryContainer: e.acentoSuave,
      onPrimaryContainer: e.acento,
      secondary: e.exito,
      onSecondary: e.textoSobreAcento,
      secondaryContainer: e.superficie,
      onSecondaryContainer: e.acento,
      tertiary: e.exito,
      onTertiary: e.textoSobreAcento,
      tertiaryContainer: e.exitoSuave,
      onTertiaryContainer: e.textoPrincipal,
      error: e.error,
      onError: e.textoSobreAcento,
      surface: e.fondo,
      onSurface: e.textoPrincipal,
      onSurfaceVariant: e.textoSecundario,
      surfaceContainerLowest: e.fondo,
      surfaceContainerLow: e.tarjeta,
      surfaceContainer: e.panel,
      surfaceContainerHigh: e.superficie,
      surfaceContainerHighest: e.separador,
      outline: e.borde,
      outlineVariant: e.separador,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    final texto = TipografiaApp.textTheme.apply(
      bodyColor: e.textoPrincipal,
      displayColor: e.textoPrincipal,
    );

    // ── Botones ──
    // FilledButton: el principal sólido (acento), para donde no va el
    // degradado. FilledButton.tonal y ElevatedButton: secundario con relleno
    // gris y texto en acento. OutlinedButton: contorno en borde. TextButton:
    // texto en acento. Deshabilitados, el texto sigue legible (4,94 sobre la
    // superficie): con baja visión importa poder leer qué está apagado.
    const formaBoton = RoundedRectangleBorder(
      borderRadius: FormasApp.bordeBoton,
    );
    const tamanoBoton = Size(FormasApp.areaTactilMinima, FormasApp.altoBoton);
    const tamanoBotonChico = Size(
      FormasApp.areaTactilMinima,
      FormasApp.areaTactilMinima,
    );
    const rellenoBoton = EdgeInsets.symmetric(horizontal: 20);

    OutlineInputBorder contornoCampo(Color color, [double ancho = 1]) =>
        OutlineInputBorder(
          borderRadius: FormasApp.bordeCampo,
          borderSide: BorderSide(color: color, width: ancho),
        );

    bool seleccionado(Set<WidgetState> estados) =>
        estados.contains(WidgetState.selected);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: esquema,
      fontFamily: TipografiaApp.familia,
      textTheme: texto,
      extensions: <ThemeExtension<dynamic>>[e],
      scaffoldBackgroundColor: e.fondo,
      // Menús desplegables (DropdownButton) y Material sin color propio.
      canvasColor: e.panel,
      dividerColor: e.separador,
      hintColor: e.textoSecundario,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: IconThemeData(color: e.textoPrincipal),

      appBarTheme: AppBarThemeData(
        backgroundColor: e.fondo,
        foregroundColor: e.textoPrincipal,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TipografiaApp.titulo.copyWith(color: e.textoPrincipal),
        iconTheme: IconThemeData(color: e.textoPrincipal),
        actionsIconTheme: IconThemeData(color: e.acento),
      ),

      cardTheme: CardThemeData(
        color: e.tarjeta,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: FormasApp.bordeTarjeta,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          disabledBackgroundColor: e.superficie,
          disabledForegroundColor: e.textoSecundario,
          minimumSize: tamanoBoton,
          padding: rellenoBoton,
          shape: formaBoton,
          textStyle: TipografiaApp.destacado,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: e.superficie,
          foregroundColor: e.acento,
          disabledBackgroundColor: e.superficie,
          disabledForegroundColor: e.textoSecundario,
          elevation: 0,
          minimumSize: tamanoBoton,
          padding: rellenoBoton,
          shape: formaBoton,
          textStyle: TipografiaApp.destacado,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: e.acento,
          disabledForegroundColor: e.textoSecundario,
          side: BorderSide(color: e.borde),
          minimumSize: tamanoBoton,
          padding: rellenoBoton,
          shape: formaBoton,
          textStyle: TipografiaApp.destacado,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: e.acento,
          disabledForegroundColor: e.textoSecundario,
          minimumSize: tamanoBotonChico,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: formaBoton,
          textStyle: TipografiaApp.destacado,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: e.acento,
        foregroundColor: e.textoSobreAcento,
      ),

      // Seleccionado: acento sobre acento suave (5,87) y la tilde de
      // Material, que marca el estado sin depender del color.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: e.superficie,
          foregroundColor: e.textoPrincipal,
          selectedBackgroundColor: e.acentoSuave,
          selectedForegroundColor: e.acento,
          disabledForegroundColor: e.textoSecundario,
          side: BorderSide(color: e.borde),
          minimumSize: tamanoBotonChico,
          textStyle: texto.titleSmall,
        ),
      ),

      // Chip común: acento sobre acento suave (5,87). Chip de filtro
      // seleccionado: relleno de acento con texto oscuro (9,31) y tilde.
      chipTheme: ChipThemeData(
        backgroundColor: e.acentoSuave,
        selectedColor: e.acento,
        disabledColor: e.superficie,
        checkmarkColor: e.textoSobreAcento,
        side: BorderSide.none,
        shape: FormasApp.formaChip,
        labelStyle: TipografiaApp.subtitulo.copyWith(
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith((estados) {
            if (estados.contains(WidgetState.disabled)) {
              return e.textoSecundario;
            }
            return seleccionado(estados) ? e.textoSobreAcento : e.acento;
          }),
        ),
      ),

      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: e.superficie,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: contornoCampo(e.borde),
        enabledBorder: contornoCampo(e.borde),
        disabledBorder: contornoCampo(e.separador),
        focusedBorder: contornoCampo(e.acento, 2),
        errorBorder: contornoCampo(e.error),
        focusedErrorBorder: contornoCampo(e.error, 2),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (estados) => TipografiaApp.cuerpo.copyWith(
            color: estados.contains(WidgetState.error)
                ? e.error
                : e.textoSecundario,
          ),
        ),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (estados) => TipografiaApp.cuerpo.copyWith(
            color: estados.contains(WidgetState.error)
                ? e.error
                : estados.contains(WidgetState.focused)
                ? e.acento
                : e.textoSecundario,
          ),
        ),
        hintStyle: TipografiaApp.cuerpo.copyWith(color: e.textoSecundario),
        helperStyle: TipografiaApp.nota.copyWith(color: e.textoSecundario),
        errorStyle: TipografiaApp.nota.copyWith(color: e.error),
        prefixIconColor: e.textoSecundario,
        suffixIconColor: e.textoSecundario,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: e.acento,
        selectionColor: e.acento.withValues(alpha: 0.35),
        selectionHandleColor: e.acento,
      ),

      listTileTheme: ListTileThemeData(
        textColor: e.textoPrincipal,
        titleTextStyle: TipografiaApp.cuerpo.copyWith(color: e.textoPrincipal),
        subtitleTextStyle: TipografiaApp.subtitulo.copyWith(
          color: e.textoSecundario,
        ),
        leadingAndTrailingTextStyle: TipografiaApp.subtitulo.copyWith(
          color: e.textoSecundario,
        ),
        minTileHeight: FormasApp.altoFilaMinimo,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EspaciadoApp.margenLateral,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: e.separador,
        thickness: 1,
        space: 1,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: e.panel,
        modalBackgroundColor: e.panel,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: FormasApp.bordeHoja),
        showDragHandle: true,
        dragHandleColor: e.borde,
        dragHandleSize: FormasApp.manijaHoja,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: e.panel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(FormasApp.radioHoja)),
        ),
        titleTextStyle: TipografiaApp.titulo.copyWith(color: e.textoPrincipal),
        contentTextStyle: TipografiaApp.cuerpo.copyWith(
          color: e.textoPrincipal,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: e.superficie,
        contentTextStyle: TipografiaApp.subtitulo.copyWith(
          color: e.textoPrincipal,
        ),
        actionTextColor: e.acento,
        closeIconColor: e.textoSecundario,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: FormasApp.bordeCampo),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: e.panel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: FormasApp.bordeCampo),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (estados) => TipografiaApp.cuerpo.copyWith(
            color: estados.contains(WidgetState.disabled)
                ? e.textoSecundario
                : e.textoPrincipal,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: e.textoPrincipal,
          borderRadius: FormasApp.bordeCampo,
        ),
        textStyle: TipografiaApp.nota.copyWith(color: e.fondo),
      ),

      // Pestaña activa en acento, las demás en gris (5,26 sobre el panel).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: e.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: e.acentoSuave,
        iconTheme: WidgetStateProperty.resolveWith(
          (estados) => IconThemeData(
            color: seleccionado(estados) ? e.acento : e.textoSecundario,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (estados) => TipografiaApp.leyenda.copyWith(
            color: seleccionado(estados) ? e.acento : e.textoSecundario,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: e.acento,
        unselectedLabelColor: e.textoSecundario,
        indicatorColor: e.acento,
        dividerColor: e.separador,
        labelStyle: texto.titleSmall,
        unselectedLabelStyle: TipografiaApp.subtitulo,
      ),

      // ── Interruptores, deslizadores y progreso ──
      // Apagado, el pulgar gris sobre la pista da 3,97 y el contorno de la
      // pista, 3,31 o más contra cualquier fondo. Prendido, pulgar oscuro
      // sobre acento (9,31). La pista del deslizador va en borde para que se
      // vea entero el recorrido; la de progreso, en separador, para que el
      // avance en acento resalte (6:1 contra la pista).
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.disabled)) return null;
          return seleccionado(estados) ? e.textoSobreAcento : e.textoSecundario;
        }),
        trackColor: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.disabled)) return null;
          return seleccionado(estados) ? e.acento : e.separador;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.disabled)) return null;
          return seleccionado(estados) ? e.acento : e.borde;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: e.acento,
        inactiveTrackColor: e.borde,
        thumbColor: e.acento,
        overlayColor: e.acento.withValues(alpha: 0.12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: e.acento,
        linearTrackColor: e.separador,
      ),
    );
  }
}
