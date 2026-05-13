import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'beacon_model.dart';
import 'zona_model.dart';

/// Painter que dibuja los polígonos de zonas no transitables.
/// Recibe coordenadas normalizadas (0.0–1.0) y las escala al tamano del canvas.
class _ZonasPainter extends CustomPainter {
  final List<ZonaNoTransitable> zonas;
  final List<Offset> verticesEnCurso; // vértices del polígono que se está dibujando
  final Size tamanoImagen; // tamano real de la imagen renderizada dentro del contain

  _ZonasPainter({
    required this.zonas,
    required this.verticesEnCurso,
    required this.tamanoImagen,
  });

  Offset _desnormalizar(Offset normalizado) {
    return Offset(
      normalizado.dx * tamanoImagen.width,
      normalizado.dy * tamanoImagen.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paintRelleno = Paint()
      ..color = Colors.red.withOpacity(0.30)
      ..style = PaintingStyle.fill;

    final paintBorde = Paint()
      ..color = Colors.red.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final paintEnCurso = Paint()
      ..color = Colors.orange.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;

    final paintPunto = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;

    // Dibujamos zonas guardadas
    for (final zona in zonas) {
      if (zona.vertices.length < 2) continue;
      final path = Path();
      final primero = _desnormalizar(zona.vertices.first);
      path.moveTo(primero.dx, primero.dy);
      for (var i = 1; i < zona.vertices.length; i++) {
        final p = _desnormalizar(zona.vertices[i]);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, paintRelleno);
      canvas.drawPath(path, paintBorde);
    }

    // Dibujamos el polígono en construcción
    if (verticesEnCurso.isNotEmpty) {
      final path = Path();
      final primero = _desnormalizar(verticesEnCurso.first);
      path.moveTo(primero.dx, primero.dy);
      for (var i = 1; i < verticesEnCurso.length; i++) {
        final p = _desnormalizar(verticesEnCurso[i]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paintEnCurso);

      // Puntos en cada vértice para que el admin vea lo que va marcando
      for (final v in verticesEnCurso) {
        final p = _desnormalizar(v);
        canvas.drawCircle(p, 5, paintPunto);
      }
    }
  }

  @override
  bool shouldRepaint(_ZonasPainter old) =>
      old.zonas != zonas ||
      old.verticesEnCurso != verticesEnCurso ||
      old.tamanoImagen != tamanoImagen;
}

/// Widget del mapa reutilizable para configuración y navegación.
///
/// - [modoEdicion]: si true, habilita tap para colocar beacons y dibujar zonas.
/// - [onTapMapa]: callback con coordenada NORMALIZADA cuando el admin toca el mapa.
/// - [onTapBeacon]: callback cuando se hace long-press sobre un beacon (para borrar).
/// - [verticesEnCurso]: vértices del polígono que se está construyendo actualmente.
class MapaWidget extends StatelessWidget {
  final String rutaImagen;
  final Map<String, BeaconMarcado> beacons;
  final List<ZonaNoTransitable> zonas;
  final Offset? posicionUsuario; // normalizada
  final bool modoEdicion;
  final void Function(Offset normalizado)? onTapMapa;
  final void Function(String mac)? onTapBeacon;
  final List<Offset> verticesEnCurso;

  const MapaWidget({
    super.key,
    required this.rutaImagen,
    required this.beacons,
    required this.zonas,
    this.posicionUsuario,
    this.modoEdicion = false,
    this.onTapMapa,
    this.onTapBeacon,
    this.verticesEnCurso = const [],
  });

  /// Calcula el tamano real que ocupa la imagen con BoxFit.contain
  /// dentro de un contenedor de tamano [contenedor], dado el tamano
  /// original de la imagen [imagen].
  static Size calcularTamanoContenido(Size contenedor, Size imagen) {
    final ratioContenedor = contenedor.width / contenedor.height;
    final ratioImagen = imagen.width / imagen.height;
    if (ratioImagen > ratioContenedor) {
      // La imagen está limitada por el ancho
      final ancho = contenedor.width;
      final alto = ancho / ratioImagen;
      return Size(ancho, alto);
    } else {
      // La imagen está limitada por el alto
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
          future: _obtenerTamanoImagen(rutaImagen),
          builder: (context, snapshot) {
            // Mientras carga, mostramos la imagen directamente (se ajusta cuando llega el tamano)
            final tamanoImagen = snapshot.data ?? contenedor;
            final tamanoRenderizado = calcularTamanoContenido(contenedor, tamanoImagen);

            // Offset del área de imagen dentro del contenedor (centrada por contain)
            final offsetX = (contenedor.width - tamanoRenderizado.width) / 2;
            final offsetY = (contenedor.height - tamanoRenderizado.height) / 2;

            Widget mapa = Stack(
              children: [
                // Imagen con contain para no deformar
                Positioned.fill(
                  child: Image.file(
                    File(rutaImagen),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Text("Plano no disponible")),
                  ),
                ),

                // Polígonos de zonas (dibujados sobre la imagen, alineados a ella)
                Positioned(
                  left: offsetX,
                  top: offsetY,
                  width: tamanoRenderizado.width,
                  height: tamanoRenderizado.height,
                  child: CustomPaint(
                    painter: _ZonasPainter(
                      zonas: zonas,
                      verticesEnCurso: verticesEnCurso,
                      tamanoImagen: tamanoRenderizado,
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

                // Ícono del usuario
                if (posicionUsuario != null)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    left: offsetX + posicionUsuario!.dx * tamanoRenderizado.width - 15,
                    top: offsetY + posicionUsuario!.dy * tamanoRenderizado.height - 15,
                    child: const Icon(
                      Icons.person_pin_circle,
                      color: Colors.blue,
                      size: 35,
                    ),
                  ),
              ],
            );

            // En modo edición, capturamos taps y los convertimos a coordenadas normalizadas
            if (modoEdicion && onTapMapa != null) {
              mapa = GestureDetector(
                onTapDown: (det) {
                  final local = det.localPosition;
                  // Solo procesamos si el toque cayó dentro del área de la imagen
                  final dx = (local.dx - offsetX) / tamanoRenderizado.width;
                  final dy = (local.dy - offsetY) / tamanoRenderizado.height;
                  if (dx >= 0 && dx <= 1 && dy >= 0 && dy <= 1) {
                    onTapMapa!(Offset(dx, dy));
                  }
                },
                child: mapa,
              );
            }

            return mapa;
          },
        );
      },
    );
  }

  static Future<Size> _obtenerTamanoImagen(String ruta) async {
    final completer = Completer<Size>();
    final image = FileImage(File(ruta));
    image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        completer.complete(Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        ));
      }),
    );
    return completer.future;
  }
}
