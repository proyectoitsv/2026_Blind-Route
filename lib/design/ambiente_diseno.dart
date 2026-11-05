import 'package:flutter/material.dart';

import 'ajustes_movimiento.dart';
import 'tema_blindroute.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Ambiente del sistema de diseño
// ═══════════════════════════════════════════════════════════════════════════
//
// El envoltorio de una pantalla migrada (y de la galería y las hojas): pone
// el tema nuevo (TemaBlindRoute.oscuro) y suma «Reducir movimiento» de
// Ajustes a «Quitar animaciones» del teléfono en el MediaQuery
// (disableAnimations). Así los componentes preguntan sólo
// MovimientoApp.reducido y, cuando el ajuste cambia, lo de abajo se vuelve a
// armar al instante.
//
// Va en cada pantalla porque los entrypoints (main_user.dart y
// main_admin.dart) no se tocan: su MaterialApp sigue con el tema de antes.
// Una pantalla nueva se abre con RutaApp (transiciones.dart); una hoja, con
// mostrarHoja, que ya la envuelve.
//
//   return AmbienteDiseno(
//     child: Scaffold(...),
//   );
class AmbienteDiseno extends StatelessWidget {
  const AmbienteDiseno({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ajustes = AjustesMovimiento.instancia;
    return ListenableBuilder(
      listenable: ajustes,
      child: Theme(data: TemaBlindRoute.oscuro, child: child),
      builder: (context, hijo) {
        final datos = MediaQuery.of(context);
        // Siempre el mismo MediaQuery (aunque no cambie nada): si se sacara,
        // lo de abajo se armaría de cero y perdería su estado.
        return MediaQuery(
          data: datos.copyWith(
            disableAnimations:
                datos.disableAnimations || ajustes.reducirMovimiento,
          ),
          child: hijo!,
        );
      },
    );
  }
}
