import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../movimiento.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Respuesta al toque de los componentes
// ═══════════════════════════════════════════════════════════════════════════
//
// Lo que se toca responde con el relieve: levantado en reposo, hundido
// mientras se presiona, plano si está deshabilitado. Sin la onda (ripple) de
// Material ni su capa: el relieve ya es la respuesta, y una capa encima le
// bajaría el contraste al texto. Los botones además se achican apenas
// (EscalaPresion). El foco con teclado o switch se ve en el borde, que pasa
// al acento con 2 px.
//
// En la fase 2 el paso de levantado a hundido es de golpe: la fase 3 lo anima
// (120 ms al presionar, 160 ms al soltar) interpolando la decoración
// (DecoracionRelieve.lerp).
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
  bool _presionado = false;
  bool _enfocado = false;

  @override
  void initState() {
    super.initState();
    _controlador.addListener(_alCambiar);
  }

  void _alCambiar() {
    final valor = _controlador.value;
    final presionado = valor.contains(WidgetState.pressed);
    final enfocado = valor.contains(WidgetState.focused);
    if (presionado == _presionado && enfocado == _enfocado) return;
    void actualizar() {
      if (!mounted) return;
      setState(() {
        _presionado = presionado;
        _enfocado = enfocado;
      });
    }

    // El control puede avisar mientras se arma (al montarse o al cambiar de
    // habilitado): ahí no se puede volver a armar a quien lo contiene, así
    // que se espera al cuadro siguiente.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => actualizar());
    } else {
      actualizar();
    }
  }

  @override
  void dispose() {
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

/// Achica a [child] (un botón) mientras está [presionado]: a 0,97 en 120 ms.
/// Con movimiento reducido (MovimientoApp.reducido) no escala: queda sólo el
/// cambio de relieve.
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
      duration: MovimientoApp.presion,
      curve: MovimientoApp.curvaPresion,
      child: child,
    );
  }
}
