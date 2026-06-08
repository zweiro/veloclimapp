import 'package:flutter/material.dart';

/// A button widget for starting or stopping the sensor logging service.
/// Params :
/// - [isConnecting]: If true, the button shows a loading spinner and is disabled.
/// - [isServiceRunning]: If true, the button shows "Stop" and stops the service when pressed.
/// - [startLogging]: Callback to start the logging service.
/// - [stopLogging]: Callback to stop the logging service.
/// - [onServiceStatusChanged]: Optional callback for service status changes.
class ConnectionButton extends StatelessWidget {
  final bool isConnecting;
  final bool isServiceRunning;
  final VoidCallback? startLogging;
  final VoidCallback? stopLogging;
  final VoidCallback? onServiceStatusChanged;

  const ConnectionButton({
    super.key,
    required this.isConnecting,
    required this.isServiceRunning,
    required this.startLogging,
    required this.stopLogging,
    required this.onServiceStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      // Button is disabled if connecting, otherwise calls start or stop callback
      onPressed: isConnecting
          ? null
          : (isServiceRunning ? stopLogging : startLogging),

      // Show spinner if connecting, otherwise play/stop icon
      icon: isConnecting
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : Icon(isServiceRunning ? Icons.stop_circle : Icons.play_circle),
      // Button label changes based on state
      label: Text(
        isConnecting
            ? 'RECHERCHE DU CAPTEUR...'
            : (isServiceRunning ? 'ARRÊTER L\'ENREGISTREMENT' : 'DÉMARRER UNE SESSION'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isServiceRunning
            ? Colors.red.shade700
            : Colors.green.shade700, // Red for stop, Green for start
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          vertical: 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 5,
      ),
    );
  }
}
