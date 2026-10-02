/// Models for `GET /search?q=<string>&top_k=20`.
///
/// Field names below mirror the API contract EXACTLY (snake_case). If the
/// backend ever sends a different shape, parsing throws and the UI shows a
/// readable contract-mismatch error instead of crashing silently.
library;

class GeoLocation {
  const GeoLocation({required this.lat, required this.lon});

  final double lat;
  final double lon;

  factory GeoLocation.fromJson(Map<String, dynamic> json) => GeoLocation(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );
}

class SearchResult {
  const SearchResult({
    required this.id,
    required this.thumbnailUrl,
    required this.takenAt,
    required this.location,
    required this.score,
  });

  final String id;

  /// Relative path, e.g. `/thumbnails/abc123.jpg`. The API client turns this
  /// into a full URL against [kApiBaseUrl].
  final String thumbnailUrl;
  final DateTime takenAt;

  /// Contract says this can be `null` — keep it nullable everywhere.
  final GeoLocation? location;

  /// Similarity score, 0.0 – 1.0.
  final double score;

  int get scorePercent => (score * 100).round();

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    final locationJson = json['location'];
    return SearchResult(
      id: json['id'] as String,
      thumbnailUrl: json['thumbnail_url'] as String,
      takenAt: DateTime.parse(json['taken_at'] as String),
      location: locationJson == null
          ? null
          : GeoLocation.fromJson(locationJson as Map<String, dynamic>),
      score: (json['score'] as num).toDouble(),
    );
  }
}

class SearchResponse {
  const SearchResponse({required this.query, required this.results});

  final String query;
  final List<SearchResult> results;

  bool get isEmpty => results.isEmpty;

  factory SearchResponse.fromJson(Map<String, dynamic> json) => SearchResponse(
        query: json['query'] as String,
        results: (json['results'] as List<dynamic>)
            .map((r) => SearchResult.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}
