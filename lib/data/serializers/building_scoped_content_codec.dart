import 'dart:convert';

class BuildingScopedContent {
  const BuildingScopedContent({
    required this.currentBuildingName,
    required this.contentsByBuilding,
  });

  final String currentBuildingName;
  final Map<String, String> contentsByBuilding;

  String contentFor(String buildingName) =>
      contentsByBuilding[buildingName] ?? '';
}

class BuildingScopedContentCodec {
  const BuildingScopedContentCodec();

  BuildingScopedContent decode(
    String raw, {
    String fallbackBuildingName = '1号楼',
  }) {
    final buildingName = fallbackBuildingName.isNotEmpty
        ? fallbackBuildingName
        : '1号楼';
    if (raw.trim().isEmpty) {
      return BuildingScopedContent(
        currentBuildingName: buildingName,
        contentsByBuilding: {buildingName: ''},
      );
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?> && decoded['buildings'] is List) {
        final map = <String, String>{};
        for (final item in decoded['buildings'] as List) {
          if (item is Map<String, Object?>) {
            final name = item['buildingName']?.toString() ?? '';
            if (name.isNotEmpty) {
              map[name] = item['content']?.toString() ?? '';
            }
          }
        }
        final current =
            decoded['currentBuildingName']?.toString() ?? buildingName;
        return BuildingScopedContent(
          currentBuildingName: current.isNotEmpty ? current : buildingName,
          contentsByBuilding: map.isEmpty ? {buildingName: ''} : map,
        );
      }
    } catch (_) {
      return BuildingScopedContent(
        currentBuildingName: buildingName,
        contentsByBuilding: {buildingName: raw},
      );
    }

    return BuildingScopedContent(
      currentBuildingName: buildingName,
      contentsByBuilding: {buildingName: raw},
    );
  }

  String encode(BuildingScopedContent content) {
    return jsonEncode({
      'currentBuildingName': content.currentBuildingName,
      'buildings': content.contentsByBuilding.entries
          .map((entry) => {'buildingName': entry.key, 'content': entry.value})
          .toList(),
    });
  }
}
