// ═══════════════════════════════════════════════════════════════════════════
// Componentes de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Widgets reutilizables con el estilo del editor con relieve, todos
// accesibles: área táctil de 48 dp, semántica para TalkBack, nada roto con
// la letra al 200 % y sin animaciones con "Quitar animaciones". Toman todo de
// los tokens de lib/design/ y los colores de EstiloApp.de(context), así se
// ven igual bajo cualquier tema.
//
//   barras.dart              BarraSuperior (botones redondos, título
//                            centrado), AccionBarra, BarraInferior y
//                            PestanaBarra (píldora de pestañas),
//                            BarraAcciones y AccionPildora (píldora de
//                            acciones)
//   botones.dart             BotonPrincipal (acento plano), BotonSecundario,
//                            BotonRedondo
//   campo_texto.dart         CampoTexto (y CampoTexto.busqueda)
//   chips.dart               ChipApp (hundido), ChipFiltro
//   control_segmentado.dart  ControlSegmentado, OpcionSegmento
//   cuadro_icono.dart        CuadroIcono (ícono en un cuadro hundido)
//   grupo_filas.dart         EncabezadoSeccion, GrupoFilas, FilaGrupo
//   hoja_inferior.dart       mostrarHoja
//   linea_ruta.dart          LineaRuta (la ruta sobre el plano), TramoRuta,
//                            MarcaTramo, EstadoTramo, Recorrido
//   linea_tiempo.dart        LineaTiempo (la ruta como línea de tiempo)
//   panel_relieve.dart       PanelRelieve (levantado o hundido)
//   progreso.dart            AnilloProgreso, BarraProgreso, MiniGrafico
//   tarjeta_dato.dart        TarjetaDato, TonoDato, GrillaTarjetas
//   tarjeta_destino.dart     TarjetaDestino
//
// presion.dart (el relieve al presionar, el foco y el achique de los
// botones) es interno: lo usan los componentes y no se exporta.
//
// Se ven todos en la galería (lib/design/galeria_componentes.dart), que se
// abre con: flutter run --flavor user -t lib/main_galeria.dart
export 'barras.dart';
export 'botones.dart';
export 'campo_texto.dart';
export 'chips.dart';
export 'control_segmentado.dart';
export 'cuadro_icono.dart';
export 'grupo_filas.dart';
export 'hoja_inferior.dart';
export 'linea_ruta.dart';
export 'linea_tiempo.dart';
export 'panel_relieve.dart';
export 'progreso.dart';
export 'tarjeta_dato.dart';
export 'tarjeta_destino.dart';
