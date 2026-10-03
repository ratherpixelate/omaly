/// Models for `GET /wrapped` — the Spotify-Wrapped-style recap.
library;

class PersonStat {
  const PersonStat({
    required this.clusterId,
    required this.label,
    required this.photoCount,
    this.coverPhotoId,
    this.thumbnailUrl,
  });

  final String clusterId;
  final String label;
  final int photoCount;
  final String? coverPhotoId;
  final String? thumbnailUrl;

  factory PersonStat.fromJson(Map<String, dynamic> json) => PersonStat(
        clusterId: json['cluster_id'] as String,
        label: json['label'] as String,
        photoCount: (json['photo_count'] as num).toInt(),
        coverPhotoId: json['cover_photo_id'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
      );
}

class LocationStat {
  const LocationStat({
    required this.name,
    required this.lat,
    required this.lon,
    required this.photoCount,
    this.coverPhotoId,
    this.thumbnailUrl,
  });

  final String name;
  final double lat;
  final double lon;
  final int photoCount;
  final String? coverPhotoId;
  final String? thumbnailUrl;

  factory LocationStat.fromJson(Map<String, dynamic> json) => LocationStat(
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        photoCount: (json['photo_count'] as num).toInt(),
        coverPhotoId: json['cover_photo_id'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
      );
}

class WrappedDayStat {
  const WrappedDayStat({
    required this.date,
    required this.formattedDate,
    required this.photoCount,
  });

  final String date;
  final String formattedDate;
  final int photoCount;

  factory WrappedDayStat.fromJson(Map<String, dynamic> json) => WrappedDayStat(
        date: json['date'] as String? ?? '',
        formattedDate: json['formatted_date'] as String? ?? json['date'] as String? ?? '',
        photoCount: (json['photo_count'] as num?)?.toInt() ?? (json['count'] as num?)?.toInt() ?? 0,
      );
}

class WrappedMonthStat {
  const WrappedMonthStat({
    required this.month,
    required this.formattedMonth,
    required this.photoCount,
  });

  final String month;
  final String formattedMonth;
  final int photoCount;

  factory WrappedMonthStat.fromJson(Map<String, dynamic> json) => WrappedMonthStat(
        month: json['month'] as String? ?? '',
        formattedMonth: json['formatted_month'] as String? ?? json['month'] as String? ?? '',
        photoCount: (json['photo_count'] as num?)?.toInt() ?? (json['count'] as num?)?.toInt() ?? 0,
      );
}

class WrappedStatistics {
  const WrappedStatistics({
    required this.totalPhotos,
    this.mostPhotosTakenInADay,
    this.mostVisitedLocation,
    this.mostPhotosWithAPerson,
    this.busiestMonth,
  });

  final int totalPhotos;
  final WrappedDayStat? mostPhotosTakenInADay;
  final LocationStat? mostVisitedLocation;
  final PersonStat? mostPhotosWithAPerson;
  final WrappedMonthStat? busiestMonth;

  factory WrappedStatistics.fromJson(Map<String, dynamic> json) {
    final dayJson = json['most_photos_taken_in_a_day'];
    final locJson = json['most_visited_location'];
    final personJson = json['most_photos_with_a_person'];
    final monthJson = json['busiest_month'];

    return WrappedStatistics(
      totalPhotos: (json['total_photos'] as num?)?.toInt() ?? 0,
      mostPhotosTakenInADay: dayJson == null ? null : WrappedDayStat.fromJson(dayJson as Map<String, dynamic>),
      mostVisitedLocation: locJson == null ? null : LocationStat.fromJson(locJson as Map<String, dynamic>),
      mostPhotosWithAPerson: personJson == null ? null : PersonStat.fromJson(personJson as Map<String, dynamic>),
      busiestMonth: monthJson == null ? null : WrappedMonthStat.fromJson(monthJson as Map<String, dynamic>),
    );
  }
}

class WrappedSummary {
  const WrappedSummary({
    required this.generatedAt,
    this.year = 2026,
    this.totalPhotos = 0,
    this.photosInYear = const [],
    this.photosTakenInYear = const [],
    required this.topPeople,
    required this.topLocations,
    this.statistics,
    required this.petsDetected,
    required this.bestShots,
    required this.narrative,
  });

  final DateTime generatedAt;
  final int year;
  final int totalPhotos;
  final List<String> photosInYear;
  final List<String> photosTakenInYear;
  final List<PersonStat> topPeople;
  final List<LocationStat> topLocations;
  final WrappedStatistics? statistics;
  final bool petsDetected;
  final List<String> bestShots;
  final String narrative;

  factory WrappedSummary.fromJson(Map<String, dynamic> json) {
    final statsJson = json['statistics'];
    final photosList = json['photos_in_year'] ?? json['photos_taken_in_year'];

    return WrappedSummary(
      generatedAt: DateTime.parse(json['generated_at'] as String),
      year: (json['year'] as num?)?.toInt() ?? 2026,
      totalPhotos: (json['total_photos'] as num?)?.toInt() ?? 0,
      photosInYear: photosList != null
          ? (photosList as List<dynamic>).map((s) => s.toString()).toList()
          : const [],
      photosTakenInYear: photosList != null
          ? (photosList as List<dynamic>).map((s) => s.toString()).toList()
          : const [],
      topPeople: (json['top_people'] as List<dynamic>)
          .map((p) => PersonStat.fromJson(p as Map<String, dynamic>))
          .toList(),
      topLocations: (json['top_locations'] as List<dynamic>)
          .map((l) => LocationStat.fromJson(l as Map<String, dynamic>))
          .toList(),
      statistics: statsJson == null
          ? null
          : WrappedStatistics.fromJson(statsJson as Map<String, dynamic>),
      petsDetected: json['pets_detected'] as bool,
      bestShots:
          (json['best_shots'] as List<dynamic>).map((s) => s as String).toList(),
      narrative: json['narrative'] as String,
    );
  }
}
