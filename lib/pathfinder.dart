import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
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

// ─── SIN CAMINO ──────────────────────────────────────────────────────────────

/// Cuál de las dos puntas quedó encerrada cuando no hay camino entre ellas
/// (ver [ResolvedorCaminos.diagnosticarSinCamino]).
enum SinCamino {
  /// El destino está en un área sin salida hacia el resto del piso, o
  /// adentro de una zona sin ninguna celda libre cerca: no se puede llegar.
  destinoEncerrado,

  /// La encerrada es el origen. Con la posición del usuario suele ser un
  /// error de la posición, que se corrige sola al moverse.
  origenEncerrado,
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
///
/// ── ZONAS: CELDAS BLOQUEADAS Y PAREDES ────────────────────────────────────
/// Las zonas no transitables afectan la grilla de dos maneras:
///
///  • **Celda bloqueada**: su CENTRO cae adentro de una zona
///    ([esZonaProhibida]). Ni la ruta ni la posición del usuario pueden estar
///    en ella.
///  • **Pared**: dos celdas vecinas libres quedan desconectadas si el
///    segmento entre sus centros pasa por adentro de una zona
///    ([conectadas]). Es lo que frena a la ruta frente a una zona angosta
///    que no tapa ningún centro (una pared de 20 cm).
///
/// Ver [_marcarObstaculos] para el porqué de este criterio.
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

  /// Conexiones cortadas por una pared, por celda (bits [_paredEste],
  /// [_paredSur], [_paredSurEste] y [_paredSurOeste]; ver [_hayPared]).
  /// Vacía hasta [inicializar].
  Uint8List _paredes = Uint8List(0);

  /// Celdas ocupadas SÓLO por las zonas no transitables dibujadas (sin
  /// escaleras ni franja de borde). Vacía hasta [inicializar].
  List<bool> _soloZonas = const [];

  List<ZonaNoTransitable> _zonas = [];

  int _idx(int x, int y) => x * _resY + y;

  /// true si el CENTRO de la celda (x, y) cae en una zona no transitable
  /// dibujada por el administrador. Es lo que usa [RestriccionZonas] para
  /// que la posición del usuario no quede adentro de una.
  bool esZonaProhibida(int x, int y) {
    if (x < 0 || x >= _resX || y < 0 || y >= _resY) return false;
    final i = _idx(x, y);
    return i < _soloZonas.length && _soloZonas[i];
  }

  /// true si se puede pasar de la celda (x1, y1) a su vecina (x2, y2), en
  /// cruz o en diagonal, sin atravesar una zona: el segmento entre los dos
  /// centros no pasa por adentro de ningún polígono. No mira si las celdas
  /// mismas están bloqueadas (eso es [esZonaProhibida]). False si las celdas
  /// no son vecinas o alguna cae fuera de la grilla.
  bool conectadas(int x1, int y1, int x2, int y2) {
    final dx = x2 - x1, dy = y2 - y1;
    if (dx.abs() > 1 || dy.abs() > 1) return false;
    if (dx == 0 && dy == 0) return true;
    if (x1 < 0 || x1 >= _resX || y1 < 0 || y1 >= _resY) return false;
    if (x2 < 0 || x2 >= _resX || y2 < 0 || y2 >= _resY) return false;
    return !_hayPared(_paredes, _resY, x1, y1, dx, dy);
  }

  /// true si el punto [p] (normalizado) cae adentro del polígono de alguna
  /// zona. No es lo mismo que [esZonaProhibida] sobre su celda: una pared
  /// angosta no bloquea ninguna celda (no tapa ningún centro), pero una
  /// medición sí puede caer adentro de ella.
  bool puntoEnZona(Offset p) {
    for (final zona in _zonas) {
      if (zona.vertices.length >= 3 && _puntoEnPoligono(p, zona.vertices)) {
        return true;
      }
    }
    return false;
  }

  // ── Inicialización ──────────────────────────────────────────────────────────

  /// [obstaculosRect]: áreas extra no transitables (normalizadas), hoy las
  /// escaleras: la ruta no puede pasar POR ENCIMA de una escalera, tiene que
  /// rodearla y llegar por su entrada. Se bloquean las celdas cuyo CENTRO
  /// cae dentro del área, igual que con las zonas (rasterizar el contorno,
  /// con un cuadrado de 1 m, bloquearía hasta 4 celdas y taparía la entrada).
  /// A diferencia de las zonas, no cortan conexiones ([conectadas]).
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
    _paredes = Uint8List(total);

    _marcarObstaculos();
    _marcarParedes();
    // Se copia ANTES de sumar las escaleras: el usuario sí puede estar parado
    // en una escalera (llega por ella en un salto de piso), sólo la ruta no
    // puede pasar por encima.
    _soloZonas = List<bool>.from(_obsZona);
    _marcarObstaculosRect();
    _aplicarAnchoPasillo();
    _marcarBordes();
    _calcularCampoDeCostos();
    _marcarComponentes();

    debugPrint(
      '[Pathfinder] Grilla ${_resX}x$_resY (${_grillaNav.tamCeldaMetros} m/celda) — '
      'zonas: ${_zonas.length}, escaleras: ${_obstaculosRect.length}, '
      'margen de borde: $_margenCeldas celda(s), '
      'áreas transitables separadas: ${_tamComponente.length}.',
    );
  }

  // ── Áreas conectadas (componentes) ─────────────────────────────────────────
  //
  // ═══ ¿SE PUEDE LLEGAR? ═══
  // Cuando el A* no encuentra camino, la pantalla tiene que saber POR QUÉ:
  // si el destino está encerrado (no se puede llegar, hay que decirlo) o si
  // lo encerrado es el origen, o sea la posición del usuario (casi siempre
  // un error de la posición, que se corrige sola al moverse). El A* sólo dice
  // "no hay camino". Para eso se agrupan las celdas libres en áreas: dos
  // celdas están en la misma si se puede ir de una a la otra caminando en
  // cruz sin pisar celdas bloqueadas ni atravesar paredes, que es justo por
  // donde se mueve el A* (con la franja de borde habilitada, como en su
  // segundo intento). Se calcula una vez por piso.

  /// Área de cada celda (índice en [_tamComponente]); -1 en las bloqueadas.
  /// Vacía hasta [inicializar].
  Int32List _componente = Int32List(0);

  /// Cantidad de celdas de cada área.
  List<int> _tamComponente = const [];

  /// El área más grande: la parte principal del piso.
  int _componentePrincipal = -1;

  void _marcarComponentes() {
    final total = _resX * _resY;
    _componente = Int32List(total)..fillRange(0, total, -1);
    final tamanos = <int>[];
    const vecinos = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    final pila = <int>[];
    for (int inicio = 0; inicio < total; inicio++) {
      if (_obsZona[inicio] || _componente[inicio] >= 0) continue;
      final id = tamanos.length;
      int tam = 0;
      _componente[inicio] = id;
      pila.add(inicio);
      while (pila.isNotEmpty) {
        final i = pila.removeLast();
        tam++;
        final x = i ~/ _resY, y = i % _resY;
        for (final (dx, dy) in vecinos) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= _resX || ny < 0 || ny >= _resY) continue;
          final j = _idx(nx, ny);
          if (_obsZona[j] || _componente[j] >= 0) continue;
          if (_hayPared(_paredes, _resY, x, y, dx, dy)) continue;
          _componente[j] = id;
          pila.add(j);
        }
      }
      tamanos.add(tam);
    }
    _tamComponente = tamanos;
    _componentePrincipal = -1;
    for (int c = 0; c < tamanos.length; c++) {
      if (_componentePrincipal < 0 || tamanos[c] > tamanos[_componentePrincipal]) {
        _componentePrincipal = c;
      }
    }
  }

  /// Área de la celda donde el A* arrancaría (o terminaría) desde [p]: la de
  /// [p], o la libre más cercana si [p] cae en una bloqueada. -1 si no hay
  /// ninguna libre cerca. -2 si todavía no se inicializó.
  int _componenteDe(Offset p) {
    if (_componente.length != _resX * _resY || _componente.isEmpty) return -2;
    final i = _celdaLibreDe(p, _obsZona, _esBorde, _resX, _resY, _pasoX, _pasoY);
    return i < 0 ? -1 : _componente[i];
  }

  /// true si se puede llegar caminando de [inicio] a [destino] (puntos
  /// normalizados): sus celdas, corridas a la libre más cercana como hace el
  /// A*, están en la misma área. true también si todavía no se sabe (sin
  /// [inicializar]).
  bool alcanzable(Offset inicio, Offset destino) {
    final a = _componenteDe(inicio);
    if (a == -2) return true;
    return a >= 0 && a == _componenteDe(destino);
  }

  /// Cuál de las dos puntas quedó encerrada cuando no hay camino de [inicio]
  /// a [destino]. Null si se puede llegar o todavía no se sabe.
  ///
  /// Si sólo una de las dos está en el área principal del piso, la encerrada
  /// es la otra. Si ninguna lo está, la de área más chica. Una punta sin
  /// ninguna celda libre cerca (adentro de una zona grande) está encerrada.
  SinCamino? diagnosticarSinCamino(Offset inicio, Offset destino) {
    final a = _componenteDe(inicio);
    final b = _componenteDe(destino);
    if (a == -2 || b == -2) return null;
    if (b < 0) return SinCamino.destinoEncerrado;
    if (a < 0) return SinCamino.origenEncerrado;
    if (a == b) return null;
    if (b == _componentePrincipal) return SinCamino.origenEncerrado;
    if (a == _componentePrincipal) return SinCamino.destinoEncerrado;
    return _tamComponente[b] <= _tamComponente[a]
        ? SinCamino.destinoEncerrado
        : SinCamino.origenEncerrado;
  }

  // ── Centros de celda (recortados al plano) ─────────────────────────────────
  //
  // Se toman de GrillaNav, que es la misma que usan RestriccionZonas y el
  // MapaWidget: el centro con el que se decide si una celda está bloqueada o
  // conectada es exactamente el de la celda que se dibuja. La última celda
  // de cada eje puede ser parcial y su centro se recorta para que NUNCA caiga
  // fuera del plano.

  double _centroX(int i) => _grillaNav.centroX(i);
  double _centroY(int j) => _grillaNav.centroY(j);

  // ── Marcado de zonas no transitables ───────────────────────────────────────
  //
  // ═══ BLOQUEO POR CENTRO ═══
  // Una celda queda bloqueada sólo si su CENTRO cae adentro de una zona.
  //
  // Antes también se rasterizaba el contorno: toda celda tocada por una
  // arista quedaba bloqueada. Con celdas de 1 m, la esquina de 20 cm de una
  // zona bloqueaba la celda entera, y una zona dibujada justo sobre el borde
  // entre dos celdas bloqueaba la fila de al lado completa. La posición
  // saltaba a la celda vecina y la ruta se cortaba en pasillos que en la
  // realidad tienen lugar de sobra.
  //
  // El contorno estaba para que una zona angosta (una pared de 20 cm, que no
  // tapa ningún centro) no quedara "abierta" y el A* se colara a través de
  // ella. Eso ahora lo resuelven las paredes ([_marcarParedes]): las celdas
  // de los dos lados quedan libres, pero la conexión entre ellas se corta.
  //
  // Un criterio por porcentaje de celda cubierta no serviría: depende de
  // cuánto mide la celda y no de por dónde puede pasar una persona.

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

      // Celdas cuyo centro (recortado al plano) cae dentro del polígono.
      //
      // Si un centro cae JUSTO sobre una arista, decide la regla del cruce de
      // rayos de [_puntoEnPoligono]: en una zona rectangular cuenta como
      // adentro sobre el borde izquierdo o el de arriba (x o y mínimos) y
      // como afuera sobre el derecho o el de abajo. Es un empate que en un
      // plano real casi nunca se da exacto, y se resuelve una sola vez al
      // cargar el piso: no puede titilar.
      for (int x = ixMin; x <= ixMax; x++) {
        for (int y = iyMin; y <= iyMax; y++) {
          if (_puntoEnPoligono(Offset(_centroX(x), _centroY(y)), zona.vertices)) {
            _obsZona[_idx(x, y)] = true;
          }
        }
      }
    }
  }

  /// Corta la conexión entre dos celdas vecinas (en cruz y en diagonal)
  /// cuando el segmento entre sus centros pasa por adentro de una zona.
  ///
  /// Se calcula una sola vez por piso: el A* y [RestriccionZonas] sólo leen
  /// los bits. Para cada zona se miran nada más las celdas alrededor de su
  /// caja, así que el costo depende del tamaño de las zonas y no del plano.
  void _marcarParedes() {
    const direcciones = [
      (_paredEste, 1, 0),
      (_paredSur, 0, 1),
      (_paredSurEste, 1, 1),
      (_paredSurOeste, -1, 1),
    ];

    for (final zona in _zonas) {
      final v = zona.vertices;
      if (v.length < 3) continue;

      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final p in v) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }

      // Un segmento entre centros vecinos sólo puede tocar la caja de la
      // zona si sale de una celda que la toca o de una pegada a ella.
      final ixMin = max(0, (minX / _pasoX).floor() - 1);
      final iyMin = max(0, (minY / _pasoY).floor() - 1);
      final ixMax = min(_resX - 1, (maxX / _pasoX).floor() + 1);
      final iyMax = min(_resY - 1, (maxY / _pasoY).floor() + 1);

      for (int x = ixMin; x <= ixMax; x++) {
        for (int y = iyMin; y <= iyMax; y++) {
          final i = _idx(x, y);
          final a = Offset(_centroX(x), _centroY(y));
          for (final (bit, dx, dy) in direcciones) {
            if ((_paredes[i] & bit) != 0) continue; // ya la cortó otra zona
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || nx >= _resX || ny >= _resY) continue;
            final b = Offset(_centroX(nx), _centroY(ny));
            if (max(a.dx, b.dx) < minX || min(a.dx, b.dx) > maxX ||
                max(a.dy, b.dy) < minY || min(a.dy, b.dy) > maxY) {
              continue;
            }
            if (_segmentoAtraviesaPoligono(a, b, v)) _paredes[i] |= bit;
          }
        }
      }
    }
  }

  /// true si alguna de las 4 conexiones en cruz de la celda (x, y) está
  /// cortada por una pared.
  bool _tieneParedEnCruz(int x, int y) {
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || nx >= _resX || ny < 0 || ny >= _resY) continue;
      if (_hayPared(_paredes, _resY, x, y, dx, dy)) return true;
    }
    return false;
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

    // Celdas libres pegadas a una pared: una zona angosta no bloquea ninguna
    // celda (no tapa ningún centro), así que sin esto la ruta no se despegaría
    // de ella. Cuentan como distancia 1, igual que las pegadas a una celda
    // bloqueada. (Antes las bloqueaba el contorno y el despegue salía solo.)
    final pegadas = <int>[];
    for (int x = 0; x < _resX; x++) {
      for (int y = 0; y < _resY; y++) {
        final i = _idx(x, y);
        if (dist[i] > 1 && _tieneParedEnCruz(x, y)) {
          dist[i] = 1;
          pegadas.add(i);
        }
      }
    }

    const vecinos = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    for (int nivel = 1; nivel <= maxAnillos; nivel++) {
      // Las pegadas a una pared ya tienen distancia 1: se expanden junto con
      // las del primer anillo.
      final siguiente = nivel == 1 ? pegadas : <int>[];
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
      if (frente.isEmpty) break;
    }
    return dist;
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
      paredes: Uint8List.fromList(_paredes),
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

// ─── GEOMETRÍA DE ZONAS Y PAREDES ────────────────────────────────────────────
//
// Funciones de nivel superior: las usa tanto el ResolvedorCaminos como el A*
// dentro del isolate. Todo se calcula en coordenadas normalizadas: escalar un
// eje distinto que el otro (metrosX ≠ metrosY) no cambia si un segmento
// cruza un polígono, así que no hace falta pasar a metros.

/// Bits de [ResolvedorCaminos._paredes]. Cada conexión entre vecinas se
/// guarda UNA vez, en la celda de la que sale hacia el este, el sur, el
/// sureste o el suroeste; la conexión inversa se lee desde la vecina.
const int _paredEste = 1;     // (x, y) ↔ (x + 1, y)
const int _paredSur = 2;      // (x, y) ↔ (x, y + 1)
const int _paredSurEste = 4;  // (x, y) ↔ (x + 1, y + 1)
const int _paredSurOeste = 8; // (x, y) ↔ (x - 1, y + 1)

/// true si una pared corta el paso de la celda (x, y) a su vecina
/// (x + dx, y + dy), con dx y dy en {-1, 0, 1}. No valida que la vecina
/// esté dentro de la grilla.
bool _hayPared(Uint8List paredes, int resY, int x, int y, int dx, int dy) {
  // Hacia el oeste, el norte, el noroeste o el noreste: se lee la misma
  // conexión desde la otra punta.
  final invertir = dy < 0 || (dy == 0 && dx < 0);
  final ox = invertir ? x + dx : x;
  final oy = invertir ? y + dy : y;
  final ddx = invertir ? -dx : dx;
  final ddy = invertir ? -dy : dy;
  final bit = ddy == 0
      ? _paredEste
      : (ddx == 0 ? _paredSur : (ddx > 0 ? _paredSurEste : _paredSurOeste));
  final i = ox * resY + oy;
  return i >= 0 && i < paredes.length && (paredes[i] & bit) != 0;
}

/// Cruce de rayos: true si [punto] está adentro del polígono [vertices].
///
/// Sobre una arista el resultado es fijo (no aleatorio): el rayo va hacia +x
/// y una arista vertical sólo cuenta si queda estrictamente a la derecha del
/// punto, y una horizontal nunca cuenta. En un rectángulo eso deja adentro
/// los bordes izquierdo y de arriba, y afuera el derecho y el de abajo: el
/// mismo criterio semiabierto que usa la grilla para los índices de celda.
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

/// true si el segmento [a]–[b] pasa por ADENTRO del polígono [v].
///
/// Tocarlo no alcanza: un segmento que roza un vértice o corre por afuera a
/// lo largo de una arista no lo atraviesa. Se buscan todos los puntos donde
/// el segmento toca alguna arista; entre dos de esos puntos seguidos el
/// segmento queda entero adentro o entero afuera, así que alcanza con mirar
/// el punto medio de cada tramo. Esto cubre también el caso que un simple
/// "¿se cruza con alguna arista?" deja pasar: la diagonal que entra y sale
/// justo por dos vértices de un cuadrado.
bool _segmentoAtraviesaPoligono(Offset a, Offset b, List<Offset> v) {
  const eps = 1e-12;
  double cruz(Offset p, Offset q) => p.dx * q.dy - p.dy * q.dx;

  final d = b - a;
  final largo2 = d.dx * d.dx + d.dy * d.dy;
  if (largo2 <= 0) return false;

  final ts = <double>[0.0, 1.0];
  for (int k = 0; k < v.length; k++) {
    final p = v[k];
    final e = v[(k + 1) % v.length] - p;
    final ap = p - a;
    final den = cruz(d, e);
    if (den.abs() > eps) {
      // a + t·d = p + u·e
      final t = cruz(ap, e) / den;
      final u = cruz(ap, d) / den;
      if (t > -eps && t < 1 + eps && u > -eps && u < 1 + eps) {
        ts.add(t.clamp(0.0, 1.0).toDouble());
      }
    } else if (cruz(ap, d).abs() <= eps) {
      // Arista sobre la misma recta: se agregan sus extremos que caen dentro
      // del segmento, para mirar aparte el tramo que corre pegado a ella.
      for (final w in [p, p + e]) {
        final t = ((w.dx - a.dx) * d.dx + (w.dy - a.dy) * d.dy) / largo2;
        if (t > 0 && t < 1) ts.add(t);
      }
    }
  }

  ts.sort();
  for (int k = 0; k + 1 < ts.length; k++) {
    if (ts[k + 1] - ts[k] <= eps) continue;
    final m = (ts[k] + ts[k + 1]) / 2;
    if (_puntoEnPoligono(Offset(a.dx + d.dx * m, a.dy + d.dy * m), v)) {
      return true;
    }
  }
  return false;
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
  final Uint8List paredes;       // conexiones cortadas (ver _hayPared)
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
    required this.paredes,
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
///
/// Dos celdas libres vecinas sólo se conectan si no hay una pared entre ellas
/// ([_hayPared]). Las paredes también están calculadas para las diagonales,
/// pero el A* no se mueve en diagonal: el seguimiento de la ruta y la voz
/// ([SeguidorRuta]) cuentan con tramos rectos y giros de 90°.
List<Offset>? _aStarIsolate(_PathArgs args) {
  final resX = args.resX;
  final resY = args.resY;
  final pasoX = args.pasoX;
  final pasoY = args.pasoY;
  final obs = args.obstaculos;
  final borde = args.borde;
  final costoExtra = args.costoExtra;
  final paredes = args.paredes;

  // Celdas de origen y destino; si caen en un obstáculo, la libre más
  // cercana (ver _celdaLibreDe).
  final ixLinear =
      _celdaLibreDe(args.inicio, obs, borde, resX, resY, pasoX, pasoY);
  if (ixLinear < 0) return null;
  final gxLinear =
      _celdaLibreDe(args.destino, obs, borde, resX, resY, pasoX, pasoY);
  if (gxLinear < 0) return null;

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
      // Las dos celdas pueden estar libres (sus centros caen afuera de toda
      // zona) y aun así tener una pared en el medio.
      if (_hayPared(paredes, resY, actual.x, actual.y, d[0], d[1])) continue;

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

/// Índice lineal (x*resY+y) de la celda desde la que el A* sale (o a la que
/// llega) para el punto normalizado [p]: la suya o, si es un obstáculo, la
/// libre más cercana. Evita el null inmediato cuando la posición trilaterada
/// cae en el borde de una zona marcada. -1 si no hay ninguna libre cerca.
///
/// Es de nivel superior porque la usan el A* (en el isolate) y
/// [ResolvedorCaminos.alcanzable]: los dos tienen que partir de la misma
/// celda.
int _celdaLibreDe(Offset p, List<bool> obs, List<bool> borde, int resX,
    int resY, double pasoX, double pasoY) {
  int clampX(int v) => v < 0 ? 0 : (v >= resX ? resX - 1 : v);
  int clampY(int v) => v < 0 ? 0 : (v >= resY ? resY - 1 : v);

  // Índice de celda a partir del paso normalizado, igual que GrillaNav.indiceX.
  // OJO: NO es (n * resX): la última celda de cada eje puede ser parcial, así
  // que resX != 1 / pasoX y usar resX corría todas las celdas del camino.
  final x0 = clampX((p.dx / pasoX).floor());
  final y0 = clampY((p.dy / pasoY).floor());
  final i = x0 * resY + y0;
  if (!obs[i]) return i;
  return _celdaLibreCercana(x0, y0, obs, borde, resX, resY);
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