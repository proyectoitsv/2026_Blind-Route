import 'dart:collection';
import 'dart:math';
import 'dart:ui';

/// Pasa-bajos exponencial de primer orden con α explícito.
class _PasaBajos {
  double? _s;

  double filtrar(double x, double alpha) {
    _s = (_s == null) ? x : alpha * x + (1 - alpha) * _s!;
    return _s!;
  }

  void fijar(double x) => _s = x;
  void resetear() => _s = null;
  double? get valor => _s;
}

/// Filtro **One Euro** (Casiez, Roussel & Vogel, CHI 2012) adaptado al
/// posicionamiento BLE.
///
/// ── Qué cambia respecto del One Euro clásico y POR QUÉ ─────────────────────
/// El One Euro original ajusta su frecuencia de corte con la derivada de la
/// **propia señal**: `fc = fcMin + beta·|dx̂|`. Eso funciona con mouse o touch,
/// donde el ruido es mucho menor que el movimiento. Con BLE pasa lo contrario:
///
///   ruido del centroide ≈ 1,5 m  ·  período de muestreo ≈ 0,18 s
///   → velocidad aparente que genera SOLO el ruido ≈ 11,7 m/s
///   → velocidad real de una persona caminando    ≈  1,2 m/s
///   → relación señal/ruido de la derivada ≈ 0,10
///
/// Es decir: el término `beta·|dx̂|` mide ruido, no movimiento. Bajar el
/// `dCutoff` no alcanza (ni a 0,1 Hz la velocidad residual por ruido baja de
/// 2,7 m/s). En la práctica el corte se dispara a 1–3 Hz y el filtro deja
/// pasar el ruido crudo: medido en simulación, el One Euro clásico sobre esta
/// señal da **peor** resultado que un EMA fijo.
///
/// Por eso acá el término adaptativo viene de **otro sensor**: el acelerómetro
/// del teléfono, que sí distingue limpiamente "quieto" de "caminando". El
/// factor de movimiento interpola la frecuencia de corte entre
/// [cutoffQuieto] (suavizado fuerte: la posición se ancla) y [cutoffMoviendo]
/// (respuesta rápida), y [beta] agrega un empujón extra proporcional a la
/// velocidad estimada sobre base larga.
///
/// Se conserva la estructura del One Euro: α depende del Δt real de cada
/// muestra, así que el filtro se comporta igual aunque los callbacks BLE
/// lleguen a ritmo irregular (que es exactamente lo que pasa).
class FiltroUnEuroPosicion {
  /// Frecuencia de corte (Hz) con el usuario detenido. Valor bajo = la
  /// posición queda prácticamente clavada. 0,04 Hz deja ~9 cm de jitter por
  /// ciclo con ruido BLE de 1,5 m (contra ~31 cm de un EMA α=0,15).
  double cutoffQuieto;

  /// Frecuencia de corte (Hz) con el usuario caminando. El óptimo medido para
  /// ruido de 1,5 m y marcha de 1,2 m/s está en 0,30–0,40 Hz: más abajo pesa
  /// la latencia, más arriba pesa el ruido que se cuela.
  double cutoffMoviendo;

  /// Hz adicionales por cada m/s de velocidad estimada. Chico a propósito: la
  /// velocidad se mide sobre base larga y todavía tiene ruido.
  double beta;

  /// Escala métrica del piso: se usa para que la velocidad esté en m/s reales
  /// y [beta] tenga significado físico independiente del tamaño del plano.
  double metrosX;
  double metrosY;

  /// Ventana (en segundos) sobre la que se estima la velocidad. Larga a
  /// propósito: la derivada muestra a muestra es puro ruido (ver arriba).
  static const double baseVelocidadSeg = 1.2;

  /// Tope de velocidad considerada (m/s). Una persona no camina más rápido
  /// que esto en interiores; recortar evita que un salto de señal dispare el
  /// corte.
  static const double velocidadMaxima = 2.5;

  final _PasaBajos _x = _PasaBajos();
  final _PasaBajos _y = _PasaBajos();

  /// Historial de salidas para la velocidad de base larga.
  final Queue<({DateTime t, Offset p})> _historial = Queue();

  double _velocidad = 0.0;
  double _cutoffActual = 0.0;

  FiltroUnEuroPosicion({
    this.cutoffQuieto = 0.04,
    this.cutoffMoviendo = 0.35,
    this.beta = 0.15,
    this.metrosX = 50.0,
    this.metrosY = 50.0,
  });

  /// Velocidad estimada del usuario en m/s (base larga, sobre la salida ya
  /// filtrada). Sirve también para mostrarla o para diagnosticar.
  double get velocidadMs => _velocidad;

  /// Frecuencia de corte efectiva del último ciclo (Hz). Útil para depurar.
  double get cutoffActual => _cutoffActual;

  Offset? get valor {
    final vx = _x.valor, vy = _y.valor;
    return (vx == null || vy == null) ? null : Offset(vx, vy);
  }

  /// Filtra la posición cruda [cruda].
  ///
  /// - [dt]: segundos transcurridos desde la muestra anterior (real, no
  ///   nominal: los callbacks BLE llegan a ritmo irregular).
  /// - [factorMovimiento]: 0 = totalmente quieto, 1 = caminando. Viene del
  ///   acelerómetro.
  Offset filtrar(
    Offset cruda, {
    required double dt,
    required double factorMovimiento,
  }) {
    final f = factorMovimiento.clamp(0.0, 1.0);

    if (_x.valor == null || dt <= 0 || !dt.isFinite) {
      _x.fijar(cruda.dx);
      _y.fijar(cruda.dy);
      _registrarHistorial(cruda);
      return cruda;
    }

    // fc = interpolación quieto↔moviendo + empujón por velocidad. El término
    // de velocidad solo pesa cuando el acelerómetro confirma movimiento: así
    // una ráfaga de ruido con el usuario parado no puede abrir el filtro.
    _cutoffActual = cutoffQuieto +
        (cutoffMoviendo - cutoffQuieto) * f +
        beta * _velocidad * f;

    final alpha = _alpha(_cutoffActual, dt);
    final salida = Offset(
      _x.filtrar(cruda.dx, alpha),
      _y.filtrar(cruda.dy, alpha),
    );

    _registrarHistorial(salida);
    _actualizarVelocidad();
    return salida;
  }

  /// α del pasa-bajos para una frecuencia de corte y un Δt dados.
  /// τ = 1/(2π·fc);  α = 1/(1 + τ/Δt)
  static double _alpha(double cutoff, double dt) {
    final fc = cutoff <= 0 ? 1e-4 : cutoff;
    final tau = 1.0 / (2 * pi * fc);
    return 1.0 / (1.0 + tau / dt);
  }

  void _registrarHistorial(Offset p) {
    final ahora = DateTime.now();
    _historial.addLast((t: ahora, p: p));
    while (_historial.length > 2 &&
        ahora.difference(_historial.first.t).inMilliseconds >
            (baseVelocidadSeg * 1000).round()) {
      _historial.removeFirst();
    }
  }

  /// Velocidad sobre base larga, en m/s reales. Se calcula sobre la salida ya
  /// filtrada (no sobre la señal cruda) para que el ruido no la domine.
  void _actualizarVelocidad() {
    if (_historial.length < 2) {
      _velocidad = 0;
      return;
    }
    final a = _historial.first, b = _historial.last;
    final seg = b.t.difference(a.t).inMilliseconds / 1000.0;
    if (seg <= 0.3) return; // base todavía muy corta: mantener el valor previo
    final dxM = (b.p.dx - a.p.dx) * metrosX;
    final dyM = (b.p.dy - a.p.dy) * metrosY;
    _velocidad = (sqrt(dxM * dxM + dyM * dyM) / seg).clamp(0.0, velocidadMaxima);
  }

  void resetear() {
    _x.resetear();
    _y.resetear();
    _historial.clear();
    _velocidad = 0;
    _cutoffActual = 0;
  }
}