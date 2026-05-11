import 'package:flutter/material.dart';

class BeaconMarcado {
  Offset posicion;
  final String nombre;
  final String mac;
  List<double> _ventanaLecturas = [];
  static const int _tamanoFiltro = 25;

  BeaconMarcado({required this.posicion, required this.nombre, required this.mac});

  Map<String, dynamic> toJson() => {
    'dx': posicion.dx,
    'dy': posicion.dy,
    'nombre': nombre,
    'mac': mac,
  };

  factory BeaconMarcado.fromJson(Map<String, dynamic> json) {
    return BeaconMarcado(
      posicion: Offset(json['dx'], json['dy']),
      nombre: json['nombre'],
      mac: json['mac'],
    );
  }

  double get rssiFiltrado {
    if (_ventanaLecturas.isEmpty) return -100.0;
    return _ventanaLecturas.reduce((a, b) => a + b) / _ventanaLecturas.length;
  }

  void agregarLectura(double nuevaLectura) {
    _ventanaLecturas.add(nuevaLectura);
    if (_ventanaLecturas.length > _tamanoFiltro) _ventanaLecturas.removeAt(0);
  }
}