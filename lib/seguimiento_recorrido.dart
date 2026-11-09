import 'dart:ui' show Offset;

import 'design/design.dart';
import 'grilla_nav.dart';

// ═══════════════════════════════════════════════════════════════════════════
// De la ruta de la navegación al recorrido que se muestra
// ═══════════════════════════════════════════════════════════════════════════
//
// La línea sobre el plano, "Tramo 2 de 3" y la línea de tiempo necesitan los
// tramos de la ruta y en cuál va el usuario. La navegación no los cuenta: su
// ruta es una lista de celdas que arranca en el usuario y a la que le va
// sacando lo recorrido.
//
// Esta clase los arma SÓLO PARA MOSTRAR, mirando esa lista. No decide nada de
// la guía ni le cambia nada: ni la voz ni el seguimiento de la ruta pasan por
// acá.
//
//   · Un tramo es un tirón recto: de esquina a esquina, las mismas que la
//     navegación usa para decir "Girá" (SeguidorRuta).
//   · Si la lista nueva es el final de la anterior, el usuario avanzó: misma
//     ruta, otra celda.
//   · Si no, la ruta cambió (se recalculó): los tramos ya recorridos quedan
//     hechos y los que faltan son los de la ruta nueva.
//   · Otro destino u otra escalera ([actualizar], clave): se empieza de cero.
//
// La lista de tramos es la misma (identical) mientras la ruta no cambie:
// LineaRuta y LineaTiempo animan el avance sobre una misma lista y saltan
// con una lista nueva.

/// Sigue la ruta de la navegación y da el [Recorrido] para mostrar.
class SeguimientoRecorrido {
  Object? _clave;

  /// La última lista que llegó: si es la misma, no hay nada que recalcular.
  List<Offset>? _ultima;
  Recorrido? _recorrido;

  /// La ruta desde la última vez que cambió, con lo ya recorrido.
  List<Offset> _completa = const [];

  /// Índice en [_completa] de la celda donde termina cada tramo.
  List<int> _finales = const [];

  /// Cuántos tramos de [_tramos] son de rutas anteriores, ya recorridos.
  int _hechos = 0;

  /// Los hechos de antes y los de la ruta de ahora.
  List<TramoRuta> _tramos = const [];

  /// El recorrido para mostrar, o null sin ruta.
  ///
  /// [clave]: qué se está recorriendo (el destino y la escalera). [marca] y
  /// [descripcionMarca]: lo que hay al final de la ruta.
  Recorrido? actualizar({
    required Object? clave,
    required List<Offset>? ruta,
    required GrillaNav grilla,
    MarcaTramo? marca,
    String? descripcionMarca,
  }) {
    if (clave != _clave) {
      _clave = clave;
      _ultima = null;
      _recorrido = null;
      _completa = const [];
      _finales = const [];
      _hechos = 0;
      _tramos = const [];
    }
    if (ruta == null || ruta.isEmpty) return null;
    if (identical(ruta, _ultima) && _recorrido != null) return _recorrido;
    _ultima = ruta;

    var recorridas = _completa.length - ruta.length;
    if (recorridas < 0 ||
        _completa.isEmpty ||
        !_esElFinalDe(ruta, recorridas)) {
      _empezarRuta(ruta, grilla, marca, descripcionMarca);
      recorridas = 0;
    }
    return _recorrido = _enCelda(recorridas);
  }

  /// Si [ruta] es lo que queda de la ruta entera después de [recorridas]
  /// celdas.
  bool _esElFinalDe(List<Offset> ruta, int recorridas) {
    for (var i = 0; i < ruta.length; i++) {
      if (ruta[i] != _completa[recorridas + i]) return false;
    }
    return true;
  }

  void _empezarRuta(
    List<Offset> ruta,
    GrillaNav grilla,
    MarcaTramo? marca,
    String? descripcionMarca,
  ) {
    // Lo ya recorrido sigue hecho: los tramos anteriores al actual.
    final hechos = _tramos.take(_recorrido?.actual ?? 0).toList();
    _completa = ruta;
    _finales = _finalesDeTramo(ruta);
    _hechos = hechos.length;
    final nuevos = <TramoRuta>[];
    var inicio = 0;
    for (final (i, fin) in _finales.indexed) {
      final ultimo = i == _finales.length - 1;
      final puntos = ruta.sublist(inicio, fin + 1);
      nuevos.add(
        TramoRuta(
          metros: _metros(puntos, grilla),
          puntos: puntos,
          marca: ultimo ? marca : null,
          descripcionMarca: ultimo ? descripcionMarca : null,
        ),
      );
      inicio = fin;
    }
    _tramos = List.unmodifiable([...hechos, ...nuevos]);
  }

  /// Dónde termina cada tramo: en cada esquina y en la última celda.
  static List<int> _finalesDeTramo(List<Offset> ruta) {
    Offset direccion(int i) {
      final paso = ruta[i + 1] - ruta[i];
      return Offset(paso.dx.sign, paso.dy.sign);
    }

    return [
      for (var i = 1; i < ruta.length - 1; i++)
        if (direccion(i - 1) != direccion(i)) i,
      ruta.length - 1,
    ];
  }

  static double _metros(List<Offset> puntos, GrillaNav g) {
    var metros = 0.0;
    for (var i = 1; i < puntos.length; i++) {
      final paso = puntos[i] - puntos[i - 1];
      metros += Offset(paso.dx * g.metrosX, paso.dy * g.metrosY).distance;
    }
    return metros;
  }

  /// El recorrido con el usuario en la celda [recorridas] de la ruta. Justo
  /// en una esquina ya va en el tramo siguiente; en la última celda, al final
  /// del último.
  Recorrido _enCelda(int recorridas) {
    var tramo = 0;
    while (tramo < _finales.length - 1 && recorridas >= _finales[tramo]) {
      tramo++;
    }
    final inicio = tramo == 0 ? 0 : _finales[tramo - 1];
    final fin = _finales[tramo];
    return Recorrido(
      tramos: _tramos,
      tramoActual: _hechos + tramo,
      avance: fin > inicio ? (recorridas - inicio) / (fin - inicio) : 1,
    );
  }
}
