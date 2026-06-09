import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Service for communicating with the VeloClimap server.
class ApiService {
  /// Test the connection to the server by pinging the /ping endpoint.
  /// Returns true if the server responds successfully, false otherwise.
  static Future<bool> pingServer(String serverUrl) async {
    try {
      final baseUrl = _normalizeUrl(serverUrl);
      final uri = Uri.parse('$baseUrl/ping');
      final response = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Upload one or more CSV files to the server as a ZIP archive.
  /// Returns true if upload was successful, false otherwise.
  static Future<bool> uploadSessions({
    required String serverUrl,
    required String sessionCode,
    required List<String> filePaths,
  }) async {
    if (filePaths.isEmpty) {
      return false;
    }

    try {
      // Create ZIP archive from the files
      final zipFile = await _createZipFromFiles(filePaths);
      if (zipFile == null) {
        return false;
      }

      final baseUrl = _normalizeUrl(serverUrl);
      final uri = Uri.parse('$baseUrl/upload');

      // Create multipart request
      final request = http.MultipartRequest('POST', uri);
      request.headers['X-Code'] = sessionCode;
      request.files.add(
        await http.MultipartFile.fromPath('file', zipFile.path),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      // Clean up temp ZIP file
      try {
        await zipFile.delete();
      } catch (e) {
        // Failed to delete temp ZIP
      }

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Create a ZIP file from a list of file paths.
  static Future<File?> _createZipFromFiles(List<String> filePaths) async {
    try {
      final archive = Archive();

      for (final path in filePaths) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final fileName = path.split('/').last;
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        }
      }

      if (archive.isEmpty) {
        return null;
      }

      final zipData = ZipEncoder().encode(archive);

      // Create temp file for ZIP
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipFile = File('${tempDir.path}/upload_$timestamp.zip');
      await zipFile.writeAsBytes(zipData, flush: true);

      return zipFile;
    } catch (e) {
      return null;
    }
  }

  /// Normalize URL by removing trailing slash.
  static String _normalizeUrl(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Validate that a URL is properly formatted.
  /// Returns null if valid, or an error message if invalid.
  static String? validateUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return 'L\'URL du serveur est requise';
    }

    final trimmedUrl = url.trim();
    final uri = Uri.tryParse(trimmedUrl);

    if (uri == null) {
      return 'Format d\'URL invalide';
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'L\'URL doit commencer par http:// ou https://';
    }

    if (uri.host.isEmpty) {
      return 'L\'URL doit contenir un nom de domaine';
    }

    return null;
  }
}
