import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Panel con relieve
// ═══════════════════════════════════════════════════════════════════════════
//
// Un panel levantado (una tarjeta, la instrucción de la navegación) o hundido
// (el plano, una pista). Es la pieza con la que se arman los componentes y,
// en la fase 5, los paneles de las pantallas.
//
// ─── Lo hundido con contenido que tapa el relleno ───
// Si el contenido pinta encima de todo el panel (el plano), la sombra
// interior tiene que caer sobre el contenido, no debajo: con sombraEncima,
// el relleno va detrás y la sombra interior y el borde, delante. Para un
// contenido con texto no se usa: el texto nunca va bajo una sombra.

/// Panel con relieve: levantado (por defecto) o [hundido].
class PanelRelieve extends StatelessWidget {
  const PanelRelieve({
    super.key,
    required this.child,
    this.hundido = false,
    this.tamano = TamanoRelieve.comun,
    this.color,
    this.radio = FormasApp.bordeTarjeta,
    this.borde,
    this.relleno = EspaciadoApp.rellenoInternoTarjeta,
    this.recortar = false,
    this.sombraEncima = false,
  });

  final Widget child;

  /// Hundido (sombras por dentro) en lugar de levantado.
  final bool hundido;
  final TamanoRelieve tamano;

  /// Relleno. Por defecto, la superficie (levantado) o el color de lo
  /// hundido.
  final Color? color;
  final BorderRadiusGeometry radio;

  /// Borde de 1 px: lo lleva el panel que se toca o que contiene controles.
  final BorderSide? borde;

  /// Relleno interno, entre el borde y el contenido.
  final EdgeInsetsGeometry relleno;

  /// Recorta el contenido a la forma del panel.
  final bool recortar;

  /// Pinta la sombra interior y el borde encima del contenido (ver arriba).
  /// Recorta el contenido.
  final bool sombraEncima;

  /// La decoración del panel.
  static DecoracionRelieve decoracion(
    EstiloApp e, {
    bool hundido = false,
    TamanoRelieve tamano = TamanoRelieve.comun,
    Color? color,
    BorderRadiusGeometry radio = FormasApp.bordeTarjeta,
    BorderSide? borde,
  }) => DecoracionRelieve(
    color: color ?? (hundido ? e.hundido : e.superficie),
    radio: radio,
    elevacion: hundido ? -1 : 1,
    tamano: tamano,
    borde: borde ?? BorderSide.none,
    sombraOscura: e.sombraOscura,
    sombraClara: e.sombraClara,
  );

  @override
  Widget build(BuildContext context) {
    final deco = decoracion(
      EstiloApp.de(context),
      hundido: hundido,
      tamano: tamano,
      color: color,
      radio: radio,
      borde: borde,
    );
    Widget contenido = Padding(padding: relleno, child: child);
    if (recortar || sombraEncima) {
      contenido = ClipRRect(borderRadius: radio, child: contenido);
    }
    if (!sombraEncima) {
      return DecoratedBox(decoration: deco, child: contenido);
    }
    return DecoratedBox(
      decoration: deco.copyWith(parte: ParteRelieve.fondo),
      child: DecoratedBox(
        decoration: deco.copyWith(parte: ParteRelieve.frente),
        position: DecorationPosition.foreground,
        child: contenido,
      ),
    );
  }
}
