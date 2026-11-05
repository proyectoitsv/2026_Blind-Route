import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'cuadro_icono.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Tarjeta de dato y grilla de tarjetas
// ═══════════════════════════════════════════════════════════════════════════
//
// Una tarjeta levantada (radio 20). Arriba, el ícono en su cuadro hundido;
// debajo, la etiqueta en texto secundario (9,10 sobre la superficie) con todo
// el ancho, el número grande en texto principal (13,85) con la unidad en
// texto secundario y, abajo, un texto, un minigráfico o un anillo. Tres
// tamaños de letra, no más: 15 (etiqueta y texto de abajo), 40 (el número) y
// 17 (la unidad).
//
// ─── Tocable ───
// La que se toca lleva el borde de 1 px (3,94 sobre la superficie) y una
// flecha gris arriba a la derecha: así se ve qué se puede tocar sin depender
// del color. Se toca entera y, presionada, se hunde y se achica apenas
// (presion.dart).
//
// ─── Letra grande ───
// La grilla pasa a una columna cuando dos tarjetas por fila no entran
// (FormasApp.anchoMinimoTarjetaDato). Si aun así el número no entra en un
// renglón, se achica lo justo para entrar, en vez de partirse a la mitad.
//
// ─── TalkBack ───
// La tarjeta se lee de una vez: "Señal, menos 67 dBm, buena". El número se
// puede decir distinto de como se ve (valorSemantico): "1,2 m" se lee mejor
// como "1,2 metros".

/// Color del texto de abajo de una [TarjetaDato] (y del subtítulo de una
/// TarjetaLista). El verde no está: es sólo de la ruta. Lo bueno se dice con
/// palabras, en gris.
enum TonoDato {
  /// Gris (9,10 sobre la superficie).
  neutro,

  /// Ámbar, algo para mirar (9,59).
  advertencia,

  /// Rojo, algo que anda mal (5,31).
  error,
}

/// Tarjeta con un dato: etiqueta, número grande y, abajo, un texto, un
/// minigráfico o un anillo.
class TarjetaDato extends StatelessWidget {
  const TarjetaDato({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.unidad,
    this.detalle,
    this.tono = TonoDato.neutro,
    this.pie,
    this.descripcionPie,
    this.alTocar,
    this.valorSemantico,
    this.pistaToque,
  });

  /// Ícono del cuadro (Icons.*_rounded). Decorativo.
  final IconData icono;
  final String etiqueta;

  /// El número, ya con su formato ("−67", "1,2").
  final String valor;

  /// Unidad, en gris al lado del número ("dBm", "m", "de 5").
  final String? unidad;

  /// Texto de abajo.
  final String? detalle;

  /// Color del [detalle]. No es lo único que dice el estado: el texto lo
  /// dice con palabras.
  final TonoDato tono;

  /// Lo de abajo del todo: un MiniGrafico o un AnilloProgreso chico.
  final Widget? pie;

  /// Qué dice el [pie], para TalkBack ("Estable en el último minuto").
  final String? descripcionPie;

  /// null: la tarjeta no se toca (y no lleva borde ni flecha).
  final VoidCallback? alTocar;

  /// Cómo se dice el número con su unidad ("1,2 metros"). Por defecto, como
  /// se ve.
  final String? valorSemantico;

  /// Completa el "Presioná dos veces para…" de TalkBack ("ver el detalle").
  final String? pistaToque;

  /// Lo que lee TalkBack, en orden.
  String get textoSemantico => [
    etiqueta,
    valorSemantico ?? [valor, ?unidad].join(' '),
    ?detalle,
    ?descripcionPie,
  ].join(', ');

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final tocable = alTocar != null;
    final colorDetalle = switch (tono) {
      TonoDato.neutro => e.textoSecundario,
      TonoDato.advertencia => e.advertencia,
      TonoDato.error => e.error,
    };

    final contenido = Padding(
      padding: EspaciadoApp.rellenoInternoTarjeta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // El cuadro arriba y la etiqueta debajo, con todo el ancho: al
          // lado del cuadro, en una grilla de dos, una palabra larga
          // ("Calibración") no entraba y se partía.
          Row(
            children: [
              CuadroIcono(icono: icono),
              const Spacer(),
              if (tocable)
                Icon(
                  Icons.chevron_right_rounded,
                  size: FormasApp.icono,
                  color: e.textoSecundario,
                ),
            ],
          ),
          const SizedBox(height: EspaciadoApp.medio),
          Text(
            etiqueta,
            style: TipografiaApp.subtitulo.copyWith(
              color: e.textoSecundario,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: EspaciadoApp.minimo),
          _Numero(valor: valor, unidad: unidad, estilo: e),
          if (detalle != null) ...[
            const SizedBox(height: EspaciadoApp.minimo),
            Text(
              detalle!,
              style: TipografiaApp.subtitulo.copyWith(color: colorDetalle),
            ),
          ],
          if (pie != null) ...[
            const SizedBox(height: EspaciadoApp.medio),
            pie!,
          ],
        ],
      ),
    );

    DecoracionRelieve decoracion(Set<WidgetState> estados) {
      final presionado = estaPresionado(estados);
      return DecoracionRelieve(
        color: presionado ? e.hundido : e.superficie,
        radio: FormasApp.bordeTarjeta,
        elevacion: presionado ? -1 : 1,
        borde: !tocable
            ? BorderSide.none
            : estaEnfocado(estados)
            ? BorderSide(color: e.acento, width: FormasApp.grosorFoco)
            : BorderSide(color: e.borde, width: FormasApp.grosorLinea),
        sombraOscura: e.sombraOscura,
        sombraClara: e.sombraClara,
      );
    }

    final Widget tarjeta = !tocable
        ? DecoratedBox(decoration: decoracion(const {}), child: contenido)
        : ConEstados(
            deshabilitado: false,
            constructor: (context, controlador, estados) {
              final presionado = estaPresionado(estados);
              return EscalaPresion(
                presionado: presionado,
                child: RelieveAnimado(
                  decoracion: decoracion(estados),
                  presionado: presionado,
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
                      child: contenido,
                    ),
                  ),
                ),
              );
            },
          );

    return Semantics(
      container: true,
      button: tocable,
      label: textoSemantico,
      onTap: alTocar,
      onTapHint: tocable ? pistaToque : null,
      excludeSemantics: true,
      child: tarjeta,
    );
  }
}

/// El número y su unidad, sobre la misma línea de base.
class _Numero extends StatelessWidget {
  const _Numero({
    required this.valor,
    required this.unidad,
    required this.estilo,
  });

  final String valor;
  final String? unidad;
  final EstiloApp estilo;

  @override
  Widget build(BuildContext context) {
    // Si el número no entra en el renglón, se achica lo justo (no se parte).
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            valor,
            maxLines: 1,
            softWrap: false,
            style: TipografiaApp.metricaGrande.copyWith(
              color: estilo.textoPrincipal,
            ),
          ),
          if (unidad != null) ...[
            const SizedBox(width: EspaciadoApp.minimo),
            Text(
              unidad!,
              maxLines: 1,
              softWrap: false,
              style: TipografiaApp.destacado.copyWith(
                color: estilo.textoSecundario,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grilla de tarjetas de dato: dos por fila, todas las de una fila del
/// mismo alto. Pasa a una sola columna cuando dos no entran (con letra
/// grande o en un teléfono angosto).
class GrillaTarjetas extends StatelessWidget {
  const GrillaTarjetas({super.key, required this.tarjetas});

  final List<Widget> tarjetas;

  /// Cuántas columnas entran en [ancho] con la letra en [escalaTexto].
  static int columnasPara(double ancho, double escalaTexto) {
    const espacio = EspaciadoApp.entreTarjetas;
    final anchoColumna = (ancho - espacio) / 2;
    return anchoColumna >= FormasApp.anchoMinimoTarjetaDato * escalaTexto
        ? 2
        : 1;
  }

  @override
  Widget build(BuildContext context) {
    final escala = TipografiaApp.escalaTexto(context);
    return LayoutBuilder(
      builder: (context, restricciones) {
        final columnas = columnasPara(restricciones.maxWidth, escala);
        final filas = <Widget>[];
        for (var i = 0; i < tarjetas.length; i += columnas) {
          if (filas.isNotEmpty) {
            filas.add(const SizedBox(height: EspaciadoApp.entreTarjetas));
          }
          if (columnas == 1) {
            filas.add(tarjetas[i]);
            continue;
          }
          filas.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tarjetas[i]),
                  const SizedBox(width: EspaciadoApp.entreTarjetas),
                  Expanded(
                    child: i + 1 < tarjetas.length
                        ? tarjetas[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: filas,
        );
      },
    );
  }
}
