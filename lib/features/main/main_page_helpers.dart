part of 'main_page.dart';

class _ModeColumn {
  const _ModeColumn(this.key, this.label, {this.number = false});
  final String key;
  final String label;
  final bool number;
}

List<_ModeColumn> _loadingColumns({
  required String packageTitle,
  required String quantityTitle,
  required String weightTitle,
}) => [
  const _ModeColumn('material', '物料名称'),
  _ModeColumn('packages', packageTitle, number: true),
  _ModeColumn('quantity', quantityTitle, number: true),
  _ModeColumn('weight', weightTitle, number: true),
  const _ModeColumn('remark', '备注'),
];

List<_ModeColumn> _columnsForMode(MainMode mode) => switch (mode) {
  MainMode.standard => const [
    _ModeColumn('installNumber', '安装编号'),
    _ModeColumn('model', '型号'),
    _ModeColumn('quantity', '数量', number: true),
  ],
  MainMode.fast => const [
    _ModeColumn('width', '宽度', number: true),
    _ModeColumn('model', '型号'),
    _ModeColumn('length', '长度', number: true),
    _ModeColumn('quantity', '数量', number: true),
  ],
  MainMode.loading => const [
    _ModeColumn('material', '物料名称'),
    _ModeColumn('packages', '包数', number: true),
    _ModeColumn('quantity', '数量', number: true),
    _ModeColumn('weight', '重量', number: true),
    _ModeColumn('remark', '备注'),
  ],
  MainMode.quality => const [
    _ModeColumn('materialType', '材料类型'),
    _ModeColumn('installNumber', '安装编号'),
    _ModeColumn('model', '型号'),
    _ModeColumn('qualityType', '质量类型'),
    _ModeColumn('description', '反馈说明'),
    _ModeColumn('photoUris', '附图'),
  ],
};

List<Map<String, String>> _decodeRowsForScope(
  String content,
  String buildingName,
  String scopeName,
) {
  final scoped = _readScopedData(content, buildingName);
  if (scoped.isEmpty) return [];
  return List<Map<String, String>>.from(scoped[scopeName] ?? const []);
}

String _encodeRowsForScope(
  String existingContent,
  String buildingName,
  String scopeName,
  List<Map<String, String>> rows,
) {
  final buildingScoped = _readBuildingScopedData(existingContent);
  final scoped = Map<String, List<Map<String, String>>>.from(
    buildingScoped[buildingName] ?? const {},
  );
  scoped[scopeName] = rows;
  buildingScoped[buildingName] = scoped;
  return _encodeBuildingScopedData(
    buildingScoped,
    currentBuildingName: buildingName,
  );
}

List<Map<String, String>> _decodeLoadingRowsForTrip(
  String content,
  String tripName, {
  String buildingName = '1号楼',
}) {
  final raw = _readLoadingBuildingContents(content)[buildingName] ?? content;
  final root = _readLoadingRoot(raw);
  if (root != null) {
    final trips = root['trips'];
    if (trips is List) {
      for (final trip in trips.whereType<Map>()) {
        if (trip['tripName']?.toString() != tripName) continue;
        return _loadingTripToRows(trip);
      }
    }
  }
  return _decodeRowsForScope(content, buildingName, tripName);
}

String _encodeLoadingRowsForTrip(
  String existingContent,
  String tripName,
  List<Map<String, String>> rows, {
  String buildingName = '1号楼',
}) {
  final buildingContents = _readLoadingBuildingContents(existingContent);
  final raw = buildingContents[buildingName] ?? '';
  final root =
      _readLoadingRoot(raw) ??
      <String, Object?>{
        'currentLoadingTripName': tripName,
        'loadingAluminumColumnMode': 'PACKAGE_NO',
        'loadingAluminumWeightMode': 'UNSELECTED',
        'loadingIronWeightMode': 'UNSELECTED',
        'trips': <Object?>[],
      };
  root['currentLoadingTripName'] = tripName;
  final trip = _rowsToLoadingTrip(tripName, rows);
  root['loadingAluminumColumnMode'] = trip['loadingAluminumColumnMode'];
  root['loadingAluminumWeightMode'] = trip['aluminumWeightMode'];
  root['loadingIronWeightMode'] = trip['ironWeightMode'];
  final trips = [
    for (final item in (root['trips'] as List? ?? const <Object?>[]))
      if (item is Map && item['tripName']?.toString() != tripName)
        Map<String, Object?>.from(item.cast<String, Object?>()),
    trip,
  ];
  root['trips'] = trips;
  buildingContents[buildingName] = jsonEncode(root);
  return _encodeLoadingBuildingContents(
    buildingContents,
    currentBuildingName: buildingName,
  );
}

List<String> _readLoadingTripNames(
  String content, {
  String buildingName = '1号楼',
}) {
  final raw = _readLoadingBuildingContents(content)[buildingName] ?? content;
  final root = _readLoadingRoot(raw);
  if (root != null) {
    final trips = root['trips'];
    if (trips is List) {
      final names = trips
          .whereType<Map>()
          .map((trip) => trip['tripName']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.isNotEmpty) return names;
    }
  }
  return _readScopedData(content, buildingName).keys.toList();
}

String _removeLoadingTrip(
  String content,
  String tripName, {
  String buildingName = '1号楼',
}) {
  final buildingContents = _readLoadingBuildingContents(content);
  final raw = buildingContents[buildingName] ?? '';
  final root = _readLoadingRoot(raw);
  if (root == null) {
    final buildingScoped = _readBuildingScopedData(content);
    final scoped = Map<String, List<Map<String, String>>>.from(
      buildingScoped[buildingName] ?? const {},
    )..remove(tripName);
    buildingScoped[buildingName] = scoped;
    return _encodeBuildingScopedData(
      buildingScoped,
      currentBuildingName: buildingName,
    );
  }
  root['trips'] = [
    for (final item in (root['trips'] as List? ?? const <Object?>[]))
      if (item is Map && item['tripName']?.toString() != tripName)
        Map<String, Object?>.from(item.cast<String, Object?>()),
  ];
  buildingContents[buildingName] = jsonEncode(root);
  return _encodeLoadingBuildingContents(
    buildingContents,
    currentBuildingName: buildingName,
  );
}

Map<String, Object?>? _readLoadingRoot(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map && decoded['trips'] is List) {
      return Map<String, Object?>.from(decoded.cast<String, Object?>());
    }
  } on FormatException {
    return null;
  }
  return null;
}

List<Map<String, String>> _loadingTripToRows(Map trip) {
  final meta = {
    ..._emptyLoadingRow(),
    '_type': 'vehicleInfo',
    'loadingAluminumColumnMode':
        trip['loadingAluminumColumnMode']?.toString() ?? 'PACKAGE_NO',
    'loadingAluminumWeightMode':
        trip['aluminumWeightMode']?.toString() ?? 'UNSELECTED',
    'loadingIronWeightMode': trip['ironWeightMode']?.toString() ?? 'UNSELECTED',
  };
  final vehicleInfo = trip['vehicleInfo'];
  if (vehicleInfo is Map) {
    for (final entry in vehicleInfo.entries) {
      meta['vehicle_${entry.key}'] = entry.value?.toString() ?? '';
    }
  }
  return [
    ..._readLoadingTripRows(trip['aluminumRows'], false),
    ..._readLoadingTripRows(trip['ironRows'], true),
    meta,
  ];
}

List<Map<String, String>> _readLoadingTripRows(Object? value, bool iron) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((row) {
    final material = row['materialName']?.toString() ?? '';
    return {
      '_type': iron ? 'iron' : 'aluminum',
      'material': material.isEmpty && iron ? '铁件' : material,
      'packages': row['packageOrCount']?.toString() ?? '',
      'quantity': row['areaOrWeight']?.toString() ?? '',
      'weight': row['weight']?.toString() ?? '',
      'remark': row['remark']?.toString() ?? '',
    };
  }).toList();
}

Map<String, Object?> _rowsToLoadingTrip(
  String tripName,
  List<Map<String, String>> rows,
) {
  final meta = rows.firstWhere(_isLoadingMetaRow, orElse: _emptyLoadingRow);
  final vehicleInfo = {
    for (final key in _emptyVehicleInfo().keys) key: meta['vehicle_$key'] ?? '',
  };
  return {
    'tripName': tripName,
    'loadingAluminumColumnMode':
        meta['loadingAluminumColumnMode'] ?? 'PACKAGE_NO',
    'aluminumWeightMode': meta['loadingAluminumWeightMode'] ?? 'UNSELECTED',
    'ironWeightMode': meta['loadingIronWeightMode'] ?? 'UNSELECTED',
    'aluminumRows': rows
        .where((row) => !_isLoadingMetaRow(row) && _isAluminumLoadingRow(row))
        .map(_loadingRowToTripRow)
        .toList(),
    'ironRows': rows
        .where((row) => !_isLoadingMetaRow(row) && _isIronLoadingRow(row))
        .map(_loadingRowToTripRow)
        .toList(),
    'vehicleInfo': vehicleInfo,
  };
}

Map<String, String> _loadingRowToTripRow(Map<String, String> row) => {
  'materialName': row['material'] ?? '',
  'packageOrCount': row['packages'] ?? '',
  'areaOrWeight': row['quantity'] ?? '',
  'weight': row['weight'] ?? '',
  'remark': row['remark'] ?? '',
};

Map<String, List<Map<String, String>>> _readScopedData(
  String content,
  String buildingName,
) {
  final buildingScoped = _readBuildingScopedData(content);
  return buildingScoped[buildingName] ?? const {};
}

Map<String, Map<String, List<Map<String, String>>>> _readBuildingScopedData(
  String content,
) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return {};
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, Object?> && decoded['buildings'] is List) {
      final wrapped = _buildingContentCodec.decode(trimmed);
      return {
        for (final entry in wrapped.contentsByBuilding.entries)
          entry.key: _readSingleBuildingScopedData(entry.value),
      };
    }
    if (decoded is Map) {
      final firstValue = decoded.values.firstOrNull;
      if (firstValue is Map) {
        final result = <String, Map<String, List<Map<String, String>>>>{};
        decoded.forEach((buildingKey, scopeValue) {
          if (scopeValue is Map) {
            result[buildingKey.toString()] = scopeValue.map(
              (scopeKey, rows) => MapEntry(
                scopeKey.toString(),
                rows is List ? _readJsonRows(rows) : <Map<String, String>>[],
              ),
            );
          }
        });
        if (result.isNotEmpty) return result;
      }
    }
  } on FormatException {
    return _readSingleBuildingFallback(trimmed);
  }
  return _readSingleBuildingFallback(trimmed);
}

Map<String, Map<String, List<Map<String, String>>>> _readSingleBuildingFallback(
  String content,
) {
  return {'1号楼': _readSingleBuildingScopedData(content)};
}

Map<String, List<Map<String, String>>> _readSingleBuildingScopedData(
  String content,
) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return {};
  if (trimmed.contains('#PACKAGE=')) return _readAndroidPackageBlocks(trimmed);
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      return {'第1包': _readJsonRows(decoded)};
    }
    if (decoded is Map) {
      final firstValue = decoded.values.firstOrNull;
      if (firstValue is List) {
        return decoded.map(
          (key, value) => MapEntry(
            key.toString(),
            value is List ? _readJsonRows(value) : <Map<String, String>>[],
          ),
        );
      }
      if (firstValue is Map) {
        final result = <String, List<Map<String, String>>>{};
        decoded.forEach((scopeKey, rows) {
          if (rows is List) {
            result[scopeKey.toString()] = _readJsonRows(rows);
          }
        });
        return result;
      }
    }
  } on FormatException {
    return {'第1包': _readTabRows(trimmed)};
  }
  return {};
}

String _encodeBuildingScopedData(
  Map<String, Map<String, List<Map<String, String>>>> scoped, {
  String currentBuildingName = '1号楼',
}) {
  return _buildingContentCodec.encode(
    BuildingScopedContent(
      currentBuildingName: currentBuildingName,
      contentsByBuilding: {
        for (final entry in scoped.entries) entry.key: jsonEncode(entry.value),
      },
    ),
  );
}

Map<String, String> _readLoadingBuildingContents(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return {};
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, Object?> && decoded['buildings'] is List) {
      return _buildingContentCodec.decode(trimmed).contentsByBuilding;
    }
  } on FormatException {
    return {'1号楼': trimmed};
  }
  return {'1号楼': trimmed};
}

String _encodeLoadingBuildingContents(
  Map<String, String> contents, {
  String currentBuildingName = '1号楼',
}) {
  return _buildingContentCodec.encode(
    BuildingScopedContent(
      currentBuildingName: currentBuildingName,
      contentsByBuilding: contents,
    ),
  );
}

class _ProjectContents {
  const _ProjectContents({
    required this.standard,
    required this.fast,
    required this.loading,
    required this.quality,
  });

  final String standard;
  final String fast;
  final String loading;
  final String quality;
}

_ProjectContents _emptyProjectContents(
  List<String> buildingNames,
  String currentBuildingName,
) {
  final names = buildingNames.isEmpty ? <String>['1号楼'] : buildingNames;
  return _ProjectContents(
    standard: _encodeBuildingScopedData({
      for (final name in names) name: {'第1包': <Map<String, String>>[]},
    }, currentBuildingName: currentBuildingName),
    fast: _encodeBuildingScopedData({
      for (final name in names) name: {'第1包': <Map<String, String>>[]},
    }, currentBuildingName: currentBuildingName),
    loading: _encodeLoadingBuildingContents({
      for (final name in names) name: _emptyLoadingRootJson(),
    }, currentBuildingName: currentBuildingName),
    quality: _encodeBuildingScopedData({
      for (final name in names) name: {'铝模1层': <Map<String, String>>[]},
    }, currentBuildingName: currentBuildingName),
  );
}

ProjectEntity _ensureBuildingContent(
  ProjectEntity project,
  String buildingName,
) {
  final standard = _readBuildingScopedData(project.standardContent);
  standard.putIfAbsent(buildingName, () => {'第1包': <Map<String, String>>[]});
  final fast = _readBuildingScopedData(project.fastContent);
  fast.putIfAbsent(buildingName, () => {'第1包': <Map<String, String>>[]});
  final loading = _readLoadingBuildingContents(project.loadingContent);
  loading.putIfAbsent(buildingName, _emptyLoadingRootJson);
  final quality = _readBuildingScopedData(project.qualityContent);
  quality.putIfAbsent(buildingName, () => {'铝模1层': <Map<String, String>>[]});
  return project.copyWith(
    standardContent: _encodeBuildingScopedData(
      standard,
      currentBuildingName: buildingName,
    ),
    fastContent: _encodeBuildingScopedData(
      fast,
      currentBuildingName: buildingName,
    ),
    loadingContent: _encodeLoadingBuildingContents(
      loading,
      currentBuildingName: buildingName,
    ),
    qualityContent: _encodeBuildingScopedData(
      quality,
      currentBuildingName: buildingName,
    ),
  );
}

String _emptyLoadingRootJson() {
  return jsonEncode({
    'currentLoadingTripName': '第1车',
    'loadingAluminumColumnMode': 'PACKAGE_NO',
    'loadingAluminumWeightMode': 'UNSELECTED',
    'loadingIronWeightMode': 'UNSELECTED',
    'trips': [_rowsToLoadingTrip('第1车', const <Map<String, String>>[])],
  });
}

Map<String, List<Map<String, String>>> _readAndroidPackageBlocks(
  String content,
) {
  final result = <String, List<Map<String, String>>>{};
  var packageName = '';
  var inRows = false;
  for (final line in content.replaceAll('\r\n', '\n').split('\n')) {
    if (line.startsWith('#PACKAGE=')) {
      packageName = line.replaceFirst('#PACKAGE=', '').trim();
      result.putIfAbsent(packageName, () => []);
      inRows = false;
    } else if (line == '#ROWS') {
      inRows = true;
    } else if (line == '#CURRENT_ROW' || line == '#END_PACKAGE') {
      inRows = false;
    } else if (inRows && packageName.isNotEmpty && line.trim().isNotEmpty) {
      result[packageName]!.add(_tabLineToStandardRow(line));
    }
  }
  return result;
}

List<Map<String, String>> _readJsonRows(List rows) {
  return rows
      .whereType<Map>()
      .map(
        (item) => item.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        ),
      )
      .toList();
}

List<Map<String, String>> _readTabRows(String content) {
  return content
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .map(_tabLineToStandardRow)
      .toList();
}

Map<String, String> _tabLineToStandardRow(String line) {
  final parts = line.split('\t');
  return {
    'installNumber': parts.elementAtOrNull(0).orEmpty(),
    'model': parts.elementAtOrNull(1).orEmpty(),
    'quantity': parts.elementAtOrNull(2).orEmpty(),
  };
}

const _qualityMaterialTypes = [
  '铝模板',
  '钢模板',
  '背楞',
  '吊架',
  '单支撑',
  '销钉',
  '销片',
  '销钉销片',
  '四方垫片',
  '对拉螺母',
  '对拉螺杆',
  '斜撑',
  '圆管',
  '调节底座',
  '码仔',
  'K板螺丝',
  'T字螺杆',
  '放线盒',
  '上料箱',
  '泵管盒',
  '方通扣',
  '回型钩',
  '凳子',
  '拉片小斜撑',
  '背楞接头',
  '铁钩铁锤',
  '其他铁件',
];

const _qualityTypes = [
  '材料变形',
  '材料脱焊',
  '材料缺失',
  '尺寸错误',
  '材料增补',
  '设计错误',
  '深化错误',
  '生产错误',
];

String _buildQualityFeedbackDesc({
  required String materialType,
  required String qualityType,
}) {
  final material = materialType.isEmpty ? '材料' : materialType;
  return switch (qualityType) {
    '材料变形' => '材料施工中变形，影响成型质量，需更换。',
    '材料脱焊' => '材料施工中脱焊，影响成型质量，需更换。',
    '材料缺失' => '材料拆包未找到，影响拼装进度，需补发。',
    '尺寸错误' => '材料实际尺寸与图纸不符，影响拼装进度，需补发。',
    '材料增补' => '材料数量不满足现场施工需求，“$material”根据现场施工统计需增加***。',
    '设计错误' => '材料设计错误，影响拼装进度，需补发。',
    '深化错误' => '深化错误，影响拼装进度，需补发。',
    '生产错误' => '材料生产错误，影响拼装进度，需补发。',
    _ => '',
  };
}

Map<String, String> _emptyStandardRow() => {
  'installNumber': '',
  'model': '',
  'quantity': '',
};
Map<String, String> _emptyFastRow() => {
  'width': '',
  'model': '',
  'length': '',
  'quantity': '',
};
Map<String, String> _emptyLoadingRow() => {
  'material': '',
  'packages': '',
  'quantity': '',
  'weight': '',
  'remark': '',
};
Map<String, String> _emptyQualityRow() => {
  'materialType': '',
  'installNumber': '',
  'model': '',
  'qualityType': '',
  'description': '',
  'photoUris': '',
};
Map<String, String> _emptyVehicleInfo() => {
  'grossWeight': '',
  'tareWeight': '',
  'middleAluminumWeight': '',
  'middleIronWeight': '',
  'woodEstimate': '',
  'vehiclePlateNumber': '',
  'loadingDate': '',
};

String _displayCellText(Map<String, String> row, String key) {
  if (key == 'photoUris') {
    final count = row[key]
        .orEmpty()
        .split('|')
        .where((uri) => uri.trim().isNotEmpty)
        .length;
    return count == 0 ? '' : '$count张';
  }
  return row[key].orEmpty();
}

bool _isEmptyRow(Map<String, String> row) => row.entries
    .where(
      (entry) =>
          !entry.key.startsWith('_') && !entry.key.startsWith('vehicle_'),
    )
    .every((entry) => entry.value.trim().isEmpty);
bool _isLoadingMetaRow(Map<String, String> row) =>
    row['_type'] == 'vehicleInfo';
bool _isAluminumLoadingRow(Map<String, String> row) {
  if (row['_type'] == 'aluminum') return true;
  if (row['_type'] == 'iron' || _isEmptyRow(row)) return false;
  final material = row['material']?.trim() ?? '';
  return material.contains('铝') ||
      material == 'SP' ||
      material == '包数' ||
      material == '重量';
}

bool _isIronLoadingRow(Map<String, String> row) {
  if (row['_type'] == 'iron') return true;
  if (row['_type'] == 'aluminum') return false;
  final material = row['material']?.trim() ?? '';
  return material.contains('铁') ||
      material.isNotEmpty && !_isAluminumLoadingRow(row);
}

const _installNoWarning = '安装编号仅支持数字和 A/B/C/D/E/F/W/S/DM/LT/P/-';
const _fastInputWarning = '警告！系统检测到错误输入，请检查输入数据是否有误！';
const _installNoTokens = {
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'K',
  'W',
  'S',
  'DM',
  'LT',
  'P',
  '-',
  '/',
};
const _fastModelTokens = {'E', 'F', 'SP'};
const _fastPresetNumericTokens = {
  '50',
  '45',
  '95',
  '65',
  '85',
  '100',
  '200',
  '300',
  '400',
  '500',
  '700',
  '900',
  '1100',
  '2700',
  '2745',
};
const _modelTokensWithSpacing = {
  'W',
  'WE',
  'WED',
  'BQ',
  'B',
  'BS',
  'BC',
  'BP',
  'S',
  'SC',
  'M',
  'MB',
  'SP',
  'LT',
  'JT',
  'GT',
  'DM',
  'IC',
  'ICA',
};

bool _numericTokenAllowed(String token) =>
    token == '.' || double.tryParse(token) != null;
bool _installTokenAllowed(String token, {bool allowSpace = false}) {
  if (allowSpace && token == '空格') return true;
  if (int.tryParse(token) != null) return true;
  return _installNoTokens.contains(token);
}

String? _quantityWarningFor(String token) =>
    RegExp(r'[A-Za-z]').hasMatch(token) ? '数量内不能输入字母' : null;
bool _fastNumberWithin(String value, num max) {
  if (value.isEmpty || value == '.') return true;
  final number = double.tryParse(value);
  return number == null || number <= max;
}

bool _fastQuantityWithin(String value) {
  final number = int.tryParse(value);
  return number == null || number <= 500;
}

int _sum(List<Map<String, String>> rows, String key) =>
    rows.fold(0, (sum, row) {
      final value = int.tryParse(row[key]?.trim() ?? '');
      return sum + (value ?? 1);
    });
double _sumDouble(List<Map<String, String>> rows, String key) =>
    rows.fold(0, (sum, row) => sum + _parseDouble(row[key]));
double _fastArea(List<Map<String, String>> rows) =>
    rows.fold(0, (sum, row) => sum + _fastUnitArea(row) * _fastQuantity(row));
int _fastQuantity(Map<String, String> row) =>
    int.tryParse(row['quantity']?.trim() ?? '') ?? 1;
double _fastUnitArea(Map<String, String> row) {
  final model = row['model'].orEmpty().trim().toUpperCase();
  if (model.contains('SP')) return 0.02;
  if (model.contains('E')) return 0;
  return _parseDouble(row['width']) * _parseDouble(row['length']) / 1000000;
}

double _fastAngleLengthMeter(List<Map<String, String>> rows) =>
    rows.fold(0, (sum, row) {
      if (row['model'].orEmpty().trim().toUpperCase() != 'E') return sum;
      return sum + _parseDouble(row['length']) * _fastQuantity(row) / 1000;
    });
String _formatFastSummaryNumber(double value) {
  if ((value - value.round()).abs() < 0.000001) return value.round().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _todayText() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

double _parseDouble(String? value) => double.tryParse(value?.trim() ?? '') ?? 0;

double _loadingIronWeighbridgeWeightFromInfo(Map<String, String> info) {
  final gross = _parseDouble(info['grossWeight']);
  final tare = _parseDouble(info['tareWeight']);
  final middleAluminum = _parseDouble(info['middleAluminumWeight']);
  final middleIron = _parseDouble(info['middleIronWeight']);
  if (middleAluminum > 0) return gross - middleAluminum;
  if (middleIron > 0) return middleIron - tare;
  return 0;
}

String _escapeHtml(String? value) {
  return (value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _formatNumber(double value) {
  if (value == 0) return '0';
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
}

BoxDecoration _groupDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(22),
  border: Border.all(color: _legacyGroupBorder),
);
BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: _legacyCardBorder),
);

class _ProjectDeleteButton extends StatelessWidget {
  const _ProjectDeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFC43D3D),
          backgroundColor: const Color(0xFFFFEAEA),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFFFCACA)),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        child: const Text('删除'),
      ),
    );
  }
}

extension on String? {
  String orEmpty() => this ?? '';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
