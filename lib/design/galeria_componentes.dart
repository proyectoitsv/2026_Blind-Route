import 'package:flutter/material.dart';

import 'design.dart';
import 'galeria_pantallas.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Galería de componentes (sólo para debug)
// ═══════════════════════════════════════════════════════════════════════════
//
// Todos los componentes de lib/design/components/ con datos de ejemplo, para
// verlos y probarlos con TalkBack y letra grande sin tocar las pantallas de
// la app. No la referencia ninguna de las dos apps (no entra en sus APK): la
// abre su propio punto de entrada,
//   flutter run --flavor user -t lib/main_galeria.dart
// que la instala EN LUGAR de la app del usuario. Para volver a la app,
//   flutter run --flavor user -t lib/main_user.dart
//
// Tres pestañas: Componentes, Texto (la escala tipográfica) y Colores (la
// paleta, con el contraste de cada token calculado en vivo). En Componentes
// están también las dos pantallas de referencia (Navegación, con una
// simulación del recorrido, y Elegir destino, galeria_pantallas.dart) y,
// arriba, una vista previa que fuerza la letra al 100 o al 200 % (lineal: más
// exigente que el 200 % de Android 14, que agranda menos los tamaños
// grandes) en toda la galería, hojas y pantallas de referencia incluidas, y
// los interruptores de «Reducir movimiento» y «Vibración» (los mismos de
// Ajustes en la app: la galería se instala en lugar de la app del usuario y
// comparte lo guardado). Sirve para mirar rápido; la prueba de verdad es con
// los ajustes del teléfono y TalkBack.

/// Lo que fuerza la vista previa de la galería.
@immutable
class VistaPrevia {
  const VistaPrevia({this.escalaLetra});

  /// Escala de la letra. null: la del teléfono.
  final double? escalaLetra;
}

/// La app de la galería, con el tema nuevo y el ambiente del sistema de
/// diseño (AmbienteDiseno). Aplica la [VistaPrevia] a todo, también a las
/// hojas y a las pantallas de referencia.
class AppGaleria extends StatefulWidget {
  const AppGaleria({super.key});

  @override
  State<AppGaleria> createState() => _AppGaleriaState();
}

class _AppGaleriaState extends State<AppGaleria> {
  final ValueNotifier<VistaPrevia> _vista = ValueNotifier(const VistaPrevia());

  @override
  void dispose() {
    _vista.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Galería BlindRoute',
      theme: TemaBlindRoute.oscuro,
      // Arriba del navegador: rige para todas las pantallas y las hojas.
      builder: (context, navegador) => AmbienteDiseno(
        child: ValueListenableBuilder<VistaPrevia>(
          valueListenable: _vista,
          child: navegador,
          builder: (context, vista, hijo) {
            final datos = MediaQuery.of(context);
            final escala = vista.escalaLetra;
            return MediaQuery(
              data: datos.copyWith(
                textScaler: escala == null
                    ? datos.textScaler
                    : TextScaler.linear(escala),
              ),
              child: hijo!,
            );
          },
        ),
      ),
      home: GaleriaComponentes(vistaPrevia: _vista),
    );
  }
}

/// La galería. Sin [vistaPrevia] no muestra los controles de la vista previa.
class GaleriaComponentes extends StatefulWidget {
  const GaleriaComponentes({super.key, this.vistaPrevia});

  final ValueNotifier<VistaPrevia>? vistaPrevia;

  @override
  State<GaleriaComponentes> createState() => _GaleriaComponentesState();
}

class _GaleriaComponentesState extends State<GaleriaComponentes> {
  int _pestana = 0;

  // Estado de los ejemplos.
  String _alcance = 'edificio';
  String _modo = 'beacons';
  String _filtro = 'todos';
  String _destino = 'aula12';
  bool _anunciarPiso = true;
  double _progreso = 0.45;
  int _tramo = 1;

  /// Una ruta de ejemplo entre pisos, para la línea de tiempo: ascensor al
  /// piso 1, escalera al piso 2 y el aula.
  static const List<TramoRuta> _tramosPisos = [
    TramoRuta(
      metros: 14,
      marca: MarcaTramo.ascensor,
      descripcionMarca: 'ascensor al piso 1',
    ),
    TramoRuta(
      metros: 8,
      marca: MarcaTramo.escalera,
      descripcionMarca: 'escalera al piso 2',
    ),
    TramoRuta(
      metros: 22,
      marca: MarcaTramo.destino,
      descripcionMarca: 'Aula 12',
    ),
  ];

  void _aviso(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  void _abrir(Widget pantalla) =>
      Navigator.of(context).push(RutaApp<void>(builder: (_) => pantalla));

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Scaffold(
      backgroundColor: e.fondo,
      extendBody: true,
      appBar: BarraSuperior(
        titulo: 'Galería de componentes',
        acciones: [
          AccionBarra(
            icono: Icons.info_outline_rounded,
            etiqueta: 'Acerca de la galería',
            alPresionar: () => _aviso(
              'Sólo para debug: no está en las apps. Se abre con '
              'lib/main_galeria.dart.',
            ),
          ),
        ],
      ),
      bottomNavigationBar: BarraInferior(
        pestanas: const [
          PestanaBarra(
            icono: Icons.widgets_rounded,
            iconoInactivo: Icons.widgets_outlined,
            texto: 'Componentes',
          ),
          PestanaBarra(
            icono: Icons.font_download_rounded,
            iconoInactivo: Icons.font_download_outlined,
            texto: 'Texto',
          ),
          PestanaBarra(
            icono: Icons.palette_rounded,
            iconoInactivo: Icons.palette_outlined,
            texto: 'Colores',
          ),
        ],
        seleccionada: _pestana,
        alCambiar: (i) => setState(() => _pestana = i),
      ),
      body: switch (_pestana) {
        0 => _lista('componentes', _componentes(e)),
        1 => _lista('texto', _texto(e)),
        _ => _lista('colores', _colores(e)),
      },
    );
  }

  /// Una pestaña: lista con los márgenes laterales y el relleno de la barra
  /// flotante (el Scaffold lo pasa en MediaQuery, porque el cuerpo va por
  /// detrás de ella).
  Widget _lista(String nombre, List<Widget> hijos) => Builder(
    // El relleno se lee adentro del Scaffold: el contexto de esta pantalla
    // está por encima y no sabe cuánto mide la barra.
    builder: (context) {
      final barras = MediaQuery.paddingOf(context);
      return ListView(
        key: PageStorageKey<String>(nombre),
        padding: EdgeInsets.fromLTRB(
          EspaciadoApp.margenLateral + barras.left,
          barras.top + EspaciadoApp.margenLateral,
          EspaciadoApp.margenLateral + barras.right,
          barras.bottom + EspaciadoApp.entreSecciones,
        ),
        children: hijos,
      );
    },
  );

  Widget _parrafo(EstiloApp e, String texto) => Text(
    texto,
    style: TipografiaApp.subtitulo.copyWith(color: e.textoSecundario),
  );

  static const Widget _entreSecciones = SizedBox(
    height: EspaciadoApp.entreSecciones,
  );

  /// Debajo de un encabezado y entre un componente y su explicación: más
  /// aire que el alcance de la luz del relieve, así ninguna sombra cae sobre
  /// el texto.
  static const Widget _bajoEncabezado = SizedBox(height: EspaciadoApp.medio);
  static const Widget _entreElementos = SizedBox(
    height: EspaciadoApp.margenLateral,
  );

  // ── Pestaña "Componentes" ─────────────────────────────────────────────────

  List<Widget> _componentes(EstiloApp e) => [
    _parrafo(
      e,
      'Todos los componentes de lib/design/components/, con datos de '
      'ejemplo. Sólo para debug.',
    ),
    if (widget.vistaPrevia != null) ...[
      _entreSecciones,
      _vistaPrevia(widget.vistaPrevia!),
    ],
    _entreSecciones,
    GrupoFilas(
      titulo: 'Pantallas de referencia',
      pie: 'Armadas con los componentes, sin lógica: lo que se toca avisa.',
      filas: [
        FilaGrupo(
          icono: Icons.navigation_rounded,
          titulo: 'Navegación',
          subtitulo: 'Instrucción, plano, línea de tiempo y simulación',
          navega: true,
          alTocar: () => _abrir(const PantallaNavegacionEjemplo()),
        ),
        FilaGrupo(
          icono: Icons.place_rounded,
          titulo: 'Elegir destino',
          subtitulo: 'Buscador, chips y tarjetas',
          navega: true,
          alTocar: () => _abrir(const PantallaDestinoEjemplo()),
        ),
      ],
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Relieve'),
    _bajoEncabezado,
    Row(
      children: [
        Expanded(
          child: PanelRelieve(
            child: Text(
              'Levantado',
              style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
            ),
          ),
        ),
        const SizedBox(width: EspaciadoApp.margenLateral),
        Expanded(
          child: PanelRelieve(
            hundido: true,
            child: Text(
              'Hundido',
              style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
            ),
          ),
        ),
      ],
    ),
    _bajoEncabezado,
    _parrafo(
      e,
      'Lo que se toca va levantado y se hunde al presionarlo; el plano, los '
      'campos y las pistas van hundidos. Los controles llevan además un '
      'borde de 1 px: el relieve solo no llega a 3:1.',
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Línea de ruta'),
    _bajoEncabezado,
    PlanoConRuta(tramoActual: _tramo, avance: 0.5),
    _entreElementos,
    ControlSegmentado<int>(
      etiqueta: 'Tramo actual',
      opciones: const [
        OpcionSegmento(valor: 0, texto: 'Tramo 1'),
        OpcionSegmento(valor: 1, texto: 'Tramo 2'),
        OpcionSegmento(valor: 2, texto: 'Tramo 3'),
      ],
      seleccionada: _tramo,
      alCambiar: (t) => setState(() => _tramo = t),
    ),
    _bajoEncabezado,
    _parrafo(
      e,
      'Verde, lo recorrido; acento y más grueso, el tramo actual; violeta '
      'punteado, lo que falta. El destino va en un cuadro con borde verde y '
      'el cabezal marca dónde va el usuario. Al cambiar de tramo, el cabezal '
      'recorre la ruta y los tramos cambian de color.',
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Línea de tiempo'),
    _bajoEncabezado,
    LineaTiempo(tramos: _tramosPisos, tramoActual: _tramo, avance: 0.5),
    _bajoEncabezado,
    _parrafo(
      e,
      'La misma ruta como línea de tiempo, con el ascensor, la escalera y el '
      'destino adentro de la pista. Cada tramo lleva su número.',
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Tarjetas de dato'),
    _bajoEncabezado,
    _tarjetas(),
    _bajoEncabezado,
    _parrafo(
      e,
      'Las que se tocan llevan borde y flecha, y se tocan enteras. Las '
      'demás sólo muestran.',
    ),
    _entreSecciones,
    GrupoFilas(
      titulo: 'Grupo de filas',
      pie: 'El separador arranca donde arranca el texto.',
      filas: [
        FilaGrupo(
          icono: Icons.map_rounded,
          titulo: 'Mapas disponibles',
          navega: true,
          alTocar: () => _aviso('Mapas disponibles'),
        ),
        FilaGrupo(
          icono: Icons.record_voice_over_rounded,
          titulo: 'Velocidad de la voz',
          valor: '100 %',
          navega: true,
          alTocar: () => _aviso('Velocidad de la voz'),
        ),
        FilaGrupo.interruptor(
          icono: Icons.campaign_rounded,
          titulo: 'Anunciar el piso',
          subtitulo: 'Al llegar a otro piso (de ejemplo)',
          valor: _anunciarPiso,
          alCambiar: (v) => setState(() => _anunciarPiso = v),
        ),
        const FilaGrupo(
          titulo: 'Edificio',
          subtitulo: 'Facultad de Ingeniería',
          valor: '3 pisos',
        ),
        FilaGrupo(
          icono: Icons.delete_rounded,
          titulo: 'Borrar todas',
          destructiva: true,
          alTocar: () => _aviso('Borrar todas'),
        ),
      ],
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Tarjetas de destino'),
    _bajoEncabezado,
    for (final (id, icono, nombre, detalle, hablado) in const [
      (
        'aula12',
        Icons.school_rounded,
        'Aula 12',
        'Piso 1 · a 25 m',
        'Piso 1, a 25 metros',
      ),
      (
        'banio',
        Icons.wc_rounded,
        'Baño',
        'Planta baja · a 12 m',
        'Planta baja, a 12 metros',
      ),
    ]) ...[
      TarjetaDestino(
        icono: icono,
        nombre: nombre,
        detalle: detalle,
        detalleSemantico: hablado,
        seleccionada: _destino == id,
        alTocar: () => setState(() => _destino = id),
      ),
      _entreElementos,
    ],
    _parrafo(
      e,
      'Se elige una sola: la elegida lleva el borde y la tilde en acento.',
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Botones'),
    _bajoEncabezado,
    BotonPrincipal(
      texto: 'Comenzar a navegar',
      icono: Icons.navigation_rounded,
      alPresionar: () => _aviso('Comenzar a navegar'),
    ),
    _entreElementos,
    const BotonPrincipal(texto: 'Descargar mapa', alPresionar: null),
    _entreElementos,
    BotonPrincipalGrande(
      icono: Icons.explore_rounded,
      texto: 'Comenzar a navegar',
      detalle: 'Tocá para comenzar',
      alPresionar: () => _aviso('Comenzar a navegar (grande)'),
    ),
    _entreElementos,
    BotonSecundario(
      texto: 'Mapas disponibles',
      icono: Icons.cloud_download_rounded,
      expandido: true,
      alPresionar: () => _aviso('Mapas disponibles'),
    ),
    _entreElementos,
    BotonSecundario(
      texto: 'Quitar mapa',
      icono: Icons.delete_rounded,
      destructivo: true,
      expandido: true,
      alPresionar: () => _aviso('Quitar mapa'),
    ),
    _entreElementos,
    Wrap(
      spacing: EspaciadoApp.medio,
      runSpacing: EspaciadoApp.medio,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BotonSecundario(
          texto: 'Ver todos',
          compacto: true,
          alPresionar: () => _aviso('Ver todos'),
        ),
        BotonRedondo(
          icono: Icons.search_rounded,
          etiqueta: 'Buscar',
          alPresionar: () => _aviso('Buscar'),
        ),
        BotonRedondo(
          icono: Icons.tune_rounded,
          etiqueta: 'Ajustes',
          alPresionar: () => _aviso('Ajustes'),
        ),
      ],
    ),
    _bajoEncabezado,
    _parrafo(
      e,
      'Al presionar, se hunden y se achican apenas (120 ms); al soltar, '
      'vuelven (160 ms). Un toque corto también se ve. El segundo está '
      'deshabilitado: queda plano y se sigue leyendo. El tercero es el '
      'principal en grande, el del inicio: ahí llena el lugar libre.',
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Chips'),
    _bajoEncabezado,
    const Wrap(
      spacing: EspaciadoApp.chico,
      runSpacing: EspaciadoApp.chico,
      children: [
        ChipApp(texto: 'Descargado', icono: Icons.download_done_rounded),
        ChipApp(texto: 'Piso 2'),
        ChipApp(texto: 'Actualizable', icono: Icons.update_rounded),
      ],
    ),
    _entreElementos,
    Wrap(
      spacing: EspaciadoApp.chico,
      children: [
        for (final (valor, texto) in [
          ('todos', 'Todos'),
          ('actualizables', 'Actualizables (2)'),
          ('descargados', 'Descargados (3)'),
        ])
          ChipFiltro(
            texto: texto,
            seleccionado: _filtro == valor,
            exclusivo: true,
            alCambiar: (_) => setState(() => _filtro = valor),
          ),
      ],
    ),
    _bajoEncabezado,
    _parrafo(
      e,
      'Arriba, chips de dato: hundidos, no se tocan. Abajo, de filtro: '
      'levantados con borde; el elegido, en acento con la tilde.',
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Control segmentado'),
    _bajoEncabezado,
    ControlSegmentado<String>(
      etiqueta: 'Alcance',
      opciones: const [
        OpcionSegmento(valor: 'edificio', texto: 'Este edificio'),
        OpcionSegmento(valor: 'general', texto: 'General'),
      ],
      seleccionada: _alcance,
      alCambiar: (v) => setState(() => _alcance = v),
    ),
    _entreElementos,
    ControlSegmentado<String>(
      etiqueta: 'Modo',
      opciones: const [
        OpcionSegmento(
          valor: 'beacons',
          texto: 'Beacons',
          icono: Icons.sensors_rounded,
        ),
        OpcionSegmento(
          valor: 'zonas',
          texto: 'Zonas',
          icono: Icons.block_rounded,
        ),
        OpcionSegmento(
          valor: 'lugares',
          texto: 'Lugares',
          icono: Icons.place_rounded,
        ),
      ],
      seleccionada: _modo,
      alCambiar: (v) => setState(() => _modo = v),
    ),
    _entreElementos,
    const ControlSegmentado<String>(
      etiqueta: 'Deshabilitado',
      opciones: [
        OpcionSegmento(valor: 'a', texto: 'Uno'),
        OpcionSegmento(valor: 'b', texto: 'Otro'),
      ],
      seleccionada: 'a',
      alCambiar: null,
    ),
    _bajoEncabezado,
    _parrafo(
      e,
      'El tercero está deshabilitado. Con letra grande, si las opciones no '
      'entran en una fila, se apilan.',
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Campos'),
    _bajoEncabezado,
    const CampoTexto(
      etiqueta: 'Nombre del lugar',
      ayuda: 'Por ejemplo, Aula 12',
      capitalizacion: TextCapitalization.sentences,
    ),
    _entreElementos,
    const CampoTexto.busqueda(
      etiqueta: 'Buscar un destino',
      ayuda: 'Aula, baño, bar…',
    ),
    _bajoEncabezado,
    _parrafo(
      e,
      'Hundidos, con borde. Enfocados, el borde pasa al acento. El buscador '
      'no muestra la etiqueta, pero TalkBack la dice.',
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Progreso'),
    _bajoEncabezado,
    ..._progresoEjemplos(e),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Hoja inferior'),
    _bajoEncabezado,
    BotonSecundario(
      texto: 'Abrir una hoja',
      icono: Icons.add_rounded,
      expandido: true,
      alPresionar: _abrirHoja,
    ),
    _entreSecciones,
    const EncabezadoSeccion(titulo: 'Barras'),
    _bajoEncabezado,
    _parrafo(
      e,
      'Arriba, la barra con botones redondos y el título chico, centrado. '
      'Abajo, la píldora flotante de pestañas, levantada y con borde, sin '
      'desenfoque. La de acciones está en la pantalla de navegación.',
    ),
  ];

  /// Los controles de la vista previa. Escuchan el valor, porque al cambiar
  /// la letra esta pantalla no se vuelve a armar entera. Debajo, los
  /// interruptores de movimiento y vibración, que son los de verdad.
  Widget _vistaPrevia(ValueNotifier<VistaPrevia> vista) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const EncabezadoSeccion(titulo: 'Vista previa'),
      _bajoEncabezado,
      ValueListenableBuilder<VistaPrevia>(
        valueListenable: vista,
        builder: (context, v, _) => ControlSegmentado<double?>(
          etiqueta: 'Tamaño de la letra',
          opciones: const [
            OpcionSegmento(
              valor: null,
              texto: 'Teléfono',
              etiquetaSemantica: 'La del teléfono',
            ),
            OpcionSegmento(valor: 1.0, texto: '100 %'),
            OpcionSegmento(valor: 2.0, texto: '200 %'),
          ],
          seleccionada: v.escalaLetra,
          alCambiar: (escala) => vista.value = VistaPrevia(escalaLetra: escala),
        ),
      ),
      _bajoEncabezado,
      _parrafo(
        EstiloApp.de(context),
        'Fuerza la letra en toda la galería. La prueba de verdad es con los '
        'ajustes del teléfono.',
      ),
      _entreSecciones,
      ListenableBuilder(
        listenable: AjustesMovimiento.instancia,
        builder: (context, _) {
          final ajustes = AjustesMovimiento.instancia;
          return GrupoFilas(
            titulo: 'Movimiento y vibración',
            pie:
                'Los mismos de Ajustes en la app del usuario: se guardan en '
                'el teléfono. «Quitar animaciones» del teléfono también '
                'reduce el movimiento.',
            filas: [
              FilaGrupo.interruptor(
                icono: Icons.motion_photos_off_rounded,
                titulo: 'Reducir movimiento',
                subtitulo: 'Sin deslizamientos, escalas ni resortes',
                valor: ajustes.reducirMovimiento,
                alCambiar: ajustes.cambiarReducirMovimiento,
              ),
              FilaGrupo.interruptor(
                icono: Icons.vibration_rounded,
                titulo: 'Vibración',
                subtitulo: 'En la simulación de la navegación',
                valor: ajustes.vibracion,
                alCambiar: ajustes.cambiarVibracion,
              ),
            ],
          );
        },
      ),
    ],
  );

  Widget _tarjetas() => GrillaTarjetas(
    tarjetas: [
      TarjetaDato(
        icono: Icons.signal_cellular_alt_rounded,
        etiqueta: 'Señal',
        valor: '−67',
        unidad: 'dBm',
        valorSemantico: 'menos 67 dBm',
        detalle: 'Buena',
        alTocar: () => _aviso('Señal'),
        pistaToque: 'ver el detalle',
      ),
      TarjetaDato(
        icono: Icons.my_location_rounded,
        etiqueta: 'Precisión',
        valor: '1,2',
        unidad: 'm',
        valorSemantico: '1,2 metros',
        pie: const MiniGrafico(
          valores: [3.1, 2.6, 2.8, 2.1, 1.9, 1.6, 1.7, 1.4, 1.2],
        ),
        descripcionPie: 'mejorando en el último minuto',
        alTocar: () => _aviso('Precisión'),
      ),
      const TarjetaDato(
        icono: Icons.map_rounded,
        etiqueta: 'Mapas',
        valor: '3',
        unidad: 'de 5',
        pie: AnilloProgreso(
          valor: 0.6,
          diametro: FormasApp.diametroAnilloChico,
          grosor: FormasApp.grosorAnilloChico,
        ),
        descripcionPie: '60 % descargado',
      ),
      const TarjetaDato(
        icono: Icons.route_rounded,
        etiqueta: 'Distancia',
        valor: '48',
        unidad: 'm',
        valorSemantico: '48 metros',
        detalle: 'Hasta la salida',
      ),
      const TarjetaDato(
        icono: Icons.bluetooth_searching_rounded,
        etiqueta: 'Beacons',
        valor: '2',
        unidad: 'de 6',
        detalle: 'Pocos a la vista',
        tono: TonoDato.advertencia,
      ),
      const TarjetaDato(
        icono: Icons.gps_fixed_rounded,
        etiqueta: 'Calibración',
        valor: '0',
        detalle: 'Sin calibrar',
        tono: TonoDato.error,
      ),
    ],
  );

  List<Widget> _progresoEjemplos(EstiloApp e) {
    final porcentaje = textoPorcentaje(_progreso);
    return [
      PanelRelieve(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: EspaciadoApp.margenLateral,
              runSpacing: EspaciadoApp.margenLateral,
              children: [
                AnilloProgreso(
                  valor: _progreso,
                  etiqueta: 'Descarga de planos',
                  centro: Text(
                    porcentaje,
                    style: TipografiaApp.destacado.copyWith(
                      color: e.textoPrincipal,
                      fontFeatures: TipografiaApp.cifrasTabulares,
                    ),
                  ),
                ),
                AnilloProgreso(
                  valor: 1,
                  etiqueta: 'Calibración',
                  valorSemantico: 'completa',
                  centro: Icon(
                    Icons.check_rounded,
                    size: FormasApp.icono,
                    color: e.textoPrincipal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: EspaciadoApp.margenLateral),
            Text(
              'Descargando planos',
              style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
            ),
            const SizedBox(height: EspaciadoApp.chico),
            BarraProgreso(valor: _progreso, etiqueta: 'Descarga de planos'),
            const SizedBox(height: EspaciadoApp.chico),
            Text(
              '$porcentaje · 3 de 7 pisos',
              style: TipografiaApp.conCifrasTabulares(
                TipografiaApp.nota.copyWith(color: e.textoSecundario),
              ),
            ),
            const SizedBox(height: EspaciadoApp.medio),
            Wrap(
              spacing: EspaciadoApp.medio,
              runSpacing: EspaciadoApp.medio,
              children: [
                BotonSecundario(
                  texto: 'Menos',
                  icono: Icons.remove_rounded,
                  compacto: true,
                  etiquetaSemantica: 'Bajar el progreso',
                  alPresionar: () => setState(
                    () => _progreso = (_progreso - 0.1).clamp(0.0, 1.0),
                  ),
                ),
                BotonSecundario(
                  texto: 'Más',
                  icono: Icons.add_rounded,
                  compacto: true,
                  etiquetaSemantica: 'Subir el progreso',
                  alPresionar: () => setState(
                    () => _progreso = (_progreso + 0.1).clamp(0.0, 1.0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      _bajoEncabezado,
      _parrafo(
        e,
        'Pistas hundidas con el avance en acento, sin degradado. Se llenan '
        'al aparecer (400 ms) y cada cambio tarda 120 ms; el número no '
        'cuenta. Con movimiento reducido, cambian de golpe.',
      ),
      _entreElementos,
      PanelRelieve(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Señal del último minuto',
              style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
            ),
            const SizedBox(height: EspaciadoApp.chico),
            const MiniGrafico(
              valores: [-74, -71, -72, -69, -70, -68, -67, -69, -67],
              descripcion:
                  'Señal del último minuto: subiendo, ahora en '
                  'menos 67 dBm',
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _abrirHoja() async {
    final nombre = await mostrarHoja<String>(
      context,
      titulo: 'Nuevo lugar',
      contenido: (context) => const _CargaRapida(),
    );
    if (!mounted || nombre == null) return;
    _aviso(nombre.isEmpty ? 'Guardado sin nombre' : 'Guardado: $nombre');
  }

  // ── Pestaña "Texto" ───────────────────────────────────────────────────────

  List<Widget> _texto(EstiloApp e) {
    // Palabras cortas: con la vista previa al 200 % (lineal), una palabra
    // larga en 68 dp no entra en el renglón y se parte.
    const ejemplo = 'Ruta al aula';
    final estilos = <(String, String, TextStyle, String)>[
      ('Título grande', '34 · bold', TipografiaApp.tituloGrande, ejemplo),
      ('Título', '22 · semibold', TipografiaApp.titulo, ejemplo),
      (
        'Título de sección',
        '20 · semibold',
        TipografiaApp.tituloSeccion,
        ejemplo,
      ),
      ('Título de barra', '14 · semibold', TipografiaApp.tituloBarra, ejemplo),
      ('Destacado', '17 · semibold', TipografiaApp.destacado, ejemplo),
      ('Botón', '17 · medium', TipografiaApp.boton, ejemplo),
      ('Cuerpo', '17 · regular', TipografiaApp.cuerpo, ejemplo),
      ('Subtítulo', '15 · regular', TipografiaApp.subtitulo, ejemplo),
      ('Nota', '13 · regular', TipografiaApp.nota, ejemplo),
      ('Leyenda', '12 · medium', TipografiaApp.leyenda, ejemplo),
      ('Métrica grande', '40 · semibold', TipografiaApp.metricaGrande, '1.234'),
      ('Métrica mediana', '28 · semibold', TipografiaApp.metricaMediana, '−67'),
    ];
    return [
      _parrafo(
        e,
        'La escala de TipografiaApp, en Inter. Los números van con cifras '
        'de ancho fijo, para que no bailen al cambiar.',
      ),
      _entreSecciones,
      for (final (nombre, medida, estilo, muestra) in estilos) ...[
        PanelRelieve(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(muestra, style: estilo.copyWith(color: e.textoPrincipal)),
              const SizedBox(height: EspaciadoApp.minimo),
              Text(
                '$nombre · $medida',
                style: TipografiaApp.nota.copyWith(color: e.textoSecundario),
              ),
            ],
          ),
        ),
        _entreElementos,
      ],
    ];
  }

  // ── Pestaña "Colores" ─────────────────────────────────────────────────────

  List<Widget> _colores(EstiloApp e) {
    /// Una fila de la paleta: muestra, nombre, valor y uso, y a la derecha
    /// el contraste contra [sobre].
    FilaGrupo fila(String nombre, Color color, String uso, Color sobre) =>
        FilaGrupo(
          inicio: _Muestra(color: color, borde: e.borde),
          titulo: nombre,
          subtitulo: '${_hex(color)} · $uso',
          valor: _textoContraste(_contraste(color, sobre)),
        );
    const blanco = Color(0xFFFFFFFF);

    return [
      _parrafo(
        e,
        'La paleta, token por token: valor, para qué es y, a la derecha, '
        'el contraste WCAG calculado en el teléfono. Mínimos: 4,5:1 para '
        'texto, 7:1 para texto importante y 3:1 para íconos, bordes y '
        'gráficos.',
      ),
      _entreSecciones,
      GrupoFilas(
        titulo: 'Fondos y relieve',
        pie:
            'Contra el texto principal. Las sombras son decorativas: nunca '
            'van debajo de un texto.',
        filas: [
          fila('Fondo', e.fondo, 'todas las pantallas', e.textoPrincipal),
          fila(
            'Superficie elevada',
            e.superficie,
            'tarjetas, botones, barras y hojas',
            e.textoPrincipal,
          ),
          fila(
            'Hundido',
            e.hundido,
            'plano, campos, pistas y cuadros de ícono',
            e.textoPrincipal,
          ),
          fila('Sombra oscura', e.sombraOscura, 'relieve', e.textoPrincipal),
          fila('Sombra clara', e.sombraClara, 'relieve', e.textoPrincipal),
        ],
      ),
      _entreSecciones,
      GrupoFilas(
        titulo: 'Texto y líneas',
        pie: 'Contra la superficie. El separador es decorativo.',
        filas: [
          fila(
            'Texto principal',
            e.textoPrincipal,
            'títulos y texto',
            e.superficie,
          ),
          fila(
            'Texto secundario',
            e.textoSecundario,
            'subtítulos y datos',
            e.superficie,
          ),
          fila('Borde', e.borde, 'borde de los controles', e.superficie),
          fila('Separador', e.separador, 'divisores', e.superficie),
        ],
      ),
      _entreSecciones,
      GrupoFilas(
        titulo: 'Acento y avisos',
        pie: 'Contra la superficie. El cian es el único acento.',
        filas: [
          fila(
            'Acento',
            e.acento,
            'tramo actual, botón principal, lo elegido',
            e.superficie,
          ),
          fila(
            'Advertencia',
            e.advertencia,
            'avisos no críticos',
            e.superficie,
          ),
          fila('Error', e.error, 'errores y lo destructivo', e.superficie),
          fila(
            'Texto sobre acento',
            e.textoSobreAcento,
            'botón principal, chip elegido',
            e.acento,
          ),
        ],
      ),
      _entreSecciones,
      GrupoFilas(
        titulo: 'Ruta',
        pie:
            'Contra la habitación del plano. Verde y violeta, sólo para '
            'los estados de la ruta.',
        filas: [
          fila(
            'Hecho',
            e.hecho,
            'tramo recorrido y destino',
            e.planoHabitacion,
          ),
          fila('Siguiente', e.siguiente, 'tramo que falta', e.planoHabitacion),
          fila('Acento', e.acento, 'tramo actual y cabezal', e.planoHabitacion),
        ],
      ),
      _entreSecciones,
      GrupoFilas(
        titulo: 'Plano',
        pie: 'El muro pasa 3:1 sobre el corredor, la habitación y el fondo.',
        filas: [
          fila(
            'Corredor',
            e.planoCorredor,
            'fondo del plano',
            e.textoPrincipal,
          ),
          fila('Habitación', e.planoHabitacion, 'salas', e.textoPrincipal),
          fila(
            'Muro',
            e.planoMuro,
            'paredes (contra el corredor)',
            e.planoCorredor,
          ),
          fila(
            'Texto del plano',
            e.planoTexto,
            'nombres de las salas (contra la habitación)',
            e.planoHabitacion,
          ),
          fila(
            'Ranura de la ruta',
            e.rutaRanura,
            'sombra bajo la ruta (contra el acento)',
            e.acento,
          ),
        ],
      ),
      _entreSecciones,
      GrupoFilas(
        titulo: 'Mapa de las pantallas sin migrar',
        pie:
            'Contra un plano blanco, que es lo que suele haber detrás. La '
            'ruta no llega a 3:1: en la fase 5 lleva la ranura oscura. La '
            'zona va sólo como relleno, nunca como texto.',
        filas: [
          fila('Ruta del mapa', ColoresApp.mapaRutaInicio, 'trazo', blanco),
          fila(
            'Celda del usuario',
            ColoresApp.mapaUsuario,
            'celda y flecha',
            blanco,
          ),
          fila(
            'Relleno de zona',
            ColoresApp.mapaZonaRelleno,
            'zona no transitable',
            blanco,
          ),
        ],
      ),
    ];
  }

  static double _contraste(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
    return (claro + 0.05) / (oscuro + 0.05);
  }

  /// "9,31:1", truncado como en colores.dart (nunca redondea para arriba).
  static String _textoContraste(double c) =>
      '${((c * 100).floor() / 100).toStringAsFixed(2).replaceAll('.', ',')}:1';

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Muestra de un color: un cuadro redondeado, con un contorno para que los
/// oscuros se vean sobre la tarjeta. Decorativa: el nombre del color está en
/// la fila.
class _Muestra extends StatelessWidget {
  const _Muestra({required this.color, required this.borde});

  final Color color;
  final Color borde;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: FormasApp.bordeCampo,
          border: Border.all(color: borde, width: FormasApp.grosorLinea),
        ),
      ),
    );
  }
}

/// Lo que va adentro de la hoja de ejemplo: una carga rápida.
class _CargaRapida extends StatefulWidget {
  const _CargaRapida();

  @override
  State<_CargaRapida> createState() => _CargaRapidaState();
}

class _CargaRapidaState extends State<_CargaRapida> {
  final TextEditingController _nombre = TextEditingController();
  String _rubro = 'baño';

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = EstiloApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoTexto(
          etiqueta: 'Nombre',
          ayuda: 'Por ejemplo, Baño de planta baja',
          controlador: _nombre,
          capitalizacion: TextCapitalization.sentences,
        ),
        const SizedBox(height: EspaciadoApp.margenLateral),
        Text(
          'Rubro',
          style: TipografiaApp.destacado.copyWith(color: e.textoPrincipal),
        ),
        const SizedBox(height: EspaciadoApp.minimo),
        Wrap(
          spacing: EspaciadoApp.chico,
          children: [
            for (final (rubro, texto) in const [
              ('baño', 'Baño'),
              ('comida', 'Comida'),
              ('aula', 'Aula'),
            ])
              ChipFiltro(
                texto: texto,
                seleccionado: _rubro == rubro,
                exclusivo: true,
                alCambiar: (_) => setState(() => _rubro = rubro),
              ),
          ],
        ),
        const SizedBox(height: EspaciadoApp.entreSecciones),
        BotonPrincipal(
          texto: 'Guardar',
          alPresionar: () => Navigator.of(context).pop(_nombre.text.trim()),
        ),
      ],
    );
  }
}
