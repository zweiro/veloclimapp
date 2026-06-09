import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sensor_logging/services/database_service.dart';
import 'package:sensor_logging/services/api_service.dart';
import 'package:sensor_logging/services/preferences_service.dart';
import 'package:sensor_logging/utils.dart';

/// Filter/sort options for the session list.
enum SessionFilter {
  newest('Plus récentes'),
  oldest('Plus anciennes'),
  notSynced('Pas encore synchronisées');

  final String label;
  const SessionFilter(this.label);
}

/// Page displaying all recorded sessions in a table format.
class SessionTablePage extends StatefulWidget {
  const SessionTablePage({super.key});

  @override
  State<SessionTablePage> createState() => _SessionTablePageState();
}

class _SessionTablePageState extends State<SessionTablePage> {
  List<Session> _sessions = [];
  bool _isLoading = true;
  SessionFilter _currentFilter = SessionFilter.newest;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);

    try {
      final sessions = await DatabaseService.instance.getAllSessions(
        syncedFilter: _currentFilter == SessionFilter.notSynced ? false : null,
        newestFirst: _currentFilter != SessionFilter.oldest,
      );

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        Utils.showSnackBar('Erreur lors du chargement des sessions', context);
      }
    }
  }

  Future<void> _shareSession(Session session) async {
    try {
      final file = File(session.filePath);
      if (await file.exists()) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(session.filePath)]),
        );
      } else {
        if (mounted) {
          Utils.showSnackBar('Fichier introuvable', context);
        }
      }
    } catch (e) {
      if (mounted) {
        Utils.showSnackBar('Erreur lors du partage: $e', context);
      }
    }
  }

  Future<void> _shareAllSessions() async {
    try {
      final zipFile = await Utils.zipAllCsv();
      if (zipFile != null) {
        await SharePlus.instance.share(
          ShareParams(files: [XFile(zipFile.path)]),
        );
      } else {
        if (mounted) {
          Utils.showSnackBar('Aucune donnée à partager', context);
        }
      }
    } catch (e) {
      if (mounted) {
        Utils.showSnackBar('Erreur lors du partage: $e', context);
      }
    }
  }

  Future<void> _syncSession(Session session) async {
    if (session.synced) return;

    final serverUrl = await PreferencesService.instance.getServerUrl();
    final sessionCode = await PreferencesService.instance.getSessionCode();

    if (serverUrl == null || serverUrl.isEmpty) {
      if (mounted) {
        Utils.showSnackBar('Veuillez configurer l\'URL du serveur', context);
      }
      return;
    }

    if (sessionCode == null || sessionCode.isEmpty) {
      if (mounted) {
        Utils.showSnackBar('Veuillez configurer le code de session', context);
      }
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final success = await ApiService.uploadSessions(
        serverUrl: serverUrl,
        sessionCode: sessionCode,
        filePaths: [session.filePath],
      );

      if (success) {
        await DatabaseService.instance.markSessionAsSynced(session.id!);
        if (mounted) {
          Utils.showSnackBar('Session synchronisée', context);
          _loadSessions();
        }
      } else {
        if (mounted) {
          Utils.showSnackBar('Échec de la synchronisation', context);
        }
      }
    } catch (e) {
      if (mounted) {
        Utils.showSnackBar('Erreur: $e', context);
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _syncAllNotSynced() async {
    final notSyncedSessions = _sessions.where((s) => !s.synced).toList();
    if (notSyncedSessions.isEmpty) {
      Utils.showSnackBar('Toutes les sessions sont déjà synchronisées', context);
      return;
    }

    final serverUrl = await PreferencesService.instance.getServerUrl();
    final sessionCode = await PreferencesService.instance.getSessionCode();

    if (serverUrl == null || serverUrl.isEmpty) {
      if (mounted) {
        Utils.showSnackBar('Veuillez configurer l\'URL du serveur', context);
      }
      return;
    }

    if (sessionCode == null || sessionCode.isEmpty) {
      if (mounted) {
        Utils.showSnackBar('Veuillez configurer le code de session', context);
      }
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final filePaths = notSyncedSessions.map((s) => s.filePath).toList();
      final success = await ApiService.uploadSessions(
        serverUrl: serverUrl,
        sessionCode: sessionCode,
        filePaths: filePaths,
      );

      if (success) {
        for (final session in notSyncedSessions) {
          await DatabaseService.instance.markSessionAsSynced(session.id!);
        }
        if (mounted) {
          Utils.showSnackBar('${notSyncedSessions.length} session(s) synchronisée(s)', context);
          _loadSessions();
        }
      } else {
        if (mounted) {
          Utils.showSnackBar('Échec de la synchronisation', context);
        }
      }
    } catch (e) {
      if (mounted) {
        Utils.showSnackBar('Erreur: $e', context);
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _deleteSession(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la session'),
        content: Text('Voulez-vous vraiment supprimer "${session.name}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete file
        final file = File(session.filePath);
        if (await file.exists()) {
          await file.delete();
        }
        // Delete from database
        await DatabaseService.instance.deleteSession(session.id!);

        if (mounted) {
          Utils.showSnackBar('Session supprimée', context);
          _loadSessions();
        }
      } catch (e) {
        if (mounted) {
          Utils.showSnackBar('Erreur lors de la suppression: $e', context);
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h${minutes.toString().padLeft(2, '0')}';
    }
    return '${minutes}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'share_all') {
                _shareAllSessions();
              } else if (value == 'sync_all') {
                _syncAllNotSynced();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'share_all',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 12),
                    Text('Tout partager'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'sync_all',
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload, size: 20),
                    SizedBox(width: 12),
                    Text('Tout synchroniser'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter dropdown
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text('Trier', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<SessionFilter>(
                    value: _currentFilter,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: SessionFilter.values.map((filter) {
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(filter.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _currentFilter = value);
                        _loadSessions();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          // Loading indicator
          if (_isSyncing)
            const LinearProgressIndicator(),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Session (${_sessions.length})',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Date / Heure / Durée',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(width: 48), // Space for icons
              ],
            ),
          ),
          // Session list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucune session',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadSessions,
                        child: ListView.separated(
                          itemCount: _sessions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final session = _sessions[index];
                            return _buildSessionRow(session);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Session session) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Session name column
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  session.fileName,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Date/time column
          Expanded(
            flex: 2,
            child: Text(
              '${_formatDate(session.createdAt)}\n${_formatTime(session.createdAt)} - ${_formatTime(session.endedAt)} (${_formatDuration(session.duration)})',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          // Sync status icon
          SvgPicture.asset(
            session.synced ? 'assets/icon/synced.svg' : 'assets/icon/unsynced.svg',
            width: 24,
            height: 24,
          ),
          // Context menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              if (value == 'share') {
                _shareSession(session);
              } else if (value == 'sync') {
                _syncSession(session);
              } else if (value == 'delete') {
                _deleteSession(session);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 18),
                    SizedBox(width: 8),
                    Text('Partager'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sync',
                enabled: !session.synced,
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      size: 18,
                      color: session.synced ? Colors.grey : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Synchroniser',
                      style: TextStyle(
                        color: session.synced ? Colors.grey : null,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Supprimer', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
