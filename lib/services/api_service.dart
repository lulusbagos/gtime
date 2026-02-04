import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;

/// API Service untuk Shitcorner API
/// Base URL default untuk Android Emulator / device
/// Saat ini diarahkan ke IP lokal: 192.168.130.236:3021
class ApiService {
  // Daftar base URL dengan fallback otomatis
  static const List<String> _baseUrls = ['https://gtimeapi.pglj.net'];

  // Base URL aktif terakhir yang sukses (untuk kompatibilitas pemanggil lama)
  static String _activeBaseUrl = _baseUrls.first;
  static String get baseUrl => _activeBaseUrl;

  // Timeout duration
  static const Duration timeoutDuration = Duration(seconds: 30);

  // Private constructor untuk singleton pattern
  ApiService._internal();

  // Singleton instance
  static final ApiService _instance = ApiService._internal();

  factory ApiService() {
    return _instance;
  }

  /// GET request
  /// [endpoint] - API endpoint (e.g., '/login', '/users')
  /// [token] - Optional authorization token
  Future<dynamic> get(String endpoint, {String? token}) async {
    try {
      final response = await _withFailover(
        'GET',
        endpoint,
        token: token,
        sender: (url, headers) => http.get(url, headers: headers),
      );
      return _handleResponse(response);
    } catch (e) {
      developer.log('GET Error: $e');
      throw ApiException('GET Request Failed: $e');
    }
  }

  /// POST request
  /// [endpoint] - API endpoint
  /// [body] - Request body (Map)
  /// [token] - Optional authorization token
  Future<dynamic> post(
    String endpoint, {
    required Map<String, dynamic> body,
    String? token,
  }) async {
    try {
      final response = await _withFailover(
        'POST',
        endpoint,
        token: token,
        body: body,
        sender: (url, headers) =>
            http.post(url, headers: headers, body: jsonEncode(body)),
      );
      return _handleResponse(response);
    } catch (e) {
      developer.log('POST Error: $e');
      throw ApiException('POST Request Failed: $e');
    }
  }

  /// PUT request
  /// [endpoint] - API endpoint
  /// [body] - Request body (Map)
  /// [token] - Optional authorization token
  Future<dynamic> put(
    String endpoint, {
    required Map<String, dynamic> body,
    String? token,
  }) async {
    try {
      final response = await _withFailover(
        'PUT',
        endpoint,
        token: token,
        body: body,
        sender: (url, headers) =>
            http.put(url, headers: headers, body: jsonEncode(body)),
      );
      return _handleResponse(response);
    } catch (e) {
      developer.log('PUT Error: $e');
      throw ApiException('PUT Request Failed: $e');
    }
  }

  /// DELETE request
  /// [endpoint] - API endpoint
  /// [token] - Optional authorization token
  Future<dynamic> delete(String endpoint, {String? token}) async {
    try {
      final response = await _withFailover(
        'DELETE',
        endpoint,
        token: token,
        sender: (url, headers) => http.delete(url, headers: headers),
      );
      return _handleResponse(response);
    } catch (e) {
      developer.log('DELETE Error: $e');
      throw ApiException('DELETE Request Failed: $e');
    }
  }

  /// PATCH request
  /// [endpoint] - API endpoint
  /// [body] - Request body (Map)
  /// [token] - Optional authorization token
  Future<dynamic> patch(
    String endpoint, {
    required Map<String, dynamic> body,
    String? token,
  }) async {
    try {
      final response = await _withFailover(
        'PATCH',
        endpoint,
        token: token,
        body: body,
        sender: (url, headers) =>
            http.patch(url, headers: headers, body: jsonEncode(body)),
      );
      return _handleResponse(response);
    } catch (e) {
      developer.log('PATCH Error: $e');
      throw ApiException('PATCH Request Failed: $e');
    }
  }

  Future<http.Response> _withFailover(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    String? token,
    required Future<http.Response> Function(
      Uri url,
      Map<String, String> headers,
    )
    sender,
  }) async {
    final headers = _getHeaders(token: token);
    final urls = [
      _activeBaseUrl,
      ..._baseUrls.where((u) => u != _activeBaseUrl),
    ];
    Object? lastError;

    for (final base in urls) {
      final baseNormalized = base.endsWith('/')
          ? base.substring(0, base.length - 1)
          : base;
      final endpointNormalized = endpoint.startsWith('/')
          ? endpoint.substring(1)
          : endpoint;
      final url = Uri.parse('$baseNormalized/$endpointNormalized');
      developer.log('$method Request: $url');
      if (body != null) developer.log('$method Body: $body');
      try {
        final response = await sender(url, headers).timeout(timeoutDuration);
        developer.log('$method Response (${url.host}): ${response.statusCode}');

        // Jika server error (5xx) coba next base
        if (response.statusCode >= 500) {
          lastError = ApiException(
            'Server error ${response.statusCode} dari $base',
          );
          continue;
        }

        // Simpan base sukses
        _activeBaseUrl = base;
        return response;
      } on TimeoutException catch (e) {
        lastError = e;
        developer.log('$method Timeout ke $base');
      } catch (e) {
        lastError = e;
        developer.log('$method Error ke $base: $e');
      }
    }

    throw ApiException('Semua endpoint gagal dihubungi: $lastError');
  }

  /// Helper method untuk mendapatkan headers
  Map<String, String> _getHeaders({String? token}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  /// Handle response dari server
  dynamic _handleResponse(http.Response response) {
    developer.log('Response Status: ${response.statusCode}');
    developer.log('Response Body: ${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success response
      try {
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse;
      } catch (e) {
        developer.log('JSON Decode Error: $e');
        return response.body;
      }
    } else if (response.statusCode == 401) {
      // Unauthorized - Token invalid or expired
      throw ApiException('Unauthorized - Token invalid or expired');
    } else if (response.statusCode == 403) {
      // Forbidden
      throw ApiException('Forbidden - Access denied');
    } else if (response.statusCode == 404) {
      // Not found
      throw ApiException('Not found - Endpoint tidak ditemukan');
    } else if (response.statusCode == 500) {
      // Server error
      throw ApiException('Server error - Terjadi kesalahan pada server');
    } else {
      // Other errors
      try {
        final errorResponse = jsonDecode(response.body);
        final message = errorResponse['message'] ?? 'Unknown error';
        throw ApiException('API Error (${response.statusCode}): $message');
      } catch (e) {
        throw ApiException(
          'API Error (${response.statusCode}): ${response.body}',
        );
      }
    }
  }
}

/// Custom Exception untuk API errors
class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}
