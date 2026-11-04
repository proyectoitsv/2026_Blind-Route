import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'colores.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Relieve: levantado y hundido
// ═══════════════════════════════════════════════════════════════════════════
//
// Lo que se toca se ve levantado o hundido. Levantado: dos sombras por
// fuera, la oscura abajo a la derecha y la clara arriba a la izquierda (la
// luz viene de arriba a la izquierda). Hundido: las mismas dos, por dentro y
// al revés (la oscura en el borde de arriba y de la izquierda), como algo
// grabado en la superficie.
//
// Las medidas son las de CSS del prompt (sección 2.2):
//   levantado        6px 6px 12px oscura, -6px -6px 12px clara
//   levantado chico  4px 4px  8px,        -4px -4px  8px  (botones de ícono,
//                                                          chips)
//   hundido          inset 4px 4px 8px,   inset -4px -4px 8px
//   hundido chico    inset 2px 2px 4px,   inset -2px -2px 4px (cuadros de
//                                                          ícono, campos
//                                                          chicos)
// El desenfoque de CSS es el doble del sigma de la gaussiana (sigma = 6 para
// 12 px). Flutter, en BoxShadow, convierte distinto (12 px serían 7,4 de
// sigma): por eso el relieve se pinta acá, con el sigma de CSS, y no con
// BoxShadow. Además BoxShadow no tiene sombras interiores.
//
// ─── Reglas ───
//   · Todo control interactivo lleva además el borde de 1 px (ColoresApp.
//     borde): el relieve solo no llega a 3:1.
//   · Ninguna sombra sobre el texto: el texto va siempre sobre la superficie
//     plana, a más distancia del borde que el alcance de la sombra
//     (SombraRelieve.alcance).
//   · Sin brillos, halos, vidrio ni degradados. Sin sombras de color.
//
// ─── Elevación ───
// Un número de −1 (hundido) a 1 (levantado), pasando por 0 (plano): las
// sombras se acortan hacia 0 y del otro lado aparecen por dentro. Así la
// fase 3 puede animar el paso de levantado a hundido al presionar
// interpolando un solo número (DecoracionRelieve.lerp).

/// Una sombra del relieve, con las medidas de CSS.
@immutable
class SombraRelieve {
  const SombraRelieve({required this.desplazamiento, required this.desenfoque});

  /// Cuánto se corre la sombra en cada eje, en dp.
  final double desplazamiento;

  /// Radio de desenfoque, como en CSS (dp).
  final double desenfoque;

  /// Sigma de la gaussiana: la mitad del desenfoque, como en CSS.
  double get sigma => desenfoque / 2;

  /// Hasta dónde llega la sombra desde el borde: afuera si es levantado,
  /// adentro si es hundido. A esa distancia ya no se ve (queda debajo del
  /// 3 % de su intensidad): el texto va más lejos.
  double get alcance => desplazamiento + desenfoque;
}

/// El tamaño del relieve: el común (tarjetas, botones, campos, pistas) o el
/// chico (botones de ícono, chips, cuadros de ícono, la manija).
enum TamanoRelieve { comun, chico }

/// Qué parte del relieve pinta una [DecoracionRelieve]. Para algo hundido
/// cuyo contenido tapa el relleno (el plano), el fondo va detrás del
/// contenido y el frente encima: así la sombra interior cae sobre el plano.
enum ParteRelieve {
  /// Todo: sombras de afuera, relleno, sombras de adentro y borde.
  todo,

  /// Las sombras de afuera y el relleno.
  fondo,

  /// Las sombras de adentro y el borde.
  frente,
}

/// Las medidas del relieve (sección 2.2 del prompt).
abstract final class RelieveApp {
  /// Tarjetas, botones grandes, la barra flotante y las hojas.
  static const SombraRelieve levantado = SombraRelieve(
    desplazamiento: 6,
    desenfoque: 12,
  );

  /// Botones de ícono, chips y cabezales.
  static const SombraRelieve levantadoChico = SombraRelieve(
    desplazamiento: 4,
    desenfoque: 8,
  );

  /// El plano, los campos y las pistas.
  static const SombraRelieve hundido = SombraRelieve(
    desplazamiento: 4,
    desenfoque: 8,
  );

  /// Cuadros de ícono, campos chicos, pistas finas y la manija de las hojas.
  static const SombraRelieve hundidoChico = SombraRelieve(
    desplazamiento: 2,
    desenfoque: 4,
  );

  /// La sombra que corresponde a un lado (levantado o hundido) y un tamaño.
  static SombraRelieve sombra({
    required bool levantado,
    required TamanoRelieve tamano,
  }) => switch ((levantado, tamano)) {
    (true, TamanoRelieve.comun) => RelieveApp.levantado,
    (true, TamanoRelieve.chico) => levantadoChico,
    (false, TamanoRelieve.comun) => hundido,
    (false, TamanoRelieve.chico) => hundidoChico,
  };
}

// ─── PINTAR EL RELIEVE ──────────────────────────────────────────────────────

/// Pinta [forma] con relieve: con [elevacion] mayor que 0, levantada (las
/// sombras por fuera); con menor que 0, hundida (por dentro); con 0, plana.
///
/// [relleno] y [borde] son opcionales (el borde va por dentro de la forma,
/// como el de un BoxDecoration). [sombraClara] en null deja sólo la oscura:
/// sobre un relleno más claro que la luz (el acento), la luz se vería como
/// una mancha oscura. [parte] elige qué se pinta (ver [ParteRelieve]).
///
/// Lo usan DecoracionRelieve y los painters que dibujan su propia forma (el
/// anillo de progreso, la línea de ruta, la línea de tiempo).
void pintarRelieve(
  Canvas canvas,
  Path forma, {
  required double elevacion,
  TamanoRelieve tamano = TamanoRelieve.comun,
  Color? relleno,
  BorderSide borde = BorderSide.none,
  Color sombraOscura = ColoresApp.sombraOscura,
  Color? sombraClara = ColoresApp.sombraClara,
  ParteRelieve parte = ParteRelieve.todo,
}) {
  final e = elevacion.clamp(-1.0, 1.0);
  final cuanto = e.abs();
  final conSombras = cuanto > 0.001;
  final sombra = RelieveApp.sombra(levantado: e > 0, tamano: tamano);
  final d = sombra.desplazamiento * cuanto;
  final sigma = sombra.sigma * cuanto;
  final fondo = parte != ParteRelieve.frente;
  final frente = parte != ParteRelieve.fondo;

  if (fondo) {
    // Levantado: la luz primero y la oscura encima (en CSS, la primera
    // sombra de la lista queda arriba).
    if (conSombras && e > 0) {
      if (sombraClara != null) {
        _sombraAfuera(canvas, forma, Offset(-d, -d), sigma, sombraClara);
      }
      _sombraAfuera(canvas, forma, Offset(d, d), sigma, sombraOscura);
    }
    if (relleno != null) {
      canvas.drawPath(forma, Paint()..color = relleno);
    }
  }
  if (frente) {
    // Hundido: la oscura arriba a la izquierda, la luz abajo a la derecha.
    if (conSombras && e < 0) {
      if (sombraClara != null) {
        _sombraAdentro(canvas, forma, Offset(-d, -d), sigma, sombraClara);
      }
      _sombraAdentro(canvas, forma, Offset(d, d), sigma, sombraOscura);
    }
    if (borde.style != BorderStyle.none && borde.width > 0) {
      // Por dentro de la forma: el trazo va centrado en el contorno con el
      // doble del ancho, recortado a la forma.
      canvas
        ..save()
        ..clipPath(forma)
        ..drawPath(
          forma,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = borde.width * 2
            ..color = borde.color,
        )
        ..restore();
    }
  }
}

void _sombraAfuera(
  Canvas canvas,
  Path forma,
  Offset desplazamiento,
  double sigma,
  Color color,
) {
  canvas.drawPath(
    forma.shift(desplazamiento),
    Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
  );
}

/// La sombra interior, como un inset de CSS: un marco (todo menos la forma
/// corrida) desenfocado y recortado a la forma. Donde la forma corrida no
/// tapa, queda la sombra.
void _sombraAdentro(
  Canvas canvas,
  Path forma,
  Offset desplazamiento,
  double sigma,
  Color color,
) {
  final limites = forma.getBounds().inflate(
    desplazamiento.distance + sigma * 3 + 1,
  );
  final marco = Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(limites)
    ..addPath(forma, desplazamiento);
  canvas
    ..save()
    ..clipPath(forma)
    ..drawPath(
      marco,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    )
    ..restore();
}

// ─── DECORACIÓN ─────────────────────────────────────────────────────────────

/// Decoración con relieve para un rectángulo redondeado o un círculo: se usa
/// con DecoratedBox o Container, como un BoxDecoration.
///
/// Las sombras de afuera se pintan fuera de la caja: quien la contiene no
/// tiene que recortar (ni una lista con poco margen, ni un Material).
@immutable
class DecoracionRelieve extends Decoration {
  const DecoracionRelieve({
    required this.color,
    this.radio = BorderRadius.zero,
    this.circulo = false,
    this.pildora = false,
    this.elevacion = 1,
    this.tamano = TamanoRelieve.comun,
    this.borde = BorderSide.none,
    this.sombraOscura = ColoresApp.sombraOscura,
    this.sombraClara = ColoresApp.sombraClara,
    this.parte = ParteRelieve.todo,
  });

  /// Relleno. Levantado, la superficie; hundido, el color de lo hundido.
  final Color color;

  /// Radio de las esquinas (no se usa si es [circulo] o [pildora]).
  final BorderRadiusGeometry radio;

  /// Un círculo del lado más corto de la caja, centrado.
  final bool circulo;

  /// Una píldora: las puntas redondas del todo (radio de la mitad del lado
  /// más corto), como un chip.
  final bool pildora;

  /// De −1 (hundido) a 1 (levantado), pasando por 0 (plano).
  final double elevacion;
  final TamanoRelieve tamano;

  /// Borde, por dentro de la forma. Todo control interactivo lo lleva.
  final BorderSide borde;
  final Color sombraOscura;

  /// null: sólo la sombra oscura (sobre un relleno más claro que la luz).
  final Color? sombraClara;
  final ParteRelieve parte;

  /// La misma decoración con otros valores.
  DecoracionRelieve copyWith({
    Color? color,
    BorderRadiusGeometry? radio,
    bool? circulo,
    bool? pildora,
    double? elevacion,
    TamanoRelieve? tamano,
    BorderSide? borde,
    Color? sombraOscura,
    Color? sombraClara,
    bool sinSombraClara = false,
    ParteRelieve? parte,
  }) => DecoracionRelieve(
    color: color ?? this.color,
    radio: radio ?? this.radio,
    circulo: circulo ?? this.circulo,
    pildora: pildora ?? this.pildora,
    elevacion: elevacion ?? this.elevacion,
    tamano: tamano ?? this.tamano,
    borde: borde ?? this.borde,
    sombraOscura: sombraOscura ?? this.sombraOscura,
    sombraClara: sinSombraClara ? null : (sombraClara ?? this.sombraClara),
    parte: parte ?? this.parte,
  );

  /// Si está levantada.
  bool get levantada => elevacion > 0;

  /// Si está hundida.
  bool get hundida => elevacion < 0;

  /// La forma en [rect].
  RRect formaEn(Rect rect, TextDirection direccion) {
    if (circulo) {
      final r = rect.shortestSide / 2;
      return RRect.fromRectAndRadius(
        Rect.fromCircle(center: rect.center, radius: r),
        Radius.circular(r),
      );
    }
    if (pildora) {
      return RRect.fromRectAndRadius(
        rect,
        Radius.circular(rect.shortestSide / 2),
      );
    }
    return radio.resolve(direccion).toRRect(rect);
  }

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      Path()..addRRect(formaEn(rect, textDirection));

  @override
  bool get isComplex => true;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PintorDecoracionRelieve(this, onChanged);

  /// Interpola entre dos decoraciones: la elevación pasa de un lado al otro
  /// por 0 (plano), y los colores y el borde se mezclan.
  static DecoracionRelieve? lerp(
    DecoracionRelieve? a,
    DecoracionRelieve? b,
    double t,
  ) {
    if (identical(a, b)) return a;
    if (a == null) return b!.copyWith(elevacion: b.elevacion * t);
    if (b == null) return a.copyWith(elevacion: a.elevacion * (1 - t));
    return DecoracionRelieve(
      color: Color.lerp(a.color, b.color, t)!,
      radio: BorderRadiusGeometry.lerp(a.radio, b.radio, t)!,
      circulo: t < 0.5 ? a.circulo : b.circulo,
      pildora: t < 0.5 ? a.pildora : b.pildora,
      elevacion: lerpDouble(a.elevacion, b.elevacion, t)!,
      tamano: t < 0.5 ? a.tamano : b.tamano,
      borde: BorderSide.lerp(a.borde, b.borde, t),
      sombraOscura: Color.lerp(a.sombraOscura, b.sombraOscura, t)!,
      sombraClara: Color.lerp(a.sombraClara, b.sombraClara, t),
      parte: t < 0.5 ? a.parte : b.parte,
    );
  }

  @override
  Decoration? lerpFrom(Decoration? a, double t) {
    if (a == null || a is DecoracionRelieve) {
      return DecoracionRelieve.lerp(a as DecoracionRelieve?, this, t);
    }
    return super.lerpFrom(a, t);
  }

  @override
  Decoration? lerpTo(Decoration? b, double t) {
    if (b == null || b is DecoracionRelieve) {
      return DecoracionRelieve.lerp(this, b as DecoracionRelieve?, t);
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      other is DecoracionRelieve &&
      other.color == color &&
      other.radio == radio &&
      other.circulo == circulo &&
      other.pildora == pildora &&
      other.elevacion == elevacion &&
      other.tamano == tamano &&
      other.borde == borde &&
      other.sombraOscura == sombraOscura &&
      other.sombraClara == sombraClara &&
      other.parte == parte;

  @override
  int get hashCode => Object.hash(
    color,
    radio,
    circulo,
    pildora,
    elevacion,
    tamano,
    borde,
    sombraOscura,
    sombraClara,
    parte,
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('color', color))
      ..add(DoubleProperty('elevacion', elevacion))
      ..add(EnumProperty<TamanoRelieve>('tamano', tamano))
      ..add(DiagnosticsProperty<BorderSide>('borde', borde))
      ..add(EnumProperty<ParteRelieve>('parte', parte));
  }
}

class _PintorDecoracionRelieve extends BoxPainter {
  _PintorDecoracionRelieve(this._decoracion, super.onChanged);

  final DecoracionRelieve _decoracion;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final tamano = configuration.size;
    if (tamano == null || tamano.isEmpty) return;
    final d = _decoracion;
    final forma = Path()
      ..addRRect(
        d.formaEn(
          offset & tamano,
          configuration.textDirection ?? TextDirection.ltr,
        ),
      );
    pintarRelieve(
      canvas,
      forma,
      elevacion: d.elevacion,
      tamano: d.tamano,
      relleno: d.color,
      borde: d.borde,
      sombraOscura: d.sombraOscura,
      sombraClara: d.sombraClara,
      parte: d.parte,
    );
  }
}
