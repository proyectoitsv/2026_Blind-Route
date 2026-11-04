import 'package:flutter/material.dart';

import 'colores.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Colores del tema (ThemeExtension)
// ═══════════════════════════════════════════════════════════════════════════
//
// Los colores de ColoresApp, por rol, colgados del tema. Las pantallas y los
// componentes los leen con EstiloApp.de(context) y no con ColoresApp
// directo: así un tema claro o un acento alternativo (fase 6) es otra
// instancia de esta clase, y ninguna pantalla se toca de nuevo.
//
// ColoresApp queda para lo que no tiene contexto: painters del mapa y valores
// constantes. Los contrastes de cada color están anotados allá.
@immutable
class EstiloApp extends ThemeExtension<EstiloApp> {
  const EstiloApp({
    required this.fondo,
    required this.tarjeta,
    required this.panel,
    required this.superficie,
    required this.separador,
    required this.borde,
    required this.textoPrincipal,
    required this.textoSecundario,
    required this.textoSobreAcento,
    required this.acento,
    required this.acentoSuave,
    required this.exito,
    required this.exitoSuave,
    required this.advertencia,
    required this.advertenciaSuave,
    required this.error,
    required this.degradadoAcento,
  });

  /// El tema oscuro, el principal.
  static const EstiloApp oscuro = EstiloApp(
    fondo: ColoresApp.fondo,
    tarjeta: ColoresApp.tarjeta,
    panel: ColoresApp.panel,
    superficie: ColoresApp.superficie,
    separador: ColoresApp.separador,
    borde: ColoresApp.borde,
    textoPrincipal: ColoresApp.textoPrincipal,
    textoSecundario: ColoresApp.textoSecundario,
    textoSobreAcento: ColoresApp.textoSobreAcento,
    acento: ColoresApp.acento,
    acentoSuave: ColoresApp.acentoSuave,
    exito: ColoresApp.exito,
    exitoSuave: ColoresApp.exitoSuave,
    advertencia: ColoresApp.advertencia,
    advertenciaSuave: ColoresApp.advertenciaSuave,
    error: ColoresApp.error,
    degradadoAcento: ColoresApp.degradadoAcento,
  );

  /// Los colores del tema vigente. Debajo de un tema sin esta extensión (el
  /// de antes, TemaApp.tema, mientras dure la migración) devuelve los
  /// oscuros, así un componente nuevo se ve bien en una pantalla vieja.
  static EstiloApp de(BuildContext context) =>
      Theme.of(context).extension<EstiloApp>() ?? oscuro;

  final Color fondo;
  final Color tarjeta;
  final Color panel;
  final Color superficie;
  final Color separador;
  final Color borde;
  final Color textoPrincipal;
  final Color textoSecundario;
  final Color textoSobreAcento;
  final Color acento;
  final Color acentoSuave;
  final Color exito;
  final Color exitoSuave;
  final Color advertencia;
  final Color advertenciaSuave;
  final Color error;
  final LinearGradient degradadoAcento;

  @override
  EstiloApp copyWith({
    Color? fondo,
    Color? tarjeta,
    Color? panel,
    Color? superficie,
    Color? separador,
    Color? borde,
    Color? textoPrincipal,
    Color? textoSecundario,
    Color? textoSobreAcento,
    Color? acento,
    Color? acentoSuave,
    Color? exito,
    Color? exitoSuave,
    Color? advertencia,
    Color? advertenciaSuave,
    Color? error,
    LinearGradient? degradadoAcento,
  }) {
    return EstiloApp(
      fondo: fondo ?? this.fondo,
      tarjeta: tarjeta ?? this.tarjeta,
      panel: panel ?? this.panel,
      superficie: superficie ?? this.superficie,
      separador: separador ?? this.separador,
      borde: borde ?? this.borde,
      textoPrincipal: textoPrincipal ?? this.textoPrincipal,
      textoSecundario: textoSecundario ?? this.textoSecundario,
      textoSobreAcento: textoSobreAcento ?? this.textoSobreAcento,
      acento: acento ?? this.acento,
      acentoSuave: acentoSuave ?? this.acentoSuave,
      exito: exito ?? this.exito,
      exitoSuave: exitoSuave ?? this.exitoSuave,
      advertencia: advertencia ?? this.advertencia,
      advertenciaSuave: advertenciaSuave ?? this.advertenciaSuave,
      error: error ?? this.error,
      degradadoAcento: degradadoAcento ?? this.degradadoAcento,
    );
  }

  // Interpola al cambiar de tema (por ejemplo, oscuro → claro en la fase 6),
  // como hace Material con sus propios colores.
  @override
  EstiloApp lerp(covariant ThemeExtension<EstiloApp>? other, double t) {
    if (other is! EstiloApp) return this;
    return EstiloApp(
      fondo: Color.lerp(fondo, other.fondo, t)!,
      tarjeta: Color.lerp(tarjeta, other.tarjeta, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      superficie: Color.lerp(superficie, other.superficie, t)!,
      separador: Color.lerp(separador, other.separador, t)!,
      borde: Color.lerp(borde, other.borde, t)!,
      textoPrincipal: Color.lerp(textoPrincipal, other.textoPrincipal, t)!,
      textoSecundario: Color.lerp(textoSecundario, other.textoSecundario, t)!,
      textoSobreAcento: Color.lerp(
        textoSobreAcento,
        other.textoSobreAcento,
        t,
      )!,
      acento: Color.lerp(acento, other.acento, t)!,
      acentoSuave: Color.lerp(acentoSuave, other.acentoSuave, t)!,
      exito: Color.lerp(exito, other.exito, t)!,
      exitoSuave: Color.lerp(exitoSuave, other.exitoSuave, t)!,
      advertencia: Color.lerp(advertencia, other.advertencia, t)!,
      advertenciaSuave: Color.lerp(
        advertenciaSuave,
        other.advertenciaSuave,
        t,
      )!,
      error: Color.lerp(error, other.error, t)!,
      degradadoAcento: LinearGradient.lerp(
        degradadoAcento,
        other.degradadoAcento,
        t,
      )!,
    );
  }
}
