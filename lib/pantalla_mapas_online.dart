import 'package:flutter/material.dart';

import 'database.dart';
import 'supabase_service.dart';
import 'tema.dart';

/// Catálogo de mapas publicados por los administradores. El usuario ve todos
/// los planos disponibles en la nube y descarga los que le interesan a la base
/// local; una vez descargado, el modo navegación los detecta como siempre.
///
/// Rendimiento: el listado sólo trae metadatos livianos (nombres + contadores),
/// las miniaturas se cargan bajo demanda desde Storage con `Image.network`
/// (Flutter cachea el decodificado) y `cacheWidth` limita la memoria por
/// imagen. Los datos pesados de un mapa (beacons, calibraciones) recién viajan
/// al tocar "Descargar".
class PantallaMapasOnline extends StatefulWidget {
  const PantallaMapasOnline({super.key});

  @override
  State<PantallaMapasOnline> createState() => _PantallaMapasOnlineState();
}

class _PantallaMapasOnlineState extends State<PantallaMapasOnline> {
  // Lista aplanada: cada elemento es un String (encabezado de edificio) o un
  // MapaPublicadoResumen (fila de mapa). Así el ListView.builder queda O(1).
  List<Object> _items = [];
  Set<String> _descargados = {};
  final Set<String> _enProgreso = {};

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
        _error = 'La nube de mapas no está configurada todavía.\n'
            'Cargá tus credenciales en supabase_config.dart.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Catálogo remoto + set local de descargados, en paralelo.
      final resultados = await Future.wait([
        SupabaseService.instance.listarMapas(),
        DatabaseHelper.instance.obtenerRemoteIdsLocales(),
      ]);
      final mapas = resultados[0] as List<MapaPublicadoResumen>;
      final descargados = resultados[1] as Set<String>;

      if (!mounted) return;
      setState(() {
        _descargados = descargados;
        _items = _aplanarPorEdificio(mapas);
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

  /// Agrupa por edificio insertando encabezados. La lista ya viene ordenada
  /// por (edificio, piso) desde el servidor.
  static List<Object> _aplanarPorEdificio(List<MapaPublicadoResumen> mapas) {
    final items = <Object>[];
    String? edificioActual;
    for (final m in mapas) {
      if (m.edificioNombre != edificioActual) {
        edificioActual = m.edificioNombre;
        items.add(edificioActual);
      }
      items.add(m);
    }
    return items;
  }

  Future<void> _descargar(MapaPublicadoResumen mapa) async {
    setState(() => _enProgreso.add(mapa.id));
    try {
      await SupabaseService.instance.descargarMapa(mapa.id);
      if (!mounted) return;
      setState(() {
        _descargados = {..._descargados, mapa.id};
        _enProgreso.remove(mapa.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${mapa.pisoNombre}" descargado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _enProgreso.remove(mapa.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al descargar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(title: const Text('Mapas disponibles')),
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
        detalle: 'Cuando un administrador publique un plano, aparecerá acá.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        if (item is String) return _encabezadoEdificio(item);
        return _tarjetaMapa(item as MapaPublicadoResumen);
      },
    );
  }

  Widget _encabezadoEdificio(String nombre) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.business_rounded, color: TemaApp.acento, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nombre,
              style: const TextStyle(
                color: TemaApp.textoBlanco,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaMapa(MapaPublicadoResumen mapa) {
    final yaDescargado = _descargados.contains(mapa.id);
    final descargando = _enProgreso.contains(mapa.id);

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
                    mapa.pisoNombre,
                    style: const TextStyle(
                      color: TemaApp.textoBlanco,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${mapa.numBeacons} beacons · '
                    '${mapa.numCalibraciones} calibraciones',
                    style: const TextStyle(
                      color: TemaApp.textoSecundario,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _boton(mapa, yaDescargado: yaDescargado, descargando: descargando),
          ],
        ),
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
            ? _placeholderMiniatura()
            : Image.network(
                SupabaseService.instance.urlImagen(mapa.imagenPath),
                fit: BoxFit.cover,
                // Decodifica a ~2x el tamaño de pantalla: mucho menos memoria
                // que cargar el plano completo para una miniatura.
                cacheWidth: 112,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _placeholderMiniatura(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _placeholderMiniatura(cargando: true);
                },
              ),
      ),
    );
  }

  Widget _placeholderMiniatura({bool cargando = false}) {
    return Container(
      color: TemaApp.fondoSurface,
      alignment: Alignment.center,
      child: cargando
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: TemaApp.acento,
              ),
            )
          : const Icon(Icons.map_rounded,
              color: TemaApp.textoSecundario, size: 24),
    );
  }

  Widget _boton(
    MapaPublicadoResumen mapa, {
    required bool yaDescargado,
    required bool descargando,
  }) {
    if (descargando) {
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

    if (yaDescargado) {
      // Descargado: se puede volver a descargar para traer la última versión.
      return Semantics(
        button: true,
        label: 'Actualizar ${mapa.pisoNombre}',
        child: TextButton.icon(
          onPressed: () => _descargar(mapa),
          style: TextButton.styleFrom(
            foregroundColor: TemaApp.instruccionAccent,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: const Text('Listo'),
        ),
      );
    }

    return Semantics(
      button: true,
      label: 'Descargar ${mapa.pisoNombre}',
      child: IconButton(
        onPressed: () => _descargar(mapa),
        icon: const Icon(Icons.cloud_download_rounded),
        color: TemaApp.acento,
        tooltip: 'Descargar',
        iconSize: 26,
      ),
    );
  }

  Widget _mensajeCentrado({
    required IconData icono,
    required String titulo,
    required String detalle,
  }) {
    // ListView (no Column) para que RefreshIndicator funcione aunque esté vacío.
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