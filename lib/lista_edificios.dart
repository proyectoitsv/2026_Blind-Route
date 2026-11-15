import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ajustes_navegacion.dart';
import 'database.dart';
import 'design/design.dart';
import 'lista_pisos.dart';
import 'pantalla_login_admin.dart';
import 'pantalla_mapas_admin.dart';
import 'supabase_config.dart';
import 'supabase_service.dart';

/// Edificios cargados en este teléfono (app del administrador): la pantalla
/// a la que se llega después del login. Tocar un edificio abre sus pisos.
///
/// ─── Sistema de diseño (fase 5.4 del rediseño) ───
/// Va envuelta en AmbienteDiseno. Arriba, la barra con "Mapas publicados en
/// la nube" y "Cerrar sesión" (con la nube configurada); cada edificio es una
/// TarjetaLista y, abajo, "Agregar edificio" es el botón principal (antes, un
/// botón flotante con un "+" sin nombre para TalkBack).
///
/// Un edificio se sigue eliminando deslizándolo hacia la izquierda, con la
/// misma confirmación, ahora en una hoja (mostrarConfirmacion). Con TalkBack,
/// que no deja deslizar, la tarjeta tiene la acción "Eliminar", que hace lo
/// mismo; por eso TalkBack no lee "Deslizá para eliminar". "Nuevo edificio"
/// es una hoja con el nombre (CampoTexto): si se guarda vacío, lo dice
/// debajo del campo (antes no pasaba nada). Los avisos son los del sistema de
/// diseño (mostrarAviso).
///
/// Cada tarjeta tiene un lápiz ("Cambiar nombre de…", con el nombre del
/// edificio), que abre la misma hoja con el nombre puesto. Ni al cargar ni al cambiar se acepta un
/// nombre repetido (ver "UN NOMBRE, UN EDIFICIO" en DatabaseHelper).
///
/// Hasta que se lee la base no se muestra nada: si no, "No hay edificios
/// registrados" se vería (y TalkBack lo anunciaría) mientras se lee.
class ListaEdificios extends StatefulWidget {
  const ListaEdificios({super.key});

  @override
  State<ListaEdificios> createState() => _ListaEdificiosState();
}

class _ListaEdificiosState extends State<ListaEdificios> {
  List<Map<String, dynamic>> _edificios = [];

  /// Si ya se leyó la base una vez.
  bool _leida = false;

  @override
  void initState() {
    super.initState();
    _refrescarEdificios();
  }

  void _refrescarEdificios() async {
    final datos = await DatabaseHelper.instance.obtenerEdificios();
    if (mounted) {
      setState(() {
        _edificios = datos;
        _leida = true;
      });
    }
  }

  Future<bool> _confirmarBorradoEdificio(String nombre) => mostrarConfirmacion(
    context,
    titulo: '¿Eliminar edificio?',
    mensaje:
        'Se eliminará "$nombre", incluyendo todos sus pisos y beacons. Esta '
        'acción es permanente.',
    confirmar: 'Eliminar todo',
    destructiva: true,
    iconoConfirmar: Icons.delete_rounded,
  );

  /// Pide confirmar y elimina el edificio. Devuelve si se eliminó. Lo usan
  /// deslizar la tarjeta y la acción "Eliminar" de TalkBack.
  Future<bool> _eliminarEdificio(Map<String, dynamic> edificio) async {
    final confirmado = await _confirmarBorradoEdificio(edificio['nombre']);
    if (confirmado != true) return false;

    // Un edificio arrastra a sus pisos. Antes de borrarlo, se quitan de la
    // nube todos sus mapas publicados. Si alguno falla (offline o de otro
    // dueño), se aborta y no se borra nada local, para no dejar mapas
    // huérfanos.
    if (SupabaseService.instance.configurado) {
      final remoteIds = await DatabaseHelper.instance
          .obtenerRemoteIdsDeEdificio(edificio['id']);
      for (final remoteId in remoteIds) {
        try {
          await SupabaseService.instance.eliminarMapa(remoteId);
        } catch (e) {
          if (!mounted) return false;
          _avisar(
            'No se pudo quitar un mapa de la nube: $e\nNo se eliminó el '
            'edificio.',
            error: true,
          );
          return false;
        }
      }
    }

    await DatabaseHelper.instance.eliminarEdificioCompleto(edificio['id']);
    if (!mounted) return true;
    _avisar("Se eliminó ${edificio['nombre']} y todos sus datos");
    return true;
  }

  /// La tarjeta del edificio eliminado sale de la lista enseguida (si se
  /// deslizó, ya se fue y no puede volver a armarse) y la lista se vuelve a
  /// leer.
  void _sacarDeLaLista(Map<String, dynamic> edificio) {
    setState(() {
      _edificios = [
        for (final otro in _edificios)
          if (otro['id'] != edificio['id']) otro,
      ];
    });
    _refrescarEdificios();
  }

  Future<void> _agregarEdificio() => mostrarHoja<void>(
    context,
    titulo: 'Nuevo edificio',
    // Lo cierra "Cancelar" (o volver, o tocar afuera).
    botonCerrar: false,
    contenido: (context) => _NuevoEdificio(alGuardar: _crearEdificio),
  );

  /// Guarda el edificio, si su nombre no está repetido. Devuelve null si lo
  /// guardó, o lo que hay que decir debajo del campo si no.
  ///
  /// Dos edificios con el mismo nombre se mezclan (ver "UN NOMBRE, UN
  /// EDIFICIO" en DatabaseHelper): no se acepta uno que ya esté en este
  /// teléfono ni uno que ya haya publicado otro administrador. Lo segundo
  /// sólo se puede saber con conexión; sin ella se guarda igual y se vuelve
  /// a revisar al publicar el primer piso.
  Future<String?> _crearEdificio(String nombre) async {
    if (await DatabaseHelper.instance.existeEdificioConNombre(nombre)) {
      return 'Ya hay un edificio con ese nombre.';
    }
    if (SupabaseService.instance.configurado) {
      try {
        if (await SupabaseService.instance.nombreDeEdificioDeOtroAdmin(
          nombre,
        )) {
          return 'Otro administrador ya publicó un edificio con ese nombre. '
              'Elegí otro.';
        }
      } catch (e) {
        debugPrint('[Edificios] No se pudo revisar el nombre en la nube: $e');
      }
    }
    await DatabaseHelper.instance.crearEdificio(nombre);
    _refrescarEdificios();
    return null;
  }

  // ── CAMBIAR EL NOMBRE DE UN EDIFICIO ──────────────────────────────────────
  //
  // Hace falta porque el nombre no se puede repetir: si otro administrador
  // ya publicó un edificio con el mismo, la publicación se rechaza, y sin
  // esto la única salida era cargar el edificio de nuevo.
  //
  // El nombre es lo que identifica al edificio en la nube, así que no
  // alcanza con cambiarlo en el teléfono: también se cambia en sus pisos ya
  // publicados (todos juntos) y en sus ajustes de navegación. Si el edificio
  // tiene pisos publicados y la nube no contesta, no se cambia nada: con el
  // nombre cambiado a medias, el usuario vería dos edificios.

  Future<void> _cambiarNombre(Map<String, dynamic> edificio) =>
      mostrarHoja<void>(
        context,
        titulo: 'Cambiar nombre',
        // Lo cierra "Cancelar" (o volver, o tocar afuera).
        botonCerrar: false,
        contenido: (context) => _NuevoEdificio(
          nombreInicial: edificio['nombre'] as String,
          alGuardar: (nombre) => _renombrarEdificio(edificio, nombre),
        ),
      );

  /// Cambia el nombre de [edificio] a [nuevo]. Devuelve null si quedó
  /// cambiado (o era el mismo), o lo que hay que decir debajo del campo.
  Future<String?> _renombrarEdificio(
    Map<String, dynamic> edificio,
    String nuevo,
  ) async {
    final id = edificio['id'] as int;
    final viejo = edificio['nombre'] as String;
    if (nuevo == viejo) return null;
    final base = DatabaseHelper.instance;
    if (await base.existeEdificioConNombre(nuevo, salvoId: id)) {
      return 'Ya hay un edificio con ese nombre.';
    }

    final publicados = await base.obtenerRemoteIdsDeEdificio(id);
    final nube = SupabaseService.instance;
    var enNube = false;
    if (nube.configurado) {
      try {
        if (await nube.nombreDeEdificioDeOtroAdmin(nuevo)) {
          return 'Otro administrador ya publicó un edificio con ese nombre. '
              'Elegí otro.';
        }
        await nube.renombrarEdificioPublicado(
          nuevo: nuevo,
          remoteIds: publicados,
        );
        enNube = true;
      } catch (e) {
        debugPrint('[Edificios] No se pudo cambiar el nombre en la nube: $e');
        if (publicados.isNotEmpty) {
          return 'No se pudo cambiar el nombre en los mapas publicados. '
              'Revisá la conexión y probá de nuevo.';
        }
        // Sin pisos publicados no hay nada que cambiar en la nube: el nombre
        // se vuelve a revisar al publicar el primero.
      }
    }

    // Los ajustes de navegación del edificio, que la nube guarda con su
    // nombre. Si no se pueden copiar, quedan pendientes en el teléfono.
    var ajustesEnNube = false;
    if (enNube) {
      try {
        ajustesEnNube = await nube.copiarAjustesDeEdificio(viejo, nuevo);
      } catch (e) {
        debugPrint('[Edificios] No se pudieron copiar los ajustes: $e');
      }
    }

    await base.renombrarEdificio(id, nuevo);
    await AjustesNavegacion.instancia.renombrarEdificio(
      viejo,
      nuevo,
      copiadoEnNube: ajustesEnNube,
    );
    _refrescarEdificios();
    _avisar(
      publicados.isEmpty
          ? 'Nombre cambiado.'
          : 'Nombre cambiado, también en los mapas publicados.',
    );
    return null;
  }

  void _abrirPisos(Map<String, dynamic> edificio) {
    Navigator.push(
      context,
      RutaApp<void>(
        builder: (context) => ListaPisos(
          edificioId: edificio['id'],
          nombreEdificio: edificio['nombre'],
        ),
      ),
    );
  }

  void _abrirMapasPublicados() {
    Navigator.push(
      context,
      RutaApp<void>(builder: (_) => const PantallaMapasAdmin()),
    );
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      RutaApp<void>(builder: (_) => const PantallaLoginAdmin()),
    );
  }

  void _avisar(String msg, {bool error = false}) {
    if (!mounted) return;
    mostrarAviso(context, msg, error: error);
  }

  @override
  Widget build(BuildContext context) {
    return AmbienteDiseno(
      child: Builder(
        builder: (context) {
          final e = EstiloApp.de(context);
          return Scaffold(
            backgroundColor: e.fondo,
            appBar: BarraSuperior(
              titulo: 'Blind Route — Edificios',
              acciones: [
                if (SupabaseConfig.configurado)
                  AccionBarra(
                    icono: Icons.cloud_rounded,
                    etiqueta: 'Mapas publicados en la nube',
                    alPresionar: _abrirMapasPublicados,
                  ),
                if (SupabaseConfig.configurado)
                  AccionBarra(
                    icono: Icons.logout_rounded,
                    etiqueta: 'Cerrar sesión',
                    alPresionar: _cerrarSesion,
                  ),
              ],
            ),
            body: SafeArea(top: false, bottom: false, child: _cuerpo()),
            bottomNavigationBar: _BarraAgregar(
              texto: 'Agregar edificio',
              icono: Icons.add_rounded,
              alPresionar: _agregarEdificio,
            ),
          );
        },
      ),
    );
  }

  Widget _cuerpo() {
    // Mientras se lee la base (un instante), el fondo vacío.
    if (!_leida) return const SizedBox.shrink();
    if (_edificios.isEmpty) {
      // En el medio; si con letra grande no entra, se desplaza.
      return const CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EstadoPantalla(
                icono: Icons.business_rounded,
                titulo: 'No hay edificios registrados',
                detalle: 'Tocá «Agregar edificio» para cargar el primero.',
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(EspaciadoApp.margenLateral),
      itemCount: _edificios.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: EspaciadoApp.entreTarjetas),
      itemBuilder: (context, i) {
        final edificio = _edificios[i];
        final nombre = edificio['nombre'] as String;
        return TarjetaLista(
          key: ValueKey<Object?>(edificio['id']),
          icono: Icons.business_rounded,
          titulo: nombre,
          subtitulo: 'Deslizá para eliminar',
          // Con TalkBack no se desliza: está la acción "Eliminar".
          etiquetaSemantica: nombre,
          acciones: [
            BotonRedondo(
              icono: Icons.edit_rounded,
              etiqueta: 'Cambiar nombre de $nombre',
              alPresionar: () => _cambiarNombre(edificio),
            ),
          ],
          alTocar: () => _abrirPisos(edificio),
          alEliminar: () => _eliminarEdificio(edificio),
          alEliminada: () => _sacarDeLaLista(edificio),
        );
      },
    );
  }
}

/// El botón principal de la pantalla, abajo, sobre el fondo: lo que antes
/// era el botón flotante.
class _BarraAgregar extends StatelessWidget {
  const _BarraAgregar({
    required this.texto,
    required this.icono,
    required this.alPresionar,
  });

  final String texto;
  final IconData icono;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EspaciadoApp.margenLateral,
          EspaciadoApp.medio,
          EspaciadoApp.margenLateral,
          EspaciadoApp.margenLateral,
        ),
        child: BotonPrincipal(
          texto: texto,
          icono: icono,
          alPresionar: alPresionar,
        ),
      ),
    );
  }
}

/// Lo que va en las hojas "Nuevo edificio" y "Cambiar nombre": el nombre,
/// "Cancelar" y "Guardar". Si se guarda vacío, o con un nombre que ya
/// existe, lo dice debajo del campo. Mientras guarda, el campo y "Guardar"
/// se deshabilitan: dos toques no cargan dos edificios.
class _NuevoEdificio extends StatefulWidget {
  const _NuevoEdificio({required this.alGuardar, this.nombreInicial});

  /// El nombre que tiene el edificio, al cambiarlo. null: un edificio nuevo.
  final String? nombreInicial;

  /// Guarda el edificio y vuelve a leer la lista. Devuelve null si lo
  /// guardó, o por qué no (va debajo del campo).
  final Future<String?> Function(String nombre) alGuardar;

  @override
  State<_NuevoEdificio> createState() => _NuevoEdificioState();
}

class _NuevoEdificioState extends State<_NuevoEdificio> {
  late final TextEditingController _nombre = TextEditingController(
    text: widget.nombreInicial,
  );
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    // Sin espacios a los costados (un nombre sólo de espacios es vacío).
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Escribí el nombre del edificio.');
      return;
    }
    setState(() => _guardando = true);
    final error = await widget.alGuardar(nombre);
    if (!mounted) return;
    if (error != null) {
      // No se guardó (el nombre ya existe): la hoja queda abierta para
      // corregirlo.
      setState(() {
        _guardando = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoTexto(
          etiqueta: 'Nombre',
          ayuda: 'Por ejemplo, Facultad de Ingeniería',
          controlador: _nombre,
          capitalizacion: TextCapitalization.sentences,
          accionTeclado: TextInputAction.done,
          habilitado: !_guardando,
          error: _error,
          // Escribir le borra el error.
          alCambiar: (_) {
            if (_error != null) setState(() => _error = null);
          },
          // "Listo": guarda.
          alEnviar: (_) => _guardando ? null : _guardar(),
        ),
        // Más aire que el alcance de la luz de los botones: ninguna sombra
        // cae sobre el error.
        const SizedBox(height: EspaciadoApp.entreSecciones),
        FilaBotones(
          children: [
            BotonSecundario(
              texto: 'Cancelar',
              alPresionar: () => Navigator.of(context).pop(),
            ),
            BotonPrincipal(
              texto: 'Guardar',
              expandido: false,
              alPresionar: _guardando ? null : _guardar,
            ),
          ],
        ),
      ],
    );
  }
}
