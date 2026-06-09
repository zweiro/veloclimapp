// --- UI (Page) ---

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensor_logging/widgets/bluetooth_indicator.dart';
import 'package:sensor_logging/widgets/bluetooth_scan_popup.dart';
import 'package:sensor_logging/widgets/connection_button.dart';
import 'package:sensor_logging/widgets/empty_session_card.dart';
import 'package:sensor_logging/utils.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sensor_logging/widgets/live_status_card.dart';
import 'package:sensor_logging/widgets/log_table.dart';
import 'package:sensor_logging/widgets/save_session_dialog.dart';
import 'package:sensor_logging/pages/server_settings_page.dart';
import 'package:sensor_logging/pages/session_table_page.dart';

/// The main page widget for connecting to a Bluetooth sensor, starting/stopping logging,
/// and displaying live sensor data and logs.
class BluetoothConnectorPage extends StatefulWidget {
  const BluetoothConnectorPage({super.key});

  @override
  State<BluetoothConnectorPage> createState() => _BluetoothConnectorPageState();
}

class _BluetoothConnectorPageState extends State<BluetoothConnectorPage> {
  // Controller for the Bluetooth device name input field
  final TextEditingController _deviceNameController = TextEditingController(
    text: "",
  );
  bool disableDeleteButton = false;

  // UI state variables to display real-time logging information
  String _connectionStatus = 'Service arrêté';
  String _characteristicData = 'Aucune donnée';
  String _locationData = 'Aucune donnée GPS';
  List<String> _csvLines = [
    'Aucune donnée',
  ]; // Stores the latest CSV lines for display
  bool _isServiceRunning = false; // Tracks if the background service is active
  BluetoothAdapterState _bluetoothAdapterState =
      BluetoothAdapterState.unknown; // Current Bluetooth adapter state

  // Subscription to listen for changes in the Bluetooth adapter state
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  String? _currentCsvFilePath; // Track the current session's CSV file path
  DateTime? _sessionStartTime; // Track when the current session started
  bool _isConnecting = false; 

  @override
  void initState() {
    super.initState();
    _checkServiceStatus(); // Check the initial status of the background service
    _listenToService(); // Start listening for updates from the background service
    _readLatestCsvLines(); // Read and display initial CSV log entries
    _listenToBluetoothAdapterState(); // Start listening to Bluetooth adapter state
  }

  /// Listens to the global Bluetooth adapter state and updates the UI accordingly.
  /// Also stops the logging service if Bluetooth is turned off.
  void _listenToBluetoothAdapterState() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _bluetoothAdapterState =
            state; // Update the UI with the new Bluetooth state
      });
      // If Bluetooth is off and the service is running, stop the logging gracefully.
      if (state != BluetoothAdapterState.on && _isServiceRunning) {
        Utils.showSnackBar(
          'Le Bluetooth est désactivé. Arrêt de journalisation.',
          context,
        );
        _stopLogging(); // Automatically stop if Bluetooth turns off
      }
    });
  }

  /// Checks if the background service is currently running and updates the UI state.
  void _checkServiceStatus() async {
    bool isRunning = await FlutterBackgroundService().isRunning();
    setState(() {
      _isServiceRunning = isRunning;
      _connectionStatus = isRunning
          ? 'Service en exécution...'
          : 'Service arrêté';
      disableDeleteButton = isRunning || _isConnecting ? true : false;
    });
  }

  /// Listens for messages (`updateUI`, `stopService`) from the background service
  /// and updates the UI accordingly.
  void _listenToService() {
    FlutterBackgroundService().on('updateUI').listen((data) {
      if (!mounted || data == null) {
        return;
      }
      setState(() {
        _connectionStatus = data['status'] ?? _connectionStatus;
        _characteristicData = data['btData'] ?? _characteristicData;
        _locationData = data['locationData'] ?? _locationData;
        if (data.containsKey('isScanning')) {
          _isConnecting = data['isScanning'] == true;
        }
        // Only set _isServiceRunning to true if status is not "Service arrêté"
        _isServiceRunning = data['status'] == 'Service arrêté'
            ? false
            : _isServiceRunning;
        disableDeleteButton = data['status'] == 'Service arrêté' ? false : true;
      });
      // Show a toast if requested
      if (data['showToast'] != null &&
          data['showToast'].toString().isNotEmpty) {
        Utils.showSnackBar(data['showToast'].toString(), context);
      }
      _readLatestCsvLines();
    });

    FlutterBackgroundService().on('stopService').listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isServiceRunning = false;
        _connectionStatus = 'Service arrêté';
        _characteristicData = 'Aucune donnée';
        _locationData = 'Aucune donnée GPS';
        disableDeleteButton = false;
        _isConnecting = false; // Always disable loader on stop
      });
    });
  }

  @override
  void dispose() {
    _deviceNameController.dispose(); // Dispose of the text editing controller
    _adapterStateSubscription
        ?.cancel(); // Cancel the Bluetooth state subscription
    super.dispose();
  }

  /// Initiates the logging process.
  /// This includes requesting permissions, checking Bluetooth state, and starting the background service.
  Future<void> _startLogging() async {
    if (_deviceNameController.text.isEmpty) {
      Utils.showSnackBar(
        'Veuillez entrer le nom du capteur Bluetooth.',
        context,
      );
      return;
    }
    setState(() {
      _isConnecting = true;
    });

    await Utils.requestPermissions();

    // Perform pre-checks before attempting to start the service:
    if (Platform.isAndroid && !await Permission.notification.isGranted) {
      Utils.showSnackBar(
        'Permission de notification requise pour fonctionner en arrière-plan.',
        context,
      );
      return;
    }
    // Check for either LocationAlways or LocationWhenInUse for GPS logging.
    if (!(await Permission.locationAlways.isGranted ||
        await Permission.locationWhenInUse.isGranted)) {
      Utils.showSnackBar(
        'Permission de localisation requise pour l\'enregistrement GPS.',
        context,
      );
      return;
    }

    // Get the *current* Bluetooth adapter state directly before starting.
    BluetoothAdapterState currentBluetoothState =
        await FlutterBluePlus.adapterState.first;

    if (currentBluetoothState != BluetoothAdapterState.on) {
      Utils.showSnackBar(
        'Bluetooth désactivé. Tentative d\'activation...',
        context,
      );
      await FlutterBluePlus.turnOn(); // Attempt to turn on Bluetooth programmatically

      // Wait for the Bluetooth adapter to actually become ON, with a timeout.
      try {
        currentBluetoothState = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 10)); // Max 10 seconds to turn on
      } on TimeoutException {
        Utils.showSnackBar(
          'Le Bluetooth ne s\'est pas activé à temps. Veuillez l\'activer manuellement.',
          context,
        );
        return;
      } catch (e) {
        Utils.showSnackBar(
          'Erreur d\'activation Bluetooth: $e. Veuillez l\'activer manuellement.',
          context,
        );
        return;
      }

      if (currentBluetoothState != BluetoothAdapterState.on) {
        // This case should ideally not be hit if the timeout and where clause work,
        // but as a final safeguard.
        Utils.showSnackBar(
          'Le Bluetooth est toujours désactivé. Veuillez l\'activer manuellement.',
          context,
        );
        return;
      }
    }
    if (!await Geolocator.isLocationServiceEnabled()) {//check if GPS is not enabled
      setState(() {
        _isConnecting = false;
      });
      // Display a dialog to inform the user that GPS is disabled
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
                await Geolocator.openLocationSettings(); // Open location settings
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

    final String deviceName = _deviceNameController.text.trim();
    if (deviceName.isEmpty) {
      Utils.showSnackBar('VC_SENS_XXXXXX', context);
      return;
    }

    // Generate a new CSV file path for this session
    final csvFilePath = await Utils.generateCsvFilePath(deviceName);
    setState(() {
      _currentCsvFilePath = csvFilePath;
      _sessionStartTime = DateTime.now();
    });

    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (isRunning) {
      // If service is already running, stop it gracefully before restarting to ensure a clean start.
      Utils.showSnackBar(
        'Arrêt du service existant avant redémarrage...',
        context,
      );
      service.invoke('stopService');
      // Wait until the service is really stopped
      int tries = 0;
      while (await service.isRunning() && tries < 20) {
        await Future.delayed(const Duration(milliseconds: 200));
        tries++;
      }
    }

    // Start the background service and send the 'startLogging' command.
    try {
      await service.startService();
      await Future.delayed(const Duration(milliseconds: 1000));
      service.invoke('setAsForeground');
      service.invoke('startLogging', {
        'deviceName': deviceName,
        'csvFilePath': csvFilePath,
      });

      setState(() {
        _isServiceRunning = true;
        _connectionStatus = 'Démarrage du service...';
        disableDeleteButton = true;
        _isConnecting = false;
      });
      Utils.showSnackBar('Enregistrement démarré.', context);
    } catch (e) {
      Utils.showSnackBar('Échec du démarrage: ${e.toString()}', context);
      setState(() {
        _isServiceRunning = false;
        _connectionStatus = 'Échec du démarrage';
        disableDeleteButton = false;
        _isConnecting = false; 
      });
    }
  }

  /// Stops the logging process by invoking the 'stopService' command on the background service.
  Future<void> _stopLogging() async {
    FlutterBackgroundService().invoke('stopService');

    // Capture current values before resetting state
    final csvFilePath = _currentCsvFilePath;
    final startTime = _sessionStartTime;

    setState(() {
      _isServiceRunning = false;
      _connectionStatus = 'Arrêté';
      disableDeleteButton = false;
      _isConnecting = false;
    });

    // Show save session dialog if we have a valid file path and start time
    if (csvFilePath != null && startTime != null && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => SaveSessionDialog(
          csvFilePath: csvFilePath,
          startedAt: startTime,
          onSaved: () {
            Utils.showSnackBar('Session enregistrée.', context);
          },
        ),
      );
    }

    // Clear session tracking
    setState(() {
      _currentCsvFilePath = null;
      _sessionStartTime = null;
    });
  }

  /// Reads the latest log entries from the CSV file and updates the UI display.
  Future<void> _readLatestCsvLines() async {
    if (_currentCsvFilePath == null) return;
    final file = File(_currentCsvFilePath!);
    if (!await file.exists()) {
      setState(() => _csvLines = ['No log data yet.']);
      return;
    }
    try {
      final lines = await file.readAsLines();
      const int numLinesToShow = 10; // Display the last 10 log entries
      if (lines.length > 1) {
        // Check if there's header + at least one data row
        // Get the last 'numLinesToShow' lines, ensuring we don't include the header in the count
        // unless it's explicitly needed (e.g., if there are fewer than 10 data lines).
        setState(
          () => _csvLines = lines.sublist(
            (lines.length - numLinesToShow).clamp(1, lines.length),
          ),
        );
      } else {
        setState(
          () => _csvLines = ['No data entries.'],
        ); // Only header exists or file is empty
      }
    } catch (e) {
      setState(() => _csvLines = ['Error reading log file: $e']);
    }
  }

  /// Extracts the temperature value from the characteristic data.
  String? get temperature {
    final match = RegExp(
      r'Temp[:=]?\s*([-\d.]+)',
    ).firstMatch(_characteristicData);
    return match != null ? '${match.group(1)}°C' : null;
  }

  /// Extracts the humidity value from the characteristic data.
  String? get humidity {
    final match = RegExp(
      r'Hum[:=]?\s*([-\d.]+)',
    ).firstMatch(_characteristicData);
    return match != null ? '${match.group(1)}%' : null;
  }

  /// Extracts the latitude and formats it to two decimal places.
  String? get latitude {
    final match = RegExp(r'Lat[:=]?\s*([-\d.]+)').firstMatch(_locationData);
    if (match != null) {
      final value = double.tryParse(match.group(1)!);
      if (value != null) {
        return value.toStringAsFixed(2);
      }
    }
    return null;
  }

  /// Extracts the longitude and formats it to two decimal places.
  String? get longitude {
    final match = RegExp(r'(Lon)[:=]?\s*([-\d.]+)').firstMatch(_locationData);
    if (match != null) {
      final value = double.tryParse(match.group(2)!);
      if (value != null) {
        return value.toStringAsFixed(2);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VéloClimat'),
        elevation: 4,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SessionTablePage(),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
            ),
            icon: const Icon(Icons.list),
            label: const Text('Sessions'),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ServerSettingsPage(),
                ),
              );
            },
            icon: Icon(Icons.settings, color: Colors.grey.shade700),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: TextField(
                    controller: _deviceNameController,
                    decoration: InputDecoration(
                      labelText: 'Nom du capteur Bluetooth',
                      hintText: 'Nom exact du capteur (ex: VC_SENS_X)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      prefixIcon: const Icon(Icons.bluetooth),
                    ),
                    enabled: !_isServiceRunning,
                  ),
                ),
                const SizedBox(width: 8),
                BluetoothScanPopup(
                  isRunning: _isServiceRunning,
                  onDeviceSelected: (device) {
                    setState(() {
                      _deviceNameController.text = device.name.isNotEmpty
                          ? device.name
                          : device.id.toString();
                    });
                    if (_isServiceRunning) {
                      // If a connection to a sensor is already in progress, stop it
                      _stopLogging();
                    }
                    _startLogging(); // Start a connection to the selected device.
                  },
                ),
              ],
            ),

            // Bluetooth Device Name Input Field
            const SizedBox(height: 20),

            // Bluetooth Status Indicator
            BluetoothIndicator(bluetoothAdapterState: _bluetoothAdapterState),

            const SizedBox(height: 20),

            // Start/Stop Logging Button
            ConnectionButton(
              isConnecting: _isConnecting,
              isServiceRunning: _isServiceRunning,
              startLogging: _startLogging,
              stopLogging: _stopLogging,
              onServiceStatusChanged: _checkServiceStatus,
            ),
            const SizedBox(height: 25),

            // Conditional layout based on service state
            if (_isServiceRunning || _isConnecting) ...[
              // Live Status Section (shown when recording)
              LiveStatusCard(
                connectionStatus: _connectionStatus,
                temperature: temperature,
                humidity: humidity,
                latitude: latitude,
                longitude: longitude,
              ),

              const SizedBox(height: 25),

              // Latest Log Entries Section
              Text(
                'Dernières mesures :',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: _csvLines.isEmpty || _csvLines.first.startsWith('No')
                    ? Center(
                        child: Text(
                          _csvLines.first.startsWith('No')
                              ? 'Aucune donnée'
                              : _csvLines.first,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      )
                    : LogTable(csvLines: _csvLines),
              ),
            ] else ...[
              // Empty session card (shown when not recording)
              const EmptySessionCard(),
            ],
            const SizedBox(height: 50), // Add some spacing at the bottom
          ],
        ),
      ),
    );
  }
}
