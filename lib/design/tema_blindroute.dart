import 'package:flutter/material.dart';

import 'colores.dart';
import 'espaciado.dart';
import 'estilo.dart';
import 'formas.dart';
import 'tipografia.dart';
import 'transiciones.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Tema oscuro de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Material 3 con identidad propia:
//   · Sin Dynamic Color ni Material You: el esquema se arma a mano con la
//     paleta. No sale de fromSeed ni de los colores del teléfono.
//   · Sin el tinte de elevación de Material 3 (surfaceTint transparente) ni
//     sus sombras: el relieve (relieve.dart) lo ponen los componentes. Los
//     widgets de Material sueltos quedan planos, con el borde de 1 px.
//   · Inter en toda la escala (TipografiaApp).
//
// Las pantallas lo toman a medida que se migran (fase 5). Hasta entonces
// siguen con TemaApp.tema, el de antes, que toma los colores de la paleta.
//
// ─── Esquema de colores (roles de Material 3) ───
//   surface                  fondo        fondo de las pantallas
//   surfaceContainerLowest   hundido      lo hundido (campos)
//   surfaceContainerLow …    superficie   tarjetas, barras, menús, hojas y
//   surfaceContainerHigh                  diálogos
//   surfaceContainerHighest  separador    pistas de progreso
//   primary / secondary /    acento       el único acento: el verde y el
//   tertiary                              violeta son sólo de la ruta, y
//                                         así no se cuelan por un widget de
//                                         Material
//   outline                  borde        bordes de controles (≥ 3:1)
//   outlineVariant           separador    divisores, decorativos
//
// ─── Área táctil ───
// materialTapTargetSize.padded lleva a 48 dp el área tocable de los
// controles chicos (chips, casillas, botones de ícono) aunque el dibujo sea
// menor. Los botones grandes miden 52 de alto.
//
// ─── Al presionar ───
// Sin la onda de Material: una capa tenue de acento (ColoresApp.
// opacidadPresion), que no baja ningún texto del mínimo. Los componentes no
// la usan: responden con el relieve.
//
// ─── Entre pantallas ───
// La transición de la tabla de movimiento (TransicionPaginaApp), en todas
// las plataformas: la toma cualquier MaterialPageRoute de una app con este
// tema (la galería). Las apps, que siguen con el tema de antes, abren las
// pantallas migradas con RutaApp.
abstract final class TemaBlindRoute {
  /// El tema oscuro, el principal. Se arma una sola vez.
  static final ThemeData oscuro = _armar(EstiloApp.oscuro);

  static ThemeData _armar(EstiloApp e) {
    final esquema = ColorScheme(
      brightness: Brightness.dark,
      primary: e.acento,
      onPrimary: e.textoSobreAcento,
      primaryContainer: e.superficie,
      onPrimaryContainer: e.acento,
      secondary: e.acento,
      onSecondary: e.textoSobreAcento,
      secondaryContainer: e.superficie,
      onSecondaryContainer: e.textoPrincipal,
      tertiary: e.acento,
      onTertiary: e.textoSobreAcento,
      tertiaryContainer: e.superficie,
      onTertiaryContainer: e.acento,
      error: e.error,
      onError: e.textoSobreAcento,
      surface: e.fondo,
      onSurface: e.textoPrincipal,
      onSurfaceVariant: e.textoSecundario,
      surfaceContainerLowest: e.hundido,
      surfaceContainerLow: e.superficie,
      surfaceContainer: e.superficie,
      surfaceContainerHigh: e.superficie,
      surfaceContainerHighest: e.separador,
      outline: e.borde,
      outlineVariant: e.separador,
      shadow: e.sombraOscura,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    final texto = TipografiaApp.textTheme.apply(
      bodyColor: e.textoPrincipal,
      displayColor: e.textoPrincipal,
    );

    // ── Botones ──
    // FilledButton: el principal (acento plano, texto oscuro). ElevatedButton
    // y FilledButton.tonal: el secundario (superficie con borde y texto
    // principal). OutlinedButton: sólo el borde. TextButton: texto en acento
    // (las acciones de un diálogo). Deshabilitados, el texto sigue legible
    // (9,10 sobre la superficie): con baja visión importa poder leer qué está
    // apagado.
    const formaBoton = RoundedRectangleBorder(
      borderRadius: FormasApp.bordeBoton,
    );
    const tamanoBoton = Size(FormasApp.areaTactilMinima, FormasApp.altoBoton);
    const tamanoBotonChico = Size(
      FormasApp.areaTactilMinima,
      FormasApp.areaTactilMinima,
    );
    const rellenoBoton = EdgeInsets.symmetric(horizontal: 20);
    final bordeControl = BorderSide(color: e.borde);

    OutlineInputBorder contornoCampo(Color color, [double ancho = 1]) =>
        OutlineInputBorder(
          borderRadius: FormasApp.bordeCampo,
          borderSide: BorderSide(color: color, width: ancho),
        );

    bool seleccionado(Set<WidgetState> estados) =>
        estados.contains(WidgetState.selected);

    // Capa al presionar o enfocar (ver ColoresApp.opacidadPresion).
    final capaPresion = e.acento.withValues(alpha: ColoresApp.opacidadPresion);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: esquema,
      fontFamily: TipografiaApp.familia,
      textTheme: texto,
      extensions: <ThemeExtension<dynamic>>[e],
      scaffoldBackgroundColor: e.fondo,
      // Menús desplegables (DropdownButton) y Material sin color propio.
      canvasColor: e.superficie,
      dividerColor: e.separador,
      hintColor: e.textoSecundario,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: IconThemeData(color: e.textoPrincipal),

      // Sin onda (ripple): al presionar queda sólo una capa tenue de acento.
      // La onda es lo más reconocible de Material y la app tiene identidad
      // propia.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: capaPresion,
      hoverColor: capaPresion,
      focusColor: capaPresion,

      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final plataforma in TargetPlatform.values)
            plataforma: const TransicionPaginaApp(),
        },
      ),

      // Como la BarraSuperior: fondo liso y el título chico, centrado.
      appBarTheme: AppBarThemeData(
        backgroundColor: e.fondo,
        foregroundColor: e.textoPrincipal,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TipografiaApp.tituloBarra.copyWith(
          color: e.textoPrincipal,
        ),
        iconTheme: IconThemeData(color: e.textoPrincipal),
        actionsIconTheme: IconThemeData(color: e.textoPrincipal),
      ),

      cardTheme: CardThemeData(
        color: e.superficie,
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
          textStyle: TipografiaApp.boton,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: e.superficie,
          foregroundColor: e.textoPrincipal,
          disabledBackgroundColor: e.superficie,
          disabledForegroundColor: e.textoSecundario,
          elevation: 0,
          side: bordeControl,
          minimumSize: tamanoBoton,
          padding: rellenoBoton,
          shape: formaBoton,
          textStyle: TipografiaApp.boton,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: e.textoPrincipal,
          disabledForegroundColor: e.textoSecundario,
          side: bordeControl,
          minimumSize: tamanoBoton,
          padding: rellenoBoton,
          shape: formaBoton,
          textStyle: TipografiaApp.boton,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: e.acento,
          disabledForegroundColor: e.textoSecundario,
          minimumSize: tamanoBotonChico,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: formaBoton,
          textStyle: TipografiaApp.boton,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: e.acento,
        foregroundColor: e.textoSobreAcento,
        elevation: 0,
        highlightElevation: 0,
      ),

      // Elegido: acento con el texto oscuro (11,47) y la tilde de Material,
      // que marca el estado sin depender del color.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: e.hundido,
          foregroundColor: e.textoPrincipal,
          selectedBackgroundColor: e.acento,
          selectedForegroundColor: e.textoSobreAcento,
          disabledForegroundColor: e.textoSecundario,
          side: bordeControl,
          minimumSize: tamanoBotonChico,
          textStyle: texto.titleSmall,
        ),
      ),

      // Sin elegir: superficie con borde y texto principal (13,85). Elegido:
      // acento con texto oscuro (11,47) y tilde.
      chipTheme: ChipThemeData(
        backgroundColor: e.superficie,
        selectedColor: e.acento,
        disabledColor: e.superficie,
        checkmarkColor: e.textoSobreAcento,
        side: bordeControl,
        shape: FormasApp.formaChip,
        labelStyle: TipografiaApp.subtitulo.copyWith(
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith((estados) {
            if (estados.contains(WidgetState.disabled)) {
              return e.textoSecundario;
            }
            return seleccionado(estados)
                ? e.textoSobreAcento
                : e.textoPrincipal;
          }),
        ),
      ),

      // Hundidos (sin la sombra interior, que la pone CampoTexto) y con el
      // borde de 1 px; enfocados, borde de acento de 2.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: e.hundido,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: contornoCampo(e.borde),
        enabledBorder: contornoCampo(e.borde),
        disabledBorder: contornoCampo(e.separador),
        focusedBorder: contornoCampo(e.acento, FormasApp.grosorFoco),
        errorBorder: contornoCampo(e.error),
        focusedErrorBorder: contornoCampo(e.error, FormasApp.grosorFoco),
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
        iconColor: e.acento,
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
        backgroundColor: e.superficie,
        modalBackgroundColor: e.superficie,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: FormasApp.bordeHoja),
        showDragHandle: true,
        dragHandleColor: e.borde,
        dragHandleSize: FormasApp.manijaHoja,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: e.superficie,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(FormasApp.radioHoja),
          ),
          side: bordeControl,
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
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FormasApp.bordeCampo,
          side: bordeControl,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: e.superficie,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FormasApp.bordeCampo,
          side: bordeControl,
        ),
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
        textStyle: TipografiaApp.nota.copyWith(color: e.textoSobreAcento),
      ),

      // Pestaña activa en acento, las demás en gris (9,10 sobre la
      // superficie).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: e.superficie,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: e.hundido,
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
      // Apagado: pista hundida con borde (4,41 sobre el fondo) y el pulgar
      // gris (10,18). Prendido: pulgar oscuro sobre acento (11,47). La pista
      // del deslizador va en borde para que se vea entero el recorrido.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.disabled)) return null;
          return seleccionado(estados) ? e.textoSobreAcento : e.textoSecundario;
        }),
        trackColor: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.disabled)) return null;
          return seleccionado(estados) ? e.acento : e.hundido;
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
        linearTrackColor: e.hundido,
        circularTrackColor: e.hundido,
      ),
    );
  }
}
