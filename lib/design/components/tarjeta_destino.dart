import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'cuadro_icono.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Tarjeta de destino
// ═══════════════════════════════════════════════════════════════════════════
//
// Un lugar para elegir de una lista (al elegir el destino): una tarjeta
// levantada (radio 20) con el ícono en un cuadro hundido, el nombre en texto
// principal (13,85) y, debajo, el piso y la distancia en texto secundario
// (9,10). Se elige una sola de la lista.
//
// ─── Elegida ───
// El borde pasa del gris de los controles al acento (8,75 sobre la
// superficie) y a la derecha aparece la tilde en acento; sin elegir, un
// círculo vacío en gris. Así el estado no depende sólo del color del borde.
// Presionada, se hunde.
//
// ─── Letra grande ───
// El cuadro del ícono (decorativo) no se muestra: el nombre se queda con el
// ancho.
//
// ─── TalkBack ───
// Se lee de una vez ("Aula 12, Piso 1 · a 25 m"), como una opción de un
// grupo en el que se elige una sola, elegida o no.

/// Tarjeta de un lugar que se elige como destino.
class TarjetaDestino extends StatelessWidget {
  const TarjetaDestino({
    super.key,
    required this.icono,
    required this.nombre,
    this.detalle,
    required this.seleccionada,
    required this.alTocar,
    this.detalleSemantico,
  });

  /// Ícono del cuadro (Icons.*_rounded): el rubro del lugar. Decorativo.
  final IconData icono;
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
            CuadroIcono(icono: icono),
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
          Icon(
            seleccionada
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: FormasApp.icono,
            color: seleccionada && habilitada ? e.acento : e.textoSecundario,
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
          return DecoratedBox(
            decoration: DecoracionRelieve(
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
          );
        },
      ),
    );
  }
}
