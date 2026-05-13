import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'database.dart';
import 'procesador_senal.dart';
import 'mapa_widget.dart';

enum _ModoEdicion { beacons, zonas }

class PantallaConfiguracion extends StatefulWidget {
  final int pisoId;
  final String rutaImagen;

  const PantallaConfiguracion({
    super.key,
    required this.pisoId,
    required this.rutaImagen,
  });

  @override
  State<PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<PantallaConfiguracion> {
  final ProcesadorSenal _procesador = ProcesadorSenal();

  Map<String, BeaconMarcado> _beaconsEnElMapa = {};
  List<ZonaNoTransitable> _zonas = [];
  List<ScanResult> _dispositivosCercanos = [];
  ScanResult? _seleccionado;
  bool _escaneando = false;
  Offset? _posicionUsuario; // normalizada

  // Control de modo de edición
  _ModoEdicion _modo = _ModoEdicion.beacons;

  // Vértices del polígono que se está dibujando en este momento
  List<Offset> _verticesEnCurso = [];

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
    final zonas = await DatabaseHelper.instance.obtenerZonasPorPiso(widget.pisoId);
    setState(() {
      _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
      _zonas = zonas;
    });
  }

  Future<void> _sincronizarBeacons() async {
    await DatabaseHelper.instance.guardarBeacons(widget.pisoId, _beaconsEnElMapa.values.toList());
  }

  // ── Beacons ────────────────────────────────────────────────────────────────

  void _borrarBeacon(String mac) async {
    setState(() => _beaconsEnElMapa.remove(mac));
    await _sincronizarBeacons();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Beacon eliminado")),
    );
  }

  void _conmutarEscaner() async {
    if (_escaneando) {
      await FlutterBluePlus.stopScan();
      setState(() => _escaneando = false);
      return;
    }
    var permisos = await [Permission.bluetoothScan, Permission.location].request();
    if (permisos.values.every((s) => s.isGranted)) {
      setState(() => _escaneando = true);
      await FlutterBluePlus.startScan(continuousUpdates: true);
      FlutterBluePlus.scanResults.listen((resultados) {
        if (!mounted) return;
        setState(() => _dispositivosCercanos = resultados);
        _actualizarSenales(resultados);
      });
    }
  }

  void _actualizarSenales(List<ScanResult> resultados) {
    for (var res in resultados) {
      String mac = res.device.remoteId.str;
      double? rssiSuave = _procesador.filtrarYPromediar(mac, res.rssi);
      if (rssiSuave != null && _beaconsEnElMapa.containsKey(mac)) {
        setState(() => _beaconsEnElMapa[mac]!.rssiFiltrado = rssiSuave);
      }
    }
    _calcularPosicion();
  }

  void _calcularPosicion() {
    var activos = _beaconsEnElMapa.values.where((b) => b.rssiFiltrado > -95).toList();
    if (activos.length < 2) return;
    double sumaX = 0, sumaY = 0, sumaPesos = 0;
    for (var b in activos) {
      double peso = pow(10, (b.rssiFiltrado + 100) / 20).toDouble();
      sumaX += b.posicion.dx * peso;
      sumaY += b.posicion.dy * peso;
      sumaPesos += peso;
    }
    if (sumaPesos > 0) {
      setState(() => _posicionUsuario = Offset(sumaX / sumaPesos, sumaY / sumaPesos));
    }
  }

  // ── Zonas ──────────────────────────────────────────────────────────────────

  void _agregarVertice(Offset normalizado) {
    setState(() => _verticesEnCurso.add(normalizado));
  }

  void _cerrarZona() async {
    if (_verticesEnCurso.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Necesitás al menos 3 puntos para cerrar la zona")),
      );
      return;
    }

    final nombre = await _pedirNombreZona();
    if (nombre == null || nombre.isEmpty) return;

    final zona = ZonaNoTransitable(
      pisoId: widget.pisoId,
      nombre: nombre,
      vertices: List.from(_verticesEnCurso),
    );
    final id = await DatabaseHelper.instance.crearZona(zona);
    setState(() {
      _zonas.add(zona.copyWith(id: id));
      _verticesEnCurso.clear();
    });
  }

  void _descartarZonaEnCurso() {
    setState(() => _verticesEnCurso.clear());
  }

  void _borrarZona(ZonaNoTransitable zona) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar zona?'),
        content: Text('Se eliminará "${zona.nombre}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await DatabaseHelper.instance.eliminarZona(zona.id!);
    setState(() => _zonas.removeWhere((z) => z.id == zona.id));
  }

  Future<String?> _pedirNombreZona() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre de la zona'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Ej: Escaleras, Ascensor, Oficina cerrada',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // ── Tap en el mapa ─────────────────────────────────────────────────────────

  void _onTapMapa(Offset normalizado) {
    if (_modo == _ModoEdicion.beacons) {
      if (_seleccionado == null) return;
      String mac = _seleccionado!.device.remoteId.str;
      setState(() {
        _beaconsEnElMapa[mac] = BeaconMarcado(
          posicion: normalizado,
          nombre: _seleccionado!.device.advName.isEmpty ? 'Beacon' : _seleccionado!.device.advName,
          mac: mac,
        );
        _seleccionado = null;
      });
      _sincronizarBeacons();
    } else {
      _agregarVertice(normalizado);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Piso'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Selector de modo
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: SegmentedButton<_ModoEdicion>(
              segments: const [
                ButtonSegment(
                  value: _ModoEdicion.beacons,
                  icon: Icon(Icons.router),
                  label: Text('Beacons'),
                ),
                ButtonSegment(
                  value: _ModoEdicion.zonas,
                  icon: Icon(Icons.block),
                  label: Text('Zonas no transitables'),
                ),
              ],
              selected: {_modo},
              onSelectionChanged: (s) {
                setState(() {
                  _modo = s.first;
                  _verticesEnCurso.clear(); // descartamos si cambiamos de modo
                });
              },
            ),
          ),

          // Hint contextual
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              _modo == _ModoEdicion.beacons
                  ? 'Seleccioná un dispositivo de la lista y tocá el mapa para ubicarlo. Long-press sobre un beacon para eliminarlo.'
                  : _verticesEnCurso.isEmpty
                      ? 'Tocá el mapa para marcar los vértices de la zona. Necesitás al menos 3 puntos.'
                      : '${_verticesEnCurso.length} punto(s) marcado(s). Seguí tocando o cerrá la zona.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),

          // Mapa
          SizedBox(
            height: 380,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InteractiveViewer(
                  // En modo zonas con vértices en curso deshabilitamos el pan/zoom
                  // para que los taps se registren como vértices y no como gestos
                  panEnabled: _verticesEnCurso.isEmpty,
                  scaleEnabled: _verticesEnCurso.isEmpty,
                  child: MapaWidget(
                    rutaImagen: widget.rutaImagen,
                    beacons: _beaconsEnElMapa,
                    zonas: _zonas,
                    posicionUsuario: _posicionUsuario,
                    modoEdicion: true,
                    onTapMapa: _onTapMapa,
                    onTapBeacon: _borrarBeacon,
                    verticesEnCurso: _verticesEnCurso,
                  ),
                ),
              ),
            ),
          ),

          // Botones de acción para zonas
          if (_modo == _ModoEdicion.zonas)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _verticesEnCurso.isNotEmpty ? _descartarZonaEnCurso : null,
                      icon: const Icon(Icons.undo),
                      label: const Text('Descartar'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _verticesEnCurso.length >= 3 ? _cerrarZona : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Cerrar zona'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]),
                    ),
                  ),
                ],
              ),
            ),

          // Panel inferior: beacons o lista de zonas
          if (_modo == _ModoEdicion.beacons) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ElevatedButton.icon(
                onPressed: _conmutarEscaner,
                icon: Icon(_escaneando ? Icons.stop : Icons.play_arrow),
                label: Text(_escaneando ? 'Detener rastreo' : 'Probar rastreo'),
              ),
            ),
            const Divider(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _dispositivosCercanos.length,
                itemBuilder: (context, i) {
                  final d = _dispositivosCercanos[i];
                  return ListTile(
                    dense: true,
                    tileColor: _seleccionado == d ? Colors.teal[50] : null,
                    title: Text(d.device.advName.isEmpty ? "Desconocido" : d.device.advName),
                    subtitle: Text("${d.device.remoteId.str} | ${d.rssi} dBm"),
                    onTap: () => setState(() => _seleccionado = d),
                  );
                },
              ),
            ),
          ] else ...[
            const Divider(height: 8),
            Expanded(
              child: _zonas.isEmpty
                  ? Center(
                      child: Text(
                        'No hay zonas definidas',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _zonas.length,
                      itemBuilder: (context, i) {
                        final zona = _zonas[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.block, color: Colors.red),
                          title: Text(zona.nombre),
                          subtitle: Text('${zona.vertices.length} vértices'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _borrarZona(zona),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
