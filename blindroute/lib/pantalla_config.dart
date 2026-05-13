import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'beacon_model.dart';
import 'zona_model.dart';
import 'poi_model.dart';
import 'database.dart';
import 'procesador_senal.dart';
import 'mapa_widget.dart';

enum _ModoEdicion { beacons, zonas, lugares }

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
  List<LugarInteres> _lugares = []; // NUEVO
  List<ScanResult> _dispositivosCercanos = [];
  ScanResult? _seleccionado;
  bool _escaneando = false;
  Offset? _posicionUsuario;

  _ModoEdicion _modo = _ModoEdicion.beacons;
  List<Offset> _verticesEnCurso = [];

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    final beacons = await DatabaseHelper.instance.obtenerBeaconsPorPiso(widget.pisoId);
    final zonas = await DatabaseHelper.instance.obtenerZonasPorPiso(widget.pisoId);
    final lugares = await DatabaseHelper.instance.obtenerLugaresPorPiso(widget.pisoId);
    setState(() {
      _beaconsEnElMapa = {for (var b in beacons) b.mac: b};
      _zonas = zonas;
      _lugares = lugares;
    });
  }

  Future<void> _sincronizarBeacons() async {
    await DatabaseHelper.instance.guardarBeacons(widget.pisoId, _beaconsEnElMapa.values.toList());
  }

  // -- Beacons ---------------------------------------------------------------

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

  // -- Zonas -----------------------------------------------------------------

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

    // Nombre opcional - si no ingresa nada, usa un nombre por defecto
    final nombre = await _pedirNombreZona();
    // Si cancela el dialogo (null), descartamos
    if (nombre == null) {
      _descartarZonaEnCurso();
      return;
    }
    // Si deja vacio, usamos nombre por defecto
    final nombreFinal = nombre.isEmpty ? 'Zona prohibida' : nombre;

    final zona = ZonaNoTransitable(
      pisoId: widget.pisoId,
      nombre: nombreFinal,
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
        title: const Text('Nombre de la zona (opcional)'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Ej: Escaleras, Ascensor (dejá vacío para usar nombre por defecto)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null), // Cancelar = null
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // -- LUGARES DE INTERÉS (POI) ----------------------------------------------

  void _agregarLugar(Offset normalizado) async {
    final controller = TextEditingController();
    final descController = TextEditingController();

    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Lugar de Interés'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Nombre (ej: Baño, Terminal 5)',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                hintText: 'Descripción opcional',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final nombre = controller.text.trim();
              if (nombre.isNotEmpty) Navigator.pop(ctx, nombre);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nombre == null || nombre.isEmpty) return;

    final lugar = LugarInteres(
      pisoId: widget.pisoId,
      nombre: nombre,
      posicion: normalizado,
      descripcion: descController.text.trim().isEmpty ? null : descController.text.trim(),
    );
    final id = await DatabaseHelper.instance.crearLugarInteres(lugar);
    setState(() => _lugares.add(lugar.copyWith(id: id)));
  }

  void _borrarLugar(LugarInteres lugar) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar lugar?'),
        content: Text('Se eliminará "${lugar.nombre}".'),
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
    await DatabaseHelper.instance.eliminarLugarInteres(lugar.id!);
    setState(() => _lugares.removeWhere((l) => l.id == lugar.id));
  }

  // -- Tap en el mapa --------------------------------------------------------

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
    } else if (_modo == _ModoEdicion.zonas) {
      _agregarVertice(normalizado);
    } else if (_modo == _ModoEdicion.lugares) {
      _agregarLugar(normalizado);
    }
  }

  // -- UI --------------------------------------------------------------------

  String _hintTexto() {
    switch (_modo) {
      case _ModoEdicion.beacons:
        return 'Seleccioná un dispositivo de la lista y tocá el mapa para ubicarlo. Long-press sobre un beacon para eliminarlo.';
      case _ModoEdicion.zonas:
        if (_verticesEnCurso.isEmpty) {
          return 'Tocá el mapa para marcar los vértices de la zona. Necesitás al menos 3 puntos. Tocá una zona existente para borrarla.';
        }
        return '${_verticesEnCurso.length} punto(s) marcado(s). Seguí tocando o cerrá la zona.';
      case _ModoEdicion.lugares:
        return 'Tocá el mapa para agregar un lugar de interés. Tocá el ícono morado para eliminarlo.';
    }
  }

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
          // Selector de modo (ahora con 3 opciones)
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
                  label: Text('Zonas'),
                ),
                ButtonSegment(
                  value: _ModoEdicion.lugares,
                  icon: Icon(Icons.place),
                  label: Text('Lugares'),
                ),
              ],
              selected: {_modo},
              onSelectionChanged: (s) {
                setState(() {
                  _modo = s.first;
                  _verticesEnCurso.clear();
                  _seleccionado = null;
                });
              },
            ),
          ),

          // Hint contextual
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              _hintTexto(),
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
                  panEnabled: _modo != _ModoEdicion.zonas || _verticesEnCurso.isEmpty,
                  scaleEnabled: _modo != _ModoEdicion.zonas || _verticesEnCurso.isEmpty,
                  child: MapaWidget(
                    rutaImagen: widget.rutaImagen,
                    beacons: _beaconsEnElMapa,
                    zonas: _zonas,
                    lugares: _lugares,
                    posicionUsuario: _posicionUsuario,
                    modoEdicion: true,
                    onTapMapa: _onTapMapa,
                    onTapBeacon: _borrarBeacon,
                    onTapLugar: _borrarLugar,
                    onTapZona: _borrarZona, // NUEVO: borrar zona al tocarla
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

          // Lista de dispositivos BLE (solo en modo beacons)
          if (_modo == _ModoEdicion.beacons)
            Expanded(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      _escaneando ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                      color: _escaneando ? Colors.teal : Colors.grey,
                    ),
                    title: Text(_escaneando ? 'Buscando dispositivos...' : 'Escaner detenido'),
                    trailing: ElevatedButton.icon(
                      onPressed: _conmutarEscaner,
                      icon: Icon(_escaneando ? Icons.stop : Icons.play_arrow),
                      label: Text(_escaneando ? 'Detener' : 'Escanear'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _escaneando ? Colors.red : Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _dispositivosCercanos.length,
                      itemBuilder: (context, i) {
                        final d = _dispositivosCercanos[i];
                        final mac = d.device.remoteId.str;
                        final yaUbicado = _beaconsEnElMapa.containsKey(mac);
                        final seleccionado = _seleccionado == d;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            yaUbicado ? Icons.check_circle : Icons.bluetooth,
                            color: yaUbicado ? Colors.green : (seleccionado ? Colors.teal : Colors.grey),
                          ),
                          title: Text(d.device.advName.isEmpty ? 'Dispositivo desconocido' : d.device.advName),
                          subtitle: Text('MAC: $mac  |  RSSI: ${d.rssi} dBm'),
                          trailing: seleccionado
                              ? const Icon(Icons.touch_app, color: Colors.teal)
                              : null,
                          onTap: yaUbicado
                              ? null
                              : () => setState(() => _seleccionado = d),
                          tileColor: seleccionado ? Colors.teal.withOpacity(0.1) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Lista de lugares de interés (solo en modo lugares)
          if (_modo == _ModoEdicion.lugares)
            Expanded(
              child: _lugares.isEmpty
                  ? const Center(child: Text('No hay lugares de interés agregados'))
                  : ListView.builder(
                      itemCount: _lugares.length,
                      itemBuilder: (context, i) {
                        final l = _lugares[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place, color: Colors.purple),
                          title: Text(l.nombre),
                          subtitle: l.descripcion != null ? Text(l.descripcion!) : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _borrarLugar(l),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}