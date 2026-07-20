import 'package:flutter/material.dart';

class BeaconMarcado {
  Offset posicion;
  final String nombre;
  final String mac;
  
  // CAMBIO AQUÍ: Ahora es una variable normal que se puede actualizar
  double rssiFiltrado; 

  BeaconMarcado({
    required this.posicion, 
    required this.nombre, 
    required this.mac,
    this.rssiFiltrado = -100.0, // Valor inicial por defecto
  });

  Map<String, dynamic> toJson() => {
    'dx': posicion.dx,
    'dy': posicion.dy,
    'nombre': nombre,
    'mac': mac,
    'rssiFiltrado': rssiFiltrado, // Guardamos también el último RSSI
  };

  factory BeaconMarcado.fromJson(Map<String, dynamic> json) {
    return BeaconMarcado(
      posicion: Offset(json['dx'], json['dy']),
      nombre: json['nombre'],
      mac: json['mac'],
      rssiFiltrado: json['rssiFiltrado'] ?? -100.0,
    );
  }

  // Borramos el getter viejo y la lista interna porque ahora
  // el ProcesadorSenal maneja el historial de forma general.
  
  void agregarLectura(double nuevaLectura) {
    // Si todavía usás esta función en algún lado, 
    // simplemente actualizamos la variable directa.
    rssiFiltrado = nuevaLectura;
  }
}