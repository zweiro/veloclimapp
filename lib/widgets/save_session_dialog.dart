import 'package:flutter/material.dart';
import 'package:sensor_logging/services/database_service.dart';

/// Dialog shown when user stops a recording session.
/// Allows user to enter a custom name for the session.
class SaveSessionDialog extends StatefulWidget {
  /// The CSV file path for this session.
  final String csvFilePath;

  /// Timestamp when the recording started.
  final DateTime startedAt;

  /// Callback when session is saved successfully.
  final VoidCallback? onSaved;

  const SaveSessionDialog({
    super.key,
    required this.csvFilePath,
    required this.startedAt,
    this.onSaved,
  });

  @override
  State<SaveSessionDialog> createState() => _SaveSessionDialogState();
}

class _SaveSessionDialogState extends State<SaveSessionDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = _defaultName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Generate default session name in format: YYYYMMDD_HHMM-HHMM
  String get _defaultName {
    final start = widget.startedAt;
    final end = DateTime.now();

    final dateStr =
        '${start.year}${start.month.toString().padLeft(2, '0')}${start.day.toString().padLeft(2, '0')}';
    final startTimeStr =
        '${start.hour.toString().padLeft(2, '0')}${start.minute.toString().padLeft(2, '0')}';
    final endTimeStr =
        '${end.hour.toString().padLeft(2, '0')}${end.minute.toString().padLeft(2, '0')}';

    return '${dateStr}_$startTimeStr-$endTimeStr';
  }

  Future<void> _saveSession() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final sessionName =
          _nameController.text.trim().isEmpty ? _defaultName : _nameController.text.trim();
      final now = DateTime.now();

      final session = Session(
        name: sessionName,
        filePath: widget.csvFilePath,
        createdAt: widget.startedAt,
        endedAt: now,
      );

      await DatabaseService.instance.insertSession(session);

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'enregistrement: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Enregistrement de la mesure',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
      content: TextField(
        controller: _nameController,
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        autofocus: true,
        enabled: !_isSaving,
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'VALIDER',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
    );
  }
}
