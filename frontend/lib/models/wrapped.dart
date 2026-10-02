/// Models for `GET /wrapped` — the Spotify-Wrapped-style recap.
library;

class PersonStat {
  const PersonStat({
    required this.clusterId,
    required this.label,
    required this.photoCount,
  });

  final String clusterId;
  final String label;
  final int photoCount;

  factory PersonStat.fromJson(Map<String, dynamic> json) => PersonStat(
        clusterId: json['cluster_id'] as String,
        label: json['label'] as String,
        photoCount: (json['photo_count'] as num).toInt(),
      );
}

class LocationStat {
  const LocationStat({
    required this.name,
    required this.lat,
    required this.lon,
    required this.photoCount,
  });

  final String name;
  final double lat;
  final double lon;
  final int photoCount;

  factory LocationStat.fromJson(Map<String, dynamic> json) => LocationStat(
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        photoCount: (json['photo_count'] as num).toInt(),
      );
}

class WrappedSummary {
  const WrappedSummary({
    required this.generatedAt,
    required this.topPeople,
    required this.topLocations,
    required this.petsDetected,
    required this.bestShots,
    required this.narrative,
  });

  final DateTime generatedAt;
  final List<PersonStat> topPeople;
  final List<LocationStat> topLocations;
  final bool petsDetected;
  final List<String> bestShots;
  final String narrative;

  factory WrappedSummary.fromJson(Map<String, dynamic> json) => WrappedSummary(
        generatedAt: DateTime.parse(json['generated_at'] as String),
        topPeople: (json['top_people'] as List<dynamic>)
            .map((p) => PersonStat.fromJson(p as Map<String, dynamic>))
            .toList(),
        topLocations: (json['top_locations'] as List<dynamic>)
            .map((l) => LocationStat.fromJson(l as Map<String, dynamic>))
            .toList(),
        petsDetected: json['pets_detected'] as bool,
        bestShots:
            (json['best_shots'] as List<dynamic>).map((s) => s as String).toList(),
        narrative: json['narrative'] as String,
      );
}
