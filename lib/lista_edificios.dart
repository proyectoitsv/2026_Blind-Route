import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database.dart';
import 'lista_pisos.dart';
import 'pantalla_login_admin.dart';
import 'pantalla_mapas_admin.dart';
import 'supabase_config.dart';
import 'supabase_service.dart';
import 'tema.dart';

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
    if (mounted) setState(() => _edificios = datos);
  }

  Future<bool> _confirmarBorradoEdificio(BuildContext context, String nombre) async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TemaApp.fondoCard,
        title: const Text('¿Eliminar edificio?', style: TextStyle(color: TemaApp.textoBlanco)),
        content: Text(
          'Se eliminará "$nombre", incluyendo todos sus pisos y beacons. Esta acción es permanente.',
          style: const TextStyle(color: TemaApp.textoSecundario),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: TemaApp.zonaRestringidaBorde),
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
        backgroundColor: TemaApp.fondoCard,
        title: const Text('Nuevo Edificio', style: TextStyle(color: TemaApp.textoBlanco)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: TemaApp.textoBlanco),
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
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(
          title: const Text('Blind Route — Edificios'),
          actions: [
            if (SupabaseConfig.configurado)
              IconButton(
                tooltip: 'Mapas publicados en la nube',
                icon: const Icon(Icons.cloud_rounded),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PantallaMapasAdmin()),
                  );
                },
              ),
            if (SupabaseConfig.configurado)
              IconButton(
                tooltip: 'Cerrar sesión',
                icon: const Icon(Icons.logout_rounded),
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (!context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PantallaLoginAdmin()),
                  );
                },
              ),
          ],
        ),
        body: _edificios.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.business_outlined, size: 64, color: TemaApp.textoSecundario),
                    SizedBox(height: 16),
                    Text('No hay edificios registrados', style: TextStyle(color: TemaApp.textoSecundario, fontSize: 16)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _edificios.length,
                itemBuilder: (context, i) {
                  final edificio = _edificios[i];
                  return Dismissible(
                    key: Key(edificio['id'].toString()),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      final confirmado = await _confirmarBorradoEdificio(
                          context, edificio['nombre']);
                      if (confirmado != true) return false;

                      // Un edificio arrastra a sus pisos. Antes de borrarlo,
                      // se quitan de la nube todos sus mapas publicados. Si
                      // alguno falla (offline o de otro dueño), se aborta y no
                      // se borra nada local, para no dejar mapas huérfanos.
                      if (SupabaseService.instance.configurado) {
                        final remoteIds = await DatabaseHelper.instance
                            .obtenerRemoteIdsDeEdificio(edificio['id']);
                        for (final remoteId in remoteIds) {
                          try {
                            await SupabaseService.instance
                                .eliminarMapa(remoteId);
                          } catch (e) {
                            if (!mounted) return false;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'No se pudo quitar un mapa de la nube: $e\nNo se eliminó el edificio.'),
                              ),
                            );
                            return false;
                          }
                        }
                      }

                      await DatabaseHelper.instance
                          .eliminarEdificioCompleto(edificio['id']);
                      if (!mounted) return true;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                            content: Text(
                                "Se eliminó ${edificio['nombre']} y todos sus datos")),
                      );
                      return true;
                    },
                    background: Container(
                      color: TemaApp.zonaRestringidaRelleno,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete_sweep, color: Colors.white, size: 28),
                    ),
                    onDismissed: (direction) => _refrescarEdificios(),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: TemaApp.fondoCard,
                        borderRadius: BorderRadius.circular(TemaApp.radiusCard),
                        border: Border.all(color: const Color(0xFF21262D), width: 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: TemaApp.acentoSuave,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.business_rounded, color: TemaApp.acento, size: 22),
                        ),
                        title: Text(edificio['nombre'], style: const TextStyle(color: TemaApp.textoBlanco, fontWeight: FontWeight.w600, fontSize: 16)),
                        subtitle: const Text('Deslizá para eliminar', style: TextStyle(color: TemaApp.textoSecundario, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: TemaApp.textoSecundario),
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
          backgroundColor: TemaApp.acento,
          foregroundColor: TemaApp.fondo,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}