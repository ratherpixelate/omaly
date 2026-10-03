/// Models for burst photos and the AI best shot picker.
library;

class BurstPhoto {
  const BurstPhoto({
    required this.id,
    required this.filename,
    required this.name,
    this.url,
    this.thumbnailUrl,
    this.takenAt,
    this.isBest = false,
    this.isCandidate = false,
    this.rank = 1,
    this.score,
    this.blinkTier,
    this.nFaces,
    this.nClosed,
    this.eyesOpenness,
    this.sharpness,
  });

  final String id;
  final String filename;
  final String name;
  final String? url;
  final String? thumbnailUrl;
  final String? takenAt;
  final bool isBest;
  final bool isCandidate;
  final int rank;
  final double? score;
  final int? blinkTier;
  final int? nFaces;
  final int? nClosed;
  final double? eyesOpenness;
  final double? sharpness;

  factory BurstPhoto.fromJson(Map<String, dynamic> json) => BurstPhoto(
        id: json['id'] as String,
        filename: json['filename'] as String? ?? json['name'] as String? ?? '',
        name: json['name'] as String? ?? json['filename'] as String? ?? '',
        url: json['url'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        takenAt: json['taken_at'] as String?,
        isBest: json['is_best'] as bool? ?? false,
        isCandidate: json['is_candidate'] as bool? ?? false,
        rank: (json['rank'] as num?)?.toInt() ?? 1,
        score: (json['score'] as num?)?.toDouble(),
        blinkTier: (json['blink_tier'] as num?)?.toInt(),
        nFaces: (json['n_faces'] as num?)?.toInt(),
        nClosed: (json['n_closed'] as num?)?.toInt(),
        eyesOpenness: (json['eyes_openness'] as num?)?.toDouble(),
        sharpness: (json['sharpness'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'name': name,
        'url': url,
        'thumbnail_url': thumbnailUrl,
        'taken_at': takenAt,
        'is_best': isBest,
        'is_candidate': isCandidate,
        'rank': rank,
        'score': score,
        'blink_tier': blinkTier,
        'n_faces': nFaces,
        'n_closed': nClosed,
        'eyes_openness': eyesOpenness,
        'sharpness': sharpness,
      };
}

class BurstGroup {
  const BurstGroup({
    required this.id,
    required this.photoCount,
    required this.bestPhotoId,
    required this.candidates,
    required this.photos,
  });

  final String id;
  final int photoCount;
  final String bestPhotoId;
  final List<String> candidates;
  final List<BurstPhoto> photos;

  BurstPhoto? get bestPhoto {
    for (final p in photos) {
      if (p.id == bestPhotoId) return p;
    }
    return photos.isNotEmpty ? photos.first : null;
  }

  factory BurstGroup.fromJson(Map<String, dynamic> json) => BurstGroup(
        id: json['group_id'] as String,
        photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
        bestPhotoId: json['best_photo_id'] as String? ?? '',
        candidates: (json['candidates'] as List<dynamic>?)
                ?.map((c) => c as String)
                .toList() ??
            const [],
        photos: (json['photos'] as List<dynamic>?)
                ?.map((p) => BurstPhoto.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'group_id': id,
        'photo_count': photoCount,
        'best_photo_id': bestPhotoId,
        'candidates': candidates,
        'photos': photos.map((p) => p.toJson()).toList(),
      };
}
