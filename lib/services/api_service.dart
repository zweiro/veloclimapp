import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Service for communicating with the VeloClimap server.
class ApiService {
  /// Test the connection to the server by pinging the /ping endpoint.
  /// Returns true if the server responds successfully, false otherwise.
  static Future<bool> pingServer(String serverUrl) async {
    try {
      // Remove trailing slash if present
      final baseUrl = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;

      final uri = Uri.parse('$baseUrl/ping');
      final response = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      debugPrint('ApiService: Ping response status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('ApiService: Ping error: $e');
      return false;
    }
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
