import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/material.dart';
import 'zona_model.dart';
import 'grilla_nav.dart';

// ─── MIN-HEAP (reemplaza HeapPriorityQueue de package:collection) ────────────
//
// Implementación propia para no depender del paquete externo 'collection'.
// Heap binario mínimo con comparador por f-score del nodo A*.
class _MinHeap<T> {
  final int Function(T a, T b) _cmp;
  final List<T> _data = [];

  _MinHeap(this._cmp);

  bool get isNotEmpty => _data.isNotEmpty;

  void add(T item) {
    _data.add(item);
    _bubbleUp(_data.length - 1);
  }

  T removeFirst() {
    final top = _data[0];
    final last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _sinkDown(0);
    }
    return top;
  }

  void _bubbleUp(int i) {
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_cmp(_data[i], _data[parent]) < 0) {
        final tmp = _data[i]; _data[i] = _data[parent]; _data[parent] = tmp;
        i = parent;
      } else { break; }
    }
  }

  void _sinkDown(int i) {
    final n = _data.length;
    while (true) {
      int smallest = i;
      final l = 2 * i + 1, r = 2 * i + 2;
      if (l < n && _cmp(_data[l], _data[smallest]) < 0) smallest = l;
      if (r < n && _cmp(_data[r], _data[smallest]) < 0) smallest = r;
      if (smallest == i) break;
      final tmp = _data[i]; _data[i] = _data[smallest]; _data[smallest] = tmp;
      i = smallest;
    }
  }
}

// ─── NODO DE GRILLA ──────────────────────────────────────────────────────────

class _Nodo {
  final int x, y;
  double g = double.infinity;
  double h = 0;
  double get f => g + h;
  _Nodo? padre;
  bool visitado = false;
  bool esObstaculo = false;

  _Nodo(this.x, this.y);

  @override
  bool operator ==(Object other) => other is _Nodo && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

// ─── RESOLVEDOR DE CAMINOS ────────────────────────────────────────────────────

/// Resuelve caminos en un plano 2D evitando zonas poligonales no transitables.
/// El A* corre en un isolate separado para no bloquear la UI ni el BLE.
class ResolvedorCaminos {
  // Definición de la grilla (escala configurable por piso y por eje). De acá
  // salen la resolución (cantidad de celdas) y el paso (tamaño de celda
  // normalizado) en cada eje. La grilla puede ser rectangular.
  GrillaNav _grillaNav = GrillaNav();
  int get _resX => _grillaNav.celdasX;
  int get _resY => _grillaNav.celdasY;
  double get _pasoX => _grillaNav.tamCeldaX;
  double get _pasoY => _grillaNav.tamCeldaY;

  // 1 = sin poda extra de ancho de pasillo. Con celdas de 1 m una persona ya
  // cabe en una sola celda, así que no exigimos pasillos más anchos (eso
  // bloquearía pasillos reales angostos en una grilla tan gruesa).
  static const int _anchoPasillo = 1;

  late List<List<_Nodo>> _grilla;
  List<ZonaNoTransitable> _zonas = [];

  // ── Inicialización ──────────────────────────────────────────────────────────

  void inicializar(List<ZonaNoTransitable> zonas, {GrillaNav? grilla}) {
    _zonas = zonas;
    if (grilla != null) _grillaNav = grilla;
    _construirGrilla();
    _marcarObstaculos();
    _aplicarAnchoPasillo();
  }

  void _construirGrilla() {
    _grilla = List.generate(
      _resX,
      (x) => List.generate(_resY, (y) => _Nodo(x, y)),
    );
  }

  void _marcarObstaculos() {
    for (final zona in _zonas) {
      if (zona.vertices.length < 3) continue;

      double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
      for (final v in zona.vertices) {
        if (v.dx < minX) minX = v.dx;
        if (v.dy < minY) minY = v.dy;
        if (v.dx > maxX) maxX = v.dx;
        if (v.dy > maxY) maxY = v.dy;
      }

      final ixMin = max(0, (minX * _resX).floor());
      final iyMin = max(0, (minY * _resY).floor());
      final ixMax = min(_resX - 1, (maxX * _resX).ceil());
      final iyMax = min(_resY - 1, (maxY * _resY).ceil());

      for (int x = ixMin; x <= ixMax; x++) {
        for (int y = iyMin; y <= iyMax; y++) {
          final cx = (x + 0.5) * _pasoX;
          final cy = (y + 0.5) * _pasoY;
          if (_puntoEnPoligono(Offset(cx, cy), zona.vertices)) {
            _grilla[x][y].esObstaculo = true;
          }
        }
      }
    }
  }

  /// Elimina celdas transitables que no tienen espacio suficiente alrededor
  /// para que una persona pase (ancho mínimo = _anchoPasillo celdas).
  void _aplicarAnchoPasillo() {
    // Snapshot de obstáculos antes de modificar la grilla
    final obs = List.generate(
      _resX,
      (x) => List.generate(_resY, (y) => _grilla[x][y].esObstaculo),
    );

    for (int x = 0; x < _resX; x++) {
      for (int y = 0; y < _resY; y++) {
        if (obs[x][y]) continue;
        if (!_tieneEspacioSuficiente(obs, x, y)) {
          _grilla[x][y].esObstaculo = true;
        }
      }
    }
  }

  bool _tieneEspacioSuficiente(List<List<bool>> obs, int x, int y) {
    int libres(int dx, int dy) {
      int count = 0;
      for (int i = 1; i <= _anchoPasillo; i++) {
        final nx = x + dx * i, ny = y + dy * i;
        if (nx < 0 || nx >= _resX || ny < 0 || ny >= _resY) break;
        if (!obs[nx][ny]) { count++; } else { break; }
      }
      return count;
    }

    // Horizontal
    if (libres(-1, 0) + libres(1, 0) < _anchoPasillo - 1) return false;
    // Vertical
    if (libres(0, -1) + libres(0, 1) < _anchoPasillo - 1) return false;
    // Diagonal ↘
    if (libres(-1, -1) + libres(1, 1) < _anchoPasillo - 1) return false;
    // Diagonal ↙
    if (libres(1, -1) + libres(-1, 1) < _anchoPasillo - 1) return false;
    return true;
  }

  bool _puntoEnPoligono(Offset punto, List<Offset> vertices) {
    bool dentro = false;
    int j = vertices.length - 1;
    for (int i = 0; i < vertices.length; i++) {
      final vi = vertices[i];
      final vj = vertices[j];
      if (((vi.dy > punto.dy) != (vj.dy > punto.dy)) &&
          (punto.dx <
              (vj.dx - vi.dx) * (punto.dy - vi.dy) / (vj.dy - vi.dy) +
                  vi.dx)) {
        dentro = !dentro;
      }
      j = i;
    }
    return dentro;
  }

  // ── Pathfinding ─────────────────────────────────────────────────────────────

  /// Encuentra el camino entre dos puntos en background (no bloquea la UI).
  /// Retorna null si alguno de los puntos está en un obstáculo o no hay camino.
  ///
  /// DIAGNÓSTICO: instrumentado con logs y un timeout duro. Si el A* dentro
  /// del isolate nunca resuelve (o tarda demasiado por una grilla mal
  /// configurada — celdas muy chicas sobre una escala muy grande), antes esto
  /// dejaba el `await` colgado para siempre y la UI mostraba "Calculando
  /// ruta..." indefinidamente sin ningún rastro en consola. Ahora:
  ///  1. Se loguea el tamaño de la grilla ANTES de lanzar el isolate — si
  ///     resX*resY es enorme (p. ej. escala configurada en cm en vez de m),
  ///     vas a verlo acá y es la causa más probable de una demora extrema.
  ///  2. Si el compute() no vuelve en 8 s, se cancela con TimeoutException en
  ///     vez de esperar para siempre, y ese timeout se loguea explícitamente.
  Future<List<Offset>?> encontrarCamino(Offset inicio, Offset destino) async {
    final args = _PathArgs(
      resX: _resX,
      resY: _resY,
      pasoX: _pasoX,
      pasoY: _pasoY,
      obstaculos: _exportarObstaculos(),
      inicio: inicio,
      destino: destino,
    );

    final totalCeldas = _resX * _resY;
    final inicioReloj = DateTime.now();
    debugPrint(
      '[Pathfinder] Lanzando compute(): grilla ${_resX}x$_resY '
      '($totalCeldas celdas), inicio=$inicio, destino=$destino',
    );

    try {
      final resultado = await compute(_aStarIsolate, args).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint(
            '[Pathfinder] TIMEOUT: el isolate no respondió en 8 s. '
            'Grilla de $totalCeldas celdas — si este número es muy grande '
            '(cientos de miles+), revisá escalaX/escalaY/tamCeldaMetros del '
            'piso en la pantalla de configuración: probablemente hay un '
            'error de unidades (p. ej. metros cargados como centímetros).',
          );
          throw TimeoutException('A* no respondió en 8 s');
        },
      );
      final ms = DateTime.now().difference(inicioReloj).inMilliseconds;
      debugPrint(
        '[Pathfinder] compute() resolvió en ${ms}ms → '
        '${resultado == null ? "SIN RUTA (null)" : "${resultado.length} celdas"}',
      );
      return resultado;
    } catch (e) {
      final ms = DateTime.now().difference(inicioReloj).inMilliseconds;
      debugPrint('[Pathfinder] compute() falló a los ${ms}ms: $e');
      rethrow;
    }
  }

  List<bool> _exportarObstaculos() {
    final lista = List<bool>.filled(_resX * _resY, false);
    for (int x = 0; x < _resX; x++) {
      for (int y = 0; y < _resY; y++) {
        lista[x * _resY + y] = _grilla[x][y].esObstaculo;
      }
    }
    return lista;
  }

  // ── Progreso en ruta ────────────────────────────────────────────────────────

  static const double _radioAlcanceWaypoint = 0.04;
  int _indiceWaypointActual = 0;

  /// Actualiza el progreso en la ruta y retorna el estado actual.
  /// Llamar en cada ciclo con la posición del usuario.
  /// Retorna null si el camino está vacío o ya se llegó al destino.
  EstadoRuta? actualizarProgreso(List<Offset> camino, Offset posUsuario) {
    if (camino.isEmpty) return null;

    if (_indiceWaypointActual >= camino.length) {
      _indiceWaypointActual = camino.length - 1;
    }

    while (_indiceWaypointActual < camino.length - 1) {
      final wp = camino[_indiceWaypointActual];
      final dist = (posUsuario - wp).distance;
      if (dist <= _radioAlcanceWaypoint) {
        _indiceWaypointActual++;
      } else {
        break;
      }
    }

    final wpActual = camino[_indiceWaypointActual];
    final esDestino = _indiceWaypointActual == camino.length - 1;
    final distWp = (posUsuario - wpActual).distance;

    double distRestante = distWp;
    for (int i = _indiceWaypointActual; i < camino.length - 1; i++) {
      distRestante += (camino[i + 1] - camino[i]).distance;
    }

    return EstadoRuta(
      proximoWaypoint: wpActual,
      indiceWaypoint: _indiceWaypointActual,
      totalWaypoints: camino.length,
      distanciaAlProximoWaypoint: distWp,
      distanciaTotalRestante: distRestante,
      llegaAlDestino: esDestino && distWp <= _radioAlcanceWaypoint,
    );
  }

  void resetearProgreso() => _indiceWaypointActual = 0;
}

// ─── ISOLATE: ARGUMENTOS Y FUNCIÓN DE NIVEL SUPERIOR ─────────────────────────

class _PathArgs {
  final int resX;
  final int resY;
  final double pasoX;
  final double pasoY;
  final List<bool> obstaculos;
  final Offset inicio;
  final Offset destino;

  _PathArgs({
    required this.resX,
    required this.resY,
    required this.pasoX,
    required this.pasoY,
    required this.obstaculos,
    required this.inicio,
    required this.destino,
  });
}

/// Función de nivel superior requerida por compute() — no puede ser un método.
/// Ejecuta el A* completo dentro del isolate, sin tocar el hilo principal.
///
/// Movimiento en 4 direcciones (N/S/E/O, sin diagonales) para que el camino
/// siga las cuadrículas de la grilla, con penalización de giro para minimizar
/// curvas. La grilla puede ser rectangular (resX × resY) y cada celda mide ~1 m
/// en cada eje, así que el costo de cada paso es uniforme (1 celda ≈ 1 m).
/// Devuelve TODAS las celdas del camino (sin simplificar) para que el
/// `MapaWidget` pueda pintar cada una.
List<Offset>? _aStarIsolate(_PathArgs args) {
  final resX = args.resX;
  final resY = args.resY;
  final pasoX = args.pasoX;
  final pasoY = args.pasoY;
  final obs = args.obstaculos;

  int clampX(int v) => v < 0 ? 0 : (v >= resX ? resX - 1 : v);
  int clampY(int v) => v < 0 ? 0 : (v >= resY ? resY - 1 : v);

  // floor() para alinear con GrillaNav.indice (que usa el MapaWidget al pintar).
  final ix0 = clampX((args.inicio.dx * resX).floor());
  final iy0 = clampY((args.inicio.dy * resY).floor());
  final gx0 = clampX((args.destino.dx * resX).floor());
  final gy0 = clampY((args.destino.dy * resY).floor());

  // Si el origen o destino caen en un obstáculo, buscar la celda libre más
  // cercana (BFS en anillos). Evita el null inmediato cuando la posición
  // trilaterada cae en el borde de una zona marcada.
  int ixLinear = ix0 * resY + iy0;
  int gxLinear = gx0 * resY + gy0;

  if (obs[ixLinear]) {
    ixLinear = _celdaLibreCercana(ix0, iy0, obs, resX, resY);
    if (ixLinear < 0) return null;
  }
  if (obs[gxLinear]) {
    gxLinear = _celdaLibreCercana(gx0, gy0, obs, resX, resY);
    if (gxLinear < 0) return null;
  }

  final ix = ixLinear ~/ resY;
  final iy = ixLinear % resY;
  final gx = gxLinear ~/ resY;
  final gy = gxLinear % resY;

  // Grilla local al isolate
  final grilla = List.generate(
    resX,
    (x) => List.generate(resY, (y) {
      final n = _Nodo(x, y);
      n.esObstaculo = obs[x * resY + y];
      return n;
    }),
  );

  final nInicio = grilla[ix][iy];
  final nDestino = grilla[gx][gy];

  // Costos en "celdas" (cada celda ≈ 1 m en ambos ejes): paso recto = 1.
  // Penalización por cada giro de 90° = 4 celdas (~4 m): A* prefiere un rodeo
  // de hasta 4 celdas antes que sumar una curva → mínimas curvas.
  const double costoPaso = 1.0;
  const double costoGiro = 4.0;

  // Heurística Manhattan en celdas: coherente con el movimiento en 4 direcciones.
  double heuristica(_Nodo a, _Nodo b) =>
      ((a.x - b.x).abs() + (a.y - b.y).abs()).toDouble();

  nInicio.g = 0;
  nInicio.h = heuristica(nInicio, nDestino);

  final abierta = _MinHeap<_Nodo>((a, b) => a.f.compareTo(b.f));
  abierta.add(nInicio);

  // Vecinos en 4 direcciones: Este, Oeste, Sur, Norte.
  const dirs = [
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1],
  ];

  while (abierta.isNotEmpty) {
    final actual = abierta.removeFirst();
    if (actual.visitado) continue;
    actual.visitado = true;

    if (actual == nDestino) {
      return _reconstruir(actual, pasoX, pasoY);
    }

    for (final d in dirs) {
      final nx = actual.x + d[0];
      final ny = actual.y + d[1];
      if (nx < 0 || nx >= resX || ny < 0 || ny >= resY) continue;
      final vecino = grilla[nx][ny];
      if (vecino.visitado || vecino.esObstaculo) continue;

      final penGiro = _penalizacionGiro(actual, d[0], d[1], costoGiro);
      final gTentativo = actual.g + costoPaso + penGiro;

      if (gTentativo < vecino.g) {
        vecino.padre = actual;
        vecino.g = gTentativo;
        vecino.h = heuristica(vecino, nDestino);
        abierta.add(vecino);
      }
    }
  }

  return null;
}

/// Devuelve el índice lineal (x*resY+y) de la celda libre más cercana a
/// (x0,y0). Busca en anillos cuadrados de radio creciente hasta r=10 celdas.
/// Retorna -1 si no encuentra ninguna celda libre en ese radio.
int _celdaLibreCercana(int x0, int y0, List<bool> obs, int resX, int resY) {
  for (int r = 0; r <= 10; r++) {
    for (int dx = -r; dx <= r; dx++) {
      for (int dy = -r; dy <= r; dy++) {
        if (dx.abs() != r && dy.abs() != r) continue; // solo el borde del anillo
        final nx = x0 + dx;
        final ny = y0 + dy;
        if (nx < 0 || nx >= resX || ny < 0 || ny >= resY) continue;
        if (!obs[nx * resY + ny]) return nx * resY + ny;
      }
    }
  }
  return -1;
}

/// Penaliza los cambios de dirección respecto del paso anterior (giros de 90°)
/// para minimizar la cantidad de curvas del camino.
double _penalizacionGiro(_Nodo actual, int dx2, int dy2, double costoGiro) {
  if (actual.padre == null) return 0.0;
  final dx1 = actual.x - actual.padre!.x;
  final dy1 = actual.y - actual.padre!.y;
  if (dx1 == dx2 && dy1 == dy2) return 0.0; // sigue recto
  return costoGiro;                          // giró 90°
}

List<Offset> _reconstruir(_Nodo destino, double pasoX, double pasoY) {
  final camino = <Offset>[];
  _Nodo? n = destino;
  while (n != null) {
    camino.add(Offset((n.x + 0.5) * pasoX, (n.y + 0.5) * pasoY));
    n = n.padre;
  }
  return camino.reversed.toList();
}

// ─── ESTADO DE RUTA ───────────────────────────────────────────────────────────

/// Resultado de actualizarProgreso(). Contiene todo lo necesario para generar
/// instrucciones de voz sin acceder al camino completo desde el exterior.
class EstadoRuta {
  final Offset proximoWaypoint;
  final int indiceWaypoint;
  final int totalWaypoints;
  final double distanciaAlProximoWaypoint;
  final double distanciaTotalRestante;
  final bool llegaAlDestino;

  const EstadoRuta({
    required this.proximoWaypoint,
    required this.indiceWaypoint,
    required this.totalWaypoints,
    required this.distanciaAlProximoWaypoint,
    required this.distanciaTotalRestante,
    required this.llegaAlDestino,
  });

  /// Distancia al próximo waypoint en metros (1 unidad = 50 m).
  double get distanciaMetros => distanciaAlProximoWaypoint * 50;

  /// Distancia total restante en metros.
  double get distanciaTotalMetros => distanciaTotalRestante * 50;

  /// Fracción del camino completada (0.0 = inicio, 1.0 = destino).
  double get progreso =>
      totalWaypoints <= 1 ? 1.0 : indiceWaypoint / (totalWaypoints - 1);
}