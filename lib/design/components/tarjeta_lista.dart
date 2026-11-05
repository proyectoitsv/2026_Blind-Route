import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../movimiento.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'botones.dart';
import 'cuadro_icono.dart';
import 'presion.dart';
import 'tarjeta_dato.dart' show TonoDato;

// ═══════════════════════════════════════════════════════════════════════════
// Tarjeta de una lista
// ═══════════════════════════════════════════════════════════════════════════
//
// Un elemento de una lista que lleva a otra pantalla (un edificio, un piso):
// una tarjeta levantada (radio 20) con el borde de 1 px de lo que se toca, el
// ícono en su cuadro hundido, el título, un subtítulo y la flecha gris. Se
// toca entera y, presionada, se hunde y se achica apenas (presion.dart), como
// una tarjeta de dato que se toca.
//
// ─── Acciones ───
// Puede llevar botones redondos (probar la navegación, cambiar el número de
// un piso). Van aparte: tocarlos no hunde la tarjeta (la tarjeta está detrás
// y los botones encima, así el toque les llega sólo a ellos) y TalkBack los
// lee después de la tarjeta, cada uno con su nombre. Van a la derecha, antes
// de la flecha, si al texto le queda lugar (140 dp con la letra normal, más
// si el teléfono la agranda); si no, en un renglón debajo del texto,
// alineados con él.
//
// ─── Eliminar ───
// Con alEliminar, el último botón es el tacho, en rojo y aparte de los
// demás (debajo del texto, en la otra punta): "Eliminar Planta baja". Pide
// la confirmación (alEliminar) y, si se confirma, la tarjeta se va. También
// se elimina deslizándola hacia la izquierda: detrás aparece un recuadro
// hundido con el tacho y "Eliminar" en rojo (5,94 sobre lo hundido); soltada
// pasado el 40 % de su ancho, pide la misma confirmación y, si no se
// confirma, vuelve a su lugar. Con TalkBack, además del botón, la tarjeta
// tiene la acción "Eliminar" (en el menú de acciones). Con movimiento
// reducido, al soltarla salta a su lugar (o se va) sin deslizarse, y el
// lugar que deja se cierra de una.
//
// ─── Letra grande ───
// Desde TipografiaApp.esLetraGrande, el título se queda con todo el ancho: el
// cuadro del ícono (decorativo) no se muestra y los botones van siempre
// debajo del texto. Así, con la letra al 200 %, ninguna palabra se parte.
//
// ─── TalkBack ───
// La tarjeta se lee de una vez ("Planta baja, botón"). Si lo que se ve no
// sirve tal cual (el subtítulo "Deslizá para eliminar", con TalkBack, no se
// puede hacer), lleva una etiqueta propia (etiquetaSemantica) y TalkBack dice
// sólo esa.

/// Un elemento de una lista: un edificio, un piso.
class TarjetaLista extends StatelessWidget {
  const TarjetaLista({
    super.key,
    required this.icono,
    required this.titulo,
    required this.alTocar,
    this.subtitulo,
    this.tonoSubtitulo = TonoDato.neutro,
    this.acciones = const <Widget>[],
    this.etiquetaSemantica,
    this.alEliminar,
    this.alEliminada,
    this.etiquetaEliminar = 'Eliminar',
  }) : assert(
         alEliminar == null || key != null,
         'Para eliminarla deslizándola, la tarjeta necesita una clave.',
       );

  /// Ícono del cuadro (Icons.*_rounded). Decorativo.
  final IconData icono;
  final String titulo;

  /// Debajo del título, en [tonoSubtitulo].
  final String? subtitulo;

  /// Gris (9,10 sobre la superficie) o, algo para mirar, ámbar (9,59).
  final TonoDato tonoSubtitulo;

  /// Botones redondos (BotonRedondo), aparte de la tarjeta: a la derecha,
  /// antes de la flecha, o debajo del texto si no entran.
  final List<Widget> acciones;

  /// Lo que hace tocar la tarjeta (en general, abrir otra pantalla).
  final VoidCallback alTocar;

  /// Lo que dice TalkBack en lugar del título y el subtítulo.
  final String? etiquetaSemantica;

  /// Pide confirmar la eliminación y elimina: true si se eliminó. null: la
  /// tarjeta no se elimina (ni lleva el tacho, ni se desliza).
  final Future<bool> Function()? alEliminar;

  /// Después de eliminada: quien la usa la saca de la lista enseguida.
  final VoidCallback? alEliminada;

  /// El nombre de la acción para TalkBack, lo que se lee detrás al
  /// deslizarla y el principio del nombre del tacho ("Eliminar Planta
  /// baja").
  final String etiquetaEliminar;

  /// Al texto, al lado de los botones, le tienen que quedar al menos estos
  /// dp (con la letra normal; crece con la del teléfono). Si no, los botones
  /// bajan.
  static const double _anchoMinimoTexto = 140;

  /// El tacho y la acción de TalkBack: lo mismo que deslizarla y soltarla.
  Future<void> _eliminarSinDeslizar() async {
    if (await alEliminar!()) alEliminada?.call();
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final letraGrande = TipografiaApp.esLetraGrande(context);
    final colorSubtitulo = switch (tonoSubtitulo) {
      TonoDato.neutro => e.textoSecundario,
      TonoDato.advertencia => e.advertencia,
      TonoDato.error => e.error,
    };

    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titulo,
          style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
        ),
        if (subtitulo != null)
          Text(
            subtitulo!,
            style: TipografiaApp.subtitulo.copyWith(color: colorSubtitulo),
          ),
      ],
    );
    final flecha = Icon(
      Icons.chevron_right_rounded,
      size: FormasApp.icono,
      color: e.textoSecundario,
    );

    // Lo que no es una acción deja pasar el toque a la tarjeta, que está
    // detrás, y no se lee aparte: lo dice la tarjeta.
    Widget pasivo(Widget hijo) =>
        IgnorePointer(child: ExcludeSemantics(child: hijo));

    // El tacho, en rojo: el último botón, aparte de los demás.
    final tacho = alEliminar == null
        ? null
        : BotonRedondo(
            icono: Icons.delete_rounded,
            etiqueta: '$etiquetaEliminar $titulo',
            destructivo: true,
            alPresionar: _eliminarSinDeslizar,
          );
    final cantidadBotones = acciones.length + (tacho == null ? 0 : 1);
    final separarTacho = tacho != null && acciones.isNotEmpty;

    // Los botones al lado del texto, si le dejan lugar; si no (o con letra
    // grande), en un renglón debajo.
    final contenido = LayoutBuilder(
      builder: (context, limites) {
        final anchoBotones = cantidadBotones == 0
            ? 0.0
            : EspaciadoApp.minimo +
                  cantidadBotones * FormasApp.areaTactilMinima +
                  (separarTacho ? EspaciadoApp.chico : 0);
        final anchoTexto =
            limites.maxWidth -
            FormasApp.cuadroIcono -
            EspaciadoApp.medio -
            anchoBotones -
            EspaciadoApp.minimo -
            FormasApp.icono;
        final alLado =
            !letraGrande &&
            (cantidadBotones == 0 ||
                anchoTexto >=
                    _anchoMinimoTexto * TipografiaApp.escalaTexto(context));

        final renglonTitulo = Row(
          children: [
            if (!letraGrande) ...[
              pasivo(CuadroIcono(icono: icono)),
              const SizedBox(width: EspaciadoApp.medio),
            ],
            Expanded(child: pasivo(textos)),
            if (alLado && cantidadBotones > 0) ...[
              const SizedBox(width: EspaciadoApp.minimo),
              ...acciones,
              if (separarTacho) const SizedBox(width: EspaciadoApp.chico),
              ?tacho,
            ],
            const SizedBox(width: EspaciadoApp.minimo),
            pasivo(flecha),
          ],
        );
        if (alLado) return renglonTitulo;
        // Debajo: el dibujo de los botones (36 en el medio de 48) alineado
        // con el texto; el tacho, en la otra punta.
        final margen = letraGrande
            ? 0.0
            : FormasApp.cuadroIcono +
                  EspaciadoApp.medio -
                  (FormasApp.areaTactilMinima - FormasApp.botonRedondo) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            renglonTitulo,
            const SizedBox(height: EspaciadoApp.chico),
            Padding(
              padding: EdgeInsetsDirectional.only(start: margen),
              child: Row(children: [...acciones, const Spacer(), ?tacho]),
            ),
          ],
        );
      },
    );

    DecoracionRelieve decoracion(Set<WidgetState> estados) {
      final presionado = estaPresionado(estados);
      return DecoracionRelieve(
        color: presionado ? e.hundido : e.superficie,
        radio: FormasApp.bordeTarjeta,
        elevacion: presionado ? -1 : 1,
        borde: estaEnfocado(estados)
            ? BorderSide(color: e.acento, width: FormasApp.grosorFoco)
            : BorderSide(color: e.borde, width: FormasApp.grosorLinea),
        sombraOscura: e.sombraOscura,
        sombraClara: e.sombraClara,
      );
    }

    final tarjeta = ConEstados(
      deshabilitado: false,
      constructor: (context, controlador, estados) {
        final presionado = estaPresionado(estados);
        return EscalaPresion(
          presionado: presionado,
          child: RelieveAnimado(
            decoracion: decoracion(estados),
            presionado: presionado,
            // La tarjeta (lo que se toca) detrás, del tamaño del contenido;
            // el contenido encima. Un toque en una acción no llega a la
            // tarjeta: no la hunde.
            child: Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    container: true,
                    button: true,
                    label: etiquetaSemantica ?? [titulo, ?subtitulo].join('\n'),
                    onTap: alTocar,
                    customSemanticsActions: alEliminar == null
                        ? null
                        : <CustomSemanticsAction, VoidCallback>{
                            CustomSemanticsAction(label: etiquetaEliminar):
                                _eliminarSinDeslizar,
                          },
                    excludeSemantics: true,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: alTocar,
                        statesController: controlador,
                        customBorder: const RoundedRectangleBorder(
                          borderRadius: FormasApp.bordeTarjeta,
                        ),
                        overlayColor: sinCapa,
                        splashFactory: sinOnda,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EspaciadoApp.rellenoInternoTarjeta,
                  child: contenido,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (alEliminar == null) return tarjeta;
    final reducido = MovimientoApp.reducido(context);
    return Dismissible(
      key: ValueKey<Key>(key!),
      direction: DismissDirection.endToStart,
      movementDuration: reducido
          ? Duration.zero
          : const Duration(milliseconds: 200),
      resizeDuration: reducido ? null : const Duration(milliseconds: 300),
      confirmDismiss: (_) => alEliminar!(),
      onDismissed: (_) => alEliminada?.call(),
      background: _FondoEliminar(texto: etiquetaEliminar),
      child: tarjeta,
    );
  }
}

/// Lo que aparece detrás de la tarjeta al deslizarla: un recuadro hundido
/// con el tacho y [texto] en rojo, a la derecha. Decorativo: con TalkBack
/// está la acción.
class _FondoEliminar extends StatelessWidget {
  const _FondoEliminar({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: DecoracionRelieve(
          color: e.hundido,
          radio: FormasApp.bordeTarjeta,
          elevacion: -1,
          sombraOscura: e.sombraOscura,
          sombraClara: e.sombraClara,
        ),
        child: Padding(
          // Lejos de la sombra interior (llega a 12).
          padding: const EdgeInsets.symmetric(
            horizontal: EspaciadoApp.rellenoTarjeta + EspaciadoApp.chico,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.delete_rounded, size: FormasApp.icono, color: e.error),
              const SizedBox(width: EspaciadoApp.chico),
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  softWrap: false,
                  style: TipografiaApp.boton.copyWith(color: e.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
