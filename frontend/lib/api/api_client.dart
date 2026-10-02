import '../config.dart';
import '../models/best_shot.dart';
import '../models/search_result.dart';
import '../models/wrapped.dart';
import 'http_api_client.dart';
import 'mock_api_client.dart';

/// The single seam between the UI and where JSON comes from.
///
/// Screens depend on this interface only, never on `http` or on hardcoded
/// data. Swapping mock -> real backend is the [kUseMockApi] flag in
/// `config.dart`; nothing else in the app changes.
abstract class ApiClient {
  /// `GET /search?q=<query>&top_k=<topK>`
  Future<SearchResponse> search(String query, {int topK = 20});

  /// `GET /best-shot?group_id=<groupId>`
  Future<BestShotResponse> bestShot(String groupId);

  /// `GET /wrapped`
  Future<WrappedSummary> wrapped();

  /// `GET /health`
  Future<bool> health();

  /// Absolute URL for a photo's thumbnail image, or `null` in mock mode
  /// (there is no server to fetch bytes from, so the UI paints a
  /// deterministic placeholder tile instead).
  ///
  /// [relativePath] is the `thumbnail_url` from search results when available;
  /// ids from `/wrapped` and `/best-shot` only carry the id, so the
  /// `/thumbnails/<id>` path is derived instead.
  Uri? thumbnailUri(String photoId, {String? relativePath});
}

/// Build the client the app should use right now.
///
/// This is the only place [kUseMockApi] is read.
ApiClient createApiClient() =>
    kUseMockApi ? MockApiClient() : HttpApiClient(baseUrl: kApiBaseUrl);

/// Error type every client throws for "we could not get a usable answer",
/// carrying a message that is safe (and useful) to show a judge on screen.
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}