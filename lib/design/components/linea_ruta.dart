import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';

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
// ─── Cabezal ───
// Va sobre la ruta, a lo largo de la línea (PathMetrics): al principio del
// tramo actual más lo que se avanzó en él. Así, la fase 3 lo puede llevar de
// un tramo al otro recorriendo la ruta. Se dibuja en su propia capa: el
// plano y la ruta van en un RepaintBoundary y no se repintan cuando el
// cabezal se mueve.
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
class LineaRuta extends StatelessWidget {
  const LineaRuta({
    super.key,
    required this.tramos,
    required this.tramoActual,
    this.avance = 0,
  });

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
    final camino = Path();
    var antes = 0.0;
    var largoActual = 0.0;
    var hayPuntos = false;
    for (var i = 0; i < tramos.length; i++) {
      final largo = _largo(tramos[i].puntos, tamano);
      if (i < r.actual) antes += largo;
      if (i == r.actual) largoActual = largo;
      // Una sola línea con todos los tramos: si el primer punto de un tramo
      // no coincide con el último del anterior, la ruta los une.
      for (final p in tramos[i].puntos) {
        final punto = _aPixeles(p, tamano);
        if (hayPuntos) {
          camino.lineTo(punto.dx, punto.dy);
        } else {
          camino.moveTo(punto.dx, punto.dy);
          hayPuntos = true;
        }
      }
    }
    if (!hayPuntos) return null;
    final metricas = camino.computeMetrics().toList();
    if (metricas.isEmpty) return null;
    final metrica = metricas.first;
    final distancia = (antes + largoActual * r.avanceAcotado).clamp(
      0.0,
      metrica.length,
    );
    return metrica.getTangentForOffset(distancia)?.position;
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final r = _recorrido;
    return Semantics(
      container: true,
      label: resumen,
      excludeSemantics: true,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: _PintorRuta(recorrido: r, estilo: e),
              ),
            ),
            CustomPaint(
              painter: _PintorCabezal(recorrido: r, estilo: e),
            ),
          ],
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

class _PintorRuta extends CustomPainter {
  const _PintorRuta({required this.recorrido, required this.estilo});

  final Recorrido recorrido;
  final EstiloApp estilo;

  double _grosor(EstadoTramo estado) => estado == EstadoTramo.actual
      ? FormasApp.grosorRutaActual
      : FormasApp.grosorRuta;

  Paint _trazo(double grosor, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = grosor
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final tramos = recorrido.tramos;
    final caminos = [for (final t in tramos) _caminoDe(t.puntos, size)];

    // Primero todas las ranuras, así un trazo nunca queda debajo de la
    // ranura del tramo de al lado.
    for (var i = 0; i < tramos.length; i++) {
      if (tramos[i].puntos.length < 2) continue;
      canvas.drawPath(
        caminos[i],
        _trazo(
          _grosor(recorrido.estadoDe(i)) + 2 * FormasApp.bordeRanura,
          estilo.rutaRanura,
        ),
      );
    }
    // Los trazos: el actual al final, encima de los demás.
    final orden = [
      for (var i = 0; i < tramos.length; i++)
        if (i != recorrido.actual) i,
      if (tramos.isNotEmpty) recorrido.actual,
    ];
    for (final i in orden) {
      if (tramos[i].puntos.length < 2) continue;
      final estado = recorrido.estadoDe(i);
      final grosor = _grosor(estado);
      switch (estado) {
        case EstadoTramo.hecho:
          canvas.drawPath(caminos[i], _trazo(grosor, estilo.hecho));
        case EstadoTramo.actual:
          canvas.drawPath(caminos[i], _trazo(grosor, estilo.acento));
        case EstadoTramo.siguiente:
          canvas.drawPath(
            _punteado(caminos[i], FormasApp.guionRuta, FormasApp.huecoRuta),
            _trazo(grosor, estilo.siguiente),
          );
      }
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
      anterior.recorrido.actual != recorrido.actual ||
      !identical(anterior.recorrido.tramos, recorrido.tramos);
}

class _PintorCabezal extends CustomPainter {
  const _PintorCabezal({required this.recorrido, required this.estilo});

  final Recorrido recorrido;
  final EstiloApp estilo;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = LineaRuta.posicionCabezal(
      recorrido.tramos,
      recorrido.tramoActual,
      recorrido.avance,
      size,
    );
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
      anterior.estilo != estilo ||
      anterior.recorrido.actual != recorrido.actual ||
      anterior.recorrido.avanceAcotado != recorrido.avanceAcotado ||
      !identical(anterior.recorrido.tramos, recorrido.tramos);
}
