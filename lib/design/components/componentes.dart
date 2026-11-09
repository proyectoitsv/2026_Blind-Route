// ═══════════════════════════════════════════════════════════════════════════
// Componentes de BlindRoute
// ═══════════════════════════════════════════════════════════════════════════
//
// Widgets reutilizables con el estilo del editor con relieve, todos
// accesibles: área táctil de 48 dp, semántica para TalkBack y nada roto con
// la letra al 200 %. Se mueven según la tabla de movimiento
// (movimiento.dart, fase 3) y, con movimiento reducido («Quitar animaciones»
// del teléfono o «Reducir movimiento» de Ajustes), sin desplazamientos,
// escalas ni resortes. Toman todo de los tokens de lib/design/ y los colores
// de EstiloApp.de(context), así se ven igual bajo cualquier tema.
//
//   aviso.dart               mostrarAviso (un mensaje abajo que se va
//                            solo, en lugar del SnackBar)
//   barras.dart              BarraSuperior (botones redondos, título
//                            centrado), AccionBarra, BarraInferior y
//                            PestanaBarra (píldora de pestañas),
//                            BarraAcciones y AccionPildora (píldora de
//                            acciones)
//   botones.dart             BotonPrincipal (acento plano),
//                            BotonPrincipalGrande (llena el lugar),
//                            BotonSecundario, BotonRedondo, FilaBotones
//                            (lado a lado o apilados)
//   campo_texto.dart         CampoTexto (oculto para una contraseña, con
//                            pistas para autocompletar, deshabilitado,
//                            con el error o una aclaración debajo, una
//                            unidad al final y varios renglones) y
//                            CampoTexto.busqueda (con "Borrar búsqueda")
//   chips.dart               ChipApp (hundido), ChipFiltro
//   confirmacion.dart        mostrarConfirmacion (una hoja con "Cancelar"
//                            y la acción, en lugar del AlertDialog)
//   control_segmentado.dart  ControlSegmentado, OpcionSegmento
//   cuadro_icono.dart        CuadroIcono (ícono en un cuadro hundido)
//   deslizador.dart          Deslizador (un valor de un rango: pista
//                            hundida y perilla levantada, con el valor
//                            escrito y dicho con su unidad)
//   estado_pantalla.dart     EstadoPantalla (vacía, con un error o
//                            esperando)
//   grupo_filas.dart         EncabezadoSeccion, GrupoFilas, FilaGrupo
//   hoja_inferior.dart       mostrarHoja
//   linea_ruta.dart          LineaRuta (la ruta sobre el plano), TramoRuta,
//                            MarcaTramo, EstadoTramo, Recorrido
//   linea_tiempo.dart        LineaTiempo (la ruta como línea de tiempo)
//   movimiento_cabezal.dart  MovimientoCabezal (cómo sigue el cabezal a la
//                            posición; lo usan las dos líneas)
//   panel_relieve.dart       PanelRelieve (levantado o hundido)
//   progreso.dart            AnilloProgreso, BarraProgreso, MiniGrafico
//   tarjeta_dato.dart        TarjetaDato, TonoDato, GrillaTarjetas
//   tarjeta_destino.dart     TarjetaDestino
//   tarjeta_lista.dart       TarjetaLista (un elemento de una lista que
//                            lleva a otra pantalla, con acciones aparte y,
//                            si se elimina, deslizándola o con la acción
//                            «Eliminar» de TalkBack)
//
// presion.dart (el relieve al presionar y su animación, el foco y el
// achique) es interno: lo usan los componentes y no se exporta.
//
// Se ven todos en la galería (lib/design/galeria_componentes.dart), que se
// abre con: flutter run --flavor user -t lib/main_galeria.dart
export 'aviso.dart';
export 'barras.dart';
export 'botones.dart';
export 'campo_texto.dart';
export 'chips.dart';
export 'confirmacion.dart';
export 'control_segmentado.dart';
export 'cuadro_icono.dart';
export 'deslizador.dart';
export 'estado_pantalla.dart';
export 'grupo_filas.dart';
export 'hoja_inferior.dart';
export 'linea_ruta.dart';
export 'linea_tiempo.dart';
export 'movimiento_cabezal.dart';
export 'panel_relieve.dart';
export 'progreso.dart';
export 'tarjeta_dato.dart';
export 'tarjeta_destino.dart';
export 'tarjeta_lista.dart';
