import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'linea_ruta.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Línea de tiempo de la ruta
// ═══════════════════════════════════════════════════════════════════════════
//
// La ruta como la línea de tiempo de un editor: una pista hundida (el
// relieve chico) con un segmento por tramo, las escaleras, los ascensores y
// el destino como marcas adentro de la pista, y un cabezal donde está el
// usuario. Va debajo del plano en la navegación. Es sólo visual: lo que se
// dice por voz no cambia.
//
// ─── Sin depender del color ───
// Cada tramo lleva su número arriba, y el estado se ve también por la forma:
//   hecho      verde, fino            (11,70 sobre lo hundido)
//   actual     acento, más grueso     (9,79)
//   siguiente  violeta, punteado      (7,24)
// Las marcas llevan su ícono en texto principal (15,50).
//
// ─── Cabezal ───
// Un botón redondo levantado con un anillo de acento de 2 dp, adentro de la
// pista, sobre el tramo actual. El número de arriba queda a 8 dp de la
// pista: la sombra del cabezal no le llega.
//
// ─── Ancho ───
// Cada tramo ocupa un ancho proporcional a sus metros, con un mínimo para
// que entre su número (crece con la letra). Si ni así entran, todos miden lo
// mismo.
//
// ─── TalkBack ───
// Se lee de una vez, como un resumen: "Tramo 2 de 3, 8 metros, escalera al
// piso 2". Debajo puede ir lo mismo escrito, para quien ve, en dos renglones:
// "Tramo 2 de 3 · faltan 8 m" y "Escalera al piso 2". Si al lado ya hay una
// línea de ruta que dice lo mismo, conviene sacarla de TalkBack
// (ExcludeSemantics) para no repetir.

/// La ruta como una línea de tiempo.
class LineaTiempo extends StatelessWidget {
  const LineaTiempo({
    super.key,
    required this.tramos,
    required this.tramoActual,
    this.avance = 0,
    this.mostrarNumeros = true,
    this.mostrarResumen = true,
  });

  final List<TramoRuta> tramos;

  /// Índice del tramo en el que está el usuario (0 = el primero).
  final int tramoActual;

  /// Cuánto del tramo actual ya se recorrió, de 0 a 1: ahí va el cabezal.
  final double avance;

  /// Si escribe el número de cada tramo arriba de la pista.
  final bool mostrarNumeros;

  /// Si escribe el resumen debajo de la pista.
  final bool mostrarResumen;

  Recorrido get _recorrido =>
      Recorrido(tramos: tramos, tramoActual: tramoActual, avance: avance);

  /// Lo que lee TalkBack.
  String get resumen => _recorrido.resumen;

  /// Aire a los costados, adentro de la pista: las puntas redondas del
  /// segmento más grueso quedan adentro de las de la pista.
  static const double _margenPista =
      (FormasApp.pistaTiempo - FormasApp.segmentoTiempoActual) / 2;

  /// El ancho de cada tramo, proporcional a sus metros, con [minimo] para
  /// cada uno. Si ni con el mínimo entran en [disponible], todos iguales.
  static List<double> anchosDeTramos(
    List<double> metros,
    double disponible,
    double minimo,
  ) {
    final n = metros.length;
    if (n == 0) return const [];
    final espacio = math.max(0.0, disponible);
    if (minimo * n >= espacio) return List.filled(n, espacio / n);
    final anchos = List<double>.filled(n, 0);
    final fijos = <int>{};
    // Los que no llegan al mínimo quedan en el mínimo; lo que sobra se
    // reparte en proporción entre los demás, hasta que ninguno cambie.
    var cambio = true;
    while (cambio) {
      cambio = false;
      final libres = [
        for (var i = 0; i < n; i++)
          if (!fijos.contains(i)) i,
      ];
      final resto = espacio - fijos.length * minimo;
      final metrosLibres = libres.fold(0.0, (s, i) => s + metros[i]);
      for (final i in libres) {
        final ancho = metrosLibres <= 0
            ? resto / libres.length
            : resto * metros[i] / metrosLibres;
        if (ancho < minimo) {
          fijos.add(i);
          cambio = true;
        }
        anchos[i] = ancho;
      }
    }
    for (final i in fijos) {
      anchos[i] = minimo;
    }
    return anchos;
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final escala = TipografiaApp.escalaTexto(context);
    final r = _recorrido;
    final actual = r.actual;

    final linea = LayoutBuilder(
      builder: (context, restricciones) {
        // Lo fijo de la fila: el lugar de las marcas y los huecos entre
        // segmentos.
        var fijo = 0.0;
        for (var i = 0; i < tramos.length; i++) {
          final ultimo = i == tramos.length - 1;
          if (tramos[i].marca != null) {
            fijo += FormasApp.pistaTiempo;
          } else if (!ultimo) {
            fijo += EspaciadoApp.minimo;
          }
        }
        final anchos = anchosDeTramos(
          [for (final t in tramos) t.metros],
          restricciones.maxWidth - 2 * _margenPista - fijo,
          FormasApp.anchoMinimoTramo * math.max(1.0, escala),
        );

        // Las dos filas, con las mismas piezas del mismo ancho: arriba los
        // números, abajo la pista.
        final numeros = <Widget>[];
        final piezas = <Widget>[];
        void hueco(double ancho) {
          numeros.add(SizedBox(width: ancho));
          piezas.add(SizedBox(width: ancho));
        }

        for (var i = 0; i < tramos.length; i++) {
          numeros.add(
            SizedBox(
              width: anchos[i],
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${i + 1}',
                    maxLines: 1,
                    softWrap: false,
                    style: TipografiaApp.conCifrasTabulares(
                      TipografiaApp.leyenda.copyWith(
                        color: i == actual
                            ? e.textoPrincipal
                            : e.textoSecundario,
                        fontWeight: i == actual
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          piezas.add(
            _Segmento(
              ancho: anchos[i],
              estado: r.estadoDe(i),
              avance: r.avanceAcotado,
              estilo: e,
            ),
          );
          final marca = tramos[i].marca;
          if (marca != null) {
            numeros.add(const SizedBox(width: FormasApp.pistaTiempo));
            piezas.add(_Marca(marca: marca, estilo: e));
          } else if (i < tramos.length - 1) {
            hueco(EspaciadoApp.minimo);
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mostrarNumeros) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _margenPista),
                child: Row(children: numeros),
              ),
              const SizedBox(height: EspaciadoApp.chico),
            ],
            DecoratedBox(
              decoration: DecoracionRelieve(
                color: e.hundido,
                pildora: true,
                elevacion: -1,
                tamano: TamanoRelieve.chico,
                sombraOscura: e.sombraOscura,
                sombraClara: e.sombraClara,
              ),
              child: SizedBox(
                height: FormasApp.pistaTiempo,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _margenPista),
                  child: Row(children: piezas),
                ),
              ),
            ),
          ],
        );
      },
    );

    return Semantics(
      container: true,
      label: resumen,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          linea,
          // Dos renglones fijos (el tramo y lo que falta; lo que hay al
          // final), así un renglón largo no deja una palabra sola abajo.
          if (mostrarResumen && tramos.isNotEmpty) ...[
            const SizedBox(height: EspaciadoApp.medio),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Tramo ${actual + 1} de ${tramos.length}',
                    style: TextStyle(
                      color: e.textoPrincipal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Espacios que no se parten: con letra grande, "faltan
                  // 4 m" baja entero al renglón de abajo.
                  TextSpan(
                    text: r.metrosQueFaltan == 1
                        ? ' · falta 1 m'
                        : ' · faltan ${r.metrosQueFaltan} m',
                  ),
                ],
              ),
              style: TipografiaApp.conCifrasTabulares(
                TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
              ),
            ),
            if (tramos[actual].textoMarca case final marca?)
              Text(
                marca.isEmpty
                    ? marca
                    : marca[0].toUpperCase() + marca.substring(1),
                style: TipografiaApp.subtitulo.copyWith(
                  color: e.textoSecundario,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Un segmento de la pista y, si es el actual, el cabezal encima.
class _Segmento extends StatelessWidget {
  const _Segmento({
    required this.ancho,
    required this.estado,
    required this.avance,
    required this.estilo,
  });

  final double ancho;
  final EstadoTramo estado;
  final double avance;
  final EstiloApp estilo;

  @override
  Widget build(BuildContext context) {
    final actual = estado == EstadoTramo.actual;
    const lado = FormasApp.cabezalTiempo;
    const radio = lado / 2;
    // El cabezal no se sale del tramo: en los extremos queda contra el
    // borde.
    final centro = ancho <= lado
        ? ancho / 2
        : (ancho * avance).clamp(radio, ancho - radio);
    return SizedBox(
      width: ancho,
      height: FormasApp.pistaTiempo,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: ancho,
            height: actual
                ? FormasApp.segmentoTiempoActual
                : FormasApp.segmentoTiempo,
            child: CustomPaint(
              painter: _PintorSegmento(
                color: switch (estado) {
                  EstadoTramo.hecho => estilo.hecho,
                  EstadoTramo.actual => estilo.acento,
                  EstadoTramo.siguiente => estilo.siguiente,
                },
                punteado: estado == EstadoTramo.siguiente,
              ),
            ),
          ),
          if (actual)
            PositionedDirectional(
              start: centro - radio,
              top: (FormasApp.pistaTiempo - lado) / 2,
              child: SizedBox.square(
                dimension: lado,
                child: DecoratedBox(
                  decoration: DecoracionRelieve(
                    color: estilo.superficie,
                    circulo: true,
                    tamano: TamanoRelieve.chico,
                    borde: BorderSide(
                      color: estilo.acento,
                      width: FormasApp.anilloCabezalTiempo,
                    ),
                    sombraOscura: estilo.sombraOscura,
                    sombraClara: estilo.sombraClara,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PintorSegmento extends CustomPainter {
  const _PintorSegmento({required this.color, required this.punteado});

  final Color color;
  final bool punteado;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final pintura = Paint()..color = color;
    final radio = Radius.circular(size.height / 2);
    if (!punteado) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, radio),
        pintura,
      );
      return;
    }
    // Guiones del largo de la ruta del plano, con las puntas redondas.
    const guion = FormasApp.guionRuta + 2;
    const hueco = FormasApp.huecoRuta;
    for (var x = 0.0; x < size.width; x += guion + hueco) {
      final ancho = math.min(guion, size.width - x);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, ancho, size.height), radio),
        pintura,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorSegmento anterior) =>
      anterior.color != color || anterior.punteado != punteado;
}

/// Lugar de una escalera, un ascensor o el destino adentro de la pista: el
/// ícono en texto principal.
class _Marca extends StatelessWidget {
  const _Marca({required this.marca, required this.estilo});

  final MarcaTramo marca;
  final EstiloApp estilo;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: FormasApp.pistaTiempo,
      child: Center(
        child: Icon(
          marca.icono,
          size: FormasApp.iconoChico,
          color: estilo.textoPrincipal,
        ),
      ),
    );
  }
}
