import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Utility class providing static helper methods for permissions, file management,
/// and user notifications in the sensor logging app.

class Utils {
  static String? csvPath;

  /// Requests essential permissions for the app: Notifications (for Android 13+),
  /// Bluetooth (for Android 12+), Location (Always/WhileInUse), and Storage.
  /// This method checks and requests all permissions required for Bluetooth scanning,
  /// background operation, and file storage. It handles Android-specific permission
  /// requirements for newer versions.
  static Future<void> requestPermissions() async {
    debugPrint('Requesting permissions...');

    // Request notification permission for Android 13+ to ensure foreground service notifications work.
    if (Platform.isAndroid) {
      var status = await Permission.notification.status;
      if (status.isDenied) {
        debugPrint('Requesting notification permission...');
        await Permission.notification.request();
      }
    }

    // Request Bluetooth permissions for Android 12 (API 31) and above
    if (Platform.isAndroid && await Permission.bluetooth.status.isDenied) {
      debugPrint('Requesting general Bluetooth permission...');
      await Permission.bluetooth.request();
    }
    if (Platform.isAndroid && await Permission.bluetoothScan.status.isDenied) {
      debugPrint('Requesting Bluetooth Scan permission...');
      await Permission.bluetoothScan.request();
    }
    if (Platform.isAndroid &&
        await Permission.bluetoothConnect.status.isDenied) {
      debugPrint('Requesting Bluetooth Connect permission...');
      await Permission.bluetoothConnect.request();
    }
    if (Platform.isAndroid &&
        await Permission.bluetoothAdvertise.status.isDenied) {
      debugPrint('Requesting Bluetooth Advertise permission...');
      await Permission.bluetoothAdvertise.request();
    }

    // Request location permissions. Prioritize "Always" for continuous background GPS logging.
    var locationStatus = await Permission.location.status;
    if (locationStatus.isDenied) {
      debugPrint('Requesting location permission...');
      await Permission.location.request();
    }

    // If location is granted (either WhileInUse or Always), specifically request "Always"
    // for robust background location tracking.
    if (await Permission.location.isGranted) {
      var backgroundLocationStatus = await Permission.locationAlways.status;
      if (backgroundLocationStatus.isDenied) {
        debugPrint('Requesting background location permission...');
        // This will open a dialog to guide the user to settings if needed for "Always" permission.
        await Permission.locationAlways.request();
      }
    }

    // Request storage permission for Android for CSV file saving in external storage
    if (Platform.isAndroid) {
      var storageStatus = await Permission.storage.status;
      if (storageStatus.isDenied) {
        debugPrint('Requesting storage permission...');
        await Permission.storage.request();
      }
    }
    debugPrint('Permissions requested.');
  }

  /// Determines the file path for the CSV log.
  /// On Android, it uses `getExternalStorageDirectory` for easier user access.
  /// On iOS, it uses `getApplicationDocumentsDirectory`.
  /// Returns a unique file path for the CSV log, creating it if necessary.
  static Future<String> get csvFilePath async {
    Directory? directory;

    if (csvPath == null) {
      if (Platform.isAndroid) {
        // getExternalStorageDirectory requires WRITE_EXTERNAL_STORAGE permission on older Android,
        // but on newer versions, it's typically managed by `requestLegacyExternalStorage` or scoped storage.
        directory = await getExternalStorageDirectory();
      } else {
        // For iOS, the application's document directory is appropriate.
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception("Could not get application directory for CSV storage.");
      }
      csvPath = '${directory.path}/sensor_log_${DateTime.now()}.csv';
      return csvPath!;
    }

    return csvPath!;
  }

  /// Generates a unique CSV file path using the device name and current timestamp.
  /// The device name is sanitized for file system compatibility.
  static Future<String> generateCsvFilePath(String deviceName) async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    if (directory == null) {
      throw Exception("Could not get application directory for CSV storage.");
    }
    // Sanitize device name for file system
    final safeDeviceName = deviceName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '${directory.path}/${safeDeviceName}_$timestamp.csv';
  }

  /// Returns a list of all CSV files in the app's storage directory.
  /// Used for listing, deleting, or zipping all log files.
  static Future<List<File>> getAllCsvFiles() async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    if (directory == null) {
      throw Exception("Could not get application directory for CSV storage.");
    }

    return directory.listSync().whereType<File>().where((file) {
      return file.path.endsWith('.csv');
    }).toList();
  }

  /// Zips all CSV files in the app's storage directory and returns the ZIP file.
  /// Returns `null` if there are no CSV files to zip.
  /// The ZIP file is created in the same directory as the CSV files.
  static Future<File?> zipAllCsv() async {
    List<File> allCsvFiles = await getAllCsvFiles();
    if (allCsvFiles.isEmpty) {
      return null;
    } else {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipFile = File(
        '${allCsvFiles.first.parent.path}/sensor_logs_$timestamp.zip',
      );
      final archive = Archive();

      for (var file in allCsvFiles) {
        final bytes = await file.readAsBytes();
        archive.addFile(
          ArchiveFile(file.path.split('/').last, bytes.length, bytes),
        );
      }

      final zipData = ZipEncoder().encode(archive);
      await zipFile.writeAsBytes(zipData, flush: true);

      // Wait for the file to actually exist (should be instant, but just in case)
      int tries = 0;
      while (!await zipFile.exists() && tries < 10) {
        await Future.delayed(const Duration(milliseconds: 50));
        tries++;
      }

      return zipFile;
    }
  }

  /// Displays a SnackBar message at the bottom of the screen.
  /// Uses [Fluttertoast] to show a toast message. If the widget is not mounted,
  /// the message is not shown.
  static void showSnackBar(String message, BuildContext context) {
    if (!context.mounted) {
      debugPrint(
        'UI: SnackBar message "$message" not shown, widget not mounted.',
      );
      return; // Ensure widget is still mounted
    }
    debugPrint('UI: Showing SnackBar: $message');
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
    );
  }
}
