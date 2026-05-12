import 'package:flutter/material.dart';
import 'database.dart';
import 'lista_pisos.dart';

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

  // Función de apoyo para confirmar antes de borrar
  Future<bool> _confirmarBorradoEdificio(BuildContext context, String nombre) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar edificio?'),
        content: Text('Se eliminará "$nombre", incluyendo todos sus pisos y beacons. Esta acción es permanente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR TODO'),
          ),
        ],
      ),
    ) ?? false;
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
                if (context.mounted) Navigator.pop(context);
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
      appBar: AppBar(
        title: const Text('BlindRoute - Edificios'), 
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _edificios.isEmpty
          ? const Center(child: Text("No hay edificios registrados"))
          : ListView.builder(
              itemCount: _edificios.length,
              itemBuilder: (context, i) {
                final edificio = _edificios[i];
                return Dismissible(
                  key: Key(edificio['id'].toString()),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) => _confirmarBorradoEdificio(context, edificio['nombre']),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_sweep, color: Colors.white, size: 28),
                  ),
                  onDismissed: (direction) async {
                    await DatabaseHelper.instance.eliminarEdificioCompleto(edificio['id']);
                    _refrescarEdificios();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Se eliminó ${edificio['nombre']} y todos sus datos"))
                    );
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: const Icon(Icons.business, color: Colors.teal),
                      title: Text(edificio['nombre']),
                      subtitle: const Text("Desliza para eliminar todo el edificio"),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ListaPisos(
                              edificioId: edificio['id'],
                              nombreEdificio: edificio['nombre'],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarEdificio,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}