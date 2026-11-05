import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../movimiento.dart';
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
// flecha gris. Presionada, la fila se hunde (120 ms; al soltar, 160 ms), sin
// achicarse: es parte de la tarjeta.
//
// ─── Interruptor ───
// Dibujado acá (no el Switch de Material, que siempre desliza en 200 ms): la
// pista y el pulgar cambian en 150 ms con la curva de salida fuerte y, con
// movimiento reducido, saltan. Toda la fila lo prende y lo apaga.
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
// Si lo que se ve no alcanza como frase, la fila lleva una etiqueta propia
// (etiquetaSemantica) y TalkBack dice sólo esa.

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
    this.etiquetaSemantica,
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
         accesorio: _Interruptor(valor: valor, habilitado: alCambiar != null),
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

  /// Lo que dice TalkBack en lugar del título, el subtítulo y el valor, si
  /// hace falta otra redacción ("Mapas disponibles para descargar"). Por
  /// defecto, lo que se ve.
  final String? etiquetaSemantica;

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
    // Con una etiqueta propia, el título la lleva y TalkBack saltea el
    // resto del texto.
    Widget gris(String texto, {TextAlign? alineacion}) => ExcludeSemantics(
      excluding: etiquetaSemantica != null,
      child: Text(texto, textAlign: alineacion, style: estiloGris),
    );

    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          semanticsLabel: etiquetaSemantica,
          style: TipografiaApp.destacado.copyWith(color: colorTitulo),
        ),
        if (subtitulo != null) gris(subtitulo!),
        if (letraGrande && valor != null) gris(valor!),
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
                child: gris(valor!, alineacion: TextAlign.end),
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
            return RelieveAnimado(
              presionado: presionado,
              decoracion: DecoracionRelieve(
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

/// Interruptor de una fila, con las medidas del de Material 3 (pista de
/// 52 × 32, pulgar de 16 apagado y de 24 prendido) y los colores del sistema
/// de diseño: apagado, pista hundida con borde (4,41 sobre el fondo) y el
/// pulgar gris (10,18); prendido, pulgar oscuro sobre el acento (11,47). El
/// estado no depende sólo del color: el pulgar cambia de lado y de tamaño.
///
/// No se toca solo: lo prende y lo apaga la fila entera (FilaGrupo
/// .interruptor). TalkBack lo lee como interruptor, activado o no.
class _Interruptor extends StatelessWidget {
  const _Interruptor({required this.valor, required this.habilitado});

  final bool valor;
  final bool habilitado;

  static const double _anchoPista = 52;
  static const double _altoPista = 32;
  static const double _bordePista = 2;
  static const double _pulgarApagado = 16;
  static const double _pulgarPrendido = 24;

  /// Del borde de la pista (por dentro del borde de 2) al lugar del pulgar
  /// más grande: así el centro del pulgar queda a 16 dp de cada punta, como
  /// en Material.
  static const double _margen =
      (_altoPista - _pulgarPrendido) / 2 - _bordePista;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final duracion = MovimientoApp.duracion(context, MovimientoApp.seleccion);
    const curva = MovimientoApp.curva;
    final prendido = valor && habilitado;
    final Color pista;
    final Color borde;
    final Color pulgar;
    if (!habilitado) {
      // Deshabilitado: todo en el separador, plano (no hace falta 3:1).
      pista = e.hundido;
      borde = e.separador;
      pulgar = e.separador;
    } else if (prendido) {
      pista = e.acento;
      borde = e.acento;
      pulgar = e.textoSobreAcento;
    } else {
      pista = e.hundido;
      borde = e.borde;
      pulgar = e.textoSecundario;
    }
    final lado = valor ? _pulgarPrendido : _pulgarApagado;
    return Semantics(
      toggled: valor,
      enabled: habilitado,
      child: SizedBox(
        width: _anchoPista,
        height: _altoPista,
        child: AnimatedContainer(
          duration: duracion,
          curve: curva,
          decoration: BoxDecoration(
            color: pista,
            borderRadius: BorderRadius.circular(_altoPista / 2),
            border: Border.all(color: borde, width: _bordePista),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _margen),
            child: AnimatedAlign(
              duration: duracion,
              curve: curva,
              alignment: valor
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: SizedBox.square(
                dimension: _pulgarPrendido,
                child: Center(
                  child: AnimatedContainer(
                    duration: duracion,
                    curve: curva,
                    width: lado,
                    height: lado,
                    decoration: BoxDecoration(
                      color: pulgar,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
