import 'dart:math';
import 'package:flutter/material.dart';
import 'zona_model.dart';

/// Nodo de la grilla para el algoritmo A*
class _NodoGrilla {
  final int x, y;
  double g = double.infinity;
  double h = 0;
  double get f => g + h;
  _NodoGrilla? padre;
  bool visitado = false;
  bool esObstaculo = false;

  _NodoGrilla(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is _NodoGrilla && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Resuelve caminos en un plano 2D evitando zonas poligonales no transitables.
/// Usa A* con penalización por giros para favorecer trayectorias rectas.
class ResolvedorCaminos {
  /// Celdas por lado del plano (0.0-1.0). Mayor = más preciso pero más lento.
  static const int _resolucion = 80;
  static const double _paso = 1.0 / _resolucion;

  /// ANCHO DE PASILLO: cuántas celdas libres consecutivas se necesitan
  /// para considerar que un pasillo es transitable. Evita que el camino
  /// pase por rendijas muy angostas entre zonas prohibidas.
  static const int _anchoPasillo = 3;

  /// PENALIZACIÓN POR GIRO: costo extra que se suma cuando el camino
  /// cambia de dirección (no sigue recto). Valor mayor = caminos más rectos.
  static const double _penalizacionGiro = 0.35;

  late List<List<_NodoGrilla>> _grilla;
  List<ZonaNoTransitable> _zonas = [];

  void inicializar(List<ZonaNoTransitable> zonas) {
    _zonas = zonas;
    _construirGrilla();
    _marcarObstaculos();
    _aplicarAnchoPasillo();
  }

  void _construirGrilla() {
    _grilla = List.generate(
      _resolucion,
      (x) => List.generate(
        _resolucion,
        (y) => _NodoGrilla(x, y),
      ),
    );
  }

  /// Marca como obstáculo las celdas dentro de los polígonos de zonas prohibidas
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

      final ixMin = max(0, (minX * _resolucion).floor());
      final iyMin = max(0, (minY * _resolucion).floor());
      final ixMax = min(_resolucion - 1, (maxX * _resolucion).ceil());
      final iyMax = min(_resolucion - 1, (maxY * _resolucion).ceil());

      for (int x = ixMin; x <= ixMax; x++) {
        for (int y = iyMin; y <= iyMax; y++) {
          final cx = (x + 0.5) * _paso;
          final cy = (y + 0.5) * _paso;
          if (_puntoEnPoligono(Offset(cx, cy), zona.vertices)) {
            _grilla[x][y].esObstaculo = true;
          }
        }
      }
    }
  }

  /// NUEVO: Aplica el ancho de pasillo. Una celda libre solo es transitable
  /// si tiene al menos [_anchoPasillo] celdas libres consecutivas en todas
  /// las direcciones cardinales (como si fuera el ancho de una persona).
  void _aplicarAnchoPasillo() {
    // Creamos una copia para no afectar las verificaciones durante el proceso
    final obstaculosOriginales = List.generate(
      _resolucion,
      (x) => List.generate(
        _resolucion,
        (y) => _grilla[x][y].esObstaculo,
      ),
    );

    for (int x = 0; x < _resolucion; x++) {
      for (int y = 0; y < _resolucion; y++) {
        if (obstaculosOriginales[x][y]) continue;

        // Verificar ancho en las 4 direcciones cardinales
        bool espacioSuficiente = true;

        // Horizontal: izquierda y derecha
        int libresIzq = 0, libresDer = 0;
        for (int i = 1; i <= _anchoPasillo && x - i >= 0; i++) {
          if (!obstaculosOriginales[x - i][y]) libresIzq++;
          else break;
        }
        for (int i = 1; i <= _anchoPasillo && x + i < _resolucion; i++) {
          if (!obstaculosOriginales[x + i][y]) libresDer++;
          else break;
        }
        if (libresIzq + libresDer < _anchoPasillo - 1) {
          espacioSuficiente = false;
        }

        // Vertical: arriba y abajo
        int libresArriba = 0, libresAbajo = 0;
        for (int i = 1; i <= _anchoPasillo && y - i >= 0; i++) {
          if (!obstaculosOriginales[x][y - i]) libresArriba++;
          else break;
        }
        for (int i = 1; i <= _anchoPasillo && y + i < _resolucion; i++) {
          if (!obstaculosOriginales[x][y + i]) libresAbajo++;
          else break;
        }
        if (libresArriba + libresAbajo < _anchoPasillo - 1) {
          espacioSuficiente = false;
        }

        // Diagonal principal (\)
        int libresDiag1Neg = 0, libresDiag1Pos = 0;
        for (int i = 1; i <= _anchoPasillo && x - i >= 0 && y - i >= 0; i++) {
          if (!obstaculosOriginales[x - i][y - i]) libresDiag1Neg++;
          else break;
        }
        for (int i = 1; i <= _anchoPasillo && x + i < _resolucion && y + i < _resolucion; i++) {
          if (!obstaculosOriginales[x + i][y + i]) libresDiag1Pos++;
          else break;
        }
        if (libresDiag1Neg + libresDiag1Pos < _anchoPasillo - 1) {
          espacioSuficiente = false;
        }

        // Diagonal secundaria (/)
        int libresDiag2Neg = 0, libresDiag2Pos = 0;
        for (int i = 1; i <= _anchoPasillo && x + i < _resolucion && y - i >= 0; i++) {
          if (!obstaculosOriginales[x + i][y - i]) libresDiag2Neg++;
          else break;
        }
        for (int i = 1; i <= _anchoPasillo && x - i >= 0 && y + i < _resolucion; i++) {
          if (!obstaculosOriginales[x - i][y + i]) libresDiag2Pos++;
          else break;
        }
        if (libresDiag2Neg + libresDiag2Pos < _anchoPasillo - 1) {
          espacioSuficiente = false;
        }

        if (!espacioSuficiente) {
          _grilla[x][y].esObstaculo = true;
        }
      }
    }
  }

  /// Ray-casting: punto dentro de polígono
  bool _puntoEnPoligono(Offset punto, List<Offset> vertices) {
    bool dentro = false;
    int j = vertices.length - 1;
    for (int i = 0; i < vertices.length; i++) {
      final vi = vertices[i];
      final vj = vertices[j];
      if (((vi.dy > punto.dy) != (vj.dy > punto.dy)) &&
          (punto.dx < (vj.dx - vi.dx) * (punto.dy - vi.dy) / (vj.dy - vi.dy) + vi.dx)) {
        dentro = !dentro;
      }
      j = i;
    }
    return dentro;
  }

  /// Encuentra el camino más recto posible entre dos puntos.
  List<Offset>? encontrarCamino(Offset inicio, Offset destino) {
    final ix = _clamp((inicio.dx * _resolucion).round(), 0, _resolucion - 1);
    final iy = _clamp((inicio.dy * _resolucion).round(), 0, _resolucion - 1);
    final gx = _clamp((destino.dx * _resolucion).round(), 0, _resolucion - 1);
    final gy = _clamp((destino.dy * _resolucion).round(), 0, _resolucion - 1);

    final nodoInicio = _grilla[ix][iy];
    final nodoDestino = _grilla[gx][gy];

    if (nodoInicio.esObstaculo || nodoDestino.esObstaculo) return null;

    // Resetear estado
    for (var fila in _grilla) {
      for (var nodo in fila) {
        nodo.g = double.infinity;
        nodo.h = 0;
        nodo.padre = null;
        nodo.visitado = false;
      }
    }

    nodoInicio.g = 0;
    nodoInicio.h = _heuristica(nodoInicio, nodoDestino);

    final abierta = <_NodoGrilla>[nodoInicio];

    while (abierta.isNotEmpty) {
      abierta.sort((a, b) => a.f.compareTo(b.f));
      final actual = abierta.removeAt(0);

      if (actual == nodoDestino) {
        return _reconstruirCamino(actual);
      }

      actual.visitado = true;

      for (final vecino in _vecinos(actual)) {
        if (vecino.visitado || vecino.esObstaculo) continue;

        final costoBase = _costoMovimiento(actual, vecino);
        final costoGiro = _penalizacionPorGiro(actual, vecino);
        final costoTotal = costoBase + costoGiro;
        final gTentativo = actual.g + costoTotal;

        if (gTentativo < vecino.g) {
          vecino.padre = actual;
          vecino.g = gTentativo;
          vecino.h = _heuristica(vecino, nodoDestino);
          if (!abierta.contains(vecino)) {
            abierta.add(vecino);
          }
        }
      }
    }

    return null;
  }

  /// NUEVO: Calcula una penalización cuando el movimiento cambia de dirección
  /// respecto al movimiento anterior, favoreciendo líneas rectas.
  double _penalizacionPorGiro(_NodoGrilla actual, _NodoGrilla vecino) {
    if (actual.padre == null) return 0.0;

    final abuelo = actual.padre!;

    // Dirección del paso anterior (abuelo -> actual)
    final dx1 = actual.x - abuelo.x;
    final dy1 = actual.y - abuelo.y;

    // Dirección del paso actual (actual -> vecino)
    final dx2 = vecino.x - actual.x;
    final dy2 = vecino.y - actual.y;

    // Si la dirección es exactamente la misma, no hay penalización
    if (dx1 == dx2 && dy1 == dy2) return 0.0;

    // Si es el movimiento inverso (volver atrás), penalización alta
    if (dx1 == -dx2 && dy1 == -dy2) return _penalizacionGiro * 3.0;

    // Si es un giro de 45 grados (diagonal a ortogonal o viceversa)
    final producto = (dx1 * dx2 + dy1 * dy2).abs();
    if (producto == 0) return _penalizacionGiro * 1.5;

    // Giro de 90 grados (ortogonal a ortogonal diferente)
    return _penalizacionGiro;
  }

  double _heuristica(_NodoGrilla a, _NodoGrilla b) {
    final dx = (a.x - b.x).abs();
    final dy = (a.y - b.y).abs();
    return _paso * (dx + dy + (sqrt2 - 2) * min(dx, dy));
  }

  List<_NodoGrilla> _vecinos(_NodoGrilla nodo) {
    final vecinos = <_NodoGrilla>[];
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) continue;
        final nx = nodo.x + dx;
        final ny = nodo.y + dy;
        if (nx >= 0 && nx < _resolucion && ny >= 0 && ny < _resolucion) {
          vecinos.add(_grilla[nx][ny]);
        }
      }
    }
    return vecinos;
  }

  double _costoMovimiento(_NodoGrilla a, _NodoGrilla b) {
    final dx = (a.x - b.x).abs();
    final dy = (a.y - b.y).abs();
    if (dx == 1 && dy == 1) return _paso * sqrt2;
    return _paso;
  }

  List<Offset> _reconstruirCamino(_NodoGrilla destino) {
    final camino = <Offset>[];
    _NodoGrilla? actual = destino;
    while (actual != null) {
      camino.add(Offset(
        (actual.x + 0.5) * _paso,
        (actual.y + 0.5) * _paso,
      ));
      actual = actual.padre;
    }
    return camino.reversed.toList();
  }

  int _clamp(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}