import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'ajustes_navegacion.dart';
import 'supabase_service.dart';
import 'design/design.dart';

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
  await mostrarHoja<void>(
    context,
    titulo: 'Ajustes de navegación',
    contenido: (_) => const _PanelAjustesNavegacion(),
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
        error =
            'Sin conexión: quedan en el teléfono y se suben al abrir la '
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
    final e = EstiloApp.de(context);
    final edificio = _ajustes.edificioActual;
    final pista = TipografiaApp.nota.copyWith(color: e.textoSecundario);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          edificio == null ? 'Sin edificio' : 'Edificio: $edificio',
          style: TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
        ),
        const SizedBox(height: EspaciadoApp.medio),
        _diagnosticoSenal(e),
        const SizedBox(height: EspaciadoApp.medio),
        _estadoNube(e),
        const SizedBox(height: EspaciadoApp.medio),
        _selectorAlcance(),
        const SizedBox(height: EspaciadoApp.chico),
        Text(
          _alcance == _Alcance.general
              ? 'Rige en todos los edificios, salvo los que tengan un '
                    'valor propio.'
              : 'Rige sólo en este edificio. Lo que no se cambia sigue '
                    'el valor general.',
          style: pista,
        ),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        const EncabezadoSeccion(titulo: 'Giros'),
        const SizedBox(height: EspaciadoApp.medio),
        for (final p in _ajustes.parametrosGiro) _control(e, p),
        const SizedBox(height: EspaciadoApp.medio),
        const EncabezadoSeccion(titulo: 'Seguimiento de la posición'),
        const SizedBox(height: EspaciadoApp.chico),
        Text(
          'Arranca tarde y avanza de golpe: bajar el umbral y las '
          'ventanas, subir los filtros. Se pasa de largo: bajar el '
          'empuje y la velocidad máxima.',
          style: pista,
        ),
        const SizedBox(height: EspaciadoApp.medio),
        for (final p in _ajustes.parametrosPosicion) _control(e, p),
        const SizedBox(height: EspaciadoApp.medio),
        const EncabezadoSeccion(titulo: 'Puntos clave'),
        const SizedBox(height: EspaciadoApp.chico),
        Text(
          'Se adelanta caminando hacia una esquina: bajar el radio o '
          'la coincidencia mínima. Parado ahí no lo reconoce: '
          'subirlos. El log [Fingerprint] dice qué dio cada uno.',
          style: pista,
        ),
        const SizedBox(height: EspaciadoApp.medio),
        for (final p in _ajustes.parametrosPuntoClave) _control(e, p),
        const SizedBox(height: EspaciadoApp.medio),
        const EncabezadoSeccion(titulo: 'Pruebas (no se guardan)'),
        const SizedBox(height: EspaciadoApp.chico),
        Text(
          'Para comparar. Se vuelven a prender al cerrar la app; en '
          'la del usuario siempre están prendidos.',
          style: pista,
        ),
        const SizedBox(height: EspaciadoApp.medio),
        GrupoFilas(
          filas: [
            FilaGrupo.interruptor(
              titulo: 'Freno lateral por brújula',
              subtitulo:
                  'Con la brújula desviada retiene parte del avance y '
                  'lo suelta de golpe al doblar.',
              valor: _ajustes.frenarLateralConBrujula,
              alCambiar: (v) =>
                  setState(() => _ajustes.frenarLateralConBrujula = v),
            ),
            FilaGrupo.interruptor(
              titulo: 'Sacar la posición de zonas prohibidas',
              subtitulo:
                  'Si cae en una zona no transitable, la lleva a la '
                  'celda libre más cercana.',
              valor: _ajustes.restringirZonas,
              alCambiar: (v) => setState(() => _ajustes.restringirZonas = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _selectorAlcance() {
    return ControlSegmentado<_Alcance>(
      etiqueta: 'Alcance de los ajustes',
      opciones: const [
        OpcionSegmento(
          valor: _Alcance.edificio,
          texto: 'Este edificio',
          icono: Icons.apartment_rounded,
        ),
        OpcionSegmento(
          valor: _Alcance.general,
          texto: 'General',
          icono: Icons.public_rounded,
        ),
      ],
      seleccionada: _alcance,
      alCambiar: (a) => setState(() => _alcance = a),
    );
  }

  /// Si los cambios llegaron a la nube.
  Widget _estadoNube(EstiloApp e) {
    final String texto;
    Color color = e.textoSecundario;
    Widget? accion;
    if (!_nube.configurado) {
      texto = 'Sin nube configurada: los cambios quedan sólo en este teléfono.';
    } else if (_subiendo) {
      texto = 'Subiendo a la nube…';
    } else if (_errorNube != null) {
      texto = _errorNube!;
      color = e.advertencia;
      accion = BotonSecundario(
        texto: 'Reintentar',
        compacto: true,
        alPresionar: _subir,
      );
    } else if (_ajustes.hayPendientes) {
      texto = 'Hay cambios sin subir a la nube.';
      color = e.advertencia;
      accion = BotonSecundario(
        texto: 'Subir ahora',
        compacto: true,
        alPresionar: _subir,
      );
    } else {
      texto = 'Todo guardado en la nube.';
      color = e.acento;
    }
    return Row(
      children: [
        Expanded(
          child: Text(texto, style: TipografiaApp.nota.copyWith(color: color)),
        ),
        if (accion != null) ...[
          const SizedBox(width: EspaciadoApp.chico),
          accion,
        ],
      ],
    );
  }

  /// Cuántas lecturas por segundo llegan de verdad de los beacons (lo mide
  /// la navegación). Con pocas, avisa que el límite está en los beacons.
  Widget _diagnosticoSenal(EstiloApp e) {
    final texto = _ajustes.diagnosticoSenal;
    final hora = _ajustes.diagnosticoSenalHora;
    if (texto == null || hora == null) {
      return Text(
        'Señal: sin medir (se mide cada 5 s navegando).',
        style: TipografiaApp.nota.copyWith(color: e.textoSecundario),
      );
    }
    final hace = DateTime.now().difference(hora).inSeconds;
    final lps = _ajustes.lecturasPorSegundo;
    final poca = lps != null && lps < 3;
    final color = poca ? e.advertencia : e.acento;
    return PanelRelieve(
      hundido: true,
      tamano: TamanoRelieve.chico,
      radio: FormasApp.bordeCampo,
      borde: BorderSide(color: color, width: FormasApp.grosorLinea),
      relleno: const EdgeInsets.all(EspaciadoApp.medio),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Señal ahora',
            style: TipografiaApp.nota.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: EspaciadoApp.minimo),
          Text(
            '$texto (hace $hace s)',
            style: TipografiaApp.conCifrasTabulares(
              TipografiaApp.nota,
            ).copyWith(color: e.textoPrincipal),
          ),
          if (poca)
            Padding(
              padding: const EdgeInsets.only(top: EspaciadoApp.minimo),
              child: Text(
                'Pocas lecturas: no se puede tener poco atraso y poco ruido '
                'a la vez. Configurar los beacons para emitir cada 100 a '
                '200 ms.',
                style: TipografiaApp.nota.copyWith(color: e.advertencia),
              ),
            ),
        ],
      ),
    );
  }

  /// Control de un parámetro en el alcance elegido: el valor, de qué capa
  /// sale y, si tiene uno propio en esa capa, cómo volver al de abajo.
  Widget _control(EstiloApp e, ParametroAjuste p) {
    final general = _alcance == _Alcance.general;
    final hayEdificio = _ajustes.edificioActual != null;
    final editable = general || (p.porEdificio && hayEdificio);
    final valor =
        _arrastre[p.clave] ?? (general ? _ajustes.valorGeneral(p) : p.valor);

    // De dónde sale el valor y cómo volver al de la capa de abajo.
    String origen;
    String? textoVolver;
    VoidCallback? volver;
    String? aviso;
    if (general) {
      if (_ajustes.generalCambiado(p)) {
        origen =
            'Cambiado para todos (el del código es '
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
      origen =
          'Cambiado en este edificio (el general es '
          '${p.formatear(_ajustes.valorGeneral(p))}).';
      textoVolver = 'Volver al valor general';
      volver = () => _ajustes.volverAlGeneral(p);
    } else {
      origen = 'Valor general.';
    }

    final pista = TipografiaApp.nota.copyWith(color: e.textoSecundario);
    return Padding(
      padding: const EdgeInsets.only(bottom: EspaciadoApp.margenLateral),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Deslizador(
            etiqueta: p.nombre,
            valor: valor,
            min: p.minimo,
            max: p.maximo,
            divisiones: p.divisiones,
            formato: p.formatear,
            formatoSemantico: p.hablado,
            ayuda: origen,
            alCambiar: editable
                ? (v) => setState(() => _arrastre[p.clave] = v)
                : null,
            alTerminar: editable
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
          if (aviso != null)
            Text(
              aviso,
              style: TipografiaApp.nota.copyWith(color: e.advertencia),
            ),
          if (volver != null)
            Padding(
              padding: const EdgeInsets.only(top: EspaciadoApp.minimo),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: BotonSecundario(
                  texto: textoVolver!,
                  compacto: true,
                  alPresionar: () {
                    setState(volver!);
                    _subir();
                  },
                ),
              ),
            ),
          Text(p.ayuda, style: pista),
        ],
      ),
    );
  }
}
