import 'package:blindroute/grilla_nav.dart';
import 'package:blindroute/histeresis_celda.dart';
import 'package:blindroute/pathfinder.dart';
import 'package:blindroute/zona_model.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HISTÉRESIS DE CELDA FRENTE A UNA PARED ANGOSTA
// ═══════════════════════════════════════════════════════════════════════════
//
// Planos cuadrados de 10 × 10 m, como en zonas_test.dart. La pared es de
// 20 cm, vertical, de x = 5,0 a 5,2 m: con celdas de 1 m deja libres las
// columnas 4 y 5 y corta el paso entre ellas.
//
// Los ciclos son los de la pantalla de navegación caminando: 1 del mismo
// lado, 5 del otro lado de una pared.

const double _lado = 10.0;

GrillaNav _grilla(double celda) =>
    GrillaNav(metrosX: _lado, metrosY: _lado, tamCeldaMetros: celda);

List<Offset> _rectM(double x0, double y0, double x1, double y1) => [
      Offset(x0 / _lado, y0 / _lado),
      Offset(x1 / _lado, y0 / _lado),
      Offset(x1 / _lado, y1 / _lado),
      Offset(x0 / _lado, y1 / _lado),
    ];

HisteresisCelda _histeresis(GrillaNav g, List<List<Offset>> zonas) {
  final r = ResolvedorCaminos()
    ..inicializar([
      for (final z in zonas)
        ZonaNoTransitable(pisoId: 1, nombre: 'zona', vertices: z),
    ], grilla: g);
  return HisteresisCelda(
    grilla: g,
    prohibida: r.esZonaProhibida,
    conectadas: r.conectadas,
  );
}

/// Propone [veces] veces la celda [c] y devuelve la confirmada al final.
(int, int)? _proponer(
  HisteresisCelda h,
  (int, int) c,
  int veces, {
  int ciclos = 1,
  int? ciclosPared = 5,
}) {
  ({int ix, int iy})? r;
  for (int i = 0; i < veces; i++) {
    r = h.actualizar(c.$1, c.$2, ciclos: ciclos, ciclosPared: ciclosPared);
  }
  return r == null ? null : (r.ix, r.iy);
}

void main() {
  final pared = _rectM(5.0, 1.0, 5.2, 8.0);

  group('Sin pared en el medio, igual que antes', () {
    test('caminando, una celda vecina se confirma en 1 ciclo', () {
      final h = _histeresis(_grilla(1.0), []);
      _proponer(h, (4, 4), 1);
      expect(_proponer(h, (5, 4), 1), (5, 4));
    });

    test('al lado de la pared, moverse por el mismo lado es inmediato', () {
      final h = _histeresis(_grilla(1.0), [pared]);
      _proponer(h, (4, 4), 1);
      expect(_proponer(h, (4, 5), 1), (4, 5));
    });

    test('con una puerta cerca, pasar al otro lado no cuenta como pared', () {
      // Pared con un hueco de 1 m en la fila 4 (y de 4 a 5 m).
      final h = _histeresis(
          _grilla(1.0), [_rectM(5.0, 1.0, 5.2, 4.0), _rectM(5.0, 5.0, 5.2, 8.0)]);
      _proponer(h, (4, 3), 1);
      // Por la puerta son 3 pasos en vez de 1: un rodeo de 2 m.
      expect(_proponer(h, (5, 3), 1), (5, 3));
    });

    test('sin ciclosPared (restricción apagada) la pared no se mira', () {
      final h = _histeresis(_grilla(1.0), [pared]);
      _proponer(h, (4, 4), 1, ciclosPared: null);
      expect(_proponer(h, (5, 4), 1, ciclosPared: null), (5, 4));
    });
  });

  group('Del otro lado de una pared de 20 cm', () {
    test('caminando hacen falta 5 ciclos seguidos', () {
      final h = _histeresis(_grilla(1.0), [pared]);
      _proponer(h, (4, 4), 1);
      expect(_proponer(h, (5, 4), 4), (4, 4));
      expect(_proponer(h, (5, 4), 1), (5, 4));
    });

    test('parado hacen falta los ciclos que se pidan (11)', () {
      final h = _histeresis(_grilla(1.0), [pared]);
      _proponer(h, (4, 4), 1, ciclos: 3, ciclosPared: 11);
      expect(_proponer(h, (5, 4), 10, ciclos: 3, ciclosPared: 11), (4, 4));
      expect(_proponer(h, (5, 4), 1, ciclos: 3, ciclosPared: 11), (5, 4));
    });

    test('un ciclo de vuelta del lado propio reinicia el conteo', () {
      final h = _histeresis(_grilla(1.0), [pared]);
      _proponer(h, (4, 4), 1);
      _proponer(h, (5, 4), 4);
      _proponer(h, (4, 4), 1);
      expect(_proponer(h, (5, 4), 4), (4, 4));
    });

    test('se cuenta el lado, no la celda (celdas de 0,5 m)', () {
      // Columnas 9 (x de 4,5 a 5,0 m) y 10 (de 5,0 a 5,5 m): la pared no tapa
      // ningún centro y corta el paso entre ellas.
      final h = _histeresis(_grilla(0.5), [pared]);
      _proponer(h, (9, 8), 1);
      // El ruido reparte las mediciones entre varias celdas del otro lado.
      for (final c in [(10, 8), (11, 8), (10, 9), (11, 9)]) {
        expect(_proponer(h, c, 1), (9, 8), reason: 'candidata $c');
      }
      expect(_proponer(h, (10, 8), 1), (10, 8));
    });
  });

  group('Volver después de cruzar una pared', () {
    // Cruza de (4, 4) a (5, 4) con los 5 ciclos de la pared.
    HisteresisCelda cruzada() {
      final h = _histeresis(_grilla(1.0), [pared]);
      _proponer(h, (4, 4), 1);
      expect(_proponer(h, (5, 4), 5), (5, 4));
      return h;
    }

    test('enseguida, volver al lado de antes cuesta lo normal', () {
      final h = cruzada();
      expect(_proponer(h, (4, 4), 1), (4, 4));
    });

    test('deshacer no abre otra ventana: cruzar de nuevo pide 5 ciclos', () {
      final h = cruzada();
      _proponer(h, (4, 4), 1);
      expect(_proponer(h, (5, 4), 4), (4, 4));
      expect(_proponer(h, (5, 4), 1), (5, 4));
    });

    test('la ventana dura ${HisteresisCelda.ciclosParaDeshacer} ciclos', () {
      final dentro = cruzada();
      _proponer(dentro, (5, 4), HisteresisCelda.ciclosParaDeshacer - 1);
      expect(_proponer(dentro, (4, 4), 1), (4, 4));

      final fuera = cruzada();
      _proponer(fuera, (5, 4), HisteresisCelda.ciclosParaDeshacer);
      expect(_proponer(fuera, (4, 4), 4), (5, 4));
      expect(_proponer(fuera, (4, 4), 1), (4, 4));
    });

    test('moverse del otro lado no cierra la ventana', () {
      final h = cruzada();
      expect(_proponer(h, (5, 5), 1), (5, 5));
      expect(_proponer(h, (4, 5), 1), (4, 5));
    });
  });
}
