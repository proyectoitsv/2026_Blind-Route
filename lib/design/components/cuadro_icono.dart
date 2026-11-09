import 'package:flutter/material.dart';

import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Cuadro con ícono
// ═══════════════════════════════════════════════════════════════════════════
//
// Un cuadro hundido de 40 dp (radio 12, el relieve chico) con el ícono chico
// en acento adentro, como las herramientas de un editor. Es el ícono de una
// tarjeta de dato, de una fila y de una tarjeta de destino. Decorativo: el
// texto de al lado dice lo mismo, así que TalkBack lo saltea.
//
// Contraste del ícono sobre el relleno hundido: acento 9,79 · error 5,94 ·
// texto principal 15,50. El ícono queda a 10 dp del borde, lejos de la
// sombra interior (llega a 6).

/// Cuadro hundido con un ícono adentro.
class CuadroIcono extends StatelessWidget {
  const CuadroIcono({
    super.key,
    required this.icono,
    this.color,
    this.lado = FormasApp.cuadroIcono,
    this.tamanoIcono = FormasApp.iconoChico,
  });

  /// Icons.*_rounded.
  final IconData icono;

  /// Color del ícono. Por defecto, el acento; en lo destructivo, el error.
  final Color? color;

  /// El lado del cuadro y el tamaño del ícono: los comunes, salvo donde el
  /// ícono se tiene que ver de lejos (la indicación de la navegación).
  final double lado;
  final double tamanoIcono;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: lado,
        child: DecoratedBox(
          decoration: DecoracionRelieve(
            color: e.hundido,
            radio: FormasApp.bordeCampo,
            elevacion: -1,
            tamano: TamanoRelieve.chico,
            sombraOscura: e.sombraOscura,
            sombraClara: e.sombraClara,
          ),
          child: Center(
            child: Icon(icono, size: tamanoIcono, color: color ?? e.acento),
          ),
        ),
      ),
    );
  }
}
