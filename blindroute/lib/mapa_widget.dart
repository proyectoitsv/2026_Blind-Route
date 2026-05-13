import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';

/// Painter que dibuja los polígonos de zonas no transitables y la ruta.
class _ZonasPainter extends CustomPainter {
  final List<ZonaNoTransitable> zonas;
  final List<Offset> verticesEnCurso;
  final Size tamanoImagen;
  final List<Offset>? ruta; // NUEVO: camino calculado

  _ZonasPainter({
    required this.zonas,
    required this.verticesEnCurso,
    required this.tamanoImagen,
    this.ruta,
  });

  Offset _desnormalizar(Offset normalizado) {
    return Offset(
      normalizado.dx * tamanoImagen.width,
      normalizado.dy * tamanoImagen.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // --- Dibujar ruta calculada ---
    if (ruta != null && ruta!.length >= 2) {
      final paintRuta = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      final primero = _desnormalizar(ruta!.first);
      path.moveTo(primero.dx, primero.dy);
      for (int i = 1; i < ruta!.length; i++) {
        final p = _desnormalizar(ruta![i]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paintRuta);
    }

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
      old.tamanoImagen != tamanoImagen ||
      old.ruta != ruta;
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
  final List<Offset>? ruta;

  const MapaWidget({
    super.key,
    required this.rutaImagen,
    required this.beacons,
    required this.zonas,
    this.lugares = const [], // NUEVO
    this.posicionUsuario,
    this.modoEdicion = false,
    this.onTapMapa,
    this.onTapBeacon,
    this.onTapLugar,
    this.onTapZona, // NUEVO
    this.verticesEnCurso = const [],
    this.ruta,
  });

  static Size calcularTamanoContenido(Size contenedor, Size imagen) {
    final ratioContenedor = contenedor.width / contenedor.height;
    final ratioImagen = imagen.width / imagen.height;
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
          future: _obtenerTamanoImagen(rutaImagen),
          builder: (context, snapshot) {
            final tamanoImagen = snapshot.data ?? contenedor;
            final tamanoRenderizado = calcularTamanoContenido(contenedor, tamanoImagen);

            final offsetX = (contenedor.width - tamanoRenderizado.width) / 2;
            final offsetY = (contenedor.height - tamanoRenderizado.height) / 2;

            Widget mapa = Stack(
              children: [
                // Imagen del plano
                Positioned.fill(
                  child: Image.file(
                    File(rutaImagen),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Center(child: Text("Plano no disponible")),
                  ),
                ),

                // Polígonos de zonas + ruta (con GestureDetector para borrar en modo edición)
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
                                  _puntoEnPoligono(puntoTocado, zona.vertices)) {
                                onTapZona!(zona);
                                return;
                              }
                            }
                          }
                        : null,
                    child: CustomPaint(
                      painter: _ZonasPainter(
                        zonas: zonas,
                        verticesEnCurso: verticesEnCurso,
                        tamanoImagen: tamanoRenderizado,
                        ruta: ruta,
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
                              color: Colors.white.withOpacity(0.85),
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

  /// Ray-casting: determina si un punto está dentro de un polígono
  static bool _puntoEnPoligono(Offset punto, List<Offset> vertices) {
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