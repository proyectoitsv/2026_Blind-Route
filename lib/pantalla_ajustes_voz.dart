import 'dart:async';

import 'package:flutter/material.dart';

import 'ajustes_navegacion.dart' show ParametroAjuste;
import 'ajustes_voz.dart';
import 'design/design.dart';
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
    return AmbienteDiseno(
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: EstiloApp.de(context).fondo,
          appBar: const BarraSuperior(titulo: 'Ajustes de voz'),
          // Hasta leer lo guardado, nada: un instante, sin nada que gire.
          body: !_cargado
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    EspaciadoApp.margenLateral,
                    EspaciadoApp.margenLateral,
                    EspaciadoApp.margenLateral,
                    EspaciadoApp.entreSecciones,
                  ),
                  children: [
                    for (final p in _ajustes.todos) ...[
                      Deslizador(
                        etiqueta: p.nombre,
                        valor: p.valor,
                        min: p.minimo,
                        max: p.maximo,
                        divisiones: p.divisiones,
                        formato: p.formatear,
                        formatoSemantico: p.hablado,
                        ayuda: p.ayuda,
                        alCambiar: (v) => _cambiar(p, v),
                      ),
                      const SizedBox(height: EspaciadoApp.entreSecciones),
                    ],
                    BotonPrincipal(
                      texto: 'Probar la voz',
                      icono: Icons.record_voice_over_rounded,
                      alPresionar: _probar,
                    ),
                    const SizedBox(height: EspaciadoApp.medio),
                    BotonSecundario(
                      texto: 'Volver a los valores de fábrica',
                      expandido: true,
                      alPresionar: _deFabrica,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
