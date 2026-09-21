import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'database.dart';
import 'pantalla_config.dart';
import 'piso_util.dart';
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

  /// Selector de número de piso. Sólo se puede elegir un número (no se
  /// escribe un nombre libre) y no se ofrecen los ya usados en el edificio.
  /// [actual] es el número del piso que se está editando (se permite
  /// re-elegirlo). Devuelve null si se cancela.
  Future<int?> _elegirNumeroPiso({int? actual}) async {
    final ocupados = await DatabaseHelper.instance
        .obtenerNumerosPisoOcupados(widget.edificioId);
    if (actual != null) ocupados.remove(actual);
    if (!mounted) return null;

    final numeros = [
      for (int n = PisoUtil.minimo; n <= PisoUtil.maximo; n++) n,
    ];

    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TemaApp.fondoCard,
        title: Text(
          actual == null ? '¿Qué piso es?' : 'Cambiar número de piso',
          style: const TextStyle(color: TemaApp.textoBlanco),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PB = planta baja · S = subsuelo',
                  style: TextStyle(color: TemaApp.textoSecundario, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: numeros.map((n) {
                    final usado = ocupados.contains(n);
                    final esActual = n == actual;
                    return Semantics(
                      button: true,
                      enabled: !usado,
                      label: usado
                          ? '${PisoUtil.nombre(n)}, ya cargado'
                          : PisoUtil.nombre(n),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: usado ? null : () => Navigator.pop(ctx, n),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor:
                                esActual ? TemaApp.acento : TemaApp.acentoSuave,
                            foregroundColor:
                                esActual ? TemaApp.fondo : TemaApp.textoBlanco,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            PisoUtil.etiquetaCorta(n),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
        ],
      ),
    );
  }

  void _agregarPiso() async {
    // 1) Primero el número: si se cancela, no se copia ninguna imagen.
    final numero = await _elegirNumeroPiso();
    if (numero == null) return;

    // 2) Después la imagen del plano.
    final picker = ImagePicker();
    final imagen = await picker.pickImage(source: ImageSource.gallery);
    if (imagen == null) return;

    final directory = await getApplicationDocumentsDirectory();
    final nombreArchivo = p.basename(imagen.path);
    final rutaPermanente = p.join(directory.path, nombreArchivo);
    await File(imagen.path).copy(rutaPermanente);

    await DatabaseHelper.instance.crearPiso(
      widget.edificioId,
      numero,
      rutaPermanente,
    );
    _refrescarPisos();
  }

  /// Cambia el número de un piso existente (o se lo asigna a un piso viejo
  /// que se cargó con nombre libre y no se pudo deducir).
  void _cambiarNumero(Map<String, dynamic> piso) async {
    final numero = await _elegirNumeroPiso(actual: piso['numero_piso'] as int?);
    if (numero == null) return;
    await DatabaseHelper.instance.actualizarNumeroPiso(piso['id'] as int, numero);
    _refrescarPisos();
    if (!mounted) return;
    if (piso['remote_id'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Número actualizado. Volvé a publicar el piso para que llegue a los usuarios.'),
        ),
      );
    }
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
                        title: Text(
                          piso['numero_piso'] != null
                              ? PisoUtil.nombre(piso['numero_piso'] as int)
                              : piso['nombre_piso'],
                          style: const TextStyle(color: TemaApp.textoBlanco, fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        subtitle: Text(
                          piso['numero_piso'] == null
                              ? 'Sin número de piso: tocá el lápiz para asignarlo'
                              : 'Deslizá para eliminar',
                          style: TextStyle(
                            color: piso['numero_piso'] == null
                                ? TemaApp.advertencia
                                : TemaApp.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, color: TemaApp.acento),
                              tooltip: 'Cambiar número de piso',
                              onPressed: () => _cambiarNumero(piso),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: TemaApp.textoSecundario),
                          ],
                        ),
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