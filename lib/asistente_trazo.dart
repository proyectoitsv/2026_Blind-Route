import 'dart:math';
import 'dart:ui';

/// Asistente de trazo ("imantado" de ángulos) para la pantalla de
/// configuración: cuando el operador está dibujando un segmento —la línea de
/// medición de escala o una arista de una zona prohibida— y el trazo queda
/// cerca de un ángulo notable (0°, 90°, 180°, 270° y opcionalmente los 45°),
/// el punto se corrige para que la línea quede **exactamente** recta.
///
/// ── Por qué el cálculo se hace en METROS y no en coordenadas normalizadas ──
/// Las posiciones se guardan normalizadas en `[0,1]`, pero el plano se dibuja
/// con la proporción métrica del piso (`escalaX : escalaY`), así que en un
/// plano de 40 m × 10 m una unidad normalizada en X vale 4 veces más metros
/// que en Y. Si el ángulo se midiera sobre las coordenadas normalizadas, la
/// tolerancia sería distinta en cada eje y el imantado no coincidiría con lo
/// que el operador ve en pantalla. Convirtiendo a metros el espacio queda
/// isótropo y el ángulo calculado es el mismo que el ángulo visual.
///
/// El imantado ortogonal (0/90/180/270) daría igual en ambos espacios, pero el
/// de 45° no: por eso todo el cálculo se unifica en metros.
class AsistenteTrazo {
  /// Desvío máximo (en grados) para que el trazo se enganche a un ángulo guía.
  /// ~7° es el valor típico de este tipo de asistentes: alcanza para corregir
  /// el pulso sin impedir que se dibujen ángulos libres a propósito.
  static const double toleranciaGrados = 7.0;

  /// Tolerancia (en metros del mundo real) para alinear un punto con otro ya
  /// existente sobre un eje (guía de cierre del polígono).
  static const double toleranciaAlineacionMetros = 0.4;

  /// Largo mínimo del segmento (en metros) para que el imantado se active. Sin
  /// esto, un trazo de pocos píxeles saltaría entre ángulos guía a cada frame.
  static const double largoMinimoMetros = 0.20;

  static const List<double> _ortogonales = [0, 90, 180, 270];
  static const List<double> _conDiagonales = [0, 45, 90, 135, 180, 225, 270, 315];

  /// Corrige [punto] para que quede alineado con [ancla] en el ángulo guía más
  /// cercano, y opcionalmente con [anclaSecundaria] sobre el eje que el primer
  /// imantado dejó libre (es lo que hace que el último vértice de un
  /// rectángulo cierre perfecto contra el primero).
  ///
  /// - [ancla]: punto de partida del segmento que se está trazando (el vértice
  ///   anterior, o el origen de la línea elástica). Si es null no hay imantado
  ///   de ángulo.
  /// - [anclaSecundaria]: punto con el que además conviene alinearse (el
  ///   vértice siguiente o el primero del polígono, para la arista de cierre).
  /// - [diagonales]: incluye los múltiplos de 45°. Se usa en zonas; en la
  ///   medición de escala se deja en false porque el largo y el ancho del
  ///   plano se miden sobre los ejes.
  ///
  /// Devuelve el punto corregido junto con las guías que quedaron activas,
  /// para que el mapa las pueda dibujar.
  static AjusteTrazo ajustar({
    required Offset punto,
    required double metrosX,
    required double metrosY,
    Offset? ancla,
    Offset? anclaSecundaria,
    bool diagonales = false,
    bool activo = true,
  }) {
    if (!activo) return AjusteTrazo(punto, const []);

    final mx = _metrosSeguros(metrosX);
    final my = _metrosSeguros(metrosY);

    var p = punto;
    final guias = <GuiaTrazo>[];

    // ── 1. Imantado de ángulo respecto del ancla ────────────────────────────
    bool ejeXLibre = false; // el imantado fijó dy: solo se puede mover en x
    bool ejeYLibre = false; // el imantado fijó dx: solo se puede mover en y

    if (ancla != null) {
      final dxM = (punto.dx - ancla.dx) * mx;
      final dyM = (punto.dy - ancla.dy) * my;
      final largo = sqrt(dxM * dxM + dyM * dyM);

      if (largo >= largoMinimoMetros) {
        final actual = atan2(dyM, dxM) * 180 / pi;
        final candidatos = diagonales ? _conDiagonales : _ortogonales;

        double mejorDif = double.infinity;
        double mejorAngulo = 0;
        for (final g in candidatos) {
          final d = _difAngular(actual, g).abs();
          if (d < mejorDif) {
            mejorDif = d;
            mejorAngulo = g;
          }
        }

        if (mejorDif <= toleranciaGrados) {
          final rad = mejorAngulo * pi / 180;
          final dirX = cos(rad), dirY = sin(rad);
          // Proyección sobre la dirección guía: conserva el avance del dedo en
          // vez de estirar el segmento al largo original, así el punto queda
          // debajo del dedo y el gesto se siente natural.
          final proy = dxM * dirX + dyM * dirY;
          p = Offset(
            ((ancla.dx + dirX * proy / mx)).clamp(0.0, 1.0),
            ((ancla.dy + dirY * proy / my)).clamp(0.0, 1.0),
          );
          guias.add(GuiaTrazo(ancla: ancla, anguloGrados: mejorAngulo));

          if (dirY.abs() < 1e-9) {
            ejeXLibre = true; // guía horizontal
          } else if (dirX.abs() < 1e-9) {
            ejeYLibre = true; // guía vertical
          }
        }
      }
    }

    // ── 2. Alineación con el ancla secundaria (arista de cierre) ────────────
    if (anclaSecundaria != null) {
      final s = anclaSecundaria;
      final difX = (p.dx - s.dx).abs() * mx;
      final difY = (p.dy - s.dy).abs() * my;

      if (guias.isEmpty) {
        // Sin imantado de ángulo: se alinean los ejes de forma independiente.
        var nx = p.dx, ny = p.dy;
        if (difX <= toleranciaAlineacionMetros) {
          nx = s.dx;
          guias.add(GuiaTrazo(ancla: s, anguloGrados: 90));
        }
        if (difY <= toleranciaAlineacionMetros) {
          ny = s.dy;
          guias.add(GuiaTrazo(ancla: s, anguloGrados: 0));
        }
        p = Offset(nx, ny);
      } else if (ejeXLibre && difX <= toleranciaAlineacionMetros) {
        // El segmento quedó horizontal: deslizarlo en x hasta alinear con s
        // deja la arista de cierre perfectamente vertical.
        p = Offset(s.dx, p.dy);
        guias.add(GuiaTrazo(ancla: s, anguloGrados: 90));
      } else if (ejeYLibre && difY <= toleranciaAlineacionMetros) {
        p = Offset(p.dx, s.dy);
        guias.add(GuiaTrazo(ancla: s, anguloGrados: 0));
      }
    }

    return AjusteTrazo(p, guias);
  }

  /// Diferencia angular en `[-180, 180)`.
  static double _difAngular(double a, double b) {
    double d = ((a - b) % 360 + 360) % 360;
    if (d > 180) d -= 360;
    return d;
  }

  static double _metrosSeguros(double m) =>
      (m.isFinite && m > 0) ? m : 1.0;
}

/// Una guía activa: la recta que pasa por [ancla] con dirección
/// [anguloGrados] (medidos en el espacio métrico del plano).
class GuiaTrazo {
  final Offset ancla;
  final double anguloGrados;

  const GuiaTrazo({required this.ancla, required this.anguloGrados});

  /// Etiqueta para mostrar al operador. Una guía y su opuesta son la misma
  /// recta, así que se reduce el ángulo al rango `[0, 180)`.
  String get etiqueta {
    final a = anguloGrados % 180;
    return '${a.round()}°';
  }

  @override
  bool operator ==(Object other) =>
      other is GuiaTrazo &&
      other.ancla == ancla &&
      other.anguloGrados == anguloGrados;

  @override
  int get hashCode => Object.hash(ancla, anguloGrados);
}

/// Resultado del asistente: el punto ya corregido y las guías que se activaron.
class AjusteTrazo {
  final Offset punto;
  final List<GuiaTrazo> guias;

  const AjusteTrazo(this.punto, this.guias);

  bool get hayAjuste => guias.isNotEmpty;
}