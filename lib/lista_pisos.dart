import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'database.dart';
import 'design/design.dart';
import 'pantalla_config.dart';
import 'pantalla_naveg.dart';
import 'piso_util.dart';
import 'supabase_service.dart';

/// Pisos de un edificio (app del administrador). Tocar un piso abre su
/// configuración.
///
/// ─── Sistema de diseño (fase 5.4 del rediseño) ───
/// Va envuelta en AmbienteDiseno. Cada piso es una TarjetaLista con dos
/// botones redondos aparte, "Probar navegación" y "Cambiar número" (el
/// lápiz), que TalkBack nombra con el piso ("Probar navegación en Planta
/// baja"). Un piso sin número lo dice en ámbar debajo del nombre. Abajo,
/// "Agregar piso" es el botón principal (antes, un botón flotante sin nombre
/// para TalkBack).
///
/// El número se elige en una hoja (antes, un diálogo) con un botón por piso:
/// los ya cargados, deshabilitados ("ya cargado"), y el del piso que se está
/// cambiando, en acento ("el actual"). Un piso se sigue eliminando
/// deslizándolo, con la misma confirmación en una hoja; con TalkBack, con la
/// acción "Eliminar" de la tarjeta. Los avisos son los del sistema de diseño
/// (mostrarAviso).
class ListaPisos extends StatefulWidget {
  final int edificioId;
  final String nombreEdificio;

  const ListaPisos({
    super.key,
    required this.edificioId,
    required this.nombreEdificio,
  });

  @override
  State<ListaPisos> createState() => _ListaPisosState();
}

class _ListaPisosState extends State<ListaPisos> {
  List<Map<String, dynamic>> _pisos = [];

  /// Si ya se leyó la base una vez: antes, "No hay pisos agregados" se vería
  /// (y TalkBack lo anunciaría) mientras se lee.
  bool _leida = false;

  @override
  void initState() {
    super.initState();
    _refrescarPisos();
  }

  void _refrescarPisos() async {
    final datos = await DatabaseHelper.instance.obtenerPisosPorEdificio(
      widget.edificioId,
    );
    if (mounted) {
      setState(() {
        _pisos = datos;
        _leida = true;
      });
    }
  }

  /// Abre la pantalla de navegación del usuario sobre este piso. Es donde el
  /// admin regula los ajustes de navegación del edificio (botón de ajustes,
  /// arriba a la derecha): hay que caminar para saber si andan.
  void _probarNavegacion(Map<String, dynamic> piso) {
    Navigator.push(
      context,
      RutaApp<void>(
        builder: (context) => PantallaNavegacion(
          pisoId: piso['id'],
          rutaImagen: piso['ruta_imagen'],
          escalaX: (piso['escala_metros'] as num?)?.toDouble() ?? 50,
          escalaY: (piso['escala_metros_alto'] as num?)?.toDouble() ?? 50,
          tamCeldaMetros: (piso['tam_celda_metros'] as num?)?.toDouble() ?? 1.0,
          rotacionMapa: (piso['rotacion_mapa'] as num?)?.toDouble() ?? 0.0,
        ),
      ),
    );
  }

  void _abrirConfiguracion(Map<String, dynamic> piso) {
    Navigator.push(
      context,
      RutaApp<void>(
        builder: (context) => PantallaConfiguracion(
          pisoId: piso['id'],
          rutaImagen: piso['ruta_imagen'],
          escalaX: (piso['escala_metros'] as num?)?.toDouble() ?? 50,
          escalaY: (piso['escala_metros_alto'] as num?)?.toDouble() ?? 50,
          tamCeldaMetros: (piso['tam_celda_metros'] as num?)?.toDouble() ?? 1.0,
        ),
      ),
    );
  }

  Future<bool> _confirmarBorrado(String nombre) => mostrarConfirmacion(
    context,
    titulo: '¿Eliminar piso?',
    mensaje: 'Esto borrará "$nombre" y todos sus beacons configurados.',
    confirmar: 'Eliminar',
    destructiva: true,
    iconoConfirmar: Icons.delete_rounded,
  );

  /// Selector de número de piso. Sólo se puede elegir un número (no se
  /// escribe un nombre libre) y no se ofrecen los ya usados en el edificio.
  /// [actual] es el número del piso que se está editando (se permite
  /// re-elegirlo). Devuelve null si se cancela.
  Future<int?> _elegirNumeroPiso({int? actual}) async {
    final ocupados = await DatabaseHelper.instance.obtenerNumerosPisoOcupados(
      widget.edificioId,
    );
    if (actual != null) ocupados.remove(actual);
    if (!mounted) return null;

    final numeros = [
      for (int n = PisoUtil.minimo; n <= PisoUtil.maximo; n++) n,
    ];

    return mostrarHoja<int>(
      context,
      titulo: actual == null ? '¿Qué piso es?' : 'Cambiar número de piso',
      contenido: (context) =>
          _SelectorNumero(numeros: numeros, ocupados: ocupados, actual: actual),
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
    await DatabaseHelper.instance.actualizarNumeroPiso(
      piso['id'] as int,
      numero,
    );
    _refrescarPisos();
    if (!mounted) return;
    if (piso['remote_id'] != null) {
      _avisar(
        'Número actualizado. Volvé a publicar el piso para que llegue a los '
        'usuarios.',
      );
    }
  }

  /// Pide confirmar y elimina el piso. Devuelve si se eliminó. Lo usan
  /// deslizar la tarjeta y la acción "Eliminar" de TalkBack.
  Future<bool> _eliminarPiso(Map<String, dynamic> piso) async {
    final confirmado = await _confirmarBorrado(piso['nombre_piso']);
    if (confirmado != true) return false;

    // Si el piso está publicado, primero se quita de la nube. Si eso falla
    // (offline o no sos el dueño), NO se borra localmente, para no dejar el
    // mapa huérfano en la nube.
    final remoteId = piso['remote_id'] as String?;
    if (remoteId != null && SupabaseService.instance.configurado) {
      try {
        await SupabaseService.instance.eliminarMapa(remoteId);
      } catch (e) {
        if (!mounted) return false;
        _avisar(
          'No se pudo quitar de la nube: $e\nNo se eliminó el piso.',
          error: true,
        );
        return false;
      }
    }

    await DatabaseHelper.instance.eliminarPiso(piso['id']);
    if (!mounted) return true;
    _avisar("${piso['nombre_piso']} eliminado");
    return true;
  }

  /// La tarjeta del piso eliminado sale de la lista enseguida (si se
  /// deslizó, ya se fue y no puede volver a armarse) y la lista se vuelve a
  /// leer.
  void _sacarDeLaLista(Map<String, dynamic> piso) {
    setState(() {
      _pisos = [
        for (final otro in _pisos)
          if (otro['id'] != piso['id']) otro,
      ];
    });
    _refrescarPisos();
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
            appBar: BarraSuperior(titulo: widget.nombreEdificio),
            body: SafeArea(top: false, bottom: false, child: _cuerpo()),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  EspaciadoApp.margenLateral,
                  EspaciadoApp.medio,
                  EspaciadoApp.margenLateral,
                  EspaciadoApp.margenLateral,
                ),
                child: BotonPrincipal(
                  texto: 'Agregar piso',
                  icono: Icons.add_photo_alternate_rounded,
                  alPresionar: _agregarPiso,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cuerpo() {
    // Mientras se lee la base (un instante), el fondo vacío.
    if (!_leida) return const SizedBox.shrink();
    if (_pisos.isEmpty) {
      // En el medio; si con letra grande no entra, se desplaza.
      return const CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EstadoPantalla(
                icono: Icons.layers_rounded,
                titulo: 'No hay pisos agregados',
                detalle: 'Tocá «Agregar piso» para cargar la imagen del plano.',
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(EspaciadoApp.margenLateral),
      itemCount: _pisos.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: EspaciadoApp.entreTarjetas),
      itemBuilder: (context, i) => _tarjetaPiso(_pisos[i]),
    );
  }

  Widget _tarjetaPiso(Map<String, dynamic> piso) {
    final numero = piso['numero_piso'] as int?;
    final nombre = numero != null
        ? PisoUtil.nombre(numero)
        : piso['nombre_piso'] as String;
    return TarjetaLista(
      key: ValueKey<Object?>(piso['id']),
      icono: Icons.layers_rounded,
      titulo: nombre,
      subtitulo: numero == null
          ? 'Sin número de piso: tocá el lápiz para asignarlo'
          : 'Deslizá para eliminar',
      tonoSubtitulo: numero == null ? TonoDato.advertencia : TonoDato.neutro,
      // Con TalkBack no se desliza (está la acción "Eliminar") y el lápiz es
      // el botón "Cambiar número", que viene después.
      etiquetaSemantica: numero == null
          ? '$nombre, sin número de piso'
          : nombre,
      acciones: [
        // Navegar este piso como lo haría el usuario, con el panel de
        // ajustes: los filtros se regulan caminando, no desde un formulario.
        BotonRedondo(
          icono: Icons.navigation_rounded,
          etiqueta: 'Probar navegación en $nombre',
          alPresionar: () => _probarNavegacion(piso),
        ),
        BotonRedondo(
          icono: Icons.edit_rounded,
          etiqueta: 'Cambiar número de $nombre',
          alPresionar: () => _cambiarNumero(piso),
        ),
      ],
      alTocar: () => _abrirConfiguracion(piso),
      alEliminar: () => _eliminarPiso(piso),
      alEliminada: () => _sacarDeLaLista(piso),
    );
  }
}

/// Lo que va en la hoja del número de piso: un botón por piso, en orden
/// (de los subsuelos al 20). Los ya cargados en el edificio, deshabilitados;
/// el del piso que se está cambiando, en acento. Cada uno lo nombra entero
/// para TalkBack ("Subsuelo 1", "Piso 2, ya cargado", "Planta baja, el
/// actual"). Elegir uno cierra la hoja con su número.
///
/// Van en una grilla pareja: todos del mismo ancho, tantos por renglón como
/// entren con el número más ancho en un renglón (con la letra del teléfono),
/// y cada renglón de punta a punta. Cinco por renglón en un teléfono de
/// 360 dp; con la letra al 200 %, cuatro.
class _SelectorNumero extends StatelessWidget {
  const _SelectorNumero({
    required this.numeros,
    required this.ocupados,
    required this.actual,
  });

  final List<int> numeros;
  final Set<int> ocupados;
  final int? actual;

  /// Ancho mínimo de cada botón: casi cuadrados (52 de alto).
  static const double _anchoMinimo = 56;

  /// Entre botón y botón, 12: la luz de uno no llega al texto del de al lado.
  static const double _separacion = EspaciadoApp.medio;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PB = planta baja · S = subsuelo',
          semanticsLabel: 'PB es planta baja y S, subsuelo.',
          style: TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
        ),
        // Más aire que el alcance de la luz de los botones: ninguna sombra
        // cae sobre el texto.
        const SizedBox(height: EspaciadoApp.entreSecciones),
        LayoutBuilder(
          builder: (context, limites) {
            final ancho = _anchoBoton(context, limites.maxWidth);
            return Wrap(
              spacing: _separacion,
              runSpacing: _separacion,
              children: [
                for (final n in numeros)
                  SizedBox(width: ancho, child: _boton(context, n)),
              ],
            );
          },
        ),
      ],
    );
  }

  /// El ancho de cada botón para que entren parejos en [disponible]: el del
  /// número más ancho, con la letra del teléfono y el relleno del botón (o
  /// el mínimo), estirado hasta llenar el renglón.
  double _anchoBoton(BuildContext context, double disponible) {
    final escala = MediaQuery.textScalerOf(context);
    var texto = 0.0;
    for (final n in numeros) {
      final medida = TextPainter(
        text: TextSpan(
          text: PisoUtil.etiquetaCorta(n),
          style: TipografiaApp.boton,
        ),
        textScaler: escala,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      texto = math.max(texto, medida.width);
      medida.dispose();
    }
    final minimo = math.max(
      _anchoMinimo,
      texto.ceilToDouble() + 2 * EspaciadoApp.rellenoTarjeta,
    );
    final columnas = math.max(
      1,
      ((disponible + _separacion) / (minimo + _separacion)).floor(),
    );
    // Un pelo menos: con el redondeo, el último del renglón no pasa al
    // siguiente.
    return (disponible - _separacion * (columnas - 1)) / columnas - 0.01;
  }

  Widget _boton(BuildContext context, int n) {
    final nombre = PisoUtil.nombre(n);
    final texto = PisoUtil.etiquetaCorta(n);
    void elegir() => Navigator.of(context).pop(n);
    final Widget boton;
    if (ocupados.contains(n)) {
      boton = BotonSecundario(
        texto: texto,
        etiquetaSemantica: '$nombre, ya cargado',
        alPresionar: null,
      );
    } else if (n == actual) {
      boton = BotonPrincipal(
        texto: texto,
        etiquetaSemantica: '$nombre, el actual',
        expandido: false,
        alPresionar: elegir,
      );
    } else {
      boton = BotonSecundario(
        texto: texto,
        etiquetaSemantica: nombre,
        alPresionar: elegir,
      );
    }
    return boton;
  }
}
