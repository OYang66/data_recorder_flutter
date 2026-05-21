class AppNoticeInfo {
  const AppNoticeInfo({
    this.noticeId,
    required this.noticeTitle,
    required this.noticeType,
    required this.noticeContent,
    required this.createTime,
    required this.updateTime,
  });

  final int? noticeId;
  final String noticeTitle;
  final String noticeType;
  final String noticeContent;
  final String createTime;
  final String updateTime;

  String get displayKey =>
      [noticeId?.toString() ?? '', updateTime, createTime].join('|');

  factory AppNoticeInfo.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return AppNoticeInfo(
      noticeId: _readNullableInt(json, 'noticeId'),
      noticeTitle: json['noticeTitle']?.toString() ?? '',
      noticeType: json['noticeType']?.toString() ?? '',
      noticeContent: json['noticeContent']?.toString() ?? '',
      createTime: json['createTime']?.toString() ?? '',
      updateTime: json['updateTime']?.toString() ?? '',
    );
  }
}

class ServerPageResult<T> {
  const ServerPageResult({required this.rows, required this.total});

  final List<T> rows;
  final int total;

  factory ServerPageResult.fromJson(Object? value, T Function(Object?) parse) {
    final json = value as Map<String, Object?>? ?? {};
    final rows = json['rows'];
    return ServerPageResult<T>(
      rows: rows is List ? rows.map(parse).toList() : <T>[],
      total: _readInt(json, 'total'),
    );
  }
}

class DeliveryOrderFileItem {
  const DeliveryOrderFileItem({
    this.fileId,
    required this.projectName,
    required this.fileName,
    required this.fileSize,
    required this.sheetCount,
    required this.uploadUserId,
    required this.uploadUserName,
    required this.createTime,
  });

  final int? fileId;
  final String projectName;
  final String fileName;
  final int fileSize;
  final int sheetCount;
  final int? uploadUserId;
  final String uploadUserName;
  final String createTime;

  factory DeliveryOrderFileItem.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return DeliveryOrderFileItem(
      fileId: _readNullableInt(json, 'fileId'),
      projectName: json['projectName']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      fileSize: _readInt(json, 'fileSize'),
      sheetCount: _readInt(json, 'sheetCount'),
      uploadUserId: _readNullableInt(json, 'uploadUserId'),
      uploadUserName: json['uploadUserName']?.toString() ?? '',
      createTime: json['createTime']?.toString() ?? '',
    );
  }
}

class DeliveryMaterialNameItem {
  const DeliveryMaterialNameItem({
    this.id,
    required this.materialKey,
    required this.materialLabel,
    required this.aliasName,
    required this.recordType,
    required this.sortOrder,
  });

  final int? id;
  final String materialKey;
  final String materialLabel;
  final String aliasName;
  final String recordType;
  final int sortOrder;

  factory DeliveryMaterialNameItem.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return DeliveryMaterialNameItem(
      id: _readNullableInt(json, 'id'),
      materialKey: json['materialKey']?.toString() ?? '',
      materialLabel: json['materialLabel']?.toString() ?? '',
      aliasName: json['aliasName']?.toString() ?? '',
      recordType: json['recordType']?.toString() ?? '',
      sortOrder: _readInt(json, 'sortOrder'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'materialKey': materialKey,
    'materialLabel': materialLabel,
    'aliasName': aliasName,
    'recordType': recordType,
    'sortOrder': sortOrder,
  };
}

class MissingMaterialItem {
  const MissingMaterialItem({
    required this.materialName,
    required this.count,
    required this.sources,
  });

  final String materialName;
  final int count;
  final List<String> sources;

  factory MissingMaterialItem.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    final rawSources = json['sources'];
    return MissingMaterialItem(
      materialName: json['materialName']?.toString() ?? '',
      count: _readInt(json, 'count'),
      sources: rawSources is List
          ? rawSources.map((item) => item.toString()).toList()
          : const [],
    );
  }
}

class DeliveryOrderSheetItem {
  const DeliveryOrderSheetItem({
    required this.sheetName,
    required this.projectName,
    required this.buildingName,
    required this.deliveryDate,
    required this.vehicleNo,
    required this.aluminumWeight,
    required this.aluminumArea,
    required this.ironTotalWeight,
    required this.ironBackWeight,
    required this.hangerWeight,
  });

  final String sheetName;
  final String projectName;
  final String buildingName;
  final String deliveryDate;
  final String vehicleNo;
  final double aluminumWeight;
  final double aluminumArea;
  final double ironTotalWeight;
  final double ironBackWeight;
  final double hangerWeight;

  factory DeliveryOrderSheetItem.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return DeliveryOrderSheetItem(
      sheetName: json['sheetName']?.toString() ?? '',
      projectName: json['projectName']?.toString() ?? '',
      buildingName: json['buildingName']?.toString() ?? '',
      deliveryDate: json['deliveryDate']?.toString() ?? '',
      vehicleNo: json['vehicleNo']?.toString() ?? '',
      aluminumWeight: _readDouble(json, 'aluminumWeight'),
      aluminumArea: _readDouble(json, 'aluminumArea'),
      ironTotalWeight: _readDouble(json, 'ironTotalWeight'),
      ironBackWeight: _readDouble(json, 'ironBackWeight'),
      hangerWeight: _readDouble(json, 'hangerWeight'),
    );
  }
}

class SettlementTypeOption {
  const SettlementTypeOption({required this.label, required this.value});

  final String label;
  final String value;

  factory SettlementTypeOption.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return SettlementTypeOption(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }
}

class SettlementColumnItem {
  const SettlementColumnItem({required this.prop, required this.label});

  final String prop;
  final String label;

  factory SettlementColumnItem.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return SettlementColumnItem(
      prop: json['prop']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }
}

class ServerProjectInfo {
  const ServerProjectInfo({required this.projectName, this.projectId});

  final String projectName;
  final int? projectId;

  factory ServerProjectInfo.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return ServerProjectInfo(
      projectName: json['projectName']?.toString() ?? '',
      projectId: (json['projectId'] as num?)?.toInt(),
    );
  }
}

class ServerBuildingInfo {
  const ServerBuildingInfo({required this.buildingName, this.buildingId});

  final String buildingName;
  final int? buildingId;

  factory ServerBuildingInfo.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return ServerBuildingInfo(
      buildingName: json['buildingName']?.toString() ?? '',
      buildingId: (json['buildingId'] as num?)?.toInt(),
    );
  }
}

class ServerStatSummary {
  const ServerStatSummary({
    required this.todayCount,
    required this.weekCount,
    required this.monthCount,
    required this.quarterCount,
    required this.yearCount,
  });

  final int todayCount;
  final int weekCount;
  final int monthCount;
  final int quarterCount;
  final int yearCount;

  factory ServerStatSummary.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return ServerStatSummary(
      todayCount: _readInt(json, 'todayCount'),
      weekCount: _readInt(json, 'weekCount'),
      monthCount: _readInt(json, 'monthCount'),
      quarterCount: _readInt(json, 'quarterCount'),
      yearCount: _readInt(json, 'yearCount'),
    );
  }
}

int _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _readNullableInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double _readDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
