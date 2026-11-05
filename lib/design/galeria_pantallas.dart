import 'dart:async';

import 'package:flutter/material.dart';

import 'design.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Pantallas de referencia de la galería (sólo para debug)
// ═══════════════════════════════════════════════════════════════════════════
//
// Las dos pantallas de la sección 4 del prompt, armadas con los componentes
// y datos de ejemplo: muestran cómo se combinan antes de migrar las pantallas
// de verdad (fase 5). No tienen lógica de la app: lo que se toca sólo avisa.
//   · Navegación: barra con botones redondos, la instrucción levantada, el
//     plano hundido con la ruta, la línea de tiempo y la barra de acciones
//     con "Repetir" en acento. Tiene una simulación del recorrido (el botón
//     de reproducir de arriba) para ver el movimiento de la fase 3: el
//     cabezal sigue la posición, al cambiar de tramo recorre la ruta (con
//     una vibración suave) y al llegar aparece el aviso con un fundido (con
//     una vibración media).
//   · Elegir destino: título centrado, buscador hundido, chips, tarjetas de
//     destino y el botón "Ir a…" en acento.
// Las abre la galería (galeria_componentes.dart).

/// Una ruta de ejemplo en un piso: tres tramos hasta el Aula 12. Los puntos
/// van sobre el plano de ejemplo ([PlanoEjemplo]).
const List<TramoRuta> tramosEjemplo = [
  TramoRuta(metros: 14, puntos: [Offset(0.06, 0.5), Offset(0.45, 0.5)]),
  TramoRuta(metros: 8, puntos: [Offset(0.45, 0.5), Offset(0.68, 0.5)]),
  TramoRuta(
    metros: 12,
    marca: MarcaTramo.destino,
    descripcionMarca: 'Aula 12',
    puntos: [Offset(0.68, 0.5), Offset(0.68, 0.16)],
  ),
];

/// Proporción (ancho / alto) del plano de ejemplo.
const double proporcionPlanoEjemplo = 1.25;

/// Un plano de ejemplo: corredores (el fondo del panel), salas con su nombre
/// y los muros. Decorativo para TalkBack: lo que importa lo dice la ruta.
class PlanoEjemplo extends StatelessWidget {
  const PlanoEjemplo({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PintorPlano(
          estilo: EstiloApp.de(context),
          escalaTexto: MediaQuery.textScalerOf(context),
        ),
      ),
    );
  }
}

class _PintorPlano extends CustomPainter {
  const _PintorPlano({required this.estilo, required this.escalaTexto});

  final EstiloApp estilo;
  final TextScaler escalaTexto;

  /// Las salas, normalizadas, con su nombre.
  static const List<(Rect, String)> _salas = [
    (Rect.fromLTRB(0.03, 0.04, 0.33, 0.40), 'Aula 10'),
    (Rect.fromLTRB(0.33, 0.04, 0.62, 0.40), 'Aula 11'),
    (Rect.fromLTRB(0.74, 0.04, 0.97, 0.40), 'Aula 12'),
    (Rect.fromLTRB(0.03, 0.60, 0.40, 0.96), 'Biblioteca'),
    (Rect.fromLTRB(0.40, 0.60, 0.70, 0.96), 'Baños'),
    (Rect.fromLTRB(0.70, 0.60, 0.97, 0.96), 'Bar'),
  ];

  Rect _aPixeles(Rect r, Size s) => Rect.fromLTRB(
    r.left * s.width,
    r.top * s.height,
    r.right * s.width,
    r.bottom * s.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final muro = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = estilo.planoMuro;
    for (final (sala, nombre) in _salas) {
      final r = _aPixeles(sala, size);
      canvas
        ..drawRect(r, Paint()..color = estilo.planoHabitacion)
        ..drawRect(r, muro);
      // El nombre, en el centro de la sala; si no entra, se corta.
      final texto = TextPainter(
        text: TextSpan(
          text: nombre,
          style: TipografiaApp.leyenda.copyWith(color: estilo.planoTexto),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textScaler: escalaTexto,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: (r.width - 8).clamp(0, double.infinity));
      texto.paint(canvas, r.center - Offset(texto.width / 2, texto.height / 2));
      texto.dispose();
    }
    // El contorno del edificio.
    canvas.drawRect(
      _aPixeles(const Rect.fromLTRB(0.03, 0.04, 0.97, 0.96), size),
      muro,
    );
  }

  @override
  bool shouldRepaint(_PintorPlano anterior) =>
      anterior.estilo != estilo || anterior.escalaTexto != escalaTexto;
}

/// El plano de ejemplo hundido, con la ruta encima. El plano va en su propio
/// RepaintBoundary: cuando el cabezal se mueve, no se vuelve a pintar.
class PlanoConRuta extends StatelessWidget {
  const PlanoConRuta({
    super.key,
    required this.tramoActual,
    required this.avance,
  });

  final int tramoActual;
  final double avance;

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    // La sombra interior va encima del plano: se ve grabado en la
    // superficie.
    return PanelRelieve(
      hundido: true,
      color: e.planoCorredor,
      relleno: EdgeInsets.zero,
      sombraEncima: true,
      child: AspectRatio(
        aspectRatio: proporcionPlanoEjemplo,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(child: PlanoEjemplo()),
            LineaRuta(
              tramos: tramosEjemplo,
              tramoActual: tramoActual,
              avance: avance,
            ),
          ],
        ),
      ),
    );
  }
}

void _aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

// ─── NAVEGACIÓN ─────────────────────────────────────────────────────────────

/// La pantalla de navegación de referencia, con una simulación del
/// recorrido.
class PantallaNavegacionEjemplo extends StatefulWidget {
  const PantallaNavegacionEjemplo({super.key});

  /// Cada cuánto llega una posición en la simulación, y cuánto se avanza
  /// (unos 1,2 m/s, caminando tranquilo).
  static const Duration intervaloSimulacion = Duration(milliseconds: 600);
  static const double pasoSimulacionMetros = 0.7;

  @override
  State<PantallaNavegacionEjemplo> createState() =>
      _PantallaNavegacionEjemploState();
}

class _PantallaNavegacionEjemploState extends State<PantallaNavegacionEjemplo> {
  int _tramo = 1;
  double _avance = 0.25;
  bool _llego = false;

  /// Cambia al volver a empezar: el plano y la línea de tiempo se arman de
  /// nuevo, así el cabezal salta al principio (es otra ruta, no un
  /// movimiento).
  int _vuelta = 0;

  Timer? _reloj;

  bool get _simulando => _reloj?.isActive ?? false;

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  void _alternarSimulacion() {
    setState(() {
      if (_simulando) {
        _reloj?.cancel();
        _reloj = null;
      } else {
        _reloj = Timer.periodic(
          PantallaNavegacionEjemplo.intervaloSimulacion,
          (_) => _paso(),
        );
      }
    });
  }

  /// Una posición nueva: avanza un paso y, al terminar un tramo, pasa al
  /// siguiente (vibración suave) o llega (vibración media).
  void _paso() {
    var tramo = _tramo;
    final metros = tramosEjemplo[tramo].metros;
    var avance =
        _avance + PantallaNavegacionEjemplo.pasoSimulacionMetros / metros;
    var llego = false;
    if (avance >= 1) {
      if (tramo < tramosEjemplo.length - 1) {
        final sobra = (avance - 1) * metros;
        tramo++;
        avance = sobra / tramosEjemplo[tramo].metros;
        HapticaApp.cambioDeTramo();
      } else {
        avance = 1;
        llego = true;
        _reloj?.cancel();
        _reloj = null;
        HapticaApp.llegada();
      }
    }
    setState(() {
      _tramo = tramo;
      _avance = avance;
      _llego = llego;
    });
  }

  void _empezarDeNuevo() {
    _reloj?.cancel();
    _reloj = null;
    setState(() {
      _tramo = 0;
      _avance = 0;
      _llego = false;
      _vuelta++;
    });
  }

  /// Lo que dice la instrucción en cada tramo de la ruta de ejemplo: la
  /// indicación y la distancia (con un espacio que no se parte antes de la
  /// "m").
  static (String, String) _indicacion(int tramo, int faltan) => switch (tramo) {
    0 => ('Seguí derecho', '$faltan m'),
    1 => ('Girá a la izquierda', 'en $faltan m'),
    _ => ('Aula 12 adelante', 'a $faltan m'),
  };

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final faltan = Recorrido(
      tramos: tramosEjemplo,
      tramoActual: _tramo,
      avance: _avance,
    ).metrosQueFaltan;
    final reducido = MovimientoApp.reducido(context);
    return Scaffold(
      backgroundColor: e.fondo,
      extendBody: true,
      appBar: BarraSuperior(
        titulo: 'Aula 12',
        acciones: [
          if (_llego)
            AccionBarra(
              icono: Icons.restart_alt_rounded,
              etiqueta: 'Volver a empezar el recorrido',
              alPresionar: _empezarDeNuevo,
            )
          else
            AccionBarra(
              icono: _simulando
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              etiqueta: _simulando
                  ? 'Pausar la simulación'
                  : 'Simular el recorrido',
              alPresionar: _alternarSimulacion,
            ),
          AccionBarra(
            icono: Icons.format_list_bulleted_rounded,
            etiqueta: 'Elegir el destino de una lista',
            alPresionar: () =>
                _aviso(context, 'Elegir el destino de una lista'),
          ),
        ],
      ),
      bottomNavigationBar: Builder(
        builder: (context) => BarraAcciones(
          acciones: [
            AccionPildora(
              icono: Icons.replay_rounded,
              texto: 'Repetir',
              etiquetaSemantica: 'Repetir la indicación',
              principal: true,
              alPresionar: () =>
                  _aviso(context, 'Girá a la izquierda en $faltan metros'),
            ),
            AccionPildora(
              icono: Icons.mic_rounded,
              texto: 'Hablar',
              etiquetaSemantica: 'Pedir un destino por voz',
              alPresionar: () => _aviso(context, 'Pedir un destino por voz'),
            ),
            AccionPildora(
              icono: Icons.close_rounded,
              texto: 'Cancelar',
              etiquetaSemantica: 'Cancelar la navegación',
              alPresionar: () => _aviso(context, 'Cancelar la navegación'),
            ),
          ],
        ),
      ),
      body: Builder(
        // El relleno de abajo (la barra flotante) se lee adentro del
        // Scaffold.
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(
            EspaciadoApp.margenLateral,
            EspaciadoApp.margenLateral,
            EspaciadoApp.margenLateral,
            MediaQuery.paddingOf(context).bottom + EspaciadoApp.entreSecciones,
          ),
          children: [
            // La instrucción y, al llegar, el aviso, que aparece con un
            // fundido (200 ms; con movimiento reducido, 120 ms). El panel
            // acompaña el cambio de alto.
            PanelRelieve(
              child: AnimatedSize(
                duration: MovimientoApp.duracion(
                  context,
                  MovimientoApp.llegada,
                ),
                curve: MovimientoApp.curva,
                alignment: AlignmentDirectional.topStart,
                child: AnimatedSwitcher(
                  duration: reducido
                      ? MovimientoApp.fundidoReducido
                      : MovimientoApp.llegada,
                  switchInCurve: MovimientoApp.curva,
                  switchOutCurve: MovimientoApp.curva.flipped,
                  layoutBuilder: (actual, anteriores) => Stack(
                    alignment: AlignmentDirectional.topStart,
                    children: [...anteriores, ?actual],
                  ),
                  child: _llego
                      ? _AvisoLlegada(key: const ValueKey('llegada'), estilo: e)
                      : _Instruccion(
                          key: const ValueKey('instruccion'),
                          tramo: _tramo,
                          indicacion: _indicacion(_tramo, faltan),
                          estilo: e,
                        ),
                ),
              ),
            ),
            const SizedBox(height: EspaciadoApp.entreSecciones),
            PlanoConRuta(
              key: ValueKey(_vuelta),
              tramoActual: _tramo,
              avance: _avance,
            ),
            const SizedBox(height: EspaciadoApp.entreSecciones),
            // Dice lo mismo que la ruta del plano: TalkBack no la repite.
            ExcludeSemantics(
              child: LineaTiempo(
                key: ValueKey(_vuelta),
                tramos: tramosEjemplo,
                tramoActual: _tramo,
                avance: _avance,
                mostrarResumen: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La instrucción: el tramo, la indicación en grande y la distancia en
/// acento. Tres tamaños de letra. El número no cuenta: cambia con cada
/// posición.
class _Instruccion extends StatelessWidget {
  const _Instruccion({
    super.key,
    required this.tramo,
    required this.indicacion,
    required this.estilo,
  });

  final int tramo;
  final (String, String) indicacion;
  final EstiloApp estilo;

  @override
  Widget build(BuildContext context) {
    final (texto, distancia) = indicacion;
    final enTramo = 'Tramo ${tramo + 1} de ${tramosEjemplo.length}';
    return Semantics(
      container: true,
      label: '$enTramo. $texto, ${distancia.replaceAll(' m', ' metros')}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            enTramo,
            style: TipografiaApp.subtitulo.copyWith(
              color: estilo.textoSecundario,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: EspaciadoApp.minimo),
          Text(
            texto,
            style: TipografiaApp.tituloGrande.copyWith(
              color: estilo.textoPrincipal,
            ),
          ),
          const SizedBox(height: EspaciadoApp.minimo),
          Text(
            distancia,
            style: TipografiaApp.metricaMediana.copyWith(color: estilo.acento),
          ),
        ],
      ),
    );
  }
}

/// El aviso de llegada. El cabezal se queda en el destino.
class _AvisoLlegada extends StatelessWidget {
  const _AvisoLlegada({super.key, required this.estilo});

  final EstiloApp estilo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Llegaste a Aula 12. Está adelante',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Destino',
            style: TipografiaApp.subtitulo.copyWith(
              color: estilo.textoSecundario,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: EspaciadoApp.minimo),
          Text(
            'Llegaste a Aula 12',
            style: TipografiaApp.tituloGrande.copyWith(
              color: estilo.textoPrincipal,
            ),
          ),
          const SizedBox(height: EspaciadoApp.minimo),
          Text(
            'Está adelante',
            style: TipografiaApp.titulo.copyWith(color: estilo.acento),
          ),
        ],
      ),
    );
  }
}

// ─── ELEGIR DESTINO ─────────────────────────────────────────────────────────

/// La pantalla de referencia para elegir un destino.
class PantallaDestinoEjemplo extends StatefulWidget {
  const PantallaDestinoEjemplo({super.key});

  @override
  State<PantallaDestinoEjemplo> createState() => _PantallaDestinoEjemploState();
}

typedef _Lugar = ({
  String id,
  IconData icono,
  String nombre,
  String detalle,
  String detalleHablado,
  String rubro,
});

class _PantallaDestinoEjemploState extends State<PantallaDestinoEjemplo> {
  static const List<_Lugar> _lugares = [
    (
      id: 'aula12',
      icono: Icons.school_rounded,
      nombre: 'Aula 12',
      detalle: 'Piso 1 · a 25 m',
      detalleHablado: 'Piso 1, a 25 metros',
      rubro: 'aulas',
    ),
    (
      id: 'banio',
      icono: Icons.wc_rounded,
      nombre: 'Baño',
      detalle: 'Planta baja · a 12 m',
      detalleHablado: 'Planta baja, a 12 metros',
      rubro: 'banios',
    ),
    (
      id: 'bar',
      icono: Icons.local_cafe_rounded,
      nombre: 'Bar',
      detalle: 'Planta baja · a 40 m',
      detalleHablado: 'Planta baja, a 40 metros',
      rubro: 'comida',
    ),
    (
      id: 'aula10',
      icono: Icons.school_rounded,
      nombre: 'Aula 10',
      detalle: 'Piso 1 · a 48 m',
      detalleHablado: 'Piso 1, a 48 metros',
      rubro: 'aulas',
    ),
  ];

  static const List<(String, String)> _filtros = [
    ('todos', 'Todos'),
    ('aulas', 'Aulas'),
    ('banios', 'Baños'),
    ('comida', 'Comida'),
  ];

  String _filtro = 'todos';
  String _busqueda = '';
  String _elegido = 'aula12';

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    final visibles = [
      for (final l in _lugares)
        if ((_filtro == 'todos' || l.rubro == _filtro) &&
            l.nombre.toLowerCase().contains(_busqueda.trim().toLowerCase()))
          l,
    ];
    final elegido = _lugares.firstWhere((l) => l.id == _elegido);
    return Scaffold(
      backgroundColor: e.fondo,
      appBar: const BarraSuperior(titulo: 'Elegir destino'),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            EspaciadoApp.margenLateral,
            EspaciadoApp.chico,
            EspaciadoApp.margenLateral,
            EspaciadoApp.medio,
          ),
          child: BotonPrincipal(
            texto: 'Ir a ${elegido.nombre}',
            icono: Icons.navigation_rounded,
            alPresionar: () => _aviso(context, 'Vamos a ${elegido.nombre}'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(EspaciadoApp.margenLateral),
        children: [
          CampoTexto.busqueda(
            etiqueta: 'Buscar un destino',
            ayuda: 'Aula, baño, bar…',
            alCambiar: (texto) => setState(() => _busqueda = texto),
          ),
          const SizedBox(height: EspaciadoApp.margenLateral),
          Wrap(
            spacing: EspaciadoApp.chico,
            children: [
              for (final (valor, texto) in _filtros)
                ChipFiltro(
                  texto: texto,
                  seleccionado: _filtro == valor,
                  exclusivo: true,
                  alCambiar: (_) => setState(() => _filtro = valor),
                ),
            ],
          ),
          const SizedBox(height: EspaciadoApp.margenLateral),
          if (visibles.isEmpty)
            Text(
              'No hay lugares con ese nombre.',
              style: TipografiaApp.cuerpo.copyWith(color: e.textoSecundario),
            ),
          for (final l in visibles) ...[
            TarjetaDestino(
              icono: l.icono,
              nombre: l.nombre,
              detalle: l.detalle,
              detalleSemantico: l.detalleHablado,
              seleccionada: l.id == _elegido,
              alTocar: () => setState(() => _elegido = l.id),
            ),
            const SizedBox(height: EspaciadoApp.entreTarjetas),
          ],
        ],
      ),
    );
  }
}
