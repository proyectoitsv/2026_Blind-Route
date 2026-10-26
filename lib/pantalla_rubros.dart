import 'package:flutter/material.dart';

import 'buscador_lugares.dart';
import 'database.dart';
import 'rubros.dart';
import 'tema.dart';

/// Ícono de un rubro. Los de fábrica tienen el suyo; los creados por el admin
/// llevan uno genérico.
IconData iconoRubro(String? id) {
  switch (id) {
    case 'comida':
      return Icons.restaurant;
    case 'cafe':
      return Icons.local_cafe;
    case Rubros.bano:
      return Icons.wc;
    case 'kiosco':
      return Icons.storefront;
    case 'tienda':
      return Icons.shopping_bag;
    case 'salud':
      return Icons.local_pharmacy;
    case 'cajero':
      return Icons.atm;
    case 'informacion':
      return Icons.info_outline;
    case 'oficina':
      return Icons.work_outline;
    case 'aula':
      return Icons.school;
    case 'laboratorio':
      return Icons.science;
    case 'biblioteca':
      return Icons.local_library;
    case 'salida':
      return Icons.door_front_door;
    case 'descanso':
      return Icons.event_seat;
    case 'deporte':
      return Icons.sports_soccer;
    case 'capilla':
      return Icons.church;
    case 'estacionamiento':
      return Icons.local_parking;
    case 'transporte':
      return Icons.directions_bus;
    default:
      return Icons.sell_outlined;
  }
}

/// Borde de chips y campos, el mismo que usa el tema para los inputs.
const Color _borde = Color(0xFF30363D);

/// Administración del catálogo de rubros de este teléfono: crear rubros
/// propios, cambiar el nombre y las palabras de uno existente, y borrarlos.
///
/// Los cambios valen enseguida para los lugares de este teléfono, pero a los
/// usuarios les llegan recién al REPUBLICAR el mapa: cada lugar publicado
/// lleva una copia de las palabras de su rubro (ver rubros.dart).
class PantallaRubros extends StatefulWidget {
  const PantallaRubros({super.key});

  @override
  State<PantallaRubros> createState() => _PantallaRubrosState();
}

class _PantallaRubrosState extends State<PantallaRubros> {
  /// Abre el editor ([rubro] null = rubro nuevo). Al volver, si hubo cambios,
  /// rearma la lista y avisa qué pasó.
  Future<void> _abrirEditor([Rubro? rubro]) async {
    final aviso = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _EditorRubro(inicial: rubro),
      ),
    );
    if (aviso == null || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(title: const Text('Rubros')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _abrirEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Nuevo rubro'),
        ),
        body: ListView(
          // Margen abajo para que el botón flotante no tape la última tarjeta.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const Text(
              'Las palabras de cada rubro sirven para pedir sus lugares por '
              'voz. Los cambios llegan al volver a publicar el mapa.',
              style: TextStyle(
                color: TemaApp.textoSecundario,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            for (final r in Rubros.todos)
              _TarjetaRubro(rubro: r, onTap: () => _abrirEditor(r)),
          ],
        ),
      ),
    );
  }
}

/// Un rubro en la lista: ícono, nombre y una muestra de sus palabras. Tocarla
/// abre el editor (ahí también se borra).
class _TarjetaRubro extends StatelessWidget {
  final Rubro rubro;
  final VoidCallback onTap;

  const _TarjetaRubro({required this.rubro, required this.onTap});

  /// Cuántas palabras se muestran antes del "+N".
  static const int _muestra = 5;

  @override
  Widget build(BuildContext context) {
    final resto = rubro.palabras.length - _muestra;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: TemaApp.fondoCard,
        borderRadius: BorderRadius.circular(TemaApp.radiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TemaApp.radiusCard),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconoRubro(rubro.id),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rubro.nombre,
                        style: const TextStyle(
                          color: TemaApp.textoBlanco,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in rubro.palabras.take(_muestra))
                            _ChipPalabra(p),
                          if (resto > 0) _ChipPalabra('+$resto', apagado: true),
                        ],
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 4, top: 8),
                  child: Icon(Icons.edit_outlined,
                      size: 20, color: TemaApp.textoSecundario),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ícono del rubro dentro de un cuadrado redondeado con el acento.
class _IconoRubro extends StatelessWidget {
  final String? id;

  const _IconoRubro(this.id);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: TemaApp.acentoSuave,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(iconoRubro(id), color: TemaApp.acento, size: 24),
    );
  }
}

/// Una palabra de un rubro, como chip de solo lectura.
class _ChipPalabra extends StatelessWidget {
  final String texto;
  final bool apagado;

  const _ChipPalabra(this.texto, {this.apagado = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: apagado ? Colors.transparent : TemaApp.fondoSurface,
        borderRadius: BorderRadius.circular(TemaApp.radiusChip),
        border: Border.all(color: _borde),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: apagado ? TemaApp.textoSecundario : TemaApp.textoBlanco,
          fontSize: 13,
        ),
      ),
    );
  }
}

// ─── Editor ──────────────────────────────────────────────────────────────────

/// Alta y edición de un rubro, a pantalla completa: nombre y palabras. Las
/// palabras se agregan de a una (o varias pegadas con comas) y se quitan con
/// la cruz de su chip. Si se edita uno que se puede borrar, abajo está el
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
    final repetido = Rubros.todos.any((r) =>
        r.id != widget.inicial?.id &&
        BuscadorLugares.normalizar(r.nombre) == norm);
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
    final slug =
        BuscadorLugares.normalizar(nombre).split(RegExp(r'\s+')).join('_');
    final sufijo = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${Rubros.prefijoPropio}${slug}_$sufijo';
  }

  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
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
      await DatabaseHelper.instance
          .guardarRubro(Rubro(id, nombre, List.of(_palabras)));
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
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TemaApp.fondoCard,
        title: Text('¿Borrar "${rubro.nombre}"?'),
        content: Text(aviso,
            style: const TextStyle(color: TemaApp.textoSecundario)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: TemaApp.zonaRestringidaBorde),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
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
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(
          title: Text(_editando ? 'Editar rubro' : 'Nuevo rubro'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: faltante == null && !_ocupado ? _guardar : null,
                child: const Text('Guardar'),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Row(
              children: [
                _IconoRubro(inicial?.id),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: _nombreCtrl,
                    autofocus: !_editando,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _palabraFoco.requestFocus(),
                    style: const TextStyle(fontSize: 17),
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      hintText: 'Ej: Ferretería',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              _palabras.isEmpty
                  ? 'Palabras'
                  : _palabras.length == 1
                      ? '1 palabra'
                      : '${_palabras.length} palabras',
              style: const TextStyle(
                color: TemaApp.textoBlanco,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cómo se pide un lugar de este rubro: nombre, verbos '
              '("comer"), necesidades ("hambre"), productos. En singular; '
              'tildes y mayúsculas dan igual.',
              style: TextStyle(
                color: TemaApp.textoSecundario,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _palabraCtrl,
              focusNode: _palabraFoco,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              onChanged: (t) {
                _alEscribir(t);
                setState(() {});
              },
              onSubmitted: _agregar,
              decoration: InputDecoration(
                hintText: 'Agregar palabra o frase',
                prefixIcon: const Icon(Icons.record_voice_over_outlined,
                    color: TemaApp.textoSecundario),
                suffixIcon: IconButton(
                  tooltip: 'Agregar',
                  icon: const Icon(Icons.add_circle),
                  color: TemaApp.acento,
                  disabledColor: _borde,
                  onPressed: _palabraCtrl.text.trim().isEmpty
                      ? null
                      : () => _agregar(_palabraCtrl.text),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_palabras.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _palabras)
                    InputChip(
                      label: Text(p),
                      labelStyle: const TextStyle(
                        color: TemaApp.textoBlanco,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                      backgroundColor: TemaApp.fondoSurface,
                      side: const BorderSide(color: _borde),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(TemaApp.radiusChip),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      deleteIconColor: TemaApp.textoSecundario,
                      deleteButtonTooltipMessage: 'Quitar "$p"',
                      onDeleted: () => setState(() => _palabras.remove(p)),
                    ),
                ],
              ),
            // Con el nombre vacío no se avisa nada: el botón Guardar apagado
            // alcanza, y un rubro nuevo no arranca con un cartel de error.
            if (faltante != null && _nombreCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: TemaApp.advertencia),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      faltante,
                      style: const TextStyle(
                          color: TemaApp.advertencia, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
            if (inicial != null) ...[
              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 12),
              if (Rubros.sePuedeBorrar(inicial.id))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _ocupado ? null : _borrar,
                    style: TextButton.styleFrom(
                      foregroundColor: TemaApp.zonaRestringidaBorde,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Borrar rubro'),
                  ),
                )
              else
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 18, color: TemaApp.textoSecundario),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No se puede borrar: se usa para preguntar si el baño '
                        'es de hombres o de mujeres. Sus palabras sí se '
                        'pueden cambiar.',
                        style: TextStyle(
                          color: TemaApp.textoSecundario,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
