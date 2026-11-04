import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Anillos, barras de progreso y minigráfico
// ═══════════════════════════════════════════════════════════════════════════
//
// Dibujados con CustomPainter: trazo grueso con puntas redondas.
//
// ─── Relieve y contraste ───
// La pista va hundida (el relieve chico) y el avance, en acento plano, sin
// degradado: 9,79 contra lo hundido. La pista en sí es decorativa: el dato
// lo dan el avance y el número.
//
// ─── TalkBack ───
// Cada uno es un elemento propio que lee su nombre y el valor ("Descarga,
// 45 %"); sin "container", Flutter pegaría la etiqueta al elemento de
// arriba. El dibujo no se describe: el valor está en el texto.
//
// Para una carga sin porcentaje (no se sabe cuánto falta), el
// CircularProgressIndicator o el LinearProgressIndicator del tema.
//
// El valor cambia de golpe; que se llene animado es de la fase 3, y nunca en
// la navegación en vivo.

/// "45 %", con un espacio que no se parte entre el número y el signo.
String textoPorcentaje(double valor) =>
    '${(valor.clamp(0.0, 1.0) * 100).round()} %';

// ─── ANILLO ─────────────────────────────────────────────────────────────────

/// Anillo de progreso, con un texto opcional en el centro.
///
/// Con un [centro], el anillo crece con la letra para que el texto siga
/// entrando adentro.
class AnilloProgreso extends StatelessWidget {
  const AnilloProgreso({
    super.key,
    required this.valor,
    this.diametro = FormasApp.diametroAnillo,
    this.grosor = FormasApp.grosorAnillo,
    this.centro,
    this.etiqueta,
    this.valorSemantico,
  });

  /// De 0 a 1.
  final double valor;
  final double diametro;
  final double grosor;

  /// Lo que va adentro, en general el porcentaje.
  final Widget? centro;

  /// El nombre para TalkBack ("Mapas descargados").
  final String? etiqueta;

  /// El valor para TalkBack. Por defecto, el porcentaje.
  final String? valorSemantico;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final escala = centro == null ? 1.0 : TipografiaApp.escalaTexto(context);
    return Semantics(
      container: true,
      label: etiqueta,
      value: valorSemantico ?? textoPorcentaje(valor),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: diametro * escala,
        child: CustomPaint(
          painter: _PintorAnillo(
            valor: valor,
            grosor: grosor * escala,
            estilo: e,
          ),
          child: centro == null ? null : Center(child: centro),
        ),
      ),
    );
  }
}

class _PintorAnillo extends CustomPainter {
  const _PintorAnillo({
    required this.valor,
    required this.grosor,
    required this.estilo,
  });

  final double valor;
  final double grosor;
  final EstiloApp estilo;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final exterior = size.shortestSide / 2;
    // La pista: un aro hundido.
    final aro = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: centro, radius: exterior))
      ..addOval(Rect.fromCircle(center: centro, radius: exterior - grosor));
    pintarRelieve(
      canvas,
      aro,
      elevacion: -1,
      tamano: TamanoRelieve.chico,
      relleno: estilo.hundido,
      sombraOscura: estilo.sombraOscura,
      sombraClara: estilo.sombraClara,
    );
    final v = valor.clamp(0.0, 1.0);
    if (v <= 0) return;
    // El avance, un poco más fino que la pista, adentro de la ranura.
    final ancho = math.max(2.0, grosor - 2);
    final radio = exterior - grosor / 2;
    final trazo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ancho
      ..strokeCap = StrokeCap.round
      ..color = estilo.acento;
    if (v >= 1) {
      canvas.drawCircle(centro, radio, trazo);
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: centro, radius: radio),
        -math.pi / 2,
        2 * math.pi * v,
        false,
        trazo,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorAnillo anterior) =>
      anterior.valor != valor ||
      anterior.grosor != grosor ||
      anterior.estilo != estilo;
}

// ─── BARRA ──────────────────────────────────────────────────────────────────

/// Barra de progreso horizontal, de todo el ancho.
class BarraProgreso extends StatelessWidget {
  const BarraProgreso({
    super.key,
    required this.valor,
    this.etiqueta,
    this.valorSemantico,
  });

  /// De 0 a 1.
  final double valor;

  /// El nombre para TalkBack ("Descarga del mapa").
  final String? etiqueta;

  /// El valor para TalkBack. Por defecto, el porcentaje.
  final String? valorSemantico;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Semantics(
      container: true,
      label: etiqueta,
      value: valorSemantico ?? textoPorcentaje(valor),
      excludeSemantics: true,
      child: SizedBox(
        height: FormasApp.altoBarraProgreso,
        width: double.infinity,
        child: CustomPaint(
          painter: _PintorBarra(
            valor: valor,
            estilo: e,
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _PintorBarra extends CustomPainter {
  const _PintorBarra({
    required this.valor,
    required this.estilo,
    required this.textDirection,
  });

  final double valor;
  final EstiloApp estilo;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    // La pista: una ranura hundida.
    pintarRelieve(
      canvas,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
      ),
      elevacion: -1,
      tamano: TamanoRelieve.chico,
      relleno: estilo.hundido,
      sombraOscura: estilo.sombraOscura,
      sombraClara: estilo.sombraClara,
    );
    final v = valor.clamp(0.0, 1.0);
    if (v <= 0) return;
    // El avance, adentro de la ranura (2 dp de aire). Aun con muy poco se ve
    // un punto: nunca menos que su alto.
    final adentro = (Offset.zero & size).deflate(2);
    final ancho = math.max(adentro.height, adentro.width * v);
    final izquierda = textDirection == TextDirection.rtl
        ? adentro.right - ancho
        : adentro.left;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(izquierda, adentro.top, ancho, adentro.height),
        Radius.circular(adentro.height / 2),
      ),
      Paint()..color = estilo.acento,
    );
  }

  @override
  bool shouldRepaint(_PintorBarra anterior) =>
      anterior.valor != valor ||
      anterior.estilo != estilo ||
      anterior.textDirection != textDirection;
}

// ─── MINIGRÁFICO ────────────────────────────────────────────────────────────

/// Línea con la evolución de un valor (por ejemplo, la señal del último
/// minuto), con un punto en el último. Va al pie de una tarjeta de dato.
///
/// Sin [descripcion] es decorativo y TalkBack lo saltea; con ella, la lee
/// ("Estable en el último minuto").
class MiniGrafico extends StatelessWidget {
  const MiniGrafico({super.key, required this.valores, this.descripcion});

  final List<double> valores;
  final String? descripcion;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final dibujo = SizedBox(
      height: FormasApp.altoMiniGrafico,
      width: double.infinity,
      child: CustomPaint(
        painter: _PintorMiniGrafico(valores: valores, color: e.acento),
      ),
    );
    if (descripcion == null) return ExcludeSemantics(child: dibujo);
    return Semantics(
      container: true,
      label: descripcion,
      excludeSemantics: true,
      child: dibujo,
    );
  }
}

class _PintorMiniGrafico extends CustomPainter {
  const _PintorMiniGrafico({required this.valores, required this.color});

  final List<double> valores;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;
    const grosor = FormasApp.grosorMiniGrafico;
    // El punto del final mide el doble del trazo: el margen evita que se
    // recorte contra los bordes.
    const margen = grosor * 1.5;
    final area = Rect.fromLTRB(
      margen,
      margen,
      size.width - margen,
      size.height - margen,
    );
    final minimo = valores.reduce(math.min);
    final maximo = valores.reduce(math.max);
    final rango = maximo - minimo;

    Offset punto(int i) {
      final x = valores.length == 1
          ? area.right
          : area.left + area.width * i / (valores.length - 1);
      // Si todos son iguales, la línea va por el medio.
      final t = rango == 0 ? 0.5 : (valores[i] - minimo) / rango;
      return Offset(x, area.bottom - area.height * t);
    }

    final pintura = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (valores.length > 1) {
      final camino = Path()..moveTo(punto(0).dx, punto(0).dy);
      for (var i = 1; i < valores.length; i++) {
        camino.lineTo(punto(i).dx, punto(i).dy);
      }
      canvas.drawPath(camino, pintura);
    }
    canvas.drawCircle(
      punto(valores.length - 1),
      margen,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PintorMiniGrafico anterior) =>
      anterior.color != color || !_iguales(anterior.valores, valores);

  static bool _iguales(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
