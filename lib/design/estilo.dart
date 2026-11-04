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
    required this.superficie,
    required this.hundido,
    required this.sombraOscura,
    required this.sombraClara,
    required this.separador,
    required this.borde,
    required this.textoPrincipal,
    required this.textoSecundario,
    required this.textoSobreAcento,
    required this.acento,
    required this.hecho,
    required this.siguiente,
    required this.advertencia,
    required this.error,
    required this.planoCorredor,
    required this.planoHabitacion,
    required this.planoMuro,
    required this.planoTexto,
    required this.rutaRanura,
  });

  /// El tema oscuro, el principal.
  static const EstiloApp oscuro = EstiloApp(
    fondo: ColoresApp.fondo,
    superficie: ColoresApp.superficie,
    hundido: ColoresApp.hundido,
    sombraOscura: ColoresApp.sombraOscura,
    sombraClara: ColoresApp.sombraClara,
    separador: ColoresApp.separador,
    borde: ColoresApp.borde,
    textoPrincipal: ColoresApp.textoPrincipal,
    textoSecundario: ColoresApp.textoSecundario,
    textoSobreAcento: ColoresApp.textoSobreAcento,
    acento: ColoresApp.acento,
    hecho: ColoresApp.hecho,
    siguiente: ColoresApp.siguiente,
    advertencia: ColoresApp.advertencia,
    error: ColoresApp.error,
    planoCorredor: ColoresApp.planoCorredor,
    planoHabitacion: ColoresApp.planoHabitacion,
    planoMuro: ColoresApp.planoMuro,
    planoTexto: ColoresApp.planoTexto,
    rutaRanura: ColoresApp.rutaRanura,
  );

  /// Los colores del tema vigente. Debajo de un tema sin esta extensión (el
  /// de antes, TemaApp.tema, mientras dure la migración) devuelve los
  /// oscuros, así un componente nuevo se ve bien en una pantalla vieja.
  static EstiloApp de(BuildContext context) =>
      Theme.of(context).extension<EstiloApp>() ?? oscuro;

  final Color fondo;

  /// Superficie elevada: tarjetas, botones, barras y hojas.
  final Color superficie;

  /// Relleno de lo hundido: plano, campos, pistas y cuadros de ícono.
  final Color hundido;

  /// Las dos sombras del relieve.
  final Color sombraOscura;
  final Color sombraClara;
  final Color separador;

  /// Borde de 1 px de todo control interactivo.
  final Color borde;
  final Color textoPrincipal;
  final Color textoSecundario;
  final Color textoSobreAcento;
  final Color acento;

  /// Tramo recorrido y destino (sólo en la ruta).
  final Color hecho;

  /// Tramo que falta (sólo en la ruta).
  final Color siguiente;
  final Color advertencia;
  final Color error;

  /// Colores del plano.
  final Color planoCorredor;
  final Color planoHabitacion;
  final Color planoMuro;
  final Color planoTexto;

  /// Sombra debajo del trazo de la ruta.
  final Color rutaRanura;

  @override
  EstiloApp copyWith({
    Color? fondo,
    Color? superficie,
    Color? hundido,
    Color? sombraOscura,
    Color? sombraClara,
    Color? separador,
    Color? borde,
    Color? textoPrincipal,
    Color? textoSecundario,
    Color? textoSobreAcento,
    Color? acento,
    Color? hecho,
    Color? siguiente,
    Color? advertencia,
    Color? error,
    Color? planoCorredor,
    Color? planoHabitacion,
    Color? planoMuro,
    Color? planoTexto,
    Color? rutaRanura,
  }) {
    return EstiloApp(
      fondo: fondo ?? this.fondo,
      superficie: superficie ?? this.superficie,
      hundido: hundido ?? this.hundido,
      sombraOscura: sombraOscura ?? this.sombraOscura,
      sombraClara: sombraClara ?? this.sombraClara,
      separador: separador ?? this.separador,
      borde: borde ?? this.borde,
      textoPrincipal: textoPrincipal ?? this.textoPrincipal,
      textoSecundario: textoSecundario ?? this.textoSecundario,
      textoSobreAcento: textoSobreAcento ?? this.textoSobreAcento,
      acento: acento ?? this.acento,
      hecho: hecho ?? this.hecho,
      siguiente: siguiente ?? this.siguiente,
      advertencia: advertencia ?? this.advertencia,
      error: error ?? this.error,
      planoCorredor: planoCorredor ?? this.planoCorredor,
      planoHabitacion: planoHabitacion ?? this.planoHabitacion,
      planoMuro: planoMuro ?? this.planoMuro,
      planoTexto: planoTexto ?? this.planoTexto,
      rutaRanura: rutaRanura ?? this.rutaRanura,
    );
  }

  // Interpola al cambiar de tema (por ejemplo, oscuro → claro en la fase 6),
  // como hace Material con sus propios colores.
  @override
  EstiloApp lerp(covariant ThemeExtension<EstiloApp>? other, double t) {
    if (other is! EstiloApp) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EstiloApp(
      fondo: l(fondo, other.fondo),
      superficie: l(superficie, other.superficie),
      hundido: l(hundido, other.hundido),
      sombraOscura: l(sombraOscura, other.sombraOscura),
      sombraClara: l(sombraClara, other.sombraClara),
      separador: l(separador, other.separador),
      borde: l(borde, other.borde),
      textoPrincipal: l(textoPrincipal, other.textoPrincipal),
      textoSecundario: l(textoSecundario, other.textoSecundario),
      textoSobreAcento: l(textoSobreAcento, other.textoSobreAcento),
      acento: l(acento, other.acento),
      hecho: l(hecho, other.hecho),
      siguiente: l(siguiente, other.siguiente),
      advertencia: l(advertencia, other.advertencia),
      error: l(error, other.error),
      planoCorredor: l(planoCorredor, other.planoCorredor),
      planoHabitacion: l(planoHabitacion, other.planoHabitacion),
      planoMuro: l(planoMuro, other.planoMuro),
      planoTexto: l(planoTexto, other.planoTexto),
      rutaRanura: l(rutaRanura, other.rutaRanura),
    );
  }
}
