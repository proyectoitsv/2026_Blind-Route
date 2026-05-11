import 'package:flutter/material.dart';
// Asegurate de importar tu pantalla principal
import 'pantalla_princ.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BlindRoute',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      // ESTA ES LA LÍNEA CLAVE:
      // Debe decir PantallaPrincipal() y NO ListaEdificios()
      home: const PantallaPrincipal(), 
    );
  }
}