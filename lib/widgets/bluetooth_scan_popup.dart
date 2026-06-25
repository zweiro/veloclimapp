import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensor_logging/utils.dart';

/// A widget that displays a popup dialog for scanning and selecting Bluetooth devices.
///
/// This widget handles all the logic for:
/// - Ensuring Bluetooth is enabled (and attempts to enable it if not)
/// - Checking location permissions and GPS status (required for BLE scan on Android)
/// - Scanning for devices whose name starts with 'VC_SENS'
/// - Displaying a list of found devices and allowing the user to select one
/// - Showing progress indicators and error messages as needed
class BluetoothScanPopup extends StatefulWidget {
  /// Whether a sensor is currently running/connected.
  final bool isRunning;

  /// Callback when a device is selected from the scan results.
  final Function(BluetoothDevice device) onDeviceSelected;

  const BluetoothScanPopup({
    super.key,
    required this.onDeviceSelected,
    required this.isRunning,
  });

  @override
  State<BluetoothScanPopup> createState() => _BluetoothScanPopupState();
}

class _BluetoothScanPopupState extends State<BluetoothScanPopup> {
  BluetoothDevice? _connectedDevice;

  /// Shows the scan dialog, handling all permission and adapter state checks.
  void _showScanDialog(BuildContext context) async {
    // Check Bluetooth adapter state before scanning
    BluetoothAdapterState currentBluetoothState =
        await FlutterBluePlus.adapterState.first;

    if (currentBluetoothState != BluetoothAdapterState.on) {
      Utils.showSnackBar(
        'Bluetooth is OFF. Attempting to turn on Bluetooth...',
        context,
      );
      await FlutterBluePlus.turnOn();

      // Wait for Bluetooth to turn ON, with timeout
      try {
        currentBluetoothState = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        Utils.showSnackBar(
          'Bluetooth did not turn on in time. Please enable it manually.',
          context,
        );
        return;
      } catch (e) {
        Utils.showSnackBar(
          'Error turning on Bluetooth: $e. Please enable it manually.',
          context,
        );
        return;
      }

      if (currentBluetoothState != BluetoothAdapterState.on) {
        Utils.showSnackBar(
          'Bluetooth is still off despite attempt. Please enable it manually.',
          context,
        );
        return;
      }
    }

    // Check for location permissions (required for BLE scan)
    if (!(await Permission.locationAlways.isGranted ||
        await Permission.locationWhenInUse.isGranted)) {
      Utils.showSnackBar(
        'Location permission (Always or While in Use) is required for GPS logging.',
        context,
      );
      return;
    }

    // Check if GPS is enabled
    if (!await Geolocator.isLocationServiceEnabled()) {
      // Show dialog to prompt user to enable GPS
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('GPS désactivé'),
          content: const Text(
            'Le GPS est désactivé. Veuillez l\'activer dans les paramètres pour continuer.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Geolocator.openLocationSettings();
                Navigator.of(context).pop();
              },
              child: const Text('Ouvrir les paramètres'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
          ],
        ),
      );
      return;
    }

    // All checks passed, show the scan dialog
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _BluetoothScanDialog(
        onDeviceSelected: (device) {
          setState(() {
            _connectedDevice = device;
          });
          widget.onDeviceSelected(device);
        },
        connectedDevice: _connectedDevice,
        isRunning: widget.isRunning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: () => _showScanDialog(context),
      icon: const Icon(Icons.bluetooth_searching),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Internal dialog widget that performs the Bluetooth scan and displays results.
///
/// - Scans for devices whose name starts with 'VC_SENS'
/// - Shows a progress indicator while scanning
/// - Allows the user to refresh the scan or select a device
class _BluetoothScanDialog extends StatefulWidget {
  final Function(BluetoothDevice device) onDeviceSelected;
  final BluetoothDevice? connectedDevice;
  final bool isRunning;

  const _BluetoothScanDialog({
    required this.onDeviceSelected,
    required this.connectedDevice,
    required this.isRunning,
  });

  @override
  State<_BluetoothScanDialog> createState() => _BluetoothScanDialogState();
}

class _BluetoothScanDialogState extends State<_BluetoothScanDialog> {
  List<BluetoothDevice> _devices = [];
  bool _isScanning = true;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _scanTimeout;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    _scanTimeout?.cancel();
    super.dispose();
  }

  /// Starts the Bluetooth scan and updates the device list.
  Future<void> _startScan() async {
    // Check Bluetooth adapter state before scanning
    BluetoothAdapterState currentBluetoothState =
        await FlutterBluePlus.adapterState.first;

    if (currentBluetoothState != BluetoothAdapterState.on) {
      Utils.showSnackBar(
        'Bluetooth is OFF. Attempting to turn on Bluetooth...',
        context,
      );
      await FlutterBluePlus.turnOn();

      // Wait for Bluetooth to turn ON, with timeout
      try {
        currentBluetoothState = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        Utils.showSnackBar(
          'Bluetooth did not turn on in time. Please enable it manually.',
          context,
        );
        return;
      } catch (e) {
        Utils.showSnackBar(
          'Error turning on Bluetooth: $e. Please enable it manually.',
          context,
        );
        return;
      }

      if (currentBluetoothState != BluetoothAdapterState.on) {
        Utils.showSnackBar(
          'Bluetooth is still off despite attempt. Please enable it manually.',
          context,
        );
        return;
      }
    }

    // Check for location permissions (required for BLE scan)
    if (!(await Permission.locationAlways.isGranted ||
        await Permission.locationWhenInUse.isGranted)) {
      Utils.showSnackBar(
        'Location permission (Always or While in Use) is required for GPS logging.',
        context,
      );
      return;
    }

    // Check if GPS is enabled
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() {
        _devices = [];
        _isScanning = false;
      });
      // Show dialog to prompt user to enable GPS
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('GPS désactivé'),
          content: const Text(
            'Le GPS est désactivé. Veuillez l\'activer dans les paramètres pour continuer.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Geolocator.openLocationSettings(); //open the location settings
                Navigator.of(context).pop();
              },
              child: const Text('Ouvrir les paramètres'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _devices = [];
      _isScanning = true;
    });

    // Start BLE scan for 5 seconds
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    // Listen for scan results and filter for devices with name starting with 'VC_SENS'
    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _devices = results
            .map((r) => r.device)
            .where((d) => d.name.startsWith('VC_SENS'))
            .toSet()
            .toList();
        // If a device is already connected and running, ensure it appears in the list
        if (widget.connectedDevice != null &&
            !_devices.contains(widget.connectedDevice) &&
            widget.isRunning &&
            widget.connectedDevice!.name.startsWith('VC_SENS')) {
          _devices.add(widget.connectedDevice!);
        }
      });
    });

    // Stop scan after timeout and update UI
    _scanTimeout?.cancel();
    _scanTimeout = Timer(const Duration(seconds: 5), () {
      FlutterBluePlus.stopScan();
      setState(() {
        _isScanning = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.bluetooth_searching, color: Colors.blue),
          const SizedBox(width: 8),
          const Text(
            'Capteurs trouvés',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height:
            MediaQuery.of(context).size.height * 0.2, // popup is 20% of screen height
        child: _isScanning && _devices.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            : _devices.isEmpty
            ? const Center(
                child: Text(
                  'Aucun appareil trouvé',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : ListView.separated(
                itemCount: _devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  final isConnected =
                      widget.connectedDevice != null &&
                      (device.id == widget.connectedDevice!.id) &&
                      widget.isRunning;
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(
                      device.name.isNotEmpty
                          ? device.name
                          : device.id.toString(),
                    ),
                    subtitle: Text(device.id.toString()),
                    trailing: isConnected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      widget.onDeviceSelected(device);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isScanning
              ? null
              : () {
                  _startScan();
                },
          child: const Text('Rafraîchir'),
        ),
        TextButton(
          child: const Text('Terminé'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
