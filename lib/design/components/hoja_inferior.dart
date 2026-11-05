import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ambiente_diseno.dart';
import '../colores.dart';
import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../movimiento.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'botones.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Hoja inferior
// ═══════════════════════════════════════════════════════════════════════════
//
// Para cargas rápidas (un nombre, una opción) sin cambiar de pantalla: una
// superficie levantada, con las esquinas de arriba de radio 24, la manija
// hundida (con borde, 3,94 sobre la superficie), un título y el botón
// redondo para cerrar.
//
// ─── Movimiento ───
// Sube desde abajo en 300 ms y baja en 200 ms, con
// cubic-bezier(0.32, 0.72, 0, 1) (también al bajar: arranca rápido), y el
// fondo se oscurece. Con movimiento reducido, aparece y se va con un fundido
// de 120 ms, sin moverse. Se cierra también arrastrándola hacia abajo: si no
// llega a la mitad (ni se la tira rápido), vuelve a su lugar en 160 ms.
//
// Es una ruta propia (_RutaHoja) y no showModalBottomSheet: la hoja de
// Material siempre sube con su curva, no se puede llevar a un fundido y, para
// TalkBack, se anuncia como "Dialog", en inglés. Esta se anuncia con su
// título.
//
// ─── Tema ───
// Va siempre envuelta en AmbienteDiseno: tiene el tema nuevo aunque se abra
// desde una pantalla vieja (o desde un contexto por encima del Theme de la
// pantalla).
//
// ─── TalkBack ───
// La manija es decorativa. Para cerrar están el botón "Cerrar", el gesto de
// volver y tocar afuera, que TalkBack también anuncia como "Cerrar". El
// título es un encabezado.
//
// ─── Letra grande y teclado ───
// Si el contenido no entra, se desplaza. Con el teclado abierto, la hoja
// sube para que el campo quede a la vista. En una tablet no pasa de 640 dp
// de ancho.

/// Abre una hoja inferior con [titulo] y lo que arme [contenido]. Devuelve
/// lo que se le pase a Navigator.pop al cerrarla.
Future<T?> mostrarHoja<T>(
  BuildContext context, {
  required String titulo,
  required WidgetBuilder contenido,
  bool botonCerrar = true,
}) {
  return Navigator.of(context).push(
    _RutaHoja<T>(
      titulo: titulo,
      constructor: (context) =>
          _Hoja(titulo: titulo, contenido: contenido, botonCerrar: botonCerrar),
    ),
  );
}

/// La ruta de la hoja: el velo detrás y la hoja abajo.
class _RutaHoja<T> extends PopupRoute<T> {
  _RutaHoja({required this.titulo, required this.constructor});

  final String titulo;
  final WidgetBuilder constructor;

  @override
  Color? get barrierColor => ColoresApp.velo;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Cerrar';

  // El velo, parejo: se oscurece y se aclara con la hoja.
  @override
  Curve get barrierCurve => Curves.linear;

  @override
  Duration get transitionDuration => MovimientoApp.reducidoSinContexto
      ? MovimientoApp.fundidoReducido
      : MovimientoApp.hojaEntrada;

  @override
  Duration get reverseTransitionDuration => MovimientoApp.reducidoSinContexto
      ? MovimientoApp.fundidoReducido
      : MovimientoApp.hojaSalida;

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

  // Si «Reducir movimiento» cambió con la hoja abierta, las duraciones se
  // actualizan al empezar cada transición.
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
  ) => _MarcoHoja(
    titulo: titulo,
    animacion: animation,
    child: AmbienteDiseno(
      child: Material(
        type: MaterialType.transparency,
        child: Builder(builder: constructor),
      ),
    ),
  );
}

/// Dónde va la hoja y cómo entra, sale y se arrastra.
class _MarcoHoja extends StatefulWidget {
  const _MarcoHoja({
    required this.titulo,
    required this.animacion,
    required this.child,
  });

  final String titulo;
  final Animation<double> animacion;
  final Widget child;

  @override
  State<_MarcoHoja> createState() => _MarcoHojaState();
}

class _MarcoHojaState extends State<_MarcoHoja>
    with SingleTickerProviderStateMixin {
  /// Ancho máximo, en una tablet o con el teléfono acostado.
  static const double _anchoMaximo = 640;

  /// Tirada hacia abajo más rápido que esto (dp/s), se cierra.
  static const double _velocidadCierre = 700;

  /// Arrastrada más que esta parte de su alto, se cierra.
  static const double _fraccionCierre = 0.5;

  static const Animation<Offset> _quieta = AlwaysStoppedAnimation<Offset>(
    Offset.zero,
  );

  late final CurvedAnimation _curva;
  late final Animation<Offset> _subida;

  /// Cuánto se arrastró hacia abajo (dp).
  final ValueNotifier<double> _arrastre = ValueNotifier<double>(0);

  /// La vuelta a su lugar, si se suelta sin llegar a cerrarla.
  late final AnimationController _vuelta;
  double _vueltaDesde = 0;

  final GlobalKey _claveHoja = GlobalKey();

  @override
  void initState() {
    super.initState();
    _curva = CurvedAnimation(
      parent: widget.animacion,
      curve: MovimientoApp.curvaHoja,
      reverseCurve: MovimientoApp.curvaHoja.flipped,
    );
    _subida = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(_curva);
    _vuelta = AnimationController(vsync: this, duration: MovimientoApp.soltar)
      ..addListener(_alVolver);
  }

  void _alVolver() {
    _arrastre.value =
        _vueltaDesde * (1 - MovimientoApp.curva.transform(_vuelta.value));
  }

  void _alArrastrar(DragUpdateDetails detalle) {
    _vuelta.stop();
    _arrastre.value = math.max(
      0,
      _arrastre.value + (detalle.primaryDelta ?? 0),
    );
  }

  void _alSoltar(DragEndDetails detalle) {
    final alto = _claveHoja.currentContext?.size?.height ?? 1;
    final velocidad = detalle.primaryVelocity ?? 0;
    if (velocidad > _velocidadCierre ||
        _arrastre.value > alto * _fraccionCierre) {
      // Se va desde donde quedó.
      Navigator.of(context).maybePop();
      return;
    }
    if (MovimientoApp.reducido(context) || _arrastre.value == 0) {
      _arrastre.value = 0;
      return;
    }
    _vueltaDesde = _arrastre.value;
    _vuelta.forward(from: 0);
  }

  @override
  void dispose() {
    _vuelta.dispose();
    _curva.dispose();
    _arrastre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducido = MovimientoApp.reducido(context);
    // Para TalkBack, la hoja se nombra con su título (la de Material diría
    // "Dialog").
    final hoja = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: widget.titulo,
      child: GestureDetector(
        onVerticalDragUpdate: _alArrastrar,
        onVerticalDragEnd: _alSoltar,
        excludeFromSemantics: true,
        child: KeyedSubtree(key: _claveHoja, child: widget.child),
      ),
    );
    // La misma forma con y sin movimiento reducido (cambian los valores, no
    // los widgets): si el ajuste cambia con la hoja abierta, no pierde lo
    // que se estaba cargando.
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _anchoMaximo),
          child: FadeTransition(
            opacity: reducido ? widget.animacion : kAlwaysCompleteAnimation,
            child: SlideTransition(
              position: reducido ? _quieta : _subida,
              child: ValueListenableBuilder<double>(
                valueListenable: _arrastre,
                child: hoja,
                builder: (context, y, hijo) =>
                    Transform.translate(offset: Offset(0, y), child: hijo),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hoja extends StatelessWidget {
  const _Hoja({
    required this.titulo,
    required this.contenido,
    required this.botonCerrar,
  });

  final String titulo;
  final WidgetBuilder contenido;
  final bool botonCerrar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final manija = FormasApp.manijaHoja;
    return DecoratedBox(
      decoration: DecoracionRelieve(
        color: e.superficie,
        radio: FormasApp.bordeHoja,
        sombraOscura: e.sombraOscura,
        sombraClara: e.sombraClara,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: EspaciadoApp.medio,
                    bottom: EspaciadoApp.minimo,
                  ),
                  child: Center(
                    child: SizedBox.fromSize(
                      size: manija,
                      child: DecoratedBox(
                        decoration: DecoracionRelieve(
                          color: e.hundido,
                          pildora: true,
                          elevacion: -1,
                          tamano: TamanoRelieve.chico,
                          borde: BorderSide(
                            color: e.borde,
                            width: FormasApp.grosorLinea,
                          ),
                          sombraOscura: e.sombraOscura,
                          sombraClara: e.sombraClara,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: EspaciadoApp.margenLateral,
                  end: EspaciadoApp.minimo,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          titulo,
                          style: TipografiaApp.titulo.copyWith(
                            color: e.textoPrincipal,
                          ),
                        ),
                      ),
                    ),
                    if (botonCerrar)
                      BotonRedondo(
                        icono: Icons.close_rounded,
                        etiqueta: 'Cerrar',
                        alPresionar: () => Navigator.of(context).pop(),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    EspaciadoApp.margenLateral,
                    EspaciadoApp.chico,
                    EspaciadoApp.margenLateral,
                    EspaciadoApp.margenLateral,
                  ),
                  child: Builder(builder: contenido),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
