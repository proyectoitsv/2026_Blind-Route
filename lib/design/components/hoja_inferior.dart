import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tema_blindroute.dart';
import '../tipografia.dart';
import 'botones.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Hoja inferior
// ═══════════════════════════════════════════════════════════════════════════
//
// Para cargas rápidas (un nombre, una opción) sin cambiar de pantalla: una
// superficie levantada, con las esquinas de arriba de radio 24, la manija
// hundida (con borde, 3,94 sobre la superficie), un título y el botón
// redondo para cerrar. El relieve lo pinta la hoja misma: la hoja de
// Material va transparente y sin recorte, así la luz de arriba se ve.
//
// ─── Tema ───
// Si el contexto desde el que se abre no tiene el sistema de diseño (una
// pantalla vieja, o uno por encima del Theme de la pantalla), la hoja se arma
// con TemaBlindRoute.oscuro.
//
// ─── TalkBack ───
// La manija es decorativa (la de Material diría "Dismiss" en inglés). Para
// cerrar están el botón "Cerrar", el gesto de volver y tocar afuera, que
// TalkBack también anuncia como "Cerrar". El título es un encabezado.
//
// ─── Letra grande y teclado ───
// Si el contenido no entra, se desplaza. Con el teclado abierto, la hoja
// sube para que el campo quede a la vista.

/// Abre una hoja inferior con [titulo] y lo que arme [contenido]. Devuelve
/// lo que se le pase a Navigator.pop al cerrarla.
Future<T?> mostrarHoja<T>(
  BuildContext context, {
  required String titulo,
  required WidgetBuilder contenido,
  bool botonCerrar = true,
}) {
  final conSistema = Theme.of(context).extension<EstiloApp>() != null;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    clipBehavior: Clip.none,
    showDragHandle: false,
    barrierLabel: 'Cerrar',
    builder: (context) {
      final hoja = _Hoja(
        titulo: titulo,
        contenido: contenido,
        botonCerrar: botonCerrar,
      );
      return conSistema
          ? hoja
          : Theme(data: TemaBlindRoute.oscuro, child: hoja);
    },
  );
}

class _Hoja extends StatelessWidget {
  const _Hoja({
    required this.titulo,
    required this.contenido,
    required this.botonCerrar,
  });

  final String titulo;
  final WidgetBuilder contenido;
  final bool botonCerrar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final manija = FormasApp.manijaHoja;
    return DecoratedBox(
      decoration: DecoracionRelieve(
        color: e.superficie,
        radio: FormasApp.bordeHoja,
        sombraOscura: e.sombraOscura,
        sombraClara: e.sombraClara,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: EspaciadoApp.medio,
                    bottom: EspaciadoApp.minimo,
                  ),
                  child: Center(
                    child: SizedBox.fromSize(
                      size: manija,
                      child: DecoratedBox(
                        decoration: DecoracionRelieve(
                          color: e.hundido,
                          pildora: true,
                          elevacion: -1,
                          tamano: TamanoRelieve.chico,
                          borde: BorderSide(
                            color: e.borde,
                            width: FormasApp.grosorLinea,
                          ),
                          sombraOscura: e.sombraOscura,
                          sombraClara: e.sombraClara,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: EspaciadoApp.margenLateral,
                  end: EspaciadoApp.minimo,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          titulo,
                          style: TipografiaApp.titulo.copyWith(
                            color: e.textoPrincipal,
                          ),
                        ),
                      ),
                    ),
                    if (botonCerrar)
                      BotonRedondo(
                        icono: Icons.close_rounded,
                        etiqueta: 'Cerrar',
                        alPresionar: () => Navigator.of(context).pop(),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    EspaciadoApp.margenLateral,
                    EspaciadoApp.chico,
                    EspaciadoApp.margenLateral,
                    EspaciadoApp.margenLateral,
                  ),
                  child: Builder(builder: contenido),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
