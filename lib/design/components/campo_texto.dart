import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Campo de texto y buscador
// ═══════════════════════════════════════════════════════════════════════════
//
// Hundido (el relieve común), con el borde de 1 px de los controles (4,41
// sobre el fondo) y el texto de ayuda en texto secundario (10,18 sobre lo
// hundido). Enfocado, el borde pasa a 2 px de acento en 150 ms (con
// movimiento reducido, de golpe).
//
// ─── Etiqueta ───
// Arriba del campo y siempre a la vista (no flota adentro): con baja visión
// se pierde menos, y adentro quedaría bajo la sombra interior. El buscador
// no la muestra (el ícono y la ayuda ya dicen qué es), pero TalkBack la dice
// igual.
//
// ─── Sombras ───
// La sombra interior llega a 12 dp del borde; el texto empieza a 14 o más
// (adentro de un campo de 52 de alto), así nunca queda debajo de una sombra.

/// Campo de texto hundido, con su etiqueta arriba.
class CampoTexto extends StatefulWidget {
  const CampoTexto({
    super.key,
    required this.etiqueta,
    this.ayuda,
    this.icono,
    this.controlador,
    this.focusNode,
    this.mostrarEtiqueta = true,
    this.alCambiar,
    this.alEnviar,
    this.accionTeclado,
    this.tipoTeclado,
    this.capitalizacion = TextCapitalization.none,
    this.autofocus = false,
  });

  /// El buscador: el ícono de la lupa, la ayuda adentro y sin etiqueta a la
  /// vista (TalkBack la dice).
  const CampoTexto.busqueda({
    super.key,
    required this.etiqueta,
    required String this.ayuda,
    this.controlador,
    this.focusNode,
    this.alCambiar,
    this.alEnviar,
    this.autofocus = false,
  }) : icono = Icons.search_rounded,
       mostrarEtiqueta = false,
       accionTeclado = TextInputAction.search,
       tipoTeclado = TextInputType.text,
       capitalizacion = TextCapitalization.none;

  /// El nombre del campo. TalkBack lo dice siempre.
  final String etiqueta;

  /// Texto de ayuda adentro, mientras está vacío ("Buscar un lugar").
  final String? ayuda;

  /// Ícono al principio, decorativo (Icons.*_rounded).
  final IconData? icono;
  final TextEditingController? controlador;
  final FocusNode? focusNode;

  /// Si muestra la [etiqueta] arriba del campo.
  final bool mostrarEtiqueta;
  final ValueChanged<String>? alCambiar;
  final ValueChanged<String>? alEnviar;
  final TextInputAction? accionTeclado;
  final TextInputType? tipoTeclado;
  final TextCapitalization capitalizacion;
  final bool autofocus;

  @override
  State<CampoTexto> createState() => _CampoTextoState();
}

class _CampoTextoState extends State<CampoTexto> {
  FocusNode? _focoPropio;
  FocusNode get _foco => widget.focusNode ?? (_focoPropio ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _foco.addListener(_alCambiarFoco);
  }

  @override
  void didUpdateWidget(covariant CampoTexto anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.focusNode != widget.focusNode) {
      (anterior.focusNode ?? _focoPropio)?.removeListener(_alCambiarFoco);
      _foco.addListener(_alCambiarFoco);
    }
  }

  void _alCambiarFoco() => setState(() {});

  @override
  void dispose() {
    _foco.removeListener(_alCambiarFoco);
    _focoPropio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final enfocado = _foco.hasFocus;
    const sinBorde = InputBorder.none;
    final campo = RelieveAnimado(
      decoracion: DecoracionRelieve(
        color: e.hundido,
        radio: FormasApp.bordeCampo,
        elevacion: -1,
        borde: enfocado
            ? BorderSide(color: e.acento, width: FormasApp.grosorFoco)
            : BorderSide(color: e.borde, width: FormasApp.grosorLinea),
        sombraOscura: e.sombraOscura,
        sombraClara: e.sombraClara,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FormasApp.altoCampo),
        child: Row(
          children: [
            if (widget.icono != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: EspaciadoApp.medio + EspaciadoApp.minimo,
                ),
                child: ExcludeSemantics(
                  child: Icon(
                    widget.icono,
                    size: FormasApp.iconoChico,
                    color: e.textoSecundario,
                  ),
                ),
              ),
            Expanded(
              child: Semantics(
                label: widget.etiqueta,
                child: TextField(
                  controller: widget.controlador,
                  focusNode: _foco,
                  autofocus: widget.autofocus,
                  onChanged: widget.alCambiar,
                  onSubmitted: widget.alEnviar,
                  textInputAction: widget.accionTeclado,
                  keyboardType: widget.tipoTeclado,
                  textCapitalization: widget.capitalizacion,
                  cursorColor: e.acento,
                  style: TipografiaApp.cuerpo.copyWith(color: e.textoPrincipal),
                  // Sin el relleno ni el contorno del tema: los pone el
                  // relieve de alrededor.
                  decoration: InputDecoration(
                    hintText: widget.ayuda,
                    hintStyle: TipografiaApp.cuerpo.copyWith(
                      color: e.textoSecundario,
                    ),
                    filled: false,
                    border: sinBorde,
                    enabledBorder: sinBorde,
                    focusedBorder: sinBorde,
                    disabledBorder: sinBorde,
                    errorBorder: sinBorde,
                    focusedErrorBorder: sinBorde,
                    contentPadding: EdgeInsetsDirectional.only(
                      start: widget.icono == null
                          ? EspaciadoApp.margenLateral
                          : EspaciadoApp.chico,
                      end: EspaciadoApp.margenLateral,
                      top: EspaciadoApp.medio + 2,
                      bottom: EspaciadoApp.medio + 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.mostrarEtiqueta) return campo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // TalkBack ya la dice en el campo: acá no la repite.
        ExcludeSemantics(
          child: Text(
            widget.etiqueta,
            style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
          ),
        ),
        const SizedBox(height: EspaciadoApp.chico),
        campo,
      ],
    );
  }
}
