import 'package:flutter/material.dart';
import 'package:sensor_logging/services/preferences_service.dart';
import 'package:sensor_logging/services/api_service.dart';
import 'package:sensor_logging/utils.dart';

/// Page for configuring server settings (URL and session code).
class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _sessionCodeController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _sessionCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final serverUrl = await PreferencesService.instance.getServerUrl();
      final sessionCode = await PreferencesService.instance.getSessionCode();

      if (mounted) {
        setState(() {
          _serverUrlController.text = serverUrl ?? '';
          _sessionCodeController.text = sessionCode ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _testConnection() async {
    if (_isTesting) return;

    final validationError = ApiService.validateUrl(_serverUrlController.text);
    if (validationError != null) {
      Utils.showSnackBar(validationError, context);
      return;
    }

    setState(() => _isTesting = true);

    try {
      final success = await ApiService.pingServer(_serverUrlController.text.trim());

      if (mounted) {
        if (success) {
          Utils.showSnackBar('Connexion réussie !', context);
        } else {
          Utils.showSnackBar('Échec de la connexion au serveur', context);
        }
      }
    } catch (e) {
      if (mounted) {
        Utils.showSnackBar('Erreur: $e', context);
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;

    final serverUrl = _serverUrlController.text.trim();
    if (serverUrl.isNotEmpty) {
      final validationError = ApiService.validateUrl(serverUrl);
      if (validationError != null) {
        Utils.showSnackBar(validationError, context);
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      await PreferencesService.instance.setServerUrl(serverUrl);
      await PreferencesService.instance.setSessionCode(
        _sessionCodeController.text.trim(),
      );

      if (mounted) {
        Utils.showSnackBar('Paramètres sauvegardés', context);
      }
    } catch (e) {
      if (mounted) {
        Utils.showSnackBar('Erreur lors de la sauvegarde: $e', context);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lien du serveur de données',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      hintText: 'https://',
                      border: UnderlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enabled: !_isSaving && !_isTesting,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _isTesting || _isSaving ? null : _testConnection,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                      ),
                      icon: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find, size: 18),
                      label: Text(_isTesting ? 'Test en cours...' : 'Tester la connexion'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Code de session',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextField(
                    controller: _sessionCodeController,
                    decoration: const InputDecoration(
                      hintText: '1234',
                      border: UnderlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    enabled: !_isSaving,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving || _isTesting ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
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
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
