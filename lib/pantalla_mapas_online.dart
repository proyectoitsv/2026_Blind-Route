import 'package:flutter/material.dart';

import 'database.dart';
import 'supabase_service.dart';
import 'tema.dart';

/// Filtros rápidos del catálogo.
enum _FiltroMapas { todos, actualizables, descargados }

/// Catálogo de mapas publicados. El usuario puede descargar, actualizar y quitar
/// mapas de su teléfono. Pensado para ser fácil de operar (también con lector de
/// pantalla): botones grandes y etiquetados, buscador por nombre y filtros.
///
/// Rendimiento: el listado sólo trae metadatos livianos; las miniaturas se
/// cargan bajo demanda con `cacheWidth`. El filtrado y la búsqueda se hacen en
/// memoria sobre esa lista liviana, sin volver a consultar la nube.
class PantallaMapasOnline extends StatefulWidget {
  const PantallaMapasOnline({super.key});

  @override
  State<PantallaMapasOnline> createState() => _PantallaMapasOnlineState();
}

class _PantallaMapasOnlineState extends State<PantallaMapasOnline> {
  List<MapaPublicadoResumen> _mapas = [];
  // remote_id → versión descargada (o null si se descargó antes de guardarla).
  Map<String, DateTime?> _descargados = {};
  final Set<String> _enProgreso = {};

  final TextEditingController _buscador = TextEditingController();
  String _busqueda = '';
  _FiltroMapas _filtro = _FiltroMapas.todos;

  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
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
      final resultados = await Future.wait([
        SupabaseService.instance.listarMapas(),
        DatabaseHelper.instance.obtenerMapasDescargados(),
      ]);
      if (!mounted) return;
      setState(() {
        _mapas = resultados[0] as List<MapaPublicadoResumen>;
        _descargados = resultados[1] as Map<String, DateTime?>;
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

  // ── Estado de cada mapa ─────────────────────────────────────────────────────

  bool _estaDescargado(MapaPublicadoResumen m) => _descargados.containsKey(m.id);

  bool _tieneActualizacion(MapaPublicadoResumen m) {
    if (!_estaDescargado(m)) return false;
    final v = _descargados[m.id];
    return v != null && m.actualizadoEn.isAfter(v);
  }

  int get _countActualizables => _mapas.where(_tieneActualizacion).length;
  int get _countDescargados => _mapas.where(_estaDescargado).length;

  // ── Acciones ────────────────────────────────────────────────────────────────

  Future<void> _descargar(MapaPublicadoResumen mapa) async {
    setState(() => _enProgreso.add(mapa.id));
    try {
      await SupabaseService.instance.descargarMapa(mapa.id);
      if (!mounted) return;
      setState(() {
        _descargados = {..._descargados, mapa.id: mapa.actualizadoEn};
        _enProgreso.remove(mapa.id);
      });
      _avisar('"${mapa.pisoNombre}" descargado');
    } catch (e) {
      if (!mounted) return;
      setState(() => _enProgreso.remove(mapa.id));
      _avisar('Error al descargar: $e');
    }
  }

  Future<void> _desinstalar(MapaPublicadoResumen mapa) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar del teléfono'),
        content: Text(
          'Se borrará "${mapa.pisoNombre}" de este teléfono. Podés volver a '
          'descargarlo cuando quieras.\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _enProgreso.add(mapa.id));
    try {
      await DatabaseHelper.instance.desinstalarMapaLocal(mapa.id);
      if (!mounted) return;
      setState(() {
        _descargados = {..._descargados}..remove(mapa.id);
        _enProgreso.remove(mapa.id);
      });
      _avisar('"${mapa.pisoNombre}" quitado del teléfono');
    } catch (e) {
      if (!mounted) return;
      setState(() => _enProgreso.remove(mapa.id));
      _avisar('Error al quitar: $e');
    }
  }

  void _avisar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Filtrado + agrupado ─────────────────────────────────────────────────────

  List<MapaPublicadoResumen> _mapasFiltrados() {
    final q = _busqueda.trim().toLowerCase();
    return _mapas.where((m) {
      switch (_filtro) {
        case _FiltroMapas.actualizables:
          if (!_tieneActualizacion(m)) return false;
          break;
        case _FiltroMapas.descargados:
          if (!_estaDescargado(m)) return false;
          break;
        case _FiltroMapas.todos:
          break;
      }
      if (q.isEmpty) return true;
      return m.pisoNombre.toLowerCase().contains(q) ||
          m.edificioNombre.toLowerCase().contains(q);
    }).toList();
  }

  /// Agrupa por edificio insertando encabezados (la lista ya viene ordenada).
  List<Object> _aplanarPorEdificio(List<MapaPublicadoResumen> mapas) {
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

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(title: const Text('Mapas disponibles')),
        body: _cargando
            ? const Center(
                child: CircularProgressIndicator(color: TemaApp.acento))
            : _error != null
                ? RefreshIndicator(
                    onRefresh: _cargar,
                    color: TemaApp.acento,
                    backgroundColor: TemaApp.fondoCard,
                    child: _mensajeCentrado(
                      icono: Icons.cloud_off_rounded,
                      titulo: 'No hay conexión con la nube',
                      detalle: _error!,
                    ),
                  )
                : Column(
                    children: [
                      _barraBusqueda(),
                      _barraFiltros(),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _cargar,
                          color: TemaApp.acento,
                          backgroundColor: TemaApp.fondoCard,
                          child: _lista(),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _barraBusqueda() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: TextField(
        controller: _buscador,
        onChanged: (v) => setState(() => _busqueda = v),
        style: const TextStyle(color: TemaApp.textoBlanco),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar mapa por nombre...',
          hintStyle: const TextStyle(color: TemaApp.textoSecundario),
          prefixIcon:
              const Icon(Icons.search_rounded, color: TemaApp.textoSecundario),
          suffixIcon: _busqueda.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Borrar búsqueda',
                  icon: const Icon(Icons.clear_rounded,
                      color: TemaApp.textoSecundario),
                  onPressed: () {
                    _buscador.clear();
                    setState(() => _busqueda = '');
                  },
                ),
          filled: true,
          fillColor: TemaApp.fondoCard,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(TemaApp.radiusButton),
            borderSide: const BorderSide(color: Color(0xFF21262D)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(TemaApp.radiusButton),
            borderSide: const BorderSide(color: Color(0xFF21262D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(TemaApp.radiusButton),
            borderSide: const BorderSide(color: TemaApp.acento),
          ),
        ),
      ),
    );
  }

  Widget _barraFiltros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Wrap(
        spacing: 8,
        children: [
          _chipFiltro('Todos', _FiltroMapas.todos, null),
          _chipFiltro(
              'Actualizables', _FiltroMapas.actualizables, _countActualizables),
          _chipFiltro(
              'Descargados', _FiltroMapas.descargados, _countDescargados),
        ],
      ),
    );
  }

  Widget _chipFiltro(String texto, _FiltroMapas filtro, int? cantidad) {
    final seleccionado = _filtro == filtro;
    final etiqueta =
        (cantidad != null && cantidad > 0) ? '$texto ($cantidad)' : texto;
    return ChoiceChip(
      label: Text(etiqueta),
      selected: seleccionado,
      onSelected: (_) => setState(() => _filtro = filtro),
      backgroundColor: TemaApp.fondoCard,
      selectedColor: TemaApp.acento.withValues(alpha: 0.25),
      side: BorderSide(
        color: seleccionado ? TemaApp.acento : const Color(0xFF21262D),
      ),
      labelStyle: TextStyle(
        color: seleccionado ? TemaApp.acento : TemaApp.textoSecundario,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }

  Widget _lista() {
    final filtrados = _mapasFiltrados();

    if (filtrados.isEmpty) {
      final vacio = _mensajeVacio();
      return _mensajeCentrado(
        icono: Icons.search_off_rounded,
        titulo: vacio.$1,
        detalle: vacio.$2,
      );
    }

    final items = _aplanarPorEdificio(filtrados);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is String) return _encabezadoEdificio(item);
        return _tarjetaMapa(item as MapaPublicadoResumen);
      },
    );
  }

  (String, String) _mensajeVacio() {
    if (_busqueda.isNotEmpty) {
      return ('Sin resultados', 'No hay mapas que coincidan con la búsqueda.');
    }
    switch (_filtro) {
      case _FiltroMapas.actualizables:
        return ('Todo al día', 'No hay mapas con actualizaciones pendientes.');
      case _FiltroMapas.descargados:
        return ('Nada descargado', 'Todavía no descargaste ningún mapa.');
      case _FiltroMapas.todos:
        return (
          'Todavía no hay mapas publicados',
          'Cuando un administrador publique un plano, aparecerá acá.'
        );
    }
  }

  Widget _encabezadoEdificio(String nombre) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
    final yaDescargado = _estaDescargado(mapa);
    final actualizacion = _tieneActualizacion(mapa);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: TemaApp.fondoCard,
        borderRadius: BorderRadius.circular(TemaApp.radiusCard),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _miniatura(mapa),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              mapa.pisoNombre,
                              style: const TextStyle(
                                color: TemaApp.textoBlanco,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (!yaDescargado) ...[
                            const SizedBox(width: 8),
                            _chip('Nuevo', TemaApp.acento),
                          ] else if (actualizacion) ...[
                            const SizedBox(width: 8),
                            _chip('Actualizado', TemaApp.instruccionAccent),
                          ],
                        ],
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
              ],
            ),
            const SizedBox(height: 12),
            _acciones(mapa, yaDescargado, actualizacion),
          ],
        ),
      ),
    );
  }

  Widget _acciones(
      MapaPublicadoResumen mapa, bool yaDescargado, bool actualizacion) {
    if (_enProgreso.contains(mapa.id)) {
      return const SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.6, color: TemaApp.acento),
          ),
        ),
      );
    }

    if (!yaDescargado) {
      return _botonAccion(
        icon: Icons.cloud_download_rounded,
        label: 'Descargar',
        color: TemaApp.acento,
        semantica: 'Descargar ${mapa.pisoNombre}',
        onTap: () => _descargar(mapa),
      );
    }

    // Descargado: acción principal (actualizar o estado) + quitar.
    return Row(
      children: [
        Expanded(
          child: actualizacion
              ? _botonAccion(
                  icon: Icons.refresh_rounded,
                  label: 'Actualizar',
                  color: TemaApp.instruccionAccent,
                  semantica: 'Actualizar ${mapa.pisoNombre}',
                  onTap: () => _descargar(mapa),
                )
              : _estadoDescargado(),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _botonAccion(
            icon: Icons.delete_outline_rounded,
            label: 'Quitar',
            color: TemaApp.zonaRestringidaRelleno,
            semantica: 'Quitar ${mapa.pisoNombre} del teléfono',
            onTap: () => _desinstalar(mapa),
            relleno: false,
          ),
        ),
      ],
    );
  }

  Widget _estadoDescargado() {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TemaApp.radiusButton),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded,
              color: TemaApp.instruccionAccent, size: 20),
          SizedBox(width: 8),
          Text('Descargado',
              style: TextStyle(
                  color: TemaApp.textoSecundario,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _botonAccion({
    required IconData icon,
    required String label,
    required Color color,
    required String semantica,
    required VoidCallback onTap,
    bool relleno = true,
  }) {
    return Semantics(
      button: true,
      label: semantica,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(TemaApp.radiusButton),
          onTap: onTap,
          child: Ink(
            height: 50,
            decoration: BoxDecoration(
              color:
                  relleno ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(TemaApp.radiusButton),
              border: Border.all(
                color: color.withValues(alpha: relleno ? 0.5 : 0.7),
                width: 1.4,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: relleno ? TemaApp.textoBlanco : color,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
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
                cacheWidth: 112,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => _placeholderMiniatura(),
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