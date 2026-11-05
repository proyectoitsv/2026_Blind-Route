import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../tipografia.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Estado de una pantalla
// ═══════════════════════════════════════════════════════════════════════════
//
// Lo que va en lugar del contenido cuando no hay nada para mostrar (una lista
// vacía, una búsqueda sin resultados), cuando algo falló (sin conexión) o
// mientras se espera: un ícono grande en gris, el título, una aclaración y,
// si hace falta, un botón ("Reintentar"). Va centrado sobre el fondo, sin
// relieve: no es un control.
//
// ─── Esperas ───
// Sin nada que gire: la v5 no quiere animaciones que se repitan. El título
// dice qué se espera ("Cargando mapas…") y el ícono es un reloj de arena
// quieto.
//
// ─── TalkBack ───
// El título y la aclaración se leen juntos y se anuncian al aparecer (región
// en vivo): quien busca un mapa por nombre se entera de que no hay
// resultados sin tener que ir a buscarlo. El ícono es decorativo. El botón,
// aparte, después.
//
// ─── Letra grande ───
// El texto se parte en renglones y crece hacia abajo. Si no entra en la
// pantalla, quien lo usa lo pone en algo que se desplace.

/// Un estado de pantalla: vacía, con un error o esperando.
class EstadoPantalla extends StatelessWidget {
  const EstadoPantalla({
    super.key,
    required this.icono,
    required this.titulo,
    this.detalle,
    this.accion,
  });

  /// Icons.*_rounded. Decorativo.
  final IconData icono;
  final String titulo;

  /// Aclaración debajo del título, en gris.
  final String? detalle;

  /// Un botón debajo, en general un BotonSecundario ("Reintentar").
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: EspaciadoApp.margenLateral,
        vertical: EspaciadoApp.entreSecciones,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Icon(
              icono,
              size: FormasApp.iconoGrande,
              color: e.textoSecundario,
            ),
          ),
          const SizedBox(height: EspaciadoApp.margenLateral),
          MergeSemantics(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: TipografiaApp.tituloSeccion.copyWith(
                      color: e.textoPrincipal,
                    ),
                  ),
                  if (detalle != null) ...[
                    const SizedBox(height: EspaciadoApp.chico),
                    Text(
                      detalle!,
                      textAlign: TextAlign.center,
                      style: TipografiaApp.subtitulo.copyWith(
                        color: e.textoSecundario,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (accion != null) ...[
            // Más aire que el alcance de la luz del botón: ninguna sombra cae
            // sobre el texto.
            const SizedBox(height: EspaciadoApp.entreSecciones),
            Center(child: accion!),
          ],
        ],
      ),
    );
  }
}
