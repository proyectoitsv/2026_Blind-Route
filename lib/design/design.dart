// ═══════════════════════════════════════════════════════════════════════════
// Sistema de diseño de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Un solo import para pantallas y componentes:
//   import 'design/design.dart';
//
//   colores.dart         ColoresApp: paleta, con el contraste de cada color
//   estilo.dart          EstiloApp: los mismos colores por rol, en el tema
//   relieve.dart         RelieveApp, DecoracionRelieve y pintarRelieve:
//                        levantado y hundido
//   tipografia.dart      TipografiaApp: Inter y la escala de texto
//   formas.dart          FormasApp: radios, altos, área táctil y medidas
//   espaciado.dart       EspaciadoApp: márgenes y separaciones
//   movimiento.dart      MovimientoApp: duraciones, curvas y resorte
//   tema_blindroute.dart TemaBlindRoute.oscuro: el ThemeData
//   components/          los componentes (componentes.dart los lista)
//
// TemaApp (tema_legado.dart), la API de antes, no se exporta acá: lo siguen
// usando por lib/tema.dart las pantallas que todavía no se migraron. La
// galería de componentes (galeria_componentes.dart) tampoco: es sólo para
// debug y la abre lib/main_galeria.dart.
//
// Los componentes importan los archivos de tokens uno por uno, no este
// archivo, para que no haya imports en círculo.
export 'colores.dart';
export 'components/componentes.dart';
export 'espaciado.dart';
export 'estilo.dart';
export 'formas.dart';
export 'movimiento.dart';
export 'relieve.dart';
export 'tema_blindroute.dart';
export 'tipografia.dart';
