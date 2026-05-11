import 'package:flutter/material.dart';
import 'database.dart';
import 'lista_pisos.dart'; // Crearemos esta pantalla a continuación

class ListaEdificios extends StatefulWidget {
  const ListaEdificios({super.key});

  @override
  State<ListaEdificios> createState() => _ListaEdificiosState();
}

class _ListaEdificiosState extends State<ListaEdificios> {
  List<Map<String, dynamic>> _edificios = [];

  @override
  void initState() {
    super.initState();
    _refrescarEdificios();
  }

  void _refrescarEdificios() async {
    final datos = await DatabaseHelper.instance.obtenerEdificios();
    setState(() => _edificios = datos);
  }

  void _agregarEdificio() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Edificio'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Nombre (ej: Facultad de Ingeniería)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await DatabaseHelper.instance.crearEdificio(controller.text);
                _refrescarEdificios();
                Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BlindRoute - Edificios'), backgroundColor: Colors.teal),
      body: ListView.builder(
        itemCount: _edificios.length,
        itemBuilder: (context, i) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ListTile(
            leading: const Icon(Icons.business, color: Colors.teal),
            title: Text(_edificios[i]['nombre']),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ListaPisos(
                    edificioId: _edificios[i]['id'],
                    nombreEdificio: _edificios[i]['nombre'],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarEdificio,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
      ),
    );
  }
}