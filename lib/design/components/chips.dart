import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Chips
// ═══════════════════════════════════════════════════════════════════════════
//
//   · ChipApp: un dato o una etiqueta ("Descargado", "Piso 2"). No se toca,
//     así que no va levantado: va hundido (el relieve chico), como grabado,
//     sin borde y con el texto secundario (10,18 sobre lo hundido).
//   · ChipFiltro: se prende y se apaga. Sin elegir, levantado (el relieve
//     chico) con el borde de 1 px y el texto principal (13,85); elegido, en
//     acento con el texto oscuro (11,47) y una tilde, así el estado no
//     depende sólo del color. Presionado, se hunde.
//
// El dibujo mide 36 de alto; el área tocable de un ChipFiltro llega a 48
// (arriba y abajo del dibujo también se toca). Con letra grande, el chip
// crece con el texto.

/// Etiqueta de los chips: el subtítulo (15) en peso medio.
final TextStyle _estiloEtiqueta = TipografiaApp.subtitulo.copyWith(
  fontWeight: FontWeight.w500,
);

/// Relleno del dibujo del chip: el texto queda a 8 dp del borde, lejos de la
/// sombra interior del relieve chico (llega a 6).
const EdgeInsets _relleno = EdgeInsets.symmetric(
  horizontal: EspaciadoApp.medio,
  vertical: EspaciadoApp.chico,
);

/// Chip de dato: hundido, con el texto secundario. No es un control.
class ChipApp extends StatelessWidget {
  const ChipApp({
    super.key,
    required this.texto,
    this.icono,
    this.etiquetaSemantica,
  });

  final String texto;

  /// Ícono antes del texto, decorativo (Icons.*_rounded).
  final IconData? icono;

  /// Lo que dice TalkBack en lugar de [texto].
  final String? etiquetaSemantica;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return DecoratedBox(
      decoration: DecoracionRelieve(
        color: e.hundido,
        pildora: true,
        elevacion: -1,
        tamano: TamanoRelieve.chico,
        sombraOscura: e.sombraOscura,
        sombraClara: e.sombraClara,
      ),
      child: Padding(
        padding: _relleno,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono, size: FormasApp.iconoChico, color: e.textoSecundario),
              const SizedBox(width: EspaciadoApp.minimo),
            ],
            Flexible(
              child: Text(
                texto,
                semanticsLabel: etiquetaSemantica,
                style: _estiloEtiqueta.copyWith(color: e.textoSecundario),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip que se prende y se apaga, para filtrar una lista.
///
/// Con [exclusivo], los chips de un grupo funcionan como opciones de las que
/// se elige una sola (como "Todos" / "Actualizables" / "Descargados"), y
/// TalkBack los anuncia así.
class ChipFiltro extends StatelessWidget {
  const ChipFiltro({
    super.key,
    required this.texto,
    required this.seleccionado,
    required this.alCambiar,
    this.exclusivo = false,
    this.etiquetaSemantica,
  });

  final String texto;
  final bool seleccionado;

  /// null: deshabilitado.
  final ValueChanged<bool>? alCambiar;
  final bool exclusivo;

  /// Lo que dice TalkBack en lugar de [texto].
  final String? etiquetaSemantica;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final habilitado = alCambiar != null;
    return Semantics(
      container: true,
      button: true,
      selected: seleccionado,
      enabled: habilitado,
      inMutuallyExclusiveGroup: exclusivo ? true : null,
      child: ConEstados(
        deshabilitado: !habilitado,
        constructor: (context, controlador, estados) {
          final presionado = estaPresionado(estados);
          final enfocado = estaEnfocado(estados);
          final colorTexto = !habilitado
              ? e.textoSecundario
              : seleccionado
              ? e.textoSobreAcento
              : e.textoPrincipal;
          final BorderSide borde;
          if (!habilitado) {
            borde = BorderSide(
              color: e.separador,
              width: FormasApp.grosorLinea,
            );
          } else if (enfocado) {
            borde = BorderSide(
              color: seleccionado ? e.textoSobreAcento : e.acento,
              width: FormasApp.grosorFoco,
            );
          } else if (seleccionado) {
            borde = BorderSide.none;
          } else {
            borde = BorderSide(color: e.borde, width: FormasApp.grosorLinea);
          }
          final decoracion = DecoracionRelieve(
            color: seleccionado && habilitado
                ? e.acento
                : presionado
                ? e.hundido
                : e.superficie,
            pildora: true,
            elevacion: elevacionControl(estados),
            tamano: TamanoRelieve.chico,
            borde: borde,
            sombraOscura: e.sombraOscura,
            // Sobre el acento, la luz se vería como una mancha oscura.
            sombraClara: seleccionado && presionado ? null : e.sombraClara,
          );
          return Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: habilitado ? () => alCambiar!(!seleccionado) : null,
              statesController: controlador,
              customBorder: FormasApp.formaChip,
              overlayColor: sinCapa,
              splashFactory: sinOnda,
              // El área tocable llega a 48; el dibujo (36) va en el medio.
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: FormasApp.areaTactilMinima,
                  minWidth: FormasApp.areaTactilMinima,
                ),
                child: Center(
                  widthFactor: 1,
                  child: DecoratedBox(
                    decoration: decoracion,
                    child: Padding(
                      padding: _relleno,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (seleccionado) ...[
                            Icon(
                              Icons.check_rounded,
                              size: FormasApp.iconoChico,
                              color: colorTexto,
                            ),
                            const SizedBox(width: EspaciadoApp.minimo),
                          ],
                          Flexible(
                            child: Text(
                              texto,
                              semanticsLabel: etiquetaSemantica,
                              style: _estiloEtiqueta.copyWith(
                                color: colorTexto,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
