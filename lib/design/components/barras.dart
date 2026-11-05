import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../espaciado.dart';
import '../estilo.dart';
import '../formas.dart';
import '../movimiento.dart';
import '../relieve.dart';
import '../tipografia.dart';
import 'botones.dart';
import 'panel_relieve.dart';
import 'presion.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Barra superior y barras flotantes
// ═══════════════════════════════════════════════════════════════════════════
//
// Se usan con
//   Scaffold(
//     extendBody: true,               // con una barra flotante
//     appBar: BarraSuperior(...),
//     bottomNavigationBar: BarraInferior(...),   // o BarraAcciones
//     body: ListView(...),            // el relleno de abajo lo da el
//   )                                 // Scaffold (MediaQuery.padding)
//
// ─── Barra superior ───
// Fondo liso (el de la pantalla), sin vidrio ni línea: botones redondos de
// 36 dp, levantados y con borde (BotonRedondo), y el título centrado, chico
// (14), en texto principal (15,50). Para un título largo, conviene repetirlo
// grande al principio del contenido.
//
// ─── Barras flotantes ───
// Una píldora levantada en la superficie, con borde de 1 px y radio 24,
// separada 16 dp de los costados, como la barra de herramientas de un
// editor. Sin desenfoque: el vidrio esmerilado le baja el contraste a lo que
// va encima. BarraInferior lleva pestañas; BarraAcciones, botones (la acción
// principal en acento, como "Repetir" en la navegación).
//
// ─── Textos en español ───
// Volver, Cerrar y "pestaña 2 de 3" son propios: los de Material saldrían en
// inglés con TalkBack, porque la app no tiene las traducciones de Material.

// ─── BARRA SUPERIOR ─────────────────────────────────────────────────────────

/// Barra superior: volver, el título centrado y acciones, todo sobre el
/// fondo liso de la pantalla.
///
/// El título va en un renglón: si no entra se corta con "…", pero TalkBack lo
/// lee entero. Con letra grande la barra crece para que el renglón no se
/// recorte de arriba ni de abajo.
class BarraSuperior extends StatelessWidget implements PreferredSizeWidget {
  const BarraSuperior({
    super.key,
    required this.titulo,
    this.acciones = const [],
    this.mostrarVolver,
    this.alVolver,
  });

  final String titulo;

  /// Botones de la derecha, en general [AccionBarra].
  final List<Widget> acciones;

  /// Si muestra el botón para volver. null: lo muestra si se puede volver.
  final bool? mostrarVolver;

  /// Qué hace el botón para volver. null: vuelve a la pantalla anterior.
  final VoidCallback? alVolver;

  /// El alto MÁXIMO, no el real: el Scaffold limita la barra a este alto,
  /// pero la barra mide lo que su contenido (56 dp con la letra normal, más
  /// con letra grande) y el Scaffold corre el cuerpo según el alto real.
  @override
  Size get preferredSize =>
      const Size.fromHeight(FormasApp.altoBarraSuperior * 2);

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final volver =
        mostrarVolver ??
        (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    // El alto: el de Material o, con letra grande, lo que pide el renglón
    // del título con su aire arriba y abajo.
    const estilo = TipografiaApp.tituloBarra;
    final renglon =
        MediaQuery.textScalerOf(context).scale(estilo.fontSize!) *
        estilo.height!;
    final alto = math.max(
      FormasApp.altoBarraSuperior,
      renglon + 2 * EspaciadoApp.medio,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Íconos claros en la barra de estado, que queda sobre esta barra.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Material(
        color: e.fondo,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: alto,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EspaciadoApp.minimo,
              ),
              child: NavigationToolbar(
                centerMiddle: true,
                middleSpacing: EspaciadoApp.chico,
                leading: volver
                    ? BotonRedondo(
                        icono: Icons.arrow_back_rounded,
                        etiqueta: 'Volver',
                        alPresionar:
                            alVolver ?? () => Navigator.maybePop(context),
                      )
                    : null,
                middle: Semantics(
                  header: true,
                  namesRoute: true,
                  child: Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: estilo.copyWith(color: e.textoPrincipal),
                  ),
                ),
                trailing: acciones.isEmpty
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: acciones),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Acción de la barra superior: un botón redondo con su nombre para
/// TalkBack, que también aparece al mantenerlo apretado.
class AccionBarra extends StatelessWidget {
  const AccionBarra({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.alPresionar,
  });

  final IconData icono;
  final String etiqueta;

  /// null: deshabilitada.
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) =>
      BotonRedondo(icono: icono, etiqueta: etiqueta, alPresionar: alPresionar);
}

// ─── PÍLDORA FLOTANTE ───────────────────────────────────────────────────────

/// La píldora de las barras flotantes: levantada, con borde, a 16 dp de los
/// costados y 12 del borde de abajo. Los márgenes no toman los toques: lo
/// que pasa por detrás se sigue pudiendo tocar.
class _Pildora extends StatelessWidget {
  const _Pildora({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EspaciadoApp.margenLateral,
          0,
          EspaciadoApp.margenLateral,
          EspaciadoApp.medio,
        ),
        child: PanelRelieve(
          radio: FormasApp.bordeBarraFlotante,
          borde: BorderSide(color: e.borde, width: FormasApp.grosorLinea),
          relleno: EdgeInsets.zero,
          sombraEncima: true,
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: FormasApp.altoBarraInferior,
              ),
              // Todas las piezas del alto de la más alta.
              child: IntrinsicHeight(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// El nombre de una pestaña o una acción, en un renglón: si con letra
/// grande no entra en su ancho, se achica lo justo para entrar, en vez de
/// partirse a la mitad de la palabra ("Compon/entes"). Sin [estilo], toma el
/// DefaultTextStyle (el de una pestaña, que cambia animado).
Widget _nombreEnUnRenglon(
  String texto,
  TextStyle? estilo, {
  String? semanticsLabel,
}) => FittedBox(
  fit: BoxFit.scaleDown,
  child: Text(
    texto,
    textAlign: TextAlign.center,
    maxLines: 1,
    softWrap: false,
    semanticsLabel: semanticsLabel,
    style: estilo,
  ),
);

// ─── BARRA INFERIOR (PESTAÑAS) ──────────────────────────────────────────────

/// Una pestaña de la [BarraInferior].
///
/// Activa se ve con [icono] (relleno: Icons.*_rounded); inactiva, con
/// [iconoInactivo] (contorno: Icons.*_outlined). Flutter no trae íconos que
/// sean de contorno y redondeados a la vez: el contorno es la variante
/// _outlined.
@immutable
class PestanaBarra {
  const PestanaBarra({
    required this.icono,
    required this.iconoInactivo,
    required this.texto,
  });

  final IconData icono;
  final IconData iconoInactivo;
  final String texto;
}

/// Barra inferior flotante con pestañas.
///
/// La activa va en acento (8,75 sobre la superficie) con el ícono relleno y
/// el nombre en negrita; las demás, en texto secundario (9,10) con el ícono
/// de contorno: el estado no depende sólo del color. Al cambiar, el ícono
/// pasa a relleno con un fundido y el color a acento, en 150 ms (con
/// movimiento reducido, de golpe). TalkBack lee el nombre, si está
/// seleccionada y "pestaña 2 de 3". Al tocar no hay relieve: la respuesta es
/// el cambio de pestaña. Conviene que los nombres sean de una palabra corta.
class BarraInferior extends StatelessWidget {
  const BarraInferior({
    super.key,
    required this.pestanas,
    required this.seleccionada,
    required this.alCambiar,
  });

  /// 2 o más.
  final List<PestanaBarra> pestanas;

  /// Índice de la pestaña activa.
  final int seleccionada;
  final ValueChanged<int> alCambiar;

  @override
  Widget build(BuildContext context) {
    assert(pestanas.length >= 2, 'Una barra de pestañas tiene 2 o más.');
    return _Pildora(
      child: Semantics(
        role: SemanticsRole.tabBar,
        container: true,
        explicitChildNodes: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < pestanas.length; i++)
              Expanded(
                child: _Pestana(
                  pestana: pestanas[i],
                  activa: i == seleccionada,
                  numero: i + 1,
                  total: pestanas.length,
                  alTocar: () => alCambiar(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    required this.pestana,
    required this.activa,
    required this.numero,
    required this.total,
    required this.alTocar,
  });

  final PestanaBarra pestana;
  final bool activa;
  final int numero;
  final int total;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final color = activa ? e.acento : e.textoSecundario;
    final duracion = MovimientoApp.duracion(context, MovimientoApp.seleccion);
    return MergeSemantics(
      child: Semantics(
        role: SemanticsRole.tab,
        selected: activa,
        button: true,
        child: InkWell(
          onTap: alTocar,
          splashFactory: sinOnda,
          overlayColor: sinCapa,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspaciadoApp.minimo,
              vertical: EspaciadoApp.chico,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // El ícono pasa de contorno a relleno con un fundido, y de
                // gris a acento, a la vez.
                ColorAnimado(
                  color: color,
                  builder: (context, colorIcono) => AnimatedSwitcher(
                    duration: duracion,
                    switchInCurve: MovimientoApp.curva,
                    switchOutCurve: MovimientoApp.curva.flipped,
                    child: Icon(
                      activa ? pestana.icono : pestana.iconoInactivo,
                      key: ValueKey<bool>(activa),
                      size: FormasApp.icono,
                      color: colorIcono,
                    ),
                  ),
                ),
                const SizedBox(height: EspaciadoApp.minimo),
                AnimatedDefaultTextStyle(
                  duration: duracion,
                  curve: MovimientoApp.curva,
                  style: TipografiaApp.leyenda.copyWith(
                    color: color,
                    fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: _nombreEnUnRenglon(pestana.texto, null),
                ),
                // Lo que agrega Material a cada pestaña, en español.
                Semantics(label: 'pestaña $numero de $total'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── BARRA DE ACCIONES ──────────────────────────────────────────────────────

/// Una acción de la [BarraAcciones].
@immutable
class AccionPildora {
  const AccionPildora({
    required this.icono,
    required this.texto,
    required this.alPresionar,
    this.principal = false,
    this.etiquetaSemantica,
  });

  /// Icons.*_rounded.
  final IconData icono;
  final String texto;

  /// null: deshabilitada.
  final VoidCallback? alPresionar;

  /// La acción principal: en acento (8,75 sobre la superficie). Una sola.
  final bool principal;

  /// Lo que dice TalkBack en lugar de [texto], si hace falta más contexto.
  final String? etiquetaSemantica;
}

/// Barra flotante con botones, como la de la navegación ("Repetir" en
/// acento). Las demás acciones van en texto principal (13,85); una
/// deshabilitada, en texto secundario. Presionada, la acción se hunde y se
/// achica apenas (presion.dart).
class BarraAcciones extends StatelessWidget {
  const BarraAcciones({super.key, required this.acciones});

  /// 1 a 4: con más, los nombres no entran.
  final List<AccionPildora> acciones;

  @override
  Widget build(BuildContext context) {
    assert(
      acciones.where((a) => a.principal).length <= 1,
      'Una sola acción principal por barra.',
    );
    return _Pildora(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final accion in acciones)
            Expanded(child: _BotonPildora(accion: accion)),
        ],
      ),
    );
  }
}

class _BotonPildora extends StatelessWidget {
  const _BotonPildora({required this.accion});

  final AccionPildora accion;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final habilitada = accion.alPresionar != null;
    final color = !habilitada
        ? e.textoSecundario
        : accion.principal
        ? e.acento
        : e.textoPrincipal;
    // Cada acción se lee de una vez: su nombre y "botón".
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: habilitada,
        child: ConEstados(
          deshabilitado: !habilitada,
          constructor: (context, controlador, estados) {
            final presionado = estaPresionado(estados);
            return Padding(
              padding: const EdgeInsets.all(EspaciadoApp.minimo),
              child: EscalaPresion(
                presionado: presionado,
                // En reposo, plana; presionada, hundida con el relieve chico,
                // adentro de la píldora.
                child: RelieveAnimado(
                  presionado: presionado,
                  decoracion: DecoracionRelieve(
                    color: presionado ? e.hundido : Colors.transparent,
                    radio: const BorderRadius.all(
                      Radius.circular(
                        FormasApp.radioHoja - EspaciadoApp.minimo,
                      ),
                    ),
                    elevacion: presionado ? -1 : 0,
                    tamano: TamanoRelieve.chico,
                    borde: estaEnfocado(estados)
                        ? BorderSide(
                            color: e.acento,
                            width: FormasApp.grosorFoco,
                          )
                        : BorderSide.none,
                    sombraOscura: e.sombraOscura,
                    sombraClara: e.sombraClara,
                  ),
                  child: InkWell(
                    onTap: accion.alPresionar,
                    statesController: controlador,
                    customBorder: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(
                          FormasApp.radioHoja - EspaciadoApp.minimo,
                        ),
                      ),
                    ),
                    splashFactory: sinOnda,
                    overlayColor: sinCapa,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: EspaciadoApp.minimo,
                        vertical: EspaciadoApp.chico,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            accion.icono,
                            size: FormasApp.icono,
                            color: color,
                          ),
                          const SizedBox(height: EspaciadoApp.minimo),
                          _nombreEnUnRenglon(
                            accion.texto,
                            TipografiaApp.leyenda.copyWith(
                              color: color,
                              fontWeight: accion.principal
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            semanticsLabel: accion.etiquetaSemantica,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
