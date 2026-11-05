import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../tipografia.dart';
import 'botones.dart';
import 'hoja_inferior.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Confirmación
// ═══════════════════════════════════════════════════════════════════════════
//
// Antes de algo que no se deshace (quitar un mapa del teléfono, borrar): una
// hoja inferior (mostrarHoja, con su movimiento, el velo y el gesto para
// cerrarla) con el mensaje y dos botones, el de cancelar y el de la acción.
// Va en lugar del AlertDialog de Material, que TalkBack anuncia como
// "Dialog", en inglés: esta se nombra con su título.
//
// ─── Botones ───
// Una acción destructiva va en un botón secundario con el texto en rojo
// (5,31 sobre la superficie), nunca en cian; una que no lo es, en el botón
// principal. El de cancelar va primero (a la izquierda o arriba) y la acción
// después, uno al lado del otro o apilados si con letra grande no entran
// (FilaBotones). Sin el botón redondo de cerrar: el de cancelar ya lo es, y
// también volver o tocar afuera (que TalkBack anuncia como "Cerrar").
//
// Devuelve true sólo si se confirmó: cerrarla de cualquier otra forma es que
// no.

/// Pide que se confirme una acción: abre una hoja con [titulo] y [mensaje],
/// y los botones [cancelar] y [confirmar]. Devuelve si se confirmó.
Future<bool> mostrarConfirmacion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String confirmar,
  String cancelar = 'Cancelar',
  bool destructiva = false,
  IconData? iconoConfirmar,
}) async {
  final confirmado = await mostrarHoja<bool>(
    context,
    titulo: titulo,
    botonCerrar: false,
    contenido: (context) {
      final e = EstiloApp.de(context);
      void cerrar(bool valor) => Navigator.of(context).pop(valor);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            mensaje,
            style: TipografiaApp.cuerpo.copyWith(color: e.textoPrincipal),
          ),
          // Más aire que el alcance de la luz de los botones: ninguna sombra
          // cae sobre el texto.
          const SizedBox(height: EspaciadoApp.entreSecciones),
          FilaBotones(
            children: [
              BotonSecundario(
                texto: cancelar,
                alPresionar: () => cerrar(false),
              ),
              if (destructiva)
                BotonSecundario(
                  texto: confirmar,
                  icono: iconoConfirmar,
                  destructivo: true,
                  alPresionar: () => cerrar(true),
                )
              else
                BotonPrincipal(
                  texto: confirmar,
                  icono: iconoConfirmar,
                  expandido: false,
                  alPresionar: () => cerrar(true),
                ),
            ],
          ),
        ],
      );
    },
  );
  return confirmado ?? false;
}
