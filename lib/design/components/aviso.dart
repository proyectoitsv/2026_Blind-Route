import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../tipografia.dart';
import 'panel_relieve.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Aviso
// ═══════════════════════════════════════════════════════════════════════════
//
// Un mensaje corto abajo de la pantalla, que se va solo ("Planta baja
// descargado", "Error al quitar: …"). Va en lugar del SnackBar de Material,
// con el estilo del editor con relieve: levantado en la superficie, con el
// borde de 1 px (lo separa de lo que pasa por detrás) y radio 20, a 16 dp de
// los costados. Un error lleva el ícono y el borde en rojo (5,31 sobre la
// superficie); el texto va siempre en el principal (13,85).
//
// ─── Cómo funciona ───
// Por dentro es un SnackBar transparente del ScaffoldMessenger, así se
// comporta como siempre: se encola, se va solo a los 4 s, se descarta
// deslizándolo hacia abajo y TalkBack lo lee al aparecer (región en vivo).
// Va sin recorte, para que se vea la sombra del relieve, y por eso tampoco se
// ve la animación de alto del SnackBar de Material 3: el aviso queda quieto
// en su lugar y aparece con un fundido corto (con TalkBack prendido, de una).
// Así no se mueve, con o sin «Reducir movimiento».
//
// ─── Sin textos de Material ───
// Sin el botón para cerrar del SnackBar, que TalkBack diría "Close", en
// inglés. Para descartarlo con TalkBack está la acción estándar del sistema.

/// Muestra [texto] en un aviso abajo de la pantalla. Con [error], lleva el
/// ícono y el borde en rojo.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> mostrarAviso(
  BuildContext context,
  String texto, {
  bool error = false,
}) {
  return ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      // La clave lleva el texto: el SnackBar la usa en el nombre de su Hero,
      // como hace con un Text.
      content: _Aviso(key: ValueKey<String>(texto), texto: texto, error: error),
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(
        EspaciadoApp.margenLateral,
        0,
        EspaciadoApp.margenLateral,
        EspaciadoApp.medio,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(),
      clipBehavior: Clip.none,
    ),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso({super.key, required this.texto, required this.error});

  final String texto;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return PanelRelieve(
      borde: BorderSide(
        color: error ? e.error : e.borde,
        width: FormasApp.grosorLinea,
      ),
      child: Row(
        children: [
          if (error) ...[
            ExcludeSemantics(
              child: Icon(
                Icons.error_rounded,
                size: FormasApp.icono,
                color: e.error,
              ),
            ),
            const SizedBox(width: EspaciadoApp.medio),
          ],
          Expanded(
            child: Text(
              texto,
              style: TipografiaApp.subtitulo.copyWith(color: e.textoPrincipal),
            ),
          ),
        ],
      ),
    );
  }
}
