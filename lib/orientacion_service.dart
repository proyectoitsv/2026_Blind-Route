import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart';

/// Servicio de orientacion basado en la brujula del dispositivo.
///
/// Usa flutter_compass para obtener el heading del celular y lo suaviza con
/// una media circular sobre una ventana deslizante. Esta pensado para usarse
/// con el celular en mano.
class OrientacionService {

  static const int _ventanaHeading = 8;
  final Queue<double> _historialHeading = Queue();

  // Deadband mínimo: solo filtra el ruido digital de ±0.1° del ADC.
  // No tiene sentido un deadband mayor cuando la ventana ya suaviza.
  static const double _umbralCambioBrujula = 0.5;
  double? _ultimoHeadingReportado;

  double? _headingActual;

  // ── Actualización de datos ──────────────────────────────────────────────────

  /// Actualiza el heading con la brujula.
  void actualizarHeadingBrujula(double heading) {
    final double headingNorm = heading % 360 < 0 ? heading % 360 + 360 : heading % 360;

    final bool esNuevoValor = _ultimoHeadingReportado == null ||
        _diferenciaAngular(headingNorm, _ultimoHeadingReportado!).abs() >
            _umbralCambioBrujula;

    if (esNuevoValor) {
      _ultimoHeadingReportado = headingNorm;

      // Suavizar con ventana circular antes de asignar.
      final suavizado = _actualizarVentanaHeading(headingNorm);
      if (suavizado != null) _headingActual = suavizado;
    }
  }

  // ── Helpers internos ────────────────────────────────────────────────────────

  /// Agrega [heading] a la ventana circular y devuelve la media circular si la
  /// ventana tiene al menos 2 muestras, o null si no.
  double? _actualizarVentanaHeading(double heading) {
    _historialHeading.addLast(heading);
    while (_historialHeading.length > _ventanaHeading) {
      _historialHeading.removeFirst();
    }
    if (_historialHeading.length < 2) return null;
    return mediaCircular(_historialHeading.toList());
  }

  static double _diferenciaAngular(double a, double b) {
    // En Dart, el operador % preserva el signo del dividendo, por lo que
    // (-10) % 360 == -10 y no 350. Usamos ((x) % 360 + 360) % 360 para
    // garantizar un resultado en [0, 360) antes de doblar al rango [-180, 180).
    double d = ((a - b) % 360 + 360) % 360;
    if (d > 180) d -= 360;
    return d;
  }

  /// Media circular de una lista de ángulos en grados.
  static double mediaCircular(List<double> angulos) {
    if (angulos.isEmpty) return 0;
    double sumSin = 0, sumCos = 0;
    for (final a in angulos) {
      final rad = a * pi / 180;
      sumSin += sin(rad);
      sumCos += cos(rad);
    }
    double media = atan2(sumSin / angulos.length, sumCos / angulos.length) * (180 / pi);
    if (media < 0) media += 360;
    return media;
  }

  // ── Getters ─────────────────────────────────────────────────────────────────

  double? get heading => _headingActual;

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
    // Nota: atan2 devuelve valores en [-180, 180], y el operador % de Dart
    // preserva el signo, por eso usamos la doble-módulo ((x % 360 + 360) % 360)
    // para garantizar [0, 360) antes de calcular _diferenciaAngular.
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
    _ultimoHeadingReportado = null;
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