import 'package:flutter/material.dart';

import 'buscador_lugares.dart';
import 'database.dart';
import 'design/design.dart';
import 'rubros.dart';

/// Ícono de un rubro. Los de fábrica tienen el suyo; los creados por el admin
/// llevan uno genérico.
IconData iconoRubro(String? id) {
  switch (id) {
    case 'comida':
      return Icons.restaurant_rounded;
    case 'cafe':
      return Icons.local_cafe_rounded;
    case Rubros.bano:
      return Icons.wc_rounded;
    case 'kiosco':
      return Icons.storefront_rounded;
    case 'tienda':
      return Icons.shopping_bag_rounded;
    case 'salud':
      return Icons.local_pharmacy_rounded;
    case 'cajero':
      return Icons.atm_rounded;
    case 'informacion':
      return Icons.info_outline_rounded;
    case 'oficina':
      return Icons.work_outline_rounded;
    case 'aula':
      return Icons.school_rounded;
    case 'laboratorio':
      return Icons.science_rounded;
    case 'biblioteca':
      return Icons.local_library_rounded;
    case 'salida':
      return Icons.door_front_door_rounded;
    case 'descanso':
      return Icons.event_seat_rounded;
    case 'deporte':
      return Icons.sports_soccer_rounded;
    case 'capilla':
      return Icons.church_rounded;
    case 'estacionamiento':
      return Icons.local_parking_rounded;
    case 'transporte':
      return Icons.directions_bus_rounded;
    default:
      return Icons.sell_rounded;
  }
}

/// Administración del catálogo de rubros de este teléfono: crear rubros
/// propios, cambiar el nombre y las palabras de uno existente, y borrarlos.
///
/// Los cambios valen enseguida para los lugares de este teléfono, pero a los
/// usuarios les llegan recién al REPUBLICAR el mapa: cada lugar publicado
/// lleva una copia de las palabras de su rubro (ver rubros.dart).
///
/// ─── Sistema de diseño (fase 5.6 del rediseño) ───
/// Va envuelta en AmbienteDiseno, como la configuración del piso desde la
/// que se abre. Cada rubro es una TarjetaLista (el ícono en su cuadro, el
/// nombre y algunas de sus palabras) y "Nuevo rubro", el botón principal
/// abajo (antes, un botón flotante). El editor sigue a pantalla completa:
/// "Guardar" va en la barra, las palabras son chips con su botón para
/// quitarlas, la confirmación es una hoja (mostrarConfirmacion) y los avisos
/// son los del sistema de diseño (mostrarAviso).
class PantallaRubros extends StatefulWidget {
  const PantallaRubros({super.key});

  @override
  State<PantallaRubros> createState() => _PantallaRubrosState();
}

class _PantallaRubrosState extends State<PantallaRubros> {
  /// Cuántas palabras se muestran antes del "y N más".
  static const int _muestra = 5;

  /// Abre el editor ([rubro] null = rubro nuevo). Al volver, si hubo cambios,
  /// rearma la lista y avisa qué pasó.
  Future<void> _abrirEditor([Rubro? rubro]) async {
    final aviso = await Navigator.push<String>(
      context,
      RutaApp<String>(builder: (_) => _EditorRubro(inicial: rubro)),
    );
    if (aviso == null || !mounted) return;
    setState(() {});
    mostrarAviso(context, aviso);
  }

  /// Algunas palabras del rubro, para la tarjeta.
  static String _palabras(Rubro r) {
    final resto = r.palabras.length - _muestra;
    final muestra = r.palabras.take(_muestra).join(', ');
    return resto > 0 ? '$muestra y $resto más' : muestra;
  }

  @override
  Widget build(BuildContext context) {
    return AmbienteDiseno(
      child: Builder(
        builder: (context) {
          final e = EstiloApp.de(context);
          final rubros = Rubros.todos;
          return Scaffold(
            backgroundColor: e.fondo,
            appBar: const BarraSuperior(titulo: 'Rubros'),
            body: SafeArea(
              top: false,
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.all(EspaciadoApp.margenLateral),
                children: [
                  Text(
                    'Las palabras de cada rubro sirven para pedir sus lugares '
                    'por voz. Los cambios llegan al volver a publicar el mapa.',
                    style: TipografiaApp.subtitulo.copyWith(
                      color: e.textoSecundario,
                    ),
                  ),
                  // Más aire que el alcance de la luz de las tarjetas.
                  const SizedBox(height: EspaciadoApp.entreSecciones),
                  for (final (i, r) in rubros.indexed) ...[
                    if (i > 0)
                      const SizedBox(height: EspaciadoApp.entreTarjetas),
                    TarjetaLista(
                      icono: iconoRubro(r.id),
                      titulo: r.nombre,
                      subtitulo: _palabras(r),
                      alTocar: () => _abrirEditor(r),
                    ),
                  ],
                ],
              ),
            ),
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
                  texto: 'Nuevo rubro',
                  icono: Icons.add_rounded,
                  alPresionar: () => _abrirEditor(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Editor ──────────────────────────────────────────────────────────────────

/// Alta y edición de un rubro, a pantalla completa: nombre y palabras. Las
/// palabras se agregan de a una (o varias pegadas con comas) y se quitan con
/// el botón de su chip. Si se edita uno que se puede borrar, abajo está el
/// botón para borrarlo.
///
/// Guarda o borra por su cuenta y, si hubo cambios, cierra devolviendo el
/// texto del aviso para la lista.
class _EditorRubro extends StatefulWidget {
  /// Rubro que se está editando. Null = alta de uno nuevo.
  final Rubro? inicial;

  const _EditorRubro({this.inicial});

  @override
  State<_EditorRubro> createState() => _EditorRubroState();
}

class _EditorRubroState extends State<_EditorRubro> {
  final _nombreCtrl = TextEditingController();
  final _palabraCtrl = TextEditingController();
  final _palabraFoco = FocusNode();
  final List<String> _palabras = [];
  bool _ocupado = false;

  bool get _editando => widget.inicial != null;

  @override
  void initState() {
    super.initState();
    final r = widget.inicial;
    if (r == null) return;
    _nombreCtrl.text = r.nombre;
    _palabras.addAll(r.palabras);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _palabraCtrl.dispose();
    _palabraFoco.dispose();
    super.dispose();
  }

  /// Suma lo escrito a [_palabras] (separado por comas o punto y coma). Las
  /// que ya están, aunque cambien tildes o mayúsculas, no se repiten: el
  /// buscador las trataría igual.
  void _sumar(String texto) {
    final yaEstan = _palabras.map(BuscadorLugares.normalizar).toSet();
    for (final parte in texto.split(RegExp(r'[,;\n]'))) {
      final p = parte.trim();
      if (p.isEmpty) continue;
      if (yaEstan.add(BuscadorLugares.normalizar(p))) _palabras.add(p);
    }
  }

  /// Agrega lo que hay en el campo y lo deja listo para la siguiente.
  void _agregar(String texto) {
    setState(() {
      _sumar(texto);
      _palabraCtrl.clear();
    });
    _palabraFoco.requestFocus();
  }

  /// Al escribir una coma se agrega lo que había antes, y lo que sigue queda
  /// en el campo. Así se puede cargar una lista seguida o pegarla entera.
  void _alEscribir(String texto) {
    final ultima = texto.lastIndexOf(RegExp(r'[,;\n]'));
    if (ultima < 0) return;
    final resto = texto.substring(ultima + 1);
    _sumar(texto.substring(0, ultima));
    _palabraCtrl.value = TextEditingValue(
      text: resto,
      selection: TextSelection.collapsed(offset: resto.length),
    );
  }

  /// Qué falta para poder guardar (null = se puede guardar).
  String? get _faltante {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return 'Escribí un nombre para el rubro.';
    final norm = BuscadorLugares.normalizar(nombre);
    final repetido = Rubros.todos.any(
      (r) =>
          r.id != widget.inicial?.id &&
          BuscadorLugares.normalizar(r.nombre) == norm,
    );
    if (repetido) return 'Ya hay un rubro que se llama así.';
    // Sin palabras el rubro no sirve para buscar, que es para lo que existe.
    if (_palabras.isEmpty && _palabraCtrl.text.trim().isEmpty) {
      return 'Agregá al menos una palabra.';
    }
    return null;
  }

  /// Id para un rubro nuevo a partir de su nombre ("Ferretería" →
  /// "propio_ferreteria_lx3k9q2a"). Con el prefijo no choca con uno de
  /// fábrica, y el sufijo de tiempo hace que un id no se reuse nunca: si se
  /// borra un rubro y se crea otro con el mismo nombre, un lugar que haya
  /// quedado en memoria con el id viejo no pasa a apuntar al nuevo.
  String _nuevoId(String nombre) {
    final slug = BuscadorLugares.normalizar(
      nombre,
    ).split(RegExp(r'\s+')).join('_');
    final sufijo = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${Rubros.prefijoPropio}${slug}_$sufijo';
  }

  void _avisar(String texto) {
    if (!mounted) return;
    mostrarAviso(context, texto, error: true);
  }

  Future<void> _guardar() async {
    if (_faltante != null || _ocupado) return;
    // Lo que haya quedado escrito sin confirmar también cuenta.
    _sumar(_palabraCtrl.text);
    _palabraCtrl.clear();
    if (_palabras.isEmpty) return;
    final nombre = _nombreCtrl.text.trim();
    final id = widget.inicial?.id ?? _nuevoId(nombre);
    setState(() => _ocupado = true);
    try {
      await DatabaseHelper.instance.guardarRubro(
        Rubro(id, nombre, List.of(_palabras)),
      );
      if (mounted) {
        Navigator.pop(context, _editando ? 'Rubro guardado' : 'Rubro creado');
      }
    } catch (e) {
      if (mounted) setState(() => _ocupado = false);
      _avisar('No se pudo guardar el rubro: $e');
    }
  }

  Future<void> _borrar() async {
    final rubro = widget.inicial;
    if (rubro == null || _ocupado) return;
    final int usados;
    try {
      usados = await DatabaseHelper.instance.contarLugaresConRubro(rubro.id);
    } catch (e) {
      _avisar('No se pudieron contar los lugares del rubro: $e');
      return;
    }
    if (!mounted) return;
    final aviso = usados == 0
        ? 'Ningún lugar lo usa.'
        : '${usados == 1 ? 'Un lugar lo usa y va a quedar' : '$usados lugares lo usan y van a quedar'} '
              'sin rubro. Republicá sus mapas para que llegue a los usuarios.';
    final confirmar = await mostrarConfirmacion(
      context,
      titulo: '¿Borrar "${rubro.nombre}"?',
      mensaje: aviso,
      confirmar: 'Borrar',
      destructiva: true,
      iconoConfirmar: Icons.delete_rounded,
    );
    if (!confirmar || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await DatabaseHelper.instance.eliminarRubro(rubro.id);
      if (mounted) Navigator.pop(context, 'Rubro borrado');
    } catch (e) {
      if (mounted) setState(() => _ocupado = false);
      _avisar('No se pudo borrar el rubro: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final faltante = _faltante;
    final inicial = widget.inicial;
    return AmbienteDiseno(
      child: Builder(
        builder: (context) {
          final e = EstiloApp.de(context);
          final letraGrande = TipografiaApp.esLetraGrande(context);
          return Scaffold(
            backgroundColor: e.fondo,
            appBar: BarraSuperior(
              titulo: _editando ? 'Editar rubro' : 'Nuevo rubro',
              acciones: [
                // En la barra y no abajo: con el teclado abierto, un botón
                // de abajo quedaría tapado.
                AccionBarra(
                  icono: Icons.check_rounded,
                  etiqueta: 'Guardar',
                  alPresionar: faltante == null && !_ocupado ? _guardar : null,
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  EspaciadoApp.margenLateral,
                  EspaciadoApp.margenLateral,
                  EspaciadoApp.margenLateral,
                  EspaciadoApp.entreSecciones,
                ),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Con letra grande, sin el cuadro (decorativo).
                      if (!letraGrande) ...[
                        // A la altura del campo (52), centrado.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: CuadroIcono(icono: iconoRubro(inicial?.id)),
                        ),
                        const SizedBox(width: EspaciadoApp.medio),
                      ],
                      Expanded(
                        child: CampoTexto(
                          etiqueta: 'Nombre',
                          ayuda: 'Por ejemplo, Ferretería',
                          controlador: _nombreCtrl,
                          autofocus: !_editando,
                          capitalizacion: TextCapitalization.sentences,
                          accionTeclado: TextInputAction.next,
                          alCambiar: (_) => setState(() {}),
                          alEnviar: (_) => _palabraFoco.requestFocus(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EspaciadoApp.entreSecciones),
                  EncabezadoSeccion(
                    titulo: _palabras.isEmpty
                        ? 'Palabras'
                        : _palabras.length == 1
                        ? '1 palabra'
                        : '${_palabras.length} palabras',
                  ),
                  const SizedBox(height: EspaciadoApp.chico),
                  Text(
                    'Cómo se pide un lugar de este rubro: nombre, verbos '
                    '("comer"), necesidades ("hambre"), productos. En '
                    'singular; tildes y mayúsculas dan igual.',
                    style: TipografiaApp.subtitulo.copyWith(
                      color: e.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: EspaciadoApp.margenLateral),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: CampoTexto(
                          etiqueta: 'Palabra o frase',
                          ayuda: 'Agregar palabra o frase',
                          icono: Icons.record_voice_over_rounded,
                          controlador: _palabraCtrl,
                          focusNode: _palabraFoco,
                          accionTeclado: TextInputAction.done,
                          alCambiar: (t) {
                            _alEscribir(t);
                            setState(() {});
                          },
                          alEnviar: _agregar,
                        ),
                      ),
                      const SizedBox(width: EspaciadoApp.chico),
                      // El botón redondo (48), a la altura del campo (52).
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: BotonRedondo(
                          icono: Icons.add_rounded,
                          etiqueta: 'Agregar',
                          alPresionar: _palabraCtrl.text.trim().isEmpty
                              ? null
                              : () => _agregar(_palabraCtrl.text),
                        ),
                      ),
                    ],
                  ),
                  if (_palabras.isNotEmpty) ...[
                    const SizedBox(height: EspaciadoApp.margenLateral),
                    Wrap(
                      spacing: EspaciadoApp.chico,
                      runSpacing: EspaciadoApp.chico,
                      children: [
                        for (final p in _palabras)
                          _ChipPalabra(
                            texto: p,
                            alQuitar: () => setState(() => _palabras.remove(p)),
                          ),
                      ],
                    ),
                  ],
                  // Con el nombre vacío no se avisa nada: el botón Guardar
                  // apagado alcanza, y un rubro nuevo no arranca con un
                  // cartel de error.
                  if (faltante != null &&
                      _nombreCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: EspaciadoApp.margenLateral),
                    _Aclaracion(
                      icono: Icons.info_rounded,
                      texto: faltante,
                      color: e.advertencia,
                    ),
                  ],
                  if (inicial != null) ...[
                    const SizedBox(height: EspaciadoApp.entreSecciones),
                    if (Rubros.sePuedeBorrar(inicial.id))
                      BotonSecundario(
                        texto: 'Borrar rubro',
                        icono: Icons.delete_rounded,
                        destructivo: true,
                        expandido: true,
                        alPresionar: _ocupado ? null : _borrar,
                      )
                    else
                      PanelRelieve(
                        hundido: true,
                        child: _Aclaracion(
                          icono: Icons.lock_rounded,
                          texto:
                              'No se puede borrar: se usa para preguntar si el '
                              'baño es de hombres o de mujeres. Sus palabras sí '
                              'se pueden cambiar.',
                          color: e.textoSecundario,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Una palabra del rubro: la palabra en un chip hundido (es un dato) y, al
/// lado, el botón redondo para quitarla ("Quitar «comer»"), que TalkBack lee
/// aparte.
class _ChipPalabra extends StatelessWidget {
  const _ChipPalabra({required this.texto, required this.alQuitar});

  final String texto;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: ChipApp(texto: texto)),
        BotonRedondo(
          icono: Icons.close_rounded,
          etiqueta: 'Quitar «$texto»',
          alPresionar: alQuitar,
        ),
      ],
    );
  }
}

/// Una aclaración con su ícono: lo que falta (en ámbar) o por qué no se
/// puede borrar (en gris).
class _Aclaracion extends StatelessWidget {
  const _Aclaracion({
    required this.icono,
    required this.texto,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(icono, size: FormasApp.iconoChico, color: color),
        ),
        const SizedBox(width: EspaciadoApp.chico),
        Expanded(
          child: Text(
            texto,
            style: TipografiaApp.subtitulo.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
