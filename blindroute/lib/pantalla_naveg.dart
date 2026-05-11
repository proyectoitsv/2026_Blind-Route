import 'package:flutter/material.dart';


class PantallaNavegacion extends StatelessWidget {
  const PantallaNavegacion({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navegación'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          'Pantalla de navegación en blanco',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
