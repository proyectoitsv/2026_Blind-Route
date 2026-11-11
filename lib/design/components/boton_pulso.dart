import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../movimiento.dart';
import '../tipografia.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Botón con pulso
// ═══════════════════════════════════════════════════════════════════════════
//
// La acción principal del inicio: un círculo de acento en el medio, sin
// tarjeta ni bordes alrededor, que cada tanto larga ondas que se abren y se
// apagan, como la señal de un GPS. Se encuentra de un vistazo y se toca en
// cualquier parte: el círculo, el título o la aclaración.
//
// Es la única animación que se repite de la app, y es decorativa: con
// «Reducir movimiento» (o «Quitar animaciones» del teléfono) las ondas no se
// mueven y queda un anillo quieto. El ticker se apaga solo cuando otra
// pantalla tapa a esta (TickerMode). Las ondas se pintan en su propia capa:
// cada cuadro repinta sólo eso.

/// El botón con pulso: un círculo de acento con el ícono en oscuro, el
/// título debajo y una aclaración para quien ve (TalkBack no la lee: ya dice
/// cómo activarlo).
class BotonPulso extends StatefulWidget {
  const BotonPulso({
    super.key,
    required this.texto,
    required this.icono,
    required this.alPresionar,
    this.detalle,
    this.llenar = false,
  });

  /// El título, debajo del círculo. Es lo que dice TalkBack.
  final String texto;

  /// El ícono del círculo (Icons.*_rounded), en oscuro sobre el acento.
  final IconData icono;

  /// null: deshabilitado (gris y sin ondas).
  final VoidCallback? alPresionar;

  /// Debajo del título, en gris. TalkBack no la lee.
  final String? detalle;

  /// Si el botón ocupa todo el lugar que le dan, con el círculo en el
  /// medio. Así se acierta aunque no se toque justo el círculo.
  final bool llenar;

  /// Cuánto se mueve la flecha hacia cada costado al buscar el norte, como
  /// la aguja de una brújula, en radianes (12°).
  static const double vaivenFlecha = 12 * math.pi / 180;

  /// Cuántas idas y vueltas da la flecha en cada pulso antes de quedarse
  /// quieta.
  static const double oscilacionesFlecha = 3;

  /// El giro de la flecha en el momento [t] (0 a 1) del pulso: va y viene,
  /// cada vez menos, y se asienta antes del pulso siguiente.
  static double giroFlecha(double t) =>
      vaivenFlecha *
      math.sin(2 * math.pi * oscilacionesFlecha * t) *
      math.exp(-4 * t);

  /// Diámetro del círculo. No crece con la letra, como los íconos.
  static const double diametro = 152;

  /// Hasta dónde llega una onda, en radios del círculo.
  static const double alcanceOnda = 1.7;

  /// Cada cuánto se repite el pulso: dos ondas seguidas y una pausa.
  static const Duration periodo = Duration(milliseconds: 2600);

  /// Cuánto tarda una onda en abrirse y apagarse.
  static const Duration vidaOnda = Duration(milliseconds: 1700);

  /// Cuándo sale la segunda onda, después de la primera.
  static const Duration entreOndas = Duration(milliseconds: 380);

  @override
  State<BotonPulso> createState() => _BotonPulsoState();
}

class _BotonPulsoState extends State<BotonPulso>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: BotonPulso.periodo,
  );

  bool get _animar =>
      widget.alPresionar != null && !MovimientoApp.reducido(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ajustarPulso();
  }

  @override
  void didUpdateWidget(covariant BotonPulso anterior) {
    super.didUpdateWidget(anterior);
    _ajustarPulso();
  }

  void _ajustarPulso() {
    if (_animar) {
      if (!_pulso.isAnimating) _pulso.repeat();
    } else if (_pulso.isAnimating || _pulso.value != 0) {
      _pulso
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final habilitado = widget.alPresionar != null;
    final relleno = habilitado ? e.acento : e.separador;
    const radio = BotonPulso.diametro / 2;
    // Las ondas salen del círculo y pasan por detrás del texto; el lugar
    // que ocupan no empuja nada (se pintan fuera de la caja).
    final circulo = SizedBox.square(
      dimension: BotonPulso.diametro,
      child: CustomPaint(
        painter: _OndasPainter(
          pulso: _pulso,
          color: e.acento,
          quieto: !_animar,
          visible: habilitado,
        ),
        child: const SizedBox.expand(),
      ),
    );
    return ConEstados(
      deshabilitado: !habilitado,
      constructor: (context, controlador, estados) {
        final presionado = estaPresionado(estados);
        final enfocado = estados.contains(WidgetState.focused);
        final boton = FilledButton(
          onPressed: widget.alPresionar,
          statesController: controlador,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: e.textoPrincipal,
            disabledForegroundColor: e.textoSecundario,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: EspaciadoApp.margenLateral,
              vertical: EspaciadoApp.medio,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: FormasApp.bordeTarjeta,
            ),
            tapTargetSize: MaterialTapTargetSize.padded,
            splashFactory: sinOnda,
          ).copyWith(overlayColor: sinCapa),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  RepaintBoundary(child: circulo),
                  EscalaPresion(
                    presionado: presionado,
                    child: AnimatedContainer(
                      duration: MovimientoApp.duracion(
                        context,
                        presionado
                            ? MovimientoApp.presion
                            : MovimientoApp.soltar,
                      ),
                      curve: MovimientoApp.curva,
                      width: BotonPulso.diametro,
                      height: BotonPulso.diametro,
                      decoration: BoxDecoration(
                        // Presionado, un poco más oscuro: se hunde.
                        color: presionado
                            ? Color.lerp(relleno, e.fondo, 0.18)
                            : relleno,
                        shape: BoxShape.circle,
                        border: enfocado
                            ? Border.all(
                                color: e.textoSobreAcento,
                                width: FormasApp.grosorFoco,
                              )
                            : null,
                      ),
                      // La flecha va y viene a los costados, como una
                      // aguja que busca el norte. Quieta sin el pulso.
                      child: AnimatedBuilder(
                        animation: _pulso,
                        builder: (context, flecha) => Transform.rotate(
                          angle: BotonPulso.giroFlecha(_pulso.value),
                          child: flecha,
                        ),
                        child: Icon(
                          widget.icono,
                          size: radio * 0.82,
                          color: habilitado
                              ? e.textoSobreAcento
                              : e.textoSecundario,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Lo que llega una onda más allá del círculo: el texto queda
              // fuera de su alcance.
              const SizedBox(
                height: BotonPulso.diametro / 2 * (BotonPulso.alcanceOnda - 1),
              ),
              Text(
                widget.texto,
                textAlign: TextAlign.center,
                style: TipografiaApp.titulo,
              ),
              if (widget.detalle != null) ...[
                const SizedBox(height: EspaciadoApp.chico),
                ExcludeSemantics(
                  child: Text(
                    widget.detalle!,
                    textAlign: TextAlign.center,
                    style: TipografiaApp.cuerpo.copyWith(
                      color: e.textoSecundario,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
        return widget.llenar ? SizedBox.expand(child: boton) : boton;
      },
    );
  }
}

/// Las ondas: dos por pulso, que se abren desde el borde del círculo hasta
/// [BotonPulso.alcanceOnda] radios y se apagan. Quietas, un anillo tenue.
class _OndasPainter extends CustomPainter {
  _OndasPainter({
    required this.pulso,
    required this.color,
    required this.quieto,
    required this.visible,
  }) : super(repaint: pulso);

  final Animation<double> pulso;
  final Color color;
  final bool quieto;
  final bool visible;

  /// Dónde va una onda (0 a 1) en el momento [t] del periodo, o null si no
  /// está a la vista.
  static double? _avance(double t, Duration salida) {
    final periodo = BotonPulso.periodo.inMicroseconds;
    final desde = salida.inMicroseconds / periodo;
    final vida = BotonPulso.vidaOnda.inMicroseconds / periodo;
    final p = (t - desde) / vida;
    return p >= 0 && p <= 1 ? p : null;
  }

  void _onda(Canvas canvas, Offset centro, double radio, double p) {
    // Arranca rápido y frena: la curva de casi todo.
    final abierta = MovimientoApp.curva.transform(p);
    final r = radio * (1 + (BotonPulso.alcanceOnda - 1) * abierta);
    final opacidad = math.pow(1 - p, 1.6).toDouble();
    canvas.drawCircle(
      centro,
      r,
      Paint()..color = color.withValues(alpha: 0.07 * opacidad),
    );
    canvas.drawCircle(
      centro,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.6 * opacidad),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final centro = size.center(Offset.zero);
    final radio = size.shortestSide / 2;
    if (quieto) {
      canvas.drawCircle(
        centro,
        radio * 1.3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.3),
      );
      return;
    }
    final t = pulso.value;
    for (final salida in [Duration.zero, BotonPulso.entreOndas]) {
      final p = _avance(t, salida);
      if (p != null) _onda(canvas, centro, radio, p);
    }
  }

  @override
  bool shouldRepaint(covariant _OndasPainter anterior) =>
      anterior.color != color ||
      anterior.quieto != quieto ||
      anterior.visible != visible;
}
