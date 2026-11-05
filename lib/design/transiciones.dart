import 'package:flutter/material.dart';

import 'movimiento.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Transiciones entre pantallas
// ═══════════════════════════════════════════════════════════════════════════
//
// La de la tabla de movimiento: la pantalla nueva entra desde el costado
// (24 dp) con un fundido en 260 ms; al volver, se va igual, al revés, en
// 200 ms. Sin paralaje: la de atrás no se mueve. Con movimiento reducido, un
// fundido de 120 ms en los dos sentidos, sin desplazamiento.
//
//   · TransicionPaginaApp: el PageTransitionsBuilder. Lo usa el tema nuevo
//     (TemaBlindRoute.oscuro), así lo toma cualquier MaterialPageRoute de una
//     app con ese tema, como la galería.
//   · RutaApp: una ruta con esta transición, para abrir pantallas desde las
//     apps, cuyo MaterialApp sigue con el tema de antes (los entrypoints no
//     se tocan). Es la que usan las pantallas migradas.

/// La transición entre pantallas del sistema de diseño.
class TransicionPaginaApp extends PageTransitionsBuilder {
  const TransicionPaginaApp();

  /// Cuánto tarda en entrar. Se fija al abrir la pantalla.
  static Duration get duracionAdelante => MovimientoApp.reducidoSinContexto
      ? MovimientoApp.fundidoReducido
      : MovimientoApp.pantallaAdelante;

  /// Cuánto tarda en irse. Se fija al cerrarla.
  static Duration get duracionAtras => MovimientoApp.reducidoSinContexto
      ? MovimientoApp.fundidoReducido
      : MovimientoApp.pantallaAtras;

  @override
  Duration get transitionDuration => duracionAdelante;

  @override
  Duration get reverseTransitionDuration => duracionAtras;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _TransicionPagina(animacion: animation, child: child);
}

/// Una ruta de pantalla completa con la transición del sistema de diseño:
/// `Navigator.of(context).push(RutaApp<void>(builder: (_) => const X()))`.
class RutaApp<T> extends PageRoute<T> {
  RutaApp({
    required this.builder,
    super.settings,
    super.fullscreenDialog,
    this.maintainState = true,
  });

  final WidgetBuilder builder;

  @override
  final bool maintainState;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => TransicionPaginaApp.duracionAdelante;

  @override
  Duration get reverseTransitionDuration => TransicionPaginaApp.duracionAtras;

  // preserve: con «Quitar animaciones» del teléfono, Flutter acorta al 5 %
  // las animaciones que no piden lo contrario. Ahí la tabla ya pide un
  // fundido corto (120 ms), que se mantiene.
  @override
  AnimationController createAnimationController() => AnimationController(
    duration: transitionDuration,
    reverseDuration: reverseTransitionDuration,
    debugLabel: debugLabel,
    vsync: navigator!,
    animationBehavior: AnimationBehavior.preserve,
  );

  // El controlador se arma una sola vez, al abrir: si mientras tanto cambió
  // «Reducir movimiento», las duraciones se actualizan al empezar cada
  // transición (como hace MaterialPageRoute).
  @override
  TickerFuture didPush() {
    controller?.duration = transitionDuration;
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    controller?.reverseDuration = reverseTransitionDuration;
    return super.didPop(result);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: builder(context),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => const TransicionPaginaApp().buildTransitions<T>(
    this,
    context,
    animation,
    secondaryAnimation,
    child,
  );
}

/// El deslizamiento con fundido. La forma del árbol es la misma con y sin
/// movimiento reducido (cambian los valores, no los widgets): si cambia el
/// ajuste con la pantalla abierta, no pierde su estado.
class _TransicionPagina extends StatefulWidget {
  const _TransicionPagina({required this.animacion, required this.child});

  final Animation<double> animacion;
  final Widget child;

  @override
  State<_TransicionPagina> createState() => _TransicionPaginaState();
}

class _TransicionPaginaState extends State<_TransicionPagina> {
  late CurvedAnimation _curva;

  @override
  void initState() {
    super.initState();
    _curva = _armar();
  }

  CurvedAnimation _armar() => CurvedAnimation(
    parent: widget.animacion,
    curve: MovimientoApp.curva,
    reverseCurve: MovimientoApp.curva.flipped,
  );

  @override
  void didUpdateWidget(covariant _TransicionPagina anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.animacion != widget.animacion) {
      _curva.dispose();
      _curva = _armar();
    }
  }

  @override
  void dispose() {
    _curva.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducido = MovimientoApp.reducido(context);
    final sentido = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    return FadeTransition(
      // Reducido: el fundido parejo, sin curva.
      opacity: reducido ? widget.animacion : _curva,
      child: AnimatedBuilder(
        animation: _curva,
        child: widget.child,
        builder: (context, hijo) => Transform.translate(
          offset: reducido
              ? Offset.zero
              : Offset(
                  (1 - _curva.value) *
                      MovimientoApp.desplazamientoPantalla *
                      sentido,
                  0,
                ),
          child: hijo,
        ),
      ),
    );
  }
}
