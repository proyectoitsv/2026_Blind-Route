import 'dart:math' as math;
import 'dart:ui' show PathMetric, lerpDouble;

import 'package:flutter/material.dart';

import '../estilo.dart';
import '../formas.dart';
import '../movimiento.dart';
import '../relieve.dart';
import 'movimiento_cabezal.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Línea de ruta (la ruta sobre el plano)
// ═══════════════════════════════════════════════════════════════════════════
//
// La ruta dibujada sobre el plano hundido, como grabada: una ranura oscura
// (ColoresApp.rutaRanura) debajo del trazo y, encima, cada tramo según su
// estado:
//   hecho      verde, trazo fino                 (13,31 sobre la ranura)
//   actual     acento, el más grueso (5 dp)      (11,14)
//   siguiente  violeta, fino y punteado          (8,23)
// El estado no depende sólo del color: el actual es más grueso y el
// siguiente va punteado. El destino va en un cuadro con borde verde; las
// escaleras y los ascensores, en un cuadro con el borde gris de los
// controles. El cabezal (dónde va el usuario sobre la ruta) es un círculo
// levantado con un anillo de acento de 3 dp.
//
// Es sólo visual: lo que se dice por voz en la navegación no cambia.
//
// ─── Coordenadas ───
// Los puntos de cada tramo van normalizados (0 a 1 del ancho y del alto de
// la línea), como las posiciones de la app sobre la imagen del plano: la
// línea se pone encima del plano, del mismo tamaño.
//
// ─── Movimiento (fase 3) ───
//   · Cabezal: con cada posición, suavizado de τ = 80 ms; al cambiar de
//     tramo, recorre la ruta a lo largo de la línea (PathMetrics) en 350 ms
//     (MovimientoCabezal). Al llegar, se queda en el destino.
//   · Tramos: al cambiar de tramo, el que se completa pasa de acento a verde
//     y el siguiente, de violeta punteado a acento sólido (los guiones se
//     alargan hasta juntarse), en 300 ms.
//   · Con movimiento reducido, todo salta. Una ruta nueva (otros tramos)
//     también salta: no es un movimiento del usuario.
// La ruta va en un RepaintBoundary y el cabezal en otro: cada posición
// repinta sólo la capa del cabezal.
//
// ─── TalkBack ───
// Se lee de una vez, como un resumen: "Tramo 2 de 3, 8 metros, escalera al
// piso 2" (los metros son los que faltan para terminar el tramo).

/// Qué hay al final de un tramo.
enum MarcaTramo {
  escalera(Icons.stairs_rounded, 'escalera'),
  ascensor(Icons.elevator_rounded, 'ascensor'),
  destino(Icons.flag_rounded, 'destino');

  const MarcaTramo(this.icono, this.nombre);

  /// El ícono de la marca.
  final IconData icono;

  /// Cómo se dice, si el tramo no trae una descripción propia.
  final String nombre;
}

/// Un tramo de la ruta: cuánto mide, qué hay al final y, para dibujarlo
/// sobre el plano, por dónde pasa.
@immutable
class TramoRuta {
  const TramoRuta({
    required this.metros,
    this.marca,
    this.descripcionMarca,
    this.puntos = const [],
  }) : assert(metros >= 0, 'Un tramo no mide menos de 0 m.');

  /// Largo del tramo, en metros.
  final double metros;

  /// Lo que hay al final: una escalera, un ascensor o el destino. null: nada
  /// (el tramo sigue en el siguiente).
  final MarcaTramo? marca;

  /// Cómo se dice la marca en el resumen ("escalera al piso 2", "Aula 12").
  /// Por defecto, el nombre de la marca.
  final String? descripcionMarca;

  /// Por dónde pasa sobre el plano, normalizado (0 a 1 del ancho y del
  /// alto). El primero suele ser el último del tramo anterior. Sólo lo usa
  /// la línea de ruta; la línea de tiempo usa los metros.
  final List<Offset> puntos;

  /// Lo que dice el resumen del final del tramo, o null si no hay marca.
  String? get textoMarca => descripcionMarca ?? marca?.nombre;
}

/// Estado de un tramo respecto del usuario.
enum EstadoTramo {
  /// Ya recorrido.
  hecho,

  /// En el que está el usuario.
  actual,

  /// Los que faltan.
  siguiente,
}

/// El recorrido: los tramos, en cuál está el usuario y cuánto avanzó. Lo
/// comparten la línea de ruta y la línea de tiempo.
@immutable
class Recorrido {
  const Recorrido({
    required this.tramos,
    required this.tramoActual,
    this.avance = 0,
  });

  final List<TramoRuta> tramos;

  /// Índice del tramo en el que está el usuario (0 = el primero).
  final int tramoActual;

  /// Cuánto del tramo actual ya se recorrió, de 0 a 1.
  final double avance;

  /// El tramo actual, dentro del rango.
  int get actual =>
      tramos.isEmpty ? 0 : tramoActual.clamp(0, tramos.length - 1);

  /// El avance, entre 0 y 1.
  double get avanceAcotado => avance.clamp(0.0, 1.0);

  /// El estado del tramo [i].
  EstadoTramo estadoDe(int i) => i < actual
      ? EstadoTramo.hecho
      : i == actual
      ? EstadoTramo.actual
      : EstadoTramo.siguiente;

  /// Los metros que faltan para terminar el tramo actual, redondeados.
  int get metrosQueFaltan => tramos.isEmpty
      ? 0
      : (tramos[actual].metros * (1 - avanceAcotado)).round();

  /// Lo que lee TalkBack: "Tramo 2 de 3, 8 metros, escalera al piso 2".
  String get resumen {
    if (tramos.isEmpty) return 'Sin ruta';
    final m = metrosQueFaltan;
    return [
      'Tramo ${actual + 1} de ${tramos.length}',
      '$m ${m == 1 ? 'metro' : 'metros'}',
      ?tramos[actual].textoMarca,
    ].join(', ');
  }
}

/// La ruta sobre el plano. Ocupa todo el lugar que le dan: va encima del
/// plano, del mismo tamaño.
class LineaRuta extends StatefulWidget {
  const LineaRuta({
    super.key,
    required this.tramos,
    required this.tramoActual,
    this.avance = 0,
  });

  /// Los tramos. Otra lista (otra ruta) hace saltar el cabezal y los
  /// colores, sin animar.
  final List<TramoRuta> tramos;

  /// Índice del tramo en el que está el usuario (0 = el primero).
  final int tramoActual;

  /// Cuánto del tramo actual ya se recorrió, de 0 a 1: ahí va el cabezal.
  final double avance;

  Recorrido get _recorrido =>
      Recorrido(tramos: tramos, tramoActual: tramoActual, avance: avance);

  /// Lo que lee TalkBack.
  String get resumen => _recorrido.resumen;

  /// Dónde va el centro del cabezal en una línea de [tamano], o null si la
  /// ruta no tiene puntos: a lo largo de la ruta, al principio del tramo
  /// actual más [avance] de su largo.
  static Offset? posicionCabezal(
    List<TramoRuta> tramos,
    int tramoActual,
    double avance,
    Size tamano,
  ) {
    final r = Recorrido(
      tramos: tramos,
      tramoActual: tramoActual,
      avance: avance,
    );
    final trazado = _Trazado(tramos, tamano);
    final distancia = trazado.distancia(r.actual, r.avanceAcotado);
    return distancia == null ? null : trazado.punto(distancia);
  }

  @override
  State<LineaRuta> createState() => _LineaRutaState();
}

class _LineaRutaState extends State<LineaRuta>
    with SingleTickerProviderStateMixin {
  /// El cambio de colores de los tramos (300 ms).
  late final AnimationController _cambio;
  late final CurvedAnimation _curva;

  /// Cómo se ve cada tramo al empezar el cambio y al terminarlo.
  late List<_Mezcla> _desde;
  late List<_Mezcla> _hasta;

  @override
  void initState() {
    super.initState();
    _cambio = AnimationController(
      vsync: this,
      duration: MovimientoApp.tramo,
      value: 1,
    );
    _curva = CurvedAnimation(parent: _cambio, curve: MovimientoApp.curva);
    _desde = _mezclas(widget);
    _hasta = _desde;
  }

  static List<_Mezcla> _mezclas(LineaRuta w) {
    final r = w._recorrido;
    return [
      for (var i = 0; i < w.tramos.length; i++) _Mezcla.de(r.estadoDe(i)),
    ];
  }

  /// Cómo se ve cada tramo ahora.
  List<_Mezcla> get _mostradas => [
    for (var i = 0; i < _hasta.length; i++)
      _Mezcla.lerp(_desde[i], _hasta[i], _curva.value),
  ];

  @override
  void didUpdateWidget(covariant LineaRuta anterior) {
    super.didUpdateWidget(anterior);
    final nuevas = _mezclas(widget);
    final otraRuta =
        !identical(anterior.tramos, widget.tramos) ||
        nuevas.length != _hasta.length;
    if (!otraRuta && _iguales(nuevas, _hasta)) return;
    if (otraRuta || MovimientoApp.reducido(context)) {
      _desde = nuevas;
      _hasta = nuevas;
      _cambio.value = 1;
      return;
    }
    // Interrumpido, sigue desde como se ve ahora.
    _desde = _mostradas;
    _hasta = nuevas;
    _cambio.forward(from: 0);
  }

  static bool _iguales(List<_Mezcla> a, List<_Mezcla> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _curva.dispose();
    _cambio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final r = widget._recorrido;
    return Semantics(
      container: true,
      label: r.resumen,
      excludeSemantics: true,
      child: SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, restricciones) => Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: _PintorRuta(
                    tramos: widget.tramos,
                    desde: _desde,
                    hasta: _hasta,
                    cambio: _curva,
                    estilo: e,
                  ),
                ),
              ),
              RepaintBoundary(
                child: _CapaCabezal(
                  tramos: widget.tramos,
                  actual: r.actual,
                  avance: r.avanceAcotado,
                  tamano: restricciones.biggest,
                  estilo: e,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Offset _aPixeles(Offset p, Size tamano) =>
    Offset(p.dx * tamano.width, p.dy * tamano.height);

/// Largo en píxeles de un tramo.
double _largo(List<Offset> puntos, Size tamano) {
  var largo = 0.0;
  for (var i = 1; i < puntos.length; i++) {
    largo += (_aPixeles(puntos[i], tamano) - _aPixeles(puntos[i - 1], tamano))
        .distance;
  }
  return largo;
}

Path _caminoDe(List<Offset> puntos, Size tamano) {
  final camino = Path();
  for (final (i, p) in puntos.indexed) {
    final punto = _aPixeles(p, tamano);
    if (i == 0) {
      camino.moveTo(punto.dx, punto.dy);
    } else {
      camino.lineTo(punto.dx, punto.dy);
    }
  }
  return camino;
}

/// [camino] cortado en guiones de [guion] con huecos de [hueco].
Path _punteado(Path camino, double guion, double hueco) {
  final resultado = Path();
  for (final metrica in camino.computeMetrics()) {
    var d = 0.0;
    while (d < metrica.length) {
      final fin = math.min(d + guion, metrica.length);
      resultado.addPath(metrica.extractPath(d, fin), Offset.zero);
      d = fin + hueco;
    }
  }
  return resultado;
}

/// La ruta entera como una sola línea, en un [tamano]: dónde empieza cada
/// tramo y cuánto mide, en píxeles a lo largo de la línea.
class _Trazado {
  factory _Trazado(List<TramoRuta> tramos, Size tamano) {
    final camino = Path();
    final inicios = <double>[];
    final largos = <double>[];
    var recorrido = 0.0;
    var hayPuntos = false;
    for (final t in tramos) {
      final largo = _largo(t.puntos, tamano);
      inicios.add(recorrido);
      largos.add(largo);
      recorrido += largo;
      // Una sola línea con todos los tramos: si el primer punto de un tramo
      // no coincide con el último del anterior, la ruta los une.
      for (final p in t.puntos) {
        final punto = _aPixeles(p, tamano);
        if (hayPuntos) {
          camino.lineTo(punto.dx, punto.dy);
        } else {
          camino.moveTo(punto.dx, punto.dy);
          hayPuntos = true;
        }
      }
    }
    final metricas = hayPuntos
        ? camino.computeMetrics().toList()
        : const <PathMetric>[];
    return _Trazado._(
      metricas.isEmpty ? null : metricas.first,
      inicios,
      largos,
    );
  }

  const _Trazado._(this._metrica, this._inicios, this._largos);

  final PathMetric? _metrica;
  final List<double> _inicios;
  final List<double> _largos;

  /// Cuánto de la línea hay hasta el tramo [actual] más [avance] de su
  /// largo, o null si la ruta no tiene puntos.
  double? distancia(int actual, double avance) {
    final metrica = _metrica;
    if (metrica == null || actual >= _inicios.length) return null;
    return (_inicios[actual] + _largos[actual] * avance).clamp(
      0.0,
      metrica.length,
    );
  }

  /// El punto de la línea a [distancia] del principio.
  Offset? punto(double distancia) {
    final metrica = _metrica;
    if (metrica == null) return null;
    return metrica
        .getTangentForOffset(distancia.clamp(0.0, metrica.length))
        ?.position;
  }
}

/// Cómo se ve un tramo: una mezcla de los tres estados (en reposo, uno solo
/// pesa 1). Al cambiar de tramo, cada uno pasa de una mezcla a otra; si el
/// cambio se interrumpe, el siguiente arranca de la mezcla que se ve.
@immutable
class _Mezcla {
  const _Mezcla(this.hecho, this.actual, this.siguiente);

  factory _Mezcla.de(EstadoTramo estado) => switch (estado) {
    EstadoTramo.hecho => const _Mezcla(1, 0, 0),
    EstadoTramo.actual => const _Mezcla(0, 1, 0),
    EstadoTramo.siguiente => const _Mezcla(0, 0, 1),
  };

  final double hecho;
  final double actual;
  final double siguiente;

  static _Mezcla lerp(_Mezcla a, _Mezcla b, double t) => _Mezcla(
    lerpDouble(a.hecho, b.hecho, t)!,
    lerpDouble(a.actual, b.actual, t)!,
    lerpDouble(a.siguiente, b.siguiente, t)!,
  );

  /// El color del trazo. En reposo, el del estado tal cual.
  Color color(EstiloApp e) {
    if (hecho >= 1) return e.hecho;
    if (actual >= 1) return e.acento;
    if (siguiente >= 1) return e.siguiente;
    double canal(double Function(Color) de) =>
        hecho * de(e.hecho) +
        actual * de(e.acento) +
        siguiente * de(e.siguiente);
    return Color.from(
      alpha: canal((c) => c.a),
      red: canal((c) => c.r),
      green: canal((c) => c.g),
      blue: canal((c) => c.b),
    );
  }

  /// El grosor del trazo: el actual, más grueso.
  double get grosor =>
      (hecho + siguiente) * FormasApp.grosorRuta +
      actual * FormasApp.grosorRutaActual;

  /// El hueco entre guiones: sólo el siguiente va punteado. Al pasar a
  /// actual, los guiones se alargan hasta juntarse.
  double get hueco => siguiente * FormasApp.huecoRuta;

  @override
  bool operator ==(Object other) =>
      other is _Mezcla &&
      other.hecho == hecho &&
      other.actual == actual &&
      other.siguiente == siguiente;

  @override
  int get hashCode => Object.hash(hecho, actual, siguiente);
}

class _PintorRuta extends CustomPainter {
  _PintorRuta({
    required this.tramos,
    required this.desde,
    required this.hasta,
    required this.cambio,
    required this.estilo,
  }) : super(repaint: cambio);

  final List<TramoRuta> tramos;
  final List<_Mezcla> desde;
  final List<_Mezcla> hasta;

  /// Cuánto va del cambio de tramo, de 0 a 1 (ya con la curva).
  final Animation<double> cambio;
  final EstiloApp estilo;

  Paint _trazo(double grosor, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = grosor
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = cambio.value;
    final mezclas = [
      for (var i = 0; i < tramos.length && i < hasta.length; i++)
        t >= 1 ? hasta[i] : _Mezcla.lerp(desde[i], hasta[i], t),
    ];
    final caminos = [
      for (var i = 0; i < mezclas.length; i++)
        _caminoDe(tramos[i].puntos, size),
    ];

    // Primero todas las ranuras, así un trazo nunca queda debajo de la
    // ranura del tramo de al lado.
    for (var i = 0; i < mezclas.length; i++) {
      if (tramos[i].puntos.length < 2) continue;
      canvas.drawPath(
        caminos[i],
        _trazo(
          mezclas[i].grosor + 2 * FormasApp.bordeRanura,
          estilo.rutaRanura,
        ),
      );
    }
    // Los trazos, del más fino al más grueso: el actual queda encima de los
    // demás (a igual grosor, en orden).
    final orden = [for (var i = 0; i < mezclas.length; i++) i]
      ..sort((a, b) {
        final porGrosor = mezclas[a].grosor.compareTo(mezclas[b].grosor);
        return porGrosor != 0 ? porGrosor : a.compareTo(b);
      });
    for (final i in orden) {
      if (tramos[i].puntos.length < 2) continue;
      final m = mezclas[i];
      final pintura = _trazo(m.grosor, m.color(estilo));
      // Con menos de medio píxel de hueco ya se ve sólido.
      canvas.drawPath(
        m.hueco < 0.5
            ? caminos[i]
            : _punteado(caminos[i], FormasApp.guionRuta, m.hueco),
        pintura,
      );
    }
    // Las marcas, al final de su tramo.
    for (final t in tramos) {
      final marca = t.marca;
      if (marca == null || t.puntos.isEmpty) continue;
      _pintarMarca(canvas, marca, _aPixeles(t.puntos.last, size));
    }
  }

  /// El cuadro de una marca: el del destino con borde verde (2 dp), el de
  /// una escalera o un ascensor con el borde gris. Ícono en verde (10,78
  /// sobre la habitación) o en texto principal (14,28).
  void _pintarMarca(Canvas canvas, MarcaTramo marca, Offset centro) {
    final destino = marca == MarcaTramo.destino;
    final cuadro = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: centro,
        width: FormasApp.cuadroMarcaRuta,
        height: FormasApp.cuadroMarcaRuta,
      ),
      const Radius.circular(FormasApp.radioCampo),
    );
    pintarRelieve(
      canvas,
      Path()..addRRect(cuadro),
      elevacion: 0,
      relleno: estilo.planoHabitacion,
      borde: BorderSide(
        color: destino ? estilo.hecho : estilo.borde,
        width: destino ? FormasApp.grosorFoco : FormasApp.grosorLinea,
      ),
    );
    final icono = marca.icono;
    final texto = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icono.codePoint),
        style: TextStyle(
          fontFamily: icono.fontFamily,
          package: icono.fontPackage,
          fontSize: FormasApp.iconoChico,
          height: 1,
          color: destino ? estilo.hecho : estilo.textoPrincipal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    texto.paint(canvas, centro - Offset(texto.width / 2, texto.height / 2));
    texto.dispose();
  }

  @override
  bool shouldRepaint(_PintorRuta anterior) =>
      anterior.estilo != estilo ||
      !identical(anterior.desde, desde) ||
      !identical(anterior.hasta, hasta) ||
      anterior.cambio != cambio ||
      !identical(anterior.tramos, tramos);
}

/// La capa del cabezal: lo mueve (MovimientoCabezal) y lo dibuja a lo largo
/// de la ruta.
class _CapaCabezal extends StatefulWidget {
  const _CapaCabezal({
    required this.tramos,
    required this.actual,
    required this.avance,
    required this.tamano,
    required this.estilo,
  });

  final List<TramoRuta> tramos;
  final int actual;
  final double avance;
  final Size tamano;
  final EstiloApp estilo;

  @override
  State<_CapaCabezal> createState() => _CapaCabezalState();
}

class _CapaCabezalState extends State<_CapaCabezal>
    with SingleTickerProviderStateMixin {
  late _Trazado _trazado;
  late final MovimientoCabezal _movimiento;

  @override
  void initState() {
    super.initState();
    _trazado = _Trazado(widget.tramos, widget.tamano);
    _movimiento = MovimientoCabezal(
      vsync: this,
      valor: _trazado.distancia(widget.actual, widget.avance) ?? 0,
    );
  }

  @override
  void didUpdateWidget(covariant _CapaCabezal anterior) {
    super.didUpdateWidget(anterior);
    // Otra ruta, u otro tamaño (el teléfono se dio vuelta): salta.
    final otraRuta =
        !identical(anterior.tramos, widget.tramos) ||
        anterior.tamano != widget.tamano;
    if (otraRuta) _trazado = _Trazado(widget.tramos, widget.tamano);
    final objetivo = _trazado.distancia(widget.actual, widget.avance);
    if (objetivo == null) return;
    if (otraRuta || MovimientoApp.reducido(context)) {
      _movimiento.saltarA(objetivo);
    } else if (anterior.actual != widget.actual) {
      _movimiento.recorrerHasta(objetivo);
    } else if (objetivo != _movimiento.objetivo) {
      _movimiento.seguir(objetivo);
    }
  }

  @override
  void dispose() {
    _movimiento.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PintorCabezal(
      trazado: _trazado,
      movimiento: _movimiento,
      estilo: widget.estilo,
    ),
  );
}

class _PintorCabezal extends CustomPainter {
  _PintorCabezal({
    required this.trazado,
    required this.movimiento,
    required this.estilo,
  }) : super(repaint: movimiento);

  final _Trazado trazado;
  final MovimientoCabezal movimiento;
  final EstiloApp estilo;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = trazado.punto(movimiento.valor);
    if (centro == null) return;
    final circulo = Path()
      ..addOval(
        Rect.fromCircle(center: centro, radius: FormasApp.cabezalRuta / 2),
      );
    pintarRelieve(
      canvas,
      circulo,
      elevacion: 1,
      tamano: TamanoRelieve.chico,
      relleno: estilo.superficie,
      borde: BorderSide(
        color: estilo.acento,
        width: FormasApp.anilloCabezalRuta,
      ),
      sombraOscura: estilo.sombraOscura,
      sombraClara: estilo.sombraClara,
    );
  }

  @override
  bool shouldRepaint(_PintorCabezal anterior) =>
      !identical(anterior.trazado, trazado) ||
      anterior.movimiento != movimiento ||
      anterior.estilo != estilo;
}
