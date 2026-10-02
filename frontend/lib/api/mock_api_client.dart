import 'dart:convert';

import '../models/best_shot.dart';
import '../models/search_result.dart';
import '../models/wrapped.dart';
import 'api_client.dart';

/// Hardcoded responses, held as raw JSON strings in the exact wire format of
/// the API contract.
///
/// Two reasons for raw JSON rather than Dart objects:
///   1. It goes through `jsonDecode` + the real `fromJson` constructors, so
///      the mock exercises the same parsing path the live backend will. A
///      field-name typo fails here and now, not during the live swap.
///   2. When your teammate's endpoint goes live, `curl localhost:8000/search
///      -G --data-urlencode 'q=beach'` and dropping that output in here is a
///      straight paste.
///
/// Query words are special-cased to exercise the UI's other states without
/// having to take the backend down mid-demo:
///   * a query containing `fail`  -> error state
///   * a query containing `empty` -> empty state
class MockApiClient implements ApiClient {
  /// Fake latency so loading states are actually visible while building the UI.
  static const Duration _latency = Duration(milliseconds: 450);

  /// 12 results, deliberately including two with `"location": null` so the
  /// nullable-location path is exercised from day one.
  static const String _searchResultsJson = '''
[
  {"id": "abc123", "thumbnail_url": "/thumbnails/abc123.jpg", "taken_at": "2026-04-12T14:33:00", "location": {"lat": 8.0688, "lon": 77.5611}, "score": 0.94},
  {"id": "abc124", "thumbnail_url": "/thumbnails/abc124.jpg", "taken_at": "2026-04-12T14:34:12", "location": {"lat": 8.0691, "lon": 77.5614}, "score": 0.91},
  {"id": "abc125", "thumbnail_url": "/thumbnails/abc125.jpg", "taken_at": "2026-04-12T15:02:00", "location": null, "score": 0.88},
  {"id": "abc126", "thumbnail_url": "/thumbnails/abc126.jpg", "taken_at": "2026-04-12T15:40:00", "location": {"lat": 8.0689, "lon": 76.5607}, "score": 0.79},
  {"id": "def456", "thumbnail_url": "/thumbnails/def456.jpg", "taken_at": "2026-02-27T09:12:00", "location": {"lat": 10.0889, "lon": 77.0595}, "score": 0.86},
  {"id": "def457", "thumbnail_url": "/thumbnails/def457.jpg", "taken_at": "2026-02-27T09:18:00", "location": {"lat": 10.0891, "lon": 77.0593}, "score": 0.83},
  {"id": "ghi012", "thumbnail_url": "/thumbnails/ghi012.jpg", "taken_at": "2025-12-31T21:05:00", "location": null, "score": 0.81},
  {"id": "jkl345", "thumbnail_url": "/thumbnails/jkl345.jpg", "taken_at": "2026-08-15T17:45:00", "location": {"lat": 9.9658, "lon": 76.2422}, "score": 0.77},
  {"id": "mno678", "thumbnail_url": "/thumbnails/mno678.jpg", "taken_at": "2026-06-08T11:30:00", "location": {"lat": 9.9967, "lon": 76.2698}, "score": 0.72},
  {"id": "pqr901", "thumbnail_url": "/thumbnails/pqr901.jpg", "taken_at": "2026-01-19T07:55:00", "location": {"lat": 10.5276, "lon": 76.2144}, "score": 0.69},
  {"id": "rst234", "thumbnail_url": "/thumbnails/rst234.jpg", "taken_at": "2026-03-03T19:20:00", "location": {"lat": 8.5061, "lon": 76.9496}, "score": 0.64},
  {"id": "uvw567", "thumbnail_url": "/thumbnails/uvw567.jpg", "taken_at": "2026-05-22T12:10:00", "location": {"lat": 9.9312, "lon": 76.2673}, "score": 0.58}
]
''';

  static const String _wrappedJson = '''
{
  "generated_at": "2026-10-03T10:00:00",
  "top_people": [
    {"cluster_id": "p1", "label": "You", "photo_count": 340},
    {"cluster_id": "p2", "label": "Arjun", "photo_count": 128},
    {"cluster_id": "p3", "label": "Priya", "photo_count": 96},
    {"cluster_id": "p4", "label": "Neha", "photo_count": 54},
    {"cluster_id": "p5", "label": "Dad", "photo_count": 41}
  ],
  "top_locations": [
    {"name": "Munnar", "lat": 10.0889, "lon": 77.0595, "photo_count": 87},
    {"name": "Kovalam Beach", "lat": 8.0688, "lon": 77.5611, "photo_count": 63},
    {"name": "Fort Kochi", "lat": 9.9658, "lon": 76.2422, "photo_count": 52},
    {"name": "Vypin Island", "lat": 9.9967, "lon": 76.2698, "photo_count": 30},
    {"name": "Thrissur", "lat": 10.5276, "lon": 76.2144, "photo_count": 18}
  ],
  "pets_detected": true,
  "best_shots": ["abc123", "def456", "burst_01_best", "ghi012", "jkl345", "mno678"],
  "narrative": "You spent the most time with yourself this year - 340 photos, mostly around Munnar. Arjun came close at 128, and Priya showed up in 96. Your pets made 46 appearances. Munnar was your top spot by a wide margin, and 6 photos were sharp enough that the burst picker chose them over their neighbours."
}
''';

  @override
  Future<SearchResponse> search(String query, {int topK = 20}) async {
    await Future<void>.delayed(_latency);

    final q = query.toLowerCase();
    if (q.contains('fail')) {
      throw ApiException(
        "Can't reach the omaly backend at http://localhost:8000.\n"
        'Is it running? (cd backend && uv run main.py)',
      );
    }

    final results = q.contains('empty')
        ? <Map<String, dynamic>>[]
        : (jsonDecode(_searchResultsJson) as List<dynamic>)
            .cast<Map<String, dynamic>>();

    // Sort by score descending and honour top_k, so the mock grid behaves the
    // way the real endpoint's will.
    final sorted = [...results]..sort(
        (a, b) => (b['score'] as num).compareTo(a['score'] as num));
    final limited =
        sorted.length > topK ? sorted.sublist(0, topK) : sorted;

    return SearchResponse.fromJson({
      'query': query, // echoed back verbatim, as the backend does
      'results': limited,
    });
  }

  @override
  Future<BestShotResponse> bestShot(String groupId) async {
    await Future<void>.delayed(_latency);
    return BestShotResponse.fromJson({
      'group_id': groupId,
      'best_photo_id': 'abc123',
      'candidates': ['abc123', 'abc124', 'abc125', 'abc126'],
    });
  }

  @override
  Future<WrappedSummary> wrapped() async {
    await Future<void>.delayed(_latency);
    return WrappedSummary.fromJson(
      jsonDecode(_wrappedJson) as Map<String, dynamic>,
    );
  }

  @override
  Future<bool> health() async => true;

  @override
  Uri? thumbnailUri(String photoId, {String? relativePath}) =>
      null; // No server in mock mode; the UI draws placeholder tiles.
}