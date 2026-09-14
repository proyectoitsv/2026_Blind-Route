import 'package:flutter/material.dart';

import 'supabase_service.dart';
import 'tema.dart';

/// Pantalla de administración de los mapas publicados en la nube. A diferencia
/// de la lista de edificios (que es local de cada teléfono), esta lee TODOS los
/// mapas del servidor, sin importar desde qué dispositivo se subieron.
///
/// - Los mapas de la cuenta logueada aparecen primero, marcados como "Tuyo".
/// - Sólo se pueden borrar los propios (el servidor rechaza el resto).
class PantallaMapasAdmin extends StatefulWidget {
  const PantallaMapasAdmin({super.key});

  @override
  State<PantallaMapasAdmin> createState() => _PantallaMapasAdminState();
}

class _PantallaMapasAdminState extends State<PantallaMapasAdmin> {
  // Lista aplanada: String = encabezado de sección; MapaPublicadoResumen = fila.
  List<Object> _items = [];
  final Set<String> _enProgreso = {};
  String? _uid;

  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!SupabaseService.instance.configurado) {
      setState(() {
        _cargando = false;
        _error = 'La nube de mapas no está configurada.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      _uid = SupabaseService.instance.usuarioActualId;
      final mapas = await SupabaseService.instance.listarMapasAdmin();
      if (!mounted) return;
      setState(() {
        _items = _aplanar(mapas);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los mapas: $e';
      });
    }
  }

  bool _esPropio(MapaPublicadoResumen m) =>
      _uid != null && m.publicadoPor == _uid;

  /// Separa en "propios" y "otros" (conservando el orden del servidor por
  /// edificio/piso dentro de cada grupo) y arma la lista con encabezados.
  List<Object> _aplanar(List<MapaPublicadoResumen> mapas) {
    final propios = mapas.where(_esPropio).toList();
    final otros = mapas.where((m) => !_esPropio(m)).toList();

    final items = <Object>[];
    if (propios.isNotEmpty) {
      items.add('Tus mapas');
      items.addAll(propios);
    }
    if (otros.isNotEmpty) {
      items.add('Otros administradores');
      items.addAll(otros);
    }
    return items;
  }

  Future<void> _eliminar(MapaPublicadoResumen mapa) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar de la nube'),
        content: Text(
          'Se quitará "${mapa.pisoNombre}" del catálogo. Los usuarios ya no '
          'podrán descargarlo.\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _enProgreso.add(mapa.id));
    try {
      await SupabaseService.instance.eliminarMapa(mapa.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${mapa.pisoNombre}" eliminado')),
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enProgreso.remove(mapa.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(title: const Text('Mapas publicados')),
        body: RefreshIndicator(
          onRefresh: _cargar,
          color: TemaApp.acento,
          backgroundColor: TemaApp.fondoCard,
          child: _construirCuerpo(),
        ),
      ),
    );
  }

  Widget _construirCuerpo() {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(color: TemaApp.acento),
      );
    }

    if (_error != null) {
      return _mensajeCentrado(
        icono: Icons.cloud_off_rounded,
        titulo: 'No hay conexión con la nube',
        detalle: _error!,
      );
    }

    if (_items.isEmpty) {
      return _mensajeCentrado(
        icono: Icons.map_outlined,
        titulo: 'Todavía no hay mapas publicados',
        detalle: 'Publicá un piso desde la configuración para verlo acá.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        if (item is String) return _encabezado(item);
        return _tarjeta(item as MapaPublicadoResumen);
      },
    );
  }

  Widget _encabezado(String texto) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        texto,
        style: const TextStyle(
          color: TemaApp.acento,
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _tarjeta(MapaPublicadoResumen mapa) {
    final propio = _esPropio(mapa);
    final borrando = _enProgreso.contains(mapa.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: TemaApp.fondoCard,
        borderRadius: BorderRadius.circular(TemaApp.radiusCard),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _miniatura(mapa),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mapa.edificioNombre,
                    style: const TextStyle(
                      color: TemaApp.textoSecundario,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mapa.pisoNombre,
                    style: const TextStyle(
                      color: TemaApp.textoBlanco,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (propio) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: TemaApp.acento.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Tuyo',
                            style: TextStyle(
                              color: TemaApp.acento,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${mapa.numBeacons} beacons',
                        style: const TextStyle(
                          color: TemaApp.textoSecundario,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _accion(mapa, propio: propio, borrando: borrando),
          ],
        ),
      ),
    );
  }

  Widget _accion(
    MapaPublicadoResumen mapa, {
    required bool propio,
    required bool borrando,
  }) {
    if (borrando) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: TemaApp.acento),
          ),
        ),
      );
    }

    // Sólo se pueden borrar los propios. En los ajenos se muestra un candado.
    if (!propio) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Icon(Icons.lock_outline_rounded,
            color: TemaApp.textoSecundario, size: 20),
      );
    }

    return Semantics(
      button: true,
      label: 'Eliminar ${mapa.pisoNombre}',
      child: IconButton(
        onPressed: () => _eliminar(mapa),
        icon: const Icon(Icons.delete_outline_rounded),
        color: TemaApp.zonaRestringidaRelleno,
        tooltip: 'Eliminar de la nube',
        iconSize: 24,
      ),
    );
  }

  Widget _miniatura(MapaPublicadoResumen mapa) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: mapa.imagenPath.isEmpty
            ? _placeholder()
            : Image.network(
                SupabaseService.instance.urlImagen(mapa.imagenPath),
                fit: BoxFit.cover,
                cacheWidth: 112,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _placeholder(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _placeholder(cargando: true);
                },
              ),
      ),
    );
  }

  Widget _placeholder({bool cargando = false}) {
    return Container(
      color: TemaApp.fondoSurface,
      alignment: Alignment.center,
      child: cargando
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: TemaApp.acento),
            )
          : const Icon(Icons.map_rounded,
              color: TemaApp.textoSecundario, size: 24),
    );
  }

  Widget _mensajeCentrado({
    required IconData icono,
    required String titulo,
    required String detalle,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Icon(icono, size: 64, color: TemaApp.textoSecundario),
        const SizedBox(height: 16),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: TemaApp.textoBlanco,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          detalle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: TemaApp.textoSecundario, fontSize: 13),
        ),
      ],
    );
  }
}