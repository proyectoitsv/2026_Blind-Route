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
///
/// ── CONTENCIÓN DENTRO DEL PLANO ────────────────────────────────────────────
/// El camino no puede salirse del plano ni pegarse a su borde. Esto se logra
/// con tres mecanismos complementarios:
///
///  1. **Franja perimetral no transitable** ([margenBordeMetros]): el anillo
///     exterior de la grilla se marca como intransitable, así el A* no puede
///     "escaparse" por el perímetro para esquivar una zona. Se exceptúan las
///     celdas cercanas al origen y al destino, para que el usuario pueda
///     entrar y salir aunque esté parado contra una pared.
///  2. **Campo de costos** ([amortiguacionBordeMetros]): las celdas próximas
///     al borde (aunque sean transitables) suman un costo extra que decrece
///     hacia el centro. Ante dos rodeos equivalentes, el A* elige el que
///     bordea la zona y no el que bordea el plano.
///  3. **Centros de celda recortados**: la última celda de cada eje puede ser
///     parcial (la escala rara vez es múltiplo exacto del lado de celda) y su
///     centro geométrico cae FUERA de `[0,1]`. Antes se devolvía tal cual: por
///     eso la ruta llegaba a dibujarse literalmente fuera de la imagen del
///     plano. Ahora se recorta igual que en `GrillaNav.centroX/centroY`.
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

  // ── Parámetros de contención respecto del borde del plano ──────────────────

  /// Franja perimetral (en metros) que se declara NO transitable. Evita que la
  /// ruta se genere pegada al límite del plano o directamente fuera de él. Se
  /// traduce a celdas según el lado de celda del piso, con un mínimo de 1.
  static const double margenBordeMetros = 1.0;

  /// Ancho (en metros) de la banda interior donde acercarse al borde tiene un
  /// costo extra decreciente. Es lo que hace que, ante dos rodeos de igual
  /// longitud, el A* prefiera el que pasa por el interior del plano.
  static const double amortiguacionBordeMetros = 2.0;

  /// Costo extra máximo (en "celdas") por estar pegado al borde transitable.
  /// Debe ser mayor que [costoMaxZona] para que bordear una zona siempre
  /// resulte más barato que bordear el plano — pero deliberadamente moderado:
  /// un valor alto haría que un pasillo perimetral legítimo (muy común: el
  /// pasillo que corre contra la pared exterior del edificio) se pague tan
  /// caro que el A* prefiera un rodeo absurdo por el interior. El trabajo
  /// pesado lo hace la franja bloqueada; esto es solo un desempate con peso.
  static const double costoMaxBorde = 2.0;

  /// Despegue de las zonas prohibidas: las celdas inmediatamente pegadas a una
  /// zona suman un costo chico, de modo que el camino la bordee sin rozarla.
  /// Se mantiene bajo a propósito: la idea es que la ruta BORDEE la zona, no
  /// que la esquive de lejos. Poner [costoMaxZona] en 0 para que el camino
  /// pase literalmente rasante a la zona.
  static const double amortiguacionZonaMetros = 1.0;
  static const double costoMaxZona = 0.6;

  /// Celdas de la franja perimetral que se habilitan alrededor del origen y
  /// del destino (distancia de Chebyshev). Sin esto, un usuario parado contra
  /// la pared o un lugar de interés ubicado sobre el límite del plano
  /// quedarían encerrados y la ruta no se podría calcular.
  static const int _radioExencionExtra = 1;

  // Grillas planas (índice lineal x * _resY + y).
  late List<bool> _obsZona;      // celdas ocupadas por zonas no transitables
  late List<bool> _esBorde;      // celdas de la franja perimetral bloqueada
  late List<double> _costoExtra; // campo de costos (borde + cercanía a zonas)
  int _margenCeldas = 1;

  List<ZonaNoTransitable> _zonas = [];

  int _idx(int x, int y) => x * _resY + y;

  // ── Inicialización ──────────────────────────────────────────────────────────

  /// [obstaculosRect]: áreas extra no transitables (normalizadas), hoy las
  /// escaleras: la ruta no puede pasar POR ENCIMA de una escalera, tiene que
  /// rodearla y llegar por su entrada. Se bloquean las celdas cuyo CENTRO
  /// cae dentro del área (sin rasterizar el contorno como en las zonas: con
  /// un cuadrado de 1 m eso bloquearía hasta 4 celdas y taparía la entrada).
  ///
  /// [puntosLibres]: puntos cuya celda NUNCA se bloquea por [obstaculosRect]
  /// (el punto frente a la entrada de cada escalera, que es el destino de la
  /// ruta). No liberan celdas bloqueadas por zonas prohibidas.
  void inicializar(
    List<ZonaNoTransitable> zonas, {
    GrillaNav? grilla,
    List<Rect> obstaculosRect = const [],
    List<Offset> puntosLibres = const [],
  }) {
    _zonas = zonas;
    _obstaculosRect = obstaculosRect;
    _puntosLibres = puntosLibres;
    if (grilla != null) _grillaNav = grilla;

    final total = _resX * _resY;
    _obsZona = List<bool>.filled(total, false);
    _esBorde = List<bool>.filled(total, false);
    _costoExtra = List<double>.filled(total, 0.0);

    _marcarObstaculos();
    _marcarObstaculosRect();
    _aplicarAnchoPasillo();
    _marcarBordes();
    _calcularCampoDeCostos();

    debugPrint(
      '[Pathfinder] Grilla ${_resX}x$_resY (${_grillaNav.tamCeldaMetros} m/celda) — '
      'zonas: ${_zonas.length}, escaleras: ${_obstaculosRect.length}, '
      'margen de borde: $_margenCeldas celda(s).',
    );
  }

  // ── Centros de celda (recortados al plano) ─────────────────────────────────
  //
  // Idéntico a GrillaNav._centro: la última celda de cada eje puede ser parcial
  // y su centro se recorta a 1.0 para que NUNCA caiga fuera del plano.

  static double _centroCelda(int i, double paso) {
    final inicio = i * paso;
    final fin = (inicio + paso) > 1.0 ? 1.0 : inicio + paso;
    return (inicio + fin) / 2;
  }

  double _centroX(int i) => _centroCelda(i, _pasoX);
  double _centroY(int j) => _centroCelda(j, _pasoY);

  // ── Marcado de zonas no transitables ───────────────────────────────────────

  void _marcarObstaculos() {
    for (final zona in _zonas) {
      if (zona.vertices.length < 3) continue;

      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final v in zona.vertices) {
        if (v.dx < minX) minX = v.dx;
        if (v.dy < minY) minY = v.dy;
        if (v.dx > maxX) maxX = v.dx;
        if (v.dy > maxY) maxY = v.dy;
      }

      final ixMin = max(0, (minX / _pasoX).floor());
      final iyMin = max(0, (minY / _pasoY).floor());
      final ixMax = min(_resX - 1, (maxX / _pasoX).ceil());
      final iyMax = min(_resY - 1, (maxY / _pasoY).ceil());

      // 1) Relleno: celdas cuyo centro (recortado al plano) cae dentro del
      //    polígono.
      for (int x = ixMin; x <= ixMax; x++) {
        for (int y = iyMin; y <= iyMax; y++) {
          if (_puntoEnPoligono(Offset(_centroX(x), _centroY(y)), zona.vertices)) {
            _obsZona[_idx(x, y)] = true;
          }
        }
      }

      // 2) Contorno: se rasterizan las aristas del polígono muestreándolas a
      //    paso fino. Sin esto una zona angosta (o el filo de una zona ancha)
      //    puede quedar "abierta" porque ningún centro de celda cae adentro, y
      //    el A* se cuela por ese hueco inexistente.
      _rasterizarContorno(zona.vertices);
    }
  }

  List<Rect> _obstaculosRect = const [];
  List<Offset> _puntosLibres = const [];

  /// Bloquea las celdas cuyo centro cae dentro de alguna de las áreas de
  /// [_obstaculosRect], salvo las celdas de [_puntosLibres]. Si el área es
  /// más chica que una celda y ningún centro cae adentro, se bloquea la celda
  /// que contiene su centro, para que la escalera nunca quede transitable.
  void _marcarObstaculosRect() {
    if (_obstaculosRect.isEmpty) return;

    int celdaX(double x) => min(_resX - 1, max(0, (x / _pasoX).floor()));
    int celdaY(double y) => min(_resY - 1, max(0, (y / _pasoY).floor()));
    final libres = <int>{
      for (final p in _puntosLibres) _idx(celdaX(p.dx), celdaY(p.dy)),
    };

    for (final r in _obstaculosRect) {
      final ixMin = celdaX(r.left);
      final ixMax = celdaX(r.right);
      final iyMin = celdaY(r.top);
      final iyMax = celdaY(r.bottom);
      bool marcoAlguna = false;
      for (int x = ixMin; x <= ixMax; x++) {
        for (int y = iyMin; y <= iyMax; y++) {
          if (r.contains(Offset(_centroX(x), _centroY(y)))) {
            final i = _idx(x, y);
            if (!libres.contains(i)) _obsZona[i] = true;
            marcoAlguna = true;
          }
        }
      }
      if (!marcoAlguna) {
        final i = _idx(celdaX(r.center.dx), celdaY(r.center.dy));
        if (!libres.contains(i)) _obsZona[i] = true;
      }
    }
  }

  void _rasterizarContorno(List<Offset> vertices) {
    final pasoMuestreo = min(_pasoX, _pasoY) / 3.0;
    if (pasoMuestreo <= 0) return;

    for (int i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      final largo = (b - a).distance;
      final muestras = max(1, (largo / pasoMuestreo).ceil());
      for (int s = 0; s <= muestras; s++) {
        final t = s / muestras;
        final px = a.dx + (b.dx - a.dx) * t;
        final py = a.dy + (b.dy - a.dy) * t;
        final cx = min(_resX - 1, max(0, (px / _pasoX).floor()));
        final cy = min(_resY - 1, max(0, (py / _pasoY).floor()));
        _obsZona[_idx(cx, cy)] = true;
      }
    }
  }

  /// Elimina celdas transitables que no tienen espacio suficiente alrededor
  /// para que una persona pase (ancho mínimo = _anchoPasillo celdas).
  /// Con [_anchoPasillo] = 1 esta poda es un no-op (una persona entra en una
  /// sola celda de 1 m). Se conserva para cuando se quiera exigir pasillos más
  /// anchos subiendo la constante.
  void _aplicarAnchoPasillo() {
    final obs = List<bool>.from(_obsZona); // snapshot previo
    for (int x = 0; x < _resX; x++) {
      for (int y = 0; y < _resY; y++) {
        if (obs[_idx(x, y)]) continue;
        if (!_tieneEspacioSuficiente(obs, x, y)) {
          _obsZona[_idx(x, y)] = true;
        }
      }
    }
  }

  bool _tieneEspacioSuficiente(List<bool> obs, int x, int y) {
    int libres(int dx, int dy) {
      int count = 0;
      for (int i = 1; i <= _anchoPasillo; i++) {
        final nx = x + dx * i, ny = y + dy * i;
        if (nx < 0 || nx >= _resX || ny < 0 || ny >= _resY) break;
        if (!obs[_idx(nx, ny)]) { count++; } else { break; }
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

  // ── Franja perimetral no transitable ───────────────────────────────────────

  /// Marca como no transitable el anillo exterior de la grilla, de ancho
  /// [margenBordeMetros] (mínimo 1 celda). Nunca consume más de un tercio de
  /// cada eje, para no dejar planos chicos sin espacio navegable.
  void _marcarBordes() {
    final tam = (_grillaNav.tamCeldaMetros.isFinite && _grillaNav.tamCeldaMetros > 0)
        ? _grillaNav.tamCeldaMetros
        : 1.0;

    int deseado = (margenBordeMetros / tam).round();
    if (deseado < 1) deseado = 1;

    // Tope de seguridad: dejar al menos 3 celdas libres en cada eje.
    final topeX = ((_resX - 3) / 2).floor();
    final topeY = ((_resY - 3) / 2).floor();
    final mx = max(0, min(deseado, topeX));
    final my = max(0, min(deseado, topeY));
    _margenCeldas = max(mx, my);

    for (int x = 0; x < _resX; x++) {
      for (int y = 0; y < _resY; y++) {
        if (x < mx || x >= _resX - mx || y < my || y >= _resY - my) {
          _esBorde[_idx(x, y)] = true;
        }
      }
    }
  }

  // ── Campo de costos (borde + cercanía a zonas) ─────────────────────────────

  void _calcularCampoDeCostos() {
    final tam = (_grillaNav.tamCeldaMetros.isFinite && _grillaNav.tamCeldaMetros > 0)
        ? _grillaNav.tamCeldaMetros
        : 1.0;

    final amortBorde = max(1, (amortiguacionBordeMetros / tam).round());
    final amortZona = max(1, (amortiguacionZonaMetros / tam).round());

    // Distancia (en celdas) a la zona no transitable más cercana, por BFS
    // multi-fuente acotado a amortZona anillos.
    final distZona = _distanciaAZonas(amortZona);

    for (int x = 0; x < _resX; x++) {
      for (int y = 0; y < _resY; y++) {
        final i = _idx(x, y);
        double extra = 0.0;

        // Distancia (en celdas) al límite del plano.
        final dBorde = min(min(x, _resX - 1 - x), min(y, _resY - 1 - y));
        if (dBorde < amortBorde) {
          extra += costoMaxBorde * (1.0 - dBorde / amortBorde);
        }

        // Despegue de zonas: solo para celdas libres pegadas a una zona.
        if (costoMaxZona > 0) {
          final dz = distZona[i];
          if (dz >= 1 && dz <= amortZona) {
            extra += costoMaxZona * (1.0 - (dz - 1) / amortZona);
          }
        }

        _costoExtra[i] = extra;
      }
    }
  }

  List<int> _distanciaAZonas(int maxAnillos) {
    const int infinito = 1 << 28;
    final dist = List<int>.filled(_resX * _resY, infinito);
    var frente = <int>[];

    for (int i = 0; i < _obsZona.length; i++) {
      if (_obsZona[i]) {
        dist[i] = 0;
        frente.add(i);
      }
    }

    const vecinos = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    for (int nivel = 1; nivel <= maxAnillos && frente.isNotEmpty; nivel++) {
      final siguiente = <int>[];
      for (final i in frente) {
        final x = i ~/ _resY, y = i % _resY;
        for (final d in vecinos) {
          final nx = x + d[0], ny = y + d[1];
          if (nx < 0 || nx >= _resX || ny < 0 || ny >= _resY) continue;
          final j = _idx(nx, ny);
          if (dist[j] > nivel) {
            dist[j] = nivel;
            siguiente.add(j);
          }
        }
      }
      frente = siguiente;
    }
    return dist;
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
  /// Se intenta primero con la franja perimetral BLOQUEADA (la ruta queda
  /// contenida dentro del plano). Si con esa restricción no existe camino
  /// —planos muy chicos, pasillos que corren pegados al límite, zonas que
  /// tocan el borde— se reintenta con la franja habilitada pero conservando el
  /// campo de costos, de modo que el borde se siga evitando salvo que sea la
  /// única alternativa. Así la corrección nunca deja al usuario sin ruta.
  Future<List<Offset>?> encontrarCamino(Offset inicio, Offset destino) async {
    final totalCeldas = _resX * _resY;
    final inicioReloj = DateTime.now();
    debugPrint(
      '[Pathfinder] Lanzando compute(): grilla ${_resX}x$_resY '
      '($totalCeldas celdas), inicio=$inicio, destino=$destino',
    );

    try {
      var resultado = await _resolver(inicio, destino, bloquearBorde: true);

      if (resultado == null) {
        debugPrint(
          '[Pathfinder] Sin ruta con el margen de borde activo. Reintentando '
          'con la franja perimetral habilitada (el campo de costos sigue '
          'penalizando acercarse al límite del plano).',
        );
        resultado = await _resolver(inicio, destino, bloquearBorde: false);
      }

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

  Future<List<Offset>?> _resolver(
    Offset inicio,
    Offset destino, {
    required bool bloquearBorde,
  }) {
    final args = _PathArgs(
      resX: _resX,
      resY: _resY,
      pasoX: _pasoX,
      pasoY: _pasoY,
      obstaculos: List<bool>.from(_obsZona),
      borde: List<bool>.from(_esBorde),
      costoExtra: List<double>.from(_costoExtra),
      bloquearBorde: bloquearBorde,
      radioExencion: _margenCeldas + _radioExencionExtra,
      inicio: inicio,
      destino: destino,
    );

    return compute(_aStarIsolate, args).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        debugPrint(
          '[Pathfinder] TIMEOUT: el isolate no respondió en 8 s. '
          'Grilla de ${_resX * _resY} celdas — si este número es muy grande '
          '(cientos de miles+), revisá escalaX/escalaY/tamCeldaMetros del '
          'piso en la pantalla de configuración: probablemente hay un '
          'error de unidades (p. ej. metros cargados como centímetros).',
        );
        throw TimeoutException('A* no respondió en 8 s');
      },
    );
  }
}

// ─── ISOLATE: ARGUMENTOS Y FUNCIÓN DE NIVEL SUPERIOR ─────────────────────────

class _PathArgs {
  final int resX;
  final int resY;
  final double pasoX;
  final double pasoY;
  final List<bool> obstaculos;   // zonas no transitables
  final List<bool> borde;        // franja perimetral del plano
  final List<double> costoExtra; // campo de costos por celda
  final bool bloquearBorde;      // ¿la franja perimetral es intransitable?
  final int radioExencion;       // celdas de borde habilitadas junto a A y B
  final Offset inicio;
  final Offset destino;

  _PathArgs({
    required this.resX,
    required this.resY,
    required this.pasoX,
    required this.pasoY,
    required this.obstaculos,
    required this.borde,
    required this.costoExtra,
    required this.bloquearBorde,
    required this.radioExencion,
    required this.inicio,
    required this.destino,
  });
}

/// Función de nivel superior requerida por compute() — no puede ser un método.
/// Ejecuta el A* completo dentro del isolate, sin tocar el hilo principal.
///
/// Movimiento en 4 direcciones (N/S/E/O, sin diagonales) para que el camino
/// siga las cuadrículas de la grilla, con penalización de giro para minimizar
/// curvas y un campo de costos que empuja el camino hacia el interior del
/// plano. Devuelve TODAS las celdas del camino (sin simplificar) para que el
/// `MapaWidget` pueda pintar cada una.
List<Offset>? _aStarIsolate(_PathArgs args) {
  final resX = args.resX;
  final resY = args.resY;
  final pasoX = args.pasoX;
  final pasoY = args.pasoY;
  final obs = args.obstaculos;
  final borde = args.borde;
  final costoExtra = args.costoExtra;

  int clampX(int v) => v < 0 ? 0 : (v >= resX ? resX - 1 : v);
  int clampY(int v) => v < 0 ? 0 : (v >= resY ? resY - 1 : v);

  // Índice de celda a partir del paso normalizado, igual que GrillaNav.indiceX.
  // OJO: NO es (n * resX): la última celda de cada eje puede ser parcial, así
  // que resX != 1 / pasoX y usar resX corría todas las celdas del camino.
  final ix0 = clampX((args.inicio.dx / pasoX).floor());
  final iy0 = clampY((args.inicio.dy / pasoY).floor());
  final gx0 = clampX((args.destino.dx / pasoX).floor());
  final gy0 = clampY((args.destino.dy / pasoY).floor());

  // Si el origen o destino caen en un obstáculo, buscar la celda libre más
  // cercana (BFS en anillos). Evita el null inmediato cuando la posición
  // trilaterada cae en el borde de una zona marcada.
  int ixLinear = ix0 * resY + iy0;
  int gxLinear = gx0 * resY + gy0;

  if (obs[ixLinear]) {
    ixLinear = _celdaLibreCercana(ix0, iy0, obs, borde, resX, resY);
    if (ixLinear < 0) return null;
  }
  if (obs[gxLinear]) {
    gxLinear = _celdaLibreCercana(gx0, gy0, obs, borde, resX, resY);
    if (gxLinear < 0) return null;
  }

  final ix = ixLinear ~/ resY;
  final iy = ixLinear % resY;
  final gx = gxLinear ~/ resY;
  final gy = gxLinear % resY;

  // ── Transitabilidad ────────────────────────────────────────────────────────
  // Una celda de la franja perimetral solo es transitable si está cerca del
  // origen o del destino (para poder despegarse de una pared y para llegar a
  // un POI ubicado sobre el límite del plano).
  final r = args.radioExencion;
  bool exenta(int x, int y) {
    final dIni = max((x - ix).abs(), (y - iy).abs());
    if (dIni <= r) return true;
    final dFin = max((x - gx).abs(), (y - gy).abs());
    return dFin <= r;
  }

  bool transitable(int x, int y) {
    final i = x * resY + y;
    if (obs[i]) return false;
    if (args.bloquearBorde && borde[i] && !exenta(x, y)) return false;
    return true;
  }

  if (!transitable(ix, iy) || !transitable(gx, gy)) return null;

  // Grilla local al isolate
  final grilla = List.generate(
    resX,
    (x) => List.generate(resY, (y) {
      final n = _Nodo(x, y);
      n.esObstaculo = !transitable(x, y);
      return n;
    }),
  );

  final nInicio = grilla[ix][iy];
  final nDestino = grilla[gx][gy];

  // Costos en "celdas" (cada celda ≈ tamCeldaMetros en ambos ejes): paso
  // recto = 1. Penalización por cada giro de 90° = 4 celdas: A* prefiere un
  // rodeo de hasta 4 celdas antes que sumar una curva → mínimas curvas.
  const double costoPaso = 1.0;
  const double costoGiro = 4.0;

  // Heurística Manhattan en celdas (admisible: el costo real de cada paso es
  // ≥ costoPaso) con desempate direccional. El término de producto cruzado
  // favorece las celdas alineadas con la recta origen→destino: sin él TODOS
  // los rodeos monótonos de igual longitud empatan, y el A* podía elegir
  // arbitrariamente el que se iba contra el borde del plano.
  final dxTotal = (ix - gx).toDouble();
  final dyTotal = (iy - gy).toDouble();
  double heuristica(_Nodo a, _Nodo b) {
    final manhattan = ((a.x - b.x).abs() + (a.y - b.y).abs()).toDouble();
    final cruz = ((a.x - b.x) * dyTotal - dxTotal * (a.y - b.y)).abs();
    return manhattan + cruz * 0.001;
  }

  nInicio.g = 0;
  nInicio.h = heuristica(nInicio, nDestino);

  // Ante igual f se expande primero el nodo con mayor g (más avanzado hacia el
  // destino): converge antes y evita abanicos de empates.
  final abierta = _MinHeap<_Nodo>((a, b) {
    final c = a.f.compareTo(b.f);
    return c != 0 ? c : b.g.compareTo(a.g);
  });
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
      final penCampo = costoExtra[nx * resY + ny];
      final gTentativo = actual.g + costoPaso + penGiro + penCampo;

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
/// Prioriza celdas que NO estén en la franja perimetral; solo si no encuentra
/// ninguna acepta una celda de borde. Retorna -1 si no hay ninguna libre.
int _celdaLibreCercana(
    int x0, int y0, List<bool> obs, List<bool> borde, int resX, int resY) {
  int respaldo = -1;
  for (int r = 0; r <= 10; r++) {
    for (int dx = -r; dx <= r; dx++) {
      for (int dy = -r; dy <= r; dy++) {
        if (dx.abs() != r && dy.abs() != r) continue; // solo el borde del anillo
        final nx = x0 + dx;
        final ny = y0 + dy;
        if (nx < 0 || nx >= resX || ny < 0 || ny >= resY) continue;
        final i = nx * resY + ny;
        if (obs[i]) continue;
        if (!borde[i]) return i;                    // celda interior: la mejor
        if (respaldo < 0) respaldo = i;             // de última, una de borde
      }
    }
  }
  return respaldo;
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

/// Reconstruye el camino como centros de celda NORMALIZADOS y **recortados al
/// plano**. La última celda de cada eje puede ser parcial: su centro
/// geométrico `(i + 0.5) * paso` cae fuera de `[0,1]`, que es exactamente por
/// lo que la ruta terminaba dibujándose fuera de los límites del mapa. Se usa
/// el mismo recorte que `GrillaNav.centroX/centroY` para que el camino
/// calculado y el pintado coincidan celda a celda.
List<Offset> _reconstruir(_Nodo destino, double pasoX, double pasoY) {
  double centro(int i, double paso) {
    final inicio = i * paso;
    final fin = (inicio + paso) > 1.0 ? 1.0 : inicio + paso;
    return (inicio + fin) / 2;
  }

  final camino = <Offset>[];
  _Nodo? n = destino;
  while (n != null) {
    camino.add(Offset(centro(n.x, pasoX), centro(n.y, pasoY)));
    n = n.padre;
  }
  return camino.reversed.toList();
}