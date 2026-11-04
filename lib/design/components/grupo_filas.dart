import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'cuadro_icono.dart';
import 'panel_relieve.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Encabezado de sección y grupo de filas
// ═══════════════════════════════════════════════════════════════════════════
//
// Un grupo de filas es una tarjeta levantada (radio 20) con filas de 52 dp
// como mínimo, separadas por una línea fina (el separador, decorativo) que
// arranca donde arranca el texto, no en el borde. Cada fila lleva su ícono en
// un cuadro hundido. Si alguna fila se toca, la tarjeta lleva el borde de
// 1 px de los controles. Una fila que lleva a otra pantalla termina en una
// flecha gris. Presionada, la fila se hunde.
//
// ─── Letra grande ───
// Las filas crecen con el texto, que se parte en renglones. Desde
// TipografiaApp.esLetraGrande, el título se queda con todo el ancho: el
// cuadro del ícono (decorativo) no se muestra, y el valor y el interruptor
// bajan debajo del título. Así, aun con la letra al 200 %, las palabras
// largas ("Configuración", "animaciones") no se parten a la mitad. La acción
// de un encabezado de sección también baja.
//
// ─── TalkBack ───
// Cada fila se lee de una vez ("Velocidad de la voz, 100 %, botón") y el
// título de la sección es un encabezado, para saltar de sección en sección.

/// Título de una sección de la pantalla (20, semibold), con una acción
/// opcional a la derecha. TalkBack lo anuncia como encabezado.
class EncabezadoSeccion extends StatelessWidget {
  const EncabezadoSeccion({super.key, required this.titulo, this.accion});

  final String titulo;

  /// Por ejemplo, un BotonSecundario compacto ("Ver todos").
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final texto = Semantics(
      header: true,
      child: Text(
        titulo,
        style: TipografiaApp.tituloSeccion.copyWith(color: e.textoPrincipal),
      ),
    );
    if (accion == null) return texto;
    if (TipografiaApp.esLetraGrande(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          texto,
          const SizedBox(height: EspaciadoApp.chico),
          accion!,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: texto),
        const SizedBox(width: EspaciadoApp.chico),
        accion!,
      ],
    );
  }
}

/// Tarjeta con filas. Las filas suelen ser [FilaGrupo]; otra cosa también
/// entra, y el separador debajo arranca en el margen de la tarjeta.
class GrupoFilas extends StatelessWidget {
  const GrupoFilas({super.key, this.titulo, this.pie, required this.filas});

  /// Encabezado de la sección, arriba de la tarjeta.
  final String? titulo;

  /// Aclaración al pie, debajo de la tarjeta (13, gris).
  final String? pie;
  final List<Widget> filas;

  /// Si alguna fila se toca: entonces la tarjeta lleva el borde.
  bool get _conControles =>
      filas.any((f) => f is FilaGrupo && f.alTocar != null);

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final letraGrande = TipografiaApp.esLetraGrande(context);
    final contenido = <Widget>[];
    for (var i = 0; i < filas.length; i++) {
      final fila = filas[i];
      contenido.add(fila);
      if (i < filas.length - 1) {
        contenido.add(
          Divider(
            height: FormasApp.grosorLinea,
            thickness: FormasApp.grosorLinea,
            color: e.separador,
            indent: fila is FilaGrupo
                ? fila.inicioTexto(letraGrande: letraGrande)
                : EspaciadoApp.rellenoTarjeta,
          ),
        );
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Más aire que el alcance de la luz de la tarjeta: ninguna sombra
        // cae sobre el texto del encabezado ni del pie.
        if (titulo != null) ...[
          EncabezadoSeccion(titulo: titulo!),
          const SizedBox(height: EspaciadoApp.medio),
        ],
        // El borde va encima de las filas: una fila presionada (hundida) no
        // lo tapa.
        PanelRelieve(
          relleno: EdgeInsets.zero,
          sombraEncima: true,
          borde: _conControles
              ? BorderSide(color: e.borde, width: FormasApp.grosorLinea)
              : null,
          child: Column(mainAxisSize: MainAxisSize.min, children: contenido),
        ),
        if (pie != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              EspaciadoApp.rellenoTarjeta,
              EspaciadoApp.medio,
              EspaciadoApp.rellenoTarjeta,
              0,
            ),
            child: Text(
              pie!,
              style: TipografiaApp.nota.copyWith(color: e.textoSecundario),
            ),
          ),
      ],
    );
  }
}

/// Fila de un [GrupoFilas]: título y, opcionales, ícono, subtítulo, valor a
/// la derecha, un accesorio (un interruptor) y la flecha si navega.
///
/// El ícono va en un cuadro hundido ([CuadroIcono]: el acento encima da
/// 9,79). Una fila [destructiva] ("Borrar todas") va con el título en el
/// color de error (5,31 sobre la superficie, 5,94 hundida) y el ícono
/// también.
class FilaGrupo extends StatelessWidget {
  const FilaGrupo({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.valor,
    this.icono,
    this.inicio,
    this.accesorio,
    this.navega = false,
    this.destructiva = false,
    this.alTocar,
  });

  /// Fila con un interruptor: toda la fila lo prende y lo apaga, y TalkBack
  /// la lee como un interruptor ("Vibrar al llegar, activado").
  FilaGrupo.interruptor({
    Key? key,
    required String titulo,
    String? subtitulo,
    IconData? icono,
    required bool valor,
    required ValueChanged<bool>? alCambiar,
  }) : this(
         key: key,
         titulo: titulo,
         subtitulo: subtitulo,
         icono: icono,
         accesorio: _Interruptor(valor: valor, alCambiar: alCambiar),
         alTocar: alCambiar == null ? null : () => alCambiar(!valor),
       );

  final String titulo;

  /// Segunda línea, en gris.
  final String? subtitulo;

  /// Dato a la derecha, en gris ("100 %", "3 pisos"). Corto: ocupa hasta
  /// el 40 % del ancho y, si no entra, se parte en renglones.
  final String? valor;

  /// Ícono del cuadro (Icons.*_rounded).
  final IconData? icono;

  /// Lo que va en lugar del cuadro del ícono (una muestra de color, por
  /// ejemplo). Se acomoda en el mismo lugar: un cuadrado de
  /// FormasApp.cuadroIcono.
  final Widget? inicio;

  /// Control a la derecha, antes de la flecha.
  final Widget? accesorio;

  /// Si lleva a otra pantalla: muestra la flecha gris.
  final bool navega;
  final bool destructiva;

  /// null: la fila no se toca (sólo muestra).
  final VoidCallback? alTocar;

  /// Hasta qué parte del ancho de la pantalla puede ocupar el [valor] a la
  /// derecha: el resto queda para el título.
  static const double _fraccionValor = 0.4;

  bool get _conCuadro => icono != null || inicio != null;

  /// Dónde arranca el texto, desde el borde de la tarjeta: ahí arranca el
  /// separador de abajo. Con letra grande no hay cuadro de ícono.
  double inicioTexto({required bool letraGrande}) =>
      EspaciadoApp.rellenoTarjeta +
      (_conCuadro && !letraGrande
          ? FormasApp.cuadroIcono + EspaciadoApp.medio
          : 0);

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final letraGrande = TipografiaApp.esLetraGrande(context);
    final colorTitulo = destructiva ? e.error : e.textoPrincipal;
    final estiloGris = TipografiaApp.subtitulo.copyWith(
      color: e.textoSecundario,
    );

    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TipografiaApp.destacado.copyWith(color: colorTitulo),
        ),
        if (subtitulo != null) Text(subtitulo!, style: estiloGris),
        if (letraGrande && valor != null) Text(valor!, style: estiloGris),
        if (letraGrande && accesorio != null) accesorio!,
      ],
    );

    final fila = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormasApp.altoFilaMinimo),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: EspaciadoApp.rellenoTarjeta,
          vertical: EspaciadoApp.chico,
        ),
        child: Row(
          children: [
            if (_conCuadro && !letraGrande) ...[
              SizedBox.square(
                dimension: FormasApp.cuadroIcono,
                child:
                    inicio ??
                    CuadroIcono(
                      icono: icono!,
                      color: destructiva ? e.error : null,
                    ),
              ),
              const SizedBox(width: EspaciadoApp.medio),
            ],
            Expanded(child: textos),
            if (!letraGrande && valor != null) ...[
              const SizedBox(width: EspaciadoApp.chico),
              // Sin flex: el título se queda con todo lo que el valor no usa.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * _fraccionValor,
                ),
                child: Text(
                  valor!,
                  textAlign: TextAlign.end,
                  style: estiloGris,
                ),
              ),
            ],
            if (!letraGrande && accesorio != null) ...[
              const SizedBox(width: EspaciadoApp.chico),
              accesorio!,
            ],
            if (navega) ...[
              const SizedBox(width: EspaciadoApp.minimo),
              Icon(
                Icons.chevron_right_rounded,
                size: FormasApp.icono,
                color: e.textoSecundario,
              ),
            ],
          ],
        ),
      ),
    );

    return MergeSemantics(
      child: Semantics(
        button: alTocar != null && accesorio == null,
        child: ConEstados(
          deshabilitado: alTocar == null,
          constructor: (context, controlador, estados) {
            final presionado = estaPresionado(estados);
            // En reposo, plana y transparente (se ve la tarjeta); presionada,
            // hundida con el relieve chico, que no llega al texto (queda a
            // 8 dp o más del borde). El grupo la recorta a sus esquinas.
            return DecoratedBox(
              decoration: DecoracionRelieve(
                color: presionado ? e.hundido : Colors.transparent,
                elevacion: presionado ? -1 : 0,
                tamano: TamanoRelieve.chico,
                borde: estaEnfocado(estados)
                    ? BorderSide(color: e.acento, width: FormasApp.grosorFoco)
                    : BorderSide.none,
                sombraOscura: e.sombraOscura,
                sombraClara: e.sombraClara,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: alTocar,
                  statesController: controlador,
                  overlayColor: sinCapa,
                  splashFactory: sinOnda,
                  child: fila,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Interruptor de una fila, con los colores del sistema de diseño fijados
/// (los mismos del tema): apagado, pista hundida con borde (4,41 sobre el
/// fondo) y el pulgar gris (10,18); prendido, pulgar oscuro sobre el acento
/// (11,47).
class _Interruptor extends StatelessWidget {
  const _Interruptor({required this.valor, required this.alCambiar});

  final bool valor;
  final ValueChanged<bool>? alCambiar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Switch(
      value: valor,
      onChanged: alCambiar,
      thumbColor: WidgetStateProperty.resolveWith((estados) {
        if (estados.contains(WidgetState.disabled)) return null;
        return estados.contains(WidgetState.selected)
            ? e.textoSobreAcento
            : e.textoSecundario;
      }),
      trackColor: WidgetStateProperty.resolveWith((estados) {
        if (estados.contains(WidgetState.disabled)) return null;
        return estados.contains(WidgetState.selected) ? e.acento : e.hundido;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((estados) {
        if (estados.contains(WidgetState.disabled)) return null;
        return estados.contains(WidgetState.selected) ? e.acento : e.borde;
      }),
      overlayColor: sinCapa,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
