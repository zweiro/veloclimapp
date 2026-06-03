import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui'; // Required for DartPluginRegistrant.ensureInitialized()
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // For Bluetooth operations
import 'package:geolocator/geolocator.dart'; // For GPS location
import 'package:csv/csv.dart'; // For CSV file generation
import 'package:sensor_logging/bluetooth_connector_page.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sensor_logging/utils.dart';

/// Main entry point and background service logic for the VéloClimat app.
///
/// This file contains:
/// - The main() function and app widget setup.
/// - Initialization and configuration of the background service for sensor logging.
/// - The background service entry point (`onStart`) which manages Bluetooth and GPS data collection,
///   device connection, reconnection, and CSV logging.
/// - Utility functions for CSV file management.
/// - Lifecycle watcher to stop the service when the app is detached.
///
/// Features:
/// - Connects to a Bluetooth sensor, reads environmental data, and logs it with GPS info.
/// - Runs as a foreground service on Android for reliability.
/// - Handles permissions, notifications, and reconnection logic.
/// - Updates the UI in real time via service events.
///
/// Usage:
/// - The app starts with `main()`, which initializes the background service and launches the UI.
/// - The background service is started/stopped from the UI (see BluetoothConnectorPage).
/// - All Bluetooth and GPS logic is handled in the background isolate for robust logging.

// --- Background Service Configuration ---

// IMPORTANT: Update these UUIDs if your sensor uses different ones
// These are example UUIDs for a generic Environmental Sensing Service and a custom characteristic.
final Guid SERVICE_UUID = Guid("181A");
final Guid CHARACTERISTIC_UUID = Guid("FF01");

/// Initializes the background service. This sets up the Android and iOS configurations.
/// It also requests necessary permissions before the service attempts to start.
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const notificationChannelId = "my_app_service";
  const notificationId = 888;

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'Sensor data logger', // title
    description:
        'This channel is used for the sensor data logging', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
  // Request necessary permissions (notifications and location) before configuring the service.
  // This ensures the user is prompted early.
  await Utils.requestPermissions();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // The entry point function for the background service
      autoStart: false, // We will start it manually from the UI
      isForegroundMode:
          true, // Runs as a foreground service to prevent system termination
      notificationChannelId:
          notificationChannelId, // Unique ID for the notification channel
      initialNotificationTitle:
          'Sensor data logger', // Initial title displayed in the ongoing notification
      initialNotificationContent:
          'Initializing...', // Initial content of the notification
      foregroundServiceNotificationId:
          notificationId, // Unique ID for the foreground service notification
      // IMPORTANT: Declare foreground service types for Android 10 (API 29) and above.
      // These should match the 'android:foregroundServiceType' in your AndroidManifest.xml.
    ),
    iosConfiguration: IosConfiguration(),
  );
}

/// The entry point for the background service. This code runs in an isolated Dart Isolate.
///
/// Handles:
/// - Bluetooth device scanning, connection, and reconnection
/// - Periodic reading of sensor data and GPS location
/// - Logging to CSV file
/// - Communicating status and data back to the UI
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Ensure Flutter plugins (like FlutterBluePlus and Geolocator) are initialized in this isolate.
  DartPluginRegistrant.ensureInitialized();
  debugPrint('Background service: onStart initiated.');

  // --- Background Task State Variables ---
  String? deviceName;
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? targetCharacteristic;
  Timer? logTimer; // Timer for periodic data collection
  StreamSubscription<BluetoothConnectionState>?
  connectionStateSubscription; // Listens for BT device disconnection
  StreamSubscription<BluetoothAdapterState>?
  adapterStateSubscription; // Listens for global BT adapter state changes

  String? csvFilePath; // Track the current session's CSV file

  bool isReconnecting = false;
  int reconnectionAttempts = 0;

  // GPS stream variables for continuous position updates
  Position? lastKnownPosition;
  StreamSubscription<Position>? gpsSubscription;

  // --- Foreground/Background Mode Management for Android ---
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService(); // Puts the service into foreground mode
      debugPrint('Background service: Set as foreground.');
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService(); // Puts the service into background mode
      debugPrint('Background service: Set as background.');
    });
  }

  // --- Stop Service Command Listener ---
  // This listener handles requests from the UI to stop the background service.
  service.on('stopService').listen((event) async {
    debugPrint(
      'Background service: stopService command received. Cleaning up...',
    );
    // Clean up all resources to prevent leaks and ensure a graceful shutdown.
    logTimer
        ?.cancel(); // Stop the periodic logging timer - Removed 'await' as cancel() returns void
    logTimer = null; // Clear the timer reference
    await connectionStateSubscription
        ?.cancel(); // Cancel device connection state listener
    await adapterStateSubscription
        ?.cancel(); // Cancel Bluetooth adapter state listener
    await gpsSubscription?.cancel(); // Cancel GPS position stream
    gpsSubscription = null;

    // Attempt to disconnect from the Bluetooth device if it's connected.
    try {
      if (connectedDevice != null &&
          (await connectedDevice!.connectionState.first) ==
              BluetoothConnectionState.connected) {
        debugPrint(
          'Background service: Disconnecting from Bluetooth device...',
        );
        await connectedDevice!.disconnect();
        debugPrint(
          'Background service: Bluetooth device disconnected cleanly.',
        );
      }
    } catch (e) {
      debugPrint('Background service: Error disconnecting device on stop: $e');
    }

    // Stop any active Bluetooth scanning.
    try {
      // Access the current value of the isScanning stream using .first
      if (await FlutterBluePlus.isScanning.first) {
        debugPrint('Background service: Stopping Bluetooth scan...');
        await FlutterBluePlus.stopScan();

        debugPrint('Background service: Bluetooth scan stopped cleanly.');
      }
    } catch (e) {
      debugPrint('Background service: Error stopping scan on stop: $e');
    }

    service.stopSelf(); // Stops the background service itself
    debugPrint('Background service: Service stopped itself.');
    // Update UI to reflect that the service has stopped and clear data displays.
    service.invoke('updateUI', {
      'status': 'Service arrêté',
      'btData': 'Aucune donnée',
      'locationData': 'Aucune donnée GPS',
    });
  });

  // --- Listen for Bluetooth Adapter State Changes ---
  // This is crucial for handling cases where Bluetooth is turned off by the user.
  adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
    debugPrint(
      'Background service: Bluetooth adapter state changed to: $state',
    );
    if (state != BluetoothAdapterState.on) {
      // If Bluetooth is off or unavailable, notify the UI and stop the logging service.
      service.invoke('updateUI', {
        'status': 'Bluetooth désactivé. Journalisation arrêtée.',
        'btData': 'Bluetooth désactivé',
        'locationData': 'Aucune donnée GPS',
      });
      debugPrint(
        'Background service: Bluetooth adapter turned off. Stopping service.',
      );
      service.invoke('stopService'); // Request to stop the service
    } else {
      // Bluetooth is ON, update status if logging is active.
      if (logTimer?.isActive ?? false) {
        service.invoke('updateUI', {
          'status': 'Bluetooth activé. Journalisation en cours...',
        });
      }
    }
  });

  // --- Listen for 'startLogging' command from the UI ---
  service.on('startLogging').listen((data) async {
    debugPrint('Background service: startLogging command received.');
    if (data == null) {
      debugPrint('Background service: startLogging data is null, returning.');
      return;
    }
    deviceName = data['deviceName'];
    csvFilePath = data['csvFilePath'];

    // Ensure CSV header for this session's file
    await _ensureCsvHeader(csvFilePath);

    // Initialize GPS stream for continuous position updates
    await gpsSubscription?.cancel();
    gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, // "best" is not available on Android: https://pub.dev/packages/geolocator#location-accuracy
        distanceFilter: 0, // Capture all updates regardless of distance
      ),
    ).listen((Position position) {
      lastKnownPosition = position;
      debugPrint('Background service: GPS position updated: ${position.latitude}, ${position.longitude}');
    }, onError: (error) {
      debugPrint('Background service: GPS stream error: $error');
    });
    debugPrint('Background service: GPS stream initialized.');

    // Prevent starting logging if it's already active.
    if (logTimer?.isActive ?? false) {
      service.invoke('updateUI', {
        'status': 'Journalisation déjà en cours pour "$deviceName".',
      });
      debugPrint('Background service: Logging already active.');
      return;
    }

    service.invoke('updateUI', {
      'status': 'Recherche de "$deviceName"...',
      'btData': 'Aucune donnée',
      'locationData': 'Aucune donnée GPS',
      'isScanning': true, // Indicate that scanning is in progress
    });
    debugPrint('Background service: UI updated to scanning status.');

    // Explicitly check if Bluetooth is enabled before starting any scan/connection.
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      service.invoke('updateUI', {
        'status':
            'Bluetooth désactivé. Impossible de démarrer la journalisation.',
      });
      service.invoke('stopService'); // Stop service as Bluetooth is required
      debugPrint('Background service: Bluetooth is OFF, stopping service.');
      return;
    }

    // --- Connect to Bluetooth Device ---
    try {
      debugPrint(
        'Background service: Attempting to connect to Bluetooth device.',
      );

      // Clean up previous state
      if (connectedDevice != null &&
          (await connectedDevice!.connectionState.first) ==
              BluetoothConnectionState.connected) {
        debugPrint(
          'Background service: Previous device was connected, disconnecting...',
        );
        await connectedDevice!.disconnect();
      }
      connectionStateSubscription?.cancel();
      connectedDevice = null;
      targetCharacteristic = null;
      FlutterBluePlus.scanResults.drain();

      // Start scan with timeout
      debugPrint(
        'Background service: Starting new Bluetooth scan for 15 seconds...',
      );
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      ScanResult? foundResult;
      late StreamSubscription scanSub;
      try {
        scanSub = FlutterBluePlus.scanResults.listen((results) {
          for (final r in results) {
            if (r.device.platformName.toLowerCase() ==
                deviceName!.toLowerCase()) {
              foundResult = r;
            }
          }
        });

        final start = DateTime.now();
        connectedDevice = foundResult?.device;

        // --- Connect to the discov
        while (foundResult == null &&
            DateTime.now().difference(start) < const Duration(seconds: 15)) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      } finally {
        await FlutterBluePlus.stopScan();
        await scanSub.cancel();
      }

      if (foundResult == null) {
        service.invoke('updateUI', {
          'status': 'BLT: non, GPS: non',
          'btData': 'Aucune donnée',
          'locationData': 'Aucune donnée GPS',
          'showToast': 'Erreur : Appareil "$deviceName" introuvable.',
          'isScanning': false,
        });
        service.invoke('stopService');
        return;
      }

      connectedDevice = foundResult?.device;

      // --- Connect to the discovered device ---
      debugPrint(
        'Background service: Connecting to ${connectedDevice!.platformName}...',
      );
      await connectedDevice!.connect(autoConnect: false);
      service.invoke('updateUI', {
        'status': 'Connexion à $deviceName. Initialisation...',
        'isScanning': false, // Scanning is no longer active
      });
      debugPrint('Background service: Connected. Discovering services...');

      // Listen for disconnection events specific to this connected device.
      // If the device disconnects unexpectedly, we'll stop the service cleanly.
      connectionStateSubscription = connectedDevice!.connectionState.listen((
        state,
      ) async {
        debugPrint(
          'Background service: Device connection state changed to: $state',
        );
        if (state == BluetoothConnectionState.disconnected) {
          isReconnecting = true;
          reconnectionAttempts++;

          service.invoke('updateUI', {
            'status': 'Connexion perdue',
            'btData': 'Déconnecté',
            'locationData': 'Aucune donnée GPS',
            'showToast':
                'Erreur : $deviceName déconnecté. Tentative de reconnexion...',
            'isScanning': true,
          });

          debugPrint(
            'Background service: Device disconnected. Trying to reconnect... (attempt $reconnectionAttempts)',
          );

          bool reconnected = false;
          String reconnectMsg = '';
          try {
            await connectedDevice!.connect(
              autoConnect: false,
              timeout: const Duration(seconds: 10),
            );
            // Redécouvre les services et la caractéristique
            List<BluetoothService> services = await connectedDevice!
                .discoverServices();
            for (var s in services) {
              if (s.uuid == SERVICE_UUID) {
                for (var c in s.characteristics) {
                  if (c.uuid == CHARACTERISTIC_UUID) {
                    targetCharacteristic = c;
                    break;
                  }
                }
              }
            }
            if (targetCharacteristic != null) {
              reconnected = true;
              reconnectMsg = 'Reconnexion réussie à $deviceName.';
              reconnectionAttempts = 0;
              service.invoke('updateUI', {
                'status': 'Reconnexion réussie à $deviceName.',
                'btData': 'Reconnecté',
                'showToast': reconnectMsg,
                'isScanning': false,
              });
            } else {
              reconnectMsg =
                  'Reconnexion échouée (caractéristique non trouvée).';
              service.invoke('updateUI', {
                'status': reconnectMsg,
                'btData': 'Déconnecté',
                'isScanning': false,
              });
            }
          } catch (e) {
            reconnectMsg = 'Reconnexion échouée à $deviceName.';
            service.invoke('updateUI', {
              'status': reconnectMsg,
              'btData': 'Déconnecté',
              'isScanning': false,
            });
          }
          isReconnecting = false;
          debugPrint('Background service: $reconnectMsg');

          if (!reconnected) {
            if (reconnectionAttempts >= 3) {
              service.invoke('updateUI', {
                'status': 'Échec de reconnexion après 3 tentatives.',
                'btData': 'Déconnecté',
                'locationData': 'Aucune donnée GPS',
                'showToast': 'Impossible de se reconnecter après 3 essais.',
                'isScanning': false,
              });
              await connectionStateSubscription?.cancel();
              connectedDevice = null;
              service.invoke('stopService');
              return;
            }
          }
        }
      });

      // Discover services and find the target characteristic.
      List<BluetoothService> services = await connectedDevice!
          .discoverServices();
      debugPrint('Background service: Discovered ${services.length} services.');
      for (var s in services) {
        debugPrint('Background service: Service UUID: ${s.uuid}');
        if (s.uuid == SERVICE_UUID) {
          debugPrint(
            'Background service: Found target SERVICE_UUID: ${s.uuid}',
          );
          for (var c in s.characteristics) {
            debugPrint('Background service: Characteristic UUID: ${c.uuid}');
            if (c.uuid == CHARACTERISTIC_UUID) {
              targetCharacteristic = c;
              debugPrint(
                'Background service: Found target CHARACTERISTIC_UUID: ${c.uuid}',
              );
              break; // Characteristic found
            }
          }
        }
      }

      // If the target characteristic is not found, disconnect and stop the service.
      if (targetCharacteristic == null) {
        service.invoke('updateUI', {
          'status': 'Caractéristique non trouvée pour $deviceName.',
        });
        debugPrint(
          'Background service: Target characteristic not found. Disconnecting...',
        );
        await connectedDevice!.disconnect(); // Disconnect cleanly
        service.invoke('stopService');
        return;
      }

      // --- Start Periodic Data Collection & Logging ---
      // This timer will trigger the data collection function at a fixed interval.
      debugPrint('Background service: Starting periodic log timer.');
      logTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) async {
        if (isReconnecting) {
          // Skip data collection during reconnection
          return;
        }
        if (connectedDevice != null && targetCharacteristic != null) {
          await _collectAndLogData(
            service,
            connectedDevice!,
            targetCharacteristic!,
            csvFilePath,
            lastKnownPosition,
          );
        } else {
          service.invoke('updateUI', {
            'status':
                'Error: Bluetooth device/characteristic unavailable. Stopping.',
          });
          debugPrint(
            'Background service: Device or characteristic became null during logging. Stopping.',
          );
          service.invoke('stopService');
        }
      });

      service.invoke('updateUI', {
        'status': 'Connecté. Journalisation toutes les secondes.',
      });
      debugPrint('Background service: Logging successfully initiated.');
    } catch (e) {
      // Catch any errors during Bluetooth scanning, connection, or service discovery.
      service.invoke('updateUI', {
        'status': 'Erreur Bluetooth : ${e.toString()}',
        'btData': 'Aucune donnée',
        'locationData': 'Aucune donnée GPS',
        'showToast': 'Erreur Bluetooth : ${e.toString()}',
      });
      debugPrint(
        'Background service: Critical Bluetooth error during setup: $e',
      );
      service.invoke('stopService');
    }
  });
}

/// Collects Bluetooth and GPS data, logs it to a CSV, and updates the UI.
/// This function runs periodically in the background service.
Future<void> _collectAndLogData(
  ServiceInstance service,
  BluetoothDevice device,
  BluetoothCharacteristic characteristic,
  String? csvFilePath,
  Position? cachedPosition,
) async {
  debugPrint('Background service: _collectAndLogData called.');
  final now = DateTime.now();
  String timestamp = now
      .toIso8601String(); // ISO 8601 format for consistent timestamps

  double? temp, hum, lat, lon, accuracy;
  String btDataStr = 'No data';
  String locationDataStr = 'No location data';

  // --- Get Bluetooth data ---
  try {
    debugPrint('Background service: Checking Bluetooth connection state...');
    // Check connection state *immediately* before attempting to read the characteristic.
    // This helps avoid errors if the device disconnects right before a read.
    if (await device.connectionState.first ==
        BluetoothConnectionState.connected) {
      debugPrint(
        'Background service: Device connected. Attempting to read characteristic...',
      );
      List<int> value = await characteristic
          .read(); // Read the characteristic's value
      debugPrint('Background service: Raw BT bytes received: $value (length: ${value.length})');
      if (value.length >= 8) {
        // Expecting at least 8 bytes for two Float32 values
        final byteData = ByteData.view(Uint8List.fromList(value).buffer);
        // Assuming little endian as per original code. Adjust if your sensor uses big endian.
        temp = byteData.getFloat32(
          0,
          Endian.little,
        ); // First 4 bytes for temperature
        hum = byteData.getFloat32(
          4,
          Endian.little,
        ); // Next 4 bytes for humidity
        debugPrint('Background service: Parsed temp=$temp, hum=$hum');

        // Check for invalid values (0xFFFFFFFF = sensor error/not ready)
        final tempBytes = value.sublist(0, 4);
        final isTempInvalid = tempBytes.every((b) => b == 255); // 0xFFFFFFFF

        if (isTempInvalid) {
          debugPrint('Background service: Temperature sensor returning 0xFFFFFFFF (not ready or error)');
          btDataStr = 'Temp: -- °C (capteur non prêt), Hum: ${hum.isNaN ? "--" : hum.toStringAsFixed(2)} %';
        } else if (temp.isNaN || hum.isNaN) {
          debugPrint('Background service: WARNING - NaN detected! Raw bytes: $tempBytes (temp), ${value.sublist(4, 8)} (hum)');
          btDataStr = 'Erreur: données capteur invalides';
        } else {
          btDataStr =
              'Temp: ${temp.toStringAsFixed(2)} °C, Hum: ${hum.toStringAsFixed(2)} %';
        }
        debugPrint('Background service: Bluetooth data read: $btDataStr');
      } else {
        btDataStr =
            'Error: Not enough bytes (${value.length}) from BT device. Expected 8+';
        debugPrint(
          'Background service: $btDataStr',
        ); // Log the error internally
      }
    } else {
      btDataStr = 'Device disconnected.';
      debugPrint('Background service: $btDataStr');
      // IMPORTANT: Do NOT stop the service here. The `_connectionStateSubscription` in `onStart`
      // will handle the disconnection and stop the service gracefully.
    }
  } catch (e) {
    btDataStr = 'Error reading BT data: $e';
    debugPrint('Background service: $btDataStr'); // Log the error internally
    // IMPORTANT: Do NOT stop the service here. Allow the service to continue attempting readings.
  }

  // --- Get GPS data from cached position ---
  if (cachedPosition != null) {
    lat = cachedPosition.latitude;
    lon = cachedPosition.longitude;
    accuracy = cachedPosition.accuracy;
    locationDataStr =
        'Lat: ${lat.toStringAsFixed(6)}, Lon: ${lon.toStringAsFixed(6)}';
    debugPrint('Background service: GPS data (cached): $locationDataStr');
  } else {
    locationDataStr = 'GPS: en attente de position...';
    debugPrint('Background service: No cached GPS position yet.');
  }

  // --- Append data to CSV ---
  debugPrint('Background service: Appending data to CSV...');
  await _appendToCsv([
    timestamp,
    temp?.toStringAsFixed(2) ?? 'N/A', // Use 'N/A' if data is null
    hum?.toStringAsFixed(2) ?? 'N/A',
    lat?.toString() ?? 'N/A',
    lon?.toString() ?? 'N/A',
    accuracy?.toStringAsFixed(2) ?? 'N/A',
  ], csvFilePath);
  debugPrint('Background service: Data appended to CSV.');

  // --- Send data to UI ---
  // Update the UI with the latest status and collected data.
  service.invoke('updateUI', {
    // Provide a more concise status message for the UI, indicating if BT/GPS had errors.
    'status':
        'Bluetooth : ${btDataStr.contains("Error") || btDataStr.contains("Erreur") ? "Erreur" : "OK"}, GPS : ${locationDataStr.contains("Error") || locationDataStr.contains("Erreur") ? "Erreur" : "OK"}',
    'btData': btDataStr
        .replaceAll('Error', 'Erreur')
        .replaceAll('Device disconnected.', 'Appareil déconnecté.')
        .replaceAll('No data', 'Aucune donnée')
        .replaceAll('Not enough bytes', 'Données Bluetooth incomplètes')
        .replaceAll('Error reading BT data', 'Erreur de lecture Bluetooth'),
    'locationData': locationDataStr
        .replaceAll('Error', 'Erreur')
        .replaceAll('No location data', 'Aucune donnée GPS')
        .replaceAll(
          'GPS service/permission disabled or denied.',
          'Service GPS ou autorisation désactivés/refusés.',
        ),
  });
  debugPrint('Background service: UI updated with latest data.');
}

// --- CSV File Management ---

/// Ensures that the CSV file exists and contains the header row.
/// If the file doesn't exist or is empty, it writes the header.
Future<void> _ensureCsvHeader(String? csvFilePath) async {
  if (csvFilePath == null) return;
  final file = File(csvFilePath);
  if (!await file.exists() || (await file.readAsString()).trim().isEmpty) {
    final header = [
      'Timestamp',
      'Temperature',
      'Humidity',
      'Latitude',
      'Longitude',
      'Accuracy',
    ];
    final csvString = const ListToCsvConverter().convert([header]);
    await file.writeAsString('$csvString\n', mode: FileMode.write);
    debugPrint('CSV header ensured.');
  } else {
    debugPrint('CSV header already present.');
  }
}

/// Appends a new row of data to the CSV log file.
Future<void> _appendToCsv(List<dynamic> row, String? csvFilePath) async {
  if (csvFilePath == null) return;
  final file = File(csvFilePath);
  final csvString = const ListToCsvConverter().convert([row]);
  await file.writeAsString('$csvString\n', mode: FileMode.append);
}

// --- Main Application Entry Point ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter widgets are initialized
  debugPrint('Main: WidgetsFlutterBinding initialized.');

  await initializeService(); // Initialize the background service configuration
  debugPrint('Main: Background service initialized.');

  // Enable verbose logging for FlutterBluePlus to aid in debugging Bluetooth issues.
  FlutterBluePlus.setLogLevel(LogLevel.verbose);
  debugPrint('Main: FlutterBluePlus log level set to verbose.');

  runApp(const MyApp());
  debugPrint('Main: MyApp started.');
}

// --- Main Flutter App Widget ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VéloClimat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LifecycleWatcher(child: const BluetoothConnectorPage()),
    );
  }
}

/// Watches the app lifecycle and stops the background service when the app is detached.
///
/// This ensures that the background service does not continue running after the app is closed.
class LifecycleWatcher extends StatefulWidget {
  final Widget child;
  const LifecycleWatcher({required this.child, super.key});

  @override
  State<LifecycleWatcher> createState() => _LifecycleWatcherState();
}

class _LifecycleWatcherState extends State<LifecycleWatcher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Stop the background service when the app is exited or detached.
      debugPrint(
        'LifecycleWatcher: App detached. Stopping background service.',
      );
      FlutterBackgroundService().invoke('stopService');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
