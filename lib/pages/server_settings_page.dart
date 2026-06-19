import 'package:flutter/material.dart';
import 'package:sensor_logging/services/preferences_service.dart';
import 'package:sensor_logging/services/api_service.dart';
import 'package:sensor_logging/utils.dart';

const _monthNames = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];

String _formatDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '?';
  try {
    final date = DateTime.parse(isoDate).toLocal();
    return '${date.day} ${_monthNames[date.month - 1]} ${date.year}';
  } catch (e) {
    return isoDate;
  }
}

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
  bool _codeValidated = false;
  String? _validationMessage;
  bool _validationSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _serverUrlController.addListener(_onFieldChanged);
    _sessionCodeController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _serverUrlController.removeListener(_onFieldChanged);
    _sessionCodeController.removeListener(_onFieldChanged);
    _serverUrlController.dispose();
    _sessionCodeController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (_codeValidated) {
      setState(() {
        _codeValidated = false;
        _validationMessage = null;
        _validationSuccess = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      final serverUrl = await PreferencesService.instance.getServerUrl();
      final sessionCode = await PreferencesService.instance.getSessionCode();

      if (mounted) {
        // Temporarily remove listeners to avoid triggering _onFieldChanged
        _serverUrlController.removeListener(_onFieldChanged);
        _sessionCodeController.removeListener(_onFieldChanged);

        setState(() {
          _serverUrlController.text = serverUrl ?? '';
          _sessionCodeController.text = sessionCode ?? '';
          _isLoading = false;
        });

        // Re-add listeners
        _serverUrlController.addListener(_onFieldChanged);
        _sessionCodeController.addListener(_onFieldChanged);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _testConnection() async {
    if (_isTesting) return;

    final serverUrl = _serverUrlController.text.trim();
    final sessionCode = _sessionCodeController.text.trim();

    // Validate URL
    final urlError = ApiService.validateUrl(serverUrl);
    if (urlError != null) {
      setState(() {
        _validationMessage = urlError;
        _validationSuccess = false;
        _codeValidated = false;
      });
      return;
    }

    // Validate code is not empty
    if (sessionCode.isEmpty) {
      setState(() {
        _validationMessage = 'Veuillez entrer le code ThermoParty';
        _validationSuccess = false;
        _codeValidated = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _validationMessage = null;
    });

    try {
      final result = await ApiService.checkThermoCode(
        serverUrl: serverUrl,
        code: sessionCode,
      );

      if (mounted) {
        if (result.valid) {
          setState(() {
            _codeValidated = true;
            _validationSuccess = true;
            _validationMessage = 'Connexion réussie !\nPériode : ${_formatDate(result.startDate)} - ${_formatDate(result.endDate)}';
          });
        } else {
          setState(() {
            _codeValidated = false;
            _validationSuccess = false;
            if (result.reason == 'code_invalide') {
              _validationMessage = 'Code ThermoParty invalide';
            } else if (result.reason == 'hors_periode') {
              _validationMessage = result.message ?? 'Code hors période';
            } else {
              _validationMessage = result.message ?? 'Erreur de validation';
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _codeValidated = false;
          _validationSuccess = false;
          _validationMessage = 'Impossible de contacter le serveur';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving || !_codeValidated) return;

    setState(() => _isSaving = true);

    try {
      await PreferencesService.instance.setServerUrl(
        _serverUrlController.text.trim(),
      );
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
                  const SizedBox(height: 24),
                  Text.rich(
                    TextSpan(
                      text: 'Code de ',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      children: const [
                        TextSpan(
                          text: 'ThermoParty',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: _sessionCodeController,
                    decoration: const InputDecoration(
                      hintText: '1234',
                      border: UnderlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
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
                  if (_validationMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _validationSuccess
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _validationSuccess
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _validationSuccess
                                ? Icons.check_circle
                                : Icons.error,
                            color: _validationSuccess
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _validationMessage!,
                              style: TextStyle(
                                color: _validationSuccess
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving || _isTesting || !_codeValidated
                          ? null
                          : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade500,
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
                  if (!_codeValidated) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Testez la connexion pour pouvoir sauvegarder',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
