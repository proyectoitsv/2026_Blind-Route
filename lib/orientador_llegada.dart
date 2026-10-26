import 'orientacion_service.dart';

/// Cómo sigue la orientación al llegar (ver [OrientadorLlegada]).
enum EstadoOrientacion {
  /// Todavía no quedó de frente al lugar.
  girando,

  /// Quedó de frente al lugar.
  deFrente,

  /// Pasó [OrientadorLlegada.maximo] sin quedar de frente.
  vencida,
}

/// Resultado de un ciclo de [OrientadorLlegada.actualizar].
class PasoOrientacion {
  final EstadoOrientacion estado;

  /// Indicación que toca decir en este ciclo ("Girá a la izquierda"), o
  /// null. Si se dijo, hay que avisarlo con
  /// [OrientadorLlegada.registrarIndicacion]; si el motor de voz estaba
  /// ocupado, se vuelve a pedir en el ciclo siguiente.
  final String? indicacion;

  /// Cuánto falta girar, en grados (positivo = a la derecha). Null sin
  /// brújula.
  final double? giro;

  const PasoOrientacion(this.estado, {this.indicacion, this.giro});
}

/// ═══════════════════════════════════════════════════════════════════════════
/// ORIENTACIÓN AL LLEGAR
/// ═══════════════════════════════════════════════════════════════════════════
///
/// El problema: la llegada se anuncia a 1,5 m del lugar (el radio de llegada
/// de la pantalla de navegación), y muchas veces el lugar queda al costado: la ruta dobla justo
/// antes, o termina en el pasillo y la puerta está a un lado. "Llegaste a
/// Baño" no dice para dónde está la entrada, y quien no ve se queda sin
/// saber hacia dónde ir.
///
/// Antes de anunciar la llegada se lo hace girar con la brújula hasta quedar
/// de frente al lugar (a la boca, en una escalera o un ascensor):
///
///  1. Al llegar: si ya viene mirando hacia el lugar, se termina enseguida.
///     Si no, se dice hacia dónde girar.
///  2. Mientras gira no se dice nada: otra orden a mitad del giro confunde.
///     Si queda quieto sin estar de frente, se corrige ("Girá un poco a la
///     derecha"), y si no se mueve se repite cada [repetirIgual].
///  3. De frente y quieto durante [sostenerDeFrente] → listo.
///  4. Si pasa [maximo] sin lograrlo (brújula mala, o la persona no gira), se
///     da por terminada: la llegada se anuncia igual, con el lado donde quedó
///     el lugar.
///
/// El rumbo objetivo se fija al llegar y no se recalcula: girando en el lugar
/// el cuerpo tapa beacons, la posición se mueve y el objetivo bailaría.
///
/// No sabe nada de voz ni de pantallas: la pantalla de navegación lo
/// alimenta ciclo a ciclo y dice lo que devuelve.
class OrientadorLlegada {
  OrientadorLlegada({required this.rumboObjetivo, required this.inicio});

  /// Rumbo real (grados, 0 = Norte, sentido horario) hacia el que tiene que
  /// quedar mirando.
  final double rumboObjetivo;

  /// Cuándo arrancó la orientación (para [maximo]).
  final DateTime inicio;

  /// Hasta este desvío (grados) cuenta como "de frente". El mismo corte que
  /// "Seguí derecho" en [OrientacionService.calcularIndicacion]: adentro de
  /// un edificio la brújula tiene errores de ese orden.
  static const double toleranciaGrados = 30;

  /// Con menos que esto por girar se dice "un poco".
  static const double giroChicoGrados = 60;

  /// Desde acá se dice "Date la vuelta".
  static const double vueltaGrados = 150;

  /// Por encima de esta velocidad angular (°/s) está girando. El heading
  /// llega suavizado y atrasado: girando, pasa por el rumbo objetivo antes de
  /// que la persona frene, y no hay que darlo por bueno ahí.
  static const double girandoGradosPorSeg = 30;

  static const Duration sostenerDeFrente = Duration(milliseconds: 600);

  /// Quieto sin estar de frente este tiempo → se corrige.
  static const Duration quietoParaCorregir = Duration(milliseconds: 800);

  /// Separación mínima entre dos indicaciones distintas, para no pisar la
  /// anterior.
  static const Duration entreIndicaciones = Duration(milliseconds: 2500);

  /// Cada cuánto se repite la misma indicación si no se mueve.
  static const Duration repetirIgual = Duration(seconds: 5);

  static const Duration maximo = Duration(seconds: 15);

  bool _primerPaso = true;
  DateTime? _deFrenteDesde;
  DateTime? _quietoDesde;
  DateTime? _ultimaVez;
  String? _ultimaIndicacion;

  /// Un ciclo: [heading] y [velocidadAngular] (°/s) de la brújula.
  PasoOrientacion actualizar({
    required double? heading,
    required double velocidadAngular,
    required DateTime ahora,
  }) {
    final vencida = ahora.difference(inicio) >= maximo;
    if (heading == null) {
      return PasoOrientacion(
          vencida ? EstadoOrientacion.vencida : EstadoOrientacion.girando);
    }
    final giro = OrientacionService.diferenciaAngular(rumboObjetivo, heading);
    final deFrente = giro.abs() <= toleranciaGrados;

    // Al llegar: si ya viene mirando hacia el lugar no hay nada que girar.
    if (_primerPaso) {
      _primerPaso = false;
      return deFrente
          ? PasoOrientacion(EstadoOrientacion.deFrente, giro: giro)
          : PasoOrientacion(EstadoOrientacion.girando,
              indicacion: textoGiro(giro), giro: giro);
    }

    final girando = velocidadAngular.abs() > girandoGradosPorSeg;
    if (deFrente && !girando) {
      final desde = _deFrenteDesde ??= ahora;
      if (ahora.difference(desde) >= sostenerDeFrente) {
        return PasoOrientacion(EstadoOrientacion.deFrente, giro: giro);
      }
    } else {
      _deFrenteDesde = null;
    }
    if (vencida) return PasoOrientacion(EstadoOrientacion.vencida, giro: giro);

    final sigue = PasoOrientacion(EstadoOrientacion.girando, giro: giro);
    if (girando) {
      _quietoDesde = null;
      return sigue;
    }
    final quieto = _quietoDesde ??= ahora;
    if (deFrente || ahora.difference(quieto) < quietoParaCorregir) return sigue;

    final texto = textoGiro(giro);
    final ultima = _ultimaVez;
    final toca = ultima == null ||
        ahora.difference(ultima) >=
            (texto == _ultimaIndicacion ? repetirIgual : entreIndicaciones);
    return toca
        ? PasoOrientacion(EstadoOrientacion.girando,
            indicacion: texto, giro: giro)
        : sigue;
  }

  /// Avisa que [texto] se dijo en [ahora].
  void registrarIndicacion(String texto, DateTime ahora) {
    _ultimaIndicacion = texto;
    _ultimaVez = ahora;
  }

  /// Qué decir para girar [giro] grados (positivo = a la derecha).
  static String textoGiro(double giro) {
    final a = giro.abs();
    if (a >= vueltaGrados) return 'Date la vuelta';
    final lado = giro > 0 ? 'derecha' : 'izquierda';
    return a < giroChicoGrados ? 'Girá un poco a la $lado' : 'Girá a la $lado';
  }

  /// Dónde queda el lugar visto por el usuario, para el anuncio de llegada
  /// ("Está adelante", "Está a tu izquierda").
  static String lado(double giro) {
    final a = giro.abs();
    if (a <= toleranciaGrados) return 'adelante';
    if (a >= vueltaGrados) return 'atrás';
    return giro > 0 ? 'a tu derecha' : 'a tu izquierda';
  }
}
