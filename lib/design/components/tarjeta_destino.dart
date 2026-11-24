// Tarjeta de destino
//
// Un lugar para elegir de una lista (al elegir el destino): una tarjeta
// levantada (radio 20) con el ícono en un cuadro hundido, el nombre en texto
// principal (15,84) y, debajo, el piso y la distancia en texto secundario
// (10,41). Se elige una sola de la lista.
//
// ─── Elegida ───
// El borde pasa del gris de los controles al acento (10,01 sobre la
// superficie) y a la derecha aparece la tilde en acento; sin elegir, un
// círculo vacío en gris. Así el estado no depende sólo del color del borde.
// Al elegirla, el borde cambia y la tilde aparece con un fundido, en 150 ms.
// Presionada, se hunde y se achica apenas (presion.dart).
//
// En lugar del cuadro del ícono puede ir otra cosa del mismo tamaño
// ([inicio]): un dispositivo Bluetooth encontrado lleva las barras de su
// señal (IndicadorSenal).
//
// ─── Letra grande ───
// El cuadro del ícono (decorativo) no se muestra: el nombre se queda con el
// ancho.
//
// ─── TalkBack ───
// Se lee de una vez ("Aula 12, Piso 1 · a 25 m"), como una opción de un
// grupo en el que se elige una sola, elegida o no.

import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../movimiento.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'cuadro_icono.dart';
import 'presion.dart';

/// Tarjeta de un lugar que se elige como destino.
class TarjetaDestino extends StatelessWidget {
  const TarjetaDestino({
    super.key,
    this.icono,
    this.inicio,
    required this.nombre,
    this.detalle,
    required this.seleccionada,
    required this.alTocar,
    this.detalleSemantico,
  }) : assert(icono != null || inicio != null);

  /// Ícono del cuadro (Icons.*_rounded): el rubro del lugar. Decorativo.
  final IconData? icono;

  /// Lo que va en lugar del cuadro del ícono, del mismo tamaño
  /// (FormasApp.cuadroIcono): las barras de la señal de un dispositivo, por
  /// ejemplo. Decorativo, como el ícono.
  final Widget? inicio;
  final String nombre;

  /// Piso y distancia ("Piso 1 · a 25 m").
  final String? detalle;
  final bool seleccionada;

  /// null: deshabilitada.
  final VoidCallback? alTocar;

  /// Cómo se dice el [detalle] ("Piso 1, a 25 metros"). Por defecto, como se
  /// ve.
  final String? detalleSemantico;

  /// Lo que lee TalkBack.
  String get textoSemantico =>
      [nombre, ?(detalleSemantico ?? detalle)].join(', ');

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final habilitada = alTocar != null;
    final letraGrande = TipografiaApp.esLetraGrande(context);

    final contenido = Padding(
      padding: EspaciadoApp.rellenoInternoTarjeta,
      child: Row(
        children: [
          if (!letraGrande) ...[
            inicio ?? CuadroIcono(icono: icono!),
            const SizedBox(width: EspaciadoApp.medio),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: TipografiaApp.destacado.copyWith(
                    color: habilitada ? e.textoPrincipal : e.textoSecundario,
                  ),
                ),
                if (detalle != null)
                  Text(
                    detalle!,
                    style: TipografiaApp.subtitulo.copyWith(
                      color: e.textoSecundario,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: EspaciadoApp.chico),
          AnimatedSwitcher(
            duration: MovimientoApp.duracion(context, MovimientoApp.seleccion),
            switchInCurve: MovimientoApp.curva,
            switchOutCurve: MovimientoApp.curva.flipped,
            child: Icon(
              seleccionada
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: ValueKey<bool>(seleccionada),
              size: FormasApp.icono,
              color: seleccionada && habilitada ? e.acento : e.textoSecundario,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: seleccionada,
      enabled: habilitada,
      inMutuallyExclusiveGroup: true,
      label: textoSemantico,
      onTap: alTocar,
      excludeSemantics: true,
      child: ConEstados(
        deshabilitado: !habilitada,
        constructor: (context, controlador, estados) {
          final presionado = estaPresionado(estados);
          final BorderSide borde;
          if (!habilitada) {
            borde = BorderSide(
              color: e.separador,
              width: FormasApp.grosorLinea,
            );
          } else if (estaEnfocado(estados)) {
            borde = BorderSide(color: e.acento, width: FormasApp.grosorFoco);
          } else {
            borde = BorderSide(
              color: seleccionada ? e.acento : e.borde,
              width: FormasApp.grosorLinea,
            );
          }
          return EscalaPresion(
            presionado: presionado,
            child: RelieveAnimado(
              presionado: presionado,
              decoracion: DecoracionRelieve(
                color: presionado ? e.hundido : e.superficie,
                radio: FormasApp.bordeTarjeta,
                elevacion: elevacionControl(estados),
                borde: borde,
                sombraOscura: e.sombraOscura,
                sombraClara: e.sombraClara,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: alTocar,
                  statesController: controlador,
                  customBorder: const RoundedRectangleBorder(
                    borderRadius: FormasApp.bordeTarjeta,
                  ),
                  overlayColor: sinCapa,
                  splashFactory: sinOnda,
                  child: contenido,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
