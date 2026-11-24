// Bandeja hundida
//
// Una lista que tiene que distinguirse de los controles que la rodean (los
// dispositivos que encontró el escáner, debajo del escáner y del filtro): un
// hueco hundido, más oscuro que la superficie (radio 20, el relieve común
// hacia adentro), con su título arriba y las tarjetas levantadas adentro,
// como piezas en un cajón. Los controles de alrededor van levantados, así que
// la diferencia es de textura y no sólo de color.
//
// Es un sliver, para ir entre los de una CustomScrollView: la lista adentro
// sigue siendo perezosa (se arman sólo las tarjetas que se ven) y la bandeja
// se pinta detrás (DecoratedSliver), también a medio desplazar.
//
// ─── TalkBack ───
// El título es un encabezado, para saltar directo a la lista. El ícono es
// decorativo.

import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';

/// Bandeja hundida con un título y [cantidad] elementos que arma
/// [constructor].
class BandejaHundida extends StatelessWidget {
  const BandejaHundida({
    super.key,
    required this.titulo,
    required this.cantidad,
    required this.constructor,
    this.icono,
  });

  final String titulo;

  /// Ícono del título (Icons.*_rounded), en acento. Decorativo.
  final IconData? icono;

  final int cantidad;
  final IndexedWidgetBuilder constructor;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final encabezado = Padding(
      padding: const EdgeInsets.fromLTRB(
        EspaciadoApp.minimo,
        EspaciadoApp.minimo,
        EspaciadoApp.minimo,
        EspaciadoApp.medio,
      ),
      child: Row(
        children: [
          if (icono != null) ...[
            ExcludeSemantics(
              child: Icon(icono, size: FormasApp.iconoChico, color: e.acento),
            ),
            const SizedBox(width: EspaciadoApp.chico),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                titulo,
                style: TipografiaApp.destacado.copyWith(
                  color: e.textoPrincipal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return DecoratedSliver(
      decoration: DecoracionRelieve(
        color: e.hundido,
        radio: FormasApp.bordeTarjeta,
        elevacion: -1,
        sombraOscura: e.sombraOscura,
        sombraClara: e.sombraClara,
      ),
      // El relleno deja las tarjetas lejos del borde, fuera de la sombra
      // interior.
      sliver: SliverPadding(
        padding: const EdgeInsets.all(EspaciadoApp.medio),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: encabezado),
            SliverList.separated(
              itemCount: cantidad,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: EspaciadoApp.chico),
              itemBuilder: constructor,
            ),
          ],
        ),
      ),
    );
  }
}
