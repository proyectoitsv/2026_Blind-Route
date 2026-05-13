import 'dart:math';
import 'package:flutter/material.dart';

/// Servicio de orientacion hibrido que funciona tanto con el celular en mano
/// (usando brujula) como en el bolsillo (usando direccion del movimiento).
///
/// MODO MANO: usa flutter_compass para obtener heading directo del dispositivo.
/// MODO BOLSILLO: calcula la direccion del movimiento comparando posiciones
/// consecutivas del usuario (asume que camina hacia adelante).
class OrientacionService {
  // Historial de posiciones para calcular direccion de movimiento
  final List<_PosicionHistorial> _historial = [];
  static const int _ventanaMovimiento = 10; // lecturas para promediar
  static const double _umbralDistanciaMinima = 0.008; // ~40cm en plano normalizado

  /// Heading actual del usuario (0=Norte, 90=Este, etc.)
  /// Puede venir de la brujula o calcularse del movimiento.
  double? _headingActual;

  /// Si es true, estamos usando direccion de movimiento (bolsillo).
  /// Si es false, estamos usando brujula (mano).
  bool _usandoMovimiento = false;

  /// Actualiza el heading con la brujula (modo mano).
  void actualizarHeadingBrujula(double heading) {
    _headingActual = heading;
    _usandoMovimiento = false;
  }

  /// Actualiza la posicion y calcula heading por movimiento (modo bolsillo).
  void actualizarPosicion(Offset posicion) {
    final ahora = DateTime.now();

    // Agregar al historial
    _historial.add(_PosicionHistorial(posicion, ahora));

    // Mantener solo las ultimas N posiciones
    while (_historial.length > _ventanaMovimiento) {
      _historial.removeAt(0);
    }

    // Necesitamos al menos 2 puntos para calcular direccion
    if (_historial.length < 2) return;

    // Calcular vector de movimiento promedio
    double sumaDx = 0;
    double sumaDy = 0;
    int count = 0;

    for (int i = 1; i < _historial.length; i++) {
      final anterior = _historial[i - 1];
      final actual = _historial[i];

      final dx = actual.posicion.dx - anterior.posicion.dx;
      final dy = actual.posicion.dy - anterior.posicion.dy;
      final distancia = sqrt(dx * dx + dy * dy);

      // Solo considerar movimientos significativos
      if (distancia > 0.001) {
        sumaDx += dx;
        sumaDy += dy;
        count++;
      }
    }

    if (count == 0) return;

    final dxPromedio = sumaDx / count;
    final dyPromedio = sumaDy / count;
    final distanciaTotal = sqrt(dxPromedio * dxPromedio + dyPromedio * dyPromedio);

    // Si no se movio lo suficiente, no actualizar heading
    if (distanciaTotal < _umbralDistanciaMinima) return;

    // Calcular angulo del movimiento (0=Norte, 90=Este)
    // Nota: en canvas Y crece hacia abajo, por eso -dy
    double angulo = atan2(dxPromedio, -dyPromedio) * (180 / pi);
    if (angulo < 0) angulo += 360;

    _headingActual = angulo;
    _usandoMovimiento = true;
  }

  /// Heading actual del usuario, o null si no hay datos suficientes.
  double? get heading => _headingActual;

  /// Indica si el heading viene de la direccion de movimiento (bolsillo)
  /// o de la brujula (mano).
  bool get usandoMovimiento => _usandoMovimiento;

  /// Texto descriptivo del modo actual.
  String get modoTexto => _usandoMovimiento
      ? 'Modo bolsillo (por movimiento)'
      : 'Modo mano (brujula)';

  /// Convierte un heading en grados a un nombre de direccion cardinal.
  static String direccionCardinal(double heading) {
    double h = heading % 360;
    if (h < 0) h += 360;

    if (h >= 337.5 || h < 22.5) return 'Norte';
    if (h >= 22.5 && h < 67.5) return 'Noreste';
    if (h >= 67.5 && h < 112.5) return 'Este';
    if (h >= 112.5 && h < 157.5) return 'Sureste';
    if (h >= 157.5 && h < 202.5) return 'Sur';
    if (h >= 202.5 && h < 247.5) return 'Suroeste';
    if (h >= 247.5 && h < 292.5) return 'Oeste';
    return 'Noroeste';
  }

  /// Convierte un heading a un icono de flecha aproximada.
  static IconData iconoDireccion(double heading) {
    double h = heading % 360;
    if (h < 0) h += 360;

    if (h >= 337.5 || h < 22.5) return Icons.arrow_upward;
    if (h >= 22.5 && h < 67.5) return Icons.north_east;
    if (h >= 67.5 && h < 112.5) return Icons.arrow_forward;
    if (h >= 112.5 && h < 157.5) return Icons.south_east;
    if (h >= 157.5 || h < 202.5) return Icons.arrow_downward;
    if (h >= 202.5 || h < 247.5) return Icons.south_west;
    if (h >= 247.5 || h < 292.5) return Icons.arrow_back;
    return Icons.north_west;
  }

  /// Calcula el angulo relativo entre la direccion actual del usuario
  /// y un punto destino en el mapa.
  static IndicacionNavegacion calcularIndicacion({
    required double headingUsuario,
    required Offset posicionUsuario,
    required Offset posicionDestino,
  }) {
    final dx = posicionDestino.dx - posicionUsuario.dx;
    final dy = posicionDestino.dy - posicionUsuario.dy;
    final distancia = sqrt(dx * dx + dy * dy);

    double anguloDestino = atan2(dx, -dy) * (180 / pi);
    if (anguloDestino < 0) anguloDestino += 360;

    double giro = anguloDestino - headingUsuario;
    while (giro > 180) giro -= 360;
    while (giro < -180) giro += 360;

    String instruccion;
    if (giro.abs() < 15) {
      instruccion = 'Segui derecho';
    } else if (giro.abs() < 45) {
      instruccion = giro > 0 ? 'Gira leve a la derecha' : 'Gira leve a la izquierda';
    } else if (giro.abs() < 90) {
      instruccion = giro > 0 ? 'Gira a la derecha' : 'Gira a la izquierda';
    } else if (giro.abs() < 135) {
      instruccion = giro > 0 ? 'Gira fuerte a la derecha' : 'Gira fuerte a la izquierda';
    } else {
      instruccion = 'Dale la vuelta';
    }

    return IndicacionNavegacion(
      headingUsuario: headingUsuario,
      anguloDestino: anguloDestino,
      giroNecesario: giro,
      distancia: distancia,
      instruccion: instruccion,
      direccionDestino: direccionCardinal(anguloDestino),
    );
  }

  void limpiar() {
    _historial.clear();
    _headingActual = null;
    _usandoMovimiento = false;
  }
}

class _PosicionHistorial {
  final Offset posicion;
  final DateTime timestamp;
  _PosicionHistorial(this.posicion, this.timestamp);
}

/// Clase de datos con la informacion de navegacion calculada.
class IndicacionNavegacion {
  final double headingUsuario;
  final double anguloDestino;
  final double giroNecesario;
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

  double get distanciaMetros => distancia * 50;
}