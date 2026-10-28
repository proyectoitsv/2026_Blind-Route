import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'ajustes_navegacion.dart';
import 'supabase_service.dart';
import 'tema.dart';

// ─── PANEL DE AJUSTES DE NAVEGACIÓN (sólo app del administrador) ────────────
//
// Hoja inferior de la pantalla de navegación para regular los ajustes
// ([AjustesNavegacion]) caminando. Cada cambio rige al instante, se guarda en
// el teléfono y se sube a la nube apenas se suelta el control.
//
// Dos alcances, los dos para cualquier admin mientras se calibra (ver
// "TRES CAPAS" en ajustes_navegacion.dart):
//   • ESTE EDIFICIO: sólo los parámetros que dependen del edificio; los
//     demás se muestran sin poder moverlos y se cambian en "General".
//   • GENERAL: todos los edificios.
//
// La app del usuario no muestra este panel: el usuario no cambia ajustes.

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
    // El tema de la app, explícito: [context] es el de la pantalla de
    // navegación, que está POR ENCIMA de su propio Theme(TemaApp.tema). Sin
    // esto la hoja tomaba el tema claro de MaterialApp y los textos del
    // selector de alcance salían oscuros sobre el fondo oscuro (sólo se leían
    // al tocarlos).
    builder: (_) => Theme(
      data: TemaApp.tema,
      child: const _PanelAjustesNavegacion(),
    ),
  );
}

enum _Alcance { edificio, general }

class _PanelAjustesNavegacion extends StatefulWidget {
  const _PanelAjustesNavegacion();

  @override
  State<_PanelAjustesNavegacion> createState() =>
      _PanelAjustesNavegacionState();
}

class _PanelAjustesNavegacionState extends State<_PanelAjustesNavegacion> {
  final AjustesNavegacion _ajustes = AjustesNavegacion.instancia;
  final SupabaseService _nube = SupabaseService.instance;

  /// En un edificio se arranca por "Este edificio"; sin edificio, por
  /// "General", que es lo único que se puede cambiar.
  late _Alcance _alcance = _ajustes.edificioActual == null
      ? _Alcance.general
      : _Alcance.edificio;

  /// Valor que se está arrastrando, por clave. Se aplica al soltar: aplicar
  /// en cada paso del arrastre guardaría en el teléfono decenas de veces.
  final Map<String, double> _arrastre = {};

  /// Refresca el diagnóstico de la señal mientras el panel está abierto.
  Timer? _refresco;

  bool _subiendo = false;
  String? _errorNube;

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

  // ── Nube ──────────────────────────────────────────────────────────────────

  /// Sube lo pendiente. Si mientras subía se cambió otra cosa, vuelve a subir
  /// (con un tope, por las dudas).
  Future<void> _subir() async {
    if (_subiendo || !_nube.configurado) return;
    setState(() {
      _subiendo = true;
      _errorNube = null;
    });
    String? error;
    for (int vuelta = 0; vuelta < 5 && _ajustes.hayPendientes; vuelta++) {
      try {
        await _nube.subirAjustesNavegacion();
      } on PostgrestException catch (e) {
        error = e.code == '42501'
            ? 'La nube rechazó el cambio. Revisar la sesión de admin y que '
                'se haya corrido supabase/ajustes_navegacion.sql.'
            : 'Error de la nube: ${e.message}';
        break;
      } on StateError catch (e) {
        error = e.message;
        break;
      } catch (e) {
        error = 'Sin conexión: quedan en el teléfono y se suben al abrir la '
            'navegación con señal.';
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _subiendo = false;
      _errorNube = error;
    });
  }

  // ── Interfaz ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final edificio = _ajustes.edificioActual;
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
              Text(
                edificio == null ? 'Sin edificio' : 'Edificio: $edificio',
                style: const TextStyle(
                    fontSize: 14, color: TemaApp.textoSecundario),
              ),
              const SizedBox(height: 12),
              _diagnosticoSenal(),
              const SizedBox(height: 12),
              _estadoNube(),
              const SizedBox(height: 12),
              _selectorAlcance(),
              const SizedBox(height: 8),
              Text(
                _alcance == _Alcance.general
                    ? 'Rige en todos los edificios, salvo los que tengan un '
                        'valor propio.'
                    : 'Rige sólo en este edificio. Lo que no se cambia sigue '
                        'el valor general.',
                style: const TextStyle(
                    fontSize: 13, color: TemaApp.textoSecundario),
              ),
              const SizedBox(height: 16),
              _titulo('Giros'),
              for (final p in _ajustes.parametrosGiro) _control(p),
              const SizedBox(height: 4),
              _titulo('Seguimiento de la posición'),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Arranca tarde y avanza de golpe: bajar el umbral y las '
                  'ventanas, subir los filtros. Se pasa de largo: bajar el '
                  'empuje y la velocidad máxima.',
                  style:
                      TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
                ),
              ),
              for (final p in _ajustes.parametrosPosicion) _control(p),
              const SizedBox(height: 4),
              _titulo('Puntos clave'),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Se adelanta caminando hacia una esquina: bajar el radio o '
                  'la coincidencia mínima. Parado ahí no lo reconoce: '
                  'subirlos. El log [Fingerprint] dice qué dio cada uno.',
                  style:
                      TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
                ),
              ),
              for (final p in _ajustes.parametrosPuntoClave) _control(p),
              const SizedBox(height: 4),
              _titulo('Pruebas (no se guardan)'),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Para comparar. Se vuelven a prender al cerrar la app; en '
                  'la del usuario siempre están prendidos.',
                  style:
                      TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
                ),
              ),
              _interruptor(
                titulo: 'Freno lateral por brújula',
                detalle: 'Con la brújula desviada retiene parte del avance y '
                    'lo suelta de golpe al doblar.',
                valor: _ajustes.frenarLateralConBrujula,
                cambiar: (v) => _ajustes.frenarLateralConBrujula = v,
              ),
              _interruptor(
                titulo: 'Sacar la posición de zonas prohibidas',
                detalle: 'Si cae en una zona no transitable, la lleva a la '
                    'celda libre más cercana.',
                valor: _ajustes.restringirZonas,
                cambiar: (v) => _ajustes.restringirZonas = v,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorAlcance() {
    return SegmentedButton<_Alcance>(
      segments: const [
        ButtonSegment(
          value: _Alcance.edificio,
          label: Text('Este edificio'),
          icon: Icon(Icons.apartment_rounded),
        ),
        ButtonSegment(
          value: _Alcance.general,
          label: Text('General'),
          icon: Icon(Icons.public_rounded),
        ),
      ],
      selected: {_alcance},
      onSelectionChanged: (s) => setState(() => _alcance = s.first),
    );
  }

  /// Si los cambios llegaron a la nube.
  Widget _estadoNube() {
    final String texto;
    Color color = TemaApp.textoSecundario;
    Widget? accion;
    if (!_nube.configurado) {
      texto = 'Sin nube configurada: los cambios quedan sólo en este teléfono.';
    } else if (_subiendo) {
      texto = 'Subiendo a la nube…';
    } else if (_errorNube != null) {
      texto = _errorNube!;
      color = TemaApp.advertencia;
      accion = TextButton(onPressed: _subir, child: const Text('Reintentar'));
    } else if (_ajustes.hayPendientes) {
      texto = 'Hay cambios sin subir a la nube.';
      color = TemaApp.advertencia;
      accion = TextButton(onPressed: _subir, child: const Text('Subir ahora'));
    } else {
      texto = 'Todo guardado en la nube.';
      color = TemaApp.acento;
    }
    return Row(
      children: [
        Expanded(
          child: Text(texto, style: TextStyle(fontSize: 13, color: color)),
        ),
        ?accion,
      ],
    );
  }

  /// Cuántas lecturas por segundo llegan de verdad de los beacons (lo mide
  /// la navegación). Con pocas, avisa que el límite está en los beacons.
  Widget _diagnosticoSenal() {
    final texto = _ajustes.diagnosticoSenal;
    final hora = _ajustes.diagnosticoSenalHora;
    if (texto == null || hora == null) {
      return const Text(
        'Señal: sin medir (se mide cada 5 s navegando).',
        style: TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
      );
    }
    final hace = DateTime.now().difference(hora).inSeconds;
    final lps = _ajustes.lecturasPorSegundo;
    final poca = lps != null && lps < 3;
    final color = poca ? TemaApp.advertencia : TemaApp.acento;
    return Container(
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
                'Pocas lecturas: no se puede tener poco atraso y poco ruido '
                'a la vez. Configurar los beacons para emitir cada 100 a '
                '200 ms.',
                style: TextStyle(fontSize: 12, color: TemaApp.advertencia),
              ),
            ),
        ],
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
      onChanged: (v) => setState(() => cambiar(v)),
    );
  }

  /// Control de un parámetro en el alcance elegido: el valor, de qué capa
  /// sale y, si tiene uno propio en esa capa, cómo volver al de abajo.
  Widget _control(ParametroAjuste p) {
    final general = _alcance == _Alcance.general;
    final hayEdificio = _ajustes.edificioActual != null;
    final editable = general || (p.porEdificio && hayEdificio);
    final valor = _arrastre[p.clave] ??
        (general ? _ajustes.valorGeneral(p) : p.valor);

    // De dónde sale el valor y cómo volver al de la capa de abajo.
    String origen;
    String? textoVolver;
    VoidCallback? volver;
    String? aviso;
    if (general) {
      if (_ajustes.generalCambiado(p)) {
        origen = 'Cambiado para todos (el del código es '
            '${p.formatear(p.porDefecto)}).';
        textoVolver = 'Volver al valor del código';
        volver = () => _ajustes.volverAlCodigo(p);
      } else {
        origen = 'Valor del código.';
      }
      final propio = _ajustes.valorDelEdificio(p);
      if (propio != null) {
        aviso = 'Este edificio usa su propio valor (${p.formatear(propio)}).';
      }
    } else if (!p.porEdificio) {
      origen = 'No depende del edificio: se cambia en "General".';
    } else if (!hayEdificio) {
      origen = 'Sin edificio: no se puede cambiar por edificio.';
    } else if (_ajustes.origen(p) == OrigenAjuste.edificio) {
      origen = 'Cambiado en este edificio (el general es '
          '${p.formatear(_ajustes.valorGeneral(p))}).';
      textoVolver = 'Volver al valor general';
      volver = () => _ajustes.volverAlGeneral(p);
    } else {
      origen = 'Valor general.';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El nombre y el valor los lee el lector de pantalla desde el
          // slider: este texto queda sólo para la vista.
          ExcludeSemantics(
            child: Text(
              '${p.nombre}: ${p.formatear(valor)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: editable ? TemaApp.textoBlanco : TemaApp.textoSecundario,
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
              label: p.nombre,
              child: Slider(
                value: valor,
                min: p.minimo,
                max: p.maximo,
                divisions: p.divisiones,
                label: p.formatear(valor),
                semanticFormatterCallback: p.hablado,
                onChanged: editable
                    ? (v) => setState(() => _arrastre[p.clave] = v)
                    : null,
                onChangeEnd: editable
                    ? (v) {
                        setState(() {
                          _arrastre.remove(p.clave);
                          if (general) {
                            _ajustes.cambiarGeneral(p, v);
                          } else {
                            _ajustes.cambiarEnEdificio(p, v);
                          }
                        });
                        _subir();
                      }
                    : null,
              ),
            ),
          ),
          Text(
            origen,
            style: const TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
          ),
          if (aviso != null)
            Text(
              aviso,
              style: const TextStyle(fontSize: 12, color: TemaApp.advertencia),
            ),
          if (volver != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(volver!);
                  _subir();
                },
                child: Text(textoVolver!),
              ),
            ),
          Text(
            p.ayuda,
            style: const TextStyle(fontSize: 12, color: TemaApp.textoSecundario),
          ),
        ],
      ),
    );
  }
}
