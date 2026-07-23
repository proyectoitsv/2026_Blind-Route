import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'grilla_nav.dart';
import 'asistente_trazo.dart';
import 'tema.dart';
/// Helpers de coordenadas/celdas compartidos por los painters.
Offset _desnormalizar(Offset n, Size tam) =>
    Offset(n.dx * tam.width, n.dy * tam.height);

Rect _rectCelda(Offset centroNorm, GrillaNav grilla, Size tam) {
  final rect = Rect.fromCenter(
    center: _desnormalizar(centroNorm, tam),
    width: grilla.tamCeldaX * tam.width,
    height: grilla.tamCeldaY * tam.height,
  );
  // Recorte al plano: la última celda de cada eje puede ser PARCIAL (la escala
  // rara vez es múltiplo exacto del lado de celda), así que su rectángulo se
  // sale de la imagen si no se acota. Sin esto, la celda del usuario o la
  // última celda de la ruta se pintan por fuera del borde del mapa.
  return rect.intersect(Rect.fromLTWH(0, 0, tam.width, tam.height));
}

/// Dibuja una línea punteada entre [a] y [b].
void _lineaPunteada(Canvas canvas, Offset a, Offset b, Paint paint,
    {double paso = 8.0}) {
  final d = b - a;
  final dist = d.distance;
  if (dist <= 0) return;
  final ux = d.dx / dist, uy = d.dy / dist;
  double t = 0;
  bool pintar = true;
  while (t < dist) {
    final t1 = t;
    final t2 = (t + paso / 2).clamp(0.0, dist);
    if (pintar) {
      canvas.drawLine(
        Offset(a.dx + ux * t1, a.dy + uy * t1),
        Offset(a.dx + ux * t2, a.dy + uy * t2),
        paint,
      );
    }
    t += paso / 2;
    pintar = !pintar;
  }
}

/// Painter "estático" del mapa: grilla de 1 m × 1 m, zonas no transitables,
/// celdas del camino y polígono en construcción. NO incluye la posición del
/// usuario (esa se pinta en una capa aparte) para que el movimiento del usuario
/// no obligue a repintar todo el mapa en cada actualización de posición.
class _MapaPainter extends CustomPainter {
  final List<ZonaNoTransitable> zonas;
  final List<Offset> verticesEnCurso;
  final Size tamanoImagen;
  final GrillaNav grilla;
  final List<Offset>? ruta;        // centros normalizados de las celdas del camino
  final bool mostrarGrilla;

  /// Puntos fijos de la medición de escala (violeta). 1 a 3 puntos.
  final List<Offset> puntosMedicion;

  /// Línea elástica en curso durante el arrastre de la medición (violeta).
  final Offset? elasticoDesde;
  final Offset? elasticoHasta;

  /// Centro normalizado de la celda seleccionada en modo calibración (amarillo).
  final Offset? celdaResaltada;

  /// Centros normalizados de las celdas que ya tienen calibraciones (pin ✓).
  final List<Offset> celdasCalibradas;

  /// Índice del vértice de [verticesEnCurso] que el operador está arrastrando
  /// en este momento (se resalta más grande), o null si no hay ninguno.
  final int? verticeArrastrado;

  /// Guías de alineación activas del asistente de trazo (líneas rectas).
  final List<GuiaTrazo> guias;

  /// Punto donde se ancla la etiqueta con el ángulo imantado (normalmente el
  /// punto que el operador está moviendo).
  final Offset? guiaPunto;

  _MapaPainter({
    required this.zonas,
    required this.verticesEnCurso,
    required this.tamanoImagen,
    required this.grilla,
    this.ruta,
    this.mostrarGrilla = false,
    this.puntosMedicion = const [],
    this.elasticoDesde,
    this.elasticoHasta,
    this.celdaResaltada,
    this.celdasCalibradas = const [],
    this.verticeArrastrado,
    this.guias = const [],
    this.guiaPunto,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // --- Grilla de 1 m × 1 m (rectangular: celdasX × celdasY) ---
    // El plano se muestra con la proporción real (escalaX : escalaY), así que
    // cada celda de 1 m se ve perfectamente cuadrada en pantalla. La última
    // celda de cada eje puede ser parcial (media cuadrícula): se recorta al
    // borde del plano para llenar todo el espacio.
    if (mostrarGrilla) {
      final w = tamanoImagen.width;
      final h = tamanoImagen.height;
      final paintGrilla = Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      for (int i = 0; i <= grilla.celdasX; i++) {
        final x = (i * grilla.tamCeldaX * w).clamp(0.0, w);
        canvas.drawLine(Offset(x, 0), Offset(x, h), paintGrilla);
      }
      for (int j = 0; j <= grilla.celdasY; j++) {
        final y = (j * grilla.tamCeldaY * h).clamp(0.0, h);
        canvas.drawLine(Offset(0, y), Offset(w, y), paintGrilla);
      }
    }

    // --- Celda seleccionada en modo calibración (amarillo 60%) ---
    if (celdaResaltada != null) {
      final paintCal = Paint()
        ..color = Colors.amber.withValues(alpha: 0.60)
        ..style = PaintingStyle.fill;
      canvas.drawRect(_rectCelda(celdaResaltada!, grilla, tamanoImagen), paintCal);
    }

    // --- Zonas no transitables ---
    // Item 6: rojo saturado (TemaApp.zonaRestringidaRelleno) con alpha 0.45
    // y borde sólido 2.5 px para alta visibilidad en baja visión.
    // Antes: Colors.red.withValues(alpha: 0.30) — poco contraste sobre plano.
    final paintRelleno = Paint()
      ..color = TemaApp.zonaRestringidaRelleno.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    final paintBorde = Paint()
      ..color = TemaApp.zonaRestringidaBorde
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final zona in zonas) {
      if (zona.vertices.length < 2) continue;
      final path = Path();
      final primero = _desnormalizar(zona.vertices.first, tamanoImagen);
      path.moveTo(primero.dx, primero.dy);
      for (var i = 1; i < zona.vertices.length; i++) {
        final p = _desnormalizar(zona.vertices[i], tamanoImagen);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, paintRelleno);
      canvas.drawPath(path, paintBorde);
    }

    // --- Celdas del camino hacia el destino ---
    // ruta[0] = celda del usuario, ruta.last = destino. El color se intensifica
    // hacia el destino para que la dirección del camino se vea claramente.
    // Item 6: azul eléctrico (#1565C0 → #0D47A1) con alpha 0.75, reemplaza el
    // gradiente verde que se confundía con el fondo y era invisible para baja visión.
    if (ruta != null && ruta!.isNotEmpty) {
      final n = ruta!.length;
      for (int i = 0; i < n; i++) {
        final t = n <= 1 ? 1.0 : i / (n - 1); // 0 = usuario, 1 = destino
        final color = Color.lerp(
          TemaApp.rutaActivaInicio, // azul eléctrico: cerca del usuario
          TemaApp.rutaActivaFin,    // azul marino: en el destino
          t,
        )!.withValues(alpha: TemaApp.rutaActivaAlpha);
        final paintRuta = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawRect(_rectCelda(ruta![i], grilla, tamanoImagen), paintRuta);
      }
    }

    // --- Polígono en construcción (modo edición de zonas) ---
    // Muestra el área delimitada con relleno naranja semitransparente, contorno,
    // línea de cierre punteada al primer vértice, y círculos numerados en cada punto.
    if (verticesEnCurso.isNotEmpty) {
      final path = Path();
      final primero = _desnormalizar(verticesEnCurso.first, tamanoImagen);
      path.moveTo(primero.dx, primero.dy);
      for (var i = 1; i < verticesEnCurso.length; i++) {
        final p = _desnormalizar(verticesEnCurso[i], tamanoImagen);
        path.lineTo(p.dx, p.dy);
      }

      // Relleno del área en construcción (solo si hay ≥ 3 vértices).
      if (verticesEnCurso.length >= 3) {
        path.close();
        final paintRelleno = Paint()
          ..color = Colors.orange.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, paintRelleno);
      }

      // Contorno del polígono en curso.
      final pathContorno = Path();
      pathContorno.moveTo(primero.dx, primero.dy);
      for (var i = 1; i < verticesEnCurso.length; i++) {
        final p = _desnormalizar(verticesEnCurso[i], tamanoImagen);
        pathContorno.lineTo(p.dx, p.dy);
      }
      final paintContorno = Paint()
        ..color = Colors.orange.withValues(alpha: 0.90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(pathContorno, paintContorno);

      // Línea de cierre punteada al primer vértice (visual hint de zona cerrable).
      if (verticesEnCurso.length >= 2) {
        final ultimo = _desnormalizar(verticesEnCurso.last, tamanoImagen);
        final paintCierre = Paint()
          ..color = Colors.orange.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        // Guiones entre el último punto y el primero.
        _lineaPunteada(canvas, ultimo, primero, paintCierre);
      }

      // Círculos numerados en cada vértice. Funcionan como manijas de arrastre:
      // el vértice que se está moviendo se dibuja más grande y con un halo,
      // para que quede claro cuál agarró el dedo (que además lo tapa).
      final paintCirculo = Paint()..color = Colors.orange..style = PaintingStyle.fill;
      final paintCirculoActivo = Paint()
        ..color = Colors.deepOrange..style = PaintingStyle.fill;
      final paintHalo = Paint()
        ..color = Colors.orange.withValues(alpha: 0.30)
        ..style = PaintingStyle.fill;
      final paintCirculoBorde = Paint()
        ..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.0;
      final tp = TextPainter(textDirection: TextDirection.ltr);
      for (var i = 0; i < verticesEnCurso.length; i++) {
        final c = _desnormalizar(verticesEnCurso[i], tamanoImagen);
        final activo = verticeArrastrado == i;
        final radio = activo ? 13.0 : 9.0;
        if (activo) canvas.drawCircle(c, 24, paintHalo);
        canvas.drawCircle(c, radio, activo ? paintCirculoActivo : paintCirculo);
        canvas.drawCircle(c, radio, paintCirculoBorde);
        tp.text = TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.white,
            fontSize: activo ? 12 : 9,
            fontWeight: FontWeight.bold,
          ),
        );
        tp.layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // --- Medición de escala (violeta): puntos fijos + línea elástica ---
    if (puntosMedicion.isNotEmpty || (elasticoDesde != null && elasticoHasta != null)) {
      final paintLinea = Paint()
        ..color = Colors.purple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      final paintPunto = Paint()
        ..color = Colors.purple
        ..style = PaintingStyle.fill;
      final paintBordePunto = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Líneas entre puntos fijos consecutivos.
      for (int i = 1; i < puntosMedicion.length; i++) {
        canvas.drawLine(
          _desnormalizar(puntosMedicion[i - 1], tamanoImagen),
          _desnormalizar(puntosMedicion[i], tamanoImagen),
          paintLinea,
        );
      }
      // Línea elástica en curso.
      if (elasticoDesde != null && elasticoHasta != null) {
        canvas.drawLine(
          _desnormalizar(elasticoDesde!, tamanoImagen),
          _desnormalizar(elasticoHasta!, tamanoImagen),
          paintLinea,
        );
      }
      // Puntos fijos (violeta con borde blanco).
      for (final p in puntosMedicion) {
        final c = _desnormalizar(p, tamanoImagen);
        canvas.drawCircle(c, 7, paintPunto);
        canvas.drawCircle(c, 7, paintBordePunto);
      }
    }

    // --- Pines de celdas ya calibradas (✓ verde) ---
    if (celdasCalibradas.isNotEmpty) {
      final icono = Icons.check_circle;
      final tp = TextPainter(textDirection: TextDirection.ltr);
      for (final centro in celdasCalibradas) {
        tp.text = TextSpan(
          text: String.fromCharCode(icono.codePoint),
          style: TextStyle(
            fontSize: 18,
            fontFamily: icono.fontFamily,
            package: icono.fontPackage,
            color: Colors.green[700],
          ),
        );
        tp.layout();
        final c = _desnormalizar(centro, tamanoImagen);
        tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2));
      }
    }

    // --- Guías del asistente de trazo (siempre por encima de todo) ---
    _dibujarGuias(canvas, tamanoImagen);
  }

  /// Guías de alineación: rectas punteadas magenta que atraviesan el plano por
  /// el punto de anclaje, más una etiqueta con el ángulo al que se imantó el
  /// trazo. Es la señal visual de que la línea quedó perfectamente recta.
  void _dibujarGuias(Canvas canvas, Size tam) {
    if (guias.isEmpty) return;

    final paintGuia = Paint()
      ..color = TemaApp.guiaAlineacion.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    // Los ejes tienen escalas métricas distintas, así que la dirección de la
    // guía (calculada en metros) hay que convertirla a normalizado antes de
    // dibujarla, o una guía de 45° no se vería a 45°.
    final mx = grilla.metrosX > 0 ? grilla.metrosX : 1.0;
    final my = grilla.metrosY > 0 ? grilla.metrosY : 1.0;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, tam.width, tam.height));
    for (final g in guias) {
      final rad = g.anguloGrados * pi / 180;
      var ux = cos(rad) / mx;
      var uy = sin(rad) / my;
      final n = sqrt(ux * ux + uy * uy);
      if (n == 0) continue;
      ux = ux / n * 3.0; // 3 unidades normalizadas: cruza el plano entero
      uy = uy / n * 3.0;
      final a = _desnormalizar(Offset(g.ancla.dx - ux, g.ancla.dy - uy), tam);
      final b = _desnormalizar(Offset(g.ancla.dx + ux, g.ancla.dy + uy), tam);
      _lineaPunteada(canvas, a, b, paintGuia, paso: 10);
    }
    canvas.restore();

    // Etiqueta con el ángulo, pegada al punto que se está moviendo.
    final punto = guiaPunto;
    if (punto == null) return;
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: guias.first.etiqueta,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    )..layout();
    final c = _desnormalizar(punto, tam);
    final ancho = tp.width + 12, alto = tp.height + 6;
    // Si no entra a la derecha, la etiqueta se pasa al otro lado del punto.
    var izq = c.dx + 14;
    if (izq + ancho > tam.width) izq = c.dx - 14 - ancho;
    var arriba = c.dy - 30;
    if (arriba < 0) arriba = c.dy + 14;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(izq, arriba, ancho, alto),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = TemaApp.guiaEtiqueta);
    tp.paint(canvas, Offset(rect.left + 6, rect.top + 3));
  }

  @override
  bool shouldRepaint(_MapaPainter old) =>
      old.zonas != zonas ||
      old.verticesEnCurso != verticesEnCurso ||
      old.tamanoImagen != tamanoImagen ||
      old.grilla != grilla ||
      old.ruta != ruta ||
      old.mostrarGrilla != mostrarGrilla ||
      old.puntosMedicion != puntosMedicion ||
      old.elasticoDesde != elasticoDesde ||
      old.elasticoHasta != elasticoHasta ||
      old.celdaResaltada != celdaResaltada ||
      old.celdasCalibradas != celdasCalibradas ||
      old.verticeArrastrado != verticeArrastrado ||
      old.guias != guias ||
      old.guiaPunto != guiaPunto;
}

/// Painter liviano de la posición del usuario: pinta solo la celda actual y la
/// flecha de orientación. Está en su propia capa para repintarse en cada tick
/// de posición sin redibujar la grilla, zonas ni el camino.
class _UsuarioPainter extends CustomPainter {
  final Offset? posicionUsuario; // posición normalizada
  final Size tamanoImagen;
  final GrillaNav grilla;
  final double? heading;         // grados; 0 = Norte (arriba)

  _UsuarioPainter({
    required this.posicionUsuario,
    required this.tamanoImagen,
    required this.grilla,
    this.heading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (posicionUsuario == null) return;
    final rect = _rectCelda(grilla.centroDeCelda(posicionUsuario!), grilla, tamanoImagen);
    final paintUsuario = Paint()
      ..color = TemaApp.posicionUsuario.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paintUsuario);
    final paintBordeUsuario = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, paintBordeUsuario);
    if (heading != null) _dibujarFlecha(canvas, rect.center, heading!);
  }

  /// Flecha blanca centrada en la celda del usuario que indica su orientación.
  /// heading 0° = Norte = arriba.
  void _dibujarFlecha(Canvas canvas, Offset centro, double headingGrados) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.rotate(headingGrados * pi / 180);
    final path = Path()
      ..moveTo(0, -9)
      ..lineTo(6, 6)
      ..lineTo(0, 2)
      ..lineTo(-6, 6)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UsuarioPainter old) =>
      old.posicionUsuario != posicionUsuario ||
      old.tamanoImagen != tamanoImagen ||
      old.grilla != grilla ||
      old.heading != heading;
}

/// Widget del mapa reutilizable para configuración y navegación.
class MapaWidget extends StatelessWidget {
  final String rutaImagen;
  final Map<String, BeaconMarcado> beacons;
  final List<ZonaNoTransitable> zonas;
  final List<LugarInteres> lugares; // NUEVO
  final Offset? posicionUsuario;
  final bool modoEdicion;
  final void Function(Offset normalizado)? onTapMapa;
  final void Function(String mac)? onTapBeacon;
  final void Function(LugarInteres lugar)? onTapLugar;
  final void Function(ZonaNoTransitable zona)? onTapZona; // NUEVO: borrar zona
  final List<Offset> verticesEnCurso;

  /// Camino calculado como lista de centros de celda (normalizados). Cada celda
  /// se pinta sobre la grilla.
  final List<Offset>? ruta;

  /// Si es true, dibuja la grilla de 1 m × 1 m sobre el plano.
  final bool mostrarGrilla;

  /// Definición de la grilla (escala del piso). Determina el tamaño y la
  /// cantidad de celdas que se pintan.
  final GrillaNav grilla;

  /// Heading en grados (0 = Norte, 90 = Este). Si es null la celda del usuario
  /// se pinta sin flecha de orientación.
  final double? headingUsuario;

  /// Puntos fijos de la medición de escala (violeta).
  final List<Offset> puntosMedicion;

  /// Extremos de la línea elástica en curso (violeta) durante el arrastre.
  final Offset? elasticoDesde;
  final Offset? elasticoHasta;

  /// Callbacks de arrastre con **un solo dedo** sobre el plano. Los usan tanto
  /// la herramienta de medición (modo escala, para la línea elástica) como el
  /// editor de zonas (modo zonas, para colocar y reacomodar vértices).
  /// Si [onArrastreInicio] es no nulo, el arrastre se entrega a estos callbacks
  /// en lugar de hacer pan del mapa. [onArrastreFin] no recibe posición: usar
  /// la última reportada por [onArrastreActualizar].
  final void Function(Offset normalizado)? onArrastreInicio;
  final void Function(Offset normalizado)? onArrastreActualizar;
  final void Function()? onArrastreFin;

  /// Se llama cuando el gesto en curso se cancela porque el usuario apoyó un
  /// segundo dedo (gesto de zoom). Permite descartar la línea elástica a medias
  /// o el vértice recién apoyado.
  final void Function()? onArrastreCancelar;

  /// Índice del vértice de [verticesEnCurso] que se está arrastrando (se
  /// resalta como manija activa), o null.
  final int? verticeArrastrado;

  /// Guías activas del asistente de trazo (líneas rectas). Se dibujan como
  /// rectas punteadas magenta que cruzan todo el plano.
  final List<GuiaTrazo> guias;

  /// Punto al que se pega la etiqueta con el ángulo imantado.
  final Offset? guiaPunto;

  /// Modo calibración: centro normalizado de la celda seleccionada (amarillo) y
  /// centros de las celdas que ya tienen calibraciones guardadas (pin ✓).
  final Offset? celdaResaltada;
  final List<Offset> celdasCalibradas;

  const MapaWidget({
    super.key,
    required this.rutaImagen,
    required this.beacons,
    required this.zonas,
    required this.grilla,
    this.lugares = const [],
    this.posicionUsuario,
    this.modoEdicion = false,
    this.onTapMapa,
    this.onTapBeacon,
    this.onTapLugar,
    this.onTapZona,
    this.verticesEnCurso = const [],
    this.ruta,
    this.mostrarGrilla = false,
    this.headingUsuario,
    this.puntosMedicion = const [],
    this.elasticoDesde,
    this.elasticoHasta,
    this.onArrastreInicio,
    this.onArrastreActualizar,
    this.onArrastreFin,
    this.onArrastreCancelar,
    this.celdaResaltada,
    this.celdasCalibradas = const [],
    this.verticeArrastrado,
    this.guias = const [],
    this.guiaPunto,
  });

  /// Tamaño del plano renderizado dentro del [contenedor], conservando una
  /// proporción ancho/alto. Si se pasa [aspectoForzado] (p. ej. la proporción
  /// métrica escalaX : escalaY) se usa esa en lugar de la de la imagen, de modo
  /// que las celdas de 1 m se vean cuadradas; la imagen se estira para llenar
  /// la caja resultante.
  static Size calcularTamanoContenido(Size contenedor, Size imagen,
      {double? aspectoForzado}) {
    final ratioContenedor = contenedor.width / contenedor.height;
    final ratioImagen = (aspectoForzado != null && aspectoForzado > 0 && aspectoForzado.isFinite)
        ? aspectoForzado
        : imagen.width / imagen.height;
    if (ratioImagen > ratioContenedor) {
      final ancho = contenedor.width;
      final alto = ancho / ratioImagen;
      return Size(ancho, alto);
    } else {
      final alto = contenedor.height;
      final ancho = alto * ratioImagen;
      return Size(ancho, alto);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contenedor = Size(constraints.maxWidth, constraints.maxHeight);

        return FutureBuilder<Size>(
          future: _tamanoImagenCacheado(rutaImagen),
          initialData: _cacheTamano[rutaImagen],
          builder: (context, snapshot) {
            final tamanoImagen = snapshot.data ?? contenedor;
            // Proporción métrica del piso (escalaX : escalaY). Renderizar el
            // plano con esta proporción hace que cada celda de 1 m sea cuadrada.
            final aspectoMetrico = (grilla.metrosX > 0 && grilla.metrosY > 0)
                ? grilla.metrosX / grilla.metrosY
                : null;
            final tamanoRenderizado = calcularTamanoContenido(
                contenedor, tamanoImagen,
                aspectoForzado: aspectoMetrico);

            final offsetX = (contenedor.width - tamanoRenderizado.width) / 2;
            final offsetY = (contenedor.height - tamanoRenderizado.height) / 2;

            Widget mapa = Stack(
              children: [
                // Imagen del plano, estirada (BoxFit.fill) a la caja métrica para
                // que coincida exactamente con la grilla y las capas superpuestas.
                // RepaintBoundary: no se re-rasteriza cuando solo cambian las
                // capas superpuestas (p. ej. la posición del usuario).
                Positioned(
                  left: offsetX,
                  top: offsetY,
                  width: tamanoRenderizado.width,
                  height: tamanoRenderizado.height,
                  child: RepaintBoundary(
                    child: Image.file(
                      File(rutaImagen),
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Text("Plano no disponible")),
                    ),
                  ),
                ),

                // Grilla + zonas + camino (con GestureDetector para borrar en modo edición)
                Positioned(
                  left: offsetX,
                  top: offsetY,
                  width: tamanoRenderizado.width,
                  height: tamanoRenderizado.height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: modoEdicion && onTapZona != null
                        ? (details) {
                            final local = details.localPosition;
                            final dx = local.dx / tamanoRenderizado.width;
                            final dy = local.dy / tamanoRenderizado.height;
                            final puntoTocado = Offset(dx, dy);
                            // Buscar si el toque cayó dentro de alguna zona existente
                            for (final zona in zonas) {
                              if (zona.vertices.length >= 3 &&
                                  MapaWidget.puntoEnPoligono(puntoTocado, zona.vertices)) {
                                onTapZona!(zona);
                                return;
                              }
                            }
                          }
                        : null,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _MapaPainter(
                          zonas: zonas,
                          verticesEnCurso: verticesEnCurso,
                          tamanoImagen: tamanoRenderizado,
                          grilla: grilla,
                          ruta: ruta,
                          mostrarGrilla: mostrarGrilla,
                          puntosMedicion: puntosMedicion,
                          elasticoDesde: elasticoDesde,
                          elasticoHasta: elasticoHasta,
                          celdaResaltada: celdaResaltada,
                          celdasCalibradas: celdasCalibradas,
                          verticeArrastrado: verticeArrastrado,
                          guias: guias,
                          guiaPunto: guiaPunto,
                        ),
                      ),
                    ),
                  ),
                ),

                // Beacons
                ...beacons.values.map((b) {
                  final px = offsetX + b.posicion.dx * tamanoRenderizado.width - 10;
                  final py = offsetY + b.posicion.dy * tamanoRenderizado.height - 10;
                  return Positioned(
                    left: px,
                    top: py,
                    child: GestureDetector(
                      onLongPress: modoEdicion && onTapBeacon != null
                          ? () => onTapBeacon!(b.mac)
                          : null,
                      child: Icon(
                        Icons.radio_button_checked,
                        color: modoEdicion ? Colors.red : Colors.black38,
                        size: 20,
                      ),
                    ),
                  );
                }),

                // LUGARES DE INTERÉS (POIs)
                ...lugares.map((lugar) {
                  final px = offsetX + lugar.posicion.dx * tamanoRenderizado.width - 14;
                  final py = offsetY + lugar.posicion.dy * tamanoRenderizado.height - 28;
                  return Positioned(
                    left: px,
                    top: py,
                    child: GestureDetector(
                      onTap: onTapLugar != null ? () => onTapLugar!(lugar) : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.place,
                            color: modoEdicion ? Colors.purple : Colors.purple[700],
                            size: 28,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              lugar.nombre,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: modoEdicion ? Colors.purple[800] : Colors.purple[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // Celda del usuario (capa liviana propia: se repinta en cada
                // tick de posición sin redibujar grilla/zonas/camino).
                if (posicionUsuario != null)
                  Positioned(
                    left: offsetX,
                    top: offsetY,
                    width: tamanoRenderizado.width,
                    height: tamanoRenderizado.height,
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _UsuarioPainter(
                            posicionUsuario: posicionUsuario,
                            tamanoImagen: tamanoRenderizado,
                            grilla: grilla,
                            heading: headingUsuario,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );

            // Convierte una posición local del gesto a coordenada normalizada
            // recortada a [0, 1].
            Offset aNormalizado(Offset local) {
              final dx = ((local.dx - offsetX) / tamanoRenderizado.width).clamp(0.0, 1.0);
              final dy = ((local.dy - offsetY) / tamanoRenderizado.height).clamp(0.0, 1.0);
              return Offset(dx, dy);
            }

            final bool hayArrastre = modoEdicion && onArrastreInicio != null;

            if (modoEdicion && onTapMapa != null) {
              mapa = GestureDetector(
                onTapDown: (det) {
                  final local = det.localPosition;
                  final dx = (local.dx - offsetX) / tamanoRenderizado.width;
                  final dy = (local.dy - offsetY) / tamanoRenderizado.height;
                  if (dx >= 0 && dx <= 1 && dy >= 0 && dy <= 1) {
                    onTapMapa!(Offset(dx, dy));
                  }
                },
                child: mapa,
              );
            }

            // Medición de escala: un dedo dibuja la línea elástica; al apoyar un
            // segundo dedo se cancela y el InteractiveViewer hace zoom. Usamos un
            // Listener (eventos crudos de puntero) porque no compite en la arena
            // de gestos con el zoom del InteractiveViewer.
            if (hayArrastre) {
              mapa = _ArrastreUnDedo(
                aNormalizado: aNormalizado,
                onInicio: onArrastreInicio!,
                onActualizar: onArrastreActualizar,
                onFin: onArrastreFin,
                onCancelar: onArrastreCancelar,
                child: mapa,
              );
            }

            return mapa;
          },
        );
      },
    );
  }

  // Cache del tamaño de cada imagen por ruta. Evita re-resolver la imagen (y
  // fugar ImageStreamListeners) en cada rebuild, que durante la navegación
  // saturaba el hilo de UI y congelaba la pantalla.
  static final Map<String, Size> _cacheTamano = {};
  static final Map<String, Future<Size>> _cacheFuturo = {};

  static Future<Size> _tamanoImagenCacheado(String ruta) {
    return _cacheFuturo.putIfAbsent(ruta, () => _obtenerTamanoImagen(ruta));
  }

  static Future<Size> _obtenerTamanoImagen(String ruta) {
    final completer = Completer<Size>();
    final stream = FileImage(File(ruta)).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
        _cacheTamano[ruta] = size;
        if (!completer.isCompleted) completer.complete(size);
        stream.removeListener(listener); // liberar el listener: sin fuga
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Ray-casting: determina si un punto está dentro de un polígono.
  /// Público para que las pantallas puedan reusarlo (p. ej. la configuración,
  /// para saber si un toque cayó sobre una zona ya creada).
  static bool puntoEnPoligono(Offset punto, List<Offset> vertices) {
    bool dentro = false;
    int j = vertices.length - 1;
    for (int i = 0; i < vertices.length; i++) {
      final vi = vertices[i];
      final vj = vertices[j];
      if (((vi.dy > punto.dy) != (vj.dy > punto.dy)) &&
          (punto.dx < (vj.dx - vi.dx) * (punto.dy - vi.dy) / (vj.dy - vi.dy) + vi.dx)) {
        dentro = !dentro;
      }
      j = i;
    }
    return dentro;
  }
}

/// Captura gestos de **un solo dedo** sobre el plano con eventos crudos de
/// puntero (Listener): la medición de escala (línea elástica) y la edición de
/// vértices de zonas prohibidas. Apoyar un **segundo dedo** cancela el gesto en
/// curso y deja que el InteractiveViewer haga zoom. A diferencia de un
/// GestureDetector con onPan*, el Listener no compite en la arena de gestos,
/// así que convive con el zoom del InteractiveViewer y con los taps internos
/// del mapa (p. ej. tocar una zona existente para borrarla).
class _ArrastreUnDedo extends StatefulWidget {
  final Offset Function(Offset local) aNormalizado;
  final void Function(Offset normalizado) onInicio;
  final void Function(Offset normalizado)? onActualizar;
  final void Function()? onFin;
  final void Function()? onCancelar;
  final Widget child;

  const _ArrastreUnDedo({
    required this.aNormalizado,
    required this.onInicio,
    required this.onActualizar,
    required this.onFin,
    required this.onCancelar,
    required this.child,
  });

  @override
  State<_ArrastreUnDedo> createState() => _ArrastreUnDedoState();
}

class _ArrastreUnDedoState extends State<_ArrastreUnDedo> {
  final Set<int> _punteros = {};
  bool _midiendo = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _punteros.add(e.pointer);
        if (_punteros.length == 1) {
          _midiendo = true;
          widget.onInicio(widget.aNormalizado(e.localPosition));
        } else if (_midiendo) {
          // Segundo dedo: el gesto pasa a ser zoom. Cancelar la medición.
          _midiendo = false;
          widget.onCancelar?.call();
        }
      },
      onPointerMove: (e) {
        if (_midiendo && _punteros.length == 1) {
          widget.onActualizar?.call(widget.aNormalizado(e.localPosition));
        }
      },
      onPointerUp: (e) {
        _punteros.remove(e.pointer);
        if (_midiendo && _punteros.isEmpty) {
          _midiendo = false;
          widget.onFin?.call();
        }
      },
      onPointerCancel: (e) {
        _punteros.remove(e.pointer);
        if (_midiendo && _punteros.isEmpty) {
          _midiendo = false;
          widget.onCancelar?.call();
        }
      },
      child: widget.child,
    );
  }
}