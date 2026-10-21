import 'dart:math';
import 'dart:ui';

import 'grilla_nav.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// POSICIÓN FUERA DE LAS ZONAS PROHIBIDAS
/// ═══════════════════════════════════════════════════════════════════════════
///
/// La multilateración no sabe nada del plano: con el error del BLE (1,5 m o
/// más) la posición cae seguido adentro de una zona no transitable (un aula
/// cerrada, una columna, un cantero), donde el usuario no puede estar. Y todo
/// lo que viene después lo arrastra: el mapa lo dibuja adentro de la pared,
/// la ruta sale de la celda libre que encuentre el pathfinder y la indicación
/// se calcula desde un lugar imposible.
///
/// Acá esa posición se lleva al CENTRO de la celda transitable que mejor
/// coincide:
///
///  • La MÁS CERCANA a la posición medida (distancia a su centro)...
///  • ...prefiriendo las del lado en el que ya estaba el usuario. Una celda a
///    la que no se llega caminando desde la posición anterior sin salir de
///    [radioLocalMetros] ni atravesar una pared (por ejemplo, el pasillo del
///    otro lado) paga [penalizacionOtroLadoMetros] extra. Sin esto, con la
///    medición en el medio de una pared la posición saltaría de un pasillo al
///    otro ciclo a ciclo, y con la medición adentro de un bloque grueso
///    pasaría al lado opuesto apenas cruzara la mitad.
///
/// CUÁNDO SE CORRIGE: cuando la medición cae en una celda bloqueada (su
/// centro está adentro de una zona) o adentro del polígono de una zona
/// aunque su celda esté libre. Lo segundo es el caso de la pared angosta:
/// una pared de 20 cm no tapa ningún centro, así que las celdas de los dos
/// lados quedan libres y, con la medición en el medio de la pared, el ruido
/// la haría pasar de una celda a la otra ciclo a ciclo. Tratándola como
/// "adentro de una zona", decide la preferencia por el lado.
///
/// La penalización sólo decide cuando la medición cae ADENTRO de una zona: si
/// cae en un lugar transitable se usa tal cual, esté del lado de la pared
/// que esté. Por eso no puede dejar al usuario encerrado del lado
/// equivocado: alcanza con que la medición salga de la zona.
///
/// POR QUÉ AL CENTRO: la posición del usuario es una celda. Antes se
/// devolvía el punto de la celda más cercano a la medición, para que la
/// posición se deslizara pegada al borde de la zona. Pero ahora una celda
/// libre puede tener parte de una zona adentro (sólo su centro tiene que
/// quedar afuera), y ese punto podía caer en la zona. El centro de una celda
/// libre está afuera de toda zona por definición.
class RestriccionZonas {
  final GrillaNav grilla;

  /// true si la celda (ix, iy) está en una zona prohibida (su centro cae
  /// adentro de una).
  final bool Function(int ix, int iy) prohibida;

  /// true si se puede pasar de la celda (x1, y1) a su vecina (x2, y2) sin
  /// atravesar una pared (ver `ResolvedorCaminos.conectadas`).
  final bool Function(int x1, int y1, int x2, int y2) conectadas;

  /// true si el punto cae adentro del polígono de alguna zona.
  final bool Function(Offset p) enZona;

  /// Hasta dónde (m, caminando por celdas transitables) se considera que una
  /// celda está "del mismo lado" que la posición anterior.
  static const double radioLocalMetros = 3.0;

  /// Costo extra (m) de una celda que no está del mismo lado. Para pasar al
  /// otro lado de una zona, la medición tiene que quedar esto más cerca de
  /// ese lado que del propio.
  static const double penalizacionOtroLadoMetros = 1.5;

  /// Más allá de esto (m) no se busca: un plano sin ninguna celda transitable
  /// cerca de la medición está mal cargado, y la posición se deja como vino.
  static const double radioBusquedaMetros = 15.0;

  RestriccionZonas({
    required this.grilla,
    required this.prohibida,
    required this.conectadas,
    required this.enZona,
  });

  /// Lado (m) de la celda más chica de la grilla. Suele ser el lado de celda
  /// del piso, salvo en las grillas uniformes de respaldo de [GrillaNav].
  double get _ladoCeldaMetros => min(
        grilla.tamCeldaX * grilla.metrosX,
        grilla.tamCeldaY * grilla.metrosY,
      );

  /// [p] si cae en un lugar transitable. Si cae en una zona prohibida, el
  /// centro de la celda transitable que mejor coincide (ver arriba).
  ///
  /// [previa]: la última posición ya restringida, para preferir su lado.
  Offset restringir(Offset p, {Offset? previa}) {
    final ix = grilla.indiceX(p.dx);
    final iy = grilla.indiceY(p.dy);
    if (!prohibida(ix, iy) && !enZona(p)) return p;

    final lado = _ladoCeldaMetros;
    if (!(lado > 0)) return p;
    final locales = previa == null ? null : _celdasLocales(previa, lado);

    final radioMax = (radioBusquedaMetros / lado).ceil();
    Offset? mejor;
    double costoMejor = double.infinity;
    // Se arranca por la celda de p (anillo 0): con la medición adentro de
    // una pared angosta, su propia celda puede estar libre y ser la mejor.
    for (int r = 0; r <= radioMax; r++) {
      // Entre la celda de p y una del anillo r hay r - 1 celdas enteras: si
      // eso ya supera al mejor costo, ningún anillo más lejano puede ganar.
      if ((r - 1) * lado > costoMejor) break;
      for (int dx = -r; dx <= r; dx++) {
        for (int dy = -r; dy <= r; dy++) {
          if (dx.abs() != r && dy.abs() != r) continue; // sólo el anillo
          final cx = ix + dx, cy = iy + dy;
          if (cx < 0 || cx >= grilla.celdasX) continue;
          if (cy < 0 || cy >= grilla.celdasY) continue;
          if (prohibida(cx, cy)) continue;
          final centro = Offset(grilla.centroX(cx), grilla.centroY(cy));
          var costo = _metros(p, centro);
          if (locales != null && !locales.contains(cx * grilla.celdasY + cy)) {
            costo += penalizacionOtroLadoMetros;
          }
          if (costo < costoMejor) {
            costoMejor = costo;
            mejor = centro;
          }
        }
      }
    }
    return mejor ?? p;
  }

  /// Celdas transitables a las que se llega desde la celda de [previa]
  /// caminando (en cruz, como el pathfinder, y sin atravesar paredes) sin
  /// pasar de [radioLocalMetros]. Null si [previa] cae en una zona: entonces
  /// no hay "lado" que preferir.
  Set<int>? _celdasLocales(Offset previa, double lado) {
    final x0 = grilla.indiceX(previa.dx);
    final y0 = grilla.indiceY(previa.dy);
    if (prohibida(x0, y0)) return null;

    final pasos = (radioLocalMetros / lado).ceil();
    final visitadas = <int>{x0 * grilla.celdasY + y0};
    var frente = <(int, int)>[(x0, y0)];
    for (int n = 0; n < pasos && frente.isNotEmpty; n++) {
      final siguiente = <(int, int)>[];
      for (final (x, y) in frente) {
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= grilla.celdasX) continue;
          if (ny < 0 || ny >= grilla.celdasY) continue;
          if (prohibida(nx, ny)) continue;
          // Una pared angosta no bloquea celdas: sin esto, los dos lados
          // quedarían "del mismo lado".
          if (!conectadas(x, y, nx, ny)) continue;
          if (visitadas.add(nx * grilla.celdasY + ny)) siguiente.add((nx, ny));
        }
      }
      frente = siguiente;
    }
    return visitadas;
  }

  double _metros(Offset a, Offset b) {
    final dx = (a.dx - b.dx) * grilla.metrosX;
    final dy = (a.dy - b.dy) * grilla.metrosY;
    return sqrt(dx * dx + dy * dy);
  }
}
