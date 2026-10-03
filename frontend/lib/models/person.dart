/// Model for a face cluster / person returned by `GET /people`.
library;

class PersonCluster {
  const PersonCluster({
    required this.id,
    required this.name,
    required this.photoCount,
    this.coverPhotoId,
    this.thumbnailUrl,
  });

  final String id;
  final String name;
  final int photoCount;
  final String? coverPhotoId;
  final String? thumbnailUrl;

  PersonCluster copyWith({
    String? id,
    String? name,
    int? photoCount,
    String? coverPhotoId,
    String? thumbnailUrl,
  }) {
    return PersonCluster(
      id: id ?? this.id,
      name: name ?? this.name,
      photoCount: photoCount ?? this.photoCount,
      coverPhotoId: coverPhotoId ?? this.coverPhotoId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }

  factory PersonCluster.fromJson(Map<String, dynamic> json) => PersonCluster(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Person ${json['id']}',
        photoCount: (json['photo_count'] as num?)?.toInt() ?? 0,
        coverPhotoId: json['cover_photo_id'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'photo_count': photoCount,
        'cover_photo_id': coverPhotoId,
        'thumbnail_url': thumbnailUrl,
      };
}
