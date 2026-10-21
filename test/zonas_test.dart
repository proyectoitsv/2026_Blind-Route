import 'package:blindroute/grilla_nav.dart';
import 'package:blindroute/pathfinder.dart';
import 'package:blindroute/restriccion_zonas.dart';
import 'package:blindroute/zona_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ZONAS PROHIBIDAS: BLOQUEO POR CENTRO, PAREDES Y SNAP DE LA POSICIÓN
// ═══════════════════════════════════════════════════════════════════════════
//
// Todos los planos son cuadrados de 10 × 10 m. Las zonas se escriben en
// metros (más fácil de leer) y se pasan a coordenadas normalizadas.

const double _lado = 10.0;

GrillaNav _grilla(double celda) =>
    GrillaNav(metrosX: _lado, metrosY: _lado, tamCeldaMetros: celda);

/// Punto en metros → normalizado.
Offset _n(double x, double y) => Offset(x / _lado, y / _lado);

/// Rectángulo en metros, como polígono.
List<Offset> _rectM(double x0, double y0, double x1, double y1) => [
      Offset(x0, y0),
      Offset(x1, y0),
      Offset(x1, y1),
      Offset(x0, y1),
    ];

ZonaNoTransitable _zona(List<Offset> poligonoM) => ZonaNoTransitable(
      pisoId: 1,
      nombre: 'zona',
      vertices: [for (final p in poligonoM) _n(p.dx, p.dy)],
    );

ResolvedorCaminos _resolvedor(GrillaNav g, List<List<Offset>> zonasM) =>
    ResolvedorCaminos()
      ..inicializar([for (final z in zonasM) _zona(z)], grilla: g);

RestriccionZonas _restriccion(GrillaNav g, ResolvedorCaminos r) =>
    RestriccionZonas(
      grilla: g,
      prohibida: r.esZonaProhibida,
      conectadas: r.conectadas,
      enZona: r.puntoEnZona,
    );

Offset _centro(GrillaNav g, int ix, int iy) =>
    Offset(g.centroX(ix), g.centroY(iy));

List<(int, int)> _celdas(List<Offset> ruta, GrillaNav g) =>
    [for (final c in ruta) (g.indiceX(c.dx), g.indiceY(c.dy))];

/// Adentro ESTRICTO de un polígono convexo (en metros), con un margen para
/// que tocar el borde no cuente. Es una comprobación independiente del
/// código que se prueba (que usa cruce de rayos).
bool _dentroConvexo(Offset p, List<Offset> poli) {
  const tol = 1e-9;
  bool positivos = true, negativos = true;
  for (int i = 0; i < poli.length; i++) {
    final a = poli[i], b = poli[(i + 1) % poli.length];
    final c = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
    if (c <= tol) positivos = false;
    if (c >= -tol) negativos = false;
  }
  return positivos || negativos;
}

/// Ningún tramo de la ruta (segmento entre centros consecutivos) pasa por
/// adentro de las zonas. Se muestrea cada tramo cada 1 cm.
void _expectRutaNoCruza(List<Offset> ruta, List<List<Offset>> zonasM) {
  for (int k = 0; k + 1 < ruta.length; k++) {
    final a = ruta[k] * _lado, b = ruta[k + 1] * _lado;
    final pasos = ((b - a).distance / 0.01).ceil();
    for (int s = 0; s <= pasos; s++) {
      final p = Offset.lerp(a, b, s / pasos)!;
      for (final z in zonasM) {
        expect(_dentroConvexo(p, z), isFalse,
            reason: 'el tramo $k de la ruta pasa por adentro de una zona en $p');
      }
    }
  }
}

/// Cada paso de la ruta es a una celda vecina en cruz (así se mueve el A*).
void _expectPasosEnCruz(List<(int, int)> celdas) {
  for (int k = 0; k + 1 < celdas.length; k++) {
    final dx = (celdas[k + 1].$1 - celdas[k].$1).abs();
    final dy = (celdas[k + 1].$2 - celdas[k].$2).abs();
    expect(dx + dy, 1, reason: 'paso $k: ${celdas[k]} → ${celdas[k + 1]}');
  }
}

void main() {
  // ── Celda de 1 m con una esquina de 20 × 20 cm ────────────────────────────
  group('Celda de 1 m con una esquina de 20 × 20 cm', () {
    final g = _grilla(1.0);
    // Esquina en el ángulo de abajo a la derecha de la celda (5, 5).
    final esquina = _rectM(5.8, 5.8, 6.0, 6.0);

    test('la celda sigue libre', () {
      final r = _resolvedor(g, [esquina]);
      expect(r.esZonaProhibida(5, 5), isFalse);
    });

    test('se conecta en cruz; sólo la diagonal que pasa por la esquina se corta',
        () {
      final r = _resolvedor(g, [esquina]);
      expect(r.conectadas(5, 5, 6, 5), isTrue);
      expect(r.conectadas(5, 5, 5, 6), isTrue);
      expect(r.conectadas(5, 5, 4, 5), isTrue);
      expect(r.conectadas(5, 5, 5, 4), isTrue);
      expect(r.conectadas(5, 5, 4, 4), isTrue);
      // De (5,5; 5,5 m) a (6,5; 6,5 m) la diagonal entra y sale de la
      // esquina justo por dos vértices: igual la atraviesa.
      expect(r.conectadas(5, 5, 6, 6), isFalse);
      expect(r.conectadas(6, 6, 5, 5), isFalse);
    });

    test('la ruta por un pasillo de una celda de ancho pasa por ella', () async {
      // Pasillo en la fila 5 (y entre 5 y 6 m), entre dos bloques.
      final zonas = [_rectM(0, 0, 10, 5), _rectM(0, 6, 10, 10), esquina];
      final r = _resolvedor(g, zonas);
      final ruta = await r.encontrarCamino(_n(1.5, 5.5), _n(8.5, 5.5));
      expect(ruta, isNotNull);
      final celdas = _celdas(ruta!, g);
      expect(celdas, contains((5, 5)));
      expect(celdas.every((c) => c.$2 == 5), isTrue);
      _expectPasosEnCruz(celdas);
      _expectRutaNoCruza(ruta, zonas);
    });

    test('una medición adentro de la esquina se queda en esa celda', () {
      final r = _resolvedor(g, [esquina]);
      final pos = _restriccion(g, r).restringir(_n(5.9, 5.9));
      expect(pos, _centro(g, 5, 5));
    });
  });

  // ── Celda de 1 m con una pared de 20 cm a un costado ──────────────────────
  group('Celda de 1 m con una pared de 20 cm a un costado', () {
    final g = _grilla(1.0);
    // Pared vertical sobre el lado izquierdo de la columna 5, de y = 1 a 8 m.
    final pared = _rectM(5.0, 1.0, 5.2, 8.0);

    test('las celdas de los dos lados siguen libres', () {
      final r = _resolvedor(g, [pared]);
      for (int y = 1; y <= 7; y++) {
        expect(r.esZonaProhibida(4, y), isFalse, reason: 'celda (4, $y)');
        expect(r.esZonaProhibida(5, y), isFalse, reason: 'celda (5, $y)');
      }
    });

    test('la pared corta el paso entre las columnas 4 y 5, y nada más', () {
      final r = _resolvedor(g, [pared]);
      for (int y = 1; y <= 7; y++) {
        expect(r.conectadas(4, y, 5, y), isFalse, reason: 'fila $y');
        expect(r.conectadas(5, y, 4, y), isFalse, reason: 'fila $y');
      }
      for (int y = 1; y <= 6; y++) {
        expect(r.conectadas(5, y, 5, y + 1), isTrue, reason: 'columna 5');
        expect(r.conectadas(4, y, 4, y + 1), isTrue, reason: 'columna 4');
      }
      // Arriba y abajo de la pared se pasa.
      expect(r.conectadas(4, 0, 5, 0), isTrue);
      expect(r.conectadas(4, 8, 5, 8), isTrue);
    });

    test('la ruta a lo largo de la pared va por la columna 5', () async {
      final r = _resolvedor(g, [pared]);
      final ruta = await r.encontrarCamino(_n(5.5, 1.5), _n(5.5, 7.5));
      expect(ruta, isNotNull);
      final celdas = _celdas(ruta!, g);
      expect(celdas.every((c) => c.$1 == 5), isTrue);
      _expectRutaNoCruza(ruta, [pared]);
    });

    test('la ruta de un lado al otro rodea la pared', () async {
      final r = _resolvedor(g, [pared]);
      final ruta = await r.encontrarCamino(_n(4.5, 4.5), _n(5.5, 4.5));
      expect(ruta, isNotNull);
      // En línea recta serían 2 celdas; rodeando por debajo (fila 8), 10.
      expect(ruta!.length, greaterThan(2));
      _expectPasosEnCruz(_celdas(ruta, g));
      _expectRutaNoCruza(ruta, [pared]);
    });
  });

  // ── Celda de 0,5 m con la mitad bloqueada ─────────────────────────────────
  //
  // Celda (10, 10): x e y entre 5,0 y 5,5 m, centro en 5,25 m. Lo que decide
  // es el centro, no cuánto de la celda tapa la zona.
  group('Celda de 0,5 m con la mitad bloqueada', () {
    final g = _grilla(0.5);
    final x0 = 10 * g.tamCeldaX; // 5,0 m
    final x1 = 11 * g.tamCeldaX; // 5,5 m
    final y0 = 10 * g.tamCeldaY;
    final y1 = 11 * g.tamCeldaY;
    final cx = g.centroX(10); // 5,25 m, exacto como lo calcula la grilla

    ResolvedorCaminos conZonaEntre(double xa, double xb) => ResolvedorCaminos()
      ..inicializar([
        ZonaNoTransitable(pisoId: 1, nombre: 'zona', vertices: [
          Offset(xa, y0),
          Offset(xb, y0),
          Offset(xb, y1),
          Offset(xa, y1),
        ]),
      ], grilla: g);

    test('la zona tapa el 60 % y el centro: bloqueada', () {
      final r = conZonaEntre(x0, _n(5.3, 0).dx);
      expect(r.esZonaProhibida(10, 10), isTrue);
    });

    test('la zona tapa el 40 % y no llega al centro: libre', () {
      final r = conZonaEntre(x0, _n(5.2, 0).dx);
      expect(r.esZonaProhibida(10, 10), isFalse);
    });

    // Mitad exacta: el borde de la zona pasa JUSTO por el centro. Lo decide
    // la regla del cruce de rayos, que es fija: sobre el borde izquierdo o de
    // arriba de la zona el centro cuenta como adentro, sobre el derecho o el
    // de abajo, como afuera. Se calcula una vez al cargar el piso.

    test('mitad izquierda (centro sobre el borde derecho de la zona): libre',
        () {
      final r = conZonaEntre(x0, cx);
      expect(r.esZonaProhibida(10, 10), isFalse);
      // Se conecta hacia afuera de la zona y a lo largo de su borde; hacia
      // adentro, no.
      expect(r.conectadas(10, 10, 11, 10), isTrue);
      expect(r.conectadas(10, 10, 10, 9), isTrue);
      expect(r.conectadas(10, 10, 10, 11), isTrue);
      expect(r.conectadas(10, 10, 9, 10), isFalse);
    });

    test('mitad derecha (centro sobre el borde izquierdo de la zona): bloqueada',
        () {
      final r = conZonaEntre(cx, x1);
      expect(r.esZonaProhibida(10, 10), isTrue);
    });
  });

  // ── La posición no cambia de celda con la medición en medio de una pared ──
  group('Medición en el medio de una pared: la posición no cambia de celda', () {
    final g = _grilla(1.0);
    // Mediciones que van y vienen alrededor del medio de la pared (x = 5 m).
    const xs = [4.95, 5.05, 5.0, 5.08, 4.92, 5.03];

    /// Corre [ciclos] ciclos realimentando la posición restringida, como la
    /// pantalla de navegación, y devuelve las celdas (x) de cada ciclo.
    List<int> simular(RestriccionZonas rz, Offset inicial, {int ciclos = 30}) {
      var previa = inicial;
      final celdas = <int>[];
      for (int k = 0; k < ciclos; k++) {
        final p = _n(xs[k % xs.length], 5.5);
        previa = rz.restringir(p, previa: previa);
        celdas.add(g.indiceX(previa.dx));
      }
      return celdas;
    }

    test('pared angosta de 20 cm (no tapa ningún centro)', () {
      final r = _resolvedor(g, [_rectM(4.9, 1.0, 5.1, 9.0)]);
      final rz = _restriccion(g, r);
      expect(r.esZonaProhibida(4, 5), isFalse);
      expect(r.esZonaProhibida(5, 5), isFalse);
      expect(simular(rz, _n(4.5, 5.5)).toSet(), {4});
      expect(simular(rz, _n(5.5, 5.5)).toSet(), {5});
    });

    test('pared gruesa de 2 m (tapa los centros de dos columnas)', () {
      final r = _resolvedor(g, [_rectM(4.0, 1.0, 6.0, 9.0)]);
      final rz = _restriccion(g, r);
      expect(r.esZonaProhibida(4, 5), isTrue);
      expect(r.esZonaProhibida(5, 5), isTrue);
      expect(simular(rz, _centro(g, 3, 5)).toSet(), {3});
      expect(simular(rz, _centro(g, 6, 5)).toSet(), {6});
    });
  });

  // ── Snap al centro de la celda libre más cercana ──────────────────────────
  group('Snap', () {
    final g = _grilla(1.0);
    final bloque = _rectM(4.0, 1.0, 6.0, 9.0);

    test('una medición en un lugar transitable se devuelve tal cual', () {
      final rz = _restriccion(g, _resolvedor(g, [bloque]));
      final p = _n(2.3, 2.7);
      expect(rz.restringir(p), p);
    });

    test('una medición en una celda bloqueada va al centro de la libre más '
        'cercana', () {
      final rz = _restriccion(g, _resolvedor(g, [bloque]));
      expect(rz.restringir(_n(4.2, 5.5)), _centro(g, 3, 5));
      expect(rz.restringir(_n(5.8, 5.5)), _centro(g, 6, 5));
    });
  });

  // ── La ruta no cruza zonas ────────────────────────────────────────────────
  group('La ruta no cruza zonas', () {
    final g = _grilla(1.0);
    // Pared diagonal de 20 cm sobre la recta y = x + 0,5 m, de x = 2 a 8 m.
    // Pasa entre los centros de celda (no tapa ninguno), así que lo único
    // que la cierra son las paredes. Más un bloque grueso.
    const e = 0.0707; // 0,1 m en la dirección perpendicular a la diagonal
    final diagonal = [
      const Offset(2 + e, 2.5 - e),
      const Offset(8 + e, 8.5 - e),
      const Offset(8 - e, 8.5 + e),
      const Offset(2 - e, 2.5 + e),
    ];
    final bloque = _rectM(6.0, 1.0, 8.0, 3.0);
    final zonas = [diagonal, bloque];

    test('ninguna celda de la diagonal queda bloqueada', () {
      final r = _resolvedor(g, zonas);
      for (int i = 2; i <= 7; i++) {
        expect(r.esZonaProhibida(i, i), isFalse);
        expect(r.esZonaProhibida(i, i + 1), isFalse);
      }
    });

    test('las conexiones son simétricas', () {
      final r = _resolvedor(g, zonas);
      for (int x = 0; x < g.celdasX; x++) {
        for (int y = 0; y < g.celdasY; y++) {
          for (final (dx, dy) in const [
            (1, 0), (0, 1), (1, 1), (-1, 1),
          ]) {
            expect(r.conectadas(x, y, x + dx, y + dy),
                r.conectadas(x + dx, y + dy, x, y),
                reason: '($x, $y) ↔ (${x + dx}, ${y + dy})');
          }
        }
      }
    });

    // Cada par va de un lado de la diagonal al otro (en metros).
    for (final (desde, hasta) in const [
      (Offset(6.5, 4.5), Offset(3.5, 6.5)),
      (Offset(8.5, 4.5), Offset(1.5, 8.5)),
      (Offset(4.5, 2.5), Offset(4.5, 7.5)),
    ]) {
      test('de (${desde.dx}, ${desde.dy}) m a (${hasta.dx}, ${hasta.dy}) m',
          () async {
        final r = _resolvedor(g, zonas);
        final ruta = await r.encontrarCamino(
          _n(desde.dx, desde.dy),
          _n(hasta.dx, hasta.dy),
        );
        expect(ruta, isNotNull);
        _expectPasosEnCruz(_celdas(ruta!, g));
        _expectRutaNoCruza(ruta, zonas);
      });
    }
  });
}
