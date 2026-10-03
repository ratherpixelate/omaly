import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/best_shot.dart';
import '../models/burst.dart';
import '../models/person.dart';
import '../models/search_result.dart';
import '../models/wrapped.dart';
import 'api_client.dart';

/// Talks to the teammate's FastAPI backend over plain HTTP on localhost.
///
/// Every request is wrapped so a dropped local connection surfaces as a
/// readable [ApiException] instead of an unhandled crash or a hung spinner.
class HttpApiClient implements ApiClient {
  HttpApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Semantic search runs a local embedding model, so first-call latency can
  /// be seconds on CPU. Generous, but still bounded so the UI can never hang.
  static const Duration _searchTimeout = Duration(seconds: 15);
  static const Duration _shortTimeout = Duration(seconds: 10);
  static const Duration _wrappedTimeout = Duration(seconds: 30);

  @override
  Future<SearchResponse> search(String query, {int topK = 20}) async {
    final json = await _get(
      '/search',
      queryParams: {'q': query, 'top_k': '$topK'},
      timeout: _searchTimeout,
      what: 'search',
    );
    return _decode(SearchResponse.fromJson, json, 'search');
  }

  @override
  Future<BestShotResponse> bestShot(String groupId) async {
    final json = await _get(
      '/best-shot',
      queryParams: {'group_id': groupId},
      timeout: _shortTimeout,
      what: 'best-shot',
    );
    return _decode(BestShotResponse.fromJson, json, 'best-shot');
  }

  @override
  Future<List<BurstGroup>> getBursts() async {
    final json = await _get('/bursts', timeout: _shortTimeout, what: 'bursts');
    final bursts = (json['bursts'] as List<dynamic>?) ?? [];
    return bursts
        .map((b) => BurstGroup.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<WrappedSummary> wrapped() async {
    final json = await _get('/wrapped', timeout: _wrappedTimeout, what: 'wrapped');
    return _decode(WrappedSummary.fromJson, json, 'wrapped');
  }

  @override
  Future<bool> health() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return false;
      return (jsonDecode(res.body) as Map<String, dynamic>)['status'] == 'ok';
    } catch (_) {
      // Health is a status dot, never a user-facing error.
      return false;
    }
  }

  @override
  Future<List<PersonCluster>> getPeople() async {
    final json = await _get('/people', timeout: _shortTimeout, what: 'people');
    final list = json['people'] as List<dynamic>? ?? [];
    return list
        .map((p) => PersonCluster.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getPersonPhotos(String clusterId) async {
    final json = await _get(
      '/people/$clusterId/photos',
      timeout: _shortTimeout,
      what: 'person photos',
    );
    final list = json['photos'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  @override
  Future<PersonCluster> renamePerson(String clusterId, String newName) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/people/$clusterId/rename'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': newName}),
          )
          .timeout(_shortTimeout);
      if (res.statusCode != 200) {
        throw ApiException(
          'Failed to rename person (${res.statusCode}): ${res.body}',
        );
      }
      return PersonCluster.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Could not rename person: $e');
    }
  }

  @override
  Uri? thumbnailUri(String photoId, {String? relativePath}) {
    final path = (relativePath == null || relativePath.isEmpty)
        ? '/thumbnails/$photoId'
        : relativePath;
    return Uri.parse('$baseUrl$path');
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? queryParams,
    required Duration timeout,
    required String what,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(timeout);
    } on SocketException {
      throw ApiException(
        "Can't reach the omaly backend at $baseUrl.\n"
        'Is it running? (cd backend && uv run main.py)',
      );
    } on HttpException {
      throw ApiException(
        "The backend at $baseUrl closed the connection.\n"
        'It may have crashed mid-request — check its terminal.',
      );
    } catch (_) {
      // TimeoutException and anything else unexpected.
      throw ApiException(
        'The $what request timed out after ${timeout.inSeconds}s.\n'
        'The local model may still be warming up — try again.',
      );
    }

    if (res.statusCode != 200) {
      throw ApiException(
        '$what failed: backend returned HTTP ${res.statusCode}.',
      );
    }

    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException(
        '$what failed: backend sent a response that was not valid JSON.',
      );
    }
  }

  /// Parse the JSON into a model, turning any contract mismatch into a clear
  /// error. A field-name typo (`thumbnailUrl` vs `thumbnail_url`) fails here
  /// with a pointed message instead of silently rendering a blank screen.
  T _decode<T>(
    T Function(Map<String, dynamic>) parse,
    Map<String, dynamic> json,
    String what,
  ) {
    try {
      return parse(json);
    } catch (e) {
      throw ApiException(
        '$what response did not match the API contract.\n'
        '($e)\n\nReceived keys: ${json.keys.join(', ')}',
      );
    }
  }
}