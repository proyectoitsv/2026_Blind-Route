import 'package:flutter/material.dart';
import 'lista_edificios.dart';
import 'modo_automatico.dart';

class PantallaPrincipal extends StatelessWidget {
  const PantallaPrincipal({super.key});

  // --- FUNCIÓN DE SEGURIDAD ---
  void _solicitarClave(BuildContext context) {
    final TextEditingController _claveController = TextEditingController();
    const String CLAVE_CORRECTA = "1234"; // Podés cambiar tu clave acá

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acceso Administrativo'),
        content: TextField(
          controller: _claveController,
          obscureText: true, // Para que no se vea la clave al escribir
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Ingresá la clave de acceso',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_claveController.text == CLAVE_CORRECTA) {
                Navigator.pop(context); // Cierra el diálogo
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ListaEdificios()),
                );
              } else {
                // Feedback si la clave es incorrecta
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Clave incorrecta")),
                );
              }
            },
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blind Route'),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // BOTÓN PRINCIPAL (Gigante para el usuario)
            Expanded(
              flex: 4, // Toma la mayor parte del espacio
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ModoAutomatico()),
                  );
                },
                child: const Text(
                  'Comenzar a Navegar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 40, // Más grande para mejor accesibilidad
                    color: Colors.white, 
                    fontWeight: FontWeight.bold
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),

            // BOTÓN DE CONFIGURACIÓN (Mucho más discreto y protegido)
            Center(
              child: SizedBox(
                width: 200, // Tamaño reducido
                height: 50,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.teal[800],
                  ),
                  icon: const Icon(Icons.settings, size: 20),
                  label: const Text(
                    'Configurar Mapa',
                    style: TextStyle(fontSize: 16),
                  ),
                  onPressed: () => _solicitarClave(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}