import 'dart:async';

import 'package:flutter/material.dart';

import 'ajustes_navegacion.dart' show ParametroAjuste;
import 'ajustes_voz.dart';
import 'tema.dart';
import 'voz_service.dart';

/// Ajustes de la voz en la app del usuario (ver [AjustesVoz]): velocidad,
/// volumen, tono y repetición de las indicaciones.
///
/// Cada cambio rige al instante y, cuando se deja de mover el control, se
/// escucha cómo quedó la voz. Está pensada para usarse con el lector de
/// pantalla: cada control se lee con su nombre y su valor, y se ajusta
/// deslizando hacia arriba o hacia abajo.
class PantallaAjustesVoz extends StatefulWidget {
  const PantallaAjustesVoz({super.key});

  @override
  State<PantallaAjustesVoz> createState() => _PantallaAjustesVozState();
}

class _PantallaAjustesVozState extends State<PantallaAjustesVoz> {
  final AjustesVoz _ajustes = AjustesVoz.instancia;
  final VozService _voz = VozService();

  bool _cargado = false;

  /// Espera después del último cambio antes de guardar y decir la frase de
  /// prueba. Con el lector de pantalla cada paso del control es un cambio:
  /// sin esta espera saldría una frase por paso.
  Timer? _prueba;

  @override
  void initState() {
    super.initState();
    _ajustes.cargar().then((_) {
      if (mounted) setState(() => _cargado = true);
    });
  }

  @override
  void dispose() {
    // Si se sale con un cambio sin guardar, se guarda igual.
    if (_prueba?.isActive ?? false) _ajustes.guardar();
    _prueba?.cancel();
    super.dispose();
  }

  void _cambiar(ParametroAjuste p, double v) {
    setState(() => _ajustes.cambiar(p, v));
    _prueba?.cancel();
    _prueba = Timer(const Duration(milliseconds: 700), () {
      _ajustes.guardar();
      _probar();
    });
  }

  Future<void> _probar() async {
    await _voz.aplicarAjustes();
    await _voz.hablar('Así suena la voz.');
  }

  Future<void> _deFabrica() async {
    _prueba?.cancel();
    await _ajustes.volverDeFabrica();
    if (!mounted) return;
    setState(() {});
    await _probar();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: TemaApp.tema,
      child: Scaffold(
        backgroundColor: TemaApp.fondo,
        appBar: AppBar(title: const Text('Ajustes de voz')),
        body: !_cargado
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final p in _ajustes.todos) _control(p),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: _probar,
                      icon: const Icon(Icons.record_voice_over_rounded),
                      label: const Text(
                        'Probar la voz',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: _deFabrica,
                      child: const Text(
                        'Volver a los valores de fábrica',
                        style: TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _control(ParametroAjuste p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El nombre y el valor los lee el lector de pantalla desde el
          // control: este texto queda sólo para la vista.
          ExcludeSemantics(
            child: Text(
              '${p.nombre}: ${p.formatear(p.valor)}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: TemaApp.textoBlanco,
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
              hint: p.ayuda,
              child: Slider(
                value: p.valor,
                min: p.minimo,
                max: p.maximo,
                divisions: p.divisiones,
                label: p.formatear(p.valor),
                semanticFormatterCallback: p.hablado,
                onChanged: (v) => _cambiar(p, v),
              ),
            ),
          ),
          ExcludeSemantics(
            child: Text(
              p.ayuda,
              style: const TextStyle(
                  fontSize: 15, color: TemaApp.textoSecundario),
            ),
          ),
        ],
      ),
    );
  }
}
