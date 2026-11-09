import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Deslizador
// ═══════════════════════════════════════════════════════════════════════════
//
// Para elegir un valor de un rango (el tamaño de la celda, la potencia mínima,
// el ajuste fino de la brújula). Arriba van el nombre y el valor escrito, en
// acento (9,79 sobre el fondo, 8,75 sobre la superficie); debajo, la pista
// hundida (el relieve chico, como la barra de progreso) con el borde de 1 px
// de los controles (4,41 sobre el fondo, 3,94 sobre la superficie), lo
// elegido en acento y la perilla levantada con el anillo de acento, como el
// cabezal de la línea de tiempo. Mientras se arrastra, la perilla se hunde.
// Deshabilitado, lo elegido y el anillo pasan al gris de los bordes.
//
// Por dentro es el Slider de Material con otro dibujo: se arrastra, se toca
// en cualquier punto de la pista y TalkBack lo sube y lo baja igual. Sin el
// globo con el valor (ya está escrito arriba), sin las marcas de los pasos y
// sin el halo de Material. El área que se toca mide 48 de alto y la perilla
// llega justo a los bordes: queda alineada con el nombre.
//
// ─── TalkBack ───
// Dice el nombre y el valor con su unidad ("Tamaño de celda, 0,8 metros") en
// vez del porcentaje de Material, y lo dice también al subirlo o bajarlo.
// Lo escrito arriba no lo repite. La aclaración de abajo, aparte, después.
//
// ─── Letra grande ───
// El valor baja debajo del nombre: así ninguno de los dos se parte.

/// Un deslizador: el nombre, el valor escrito y la pista con la perilla.
class Deslizador extends StatelessWidget {
  const Deslizador({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.min,
    required this.max,
    required this.formato,
    required this.alCambiar,
    this.divisiones,
    this.formatoSemantico,
    this.alTerminar,
    this.ayuda,
  });

  /// El nombre ("Tamaño de celda"). TalkBack lo dice con el valor.
  final String etiqueta;
  final double valor;
  final double min;
  final double max;

  /// Cuántos pasos tiene el rango (null: continuo).
  final int? divisiones;

  /// Cómo se escribe un valor arriba ("0,8 m").
  final String Function(double valor) formato;

  /// Cómo lo dice TalkBack ("0,8 metros"). Por defecto, como se escribe.
  final String Function(double valor)? formatoSemantico;

  /// Cada cambio, mientras se arrastra. null: deshabilitado.
  final ValueChanged<double>? alCambiar;

  /// Al soltarlo.
  final ValueChanged<double>? alTerminar;

  /// Aclaración debajo de la pista, en gris.
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final letraGrande = TipografiaApp.esLetraGrande(context);
    final habilitado = alCambiar != null;
    final nombre = Text(
      etiqueta,
      style: TipografiaApp.destacado.copyWith(
        color: habilitado ? e.textoPrincipal : e.textoSecundario,
      ),
    );
    final valorEscrito = Text(
      formato(valor),
      textAlign: letraGrande ? TextAlign.start : TextAlign.end,
      style: TipografiaApp.conCifrasTabulares(
        TipografiaApp.destacado,
      ).copyWith(color: habilitado ? e.acento : e.textoSecundario),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // TalkBack los dice en el deslizador: acá no los repite.
        ExcludeSemantics(
          child: letraGrande
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [nombre, valorEscrito],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: nombre),
                    const SizedBox(width: EspaciadoApp.chico),
                    valorEscrito,
                  ],
                ),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: FormasApp.altoBarraProgreso,
            trackShape: _PistaDeslizador(estilo: e),
            thumbShape: _PerillaDeslizador(estilo: e),
            overlayShape: const _AreaDeslizador(),
            overlayColor: Colors.transparent,
            tickMarkShape: SliderTickMarkShape.noTickMark,
            showValueIndicator: ShowValueIndicator.never,
            // La pista y la perilla las pintan sus formas con el estilo; con
            // estos colores, Material no pinta nada propio encima.
            activeTrackColor: e.acento,
            inactiveTrackColor: e.hundido,
            thumbColor: e.superficie,
          ),
          child: Slider(
            value: valor.clamp(min, max),
            min: min,
            max: max,
            divisions: divisiones,
            // Sin el globo, el texto de Material sólo lo usa TalkBack.
            label: etiqueta,
            semanticFormatterCallback: formatoSemantico ?? formato,
            onChanged: alCambiar,
            onChangeEnd: alTerminar,
          ),
        ),
        if (ayuda != null)
          Text(
            ayuda!,
            style: TipografiaApp.nota.copyWith(color: e.textoSecundario),
          ),
      ],
    );
  }
}

/// El radio de la perilla: el cabezal de la línea de tiempo (24 dp).
const double _radioPerilla = FormasApp.cabezalTiempo / 2;

/// El área que se toca: tan ancha como la perilla (así la perilla llega a los
/// bordes) y de 48 de alto. No pinta nada: sin el halo de Material.
class _AreaDeslizador extends SliderComponentShape {
  const _AreaDeslizador();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(_radioPerilla * 2, FormasApp.areaTactilMinima);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {}
}

/// La pista: una ranura hundida de todo el ancho, con el borde de los
/// controles, y lo elegido en acento adentro (2 dp de aire), hasta la perilla.
class _PistaDeslizador extends SliderTrackShape with BaseSliderTrackShape {
  const _PistaDeslizador({required this.estilo});

  final EstiloApp estilo;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final recorrido = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    // La ranura va de punta a punta del deslizador (la perilla nunca se sale
    // de ella); lo que recorre la perilla es un poco más corto.
    final ranura = Rect.fromLTRB(
      offset.dx,
      recorrido.top,
      offset.dx + parentBox.size.width,
      recorrido.bottom,
    );
    final canvas = context.canvas;
    final radio = Radius.circular(ranura.height / 2);
    pintarRelieve(
      canvas,
      Path()..addRRect(RRect.fromRectAndRadius(ranura, radio)),
      elevacion: -1,
      tamano: TamanoRelieve.chico,
      relleno: estilo.hundido,
      borde: BorderSide(color: estilo.borde, width: FormasApp.grosorLinea),
      sombraOscura: estilo.sombraOscura,
      sombraClara: estilo.sombraClara,
    );
    final adentro = ranura.deflate(2);
    final elegido = textDirection == TextDirection.rtl
        ? Rect.fromLTRB(
            thumbCenter.dx,
            adentro.top,
            adentro.right,
            adentro.bottom,
          )
        : Rect.fromLTRB(
            adentro.left,
            adentro.top,
            thumbCenter.dx,
            adentro.bottom,
          );
    if (elegido.width <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(elegido, Radius.circular(adentro.height / 2)),
      Paint()
        ..color = Color.lerp(
          estilo.borde,
          estilo.acento,
          enableAnimation.value,
        )!,
    );
  }
}

/// La perilla: un círculo levantado (el relieve chico) en la superficie, con
/// el anillo de acento de 2 px. Presionada (mientras se arrastra), se hunde.
class _PerillaDeslizador extends SliderComponentShape {
  const _PerillaDeslizador({required this.estilo});

  final EstiloApp estilo;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(_radioPerilla * 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final presion = activationAnimation.value;
    pintarRelieve(
      context.canvas,
      Path()..addOval(Rect.fromCircle(center: center, radius: _radioPerilla)),
      // De levantada (1) a hundida (−1), pasando por plana.
      elevacion: lerpDouble(1, -1, presion)!,
      tamano: TamanoRelieve.chico,
      relleno: Color.lerp(estilo.superficie, estilo.hundido, presion),
      borde: BorderSide(
        color: Color.lerp(estilo.borde, estilo.acento, enableAnimation.value)!,
        width: FormasApp.anilloCabezalTiempo,
      ),
      sombraOscura: estilo.sombraOscura,
      sombraClara: estilo.sombraClara,
    );
  }
}
