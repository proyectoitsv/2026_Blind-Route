import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart';

/// Servicio de orientacion basado en la brujula del dispositivo.
///
/// Usa flutter_compass para obtener el heading del celular y lo suaviza con
/// una media circular sobre una ventana deslizante. Esta pensado para usarse
/// con el celular en mano.
///
/// Ademas del heading suavizado expone dos medidas que el pipeline de
/// posicionamiento necesita para decidir si puede CONFIAR en ese heading:
///   • [calidadRumbo]        — que tan coherentes son las muestras de la ventana.
///   • [velocidadAngularGrados] — que tan rapido esta girando el usuario.
/// Ver el comentario de cada getter.
class OrientacionService {

  static const int _ventanaHeading = 8;
  final Queue<double> _historialHeading = Queue();

  double? _headingActual;

  /// Longitud del vector resultante de la media circular, en `[0,1]`.
  /// 1 = todas las muestras apuntan igual; 0 = dispersion total.
  double _resultante = 0.0;

  /// Velocidad angular suavizada del heading, en grados/segundo (con signo).
  double _velocidadAngular = 0.0;
  DateTime? _tUltimaMuestra;

  /// Constante de tiempo del suavizado de la velocidad angular (s).
  static const double _tauVelAngularSeg = 0.25;

  // ── Actualización de datos ──────────────────────────────────────────────────

  /// Actualiza el heading con la brujula.
  ///
  /// NOTA (cambio respecto de la version anterior): antes habia un deadband de
  /// 0.5 grados que descartaba la muestra ENTERA — no entraba a la ventana ni
  /// actualizaba nada. Con el usuario quieto y apuntando estable eso dejaba la
  /// ventana congelada con muestras viejas, y cualquier medida derivada de ella
  /// (calidad, velocidad angular) quedaba mirando el pasado. Ahora la ventana se
  /// alimenta SIEMPRE; el antitiliteo de la UI ya lo resuelve el chequeo de 1
  /// grado del timer de refresco en la pantalla de navegacion.
  void actualizarHeadingBrujula(double heading) {
    final double headingNorm = ((heading % 360) + 360) % 360;

    final ahora = DateTime.now();
    final anterior = _headingActual;

    final suavizado = _actualizarVentanaHeading(headingNorm);
    if (suavizado == null) return;

    // Velocidad angular sobre el heading YA suavizado: sobre el crudo seria
    // puro ruido del magnetometro.
    if (anterior != null && _tUltimaMuestra != null) {
      final dt = ahora.difference(_tUltimaMuestra!).inMicroseconds / 1e6;
      if (dt > 1e-3 && dt < 1.0) {
        final tasa = _diferenciaAngular(suavizado, anterior) / dt;
        final a = dt / (_tauVelAngularSeg + dt);
        _velocidadAngular += a * (tasa - _velocidadAngular);
      }
    }
    _tUltimaMuestra = ahora;
    _headingActual = suavizado;
  }

  // ── Helpers internos ────────────────────────────────────────────────────────

  /// Agrega [heading] a la ventana circular, actualiza [_resultante] y devuelve
  /// la media circular si la ventana tiene al menos 2 muestras, o null si no.
  double? _actualizarVentanaHeading(double heading) {
    _historialHeading.addLast(heading);
    while (_historialHeading.length > _ventanaHeading) {
      _historialHeading.removeFirst();
    }
    if (_historialHeading.length < 2) return null;
    final r = _mediaYResultante(_historialHeading);
    _resultante = r.$2;
    return r.$1;
  }

  static double _diferenciaAngular(double a, double b) {
    // En Dart, el operador % preserva el signo del dividendo, por lo que
    // (-10) % 360 == -10 y no 350. Usamos ((x) % 360 + 360) % 360 para
    // garantizar un resultado en [0, 360) antes de doblar al rango [-180, 180).
    double d = ((a - b) % 360 + 360) % 360;
    if (d > 180) d -= 360;
    return d;
  }

  /// Media circular y longitud resultante de una lista de angulos en grados.
  static (double, double) _mediaYResultante(Iterable<double> angulos) {
    double sumSin = 0, sumCos = 0;
    int n = 0;
    for (final a in angulos) {
      final rad = a * pi / 180;
      sumSin += sin(rad);
      sumCos += cos(rad);
      n++;
    }
    if (n == 0) return (0.0, 0.0);
    sumSin /= n;
    sumCos /= n;
    double media = atan2(sumSin, sumCos) * (180 / pi);
    if (media < 0) media += 360;
    return (media, sqrt(sumSin * sumSin + sumCos * sumCos));
  }

  /// Media circular de una lista de angulos en grados.
  static double mediaCircular(List<double> angulos) {
    if (angulos.isEmpty) return 0;
    return _mediaYResultante(angulos).$1;
  }

  // ── Getters ─────────────────────────────────────────────────────────────────

  double? get heading => _headingActual;

  /// Longitud resultante R de la media circular, en `[0,1]`. Diagnostico:
  /// permite ver en el log POR QUE calidadRumbo da lo que da.
  double get resultante => _resultante;

  /// Velocidad angular del rumbo en grados/segundo (positiva = horario).
  /// La usa la puerta direccional para suspender la restriccion mientras el
  /// usuario gira: durante un giro el eje "adelante/lateral" esta rotando y
  /// cualquier restriccion referida al eje viejo es incorrecta.
  double get velocidadAngularGrados => _velocidadAngular;

  /// Confiabilidad del rumbo en `[0,1]`, derivada de la dispersion angular de
  /// la ventana.
  ///
  /// POR QUE HACE FALTA: en interiores el campo magnetico esta severamente
  /// distorsionado por estructura metalica, ascensores, tableros electricos y
  /// maquinaria. Un heading basura no "restringe" el movimiento: clava la
  /// posicion sobre un eje EQUIVOCADO, que es bastante peor que no restringir
  /// nada. Antes de dejar que el rumbo mande sobre el posicionamiento hay que
  /// poder decir cuanto se le cree.
  ///
  /// Se usa la longitud resultante R de la media circular (R ≈ exp(−σ²/2)).
  /// La ventana tiene que estar llena para que el numero signifique algo.
  ///
  /// RECALIBRADO: los umbrales anteriores (rMalo=0.97, rBueno=0.999) estaban
  /// pensados para un telefono apoyado (±2–3° de ruido). Con el telefono EN LA
  /// MANO y caminando, el heading oscila ±10–20° por el braceo y los pasos:
  ///   ±10° → R=0.985 (calidad vieja 0.51)   ±15° → R=0.966 (calidad vieja 0!)
  /// Con calidad 0 el rumbo quedaba por debajo de _calidadRumboMinima y TODA
  /// la restriccion direccional se apagaba justo mientras el usuario caminaba
  /// — que es cuando mas se la necesita. Los umbrales nuevos toleran el ruido
  /// de mano (±10° → 1.0, ±15° → 0.78, ±20° → 0.48) y siguen rechazando la
  /// dispersion realmente mala (±25° o mas → ~0).
  ///
  /// Nota: durante un giro genuino R tambien baja, y eso esta bien — es
  /// exactamente cuando conviene no restringir.
  double get calidadRumbo {
    if (_historialHeading.length < _ventanaHeading) return 0.0;
    const double rMalo = 0.90;   // antes 0.97
    const double rBueno = 0.985; // antes 0.999
    return ((_resultante - rMalo) / (rBueno - rMalo)).clamp(0.0, 1.0);
  }

  // ── Helpers estáticos ───────────────────────────────────────────────────────

  static String direccionCardinal(double heading) {
    double h = heading % 360;
    if (h < 0) h += 360;
    if (h >= 337.5 || h < 22.5)  return 'Norte';
    if (h < 67.5)                 return 'Noreste';
    if (h < 112.5)                return 'Este';
    if (h < 157.5)                return 'Sureste';
    if (h < 202.5)                return 'Sur';
    if (h < 247.5)                return 'Suroeste';
    if (h < 292.5)                return 'Oeste';
    return 'Noroeste';
  }

  static IconData iconoDireccion(double heading) {
    double h = heading % 360;
    if (h < 0) h += 360;
    if (h >= 337.5 || h < 22.5)  return Icons.arrow_upward;
    if (h < 67.5)                 return Icons.north_east;
    if (h < 112.5)                return Icons.arrow_forward;
    if (h < 157.5)                return Icons.south_east;
    if (h < 202.5)                return Icons.arrow_downward;
    if (h < 247.5)                return Icons.south_west;
    if (h < 292.5)                return Icons.arrow_back;
    return Icons.north_west;
  }

  static IndicacionNavegacion calcularIndicacion({
    required double headingUsuario,
    required Offset posicionUsuario,
    required Offset posicionDestino,
    double rotacionMapa = 0,
    double metrosX = 50,
    double metrosY = 50,
  }) {
    // Convertir el desplazamiento normalizado a metros reales en cada eje
    // (la escala puede ser distinta en X e Y), para que la distancia y el
    // rumbo sean correctos aunque la grilla sea rectangular.
    final dxM = (posicionDestino.dx - posicionUsuario.dx) * metrosX;
    final dyM = (posicionDestino.dy - posicionUsuario.dy) * metrosY;
    final distanciaMetros = sqrt(dxM * dxM + dyM * dyM);

    // anguloDestino se calcula en coordenadas del mapa (en metros), donde
    // "arriba" apunta a rotacionMapa grados del mundo real (0 = Norte, etc.).
    // Sumando rotacionMapa convertimos el ángulo del mapa a ángulo real-mundo,
    // para que sea comparable con headingUsuario (que viene de la brújula).
    double anguloDestino = atan2(dxM, -dyM) * (180 / pi);
    anguloDestino = ((anguloDestino + rotacionMapa) % 360 + 360) % 360;

    double giro = _diferenciaAngular(anguloDestino, headingUsuario);

    final String instruccion;
    if (giro.abs() < 30) {
      instruccion = 'Seguí derecho';
    } else if (giro.abs() < 150) {
      instruccion = giro > 0 ? 'Girá a la derecha' : 'Girá a la izquierda';
    } else {
      instruccion = 'Date la vuelta';
    }

    return IndicacionNavegacion(
      headingUsuario: headingUsuario,
      anguloDestino: anguloDestino,
      giroNecesario: giro,
      distancia: distanciaMetros,
      instruccion: instruccion,
      direccionDestino: direccionCardinal(anguloDestino),
    );
  }

  /// Devuelve el próximo punto objetivo siguiendo el camino de la grilla: la
  /// próxima "esquina" (donde el camino cambia de dirección) o el destino final.
  ///
  /// Las instrucciones de voz/giro deben apuntar a este punto en lugar de
  /// directamente al destino, para que el usuario avance a lo largo del camino
  /// pintado (que sigue las cuadrículas) y no en línea recta cruzando paredes.
  static Offset proximoObjetivo(List<Offset> ruta, Offset posicionUsuario) {
    if (ruta.isEmpty) return posicionUsuario;
    if (ruta.length == 1) return ruta.first;

    // Celda del camino más cercana a la posición actual.
    int idx = 0;
    double mejor = double.infinity;
    for (int i = 0; i < ruta.length; i++) {
      final d = (ruta[i] - posicionUsuario).distanceSquared;
      if (d < mejor) {
        mejor = d;
        idx = i;
      }
    }
    if (idx >= ruta.length - 1) return ruta.last;

    Offset signo(Offset v) => Offset(v.dx.sign, v.dy.sign);
    final dirInicial = signo(ruta[idx + 1] - ruta[idx]);

    // Avanzar mientras la dirección no cambie: el punto donde cambia es la
    // próxima esquina del camino.
    int j = idx;
    while (j < ruta.length - 1 && signo(ruta[j + 1] - ruta[j]) == dirInicial) {
      j++;
    }
    return ruta[j];
  }

  void limpiar() {
    _historialHeading.clear();
    _headingActual = null;
    _resultante = 0.0;
    _velocidadAngular = 0.0;
    _tUltimaMuestra = null;
  }
}

/// Clase de datos con la informacion de navegacion calculada.
class IndicacionNavegacion {
  final double headingUsuario;
  final double anguloDestino;
  final double giroNecesario;

  /// Distancia al objetivo, ya convertida a **metros reales** (la escala puede
  /// ser distinta en X e Y).
  final double distancia;
  final String instruccion;
  final String direccionDestino;

  const IndicacionNavegacion({
    required this.headingUsuario,
    required this.anguloDestino,
    required this.giroNecesario,
    required this.distancia,
    required this.instruccion,
    required this.direccionDestino,
  });

  /// Distancia en metros reales al objetivo.
  double get distanciaMetros => distancia;
}