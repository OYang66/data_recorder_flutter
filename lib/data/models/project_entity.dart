class ProjectEntity {
  const ProjectEntity({
    this.id,
    required this.name,
    required this.buildingName,
    required this.standardContent,
    required this.fastContent,
    required this.loadingContent,
    required this.qualityContent,
  });

  final int? id;
  final String name;
  final String buildingName;
  final String standardContent;
  final String fastContent;
  final String loadingContent;
  final String qualityContent;

  ProjectEntity copyWith({
    int? id,
    String? name,
    String? buildingName,
    String? standardContent,
    String? fastContent,
    String? loadingContent,
    String? qualityContent,
  }) {
    return ProjectEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      buildingName: buildingName ?? this.buildingName,
      standardContent: standardContent ?? this.standardContent,
      fastContent: fastContent ?? this.fastContent,
      loadingContent: loadingContent ?? this.loadingContent,
      qualityContent: qualityContent ?? this.qualityContent,
    );
  }

  factory ProjectEntity.fromMap(Map<String, Object?> map) {
    final rawId = map['id'];
    return ProjectEntity(
      id: rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? ''),
      name: map['name'] as String? ?? '默认项目',
      buildingName: map['buildingName'] as String? ?? '',
      standardContent: map['standardContent'] as String? ?? '[]',
      fastContent: map['fastContent'] as String? ?? '[]',
      loadingContent: map['loadingContent'] as String? ?? '',
      qualityContent: map['qualityContent'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'buildingName': buildingName,
      'standardContent': standardContent,
      'fastContent': fastContent,
      'loadingContent': loadingContent,
      'qualityContent': qualityContent,
    };
  }
}
