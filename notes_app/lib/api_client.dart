// ============================================================
// API CLIENT — thin wrapper around http calls to your sync server
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;   // e.g. "http://10.0.2.2:3000" for Android emulator
  final String? authToken;

  ApiClient({required this.baseUrl, this.authToken});

  Future<Map<String, dynamic>> post(String path, {required Map<String, dynamic> body}) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Sync failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
