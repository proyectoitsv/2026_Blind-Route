import 'dart:async';

import 'package:flutter/material.dart';

import 'ajustes_navegacion.dart';
import 'tema.dart';

// ─── PANEL DE AJUSTES DE NAVEGACIÓN ─────────────────────────────────────────
//
// Dos pantallas sobre [AjustesNavegacion]:
//   • El PANEL (hoja inferior): la lista de configuraciones guardadas, con su
//     calificación a la derecha. Tocar una la pone en uso; la flecha
//     despliega la descripción, las estrellas para calificarla y las
//     acciones (editar, duplicar, borrar).
//   • El EDITOR (pantalla completa): nombre, descripción, calificación y
//     todos los valores. En las de fábrica sólo se editan la descripción y la
//     calificación: son la referencia contra la que se compara, y para probar
//     otros valores se duplican.
//
// Todo se guarda al momento y, si la configuración editada es la que está en
// uso, sus valores rigen desde ya: se puede regular caminando.

const Color _colorEstrella = TemaApp.advertencia;

String _nombreVisible(Preseleccion p) =>
    p.nombre.trim().isEmpty ? 'Sin nombre' : p.nombre.trim();

/// Abre el panel de ajustes de navegación.
Future<void> mostrarPanelAjustesNavegacion(BuildContext context) async {
  await AjustesNavegacion.instancia.cargar();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TemaApp.fondoCard,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(TemaApp.radiusCard)),
    ),
    builder: (_) => const _PanelAjustesNavegacion(),
  );
}

// ─── LISTA DE CONFIGURACIONES ───────────────────────────────────────────────

class _PanelAjustesNavegacion extends StatefulWidget {
  const _PanelAjustesNavegacion();

  @override
  State<_PanelAjustesNavegacion> createState() =>
      _PanelAjustesNavegacionState();
}

class _PanelAjustesNavegacionState extends State<_PanelAjustesNavegacion> {
  final AjustesNavegacion _ajustes = AjustesNavegacion.instancia;

  /// Configuraciones con la descripción desplegada.
  final Set<String> _desplegadas = {};

  /// Refresca el diagnóstico de la señal mientras el panel está abierto.
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    _refresco = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  /// Cuántas lecturas por segundo llegan de verdad de los beacons (lo mide
  /// la navegación). Con pocas, avisa que el límite está en los beacons.
  Widget _diagnosticoSenal() {
    final texto = _ajustes.diagnosticoSenal;
    final hora = _ajustes.diagnosticoSenalHora;
    if (texto == null || hora == null) {
      return const Text(
        'Señal: todavía sin medir (se mide navegando, cada 5 segundos).',
        style: TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
      );
    }
    final hace = DateTime.now().difference(hora).inSeconds;
    final lps = _ajustes.lecturasPorSegundo;
    final poca = lps != null && lps < 3;
    final color = poca ? TemaApp.advertencia : TemaApp.acento;
    return Semantics(
      liveRegion: false,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: poca ? TemaApp.fondoAdvertencia : TemaApp.fondoPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SEÑAL AHORA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$texto (hace $hace s)',
              style: const TextStyle(fontSize: 13, color: TemaApp.textoBlanco),
            ),
            if (poca)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Los beacons emiten pocas veces por segundo: así ninguna '
                  'configuración puede tener poco atraso y poco ruido a la '
                  'vez. Conviene configurarlos para emitir cada 100 a 200 ms '
                  '(de 5 a 10 veces por segundo).',
                  style: TextStyle(fontSize: 12, color: TemaApp.advertencia),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirEditor(Preseleccion p) async {
    // El editor devuelve una configuración cuando, desde una de fábrica, se
    // pidió duplicarla para editarla: entonces se abre el editor de la copia.
    final otra = await Navigator.of(context).push<Preseleccion>(
      MaterialPageRoute(builder: (_) => _EditorPreseleccion(preseleccion: p)),
    );
    if (!mounted) return;
    setState(() {});
    if (otra != null) {
      setState(() => _desplegadas.add(otra.id));
      await _abrirEditor(otra);
    }
  }

  /// Crea una propia (copia de [base], o de la que está en uso) y la abre.
  void _nuevaPropia({Preseleccion? base}) {
    final nueva = _ajustes.crearPropia(base: base);
    setState(() => _desplegadas.add(nueva.id));
    _abrirEditor(nueva);
  }

  Future<void> _confirmarBorrar(Preseleccion p) async {
    final ok = await _confirmarBorrado(context, p);
    if (ok && mounted) setState(() => _ajustes.borrar(p));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Ajustes de navegación',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: TemaApp.textoBlanco,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tocá una configuración para usarla. Las de fábrica sirven de '
                'referencia: calificalas y anotá qué anda; para cambiar '
                'valores, duplicá una o creá una personalizada.',
                style: TextStyle(fontSize: 13, color: TemaApp.textoSecundario),
              ),
              const SizedBox(height: 12),
              _diagnosticoSenal(),
              const SizedBox(height: 16),
              for (final p in _ajustes.preselecciones) _tarjeta(p),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Nueva personalizada'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TemaApp.acento,
                  side: const BorderSide(color: TemaApp.acento),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _nuevaPropia(),
              ),
              const SizedBox(height: 4),
              const Text(
                'Arranca con los valores de la configuración en uso.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(Preseleccion p) {
    final enUso = _ajustes.esActiva(p);
    final desplegada = _desplegadas.contains(p.id);
    final nombre = _nombreVisible(p);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: TemaApp.fondoPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enUso ? TemaApp.acento : TemaApp.fondoSurface,
          width: enUso ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  selected: enUso,
                  label: '$nombre. ${p.calificacion} de 5 estrellas.'
                      '${enUso ? ' En uso.' : ''}',
                  onTapHint: 'usar esta configuración',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _ajustes.seleccionar(p)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                      child: Row(
                        children: [
                          Icon(
                            enUso
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: enUso
                                ? TemaApp.acento
                                : TemaApp.textoSecundario,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: TemaApp.textoBlanco,
                                  ),
                                ),
                                if (p.deFabrica || enUso)
                                  Text(
                                    [
                                      if (p.deFabrica) 'De fábrica',
                                      if (enUso) 'En uso',
                                    ].join(' · '),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: enUso
                                          ? TemaApp.acento
                                          : TemaApp.textoSecundario,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          _Estrellas(valor: p.calificacion),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: desplegada ? 'Ocultar descripción' : 'Ver descripción',
                icon: Icon(desplegada
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded),
                color: TemaApp.textoSecundario,
                onPressed: () => setState(() {
                  if (desplegada) {
                    _desplegadas.remove(p.id);
                  } else {
                    _desplegadas.add(p.id);
                  }
                }),
              ),
            ],
          ),
          if (desplegada)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.descripcion.trim().isEmpty
                        ? 'Sin descripción todavía.'
                        : p.descripcion.trim(),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: TemaApp.textoSecundario,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _EditorCalificacion(
                    valor: p.calificacion,
                    alCambiar: (v) {
                      setState(() => p.calificacion = v);
                      _ajustes.preseleccionCambiada(p);
                    },
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        icon: Icon(p.deFabrica
                            ? Icons.edit_note_rounded
                            : Icons.edit_rounded),
                        label: Text(p.deFabrica ? 'Anotar y ver valores' : 'Editar'),
                        style: TextButton.styleFrom(
                            foregroundColor: TemaApp.acento),
                        onPressed: () => _abrirEditor(p),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Duplicar'),
                        style: TextButton.styleFrom(
                            foregroundColor: TemaApp.acento),
                        onPressed: () => _nuevaPropia(base: p),
                      ),
                      if (!p.deFabrica)
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Borrar'),
                          style: TextButton.styleFrom(
                              foregroundColor: TemaApp.zonaRestringidaBorde),
                          onPressed: () => _confirmarBorrar(p),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Future<bool> _confirmarBorrado(BuildContext context, Preseleccion p) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('¿Borrar "${_nombreVisible(p)}"?'),
      content: const Text('Se pierden sus valores y sus anotaciones.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  return ok == true;
}

// ─── ESTRELLAS ──────────────────────────────────────────────────────────────

/// Calificación de solo lectura (la lee el lector de pantalla desde la
/// tarjeta que la contiene).
class _Estrellas extends StatelessWidget {
  final int valor;
  const _Estrellas({required this.valor});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 1; i <= 5; i++)
            Icon(
              i <= valor ? Icons.star_rounded : Icons.star_border_rounded,
              size: 16,
              color: i <= valor
                  ? _colorEstrella
                  : TemaApp.textoSecundario.withValues(alpha: 0.6),
            ),
        ],
      ),
    );
  }
}

/// Estrellas para calificar de 0 a 5. Tocar la estrella que ya marca el
/// valor la desmarca (así se llega a 0). 
class _EditorCalificacion extends StatelessWidget {
  final int valor;
  final ValueChanged<int> alCambiar;
  const _EditorCalificacion({required this.valor, required this.alCambiar});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ExcludeSemantics(
          child: Text(
            'Calificación: $valor de 5',
            style: const TextStyle(fontSize: 13, color: TemaApp.textoSecundario),
          ),
        ),
        const SizedBox(width: 4),
        for (int i = 1; i <= 5; i++)
          IconButton(
            tooltip: valor == i
                ? 'Calificación $i de 5. Tocar para bajar a ${i - 1}'
                : 'Calificar con $i de 5',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              i <= valor ? Icons.star_rounded : Icons.star_border_rounded,
              color: i <= valor ? _colorEstrella : TemaApp.textoSecundario,
            ),
            onPressed: () => alCambiar(valor == i ? i - 1 : i),
          ),
      ],
    );
  }
}

// ─── EDITOR ─────────────────────────────────────────────────────────────────

/// Pantalla para editar una configuración. Devuelve (al cerrar) la copia
/// creada con "Duplicar y editar", si se usó.
class _EditorPreseleccion extends StatefulWidget {
  final Preseleccion preseleccion;
  const _EditorPreseleccion({required this.preseleccion});

  @override
  State<_EditorPreseleccion> createState() => _EditorPreseleccionState();
}

class _EditorPreseleccionState extends State<_EditorPreseleccion> {
  final AjustesNavegacion _ajustes = AjustesNavegacion.instancia;
  late final TextEditingController _nombre =
      TextEditingController(text: _p.nombre);
  late final TextEditingController _descripcion =
      TextEditingController(text: _p.descripcion);

  /// true si se borró desde acá: ya no hay nada que guardar al salir.
  bool _borrada = false;

  Preseleccion get _p => widget.preseleccion;

  /// Las de fábrica sólo admiten descripción y calificación.
  bool get _bloqueada => _p.deFabrica;

  @override
  void dispose() {
    // El texto se va copiando al modelo mientras se escribe; al salir sólo
    // falta no dejar un nombre vacío, y guardar.
    if (!_borrada) {
      if (_p.nombre.trim().isEmpty) _p.nombre = 'Sin nombre';
      _p.nombre = _p.nombre.trim();
      _p.descripcion = _p.descripcion.trim();
      _ajustes.preseleccionCambiada(_p);
    }
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  void _cambiado() => _ajustes.preseleccionCambiada(_p);

  Future<void> _borrar() async {
    final ok = await _confirmarBorrado(context, _p);
    if (!ok || !mounted) return;
    _borrada = true;
    _ajustes.borrar(_p);
    Navigator.of(context).pop();
  }

  void _duplicarYEditar() {
    final copia = _ajustes.crearPropia(base: _p);
    Navigator.of(context).pop(copia);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(
          backgroundColor: TemaApp.fondoCard,
          foregroundColor: TemaApp.textoBlanco,
          title: Text(
              _bloqueada ? 'Configuración de fábrica' : 'Editar configuración'),
          actions: [
            if (!_bloqueada)
              IconButton(
                tooltip: 'Borrar configuración',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _borrar,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_bloqueada) _avisoFabrica(),
            TextField(
              controller: _nombre,
              enabled: !_bloqueada,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: TemaApp.textoBlanco),
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              onChanged: (t) => _p.nombre = t,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descripcion,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: TemaApp.textoBlanco),
              decoration: const InputDecoration(
                labelText: 'Descripción y anotaciones',
                hintText: 'Qué anda, qué no, dónde la probaste…',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (t) => _p.descripcion = t,
            ),
            const SizedBox(height: 4),
            _EditorCalificacion(
              valor: _p.calificacion,
              alCambiar: (v) {
                setState(() => _p.calificacion = v);
                _cambiado();
              },
            ),
            _estadoDeUso(),
            const SizedBox(height: 16),
            _titulo('Giros'),
            for (final def in _ajustes.parametrosGiro) _control(def),
            const SizedBox(height: 4),
            _titulo('Seguimiento de la posición'),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Si el punto tarda en arrancar y después avanza de golpe: '
                'bajar el umbral de caminata y las ventanas de señal, subir '
                'los filtros. Si se pasa de largo: bajar el empuje y la '
                'velocidad máxima.',
                style: TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
              ),
            ),
            _interruptor(
              titulo: 'Frenar el movimiento de costado con la brújula',
              detalle: 'Con la brújula desviada retiene parte del avance y lo '
                  'suelta de golpe al doblar. Apagarlo para ver si el '
                  'problema viene de ahí.',
              valor: _p.frenarLateralConBrujula,
              cambiar: (v) => _p.frenarLateralConBrujula = v,
            ),
            for (final def in _ajustes.parametrosPosicion) _control(def),
            const SizedBox(height: 4),
            _titulo('Zonas'),
            _interruptor(
              titulo: 'No dejar la posición en zonas prohibidas',
              detalle: 'Si el posicionamiento cae en una zona no transitable, '
                  'se usa la celda transitable que mejor coincide.',
              valor: _p.restringirZonas,
              cambiar: (v) => _p.restringirZonas = v,
            ),
          ],
        ),
      ),
    );
  }

  Widget _avisoFabrica() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TemaApp.acentoSuave,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Es una configuración de fábrica: sirve de referencia y sus '
            'valores no se cambian. Podés calificarla y anotar qué anda. Para '
            'probar otros valores, duplicala.',
            style: TextStyle(fontSize: 13, color: TemaApp.textoBlanco),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Duplicar y editar'),
            onPressed: _duplicarYEditar,
          ),
        ],
      ),
    );
  }

  Widget _estadoDeUso() {
    if (_ajustes.esActiva(_p)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: TemaApp.acento, size: 20),
            SizedBox(width: 8),
            Text(
              'En uso: los cambios rigen al instante.',
              style: TextStyle(fontSize: 13, color: TemaApp.acento),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Usar esta configuración'),
        style: OutlinedButton.styleFrom(foregroundColor: TemaApp.acento),
        onPressed: () => setState(() => _ajustes.seleccionar(_p)),
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          header: true,
          child: Text(
            texto.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: TemaApp.acento,
            ),
          ),
        ),
      );

  Widget _interruptor({
    required String titulo,
    required String detalle,
    required bool valor,
    required void Function(bool) cambiar,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: valor,
      title: Text(
        titulo,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: TemaApp.textoBlanco,
        ),
      ),
      subtitle: Text(
        detalle,
        style: const TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
      ),
      onChanged: _bloqueada
          ? null
          : (v) {
              setState(() => cambiar(v));
              _cambiado();
            },
    );
  }

  Widget _control(ParametroAjuste def) {
    final valor = (_p.valores[def.clave] ?? def.porDefecto)
        .clamp(def.minimo, def.maximo)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El nombre y el valor los lee el lector de pantalla desde el
          // slider: este texto queda sólo para la vista.
          ExcludeSemantics(
            child: Text(
              '${def.nombre}: ${def.formatear(valor)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _bloqueada
                    ? TemaApp.textoSecundario
                    : TemaApp.textoBlanco,
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: TemaApp.acento,
              thumbColor: TemaApp.acento,
              inactiveTrackColor: TemaApp.fondoSurface,
              overlayColor: TemaApp.acento.withValues(alpha: 0.15),
              valueIndicatorColor: TemaApp.acento,
              valueIndicatorTextStyle: const TextStyle(
                color: TemaApp.fondo,
                fontWeight: FontWeight.bold,
              ),
            ),
            child: Semantics(
              label: def.nombre,
              child: Slider(
                value: valor,
                min: def.minimo,
                max: def.maximo,
                divisions: def.divisiones,
                label: def.formatear(valor),
                semanticFormatterCallback: def.hablado,
                onChanged: _bloqueada
                    ? null
                    : (v) => setState(() => _p.valores[def.clave] = v),
                onChangeEnd: (_) => _cambiado(),
              ),
            ),
          ),
          Text(
            def.ayuda,
            style: const TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
          ),
        ],
      ),
    );
  }
}
