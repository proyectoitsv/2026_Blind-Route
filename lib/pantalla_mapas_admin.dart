import 'package:flutter/material.dart';

import 'design/design.dart';
import 'supabase_service.dart';

/// Pantalla de administración de los mapas publicados en la nube. A diferencia
/// de la lista de edificios (que es local de cada teléfono), esta lee TODOS los
/// mapas del servidor, sin importar desde qué dispositivo se subieron.
///
/// - Los mapas de la cuenta logueada aparecen primero, marcados como "Tuyo".
/// - Sólo se pueden borrar los propios (el servidor rechaza el resto).
///
/// ─── Sistema de diseño (fase 5.5 del rediseño) ───
/// Va envuelta en AmbienteDiseno, como el catálogo del usuario
/// (pantalla_mapas_online.dart), que es su modelo: la barra con "Volver a
/// cargar la lista" (con TalkBack no se puede tirar hacia abajo), los dos
/// grupos con su EncabezadoSeccion ("Tus mapas" y "Otros administradores") y
/// cada mapa en una TarjetaMapaAdmin (abajo). Cargando, sin conexión (con
/// "Reintentar") y sin mapas: EstadoPantalla, quieto (sin nada que gire), que
/// TalkBack anuncia. Eliminar un mapa se confirma en una hoja
/// (mostrarConfirmacion) y los avisos son los del sistema de diseño
/// (mostrarAviso).
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
    final confirmar = await mostrarConfirmacion(
      context,
      titulo: 'Eliminar de la nube',
      mensaje:
          'Se quitará "${mapa.pisoNombre}" del catálogo. Los usuarios ya no '
          'podrán descargarlo.\n\n¿Continuar?',
      confirmar: 'Eliminar',
      destructiva: true,
      iconoConfirmar: Icons.delete_rounded,
    );
    if (!confirmar) return;

    setState(() => _enProgreso.add(mapa.id));
    try {
      await SupabaseService.instance.eliminarMapa(mapa.id);
      if (!mounted) return;
      _avisar('"${mapa.pisoNombre}" eliminado');
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enProgreso.remove(mapa.id));
      _avisar('Error al eliminar: $e', error: true);
    }
  }

  void _avisar(String msg, {bool error = false}) {
    if (!mounted) return;
    mostrarAviso(context, msg, error: error);
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
              titulo: 'Mapas publicados',
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

    if (_items.isEmpty) {
      return _conRecarga(
        e,
        _enElMedio(
          const EstadoPantalla(
            icono: Icons.map_rounded,
            titulo: 'Todavía no hay mapas publicados',
            detalle: 'Publicá un piso desde la configuración para verlo acá.',
          ),
        ),
      );
    }

    return _conRecarga(
      e,
      ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          EspaciadoApp.margenLateral,
          EspaciadoApp.margenLateral,
          EspaciadoApp.margenLateral,
          EspaciadoApp.entreSecciones,
        ),
        itemCount: _items.length,
        itemBuilder: _item,
      ),
    );
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

  /// El encabezado de un grupo o la tarjeta de un mapa, con su aire: 28 antes
  /// de cada grupo (menos el primero), 12 entre el encabezado y su primer
  /// mapa y entre mapa y mapa.
  Widget _item(BuildContext context, int i) {
    final item = _items[i];
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
        i + 1 < _items.length && _items[i + 1] is MapaPublicadoResumen;
    return Padding(
      padding: EdgeInsets.only(
        bottom: sigueOtroMapa ? EspaciadoApp.entreTarjetas : 0,
      ),
      child: TarjetaMapaAdmin(
        mapa: mapa,
        propio: _esPropio(mapa),
        eliminando: _enProgreso.contains(mapa.id),
        urlImagen: mapa.imagenPath.isEmpty
            ? null
            : SupabaseService.instance.urlImagen(mapa.imagenPath),
        alEliminar: () => _eliminar(mapa),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tarjeta de un mapa publicado
// ═══════════════════════════════════════════════════════════════════════════
//
// Como la del catálogo del usuario (TarjetaMapa, pantalla_mapas_online.dart):
// levantada (radio 20) y sin borde, porque el botón de adentro lleva el suyo.
// Arriba, la miniatura del plano en un cuadro hundido (la imagen de la nube;
// mientras llega o si no llega, el ícono de un mapa, sin nada que gire), el
// edificio en gris, el nombre del piso, cuántos beacons y calibraciones tiene
// y, si es de la cuenta, la marca "Tuyo" en un chip hundido (sin cian: la v5
// lo guarda para lo elegido).
//
// Abajo, en uno propio, "Eliminar" (secundario, en rojo, nunca en cian). En
// uno de otro administrador, en lugar del botón, una línea con el candado
// que dice por qué no se puede eliminar (antes, sólo el candado, que TalkBack
// no leía). Mientras se elimina, en lugar del botón va un recuadro hundido y
// quieto que dice "Eliminando…" y que TalkBack anuncia.
//
// ─── TalkBack ───
// La parte de arriba se lee de una vez ("Facultad de Ingeniería, Planta
// baja, 4 beacons y 12 calibraciones, Tuyo"), y en uno ajeno, junto con por
// qué no se elimina. El botón dice de qué piso es: "Eliminar Planta baja de
// la nube".
//
// Sólo muestra y avisa el toque: la carga y el borrado los hace la pantalla.
// Así se puede probar sin la nube.

/// La tarjeta de un mapa publicado, en la pantalla del administrador.
class TarjetaMapaAdmin extends StatelessWidget {
  const TarjetaMapaAdmin({
    super.key,
    required this.mapa,
    required this.propio,
    required this.alEliminar,
    this.eliminando = false,
    this.urlImagen,
  });

  final MapaPublicadoResumen mapa;

  /// Si lo publicó la cuenta con la que se entró: sólo esos se eliminan.
  final bool propio;

  /// Si se está eliminando (va "Eliminando…" en lugar del botón).
  final bool eliminando;

  /// La imagen del plano en la nube, para la miniatura. null: un ícono.
  final String? urlImagen;

  final VoidCallback alEliminar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final beacons = mapa.numBeacons;
    final calibraciones = mapa.numCalibraciones;
    final gris = TipografiaApp.subtitulo.copyWith(color: e.textoSecundario);
    final datos = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Miniatura(url: urlImagen),
        const SizedBox(width: EspaciadoApp.medio),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mapa.edificioNombre, style: gris),
              const SizedBox(height: EspaciadoApp.minimo),
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
                style: gris,
              ),
              if (propio) ...[
                const SizedBox(height: EspaciadoApp.chico),
                const ChipApp(texto: 'Tuyo', icono: Icons.person_rounded),
              ],
            ],
          ),
        ),
      ],
    );
    return PanelRelieve(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                datos,
                if (!propio) ...[
                  const SizedBox(height: EspaciadoApp.medio),
                  _SinPermiso(estilo: gris, color: e.textoSecundario),
                ],
              ],
            ),
          ),
          if (propio) ...[
            // Más aire que el alcance de la luz del botón: ninguna sombra cae
            // sobre el texto del chip.
            const SizedBox(height: EspaciadoApp.margenLateral),
            if (eliminando)
              _EnCurso(
                texto: 'Eliminando…',
                etiqueta: 'Eliminando ${mapa.pisoNombre} de la nube',
              )
            else
              FilaBotones(
                children: [
                  BotonSecundario(
                    texto: 'Eliminar',
                    icono: Icons.delete_rounded,
                    destructivo: true,
                    etiquetaSemantica: 'Eliminar ${mapa.pisoNombre} de la nube',
                    alPresionar: alEliminar,
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// En un mapa de otro administrador, por qué no se puede eliminar: el
/// candado (decorativo) y el texto, en gris.
class _SinPermiso extends StatelessWidget {
  const _SinPermiso({required this.estilo, required this.color});

  final TextStyle estilo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // El candado, centrado en el primer renglón, crezca o no la letra.
    final renglon =
        MediaQuery.textScalerOf(context).scale(estilo.fontSize!) *
        estilo.height!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: (renglon - FormasApp.iconoChico).clamp(0, double.infinity) / 2,
          ),
          child: ExcludeSemantics(
            child: Icon(
              Icons.lock_rounded,
              size: FormasApp.iconoChico,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: EspaciadoApp.chico),
        Expanded(
          child: Text(
            'Sólo lo puede eliminar quien lo publicó.',
            style: estilo,
          ),
        ),
      ],
    );
  }
}

/// La miniatura del plano: un cuadro hundido con la imagen de la nube (la
/// misma de antes, achicada en memoria) o, mientras llega (o si no llega), el
/// ícono de un mapa, sin nada que gire. Decorativa.
class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final url = this.url;
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
          child: url == null
              ? icono
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: 112,
                  gaplessPlayback: true,
                  // El ícono hasta que el plano se puede mostrar (antes, una
                  // ruedita mientras llegaba, y nada hasta el primer dato).
                  frameBuilder: (context, child, cuadro, sincronico) =>
                      cuadro == null ? icono : child,
                  errorBuilder: (context, error, stack) => icono,
                ),
        ),
      ),
    );
  }
}

/// Lo que va en lugar de "Eliminar" mientras se elimina un mapa: un recuadro
/// hundido del alto de un botón, quieto, con [texto]. TalkBack dice
/// [etiqueta] al aparecer.
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
