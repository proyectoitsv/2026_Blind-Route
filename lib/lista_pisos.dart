import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'database.dart';
import 'pantalla_config.dart';
import 'supabase_service.dart';
import 'tema.dart';

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
    if (mounted) setState(() => _pisos = datos);
  }

  Future<bool> _confirmarBorrado(BuildContext context, String nombre) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaApp.fondoCard,
        title: const Text('¿Eliminar piso?', style: TextStyle(color: TemaApp.textoBlanco)),
        content: Text(
          'Esto borrará "$nombre" y todos sus beacons configurados.',
          style: const TextStyle(color: TemaApp.textoSecundario),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: TemaApp.zonaRestringidaBorde),
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
        backgroundColor: TemaApp.fondoCard,
        title: const Text('Nuevo Piso', style: TextStyle(color: TemaApp.textoBlanco)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: TemaApp.textoBlanco),
          decoration: const InputDecoration(hintText: 'Nombre (ej: Planta Baja)'),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await DatabaseHelper.instance.crearPiso(
                  widget.edificioId,
                  controller.text,
                  rutaPermanente,
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
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(title: Text(widget.nombreEdificio)),
        body: _pisos.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.layers_outlined, size: 64, color: TemaApp.textoSecundario),
                    SizedBox(height: 16),
                    Text('No hay pisos agregados', style: TextStyle(color: TemaApp.textoSecundario, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('Tocá + para agregar una imagen de plano', style: TextStyle(color: TemaApp.textoSecundario, fontSize: 13)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _pisos.length,
                itemBuilder: (context, i) {
                  final piso = _pisos[i];
                  return Dismissible(
                    key: Key(piso['id'].toString()),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      final confirmado =
                          await _confirmarBorrado(context, piso['nombre_piso']);
                      if (confirmado != true) return false;

                      // Si el piso está publicado, primero se quita de la nube.
                      // Si eso falla (offline o no sos el dueño), NO se borra
                      // localmente, para no dejar el mapa huérfano en la nube.
                      final remoteId = piso['remote_id'] as String?;
                      if (remoteId != null &&
                          SupabaseService.instance.configurado) {
                        try {
                          await SupabaseService.instance.eliminarMapa(remoteId);
                        } catch (e) {
                          if (!mounted) return false;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'No se pudo quitar de la nube: $e\nNo se eliminó el piso.'),
                            ),
                          );
                          return false;
                        }
                      }

                      await DatabaseHelper.instance.eliminarPiso(piso['id']);
                      if (!mounted) return true;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                            content: Text("${piso['nombre_piso']} eliminado")),
                      );
                      return true;
                    },
                    background: Container(
                      color: TemaApp.zonaRestringidaRelleno,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (direction) => _refrescarPisos(),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: TemaApp.fondoCard,
                        borderRadius: BorderRadius.circular(TemaApp.radiusCard),
                        border: Border.all(color: const Color(0xFF21262D)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: TemaApp.acentoSuave,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.layers_rounded, color: TemaApp.acento, size: 22),
                        ),
                        title: Text(piso['nombre_piso'], style: const TextStyle(color: TemaApp.textoBlanco, fontWeight: FontWeight.w600, fontSize: 16)),
                        subtitle: const Text('Deslizá para eliminar', style: TextStyle(color: TemaApp.textoSecundario, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: TemaApp.textoSecundario),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PantallaConfiguracion(
                                pisoId: piso['id'],
                                rutaImagen: piso['ruta_imagen'],
                                escalaX: (piso['escala_metros'] as num?)?.toDouble() ?? 50,
                                escalaY: (piso['escala_metros_alto'] as num?)?.toDouble() ?? 50,
                                tamCeldaMetros: (piso['tam_celda_metros'] as num?)?.toDouble() ?? 1.0,
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
          onPressed: _agregarPiso,
          backgroundColor: TemaApp.acento,
          foregroundColor: TemaApp.fondo,
          child: const Icon(Icons.add_photo_alternate_rounded),
        ),
      ),
    );
  }
}