import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'database.dart'; // Tu clase de base de datos
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

  void _agregarPiso() async {
    final controller = TextEditingController();
    final picker = ImagePicker();
    final imagen = await picker.pickImage(source: ImageSource.gallery);

    if (imagen == null) return;

    // COPIA DE SEGURIDAD: Guardamos la imagen en la carpeta interna de la app
    final directory = await getApplicationDocumentsDirectory();
    final nombreArchivo = p.basename(imagen.path);
    final rutaPermanente = p.join(directory.path, nombreArchivo);
    await File(imagen.path).copy(rutaPermanente);

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
      appBar: AppBar(title: Text(widget.nombreEdificio)),
      body: ListView.builder(
        itemCount: _pisos.length,
        itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.layers),
          title: Text(_pisos[i]['nombre_piso']),
          onTap: () {
            // Aquí pasamos al mapa de navegación que ya tenías
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PantallaConfiguracion(
                  pisoId: _pisos[i]['id'],
                  rutaImagen: _pisos[i]['ruta_imagen'],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarPiso,
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }
}