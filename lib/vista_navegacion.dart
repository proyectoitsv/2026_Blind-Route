import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'design/design.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Lo que se ve en la navegación (fase 5.7 del rediseño)
// ═══════════════════════════════════════════════════════════════════════════
//
// La pantalla de navegación (pantalla_naveg.dart) tiene la lógica: la
// posición, la ruta, la voz. Acá está lo que se ve, y no decide nada: recibe
// lo que hay que mostrar y avisa los toques.
//
// De arriba abajo: la barra con el piso; el destino con la brújula (o, sin
// destino, qué hacer); los pisos para mirar; la indicación; el plano hundido,
// con la ruta; la línea de tiempo; el estado de la señal y la píldora con el
// micrófono.
//
// ─── Toda la pantalla escucha ───
// Dos gestos sobre toda la pantalla (ver [VistaNavegacion]): un toque corto
// pide el destino por voz y mantener apretado cambia de piso. Lo que se toca
// aparte (botones, chips) se queda con su toque; arrastrar el plano no cuenta
// como toque.
//
// ─── TalkBack y la voz ───
// La guía la da la voz. TalkBack dice lo mismo que antes, cuando se llega con
// el foco: sólo se anuncian solas las llegadas (y el cartel de otro piso). La
// orientación al llegar cambia mientras la persona gira y el estado de la
// señal cambia todo el tiempo: anunciados, pisarían a la voz.

/// Qué clase de indicación muestra la tarjeta.
enum TipoIndicacion {
  /// Guiando: la indicación de voz con la distancia, en acento.
  guia,

  /// Girando hacia el lugar al llegar.
  orientacion,

  /// Llegó al destino.
  llegada,

  /// Llegó a la escalera o al ascensor.
  escalera,
}

/// Lo que muestra la tarjeta de la indicación.
@immutable
class DatosIndicacion {
  const DatosIndicacion({
    required this.tipo,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.etiqueta,
  });

  final TipoIndicacion tipo;

  /// Icons.*_rounded.
  final IconData icono;

  /// "Girá a la izquierda", "Llegaste".
  final String titulo;

  /// La distancia o el lugar.
  final String detalle;

  /// Lo que dice TalkBack.
  final String etiqueta;

  /// Las llegadas: TalkBack las anuncia solas y aparecen con un fundido.
  bool get esLlegada =>
      tipo == TipoIndicacion.llegada || tipo == TipoIndicacion.escalera;
}

/// Un botón del selector de pisos.
@immutable
class OpcionPiso {
  const OpcionPiso({
    required this.etiqueta,
    required this.nombre,
    required this.esMio,
    required this.visto,
    required this.alTocar,
  });

  /// Lo que dice el botón ("PB", "2").
  final String etiqueta;

  /// El nombre entero, para TalkBack ("Planta baja").
  final String nombre;

  /// Si es el piso donde está el usuario.
  final bool esMio;

  /// Si es el que se está viendo.
  final bool visto;
  final VoidCallback alTocar;
}

/// Un lugar de la lista de destinos.
@immutable
class OpcionDestino {
  const OpcionDestino({
    required this.clave,
    required this.nombre,
    required this.pisos,
    required this.icono,
  });

  /// Lo que devuelve [mostrarListaDestinos] si se lo elige.
  final String clave;
  final String nombre;

  /// En qué pisos está ("Planta baja (acá) · Piso 2").
  final String pisos;
  final IconData icono;
}

/// La lista de destinos, en una hoja: un toque y va. Da la clave del elegido,
/// o null si se cierra.
Future<String?> mostrarListaDestinos(
  BuildContext context,
  List<OpcionDestino> opciones,
) => mostrarHoja<String>(
  context,
  titulo: '¿A dónde querés ir?',
  contenido: (hoja) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, o) in opciones.indexed) ...[
        if (i > 0) const SizedBox(height: EspaciadoApp.medio),
        TarjetaLista(
          icono: o.icono,
          titulo: o.nombre,
          subtitulo: o.pisos,
          alTocar: () => Navigator.pop(hoja, o.clave),
        ),
      ],
    ],
  ),
);

/// La navegación: arma la pantalla con lo que le pasan.
class VistaNavegacion extends StatelessWidget {
  const VistaNavegacion({
    super.key,
    required this.titulo,
    required this.destino,
    required this.estadoRuta,
    required this.brujula,
    required this.pisos,
    required this.indicacion,
    required this.recorrido,
    required this.plano,
    required this.avisoOtroPiso,
    required this.buscandoUbicacion,
    required this.siguiendo,
    required this.alCentrar,
    required this.estadoSenal,
    required this.detalleSenal,
    required this.escuchando,
    required this.ayuda,
    required this.ayudaImportante,
    required this.alTocarPantalla,
    required this.alMantenerPantalla,
    required this.duracionMantener,
    required this.alElegirDeLista,
    required this.alCancelar,
    required this.alAbrirAjustes,
  });

  /// El piso, en la barra.
  final String titulo;

  /// El destino, o null si todavía no hay.
  final String? destino;

  /// Cómo va la ruta ("Calculando ruta...", "Ruta a Aula 12: 12.5m").
  final String estadoRuta;

  /// La brújula (un [ChipOrientacion]).
  final Widget brujula;

  /// Los pisos para mirar. Vacío: sin selector.
  final List<OpcionPiso> pisos;

  /// La tarjeta de la indicación, o null si no hay nada que indicar.
  final DatosIndicacion? indicacion;

  /// Los tramos de la ruta, para "Tramo 2 de 3" y la línea de tiempo.
  final Recorrido? recorrido;

  /// El plano, ya armado: va adentro del panel hundido.
  final Widget plano;

  /// El cartel de cuando se mira otro piso ("Viendo Piso 1 · estás en…").
  final String? avisoOtroPiso;

  /// Todavía no hay posición y se la está buscando.
  final bool buscandoUbicacion;

  /// Si el mapa está siguiendo al usuario: si no, el botón de centrar se
  /// resalta, que es cuando hace falta.
  final bool siguiendo;
  final VoidCallback alCentrar;

  /// El estado de la señal, siempre a la vista.
  final String estadoSenal;

  /// Un dato más de la señal, que se despliega. null: no hay qué desplegar.
  final String? detalleSenal;

  /// El micrófono está abierto.
  final bool escuchando;

  /// Lo que se puede hacer ahora, arriba de la píldora.
  final String ayuda;

  /// Si [ayuda] hace falta para seguir ("Decí el nombre del lugar"). Si no,
  /// con letra grande no se muestra: el plano necesita ese lugar.
  final bool ayudaImportante;

  /// Un toque en cualquier parte: el destino por voz (o, si se estaba
  /// escuchando, deja de escuchar).
  final VoidCallback alTocarPantalla;

  /// Mantener apretada la pantalla: cambiar de piso.
  final VoidCallback alMantenerPantalla;

  /// Cuánto hay que mantenerla: la de GestureDetector (0,5 s) es demasiado
  /// corta, y un toque apoyado sin querer podría cargar otro piso.
  final Duration duracionMantener;

  final VoidCallback alElegirDeLista;

  /// null: no hay destino para cancelar.
  final VoidCallback? alCancelar;

  /// null: sin el botón (sólo está en la app del admin).
  final VoidCallback? alAbrirAjustes;

  /// Lo más que ocupa lo de arriba: el plano siempre tiene lugar. Con letra
  /// grande, lo de arriba se desplaza.
  static const double _maximoArriba = 0.45;

  static Widget _conMargen(Widget hijo) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: EspaciadoApp.margenLateral),
    child: hijo,
  );

  Widget _arriba(BuildContext context, EstiloApp e) {
    final indicacion = this.indicacion;
    final r = recorrido;
    final tarjeta = indicacion == null
        ? null
        : _conMargen(
            TarjetaIndicacion(
              datos: indicacion,
              tramo: r != null && indicacion.tipo == TipoIndicacion.guia
                  ? 'Tramo ${r.actual + 1} de ${r.tramos.length}'
                  : null,
            ),
          );
    // Con letra grande no entra todo sin desplazar: la indicación va primero,
    // que es lo que hay que ver.
    final letraGrande = TipografiaApp.esLetraGrande(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (letraGrande && tarjeta != null) ...[
          tarjeta,
          const SizedBox(height: EspaciadoApp.medio),
        ],
        _conMargen(
          _FilaDestino(
            destino: destino,
            estadoRuta: estadoRuta,
            brujula: brujula,
          ),
        ),
        if (pisos.isNotEmpty) ...[
          const SizedBox(height: EspaciadoApp.minimo),
          SelectorPisos(pisos: pisos),
        ],
        if (!letraGrande && tarjeta != null) ...[
          const SizedBox(height: EspaciadoApp.medio),
          tarjeta,
        ],
        // Más que el alcance de la sombra de la tarjeta: el desplazamiento
        // recorta lo que se sale.
        const SizedBox(height: EspaciadoApp.medio),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AmbienteDiseno(
      child: Builder(
        builder: (context) {
          final e = EstiloApp.de(context);
          return Scaffold(
            backgroundColor: e.fondo,
            appBar: BarraSuperior(
              titulo: titulo,
              acciones: [
                // Sólo en la app del admin: regular los ajustes del edificio
                // caminando (ver AjustesNavegacion). El usuario no los cambia.
                if (alAbrirAjustes != null)
                  AccionBarra(
                    icono: Icons.tune_rounded,
                    etiqueta: 'Ajustes de navegación',
                    alPresionar: alAbrirAjustes,
                  ),
                AccionBarra(
                  icono: destino != null
                      ? Icons.edit_location_alt_rounded
                      : Icons.format_list_bulleted_rounded,
                  etiqueta: destino != null
                      ? 'Cambiar destino'
                      : 'Seleccionar destino desde lista',
                  alPresionar: alElegirDeLista,
                ),
              ],
            ),
            // Para TalkBack, el nombre y las dos acciones van en un mismo
            // nodo; lo de adentro, en los suyos.
            body: Semantics(
              container: true,
              explicitChildNodes: true,
              label:
                  'Tocá en cualquier parte de la pantalla para elegir tu '
                  'destino por voz',
              onTap: alTocarPantalla,
              onLongPress: alMantenerPantalla,
              onLongPressHint: 'cambiar de piso',
              // Dos gestos sobre toda la pantalla:
              //  - toque corto  → elegir destino por voz (como siempre);
              //  - mantener ~1 s → cambiar de piso (salto al piso siguiente).
              // Se usa RawGestureDetector para poder fijar la duración del
              // mantener.
              //
              // CONVIVENCIA CON EL MAPA DESPLAZABLE: ninguno de los dos gestos
              // choca con arrastrar o hacer zoom. Si el dedo se mueve más de
              // unos pocos píxeles antes de que pase el segundo, Flutter
              // descarta el toque y el mantener, y el movimiento queda para el
              // mapa.
              // Se descartó el doble toque para cambiar de piso por dos
              // motivos: obliga a que cada toque simple espere ~0,3 s (por si
              // viene un segundo toque) y con TalkBack el doble toque lo usa
              // el lector. El mantener, con TalkBack, es "doble toque
              // sostenido".
              child: RawGestureDetector(
                excludeFromSemantics: true,
                // translucent deja pasar los eventos a los hijos (mapa,
                // botones, píldora), que capturan sus propios toques y gestos.
                behavior: HitTestBehavior.translucent,
                gestures: <Type, GestureRecognizerFactory>{
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        () => TapGestureRecognizer(),
                        (r) => r.onTap = alTocarPantalla,
                      ),
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer
                      >(
                        () => LongPressGestureRecognizer(
                          duration: duracionMantener,
                        ),
                        (r) => r.onLongPress = alMantenerPantalla,
                      ),
                },
                child: LayoutBuilder(
                  builder: (context, restricciones) =>
                      _columna(context, e, restricciones.maxHeight),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _columna(BuildContext context, EstiloApp e, double alto) {
    final r = recorrido;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: alto * _maximoArriba),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: EspaciadoApp.chico),
            child: _arriba(context, e),
          ),
        ),
        Expanded(
          child: _conMargen(
            _PlanoConControles(
              plano: plano,
              avisoOtroPiso: avisoOtroPiso,
              buscandoUbicacion: buscandoUbicacion,
              siguiendo: siguiendo,
              alCentrar: alCentrar,
            ),
          ),
        ),
        // Dice lo mismo que la indicación: TalkBack no la repite. Con letra
        // grande es lo primero que se saca, para que el plano tenga lugar.
        if (r != null && !TipografiaApp.esLetraGrande(context)) ...[
          const SizedBox(height: EspaciadoApp.medio),
          ExcludeSemantics(
            child: _conMargen(
              LineaTiempo(
                tramos: r.tramos,
                tramoActual: r.tramoActual,
                avance: r.avance,
                mostrarResumen: false,
              ),
            ),
          ),
        ],
        _FilaSenal(texto: estadoSenal, detalle: detalleSenal),
        // Para quien ve: TalkBack ya dice qué hace cada cosa.
        if (ayudaImportante || !TipografiaApp.esLetraGrande(context))
          ExcludeSemantics(
            child: _conMargen(
              Text(
                ayuda,
                textAlign: TextAlign.center,
                style: TipografiaApp.subtitulo.copyWith(
                  color: e.textoSecundario,
                ),
              ),
            ),
          ),
        const SizedBox(height: EspaciadoApp.minimo),
        BarraAcciones(
          acciones: [
            AccionPildora(
              icono: escuchando ? Icons.hearing_rounded : Icons.mic_rounded,
              texto: escuchando ? 'Escuchando...' : 'Tocá y hablá',
              etiquetaSemantica: escuchando
                  ? 'Escuchando, hablá ahora'
                  : 'Tocá aquí y decí el destino',
              principal: true,
              alPresionar: alTocarPantalla,
            ),
            if (alCancelar != null)
              AccionPildora(
                icono: Icons.close_rounded,
                texto: 'Cancelar',
                etiquetaSemantica: 'Cancelar navegación',
                alPresionar: alCancelar,
              ),
          ],
        ),
      ],
    );
  }
}

/// El destino y cómo va la ruta, con la brújula al lado. Sin destino, qué
/// hacer. Con letra grande, la brújula baja: así ninguno le pelea el ancho al
/// otro.
class _FilaDestino extends StatelessWidget {
  const _FilaDestino({
    required this.destino,
    required this.estadoRuta,
    required this.brujula,
  });

  final String? destino;
  final String estadoRuta;
  final Widget brujula;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final destino = this.destino;
    final texto = destino == null
        ? Text(
            'Tocá la pantalla para elegir destino',
            style: TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
          )
        // TalkBack lo lee de una vez: el destino y cómo va la ruta.
        : MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.place_rounded,
                      size: FormasApp.iconoChico,
                      color: e.acento,
                    ),
                    const SizedBox(width: EspaciadoApp.minimo),
                    Expanded(
                      child: Text(
                        destino,
                        style: TipografiaApp.destacado.copyWith(
                          color: e.textoPrincipal,
                        ),
                      ),
                    ),
                  ],
                ),
                if (estadoRuta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: FormasApp.iconoChico + EspaciadoApp.minimo,
                    ),
                    child: Text(
                      estadoRuta,
                      style: TipografiaApp.subtitulo.copyWith(
                        color: e.textoSecundario,
                      ),
                    ),
                  ),
              ],
            ),
          );
    if (TipografiaApp.esLetraGrande(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          texto,
          const SizedBox(height: EspaciadoApp.chico),
          brujula,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: texto),
        const SizedBox(width: EspaciadoApp.chico),
        brujula,
      ],
    );
  }
}

/// Hacia dónde mira el teléfono sobre el plano: la flecha, el punto cardinal
/// y los grados. Sin brújula, lo avisa.
class ChipOrientacion extends StatefulWidget {
  const ChipOrientacion({
    super.key,
    required this.disponible,
    this.grados,
    this.direccion,
  });

  /// Si hay brújula. Si no, un aviso en lugar de esconderse: la voz ya lo
  /// dijo, y las indicaciones de giro pueden ser menos precisas.
  final bool disponible;

  /// El rumbo sobre el plano. null: todavía no llegó ninguna lectura.
  final double? grados;

  /// El punto cardinal ("NE").
  final String? direccion;

  @override
  State<ChipOrientacion> createState() => _ChipOrientacionState();
}

class _ChipOrientacionState extends State<ChipOrientacion> {
  /// Las vueltas que se le dan a la flecha. No se quedan en [0, 1): de 359° a
  /// 1° la flecha gira 2° hacia adelante, no una vuelta entera hacia atrás.
  late double _vueltas = (widget.grados ?? 0) / 360;

  @override
  void didUpdateWidget(covariant ChipOrientacion anterior) {
    super.didUpdateWidget(anterior);
    final grados = widget.grados;
    if (grados == null) return;
    final destino = grados / 360;
    _vueltas = destino + (_vueltas - destino).roundToDouble();
  }

  /// Una pastilla hundida, como un chip de dato.
  Widget _pastilla(EstiloApp e, List<Widget> hijos) => DecoratedBox(
    decoration: DecoracionRelieve(
      color: e.hundido,
      pildora: true,
      elevacion: -1,
      tamano: TamanoRelieve.chico,
      sombraOscura: e.sombraOscura,
      sombraClara: e.sombraClara,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: EspaciadoApp.medio,
        vertical: EspaciadoApp.chico,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: hijos),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    if (!widget.disponible) {
      return Semantics(
        container: true,
        label:
            'Brújula no disponible. Las instrucciones de giro pueden ser '
            'menos precisas.',
        excludeSemantics: true,
        child: _pastilla(e, [
          Icon(
            Icons.compass_calibration_rounded,
            size: FormasApp.iconoChico,
            color: e.advertencia,
          ),
          const SizedBox(width: EspaciadoApp.minimo),
          Flexible(
            child: Text(
              'Brújula no disponible',
              style: TipografiaApp.subtitulo.copyWith(
                color: e.advertencia,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      );
    }
    final grados = widget.grados;
    if (grados == null) return const SizedBox.shrink();
    final enteros = grados.toStringAsFixed(0);
    return Semantics(
      container: true,
      label: 'Orientación: ${widget.direccion}, $enteros grados',
      excludeSemantics: true,
      child: _pastilla(e, [
        // Rota en sentido horario con el rumbo. La brújula cambia varias
        // veces por segundo: como mucho 120 ms, lo de un cambio frecuente.
        AnimatedRotation(
          turns: _vueltas,
          duration: MovimientoApp.duracion(
            context,
            MovimientoApp.cambioProgreso,
          ),
          curve: MovimientoApp.curva,
          child: Icon(
            Icons.navigation_rounded,
            size: FormasApp.iconoChico,
            color: e.acento,
          ),
        ),
        const SizedBox(width: EspaciadoApp.minimo),
        Text(
          '${widget.direccion}',
          style: TipografiaApp.subtitulo.copyWith(
            color: e.acento,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: EspaciadoApp.minimo),
        Text(
          '$enteros°',
          style: TipografiaApp.conCifrasTabulares(
            TipografiaApp.nota,
          ).copyWith(color: e.textoSecundario),
        ),
      ]),
    );
  }
}

/// Los pisos del edificio, para mirar otro sin moverse. El del usuario lleva
/// el ícono de ubicación; el que se está viendo va elegido.
class SelectorPisos extends StatelessWidget {
  const SelectorPisos({super.key, required this.pisos});

  final List<OpcionPiso> pisos;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: EspaciadoApp.margenLateral,
      ),
      child: Row(
        children: [
          Icon(
            Icons.layers_rounded,
            size: FormasApp.iconoChico,
            color: e.textoSecundario,
          ),
          for (final p in pisos) ...[
            const SizedBox(width: EspaciadoApp.chico),
            ChipFiltro(
              texto: p.etiqueta,
              icono: p.esMio ? Icons.my_location_rounded : null,
              seleccionado: p.visto,
              exclusivo: true,
              etiquetaSemantica: 'Ver ${p.nombre}${p.esMio ? ', tu piso' : ''}',
              alCambiar: (_) => p.alTocar(),
            ),
          ],
        ],
      ),
    );
  }
}

/// La tarjeta de la indicación: lo más importante de la pantalla, levantada.
/// El ícono en grande en su cuadro, el tramo, la indicación en 28 y la
/// distancia en acento. Al llegar, el aviso aparece con un fundido.
class TarjetaIndicacion extends StatelessWidget {
  const TarjetaIndicacion({super.key, required this.datos, this.tramo});

  final DatosIndicacion datos;

  /// "Tramo 2 de 3", arriba de la indicación. TalkBack no lo lee: dice la
  /// indicación con su distancia, como siempre.
  final String? tramo;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final letraGrande = TipografiaApp.esLetraGrande(context);
    final cuadro = CuadroIcono(
      icono: datos.icono,
      color: datos.tipo == TipoIndicacion.llegada ? e.hecho : e.acento,
      lado: FormasApp.cuadroIndicacion,
      tamanoIcono: FormasApp.iconoIndicacion,
    );
    final tramo = this.tramo;
    final rotulo = tramo == null
        ? null
        : Text(
            tramo,
            style: TipografiaApp.conCifrasTabulares(
              TipografiaApp.subtitulo,
            ).copyWith(color: e.textoSecundario, fontWeight: FontWeight.w600),
          );
    final titulo = Text(
      datos.titulo,
      style: TipografiaApp.instruccion.copyWith(color: e.textoPrincipal),
    );
    final detalle = Text(
      datos.detalle,
      style: datos.tipo == TipoIndicacion.guia
          ? TipografiaApp.conCifrasTabulares(
              TipografiaApp.titulo,
            ).copyWith(color: e.acento)
          : TipografiaApp.cuerpo.copyWith(color: e.textoSecundario),
    );
    return Semantics(
      container: true,
      liveRegion: datos.esLlegada,
      label: datos.etiqueta,
      excludeSemantics: true,
      child: PanelRelieve(
        child: _FundidoLlegada(
          llegada: datos.esLlegada ? datos.tipo : null,
          child: letraGrande
              // Con letra grande, el ícono arriba: el texto usa todo el ancho.
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        cuadro,
                        if (rotulo != null) ...[
                          const SizedBox(width: EspaciadoApp.medio),
                          Expanded(child: rotulo),
                        ],
                      ],
                    ),
                    const SizedBox(height: EspaciadoApp.chico),
                    titulo,
                    detalle,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cuadro,
                    const SizedBox(width: EspaciadoApp.medio),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [?rotulo, titulo, detalle],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// El contenido de la tarjeta, que aparece con un fundido cuando pasa a ser
/// un aviso de llegada: 200 ms y, con movimiento reducido, 120. Lo demás
/// cambia de golpe: las indicaciones cambian seguido.
///
/// Con un controlador propio con AnimationBehavior.preserve: con «Quitar
/// animaciones» del teléfono, un AnimatedSwitcher quedaría casi instantáneo,
/// y la tabla pide el fundido de 120 ms.
class _FundidoLlegada extends StatefulWidget {
  const _FundidoLlegada({required this.llegada, required this.child});

  /// Qué llegada se está mostrando, o null si no es una.
  final TipoIndicacion? llegada;
  final Widget child;

  @override
  State<_FundidoLlegada> createState() => _FundidoLlegadaState();
}

class _FundidoLlegadaState extends State<_FundidoLlegada>
    with SingleTickerProviderStateMixin {
  late final AnimationController _opacidad = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final CurvedAnimation _curva = CurvedAnimation(
    parent: _opacidad,
    curve: MovimientoApp.curva,
  );

  @override
  void didUpdateWidget(covariant _FundidoLlegada anterior) {
    super.didUpdateWidget(anterior);
    if (widget.llegada == null || widget.llegada == anterior.llegada) return;
    _opacidad.duration = MovimientoApp.reducido(context)
        ? MovimientoApp.fundidoReducido
        : MovimientoApp.llegada;
    _opacidad.forward(from: 0);
  }

  @override
  void dispose() {
    _curva.dispose();
    _opacidad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _curva, child: widget.child);
}

/// El plano hundido, con los carteles y el botón de centrar encima. Los
/// carteles y el botón van afuera del panel: la sombra interior cae sobre el
/// plano, nunca sobre un texto.
class _PlanoConControles extends StatelessWidget {
  const _PlanoConControles({
    required this.plano,
    required this.avisoOtroPiso,
    required this.buscandoUbicacion,
    required this.siguiendo,
    required this.alCentrar,
  });

  final Widget plano;
  final String? avisoOtroPiso;
  final bool buscandoUbicacion;
  final bool siguiendo;
  final VoidCallback alCentrar;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final avisoOtroPiso = this.avisoOtroPiso;
    final enOtroPiso = avisoOtroPiso != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        PanelRelieve(
          hundido: true,
          sombraEncima: true,
          relleno: EdgeInsets.zero,
          borde: BorderSide(color: e.borde, width: FormasApp.grosorLinea),
          child: plano,
        ),
        if (enOtroPiso || buscandoUbicacion)
          Positioned(
            top: EspaciadoApp.chico,
            left: EspaciadoApp.chico,
            right: EspaciadoApp.chico,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Queda claro que no es donde está el usuario, y TalkBack lo
                // anuncia al cambiar de piso.
                if (enOtroPiso)
                  Semantics(
                    container: true,
                    liveRegion: true,
                    child: ChipApp(
                      texto: avisoOtroPiso,
                      icono: Icons.visibility_rounded,
                    ),
                  ),
                if (buscandoUbicacion)
                  Semantics(
                    container: true,
                    child: const ChipApp(
                      texto: 'Buscando tu ubicación...',
                      icono: Icons.location_searching_rounded,
                    ),
                  ),
              ],
            ),
          ),
        Positioned(
          right: EspaciadoApp.minimo,
          bottom: EspaciadoApp.minimo,
          child: BotonRedondo(
            icono: siguiendo
                ? Icons.my_location_rounded
                : Icons.location_searching_rounded,
            etiqueta: enOtroPiso
                ? 'Volver a tu piso'
                : 'Centrar el mapa en tu ubicación',
            resaltado: !siguiendo,
            alPresionar: alCentrar,
          ),
        ),
      ],
    );
  }
}

/// El estado de la señal: un renglón con los beacons que se oyen y, si hay,
/// un dato más que se despliega. TalkBack lo lee al llegar con el foco.
class _FilaSenal extends StatefulWidget {
  const _FilaSenal({required this.texto, required this.detalle});

  final String texto;
  final String? detalle;

  @override
  State<_FilaSenal> createState() => _FilaSenalState();
}

class _FilaSenalState extends State<_FilaSenal> {
  bool _abierta = false;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final detalle = widget.detalle;
    final estilo = TipografiaApp.nota.copyWith(
      color: e.textoSecundario,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.only(
        left: EspaciadoApp.margenLateral,
        right: EspaciadoApp.minimo,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: FormasApp.areaTactilMinima,
        ),
        child: Row(
          children: [
            Icon(
              Icons.sensors_rounded,
              size: FormasApp.iconoChico,
              color: e.acento,
            ),
            const SizedBox(width: EspaciadoApp.chico),
            Expanded(
              child: Semantics(
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.texto, style: estilo),
                    if (_abierta && detalle != null)
                      Text(detalle, style: estilo),
                  ],
                ),
              ),
            ),
            if (detalle != null)
              BotonRedondo(
                icono: _abierta
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                etiqueta: _abierta
                    ? 'Ocultar el detalle de la señal'
                    : 'Ver el detalle de la señal',
                alPresionar: () => setState(() => _abierta = !_abierta),
              ),
          ],
        ),
      ),
    );
  }
}
