import 'dart:math';

import 'grilla_nav.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// HISTÉRESIS DE CELDA
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Estabiliza en qué celda de la grilla está el usuario. Sin esto, cuando el
/// usuario está cerca del borde entre dos celdas la posición oscila entre
/// ellas con cada lectura BLE, y eso da saltos en el mapa e indicaciones de
/// voz alternadas ("girá a la derecha" / "girá a la izquierda") en segundos.
/// Una celda nueva se confirma recién tras varios ciclos seguidos en ella, y
/// mientras tanto queda la anterior.
///
/// ── DEL OTRO LADO DE UNA PARED ──────────────────────────────────────────────
///
/// Con las zonas bloqueadas por el centro de la celda, una pared angosta (20
/// cm) no bloquea ninguna celda: sólo corta la conexión entre las de los dos
/// lados. Antes se bloqueaban las celdas que tocaba, y eso dejaba un colchón:
/// para pasar al otro lado, la medición tenía que caer ~0,65 m más allá de la
/// pared. Ahora le alcanza con salir del polígono, y caminando se confirma
/// en un ciclo: cualquier ciclo ruidoso del otro lado hacía saltar al
/// usuario atrás de la pared. Si el salto duraba más que el tiempo fuera de
/// ruta, la ruta se recalculaba desde el lado equivocado.
///
/// Por eso, si la candidata está del otro lado de una pared ([_cruzaPared])
/// se piden más ciclos (`ciclosPared`), y se cuentan los ciclos seguidos DEL
/// OTRO LADO, en cualquier celda, no en la misma: con celdas de 0,5 m el
/// ruido reparte las mediciones entre varias celdas de ese lado, y contar
/// por celda reiniciaba el conteo a cada rato (en simulación, con 8 ciclos
/// una corrección real llegaba a tardar 35 s).
///
/// Y durante [ciclosParaDeshacer] ciclos después de cruzar, volver al lado de
/// antes cuesta lo normal. Sin esto, salir de un cruce falso costaría lo
/// mismo que entrar: hay menos cruces, pero cada uno dura más, y en
/// simulación salían MÁS recálculos de ruta que antes. Deshacer no abre otra
/// ventana (si no, el punto podría ir y venir a ritmo de ruido).
///
/// Los movimientos entre celdas del mismo lado (caminar, doblar una esquina,
/// pasar por una puerta) no cambian: sólo paga la demora una posición que
/// tiene que corregirse a través de una pared, es decir, que estaba del lado
/// equivocado.
class HisteresisCelda {
  final GrillaNav grilla;

  /// true si la celda (ix, iy) está en una zona prohibida (su centro cae
  /// adentro de una). Ver `ResolvedorCaminos.esZonaProhibida`.
  final bool Function(int ix, int iy) prohibida;

  /// true si se puede pasar de la celda (x1, y1) a su vecina (x2, y2) sin
  /// atravesar una pared. Ver `ResolvedorCaminos.conectadas`.
  final bool Function(int x1, int y1, int x2, int y2) conectadas;

  /// Ciclos (~2 s a ~5,5 ciclos por segundo) después de cruzar una pared en
  /// los que volver al lado de antes cuesta lo normal.
  static const int ciclosParaDeshacer = 11;

  /// Rodeo (m) a partir del cual dos celdas se consideran separadas por una
  /// pared: si para ir caminando de una a la otra hay que andar más que esto
  /// de más, están de lados distintos. Así, una puerta cerca o una columna
  /// chica no cuentan como pared.
  static const double rodeoMaxMetros = 2.0;

  /// Más allá de esto (m, en cruz) no se busca: un salto así no es ruido de
  /// una pared, y la búsqueda crecería sin necesidad.
  static const double distanciaMaxMetros = 6.0;

  HisteresisCelda({
    required this.grilla,
    required this.prohibida,
    required this.conectadas,
  });

  ({int ix, int iy})? _celdaConfirmada;

  ({int ix, int iy})? _celdaCandidata;
  int _ciclosEnCandidata = 0;

  /// Si la candidata actual está del otro lado de una pared respecto de la
  /// confirmada. Se calcula una vez por candidata nueva.
  bool _candidataCruzaPared = false;

  /// Celda confirmada antes del último cruce de una pared, y cuántos ciclos
  /// quedan para poder volver a su lado sin la espera de la pared.
  ({int ix, int iy})? _celdaAntesDelCruce;
  int _ciclosRestantesDeshacer = 0;

  /// Propone la celda (ix, iy). Devuelve la celda confirmada vigente.
  ///
  /// [ciclos]: ciclos seguidos para confirmar una celda del mismo lado.
  /// [ciclosPared]: ciclos seguidos del otro lado de una pared para cruzarla.
  /// Null: no se distinguen las paredes (sin plano, o con la restricción de
  /// zonas apagada) y todo se confirma con [ciclos].
  ({int ix, int iy})? actualizar(int ix, int iy, {required int ciclos, int? ciclosPared}) {
    final confirmada = _celdaConfirmada;
    if (confirmada == null) {
      _celdaConfirmada = (ix: ix, iy: iy);
      return _celdaConfirmada;
    }

    // La ventana se lee ANTES de descontar este ciclo: dura exactamente
    // [ciclosParaDeshacer] ciclos después del cruce.
    final enVentana = _ciclosRestantesDeshacer > 0;
    if (enVentana) _ciclosRestantesDeshacer--;

    if (ix == confirmada.ix && iy == confirmada.iy) {
      _olvidarCandidata();
      return confirmada;
    }

    final nueva = (ix: ix, iy: iy);
    final mismaCelda =
        _celdaCandidata?.ix == ix && _celdaCandidata?.iy == iy;
    final cruza = ciclosPared != null &&
        (mismaCelda ? _candidataCruzaPared : _cruzaPared(confirmada, nueva));

    // Del otro lado de una pared se cuenta el LADO: si la candidata anterior
    // también estaba del otro lado, el conteo sigue aunque cambie de celda.
    if (mismaCelda || (cruza && _celdaCandidata != null && _candidataCruzaPared)) {
      _ciclosEnCandidata++;
    } else {
      _ciclosEnCandidata = 1;
    }
    _celdaCandidata = nueva;
    _candidataCruzaPared = cruza;

    // ¿Vuelve al lado en el que estaba antes del último cruce?
    final antes = _celdaAntesDelCruce;
    final deshace =
        cruza && enVentana && antes != null && !_cruzaPared(antes, nueva);

    final requeridos = (cruza && !deshace) ? ciclosPared : ciclos;
    if (_ciclosEnCandidata >= requeridos) {
      if (deshace) {
        _celdaAntesDelCruce = null;
        _ciclosRestantesDeshacer = 0;
      } else if (cruza) {
        _celdaAntesDelCruce = confirmada;
        _ciclosRestantesDeshacer = ciclosParaDeshacer;
      }
      _celdaConfirmada = nueva;
      _olvidarCandidata();
    }
    return _celdaConfirmada;
  }

  void resetear() {
    _celdaConfirmada = null;
    _olvidarCandidata();
    _celdaAntesDelCruce = null;
    _ciclosRestantesDeshacer = 0;
  }

  void _olvidarCandidata() {
    _celdaCandidata = null;
    _ciclosEnCandidata = 0;
    _candidataCruzaPared = false;
  }

  /// true si [b] está del otro lado de una pared respecto de [a]: no se llega
  /// caminando (en cruz, como el pathfinder, por celdas libres y sin
  /// atravesar paredes) en |dx| + |dy| pasos más [rodeoMaxMetros].
  ///
  /// False si [a] está en una zona prohibida (no hay lado que cuidar, igual
  /// que en `RestriccionZonas`) o si [b] queda a más de [distanciaMaxMetros].
  bool _cruzaPared(({int ix, int iy}) a, ({int ix, int iy}) b) {
    final directo = (a.ix - b.ix).abs() + (a.iy - b.iy).abs();
    if (directo == 0) return false;
    final lado = min(
      grilla.tamCeldaX * grilla.metrosX,
      grilla.tamCeldaY * grilla.metrosY,
    );
    if (!(lado > 0)) return false;
    if (directo * lado > distanciaMaxMetros) return false;
    if (prohibida(a.ix, a.iy)) return false;

    final pasos = directo + (rodeoMaxMetros / lado).ceil();
    final destino = b.ix * grilla.celdasY + b.iy;
    final visitadas = <int>{a.ix * grilla.celdasY + a.iy};
    var frente = <(int, int)>[(a.ix, a.iy)];
    for (int n = 0; n < pasos && frente.isNotEmpty; n++) {
      final siguiente = <(int, int)>[];
      for (final (x, y) in frente) {
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= grilla.celdasX) continue;
          if (ny < 0 || ny >= grilla.celdasY) continue;
          if (prohibida(nx, ny)) continue;
          if (!conectadas(x, y, nx, ny)) continue;
          final i = nx * grilla.celdasY + ny;
          if (i == destino) return false;
          if (visitadas.add(i)) siguiente.add((nx, ny));
        }
      }
      frente = siguiente;
    }
    return true;
  }
}
