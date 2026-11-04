import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../movimiento.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Control segmentado
// ═══════════════════════════════════════════════════════════════════════════
//
// Elegir una entre pocas opciones (2 a 4): una pista hundida, con el borde
// de los controles, y una pieza levantada (el relieve chico) con borde de
// acento que se desliza con resorte hasta la opción elegida. Deshabilitado,
// el borde de la pieza es gris.
//
// ─── Texto ───
// La opción elegida va en texto principal sobre la pieza (13,85) y las demás
// en texto secundario sobre la pista hundida (10,18). Para que el color
// cambie justo donde está la pieza mientras viaja, las opciones se dibujan
// dos veces: en gris sobre la pista y, encima, una copia clara recortada a la
// forma de la pieza, que viaja con ella. La copia no se toca ni la lee
// TalkBack.
//
// ─── Sombras ───
// Las sombras de la pieza no pasan del margen que la separa del borde de su
// opción (FormasApp.margenPieza): nunca caen sobre el texto de las otras. La
// sombra interior de la pista llega a 12 dp del borde y el texto queda más
// adentro.
//
// ─── Letra grande ───
// Si alguna opción no entra en su porción de la fila, las opciones se apilan
// y la pieza se desliza de arriba a abajo: así el texto nunca se corta a la
// mitad de una palabra. Todas miden lo mismo (la más alta) y al menos 48 dp,
// que es el área táctil: la pieza va adentro de la opción, con un margen.
//
// ─── Movimiento ───
// Resorte amortiguado justo, sin rebote (MovimientoApp.resorteControl). Con
// "Quitar animaciones" (MovimientoApp.reducido), la pieza salta.
//
// ─── TalkBack ───
// Cada opción es un botón seleccionado o no, de un grupo en el que se elige
// una sola, como en el SegmentedButton de Material.

/// Una opción de un [ControlSegmentado].
@immutable
class OpcionSegmento<T> {
  const OpcionSegmento({
    required this.valor,
    required this.texto,
    this.icono,
    this.etiquetaSemantica,
  });

  final T valor;
  final String texto;

  /// Ícono antes del texto, decorativo (Icons.*_rounded).
  final IconData? icono;

  /// Lo que dice TalkBack en lugar de [texto].
  final String? etiquetaSemantica;
}

/// Control segmentado: una opción elegida entre pocas.
class ControlSegmentado<T> extends StatefulWidget {
  const ControlSegmentado({
    super.key,
    required this.opciones,
    required this.seleccionada,
    required this.alCambiar,
    this.etiqueta,
  });

  /// 2 o más (lo ideal, hasta 4).
  final List<OpcionSegmento<T>> opciones;

  /// El valor de la opción elegida. El control no cambia solo: avisa con
  /// [alCambiar] y la pieza se mueve cuando llega el valor nuevo.
  final T seleccionada;

  /// null: deshabilitado.
  final ValueChanged<T>? alCambiar;

  /// Nombre del grupo para TalkBack ("Alcance"), si el contexto no lo dice.
  final String? etiqueta;

  @override
  State<ControlSegmentado<T>> createState() => _ControlSegmentadoState<T>();
}

class _ControlSegmentadoState<T> extends State<ControlSegmentado<T>>
    with SingleTickerProviderStateMixin {
  late double _destino = _indice(widget.seleccionada).toDouble();

  /// Posición de la pieza, en opciones (0 = la primera). Sin límites: el
  /// resorte se pasa un poco y vuelve.
  late final AnimationController _pieza = AnimationController.unbounded(
    vsync: this,
    value: _destino,
  );

  int _indice(T valor) {
    final i = widget.opciones.indexWhere((o) => o.valor == valor);
    assert(i >= 0, 'La opción elegida no está entre las opciones.');
    return math.max(i, 0);
  }

  @override
  void didUpdateWidget(covariant ControlSegmentado<T> anterior) {
    super.didUpdateWidget(anterior);
    final destino = _indice(widget.seleccionada).toDouble();
    if (destino == _destino) return;
    _destino = destino;
    if (MovimientoApp.reducido(context)) {
      _pieza.value = destino; // corta cualquier resorte en curso
    } else {
      _pieza.animateWith(
        SpringSimulation(
          MovimientoApp.resorteControl,
          _pieza.value,
          destino,
          _pieza.velocity,
        ),
      );
    }
  }

  @override
  void dispose() {
    _pieza.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.opciones.length >= 2,
      'Un control segmentado tiene 2 opciones o más.',
    );
    final e = EstiloApp.de(context);
    final habilitado = widget.alCambiar != null;
    final elegida = _indice(widget.seleccionada);
    final estilo = TipografiaApp.subtitulo.copyWith(
      fontWeight: FontWeight.w600,
    );

    // El mismo contenido para las dos copias: sólo cambia el color, así las
    // dos se acomodan igual y la de encima calza justo. Márgenes chicos: con
    // tres opciones con ícono, en un teléfono de 360 dp, entran en fila.
    Widget contenido(OpcionSegmento<T> o, Color color) => Padding(
      padding: const EdgeInsets.all(EspaciadoApp.chico),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (o.icono != null) ...[
            Icon(o.icono, size: FormasApp.iconoChico, color: color),
            const SizedBox(width: EspaciadoApp.minimo),
          ],
          Flexible(
            child: Text(
              o.texto,
              textAlign: TextAlign.center,
              semanticsLabel: o.etiquetaSemantica,
              style: estilo.copyWith(color: color),
            ),
          ),
        ],
      ),
    );

    final abajo = <Widget>[
      for (var i = 0; i < widget.opciones.length; i++)
        MergeSemantics(
          child: Semantics(
            button: true,
            selected: i == elegida,
            inMutuallyExclusiveGroup: true,
            enabled: habilitado,
            child: InkWell(
              onTap: habilitado
                  ? () {
                      if (i != elegida) {
                        widget.alCambiar!(widget.opciones[i].valor);
                      }
                    }
                  : null,
              overlayColor: sinCapa,
              splashFactory: sinOnda,
              child: contenido(widget.opciones[i], e.textoSecundario),
            ),
          ),
        ),
    ];
    // La copia de encima, sobre la pieza: texto principal (deshabilitado,
    // secundario, 9,10 sobre la superficie).
    final encima = <Widget>[
      for (final o in widget.opciones)
        contenido(o, habilitado ? e.textoPrincipal : e.textoSecundario),
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.etiqueta,
      child: DecoratedBox(
        decoration: DecoracionRelieve(
          color: e.hundido,
          radio: FormasApp.bordeCampo,
          elevacion: -1,
          borde: BorderSide(color: e.borde, width: FormasApp.grosorLinea),
          sombraOscura: e.sombraOscura,
          sombraClara: e.sombraClara,
        ),
        child: ClipRRect(
          borderRadius: FormasApp.bordeCampo,
          child: Material(
            type: MaterialType.transparency,
            child: _Opciones(
              posicion: _pieza,
              pieza: DecoracionRelieve(
                color: e.superficie,
                radio: BorderRadius.circular(
                  FormasApp.radioCampo - FormasApp.margenPieza,
                ),
                tamano: TamanoRelieve.chico,
                borde: BorderSide(
                  color: habilitado ? e.acento : e.borde,
                  width: FormasApp.grosorLinea,
                ),
                sombraOscura: e.sombraOscura,
                sombraClara: e.sombraClara,
              ),
              margenPieza: FormasApp.margenPieza,
              altoMinimo: FormasApp.areaTactilMinima,
              textDirection: Directionality.of(context),
              children: [...abajo, ...encima],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Acomodo y dibujo de las opciones ───────────────────────────────────────
//
// Los hijos son 2n: primero las n opciones de abajo (las que se tocan y lee
// TalkBack) y después sus n copias oscuras. Todas miden lo mismo: en fila,
// un enésimo del ancho; apiladas, el ancho entero. El alto es el de la más
// alta, y al menos [altoMinimo].

class _Opciones extends MultiChildRenderObjectWidget {
  const _Opciones({
    required this.posicion,
    required this.pieza,
    required this.margenPieza,
    required this.altoMinimo,
    required this.textDirection,
    required super.children,
  });

  final Animation<double> posicion;

  /// Cómo se ve la pieza (su forma se arma en cada cuadro).
  final DecoracionRelieve pieza;
  final double margenPieza;
  final double altoMinimo;
  final TextDirection textDirection;

  @override
  _RenderOpciones createRenderObject(BuildContext context) => _RenderOpciones(
    posicion: posicion,
    pieza: pieza,
    margenPieza: margenPieza,
    altoMinimo: altoMinimo,
    textDirection: textDirection,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderOpciones render) {
    render
      ..posicion = posicion
      ..pieza = pieza
      ..margenPieza = margenPieza
      ..altoMinimo = altoMinimo
      ..textDirection = textDirection;
  }
}

class _DatosOpcion extends ContainerBoxParentData<RenderBox> {}

typedef _Medidas = ({
  Axis eje,
  double anchoOpcion,
  double altoOpcion,
  Size tamano,
});

class _RenderOpciones extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DatosOpcion>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DatosOpcion> {
  _RenderOpciones({
    required Animation<double> posicion,
    required DecoracionRelieve pieza,
    required double margenPieza,
    required double altoMinimo,
    required TextDirection textDirection,
  }) : _posicion = posicion,
       _pieza = pieza,
       _margenPieza = margenPieza,
       _altoMinimo = altoMinimo,
       _textDirection = textDirection;

  Animation<double> _posicion;
  set posicion(Animation<double> valor) {
    if (identical(valor, _posicion)) return;
    if (attached) _posicion.removeListener(markNeedsPaint);
    _posicion = valor;
    if (attached) _posicion.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  DecoracionRelieve _pieza;
  set pieza(DecoracionRelieve valor) {
    if (valor == _pieza) return;
    _pieza = valor;
    markNeedsPaint();
  }

  double _margenPieza;
  set margenPieza(double valor) {
    if (valor == _margenPieza) return;
    _margenPieza = valor;
    markNeedsPaint();
  }

  double _altoMinimo;
  set altoMinimo(double valor) {
    if (valor == _altoMinimo) return;
    _altoMinimo = valor;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection valor) {
    if (valor == _textDirection) return;
    _textDirection = valor;
    markNeedsLayout();
  }

  // Lo que dejó el último acomodo, para dibujar la pieza.
  Axis _eje = Axis.horizontal;
  double _anchoOpcion = 0;
  double _altoOpcion = 0;

  final LayerHandle<ClipRRectLayer> _recorte = LayerHandle<ClipRRectLayer>();

  int get _cantidad => childCount ~/ 2;

  /// Las opciones de abajo (las primeras n).
  List<RenderBox> get _abajo => getChildrenAsList().sublist(0, _cantidad);

  /// Las copias de encima (las últimas n).
  List<RenderBox> get _encima => getChildrenAsList().sublist(_cantidad);

  @override
  bool get isRepaintBoundary => true;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DatosOpcion) child.parentData = _DatosOpcion();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _posicion.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _posicion.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _recorte.layer = null;
    super.dispose();
  }

  // ── Medidas ──

  /// Decide si las opciones van en fila o apiladas y cuánto mide cada una,
  /// sólo con los tamaños intrínsecos (sirve para el acomodo real y para el
  /// "en seco").
  _Medidas _medir(BoxConstraints constraints) {
    final n = _cantidad;
    if (n == 0) {
      return (
        eje: Axis.horizontal,
        anchoOpcion: 0,
        altoOpcion: 0,
        tamano: constraints.smallest,
      );
    }
    final abajo = _abajo;
    // El ancho natural de la más ancha, en un solo renglón.
    final anchoNatural = abajo
        .map((c) => c.getMaxIntrinsicWidth(double.infinity))
        .reduce(math.max);
    final ancho = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.constrainWidth(anchoNatural * n);
    final enFila = anchoNatural <= ancho / n;
    final eje = enFila ? Axis.horizontal : Axis.vertical;
    final anchoOpcion = enFila ? ancho / n : ancho;
    var alto = _altoMinimo;
    for (final c in abajo) {
      alto = math.max(alto, c.getMaxIntrinsicHeight(anchoOpcion));
    }
    final tamano = constraints.constrain(Size(ancho, enFila ? alto : alto * n));
    return (
      eje: eje,
      anchoOpcion: anchoOpcion,
      altoOpcion: alto,
      tamano: tamano,
    );
  }

  /// Dónde va la opción [k] (también su copia).
  Offset _origen(int k) {
    if (_eje == Axis.vertical) return Offset(0, k * _altoOpcion);
    final columna = _textDirection == TextDirection.rtl ? _cantidad - 1 - k : k;
    return Offset(columna * _anchoOpcion, 0);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _medir(constraints).tamano;

  @override
  void performLayout() {
    final medidas = _medir(constraints);
    _eje = medidas.eje;
    _anchoOpcion = medidas.anchoOpcion;
    _altoOpcion = medidas.altoOpcion;
    final ajuste = BoxConstraints.tight(Size(_anchoOpcion, _altoOpcion));
    final n = _cantidad;
    var i = 0;
    for (var c = firstChild; c != null; c = childAfter(c), i++) {
      c.layout(ajuste);
      (c.parentData! as _DatosOpcion).offset = _origen(n == 0 ? 0 : i % n);
    }
    size = medidas.tamano;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    // Apiladas, alcanza con el ancho de la más ancha.
    if (_cantidad == 0) return 0;
    return _abajo.map((c) => c.getMinIntrinsicWidth(height)).reduce(math.max);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    // En fila, todas del ancho de la más ancha.
    if (_cantidad == 0) return 0;
    return _cantidad *
        _abajo.map((c) => c.getMaxIntrinsicWidth(height)).reduce(math.max);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _medir(BoxConstraints(maxWidth: width)).tamano.height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _medir(BoxConstraints(maxWidth: width)).tamano.height;

  // ── Dibujo ──

  /// La pieza, en coordenadas propias: la opción a la que llegó el resorte,
  /// achicada por el margen. Si el resorte se pasa, queda contra el borde.
  Rect _rectPieza() {
    final n = _cantidad;
    final p = _posicion.value.clamp(0.0, n - 1.0);
    final Rect opcion;
    if (_eje == Axis.vertical) {
      opcion = Rect.fromLTWH(0, p * _altoOpcion, _anchoOpcion, _altoOpcion);
    } else {
      final columna = _textDirection == TextDirection.rtl ? n - 1 - p : p;
      opcion = Rect.fromLTWH(
        columna * _anchoOpcion,
        0,
        _anchoOpcion,
        _altoOpcion,
      );
    }
    return opcion.deflate(_margenPieza);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_cantidad == 0) return;
    for (final c in _abajo) {
      context.paintChild(c, (c.parentData! as _DatosOpcion).offset + offset);
    }
    final pieza = _rectPieza();
    final forma = _pieza.formaEn(pieza, _textDirection);
    // La pieza con su relieve. Las sombras no pasan del margen: no caen
    // sobre el texto de las otras opciones.
    final canvas = context.canvas
      ..save()
      ..clipRect(pieza.inflate(_margenPieza).shift(offset));
    pintarRelieve(
      canvas,
      Path()..addRRect(forma.shift(offset)),
      elevacion: _pieza.elevacion,
      tamano: _pieza.tamano,
      relleno: _pieza.color,
      borde: _pieza.borde,
      sombraOscura: _pieza.sombraOscura,
      sombraClara: _pieza.sombraClara,
    );
    canvas.restore();
    _recorte.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      pieza,
      forma,
      (contexto, desplazamiento) {
        for (final c in _encima) {
          contexto.paintChild(
            c,
            (c.parentData! as _DatosOpcion).offset + desplazamiento,
          );
        }
      },
      oldLayer: _recorte.layer,
    );
  }

  // ── Toques y TalkBack: sólo las opciones de abajo ──

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final c in _abajo.reversed) {
      final datos = c.parentData! as _DatosOpcion;
      final tocado = result.addWithPaintOffset(
        offset: datos.offset,
        position: position,
        hitTest: (resultado, posicion) =>
            c.hitTest(resultado, position: posicion),
      );
      if (tocado) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    _abajo.forEach(visitor);
  }
}
