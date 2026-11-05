import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../movimiento.dart';
import '../relieve.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Respuesta al toque de los componentes
// ═══════════════════════════════════════════════════════════════════════════
//
// Lo que se toca responde con el relieve: levantado en reposo, hundido
// mientras se presiona, plano si está deshabilitado. Sin la onda (ripple) de
// Material ni su capa: el relieve ya es la respuesta, y una capa encima le
// bajaría el contraste al texto. Los botones, los chips y las tarjetas que
// se tocan además se achican apenas (EscalaPresion). El foco con teclado o
// switch se ve en el borde, que pasa al acento con 2 px.
//
// ─── Movimiento (fase 3) ───
// El paso de un relieve a otro se anima (RelieveAnimado), según la tabla de
// movimiento: presionar 120 ms, soltar 160 ms, seleccionar o enfocar 150 ms,
// con la curva de salida fuerte. Interrumpido, sigue desde donde está. Con
// movimiento reducido, al presionar cambia sólo la sombra (120 ms, sin
// escala) y al soltar vuelve de golpe.
//
// Un toque corto también se ve: en una lista, el toque se confirma recién al
// levantar el dedo, y el control pasaría de presionado a suelto en el mismo
// cuadro. ConEstados lo deja hundido al menos lo que dura el paso a hundido
// (MovimientoApp.presion) y después lo suelta. El toque en sí (onTap) no se
// demora.
//
// Interno: lo usan los componentes y no se exporta.

/// Fábrica de tinta sin onda.
const InteractiveInkFeatureFactory sinOnda = NoSplash.splashFactory;

/// Sin capa al presionar, enfocar ni pasar el puntero: la respuesta es el
/// relieve y el borde.
const WidgetStateProperty<Color?> sinCapa = WidgetStatePropertyAll(
  Colors.transparent,
);

/// Si el control está presionado (y habilitado).
bool estaPresionado(Set<WidgetState> estados) =>
    estados.contains(WidgetState.pressed) &&
    !estados.contains(WidgetState.disabled);

/// Si el control tiene el foco (y está habilitado).
bool estaEnfocado(Set<WidgetState> estados) =>
    estados.contains(WidgetState.focused) &&
    !estados.contains(WidgetState.disabled);

/// La elevación de un control: levantado (1) en reposo, hundido (−1)
/// presionado y plano (0) deshabilitado.
double elevacionControl(Set<WidgetState> estados) {
  if (estados.contains(WidgetState.disabled)) return 0;
  return estaPresionado(estados) ? -1 : 1;
}

/// Arma un control con un [WidgetStatesController] que se le pasa al widget
/// de Material (un botón, un InkWell) y se vuelve a armar cuando cambia si
/// está presionado o enfocado. [deshabilitado] lo dice quien lo usa (sale de
/// que no haya callback): así no hay que esperar a que el control lo marque.
///
/// Un toque corto se muestra presionado al menos [MovimientoApp.presion]
/// (ver arriba).
class ConEstados extends StatefulWidget {
  const ConEstados({
    super.key,
    required this.deshabilitado,
    required this.constructor,
  });

  final bool deshabilitado;
  final Widget Function(
    BuildContext context,
    WidgetStatesController controlador,
    Set<WidgetState> estados,
  )
  constructor;

  @override
  State<ConEstados> createState() => _ConEstadosState();
}

class _ConEstadosState extends State<ConEstados> {
  final WidgetStatesController _controlador = WidgetStatesController();

  /// Lo último que dijo el control: el dedo está abajo.
  bool _dedoAbajo = false;
  bool _enfocado = false;

  /// Corre desde que se presiona: mientras corre, el hundido no se suelta.
  Timer? _minimo;

  /// Lo que se muestra: presionado mientras el dedo está abajo y, en un
  /// toque corto, hasta cumplir el mínimo.
  bool get _presionado => _dedoAbajo || (_minimo?.isActive ?? false);

  @override
  void initState() {
    super.initState();
    _controlador.addListener(_alCambiar);
  }

  void _alCambiar() {
    final valor = _controlador.value;
    final abajo = valor.contains(WidgetState.pressed);
    final antes = (_presionado, _enfocado);
    if (abajo && !_dedoAbajo) {
      _minimo?.cancel();
      _minimo = Timer(MovimientoApp.presion, _redibujar);
    }
    _dedoAbajo = abajo;
    _enfocado = valor.contains(WidgetState.focused);
    if ((_presionado, _enfocado) != antes) _redibujar();
  }

  void _redibujar() {
    if (!mounted) return;
    // El control puede avisar mientras se arma (al montarse o al cambiar de
    // habilitado): ahí no se puede volver a armar a quien lo contiene, así
    // que se espera al cuadro siguiente.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _minimo?.cancel();
    _controlador
      ..removeListener(_alCambiar)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estados = <WidgetState>{
      if (widget.deshabilitado) WidgetState.disabled,
      if (_presionado && !widget.deshabilitado) WidgetState.pressed,
      if (_enfocado && !widget.deshabilitado) WidgetState.focused,
    };
    return widget.constructor(context, _controlador, estados);
  }
}

/// Una DecoratedBox con relieve que pasa de una [decoracion] a la siguiente
/// animada: al presionar (120 ms), al soltar (160 ms) y en cualquier otro
/// cambio, como seleccionar o enfocar (150 ms), con la curva de salida
/// fuerte (MovimientoApp.duracionRelieve). Interrumpida, sigue desde la
/// decoración que se está viendo. [presionado] dice qué cambio es.
///
/// La elevación interpola pasando por plano (DecoracionRelieve.lerp): las
/// sombras de afuera se acortan y del otro lado aparecen las de adentro.
class RelieveAnimado extends StatefulWidget {
  const RelieveAnimado({
    super.key,
    required this.decoracion,
    this.presionado = false,
    this.child,
  });

  final DecoracionRelieve decoracion;
  final bool presionado;
  final Widget? child;

  @override
  State<RelieveAnimado> createState() => _RelieveAnimadoState();
}

class _RelieveAnimadoState extends State<RelieveAnimado>
    with SingleTickerProviderStateMixin {
  late final AnimationController _avance;
  late final CurvedAnimation _curva;
  late DecoracionRelieve _desde;
  late DecoracionRelieve _hasta;

  @override
  void initState() {
    super.initState();
    // preserve: con «Quitar animaciones» del teléfono, Flutter acorta al 5 %
    // las animaciones que no piden lo contrario; el paso a hundido con
    // movimiento reducido dura 120 ms (sólo la sombra), como dice la tabla.
    _avance = AnimationController(
      vsync: this,
      value: 1,
      animationBehavior: AnimationBehavior.preserve,
    );
    _curva = CurvedAnimation(parent: _avance, curve: MovimientoApp.curva);
    _desde = widget.decoracion;
    _hasta = widget.decoracion;
  }

  /// La decoración que se ve ahora.
  DecoracionRelieve get _actual => _avance.value >= 1
      ? _hasta
      : DecoracionRelieve.lerp(_desde, _hasta, _curva.value)!;

  @override
  void didUpdateWidget(covariant RelieveAnimado anterior) {
    super.didUpdateWidget(anterior);
    if (widget.decoracion == _hasta) return;
    final duracion = MovimientoApp.duracionRelieve(
      context,
      presionadoAntes: anterior.presionado,
      presionado: widget.presionado,
    );
    _desde = _actual;
    _hasta = widget.decoracion;
    if (duracion == Duration.zero) {
      _avance.value = 1;
    } else {
      _avance
        ..duration = duracion
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curva.dispose();
    _avance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _avance,
      child: widget.child,
      builder: (context, hijo) =>
          DecoratedBox(decoration: _actual, child: hijo),
    );
  }
}

/// Achica a [child] (un botón, un chip, una tarjeta) mientras está
/// [presionado]: a 0,97 en 120 ms y de vuelta a 1 en 160 ms. Con movimiento
/// reducido no escala: queda sólo el cambio de relieve.
class EscalaPresion extends StatelessWidget {
  const EscalaPresion({
    super.key,
    required this.presionado,
    required this.child,
  });

  final bool presionado;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final escala = presionado && !MovimientoApp.reducido(context)
        ? MovimientoApp.escalaPresion
        : 1.0;
    return AnimatedScale(
      scale: escala,
      duration: presionado ? MovimientoApp.presion : MovimientoApp.soltar,
      curve: MovimientoApp.curva,
      child: child,
    );
  }
}

/// Un color que cambia en 150 ms, como el texto de un chip al elegirlo. Con
/// movimiento reducido, salta.
class ColorAnimado extends StatelessWidget {
  const ColorAnimado({super.key, required this.color, required this.builder});

  final Color color;
  final Widget Function(BuildContext context, Color color) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: MovimientoApp.duracion(context, MovimientoApp.seleccion),
      curve: MovimientoApp.curva,
      builder: (context, c, _) => builder(context, c ?? color),
    );
  }
}
