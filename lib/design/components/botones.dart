import 'package:flutter/material.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Botones
// ═══════════════════════════════════════════════════════════════════════════
//
// Sobre los botones de Material (FilledButton), que ya traen la semántica de
// botón, el foco y el área táctil: el botón de Material va transparente y el
// relieve se pinta detrás, con DecoracionRelieve, porque Material recorta lo
// que pinta adentro a su forma y las sombras de afuera no se verían.
//
// ─── Estados ───
//   reposo         levantado
//   presionado     hundido (en 120 ms) y achicado a 0,97; al soltar vuelve
//                  en 160 ms (presion.dart)
//   deshabilitado  plano, con el texto secundario (se sigue leyendo: con baja
//                  visión importa saber qué está apagado)
//   enfocado       el borde pasa a 2 px de acento (con teclado o switch)
//
// Con letra grande, el texto se parte en renglones y el botón crece: los
// altos son mínimos, nunca fijos.

/// Relleno de los botones grandes: el texto nunca toca el borde, ni partido
/// en varios renglones, y queda lejos de la sombra interior al presionar.
const EdgeInsets _relleno = EdgeInsets.symmetric(
  horizontal: EspaciadoApp.rellenoTarjeta,
  vertical: EspaciadoApp.medio,
);

/// Relleno de los compactos.
const EdgeInsets _rellenoCompacto = EdgeInsets.symmetric(
  horizontal: EspaciadoApp.medio,
  vertical: EspaciadoApp.chico,
);

const Size _tamanoGrande = Size(
  FormasApp.areaTactilMinima,
  FormasApp.altoBoton,
);
const Size _tamanoCompacto = Size(
  FormasApp.areaTactilMinima,
  FormasApp.areaTactilMinima,
);

/// El estilo de Material de los botones: transparente (el relieve va
/// detrás), sin onda ni capa, con los valores fijados acá para que se vean
/// igual bajo cualquier tema.
ButtonStyle _estiloBase({
  required Color texto,
  required Color textoDeshabilitado,
  required Size tamano,
  required EdgeInsets relleno,
  required OutlinedBorder forma,
}) => FilledButton.styleFrom(
  backgroundColor: Colors.transparent,
  disabledBackgroundColor: Colors.transparent,
  foregroundColor: texto,
  disabledForegroundColor: textoDeshabilitado,
  elevation: 0,
  minimumSize: tamano,
  padding: relleno,
  shape: forma,
  textStyle: TipografiaApp.boton,
  iconSize: FormasApp.iconoChico,
  tapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
  splashFactory: sinOnda,
).copyWith(overlayColor: sinCapa);

Widget _botonMaterial({
  required VoidCallback? alPresionar,
  required ButtonStyle estilo,
  required WidgetStatesController controlador,
  required IconData? icono,
  required Widget etiqueta,
}) => icono == null
    ? FilledButton(
        onPressed: alPresionar,
        style: estilo,
        statesController: controlador,
        child: etiqueta,
      )
    : FilledButton.icon(
        onPressed: alPresionar,
        style: estilo,
        statesController: controlador,
        icon: Icon(icono),
        label: etiqueta,
      );

// ─── BOTÓN PRINCIPAL ────────────────────────────────────────────────────────
//
// La acción principal de una pantalla: acento plano (sin degradado), texto
// oscuro en peso medio (11,47), 52 de alto y radio 14. Uno solo por
// pantalla. El acento ya pasa 3:1 contra el fondo (9,79): no necesita el
// borde gris de los demás controles.
//
// Presionado, hundido sólo con la sombra oscura: la luz del relieve es más
// oscura que el acento y se vería como una mancha.

/// El relieve del botón principal (el común y el grande): acento levantado;
/// presionado, hundido sin la luz; deshabilitado, plano en la superficie;
/// con el foco, el borde de 2 px en el color del texto (uno de acento no se
/// vería sobre el relleno).
DecoracionRelieve _decoracionPrincipal(
  EstiloApp e,
  Set<WidgetState> estados, {
  required bool habilitado,
  required BorderRadius radio,
}) => DecoracionRelieve(
  color: habilitado ? e.acento : e.superficie,
  radio: radio,
  elevacion: elevacionControl(estados),
  borde: !habilitado
      ? BorderSide(color: e.separador, width: FormasApp.grosorLinea)
      : estaEnfocado(estados)
      ? BorderSide(color: e.textoSobreAcento, width: FormasApp.grosorFoco)
      : BorderSide.none,
  sombraOscura: e.sombraOscura,
  sombraClara: estaPresionado(estados) ? null : e.sombraClara,
);

/// El botón de la acción principal de la pantalla.
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.alPresionar,
    this.icono,
    this.expandido = true,
    this.etiquetaSemantica,
  });

  final String texto;

  /// null: deshabilitado.
  final VoidCallback? alPresionar;

  /// Ícono antes del texto (Icons.*_rounded).
  final IconData? icono;

  /// Ocupa todo el ancho, lo común en el teléfono. Adentro de una fila, va
  /// en false o dentro de un Expanded.
  final bool expandido;

  /// Lo que dice TalkBack en lugar de [texto], si hace falta más contexto.
  final String? etiquetaSemantica;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final habilitado = alPresionar != null;
    final estilo = _estiloBase(
      texto: e.textoSobreAcento,
      textoDeshabilitado: e.textoSecundario,
      tamano: _tamanoGrande,
      relleno: _relleno,
      forma: const RoundedRectangleBorder(borderRadius: FormasApp.bordeBoton),
    );
    final etiqueta = Text(
      texto,
      textAlign: TextAlign.center,
      semanticsLabel: etiquetaSemantica,
    );
    final boton = ConEstados(
      deshabilitado: !habilitado,
      constructor: (context, controlador, estados) {
        final presionado = estaPresionado(estados);
        return EscalaPresion(
          presionado: presionado,
          child: RelieveAnimado(
            decoracion: _decoracionPrincipal(
              e,
              estados,
              habilitado: habilitado,
              radio: FormasApp.bordeBoton,
            ),
            presionado: presionado,
            child: _botonMaterial(
              alPresionar: alPresionar,
              estilo: estilo,
              controlador: controlador,
              icono: icono,
              etiqueta: etiqueta,
            ),
          ),
        );
      },
    );
    return expandido ? SizedBox(width: double.infinity, child: boton) : boton;
  }
}

// ─── BOTÓN PRINCIPAL GRANDE ─────────────────────────────────────────────────
//
// El mismo botón principal (acento plano y levantado, texto oscuro; se hunde
// y se achica al presionarlo), en grande: para la acción que se tiene que
// poder acertar sin mirar con cuidado, como "Comenzar a navegar" en el
// inicio. Llena el lugar que le dan (va en un Expanded) con el ícono arriba,
// el texto en 22 y, debajo, una aclaración. Tiene la forma de una tarjeta
// (radio 20). Es el botón principal de su pantalla: no va con un
// BotonPrincipal al lado.
//
// No tiene alto propio: mide lo que le dan o, si no le alcanza, lo que pide
// su contenido (con letra grande, el texto se parte en renglones y el botón
// crece). El texto va en 22 y no en 34: así, aun con la letra al 200 % en un
// teléfono de 360 dp, ninguna palabra se parte ("Comenzar", en 34, ya no
// entraría en un renglón).
//
// TalkBack lee el texto (o etiquetaSemantica) y "botón". La aclaración
// ("Tocá para comenzar") es para quien ve: no la lee.

/// El botón principal en grande: llena el lugar que le dan.
class BotonPrincipalGrande extends StatelessWidget {
  const BotonPrincipalGrande({
    super.key,
    required this.texto,
    required this.icono,
    required this.alPresionar,
    this.detalle,
    this.etiquetaSemantica,
  });

  final String texto;

  /// Ícono de arriba (Icons.*_rounded). Decorativo.
  final IconData icono;

  /// null: deshabilitado.
  final VoidCallback? alPresionar;

  /// Aclaración debajo del texto, para quien ve ("Tocá para comenzar").
  /// TalkBack no la lee.
  final String? detalle;

  /// Lo que dice TalkBack en lugar de [texto], si hace falta más contexto.
  final String? etiquetaSemantica;

  /// A los costados, el relleno de una tarjeta; arriba y abajo, más aire,
  /// así se ve grande aun cuando mide lo que su contenido. El texto queda
  /// lejos de la sombra interior al presionar.
  static const EdgeInsets _rellenoGrande = EdgeInsets.symmetric(
    horizontal: EspaciadoApp.rellenoTarjeta,
    vertical: EspaciadoApp.entreSecciones,
  );

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final habilitado = alPresionar != null;
    final estilo = _estiloBase(
      texto: e.textoSobreAcento,
      textoDeshabilitado: e.textoSecundario,
      tamano: _tamanoGrande,
      relleno: _rellenoGrande,
      forma: const RoundedRectangleBorder(borderRadius: FormasApp.bordeTarjeta),
    );
    // El color del ícono y de los textos sale del botón: oscuro sobre el
    // acento (11,47) y, deshabilitado, el texto secundario.
    final contenido = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: FormasApp.iconoGrande),
        const SizedBox(height: EspaciadoApp.medio),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: TipografiaApp.titulo,
          semanticsLabel: etiquetaSemantica,
        ),
        if (detalle != null) ...[
          const SizedBox(height: EspaciadoApp.chico),
          ExcludeSemantics(
            child: Text(
              detalle!,
              textAlign: TextAlign.center,
              style: TipografiaApp.cuerpo,
            ),
          ),
        ],
      ],
    );
    return ConEstados(
      deshabilitado: !habilitado,
      constructor: (context, controlador, estados) {
        final presionado = estaPresionado(estados);
        return EscalaPresion(
          presionado: presionado,
          child: RelieveAnimado(
            decoracion: _decoracionPrincipal(
              e,
              estados,
              habilitado: habilitado,
              radio: FormasApp.bordeTarjeta,
            ),
            presionado: presionado,
            child: FilledButton(
              onPressed: alPresionar,
              style: estilo,
              statesController: controlador,
              child: contenido,
            ),
          ),
        );
      },
    );
  }
}

// ─── BOTÓN SECUNDARIO ───────────────────────────────────────────────────────

/// Botón para las acciones que no son la principal: levantado, con el borde
/// de 1 px (3,94 sobre la superficie) y el texto principal (13,85).
///
/// [destructivo] (borrar, quitar) pinta el texto en el color de error: 5,31
/// sobre la superficie y 5,94 hundido, al presionar. [compacto] mide 48 de
/// alto en vez de 52, para una acción al lado de un título ("Ver todos").
class BotonSecundario extends StatelessWidget {
  const BotonSecundario({
    super.key,
    required this.texto,
    required this.alPresionar,
    this.icono,
    this.destructivo = false,
    this.compacto = false,
    this.expandido = false,
    this.etiquetaSemantica,
  });

  final String texto;

  /// null: deshabilitado.
  final VoidCallback? alPresionar;
  final IconData? icono;
  final bool destructivo;
  final bool compacto;

  /// Ocupa todo el ancho disponible.
  final bool expandido;

  /// Lo que dice TalkBack en lugar de [texto], si hace falta más contexto.
  final String? etiquetaSemantica;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final habilitado = alPresionar != null;
    final estilo = _estiloBase(
      texto: destructivo ? e.error : e.textoPrincipal,
      textoDeshabilitado: e.textoSecundario,
      tamano: compacto ? _tamanoCompacto : _tamanoGrande,
      relleno: compacto ? _rellenoCompacto : _relleno,
      forma: const RoundedRectangleBorder(borderRadius: FormasApp.bordeBoton),
    );
    final etiqueta = Text(
      texto,
      textAlign: TextAlign.center,
      semanticsLabel: etiquetaSemantica,
    );
    final boton = ConEstados(
      deshabilitado: !habilitado,
      constructor: (context, controlador, estados) {
        final presionado = estaPresionado(estados);
        return EscalaPresion(
          presionado: presionado,
          child: RelieveAnimado(
            presionado: presionado,
            decoracion: DecoracionRelieve(
              color: presionado ? e.hundido : e.superficie,
              radio: FormasApp.bordeBoton,
              elevacion: elevacionControl(estados),
              borde: _bordeControl(e, estados),
              sombraOscura: e.sombraOscura,
              sombraClara: e.sombraClara,
            ),
            child: _botonMaterial(
              alPresionar: alPresionar,
              estilo: estilo,
              controlador: controlador,
              icono: icono,
              etiqueta: etiqueta,
            ),
          ),
        );
      },
    );
    return expandido ? SizedBox(width: double.infinity, child: boton) : boton;
  }
}

/// El borde de un control gris: el de 1 px; enfocado, 2 px de acento;
/// deshabilitado, el separador (decorativo: el texto gris ya dice que está
/// apagado).
BorderSide _bordeControl(EstiloApp e, Set<WidgetState> estados) {
  if (estados.contains(WidgetState.disabled)) {
    return BorderSide(color: e.separador, width: FormasApp.grosorLinea);
  }
  if (estaEnfocado(estados)) {
    return BorderSide(color: e.acento, width: FormasApp.grosorFoco);
  }
  return BorderSide(color: e.borde, width: FormasApp.grosorLinea);
}

// ─── BOTÓN REDONDO ──────────────────────────────────────────────────────────

/// Botón redondo de ícono: 36 dp de dibujo, levantado (el relieve chico) y
/// con borde, adentro de un área tocable de 48. Es el de las barras (volver,
/// acciones, cerrar una hoja). El ícono va en texto principal (13,85).
///
/// [etiqueta] es lo que dice TalkBack y lo que aparece al mantenerlo
/// apretado.
class BotonRedondo extends StatelessWidget {
  const BotonRedondo({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.alPresionar,
  });

  final IconData icono;
  final String etiqueta;

  /// null: deshabilitado.
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final habilitado = alPresionar != null;
    const tamano = Size.square(FormasApp.botonRedondo);
    final estilo = _estiloBase(
      texto: e.textoPrincipal,
      textoDeshabilitado: e.textoSecundario,
      tamano: tamano,
      relleno: EdgeInsets.zero,
      forma: const CircleBorder(),
    ).copyWith(fixedSize: const WidgetStatePropertyAll(tamano));
    // El nombre va en el ícono: así queda en el mismo nodo que el botón y
    // TalkBack lo lee una sola vez. El globo, al mantenerlo apretado.
    return Tooltip(
      message: etiqueta,
      excludeFromSemantics: true,
      child: ConEstados(
        deshabilitado: !habilitado,
        constructor: (context, controlador, estados) {
          final presionado = estaPresionado(estados);
          // El botón de Material mide 48 (el área tocable) con el dibujo de
          // 36 en el centro: el relieve va detrás, del mismo 36.
          return EscalaPresion(
            presionado: presionado,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.fromSize(
                  size: tamano,
                  child: RelieveAnimado(
                    presionado: presionado,
                    decoracion: DecoracionRelieve(
                      color: presionado ? e.hundido : e.superficie,
                      circulo: true,
                      elevacion: elevacionControl(estados),
                      tamano: TamanoRelieve.chico,
                      borde: _bordeControl(e, estados),
                      sombraOscura: e.sombraOscura,
                      sombraClara: e.sombraClara,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: alPresionar,
                  style: estilo,
                  statesController: controlador,
                  child: Icon(icono, semanticLabel: etiqueta),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
