/// Model for `GET /best-shot?group_id=<string>`.
library;

class BestShotResponse {
  const BestShotResponse({
    required this.groupId,
    required this.bestPhotoId,
    required this.candidates,
  });

  final String groupId;
  final String bestPhotoId;
  final List<String> candidates;

  factory BestShotResponse.fromJson(Map<String, dynamic> json) =>
      BestShotResponse(
        groupId: json['group_id'] as String,
        bestPhotoId: json['best_photo_id'] as String,
        candidates: (json['candidates'] as List<dynamic>)
            .map((c) => c as String)
            .toList(),
      );
}
