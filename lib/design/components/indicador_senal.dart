// Indicador de señal
//
// La fuerza con que se oye un dispositivo Bluetooth, como las rayitas de
// señal del teléfono: cuatro barras de alto creciente en un cuadro hundido
// de 40 dp, el mismo lugar que ocupa el cuadro del ícono en una tarjeta. Las
// barras llenas van en acento y las demás en el color del separador. Así un
// dispositivo encontrado se distingue de las filas y los botones de
// alrededor, que llevan un ícono, y se ve de un vistazo cuál se oye más
// fuerte. Decorativo: el texto de al lado dice los dBm, así que TalkBack lo
// saltea.
//
// IndicadorSenal.barrasDe pasa de dBm a barras: −60 dBm o más, 4; desde −70,
// 3; desde −80, 2; más débil, 1.

import 'package:flutter/material.dart';

import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';

/// Cuadro hundido con las barras de la señal.
class IndicadorSenal extends StatelessWidget {
  const IndicadorSenal({super.key, required this.barras, this.apagado = false})
    : assert(barras >= 0 && barras <= total);

  /// Cuántas barras van llenas, de 0 a [total].
  final int barras;

  /// Las llenas en gris en vez de acento: un dispositivo que no se puede
  /// elegir (ya está en el plano).
  final bool apagado;

  static const int total = 4;

  /// Ancho de cada barra y alto de la más baja; las siguientes crecen de a
  /// ese mismo alto, hasta 20 dp, el lado del área de adentro del cuadro.
  static const double _ancho = 3;
  static const double _paso = 5;

  /// Las barras quedan a 10 dp del borde, lejos de la sombra interior, como
  /// el ícono de CuadroIcono.
  static const double _margen = 10;

  /// Las barras para una potencia de [dbm].
  static int barrasDe(int dbm) => dbm >= -60
      ? 4
      : dbm >= -70
      ? 3
      : dbm >= -80
      ? 2
      : 1;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final llena = apagado ? e.textoSecundario : e.acento;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: FormasApp.cuadroIcono,
        child: DecoratedBox(
          decoration: DecoracionRelieve(
            color: e.hundido,
            radio: FormasApp.bordeCampo,
            elevacion: -1,
            tamano: TamanoRelieve.chico,
            sombraOscura: e.sombraOscura,
            sombraClara: e.sombraClara,
          ),
          child: Padding(
            padding: const EdgeInsets.all(_margen),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < total; i++)
                  Container(
                    key: ValueKey<int>(i),
                    width: _ancho,
                    height: _paso * (i + 1),
                    decoration: BoxDecoration(
                      color: i < barras ? llena : e.separador,
                      borderRadius: BorderRadius.circular(_ancho / 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
