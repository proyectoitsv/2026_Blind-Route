import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'database.dart'; 
import 'pantalla_config.dart';

class ListaPisos extends StatefulWidget {
  final int edificioId;
  final String nombreEdificio;

  const ListaPisos({super.key, required this.edificioId, required this.nombreEdificio});

  @override
  State<ListaPisos> createState() => _ListaPisosState();
}

class _ListaPisosState extends State<ListaPisos> {
  List<Map<String, dynamic>> _pisos = [];

  @override
  void initState() {
    super.initState();
    _refrescarPisos();
  }

  void _refrescarPisos() async {
    final datos = await DatabaseHelper.instance.obtenerPisosPorEdificio(widget.edificioId);
    setState(() => _pisos = datos);
  }

  // Función para confirmar y borrar un piso
  Future<bool> _confirmarBorrado(BuildContext context, String nombre) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar piso?'),
        content: Text('Esto borrará "$nombre" y todos sus beacons configurados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _agregarPiso() async {
    final controller = TextEditingController();
    final picker = ImagePicker();
    final imagen = await picker.pickImage(source: ImageSource.gallery);

    if (imagen == null) return;

    final directory = await getApplicationDocumentsDirectory();
    final nombreArchivo = p.basename(imagen.path);
    final rutaPermanente = p.join(directory.path, nombreArchivo);
    await File(imagen.path).copy(rutaPermanente);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Piso'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Nombre (ej: Planta Baja)'),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await DatabaseHelper.instance.crearPiso(
                  widget.edificioId, 
                  controller.text, 
                  rutaPermanente
                );
                _refrescarPisos();
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
      appBar: AppBar(title: Text(widget.nombreEdificio)),
      body: _pisos.isEmpty 
        ? const Center(child: Text("No hay pisos agregados"))
        : ListView.builder(
            itemCount: _pisos.length,
            itemBuilder: (context, i) {
              final piso = _pisos[i];
              return Dismissible(
                key: Key(piso['id'].toString()),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) => _confirmarBorrado(context, piso['nombre_piso']),
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) async {
                  await DatabaseHelper.instance.eliminarPiso(piso['id']);
                  _refrescarPisos();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("${piso['nombre_piso']} eliminado"))
                  );
                },
                child: ListTile(
                  leading: const Icon(Icons.layers),
                  title: Text(piso['nombre_piso']),
                  subtitle: const Text("Desliza para eliminar"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PantallaConfiguracion(
                          pisoId: piso['id'],
                          rutaImagen: piso['ruta_imagen'],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarPiso,
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }
}