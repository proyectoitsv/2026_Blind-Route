import 'package:flutter/material.dart';

import 'design/design.dart';
import 'pantalla_ajustes_voz.dart';

/// Ajustes de la app del usuario: la voz, el movimiento y la vibración.
///
/// Es la primera pantalla de las apps con el sistema de diseño (fase 3 del
/// rediseño): va envuelta en AmbienteDiseno. Los ajustes de la voz siguen en
/// su pantalla (pantalla_ajustes_voz.dart, todavía sin migrar), que se abre
/// desde acá.
///
/// «Reducir movimiento» y «Vibración» son de cada persona y se guardan sólo
/// en el teléfono (AjustesMovimiento). Al prender la vibración, el teléfono
/// vibra una vez: así se sabe que anda (si la vibración al tocar está
/// apagada en el teléfono, puede que no vibre).
class PantallaAjustes extends StatelessWidget {
  const PantallaAjustes({super.key});

  @override
  Widget build(BuildContext context) {
    // Afuera del ambiente: lo que dice el teléfono, sin el ajuste propio.
    final telefonoSinAnimaciones =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AmbienteDiseno(
      child: Builder(
        builder: (context) {
          final e = EstiloApp.de(context);
          final ajustes = AjustesMovimiento.instancia;
          return Scaffold(
            backgroundColor: e.fondo,
            appBar: const BarraSuperior(titulo: 'Ajustes'),
            body: ListenableBuilder(
              listenable: ajustes,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(
                  EspaciadoApp.margenLateral,
                  EspaciadoApp.margenLateral,
                  EspaciadoApp.margenLateral,
                  EspaciadoApp.entreSecciones,
                ),
                children: [
                  GrupoFilas(
                    titulo: 'Voz',
                    filas: [
                      FilaGrupo(
                        icono: Icons.record_voice_over_rounded,
                        titulo: 'Ajustes de voz',
                        subtitulo: 'Velocidad, volumen, tono y repetición',
                        navega: true,
                        alTocar: () => Navigator.of(context).push(
                          RutaApp<void>(
                            builder: (_) => const PantallaAjustesVoz(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EspaciadoApp.entreSecciones),
                  GrupoFilas(
                    titulo: 'Movimiento y vibración',
                    pie: telefonoSinAnimaciones
                        ? '«Quitar animaciones» está prendido en el '
                              'teléfono: el movimiento ya está reducido.'
                        : null,
                    filas: [
                      FilaGrupo.interruptor(
                        icono: Icons.motion_photos_off_rounded,
                        titulo: 'Reducir movimiento',
                        subtitulo: 'Sin deslizamientos, escalas ni resortes',
                        valor: ajustes.reducirMovimiento,
                        alCambiar: ajustes.cambiarReducirMovimiento,
                      ),
                      FilaGrupo.interruptor(
                        icono: Icons.vibration_rounded,
                        titulo: 'Vibración',
                        subtitulo: 'Al doblar, al llegar y al cambiar de piso',
                        valor: ajustes.vibracion,
                        alCambiar: _cambiarVibracion,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Al prenderla, una vibración de prueba.
  static Future<void> _cambiarVibracion(bool valor) async {
    await AjustesMovimiento.instancia.cambiarVibracion(valor);
    if (valor) await HapticaApp.media();
  }
}
