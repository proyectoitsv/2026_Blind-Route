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
//   movimiento.dart      MovimientoApp: la tabla de movimiento (duraciones,
//                        curvas y resorte) y si hay que reducirlo
//   ajustes_movimiento.dart  AjustesMovimiento: «Reducir movimiento» y
//                        «Vibración», guardados en el teléfono
//   ambiente_diseno.dart AmbienteDiseno: el envoltorio de una pantalla
//                        migrada (tema nuevo y movimiento reducido)
//   transiciones.dart    TransicionPaginaApp y RutaApp: entre pantallas
//   haptica.dart         HapticaApp: las vibraciones, con su interruptor
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
export 'ajustes_movimiento.dart';
export 'ambiente_diseno.dart';
export 'colores.dart';
export 'components/componentes.dart';
export 'espaciado.dart';
export 'estilo.dart';
export 'formas.dart';
export 'haptica.dart';
export 'movimiento.dart';
export 'relieve.dart';
export 'tema_blindroute.dart';
export 'tipografia.dart';
export 'transiciones.dart';
