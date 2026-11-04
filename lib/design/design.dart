// ═══════════════════════════════════════════════════════════════════════════
// Sistema de diseño de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Un solo import para pantallas y componentes:
//   import 'design/design.dart';
//
//   colores.dart         ColoresApp: paleta, con el contraste de cada color
//   estilo.dart          EstiloApp: los mismos colores por rol, en el tema
//   tipografia.dart      TipografiaApp: Inter y la escala de texto
//   formas.dart          FormasApp: radios, altos y área táctil
//   espaciado.dart       EspaciadoApp: márgenes y separaciones
//   movimiento.dart      MovimientoApp: duraciones, curvas y resorte
//   tema_blindroute.dart TemaBlindRoute.oscuro: el ThemeData
//
// TemaApp (tema_legado.dart), la API de antes, no se exporta acá: lo siguen
// usando por lib/tema.dart las pantallas que todavía no se migraron.
export 'colores.dart';
export 'espaciado.dart';
export 'estilo.dart';
export 'formas.dart';
export 'movimiento.dart';
export 'tema_blindroute.dart';
export 'tipografia.dart';
