import 'dart:io';

import 'package:flutter/material.dart';

import 'database.dart';
import 'design/design.dart';
import 'supabase_service.dart';

/// Filtros rápidos del catálogo.
enum _FiltroMapas { todos, actualizables, descargados }

/// En qué está un mapa del catálogo para este teléfono.
enum EstadoMapa {
  /// Todavía no se descargó.
  nuevo,

  /// Descargado, y en la nube hay una versión más nueva.
  actualizable,

  /// Descargado y al día.
  descargado,
}

/// Lo que se está haciendo con un mapa. Mientras dura, su tarjeta lo dice en
/// lugar de los botones.
enum OperacionMapa { descarga, actualizacion, borrado }

/// Catálogo de mapas publicados. El usuario puede descargar, actualizar y quitar
/// mapas de su teléfono. Pensado para ser fácil de operar (también con lector de
/// pantalla): botones grandes y etiquetados, buscador por nombre y filtros.
///
/// Rendimiento: el listado sólo trae metadatos livianos y NO baja ninguna
/// imagen. La miniatura se muestra sólo en los mapas ya descargados, desde el
/// archivo del teléfono; el resto lleva un ícono. (Antes se pedía a la nube el
/// plano completo de cada mapa visible sólo para dibujar la miniatura:
/// `cacheWidth` achica la imagen en memoria, no la descarga.) El filtrado y la
/// búsqueda se hacen en memoria sobre esa lista liviana, sin volver a
/// consultar la nube.
///
/// ─── Sistema de diseño (fase 5.2 del rediseño) ───
/// Va envuelta en AmbienteDiseno. El buscador, los filtros y la lista se
/// desplazan juntos: con letra grande, la lista no queda reducida a un
/// renglón. Cada mapa es una TarjetaMapa (abajo), con los botones de siempre
/// y las mismas etiquetas de TalkBack; ninguno va en cian, porque serían
/// varios botones principales en la pantalla. Lo que no es la lista (vacía,
/// sin conexión, cargando) es un EstadoPantalla, quieto (sin nada que gire),
/// que TalkBack anuncia al aparecer. Quitar un mapa se confirma en una hoja
/// (mostrarConfirmacion) y los avisos son los del sistema de diseño
/// (mostrarAviso).
///
/// Tirar hacia abajo vuelve a cargar la lista, como antes. Con TalkBack eso no
/// se puede hacer: para eso están el botón de la barra ("Volver a cargar la
/// lista") y "Reintentar" en el error de conexión, que hacen lo mismo.
class PantallaMapasOnline extends StatefulWidget {
  const PantallaMapasOnline({super.key});

  @override
  State<PantallaMapasOnline> createState() => _PantallaMapasOnlineState();
}

class _PantallaMapasOnlineState extends State<PantallaMapasOnline> {
  List<MapaPublicadoResumen> _mapas = [];
  // remote_id → versión descargada (o null si se descargó antes de guardarla).
  Map<String, DateTime?> _descargados = {};
  // remote_id → ruta local de la imagen del plano (sólo mapas descargados).
  Map<String, String> _imagenesLocales = {};
  final Set<String> _enProgreso = {};
  // remote_id → qué se está haciendo con él, para que la tarjeta lo diga
  // mientras está en _enProgreso. Lo anotan los botones de la tarjeta.
  final Map<String, OperacionMapa> _operaciones = {};

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
        _error =
            'La nube de mapas no está configurada todavía.\n'
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
      final mapas = resultados[0] as List<MapaPublicadoResumen>;
      final descargados = resultados[1] as Map<String, DateTime?>;
      final quitados = await _quitarEliminados(mapas, descargados);
      final imagenes = await DatabaseHelper.instance
          .obtenerImagenesDescargadas();
      if (!mounted) return;
      setState(() {
        _mapas = mapas;
        _descargados = descargados;
        _imagenesLocales = imagenes;
        _cargando = false;
      });
      if (quitados > 0) {
        _avisar(
          quitados == 1
              ? 'Se quitó 1 mapa que ya no está disponible'
              : 'Se quitaron $quitados mapas que ya no están disponibles',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los mapas: $e';
      });
    }
  }

  /// Quita del teléfono los mapas descargados que el admin eliminó de la nube
  /// (los que están en [descargados] pero ya no figuran en [mapas]). Saca esas
  /// entradas de [descargados] y devuelve cuántos quitó.
  ///
  /// No hace ninguna consulta: usa el catálogo que se acaba de bajar. Por eso
  /// depende de que `listarMapas()` traiga el catálogo COMPLETO; si algún día
  /// se pagina o se filtra, esta limpieza tiene que confirmar por id antes de
  /// borrar. Sólo corre cuando la lista llegó bien: sin conexión no se toca
  /// nada.
  Future<int> _quitarEliminados(
    List<MapaPublicadoResumen> mapas,
    Map<String, DateTime?> descargados,
  ) async {
    if (descargados.isEmpty) return 0;
    final enNube = <String>{for (final m in mapas) m.id};
    final eliminados = <String>[
      for (final id in descargados.keys)
        if (!enNube.contains(id)) id,
    ];
    var quitados = 0;
    for (final id in eliminados) {
      try {
        await DatabaseHelper.instance.desinstalarMapaLocal(id);
        descargados.remove(id);
        quitados++;
      } catch (e) {
        // Si no se pudo quitar, no se frena el catálogo: se reintenta la
        // próxima vez que se abra.
        debugPrint('[Catálogo] No se pudo quitar el mapa $id: $e');
      }
    }
    return quitados;
  }

  // ── Estado de cada mapa ─────────────────────────────────────────────────────

  bool _estaDescargado(MapaPublicadoResumen m) =>
      _descargados.containsKey(m.id);

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
      final pisoId = await SupabaseService.instance.descargarMapa(mapa.id);
      // Ruta del plano recién bajado, para mostrar su miniatura.
      final piso = await DatabaseHelper.instance.obtenerPisoInfo(pisoId);
      if (!mounted) return;
      setState(() {
        _descargados = {..._descargados, mapa.id: mapa.actualizadoEn};
        if (piso != null) {
          _imagenesLocales = {..._imagenesLocales, mapa.id: piso.rutaImagen};
        }
        _enProgreso.remove(mapa.id);
      });
      _avisar('"${mapa.pisoNombre}" descargado');
    } catch (e) {
      if (!mounted) return;
      setState(() => _enProgreso.remove(mapa.id));
      _avisar('Error al descargar: $e', error: true);
    }
  }

  Future<void> _desinstalar(MapaPublicadoResumen mapa) async {
    final confirmar = await mostrarConfirmacion(
      context,
      titulo: 'Quitar del teléfono',
      mensaje:
          'Se borrará "${mapa.pisoNombre}" de este teléfono. Podés volver '
          'a descargarlo cuando quieras.\n\n¿Continuar?',
      confirmar: 'Quitar',
      destructiva: true,
      iconoConfirmar: Icons.delete_rounded,
    );
    if (!confirmar) return;

    setState(() => _enProgreso.add(mapa.id));
    try {
      await DatabaseHelper.instance.desinstalarMapaLocal(mapa.id);
      if (!mounted) return;
      setState(() {
        _descargados = {..._descargados}..remove(mapa.id);
        _imagenesLocales = {..._imagenesLocales}..remove(mapa.id);
        _enProgreso.remove(mapa.id);
      });
      _avisar('"${mapa.pisoNombre}" quitado del teléfono');
    } catch (e) {
      if (!mounted) return;
      setState(() => _enProgreso.remove(mapa.id));
      _avisar('Error al quitar: $e', error: true);
    }
  }

  void _avisar(String msg, {bool error = false}) {
    if (!mounted) return;
    mostrarAviso(context, msg, error: error);
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
    return AmbienteDiseno(
      child: Builder(
        builder: (context) {
          final e = EstiloApp.de(context);
          return Scaffold(
            backgroundColor: e.fondo,
            appBar: BarraSuperior(
              titulo: 'Mapas disponibles',
              acciones: [
                if (SupabaseService.instance.configurado)
                  AccionBarra(
                    icono: Icons.refresh_rounded,
                    etiqueta: 'Volver a cargar la lista',
                    alPresionar: _cargando ? null : _cargar,
                  ),
              ],
            ),
            body: SafeArea(top: false, child: _cuerpo(e)),
          );
        },
      ),
    );
  }

  Widget _cuerpo(EstiloApp e) {
    if (_cargando) {
      return _enElMedio(
        const EstadoPantalla(
          icono: Icons.hourglass_empty_rounded,
          titulo: 'Cargando mapas…',
        ),
      );
    }
    if (_error != null) {
      return _conRecarga(
        e,
        _enElMedio(
          EstadoPantalla(
            icono: Icons.cloud_off_rounded,
            titulo: 'No hay conexión con la nube',
            detalle: _error,
            accion: SupabaseService.instance.configurado
                ? BotonSecundario(
                    texto: 'Reintentar',
                    icono: Icons.refresh_rounded,
                    alPresionar: _cargar,
                  )
                : null,
          ),
        ),
      );
    }
    return _conRecarga(e, _lista());
  }

  /// [estado] en el medio de la pantalla. Si con letra grande no entra, se
  /// desplaza (y se puede tirar hacia abajo aunque entre).
  Widget _enElMedio(Widget estado) => CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverFillRemaining(hasScrollBody: false, child: Center(child: estado)),
    ],
  );

  /// Tirar hacia abajo vuelve a cargar la lista.
  Widget _conRecarga(EstiloApp e, Widget hijo) => RefreshIndicator(
    onRefresh: _cargar,
    color: e.acento,
    backgroundColor: e.superficie,
    child: hijo,
  );

  Widget _lista() {
    final filtrados = _mapasFiltrados();
    final items = _aplanarPorEdificio(filtrados);
    final vacio = filtrados.isEmpty ? _mensajeVacio() : null;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            EspaciadoApp.margenLateral,
            EspaciadoApp.margenLateral,
            EspaciadoApp.margenLateral,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CampoTexto.busqueda(
                  etiqueta: 'Buscar mapa',
                  ayuda: 'Buscar mapa por nombre…',
                  controlador: _buscador,
                  alCambiar: (v) => setState(() => _busqueda = v),
                ),
                const SizedBox(height: EspaciadoApp.margenLateral),
                _barraFiltros(),
              ],
            ),
          ),
        ),
        if (vacio != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EstadoPantalla(
                icono: Icons.search_off_rounded,
                titulo: vacio.$1,
                detalle: vacio.$2,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              EspaciadoApp.margenLateral,
              EspaciadoApp.entreSecciones,
              EspaciadoApp.margenLateral,
              EspaciadoApp.entreSecciones,
            ),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => _item(items, i),
            ),
          ),
      ],
    );
  }

  Widget _barraFiltros() {
    return Wrap(
      spacing: EspaciadoApp.chico,
      runSpacing: EspaciadoApp.chico,
      children: [
        _chipFiltro('Todos', _FiltroMapas.todos, null),
        _chipFiltro(
          'Actualizables',
          _FiltroMapas.actualizables,
          _countActualizables,
        ),
        _chipFiltro('Descargados', _FiltroMapas.descargados, _countDescargados),
      ],
    );
  }

  Widget _chipFiltro(String texto, _FiltroMapas filtro, int? cantidad) {
    final etiqueta = (cantidad != null && cantidad > 0)
        ? '$texto ($cantidad)'
        : texto;
    return ChipFiltro(
      texto: etiqueta,
      seleccionado: _filtro == filtro,
      exclusivo: true,
      alCambiar: (_) => setState(() => _filtro = filtro),
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
          'Cuando un administrador publique un plano, aparecerá acá.',
        );
    }
  }

  /// El encabezado de un edificio o la tarjeta de un mapa, con su aire: 28
  /// antes de cada edificio (menos el primero), 12 entre el encabezado y su
  /// primer mapa y entre mapa y mapa.
  Widget _item(List<Object> items, int i) {
    final item = items[i];
    if (item is String) {
      return Padding(
        padding: EdgeInsets.only(
          top: i == 0 ? 0 : EspaciadoApp.entreSecciones,
          bottom: EspaciadoApp.medio,
        ),
        child: EncabezadoSeccion(titulo: item),
      );
    }
    final mapa = item as MapaPublicadoResumen;
    final sigueOtroMapa =
        i + 1 < items.length && items[i + 1] is MapaPublicadoResumen;
    return Padding(
      padding: EdgeInsets.only(
        bottom: sigueOtroMapa ? EspaciadoApp.entreTarjetas : 0,
      ),
      child: _tarjetaMapa(mapa),
    );
  }

  Widget _tarjetaMapa(MapaPublicadoResumen mapa) {
    final estado = !_estaDescargado(mapa)
        ? EstadoMapa.nuevo
        : _tieneActualizacion(mapa)
        ? EstadoMapa.actualizable
        : EstadoMapa.descargado;
    return TarjetaMapa(
      mapa: mapa,
      estado: estado,
      rutaImagen: _imagenesLocales[mapa.id],
      operacion: _enProgreso.contains(mapa.id)
          ? (_operaciones[mapa.id] ?? OperacionMapa.descarga)
          : null,
      alDescargar: () {
        _operaciones[mapa.id] = OperacionMapa.descarga;
        _descargar(mapa);
      },
      alActualizar: () {
        _operaciones[mapa.id] = OperacionMapa.actualizacion;
        _descargar(mapa);
      },
      alQuitar: () {
        _operaciones[mapa.id] = OperacionMapa.borrado;
        _desinstalar(mapa);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tarjeta de un mapa
// ═══════════════════════════════════════════════════════════════════════════
//
// Levantada (radio 20), sin borde: los botones de adentro llevan el suyo.
// Arriba, la miniatura del plano en un cuadro hundido (sólo si está en el
// teléfono; si no, un ícono), el nombre del piso, cuántos beacons y
// calibraciones tiene y la marca de su estado en un chip hundido ("Nuevo",
// "Actualizable", "Descargado"), sin cian ni verde: la v5 los guarda para lo
// elegido y para la ruta. Abajo, los botones: "Descargar" en uno nuevo;
// "Actualizar" y "Quitar" en uno actualizable; "Quitar" en uno descargado.
// Son secundarios ("Quitar", en rojo) y van lado a lado o, si con letra
// grande no entran, uno debajo del otro (FilaBotones).
//
// Mientras se descarga, se actualiza o se quita, en lugar de los botones va
// un recuadro hundido y quieto que dice qué se está haciendo; TalkBack lo
// anuncia.
//
// ─── TalkBack ───
// La parte de arriba se lee de una vez ("Planta baja, 4 beacons y 12
// calibraciones, Nuevo"). Los botones conservan las etiquetas de siempre:
// "Descargar Planta baja", "Actualizar Planta baja" y "Quitar Planta baja
// del teléfono".
//
// Sólo muestra y avisa los toques: la carga, la descarga y el borrado los
// hace la pantalla. Así se puede probar sin la nube.

/// La tarjeta de un mapa del catálogo.
class TarjetaMapa extends StatelessWidget {
  const TarjetaMapa({
    super.key,
    required this.mapa,
    required this.estado,
    required this.alDescargar,
    required this.alActualizar,
    required this.alQuitar,
    this.rutaImagen,
    this.operacion,
  });

  final MapaPublicadoResumen mapa;
  final EstadoMapa estado;

  /// El plano en el teléfono, para la miniatura. null: un ícono.
  final String? rutaImagen;

  /// Lo que se está haciendo con el mapa. null: nada (se ven los botones).
  final OperacionMapa? operacion;

  final VoidCallback alDescargar;
  final VoidCallback alActualizar;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final (marca, iconoMarca) = switch (estado) {
      EstadoMapa.nuevo => ('Nuevo', Icons.cloud_rounded),
      EstadoMapa.actualizable => ('Actualizable', Icons.update_rounded),
      EstadoMapa.descargado => ('Descargado', Icons.download_done_rounded),
    };
    final beacons = mapa.numBeacons;
    final calibraciones = mapa.numCalibraciones;
    return PanelRelieve(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Miniatura(rutaImagen: rutaImagen),
                const SizedBox(width: EspaciadoApp.medio),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mapa.pisoNombre,
                        style: TipografiaApp.destacado.copyWith(
                          color: e.textoPrincipal,
                        ),
                      ),
                      const SizedBox(height: EspaciadoApp.minimo),
                      Text(
                        '$beacons beacons · $calibraciones calibraciones',
                        semanticsLabel:
                            '$beacons beacons y $calibraciones calibraciones',
                        style: TipografiaApp.subtitulo.copyWith(
                          color: e.textoSecundario,
                        ),
                      ),
                      const SizedBox(height: EspaciadoApp.chico),
                      ChipApp(texto: marca, icono: iconoMarca),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Más aire que el alcance de la luz de los botones: ninguna sombra
          // cae sobre el texto del chip.
          const SizedBox(height: EspaciadoApp.margenLateral),
          _acciones(),
        ],
      ),
    );
  }

  Widget _acciones() {
    final piso = mapa.pisoNombre;
    final enCurso = operacion;
    if (enCurso != null) {
      final (texto, etiqueta) = switch (enCurso) {
        OperacionMapa.descarga => ('Descargando…', 'Descargando $piso'),
        OperacionMapa.actualizacion => ('Actualizando…', 'Actualizando $piso'),
        OperacionMapa.borrado => ('Quitando…', 'Quitando $piso del teléfono'),
      };
      return _EnCurso(texto: texto, etiqueta: etiqueta);
    }
    final quitar = BotonSecundario(
      texto: 'Quitar',
      icono: Icons.delete_rounded,
      destructivo: true,
      etiquetaSemantica: 'Quitar $piso del teléfono',
      alPresionar: alQuitar,
    );
    return FilaBotones(
      children: switch (estado) {
        EstadoMapa.nuevo => [
          BotonSecundario(
            texto: 'Descargar',
            icono: Icons.cloud_download_rounded,
            etiquetaSemantica: 'Descargar $piso',
            alPresionar: alDescargar,
          ),
        ],
        EstadoMapa.actualizable => [
          BotonSecundario(
            texto: 'Actualizar',
            icono: Icons.update_rounded,
            etiquetaSemantica: 'Actualizar $piso',
            alPresionar: alActualizar,
          ),
          quitar,
        ],
        EstadoMapa.descargado => [quitar],
      },
    );
  }
}

/// La miniatura del plano: un cuadro hundido con el plano del teléfono o,
/// si no está, el ícono de un mapa. Decorativa. Sale del archivo local: no se
/// pide ninguna imagen a la nube.
class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.rutaImagen});

  final String? rutaImagen;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final ruta = rutaImagen;
    final icono = Center(
      child: Icon(
        Icons.map_rounded,
        size: FormasApp.icono,
        color: e.textoSecundario,
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: FormasApp.miniatura,
        // La sombra interior va encima del plano: así se ve hundido.
        child: PanelRelieve(
          hundido: true,
          tamano: TamanoRelieve.chico,
          radio: FormasApp.bordeCampo,
          relleno: EdgeInsets.zero,
          sombraEncima: true,
          child: ruta == null
              ? icono
              : Image.file(
                  File(ruta),
                  fit: BoxFit.cover,
                  cacheWidth: 112,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) => icono,
                ),
        ),
      ),
    );
  }
}

/// Lo que va en lugar de los botones mientras se descarga, se actualiza o se
/// quita un mapa: un recuadro hundido del alto de un botón, quieto, con
/// [texto]. TalkBack dice [etiqueta] al aparecer.
class _EnCurso extends StatelessWidget {
  const _EnCurso({required this.texto, required this.etiqueta});

  final String texto;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: etiqueta,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FormasApp.altoBoton),
        child: PanelRelieve(
          hundido: true,
          tamano: TamanoRelieve.chico,
          radio: FormasApp.bordeBoton,
          relleno: const EdgeInsets.symmetric(
            horizontal: EspaciadoApp.rellenoTarjeta,
            vertical: EspaciadoApp.medio,
          ),
          child: Center(
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: TipografiaApp.boton.copyWith(color: e.textoSecundario),
            ),
          ),
        ),
      ),
    );
  }
}
