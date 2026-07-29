import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart' show debugPrint;

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
/// la nube de beacons, y de hecho tiende a su centro.
///
/// La multilateración usa las distancias como **restricciones geométricas**
/// (circunferencias de radio dᵢ centradas en cada beacon) y busca el punto que
/// mejor las satisface por mínimos cuadrados. Ese punto puede caer en cualquier
/// parte del plano —bordes y esquinas incluidos— y no colapsa al centro.
///
/// ── CÓMO ────────────────────────────────────────────────────────────────
/// • Se resuelve en **metros**, no en normalizado: las distancias del modelo
///   log solo tienen sentido geométrico en un marco métrico, y los ejes pueden
///   tener escalas muy distintas (metrosX ≠ metrosY).
/// • **Gauss-Newton** inicializado en el centroide ponderado (arranque robusto
///   y barato, y fallback si la geometría es mala).
/// • **IRLS con peso de Huber** sobre el residuo de rango: un beacon con
///   multipath se descarta solo, sin arruinar la solución.
/// • **Amortiguación Levenberg-Marquardt** (λI en la normal) para que el
///   sistema 2×2 no se vuelva singular con geometrías degeneradas.
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
  /// Se agrega un término que tira la solución hacia la posición ANTERIOR
  /// (regularización de Tikhonov hacia esa ancla). Efectos:
  ///   • un outlier de un frame ya no puede mover la posición;
  ///   • estabiliza geometrías degeneradas (no hay "flips" por GDOP);
  ///   • NO reintroduce el sesgo al centro: el ancla es la posición previa.
  /// El peso lo gobierna el acelerómetro: fuerte con el usuario quieto y suave
  /// al caminar. Se expresa como múltiplo del peso total de los rangos → es
  /// independiente de cuántos beacons haya visibles en el frame.
  static const double _priorQuieto = 3.0;
  static const double _priorMoviendo = 0.25;

  /// ── SESGO ANISOTRÓPICO POR RUMBO (brújula) ───────────────────────────────
  ///
  /// OJO con qué hace y qué NO hace este término, porque la versión anterior le
  /// pedía algo que un prior cuadrático no puede dar.
  ///
  /// El ancla es un término cuadrático alrededor de la posición previa. Su
  /// efecto sobre el desplazamiento de un ciclo es una **ganancia lineal**:
  /// `Δsalida ≈ Δmedición / (1 + k)`. Es decir, un pasa-bajos direccional. Eso
  /// atenúa por igual al ruido y al movimiento real y, como es recursivo,
  /// cualquier empuje lateral SOSTENIDO termina pasando entero en unos pocos
  /// ciclos. Un prior cuadrático **no puede** distinguir "ruido" de "señal
  /// fuerte y persistente": las trata igual, sólo que más lento.
  ///
  /// Por eso acá el rumbo hace únicamente lo que un prior sí sabe hacer:
  /// condicionar el problema, favoreciendo levemente las soluciones que
  /// explican los rangos moviéndose a lo largo del eje de marcha. La decisión
  /// "esto es ruido lateral / esto es movimiento lateral real" se toma después,
  /// en [PuertaRumbo], que sí tiene memoria y sí puede medir persistencia.
  ///
  /// El factor se aplica SOLO en la dirección perpendicular y **escala con el
  /// movimiento**: con el usuario detenido no existe una "dirección de marcha"
  /// que privilegiar (todo desplazamiento es ruido en cualquier eje) y el ancla
  /// vuelve a ser isotrópica. La versión anterior hacía justo lo contrario
  /// —ablandaba el eje longitudinal a 1.8 con el usuario quieto, contra 3.0 del
  /// ancla isotrópica—, así que activar la brújula dejaba la posición MÁS
  /// suelta hacia adelante y atrás que no tenerla.
  ///
  /// Se lo mantiene deliberadamente moderado (×2.5 como máximo): si se lo sube
  /// mucho, el solver borra la evidencia lateral y [PuertaRumbo] se queda ciega
  /// —nunca vería el desplazamiento lateral real que tiene que dejar pasar—.
  static const double _factorPerpMax = 2.5;

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
    double factorMovimiento = 1.0,
    // Rumbo del usuario en el marco del PLANO, como versor en coordenadas
    // normalizadas de pantalla (x→derecha, y→abajo). Es la dirección de la
    // brújula ya descontada la rotación del mapa. Si no hay brújula, `null` y
    // el ancla es isotrópica.
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

    // Con menos de 3 rangos la multilateración es ambigua. En vez de saltar al
    // centroide (que se mueve bruscamente cada vez que cambia el set visible),
    // se avanza suavemente desde la posición previa hacia el centroide.
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
    // evita que el solver caiga en un mínimo local distinto de un frame al otro.
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
    // Las entradas no dependen de (x,y): se calculan una sola vez.
    double pa11 = 0, pa12 = 0, pa22 = 0;
    if (tienePrevia) {
      final kIso =
          sumWc * (_priorQuieto + (_priorMoviendo - _priorQuieto) * fMov);

      // Versor del rumbo en marco MÉTRICO: un mismo desplazamiento normalizado
      // mide distinto en cada eje (mx≠my), así que hay que llevarlo a metros y
      // renormalizar para que "a lo largo" sea la dirección física real.
      double? hx, hy;
      if (rumboPlano != null) {
        final double hmx = rumboPlano.dx * mx, hmy = rumboPlano.dy * my;
        final hn = sqrt(hmx * hmx + hmy * hmy);
        if (hn > 1e-6) {
          hx = hmx / hn;
          hy = hmy / hn;
        }
      }

      if (hx != null && hy != null) {
        // A lo largo del rumbo se conserva EXACTAMENTE la rigidez isotrópica
        // (nunca queda más suelto que sin brújula); sólo se endurece el eje
        // perpendicular, y de forma proporcional al movimiento.
        final kAlong = kIso;
        final kPerp = kIso * (1.0 + (_factorPerpMax - 1.0) * fMov);
        // H = kAlong·h·hᵀ + kPerp·n·nᵀ,  con n = (−hy, hx) perpendicular.
        pa11 = kAlong * hx * hx + kPerp * hy * hy;
        pa12 = (kAlong - kPerp) * hx * hy;
        pa22 = kAlong * hy * hy + kPerp * hx * hx;
      } else {
        pa11 = kIso;
        pa22 = kIso;
      }
    }

    for (int it = 0; it < maxIter; it++) {
      // Normal 2×2 (JᵀWJ) y gradiente (JᵀW r), con amortiguación LM en la
      // diagonal. Se arma a mano para evitar asignaciones en el hot path.
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

/// ═══════════════════════════════════════════════════════════════════════════
/// PUERTA DIRECCIONAL POR RUMBO
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Acá vive de verdad la regla "la persona se mueve hacia donde mira; lo demás
/// es ruido, salvo que sea fuerte y persistente".
///
/// ── POR QUÉ NO ALCANZABA CON EL PRIOR DEL SOLVER ───────────────────────────
/// Un prior cuadrático (ver [Posicionador]) es un pasa-bajos: aplica la misma
/// ganancia `1/(1+k)` al ruido y al movimiento real. No tiene memoria, así que
/// no puede evaluar "persistencia", que es justamente la palabra clave del
/// requisito.
///
/// ── EL DISCRIMINADOR QUE SÍ SIRVE: EL SIGNO ────────────────────────────────
/// El ruido BLE lateral **cambia de signo** ciclo a ciclo (es aproximadamente
/// de media cero): si se promedia el desplazamiento lateral CON SIGNO sobre un
/// par de segundos, el ruido se cancela solo. El movimiento lateral real, en
/// cambio, mantiene el signo mientras dura. Esa es toda la idea:
///
///   • [_evidenciaLateral] = EMA del desplazamiento lateral CON SIGNO,
///     expresado como velocidad (m/s). Ruido → tiende a 0. Movimiento real →
///     tiende a la velocidad real de la persona.
///   • Además se exige que el signo sea CONSISTENTE durante
///     [_minCiclosConsistentes] ciclos seguidos, así una ráfaga de multipath
///     que casualmente empuje para el mismo lado tiene que sostenerse ~1 s.
///
/// Con la puerta CERRADA el desplazamiento lateral pasa al 10 %; con la puerta
/// ABIERTA pasa entero. Apertura y cierre son rampas (constante de tiempo
/// [_tauAperturaSeg]) para que no haya un salto visible al conmutar, y el
/// cierre usa un umbral más bajo que la apertura (histéresis anti-titileo).
///
/// ── ASIMETRÍA ADELANTE / ATRÁS ─────────────────────────────────────────────
/// El prior del solver es simétrico por construcción (`h·hᵀ` no distingue `+h`
/// de `−h`), así que en la versión anterior "caminar hacia atrás" quedaba tan
/// permitido como caminar hacia adelante. La gente casi nunca camina de
/// espaldas: el retroceso a lo largo del eje se deja pasar sólo al 35 %.
///
/// ── GIROS ──────────────────────────────────────────────────────────────────
/// La restricción se apaga mientras la persona gira rápido: durante un giro el
/// eje de referencia está rotando, "lateral" y "longitudinal" se intercambian,
/// y cualquier evidencia acumulada en el marco viejo es basura en el nuevo.
///
/// ── ESCALA CON EL MOVIMIENTO ───────────────────────────────────────────────
/// Toda la anisotropía se multiplica por el factor del acelerómetro: con el
/// usuario detenido la puerta es la identidad y mandan el ancla isotrópica del
/// solver, el One Euro y la zona muerta (que ya congelan bien la posición). No
/// tiene sentido hablar de "dirección de marcha" de alguien que no marcha.
class PuertaRumbo {
  /// Fracción del desplazamiento HACIA ATRÁS (contra el rumbo) que se deja
  /// pasar cuando la anisotropía está al máximo.
  static const double _facAtras = 0.35;

  /// Fracción del desplazamiento LATERAL que se deja pasar con la puerta
  /// cerrada y la anisotropía al máximo.
  static const double _gLateralCerrada = 0.10;

  /// Constante de tiempo del acumulador de evidencia lateral (s). Larga a
  /// propósito: es lo que promedia el ruido de signo alterno hasta cancelarlo.
  /// Con 2 s a ~5.5 Hz promedia ~11 muestras → divide el ruido por ~3.3.
  static const double _tauEvidenciaSeg = 2.0;

  /// Deriva lateral sostenida (m/s) necesaria para ABRIR la puerta. Una persona
  /// que se corre de verdad hacia el costado va a ~0.8–1.2 m/s; el ruido, ya
  /// promediado con signo, se queda bien por debajo de 0.5 m/s.
  static const double _umbralAbrirMs = 0.55;

  /// Umbral de CIERRE, más bajo que el de apertura (histéresis anti-titileo).
  static const double _umbralCerrarMs = 0.30;

  /// Ciclos consecutivos con el desplazamiento lateral en el MISMO sentido que
  /// la evidencia acumulada. A ~5.5 Hz, 5 ciclos ≈ 0.9 s.
  static const int _minCiclosConsistentes = 5;

  /// Desplazamiento lateral (m) por debajo del cual el ciclo no cuenta como
  /// evidencia: evita que el ruido chiquito sume "consistencia" gratis.
  static const double _pisoCicloMetros = 0.05;

  /// Constante de tiempo de la rampa de apertura/cierre (s).
  static const double _tauAperturaSeg = 0.45;

  /// Velocidad angular (°/s) por encima de la cual se considera que la persona
  /// está girando y se suspende toda la restricción.
  static const double _giroRapidoGradosSeg = 60.0;

  double _evidenciaLateral = 0.0;
  int _ciclosConsistentes = 0;
  double _apertura = 0.0;
  bool _abierta = false;

  /// Evidencia lateral acumulada, con signo, en m/s. Diagnóstico.
  double get evidenciaLateralMs => _evidenciaLateral;

  /// Apertura efectiva de la puerta lateral en `[0,1]`. Diagnóstico.
  double get apertura => _apertura;

  /// `true` si la puerta lateral está habilitada (deriva fuerte y persistente).
  bool get lateralHabilitado => _abierta;

  /// Aplica la restricción direccional al desplazamiento propuesto por el
  /// solver.
  ///
  /// - [posPrevia] y [candidata]: posiciones normalizadas `[0,1]`.
  /// - [rumboPlano]: versor del rumbo en el marco del plano (el mismo que
  ///   recibe [Posicionador.estimar]).
  /// - [factorMovimiento]: 0 = quieto (la puerta es la identidad),
  ///   1 = caminando (restricción plena).
  /// - [dt]: segundos reales desde el ciclo anterior.
  /// - [velocidadAngularGrados]: velocidad de giro del rumbo, en °/s.
  Offset aplicar({
    required Offset posPrevia,
    required Offset candidata,
    required Offset rumboPlano,
    required double metrosX,
    required double metrosY,
    required double factorMovimiento,
    required double dt,
    double velocidadAngularGrados = 0.0,
  }) {
    if (!dt.isFinite || dt <= 0) return candidata;
    final mx = (metrosX.isFinite && metrosX > 0) ? metrosX : 1.0;
    final my = (metrosY.isFinite && metrosY > 0) ? metrosY : 1.0;

    // Versor del rumbo en marco métrico (ver la nota en Posicionador.estimar:
    // una dirección normalizada NO es la misma dirección física si mx ≠ my).
    double hx = rumboPlano.dx * mx;
    double hy = rumboPlano.dy * my;
    final hn = sqrt(hx * hx + hy * hy);
    if (!hn.isFinite || hn < 1e-6) return candidata;
    hx /= hn;
    hy /= hn;
    final nx = -hy, ny = hx; // perpendicular al rumbo

    // Desplazamiento propuesto por el solver, en metros, descompuesto en el eje
    // de marcha (a) y el eje lateral (l).
    final dxM = (candidata.dx - posPrevia.dx) * mx;
    final dyM = (candidata.dy - posPrevia.dy) * my;
    final double a = dxM * hx + dyM * hy;
    final double l = dxM * nx + dyM * ny;

    final fMov = factorMovimiento.clamp(0.0, 1.0);

    if (velocidadAngularGrados.abs() > _giroRapidoGradosSeg) {
      // El eje de referencia está rotando: la evidencia acumulada pertenece a
      // un marco que ya no existe. Se descarta y se deja pasar todo.
      resetear();
      return candidata;
    }

    // ── Evidencia lateral CON SIGNO ─────────────────────────────────────────
    final alphaEv = dt / (_tauEvidenciaSeg + dt);
    _evidenciaLateral += alphaEv * (l / dt - _evidenciaLateral);

    if (l.abs() > _pisoCicloMetros && l * _evidenciaLateral > 0) {
      _ciclosConsistentes++;
    } else {
      _ciclosConsistentes = 0;
    }

    final umbral = _abierta ? _umbralCerrarMs : _umbralAbrirMs;
    final abiertaAhora = _evidenciaLateral.abs() > umbral &&
        _ciclosConsistentes >= _minCiclosConsistentes;
    if (abiertaAhora != _abierta) {
      _abierta = abiertaAhora;
      debugPrint('[Rumbo] Puerta lateral ${_abierta ? "ABIERTA" : "cerrada"} '
          '(evidencia ${_evidenciaLateral.toStringAsFixed(2)} m/s, '
          '$_ciclosConsistentes ciclos consistentes)');
    }
    final alphaAp = dt / (_tauAperturaSeg + dt);
    _apertura += alphaAp * ((_abierta ? 1.0 : 0.0) - _apertura);

    // ── Ganancias por eje ───────────────────────────────────────────────────
    // aniso = 0 → la puerta es la identidad (usuario detenido).
    // aniso = 1 → restricción direccional plena (usuario caminando).
    final aniso = fMov;
    const double gAdelante = 1.0;
    final double gAtras = 1.0 + (_facAtras - 1.0) * aniso;
    final double gLatBase = 1.0 + (_gLateralCerrada - 1.0) * aniso;
    final double gLateral = gLatBase + _apertura * (gAdelante - gLatBase);

    final aSalida = a * (a >= 0 ? gAdelante : gAtras);
    final lSalida = l * gLateral;

    return Offset(
      posPrevia.dx + (aSalida * hx + lSalida * nx) / mx,
      posPrevia.dy + (aSalida * hy + lSalida * ny) / my,
    );
  }

  void resetear() {
    _evidenciaLateral = 0.0;
    _ciclosConsistentes = 0;
    _apertura = 0.0;
    _abierta = false;
  }
}