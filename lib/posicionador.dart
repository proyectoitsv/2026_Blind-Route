import 'dart:math';
import 'dart:ui';

/// Una observación de rango: la posición (normalizada) de un beacon y la
/// distancia (m) que se le estimó a partir de su RSSI filtrado.
class ObservacionRango {
  /// Posición del beacon, normalizada `[0,1]` respecto de la imagen del plano.
  final Offset posBeacon;

  /// Distancia estimada beacon↔usuario, en metros (modelo log-distancia).
  final double distancia;

  /// Peso relativo de la observación (mayor = más confiable). Como el error en
  /// metros del modelo log crece con la distancia, conviene que un beacon
  /// cercano pese más que uno lejano.
  final double confianza;

  const ObservacionRango(this.posBeacon, this.distancia, this.confianza);
}

/// Estima la posición del usuario (normalizada) por **multilateración** de los
/// rangos a los beacons.
///
/// ── POR QUÉ ESTO REEMPLAZA AL CENTROIDE PONDERADO ──────────────────────────
/// El método anterior calculaba `posición = Σ(pos_beaconᵢ · wᵢ) / Σwᵢ`, con
/// `wᵢ = 1/dᵢ²`. Eso es un **promedio de las posiciones de los beacons**: por
/// más que se afine el peso, el resultado NUNCA puede salirse del interior de
/// la nube de beacons, y de hecho tiende a su centro. Consecuencia:
///
///   • Pegado a un beacon → ese beacon domina el peso y la posición "se pega"
///     a él: sale bien. (Por eso andaba bien cerca de un beacon.)
///   • En el medio, equidistante de varios → todos los pesos se parecen y la
///     posición COLAPSA al centro geométrico del layout, sin relación con
///     dónde está la persona realmente. (Por eso andaba mal "en el medio".)
///
/// Medido en simulación (ruido BLE post-mediana ≈ 1,5 dBm), el centroide
/// ponderado arrastra un **sesgo sistemático hacia el centro** que crece con la
/// distancia al centroide: ~0,2 m a 3 m del centro, ~1,3 m a 7 m. La
/// multilateración baja ese error a ~0,3 m en los mismos puntos.
///
/// La multilateración usa las distancias como **restricciones geométricas**
/// (circunferencias de radio dᵢ centradas en cada beacon) y busca el punto que
/// mejor las satisface por mínimos cuadrados. Ese punto puede caer en cualquier
/// parte del plano —bordes y esquinas incluidos— y no colapsa al centro.
///
/// ── CÓMO ────────────────────────────────────────────────────────────────
/// • Se resuelve en **metros**, no en normalizado: las distancias del modelo
///   log solo tienen sentido geométrico en un marco métrico, y los ejes pueden
///   tener escalas muy distintas (metrosX ≠ metrosY). Se convierte a metros,
///   se resuelve, y se vuelve a normalizar al final.
/// • **Gauss-Newton** (pocas iteraciones; converge rápido) inicializado en el
///   centroide ponderado: es un arranque robusto y barato, y además sirve de
///   fallback si la geometría es mala.
/// • **IRLS con peso de Huber** sobre el residuo de rango: un beacon con
///   multipath (rango espurio, típicamente "más cerca" de lo real) se descarta
///   solo, sin arruinar la solución. Sin esto, un rebote fuerte tironea la
///   posición como lo hacía el centroide.
/// • **Amortiguación Levenberg-Marquardt** (λI en la normal) para que el
///   sistema 2×2 no se vuelva singular con geometrías degeneradas (beacons casi
///   colineales, o sólo 2 visibles).
class Posicionador {
  /// Umbral de Huber (m): por encima de este residuo de rango, la observación
  /// empieza a descartarse progresivamente (robustez ante multipath).
  static const double _kHuber = 2.5;

  /// Amortiguación Levenberg-Marquardt de la normal 2×2. Chica: sólo estabiliza
  /// geometrías malas sin frenar la convergencia en las buenas.
  static const double _lambda = 0.05;

  /// ── ANCLA TEMPORAL (la clave contra los saltos) ──────────────────────────
  /// La multilateración pura resuelve cada frame DE CERO: con rangos RSSI
  /// ruidosos y geometrías malas (dilución de precisión) un solo pico de
  /// multipath, o que entre/salga un beacon del set visible, la manda lejos.
  /// El One Euro no puede taparlo —ante un salto grande SUBE su corte y lo deja
  /// pasar—: la robustez tiene que estar acá. Se agrega un término que tira la
  /// solución hacia la posición ANTERIOR (regularización de Tikhonov hacia esa
  /// ancla). Efectos:
  ///   • un outlier de un frame ya no puede mover la posición: el ancla la
  ///     sostiene;
  ///   • estabiliza geometrías degeneradas (suma un término bien condicionado a
  ///     la normal → no hay "flips" por GDOP);
  ///   • NO reintroduce el sesgo al centro: el ancla es la posición previa, no
  ///     el centroide.
  /// El peso del ancla lo gobierna el acelerómetro, igual que el One Euro:
  /// fuerte con el usuario quieto (nada debería moverse, todo salto es ruido) y
  /// suave al caminar (para poder seguir el movimiento real). Se expresa como
  /// múltiplo del peso total de los rangos → es independiente de cuántos
  /// beacons haya visibles en el frame.
  static const double _priorQuieto = 3.0;
  static const double _priorMoviendo = 0.25;

  /// ── RESTRICCIÓN ANISOTRÓPICA POR RUMBO (brújula) ─────────────────────────
  /// La persona camina en la dirección en que mira: el rumbo define un EJE de
  /// movimiento permitido. A lo largo de ese eje el ancla es BLANDA (deja
  /// avanzar/retroceder siguiendo el paso real); en la dirección PERPENDICULAR
  /// es DURA (frena la deriva lateral —el avatar yéndose de este a oeste sin que
  /// la persona se desplace ni mire para allá—, que es puro ruido BLE). Si la
  /// persona gira, el eje rota con el rumbo, así que esto NO bloquea los giros:
  /// lo que un instante fue "lateral" pasa a ser "a lo largo" en el rumbo nuevo.
  /// Es la histéresis direccional que pediste. Sólo aplica si hay rumbo válido;
  /// sin brújula, se cae al ancla isotrópica de arriba (sin cambios).
  static const double _priorAlongQuieto = 1.8;
  static const double _priorAlongMoviendo = 0.2;
  static const double _priorPerp = 3.0;

  /// Tope de paso por iteración (m): evita que una iteración de Gauss-Newton
  /// "teletransporte" la solución si el sistema está mal condicionado.
  static const double _maxPasoIterM = 4.0;

  /// Estima la posición (normalizada `[0,1]`) a partir de las observaciones de
  /// rango [obs] y la escala del piso ([metrosX] × [metrosY]).
  static Offset estimar(
    List<ObservacionRango> obs, {
    required double metrosX,
    required double metrosY,
    // Posición estimada en el frame anterior (normalizada). Es el ancla
    // temporal y el arranque en caliente del solver. `null` en el primer frame.
    Offset? posPrevia,
    // Factor de movimiento del acelerómetro (0 = quieto, 1 = caminando).
    // Gobierna la fuerza del ancla: quieto ancla fuerte, moviéndose ancla suave.
    double factorMovimiento = 1.0,
    // Rumbo del usuario en el marco del PLANO, como versor en coordenadas
    // normalizadas de pantalla (x→derecha, y→abajo). Es la dirección de la
    // brújula ya descontada la rotación del mapa. Si no hay brújula, `null` y
    // el ancla vuelve a ser isotrópica.
    Offset? rumboPlano,
    int maxIter = 12,
  }) {
    if (obs.isEmpty) return posPrevia ?? const Offset(0.5, 0.5);
    final fMov = factorMovimiento.clamp(0.0, 1.0);

    // Centroide ponderado por confianza: arranque de Gauss-Newton y fallback.
    double sx = 0, sy = 0, sw = 0;
    for (final o in obs) {
      sx += o.posBeacon.dx * o.confianza;
      sy += o.posBeacon.dy * o.confianza;
      sw += o.confianza;
    }
    final centroide =
        sw > 0 ? Offset(sx / sw, sy / sw) : const Offset(0.5, 0.5);

    // Con menos de 3 rangos la multilateración es ambigua (2 circunferencias se
    // cortan en 0/1/2 puntos). En vez de saltar al centroide (que se mueve
    // bruscamente cada vez que cambia el set de beacons visibles), se avanza
    // suavemente desde la posición previa hacia el centroide: quieto casi no se
    // mueve, caminando cede más. Sin previa (primer frame), el centroide.
    if (obs.length < 3) {
      if (posPrevia == null) return centroide;
      final a = (0.12 + 0.4 * fMov).clamp(0.0, 1.0);
      return Offset(
        posPrevia.dx + (centroide.dx - posPrevia.dx) * a,
        posPrevia.dy + (centroide.dy - posPrevia.dy) * a,
      );
    }

    final mx = (metrosX.isFinite && metrosX > 0) ? metrosX : 1.0;
    final my = (metrosY.isFinite && metrosY > 0) ? metrosY : 1.0;

    // Arranque EN CALIENTE desde la posición previa: da continuidad temporal y
    // evita que el solver caiga en un mínimo local distinto de un frame al otro
    // (fuente típica de saltos). Sin previa, arranca en el centroide.
    final inicio = posPrevia ?? centroide;
    double x = inicio.dx * mx;
    double y = inicio.dy * my;

    // Ancla temporal en métrico (hacia dónde tira el prior).
    final tienePrevia = posPrevia != null;
    final pxPrev = (posPrevia?.dx ?? centroide.dx) * mx;
    final pyPrev = (posPrevia?.dy ?? centroide.dy) * my;

    final n = obs.length;
    final bx = List<double>.filled(n, 0);
    final by = List<double>.filled(n, 0);
    final d = List<double>.filled(n, 0);
    final wc = List<double>.filled(n, 0);
    double sumWc = 0;
    for (int i = 0; i < n; i++) {
      bx[i] = obs[i].posBeacon.dx * mx;
      by[i] = obs[i].posBeacon.dy * my;
      d[i] = obs[i].distancia;
      wc[i] = obs[i].confianza;
      sumWc += wc[i];
    }

    // ── Ancla temporal: matriz de rigidez 2×2 (pa11, pa12, pa22) ────────────
    // Es un término cuadrático alrededor de la posición previa. Sin rumbo es
    // isotrópico (pa11=pa22=kIso, pa12=0) → idéntico al ancla anterior. Con
    // rumbo se hace ANISOTRÓPICO: blando a lo largo del eje del rumbo, duro en
    // perpendicular. Las entradas no dependen de (x,y), se calculan una vez.
    double pa11 = 0, pa12 = 0, pa22 = 0;
    if (tienePrevia) {
      // Versor del rumbo en marco MÉTRICO: un mismo desplazamiento normalizado
      // mide distinto en cada eje (mx≠my), así que hay que llevarlo a metros y
      // renormalizar para que "a lo largo" sea la dirección física real.
      double? hx, hy;
      if (rumboPlano != null) {
        double hmx = rumboPlano.dx * mx, hmy = rumboPlano.dy * my;
        final hn = sqrt(hmx * hmx + hmy * hmy);
        if (hn > 1e-6) {
          hx = hmx / hn;
          hy = hmy / hn;
        }
      }
      if (hx != null && hy != null) {
        // Con rumbo: eje blando (kAlong) + perpendicular duro (kPerp).
        final kAlong = sumWc *
            (_priorAlongQuieto + (_priorAlongMoviendo - _priorAlongQuieto) * fMov);
        final kPerp = sumWc * _priorPerp;
        // H = kAlong·h·hᵀ + kPerp·n·nᵀ,  con n = (−hy, hx) perpendicular.
        pa11 = kAlong * hx * hx + kPerp * hy * hy;
        pa12 = (kAlong - kPerp) * hx * hy;
        pa22 = kAlong * hy * hy + kPerp * hx * hx;
      } else {
        // Sin rumbo válido: ancla isotrópica (comportamiento anterior).
        final kIso = sumWc * (_priorQuieto + (_priorMoviendo - _priorQuieto) * fMov);
        pa11 = kIso;
        pa22 = kIso;
      }
    }

    for (int it = 0; it < maxIter; it++) {
      // Normal 2×2 (JᵀWJ) y gradiente (JᵀW r), con amortiguación LM en la
      // diagonal. Se arma a mano para evitar asignaciones en el hot path.
      // Arranca con el término del ANCLA (matriz de rigidez pa·· + su gradiente
      // pa·(x−ancla)): eso tira la solución hacia la posición previa, blando a
      // lo largo del rumbo y duro en perpendicular.
      final dxp = x - pxPrev, dyp = y - pyPrev;
      double a11 = _lambda + pa11, a12 = pa12, a22 = _lambda + pa22;
      double g1 = pa11 * dxp + pa12 * dyp, g2 = pa12 * dxp + pa22 * dyp;
      for (int i = 0; i < n; i++) {
        final ex = x - bx[i], ey = y - by[i];
        double rng = sqrt(ex * ex + ey * ey);
        if (rng < 1e-3) rng = 1e-3;
        final r = rng - d[i]; // residuo de rango (m)
        final ar = r.abs();
        final huber = ar <= _kHuber ? 1.0 : _kHuber / ar;
        final w = wc[i] * huber;
        final jx = ex / rng, jy = ey / rng; // versor beacon→x (fila del jacob.)
        a11 += w * jx * jx;
        a12 += w * jx * jy;
        a22 += w * jy * jy;
        g1 += w * jx * r;
        g2 += w * jy * r;
      }
      final det = a11 * a22 - a12 * a12;
      if (det.abs() < 1e-9) break; // singular pese al LM: cortar
      // Paso de Gauss-Newton: (JᵀWJ)·paso = JᵀW r  →  x ← x − paso.
      double pasoX = (a22 * g1 - a12 * g2) / det;
      double pasoY = (a11 * g2 - a12 * g1) / det;
      // Tope de paso por iteración: si el sistema está mal condicionado, un paso
      // enorme teletransportaría la solución. Se recorta manteniendo dirección.
      final pasoN = sqrt(pasoX * pasoX + pasoY * pasoY);
      if (pasoN > _maxPasoIterM) {
        final s = _maxPasoIterM / pasoN;
        pasoX *= s;
        pasoY *= s;
      }
      x -= pasoX;
      y -= pasoY;
      // Recorte al plano en cada iteración: la posición no puede salirse.
      x = x.clamp(0.0, mx);
      y = y.clamp(0.0, my);
      if (pasoX * pasoX + pasoY * pasoY < 1e-6) break; // convergió
    }

    final nx = (x / mx).clamp(0.0, 1.0);
    final ny = (y / my).clamp(0.0, 1.0);
    if (!nx.isFinite || !ny.isFinite) return centroide; // por las dudas
    return Offset(nx, ny);
  }
}