import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper robusto para manejar el ciclo de vida del escaneo Bluetooth.
/// Evita crashes por setState after dispose, scans conflictivos, y permisos.
class BluetoothHelper {
  static StreamSubscription<List<ScanResult>>? _scanSubscription;
  static bool _isScanning = false;

  /// Si es true, el scan NO se detendra cuando se llame a detenerScanSeguro.
  /// Se usa cuando navegamos de ModoAutomatico a PantallaNavegacion para
  /// mantener el scan activo entre pantallas.
  static bool mantenerScanActivo = false;

  /// Verifica que Bluetooth este soportado, encendido y con permisos.
  static Future<bool> verificarPrecondiciones(BuildContext context) async {
    if (!await FlutterBluePlus.isSupported) return false;

    var state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        return false;
      }
    }

    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      return false;
    }

    var permisos = await [
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    return permisos.values.every((s) => s.isGranted);
  }

  /// Inicia el escaneo de forma segura.
  static Future<bool> iniciarScanSeguro({
    required void Function(List<ScanResult>) onResultados,
    void Function(Object)? onError,
    Duration? removeIfGone,
  }) async {
    if (_isScanning || FlutterBluePlus.isScanningNow) {
      // Si ya hay un scan activo, solo actualizamos el callback
      // NO lo detenemos para evitar perder el historial de beacons
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    }

    _isScanning = true;
    mantenerScanActivo = false; // Resetear flag

    try {
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        (resultados) {
          onResultados(resultados);
        },
        onError: (e) {
          onError?.call(e);
        },
      );

      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
        removeIfGone: removeIfGone ?? const Duration(seconds: 4),
      );

      return true;
    } catch (e) {
      _isScanning = false;
      onError?.call(e);
      return false;
    }
  }

  /// Detiene el escaneo de forma segura.
  /// Si mantenerScanActivo es true, NO detiene el scan (usado al navegar entre pantallas).
  static Future<void> detenerScanSeguro() async {
    if (mantenerScanActivo) {
      // Solo cancelamos la suscripcion anterior, pero el scan sigue activo
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      mantenerScanActivo = false;
      return;
    }

    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (e) {
      // Ignorar errores al detener
    } finally {
      _isScanning = false;
    }
  }

  static void setStateSeguro(VoidCallback setStateFn, bool mounted) {
    if (mounted) {
      setStateFn();
    }
  }
}