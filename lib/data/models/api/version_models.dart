class AppVersionInfo {
  const AppVersionInfo({
    this.id,
    required this.versionCode,
    required this.versionName,
    this.updateTitle = '',
    this.updateContent = '',
    required this.downloadUrl,
    this.forceUpdate = 0,
    this.status = '0',
  });

  final int? id;
  final int versionCode;
  final String versionName;
  final String updateTitle;
  final String updateContent;
  final String downloadUrl;
  final int forceUpdate;
  final String status;

  bool get isForceUpdate => forceUpdate == 1;

  factory AppVersionInfo.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return AppVersionInfo(
      id: (json['id'] as num?)?.toInt(),
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
      versionName: json['versionName']?.toString() ?? '',
      updateTitle: json['updateTitle']?.toString() ?? '',
      updateContent: json['updateContent']?.toString() ?? '',
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      forceUpdate: (json['forceUpdate'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? '0',
    );
  }
}
