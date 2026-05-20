import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_dialog_chrome.dart';
import '../../data/models/api/server_models.dart';
import '../../data/models/api/sub_display_models.dart';
import '../../data/models/project_entity.dart';
import '../../data/serializers/building_scoped_content_codec.dart';
import '../../core/storage/preferences.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/server_repository.dart';
import '../../data/repositories/version_repository.dart';

enum MainMode {
  standard('型号统计', '包号'),
  fast('返厂统计', '包号'),
  loading('返厂装车', '车次'),
  quality('质量反馈', '铝模层数');

  const MainMode(this.label, this.scopeLabel);
  final String label;
  final String scopeLabel;
}

enum StandardField { installNumber, model, quantity }

enum FastField { width, model, length, quantity }

enum LoadingField { material, packages, quantity, weight, remark }

enum QualityField {
  materialType,
  installNumber,
  model,
  qualityType,
  description,
  photoUris,
}

const _buildingContentCodec = BuildingScopedContentCodec();

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  static const _exportChannel = MethodChannel(
    'com.example.datarecorder/export_share',
  );
  static const _photoChannel = MethodChannel(
    'com.example.datarecorder/quality_photo',
  );
  static const _updateChannel = MethodChannel(
    'com.example.datarecorder/update',
  );
  static const _fastVoiceChannel = MethodChannel(
    'com.example.datarecorder/fast_voice',
  );

  final _repository = const ProjectRepository();
  final _preferences = AppPreferences();
  late final _serverRepository = ServerRepository(preferences: _preferences);
  final _versionRepository = VersionRepository();
  final List<ProjectEntity> _projects = [];
  ProjectEntity? _project;
  MainMode _mode = MainMode.standard;
  String _packageName = '第1包';
  String _tripName = '第1车';
  String _qualityFloor = '铝模1层';
  StandardField _standardField = StandardField.installNumber;
  FastField _fastField = FastField.width;
  LoadingField _loadingField = LoadingField.material;
  bool _loadingAluminumUsePackageCount = false;
  String _loadingAluminumWeightMode = 'UNSELECTED';
  String _loadingIronWeightMode = 'UNSELECTED';
  QualityField _qualityField = QualityField.installNumber;
  int? _editingStandardRowIndex;
  int? _editingFastRowIndex;
  int? _editingLoadingRowIndex;
  int? _editingQualityRowIndex;
  bool _pendingReplaceStandardEditing = false;
  bool _pendingReplaceFastEditing = false;
  Map<String, String> _standardCurrent = _emptyStandardRow();
  Map<String, String> _fastCurrent = _emptyFastRow();
  Map<String, String> _loadingCurrent = _emptyLoadingRow();
  Map<String, String> _qualityCurrent = _emptyQualityRow();
  Map<String, String> _vehicleInfo = _emptyVehicleInfo();
  String _subDisplayCode = '';
  String _username = '';
  bool? _subDisplayConnected;
  int _subDisplaySessionCount = 0;
  Timer? _historyBackupTimer;
  Timer? _subDisplayStatusTimer;
  String? _lastSubDisplayPayload;
  bool _loading = true;
  bool _fastVoicePressed = false;
  bool _fastVoiceStarting = false;
  bool _fastVoiceListening = false;
  bool _fastVoiceWaitingResult = false;
  bool _fastVoiceDialogVisible = false;
  OverlayEntry? _fastVoiceDialogEntry;
  DateTime? _fastVoicePressStartedAt;
  Timer? _fastVoiceTimeoutTimer;
  int _fastVoiceHoldGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProject();
    _historyBackupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _saveCurrentHistory(showToast: false),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveCurrentDraft();
    _historyBackupTimer?.cancel();
    _subDisplayStatusTimer?.cancel();
    _fastVoiceTimeoutTimer?.cancel();
    unawaited(_fastVoiceChannel.invokeMethod<void>('cancelListening'));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveCurrentDraft());
    }
  }

  Future<void> _saveCurrentDraft() async {
    await _saveMainState();
    if (_project == null) return;
    if (_hasEditingRow) {
      await _saveEditedCurrentRow();
      return;
    }
    if (_isEmptyRow(_currentRow)) return;
    final rows = _rows;
    if (rows.any((row) => identical(row, _currentRow))) return;
    await _saveRows([...rows, Map<String, String>.from(_currentRow)]);
    if (mounted) _clearCurrentRow();
  }

  void _syncSubDisplayPolling() {
    final shouldPoll = _mode == MainMode.fast && _subDisplayCode.isNotEmpty;
    if (!shouldPoll) {
      _subDisplayStatusTimer?.cancel();
      _subDisplayStatusTimer = null;
      return;
    }
    if (_subDisplayStatusTimer?.isActive == true) return;
    _subDisplayStatusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshSubDisplayStatus(),
    );
  }

  Future<void> _loadProject() async {
    try {
      final projects = await _repository.getAllProjects();
      ProjectEntity project;
      if (projects.isEmpty) {
        project = await _createDefaultProject();
        projects.add(project);
      } else {
        final lastProjectId = await _preferences.getLastProjectId();
        project = projects.firstWhere(
          (item) => item.id == lastProjectId,
          orElse: () => projects.first,
        );
      }
      final mainState = await _preferences.getMainState();
      final username = await _preferences.getUsername();
      final savedMode = MainMode.values.firstWhere(
        (mode) => mode.name == mainState['flutter_main_mode'],
        orElse: () => _mode,
      );
      if (!mounted) return;
      setState(() {
        _projects
          ..clear()
          ..addAll(projects);
        _project = project;
        _username = username;
        _mode = savedMode;
        _packageName = (mainState['flutter_package_name'] ?? '').ifBlank(
          _packageName,
        );
        _tripName = (mainState['flutter_trip_name'] ?? '').ifBlank(_tripName);
        _qualityFloor = (mainState['flutter_quality_floor'] ?? '').ifBlank(
          _qualityFloor,
        );
        _subDisplayCode = (mainState['flutter_sub_display_code'] ?? '').ifBlank(
          _subDisplayCode,
        );
        _loading = false;
      });
      _syncSubDisplayPolling();
      if (_mode == MainMode.fast && _subDisplayCode.isNotEmpty) {
        _refreshSubDisplayStatus();
      }
      unawaited(_checkLatestNoticeAndShowOnce());
    } catch (_) {
      const buildingName = '1号楼';
      final contents = _emptyProjectContents(const [
        buildingName,
      ], buildingName);
      final username = await _preferences.getUsername();
      if (!mounted) return;
      setState(() {
        _projects.clear();
        _project = ProjectEntity(
          name: '默认项目',
          buildingName: buildingName,
          standardContent: contents.standard,
          fastContent: contents.fast,
          loadingContent: contents.loading,
          qualityContent: contents.quality,
        );
        _username = username;
        _loading = false;
      });
      _showNotReady('本地数据加载失败，已进入默认项目');
    }
  }

  Future<void> _checkLatestNoticeAndShowOnce() async {
    try {
      final response = await _serverRepository.getLatestNotice();
      final notice = response.data;
      if (!mounted || !response.isSuccess || notice == null) return;
      if (notice.noticeId == null || notice.displayKey.trim().isEmpty) return;
      final shownKey = await _preferences.getShownNoticeKey();
      if (!mounted || shownKey == notice.displayKey) return;
      await _preferences.saveShownNoticeKey(notice.displayKey);
      if (!mounted) return;
      await _showServerNoticeDialog(notice);
    } catch (_) {
      return;
    }
  }

  Future<void> _showServerNoticeDialog(AppNoticeInfo notice) {
    final title = notice.noticeTitle.ifBlank('系统公告');
    final type = notice.noticeType == '1' ? '通知' : '公告';
    final time = notice.updateTime.ifBlank(notice.createTime.ifBlank('刚刚发布'));
    return showAppCardDialog<void>(
      context: context,
      title: title,
      subtitle: '服务器$type · $time',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF08111F),
                  Color(0xFF18295C),
                  Color(0xFF4B24A8),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x6600E5FF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  '来自服务器后台的最新公告',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFD9ECFF), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Color(0xFFF5F8FF)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFDDE7FF)),
                ),
                child: Text.rich(
                  TextSpan(children: _noticeSpans(notice.noticeContent)),
                  style: const TextStyle(
                    color: Color(0xFF2F2A3D),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppDialogActionButton(
            text: '我知道了',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _noticeSpans(String content) {
    final safe = content.ifBlank('暂无公告内容');
    final spans = <InlineSpan>[];
    final exp = RegExp(
      r'<\s*(br|p)\s*/?\s*>|<\s*/\s*p\s*>|<[^>]+>|[^<]+',
      caseSensitive: false,
    );
    for (final match in exp.allMatches(safe)) {
      final token = match.group(0) ?? '';
      final lower = token.toLowerCase();
      if (lower.startsWith('<br') ||
          lower.startsWith('<p') ||
          lower.startsWith('</p')) {
        if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));
      } else if (!token.startsWith('<')) {
        spans.add(TextSpan(text: _decodeHtmlText(token)));
      }
    }
    if (spans.isEmpty) {
      return [
        TextSpan(
          text: _decodeHtmlText(safe.replaceAll(RegExp(r'<[^>]+>'), '')),
        ),
      ];
    }
    return spans;
  }

  String _decodeHtmlText(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  String get _scopeName => switch (_mode) {
    MainMode.loading => _tripName,
    MainMode.quality => _qualityFloor,
    _ => _packageName,
  };

  List<Map<String, String>> get _rows {
    if (_mode == MainMode.loading) {
      return _decodeLoadingRowsForTrip(
        _contentForMode(_mode),
        _tripName,
        buildingName: _currentBuildingName,
      ).where((row) => !_isLoadingMetaRow(row)).toList();
    }
    return _decodeRowsForScope(
      _contentForMode(_mode),
      _currentBuildingName,
      _scopeName,
    );
  }

  String get _currentBuildingName {
    final name = _project?.buildingName ?? '';
    return name.isEmpty ? '1号楼' : name;
  }

  String get _avatarText {
    final name = _username.trim();
    if (name.isEmpty) return '用';
    return name.characters.first.toUpperCase();
  }

  String _topButtonLabel(String value) {
    final text = value.trim();
    if (text.characters.length <= 6) return text;
    return '${text.characters.take(6).join()}…';
  }

  String _contentForMode(MainMode mode) {
    final project = _project;
    if (project == null) return '[]';
    return switch (mode) {
      MainMode.standard => project.standardContent,
      MainMode.fast => project.fastContent,
      MainMode.loading => project.loadingContent,
      MainMode.quality => project.qualityContent,
    };
  }

  Map<String, String> get _currentRow => switch (_mode) {
    MainMode.standard => _standardCurrent,
    MainMode.fast => _fastCurrent,
    MainMode.loading => _loadingCurrent,
    MainMode.quality => _qualityCurrent,
  };

  int? get _editingRowIndex => switch (_mode) {
    MainMode.standard => _editingStandardRowIndex,
    MainMode.fast => _editingFastRowIndex,
    MainMode.loading => _editingLoadingRowIndex,
    MainMode.quality => _editingQualityRowIndex,
  };

  bool get _hasEditingRow => _editingRowIndex != null;

  Future<void> _saveMainState() async {
    await _preferences.saveMainState(
      mode: _mode.name,
      packageName: _packageName,
      tripName: _tripName,
      qualityFloor: _qualityFloor,
      subDisplayCode: _subDisplayCode,
    );
    final id = _project?.id;
    if (id != null) await _preferences.saveLastProjectId(id);
  }

  Future<void> _refreshSubDisplayStatus({bool showError = false}) async {
    if (_subDisplayCode.isEmpty) return;
    final wasConnected = _subDisplayConnected == true;
    try {
      final status = await _serverRepository.getSubDisplayStatus(
        _subDisplayCode,
      );
      if (!mounted) return;
      if (!status.isSuccess) {
        final message = status.displayMessage;
        if (message.contains('失效') ||
            message.contains('过期') ||
            message.contains('不存在')) {
          _clearSubDisplayCode(message);
        }
        return;
      }
      final connected = status.data?.connected == true;
      setState(() {
        _subDisplayConnected = connected;
        _subDisplaySessionCount = status.data?.sessionCount ?? 0;
      });
      if (!wasConnected && connected) {
        unawaited(_pushFastSnapshotToSubDisplay(force: true));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _subDisplayConnected = false;
        _subDisplaySessionCount = 0;
      });
      if (showError) _showNotReady('连接状态刷新失败，请检查网络');
    }
  }

  void _clearSubDisplayCode([String? message]) {
    _subDisplayStatusTimer?.cancel();
    _subDisplayStatusTimer = null;
    setState(() {
      _subDisplayCode = '';
      _subDisplayConnected = false;
      _subDisplaySessionCount = 0;
      _lastSubDisplayPayload = null;
    });
    unawaited(_saveMainState());
    if (message != null && message.isNotEmpty) _showNotReady(message);
  }

  String get _subDisplayStatusText {
    if (_subDisplayCode.isEmpty) return '未生成连接码';
    if (_subDisplayConnected == true) return '已连接';
    return '未连接';
  }

  String _subDisplayButtonText() {
    if (_subDisplayCode.isEmpty) return '生成连接码';
    if (_subDisplayConnected == true) return '已连接$_subDisplaySessionCount';
    if (_subDisplayConnected == false) return '未连接';
    return '查看连接码';
  }

  Future<void> _saveRows(List<Map<String, String>> rows) async {
    final project = _project;
    if (project == null) return;
    final rowsToSave = _mode == MainMode.loading
        ? _withLoadingVehicleInfo(rows)
        : rows;
    final content = _mode == MainMode.loading
        ? _encodeLoadingRowsForTrip(
            _contentForMode(_mode),
            _tripName,
            rowsToSave,
            buildingName: _currentBuildingName,
          )
        : _encodeRowsForScope(
            _contentForMode(_mode),
            _currentBuildingName,
            _scopeName,
            rowsToSave,
          );
    final updated = switch (_mode) {
      MainMode.standard => project.copyWith(standardContent: content),
      MainMode.fast => project.copyWith(fastContent: content),
      MainMode.loading => project.copyWith(loadingContent: content),
      MainMode.quality => project.copyWith(qualityContent: content),
    };
    await _updateProject(updated);
    if (_mode == MainMode.fast) unawaited(_pushFastSnapshotToSubDisplay());
  }

  Future<void> _updateProject(ProjectEntity updated) async {
    await _repository.update(updated);
    if (!mounted) return;
    setState(() {
      _project = updated;
      final index = _projects.indexWhere((item) => item.id == updated.id);
      if (index >= 0) _projects[index] = updated;
    });
    await _saveMainState();
  }

  Future<void> _finishCurrentRow() async {
    final current = Map<String, String>.from(_currentRow);
    if (_hasEditingRow) {
      await _saveEditedCurrentRow();
      if (mounted) _clearCurrentRow();
      return;
    }
    if (_isEmptyRow(current)) {
      _resetCurrentField();
      setState(() {});
      return;
    }
    final rows = _rows..add(current);
    _clearCurrentRow();
    await _saveRows(rows);
  }

  Future<void> _saveEditedCurrentRow() async {
    final index = _editingRowIndex;
    if (index == null) return;
    final rows = _rows;
    if (index < 0 || index >= rows.length) return;
    rows[index] = Map<String, String>.from(_currentRow);
    await _saveRows(rows);
  }

  Future<void> _saveQualityEditedRow(Map<String, String> row) async {
    final index = _editingQualityRowIndex;
    if (index == null) return;
    final rows = _rows;
    if (index < 0 || index >= rows.length) return;
    rows[index] = Map<String, String>.from(row);
    await _saveRows(rows);
  }

  Future<void> _deleteDisplayRow(int? index) async {
    if (index == null) {
      if (_isEmptyRow(_currentRow)) return;
      final confirmed = await _confirmDanger(
        title: '确认删除',
        message: '确定删除这一行吗？删除后无法恢复。',
        confirmText: '删除',
      );
      if (!confirmed) return;
      _clearCurrentRow();
      return;
    }
    await _deleteRow(index);
  }

  Future<void> _deleteRow(int index) async {
    final confirmed = await _confirmDanger(
      title: '确认删除',
      message: '确定删除这一行吗？删除后无法恢复。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    final rows = _rows..removeAt(index);
    setState(() {
      switch (_mode) {
        case MainMode.standard:
          if (_editingStandardRowIndex == index) {
            _standardCurrent = _emptyStandardRow();
            _standardField = StandardField.installNumber;
            _editingStandardRowIndex = null;
          } else if ((_editingStandardRowIndex ?? -1) > index) {
            _editingStandardRowIndex = _editingStandardRowIndex! - 1;
          }
        case MainMode.fast:
          if (_editingFastRowIndex == index) {
            _fastCurrent = _emptyFastRow();
            _fastField = FastField.width;
            _editingFastRowIndex = null;
          } else if ((_editingFastRowIndex ?? -1) > index) {
            _editingFastRowIndex = _editingFastRowIndex! - 1;
          }
          _lastSubDisplayPayload = null;
        case MainMode.loading:
          if (_editingLoadingRowIndex == index) {
            _loadingCurrent = _emptyLoadingRow();
            _loadingField = LoadingField.material;
            _editingLoadingRowIndex = null;
          } else if ((_editingLoadingRowIndex ?? -1) > index) {
            _editingLoadingRowIndex = _editingLoadingRowIndex! - 1;
          }
        case MainMode.quality:
          if (_editingQualityRowIndex == index) {
            _qualityCurrent = _emptyQualityRow();
            _qualityField = QualityField.installNumber;
            _editingQualityRowIndex = null;
          } else if ((_editingQualityRowIndex ?? -1) > index) {
            _editingQualityRowIndex = _editingQualityRowIndex! - 1;
          }
      }
    });
    await _saveRows(rows);
  }

  List<Map<String, String>> _withLoadingVehicleInfo(
    List<Map<String, String>> rows,
  ) {
    final info = _vehicleInfoForCurrentTrip();
    return [
      ...rows.where((row) => !_isLoadingMetaRow(row)),
      {
        ..._emptyLoadingRow(),
        '_type': 'vehicleInfo',
        'loadingAluminumColumnMode': _loadingAluminumUsePackageCount
            ? 'COUNT'
            : 'PACKAGE_NO',
        'loadingAluminumWeightMode': _loadingAluminumWeightMode,
        'loadingIronWeightMode': _loadingIronWeightMode,
        ...info.map((key, value) => MapEntry('vehicle_$key', value)),
      },
    ];
  }

  Map<String, String> _loadingMetaForCurrentTrip() {
    final rows = _decodeLoadingRowsForTrip(
      _contentForMode(MainMode.loading),
      _tripName,
      buildingName: _currentBuildingName,
    );
    return rows.firstWhere(_isLoadingMetaRow, orElse: _emptyLoadingRow);
  }

  void _syncLoadingModesFromCurrentTrip() {
    final meta = _loadingMetaForCurrentTrip();
    _loadingAluminumUsePackageCount =
        meta['loadingAluminumColumnMode'] == 'COUNT';
    _loadingAluminumWeightMode = meta['loadingAluminumWeightMode']
        .orEmpty()
        .ifBlank('UNSELECTED');
    _loadingIronWeightMode = meta['loadingIronWeightMode'].orEmpty().ifBlank(
      'UNSELECTED',
    );
  }

  Map<String, String> _vehicleInfoForCurrentTrip() {
    final meta = _loadingMetaForCurrentTrip();
    return _emptyVehicleInfo().map((key, value) {
      return MapEntry(key, meta['vehicle_$key'] ?? _vehicleInfo[key] ?? value);
    });
  }

  String _loadingWeightHeader(bool aluminum) {
    final mode = aluminum ? _loadingAluminumWeightMode : _loadingIronWeightMode;
    return switch (mode) {
      'SINGLE_PACKAGE' => '单包重量',
      'WEIGHBRIDGE_TOTAL' => '过磅总重量',
      _ => '选择重量',
    };
  }

  Future<void> _showLoadingAluminumColumnModeDialog() async {
    final selected = await _showOptionDialog(
      title: '铝模列模式',
      subtitle: _loadingAluminumUsePackageCount ? '当前按包数录入' : '当前按包号录入',
      options: const ['包号', '包数'],
      current: _loadingAluminumUsePackageCount ? '包数' : '包号',
    );
    if (!mounted || selected == null) return;
    _setLoadingAluminumColumnMode(selected == '包数');
  }

  void _setLoadingAluminumColumnMode(bool usePackageCount) {
    final rows = _rows;
    setState(() {
      _loadingAluminumUsePackageCount = usePackageCount;
    });
    if (!usePackageCount) _resequenceLoadingAluminumPackages(rows);
    unawaited(_saveRows(rows));
  }

  Future<void> _showLoadingWeightModeDialog({required bool aluminum}) async {
    final selected = await _showOptionDialog(
      title: aluminum ? '铝模重量模式' : '铁件重量模式',
      subtitle: '选择重量列的录入方式',
      options: const ['单包重量', '过磅总重量'],
      current: _loadingWeightHeader(aluminum),
    );
    if (!mounted || selected == null) return;
    _setLoadingWeightMode(
      aluminum: aluminum,
      mode: selected == '过磅总重量' ? 'WEIGHBRIDGE_TOTAL' : 'SINGLE_PACKAGE',
    );
  }

  void _setLoadingWeightMode({required bool aluminum, required String mode}) {
    setState(() {
      if (aluminum) {
        _loadingAluminumWeightMode = mode;
      } else {
        _loadingIronWeightMode = mode;
      }
    });
    unawaited(_saveLoadingMetaOnly());
  }

  void _resequenceLoadingAluminumPackages(List<Map<String, String>> rows) {
    var packageNo = 1;
    for (final row in rows) {
      if (_isAluminumLoadingRow(row)) row['packages'] = '${packageNo++}';
    }
  }

  Future<void> _saveLoadingMetaOnly() async {
    final rows = _rows;
    await _saveRows(rows);
  }

  double _loadingAluminumWeighbridgeWeight() {
    return _loadingAluminumWeighbridgeWeightFromInfo(
      _vehicleInfoForCurrentTrip(),
    );
  }

  double _loadingAluminumWeighbridgeWeightFromInfo(Map<String, String> info) {
    final gross = _parseDouble(info['grossWeight']);
    final tare = _parseDouble(info['tareWeight']);
    final middleAluminum = _parseDouble(info['middleAluminumWeight']);
    final middleIron = _parseDouble(info['middleIronWeight']);
    if (middleAluminum > 0) return middleAluminum - tare;
    if (middleIron > 0) return gross - middleIron;
    return 0;
  }

  double _loadingIronWeighbridgeWeightFromInfo(Map<String, String> info) {
    final gross = _parseDouble(info['grossWeight']);
    final tare = _parseDouble(info['tareWeight']);
    final middleAluminum = _parseDouble(info['middleAluminumWeight']);
    final middleIron = _parseDouble(info['middleIronWeight']);
    if (middleAluminum > 0) return gross - middleAluminum;
    if (middleIron > 0) return middleIron - tare;
    return 0;
  }

  double _loadingAluminumSummaryWeight(List<Map<String, String>> rows) {
    if (_loadingAluminumWeightMode == 'WEIGHBRIDGE_TOTAL') {
      return _loadingAluminumWeighbridgeWeight();
    }
    return _sumDouble(rows.where(_isAluminumLoadingRow).toList(), 'weight');
  }

  bool _loadingWeightEditableForCurrentRow() {
    if (_loadingField != LoadingField.weight) return true;
    if (_isIronLoadingRow(_loadingCurrent)) {
      return _loadingIronWeightMode == 'SINGLE_PACKAGE';
    }
    return _loadingAluminumWeightMode == 'SINGLE_PACKAGE';
  }

  Future<void> _showAluminumMaterialDialog() async {
    final selected = await _showOptionDialog(
      title: '选择铝物料',
      subtitle: '点击后新增一条铝模装车记录',
      options: const ['铝模', 'SP', '铝箱'],
      current: _loadingCurrent['material'],
    );
    if (!mounted || selected == null) return;
    await _startLoadingMaterial(aluminum: true, material: selected);
  }

  Future<void> _showIronMaterialDialog() async {
    const materials = [
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
    final selected = await _showOptionDialog(
      title: '铁物料',
      subtitle: '点击物料后直接新增到当前装车记录',
      options: materials,
      current: _loadingCurrent['material'],
    );
    if (!mounted || selected == null) return;
    await _startLoadingMaterial(aluminum: false, material: selected);
  }

  Future<void> _startLoadingMaterial({
    required bool aluminum,
    required String material,
  }) async {
    final weightMode = aluminum
        ? _loadingAluminumWeightMode
        : _loadingIronWeightMode;
    if (weightMode == 'UNSELECTED') {
      final targetName = aluminum ? '铝模' : '铁件';
      _showNotReady('请先点击$targetName重量，选择单包重量或过磅总重量');
      return;
    }
    await _saveCurrentDraft();
    if (!mounted) return;
    final row = {
      ..._emptyLoadingRow(),
      '_type': aluminum ? 'aluminum' : 'iron',
      'material': material,
    };
    var field = LoadingField.packages;
    if (aluminum && !_loadingAluminumUsePackageCount) {
      row['packages'] = _nextLoadingPackageNo();
      field = LoadingField.quantity;
    }
    setState(() {
      _loadingCurrent = row;
      _loadingField = field;
    });
  }

  String _nextLoadingPackageNo() {
    final rows = _rows.where(_isAluminumLoadingRow).toList();
    if (_loadingAluminumUsePackageCount) return '';
    return (rows.length + 1).toString();
  }

  Future<void> _deductAluminumBoxWeight(int ironRowIndex) async {
    final rows = _rows;
    if (ironRowIndex < 0 || ironRowIndex >= rows.length) return;
    final ironRow = rows[ironRowIndex];
    if (!_isIronLoadingRow(ironRow) ||
        ironRow['material'].orEmpty().trim().isEmpty ||
        ironRow['weight'].orEmpty().trim().isEmpty) {
      _showNotReady('请先输入铁件名称和重量');
      return;
    }
    final controller = TextEditingController();
    final input = await showAppCardDialog<String>(
      context: context,
      title: '请输入铝箱重量',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '铝箱重量'),
          ),
          const SizedBox(height: 12),
          AppDialogActionRow(
            onCancel: () => Navigator.of(context).pop(),
            confirmText: '确定',
            onConfirm: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    final value = _parseDouble(input);
    if (input == null || value <= 0) return;
    final origin = _parseDouble(ironRow['weight']);
    rows[ironRowIndex] = {
      ...ironRow,
      'weight': _formatNumber(origin - value),
      'remark': '已扣除铝箱重量',
    };
    rows.add({
      ..._emptyLoadingRow(),
      '_type': 'aluminum',
      'material': '铝箱',
      'weight': _formatNumber(value),
    });
    setState(() {
      _editingLoadingRowIndex = ironRowIndex;
      _loadingCurrent = Map<String, String>.from(rows[ironRowIndex]);
      _loadingField = LoadingField.remark;
    });
    await _saveRows(rows);
  }

  void _appendToken(String token) {
    var saveQualityEdit = false;
    String? warning;
    setState(() {
      switch (_mode) {
        case MainMode.standard:
          warning = _appendStandardToken(token);
        case MainMode.fast:
          warning = _appendFastToken(token);
          _lastSubDisplayPayload = null;
        case MainMode.loading:
          warning = _appendLoadingToken(token);
        case MainMode.quality:
          if (_qualityField == QualityField.installNumber ||
              _qualityField == QualityField.model) {
            warning = _appendQualityToken(token);
            saveQualityEdit = warning == null;
          }
      }
    });
    if (warning != null) _showNotReady(warning!);
    if (saveQualityEdit) unawaited(_saveQualityEditedRow(_qualityCurrent));
  }

  void _backspace() {
    final saveQualityEdit =
        _mode == MainMode.quality && _editingQualityRowIndex != null;
    setState(() {
      if (_mode == MainMode.loading &&
          (_loadingField == LoadingField.material ||
              _loadingField == LoadingField.remark ||
              (_loadingField == LoadingField.weight &&
                  !_loadingWeightEditableForCurrentRow()))) {
        return;
      }
      final row = _currentRow;
      final key = _currentKey;
      final value = row[key] ?? '';
      if (value.isNotEmpty) row[key] = value.substring(0, value.length - 1);
      if (_mode == MainMode.fast) _lastSubDisplayPayload = null;
    });
    if (saveQualityEdit) unawaited(_saveQualityEditedRow(_qualityCurrent));
  }

  String get _currentKey => switch (_mode) {
    MainMode.standard => switch (_standardField) {
      StandardField.installNumber => 'installNumber',
      StandardField.model => 'model',
      StandardField.quantity => 'quantity',
    },
    MainMode.fast => switch (_fastField) {
      FastField.width => 'width',
      FastField.model => 'model',
      FastField.length => 'length',
      FastField.quantity => 'quantity',
    },
    MainMode.loading => _loadingField.name,
    MainMode.quality => _qualityField.name,
  };

  String? _appendStandardToken(String token) {
    final replace =
        _editingStandardRowIndex != null && _pendingReplaceStandardEditing;
    switch (_standardField) {
      case StandardField.installNumber:
        if (!_installTokenAllowed(token)) return _installNoWarning;
        _writeToMap(_standardCurrent, 'installNumber', token, replace: replace);
      case StandardField.model:
        _appendModelTokenToMap(
          _standardCurrent,
          'model',
          token,
          replace: replace,
        );
      case StandardField.quantity:
        if (int.tryParse(token) == null) return _quantityWarningFor(token);
        _writeToMap(_standardCurrent, 'quantity', token, replace: replace);
    }
    _pendingReplaceStandardEditing = false;
    return null;
  }

  String? _appendFastToken(String token) {
    final replace = _editingFastRowIndex != null && _pendingReplaceFastEditing;
    if (_fastModelTokens.contains(token)) {
      _fastCurrent['model'] = token;
      _fastField = FastField.model;
      _pendingReplaceFastEditing = false;
      return null;
    }
    if (!_numericTokenAllowed(token)) return null;
    final targetField = _fastField == FastField.model
        ? _resolveNextFastNumericField()
        : _fastField;
    if (targetField == FastField.model) return null;
    if (targetField == FastField.quantity && int.tryParse(token) == null) {
      return _quantityWarningFor(token);
    }
    final warning = _appendFastNumericToken(
      targetField,
      token,
      replace: replace,
    );
    if (warning == null || _fastPresetNumericTokens.contains(token)) {
      _fastField = targetField;
      _pendingReplaceFastEditing = false;
    }
    return warning;
  }

  String? _appendLoadingToken(String token) {
    switch (_loadingField) {
      case LoadingField.material:
      case LoadingField.remark:
        return null;
      case LoadingField.weight:
        if (!_loadingWeightEditableForCurrentRow()) return null;
        _appendToMap(_loadingCurrent, _loadingField.name, token);
      case LoadingField.packages:
      case LoadingField.quantity:
        _appendToMap(_loadingCurrent, _loadingField.name, token);
    }
    return null;
  }

  String? _appendQualityToken(String token) {
    final safeToken = token == '空格' ? ' ' : token;
    switch (_qualityField) {
      case QualityField.installNumber:
        if (_installTokenAllowed(token, allowSpace: true)) {
          _appendToMap(_qualityCurrent, 'installNumber', safeToken);
          return null;
        }
        return _installNoWarning;
      case QualityField.model:
        _appendModelTokenToMap(_qualityCurrent, 'model', token);
      case QualityField.materialType:
      case QualityField.qualityType:
      case QualityField.description:
      case QualityField.photoUris:
        return null;
    }
    return null;
  }

  FastField _resolveNextFastNumericField() {
    final model = _fastCurrent['model'].orEmpty().trim().toUpperCase();
    if (model == 'SP') return FastField.quantity;
    if (model == 'E' || model == 'F') return FastField.length;
    if (_fastCurrent['width'].orEmpty().trim().isEmpty) return FastField.width;
    if (_fastCurrent['length'].orEmpty().trim().isEmpty) {
      return FastField.length;
    }
    return FastField.quantity;
  }

  String? _appendFastNumericToken(
    FastField field,
    String token, {
    required bool replace,
  }) {
    final key = switch (field) {
      FastField.width => 'width',
      FastField.length => 'length',
      FastField.quantity => 'quantity',
      FastField.model => 'model',
    };
    if (field == FastField.quantity && int.tryParse(token) == null) {
      return _quantityWarningFor(token);
    }
    final current = replace ? '' : _fastCurrent[key].orEmpty();
    final candidate = '$current$token';
    final valid = switch (field) {
      FastField.width => _fastNumberWithin(candidate, 600),
      FastField.length => _fastNumberWithin(candidate, 4500),
      FastField.quantity => _fastQuantityWithin(candidate),
      FastField.model => true,
    };
    if (valid) {
      _fastCurrent[key] = candidate;
      return null;
    }
    if (_fastPresetNumericTokens.contains(token)) {
      _fastCurrent[key] = token;
    }
    return _fastInputWarning;
  }

  void _appendToMap(Map<String, String> row, String key, String token) {
    row[key] = '${row[key] ?? ''}$token';
  }

  void _writeToMap(
    Map<String, String> row,
    String key,
    String token, {
    required bool replace,
  }) {
    row[key] = replace ? token : '${row[key] ?? ''}$token';
  }

  void _appendModelTokenToMap(
    Map<String, String> row,
    String key,
    String token, {
    bool replace = false,
  }) {
    final safeToken = token == '空格' ? ' ' : token;
    if (!_modelTokensWithSpacing.contains(token)) {
      _writeToMap(row, key, safeToken, replace: replace);
      return;
    }
    final current = replace ? '' : row[key].orEmpty();
    final prefix = current.isEmpty || current.endsWith(' ') ? '' : ' ';
    row[key] = '$current$prefix$token ';
  }

  void _nextColumn() {
    setState(() {
      switch (_mode) {
        case MainMode.standard:
          _standardField = StandardField
              .values[(_standardField.index + 1) % StandardField.values.length];
        case MainMode.fast:
          if (_editingFastRowIndex != null) {
            _fastField = FastField
                .values[(_fastField.index + 1) % FastField.values.length];
            _pendingReplaceFastEditing = true;
          } else {
            _fastField = switch (_fastField) {
              FastField.width => FastField.length,
              FastField.model => FastField.length,
              FastField.length => FastField.quantity,
              FastField.quantity => FastField.width,
            };
          }
        case MainMode.loading:
          _loadingField = LoadingField
              .values[(_loadingField.index + 1) % LoadingField.values.length];
        case MainMode.quality:
          _qualityField = QualityField
              .values[(_qualityField.index + 1) % QualityField.values.length];
      }
    });
  }

  Future<void> _newLine() async {
    if (_mode == MainMode.loading) {
      await _moveLoadingToNextRow();
      return;
    }
    await _finishCurrentRow();
  }

  Future<void> _moveLoadingToNextRow() async {
    var rows = _rows;
    var currentIndex = _editingLoadingRowIndex;
    if (rows.isEmpty && _isEmptyRow(_loadingCurrent)) {
      _showNotReady('请先通过铝物料或铁物料新增数据');
      return;
    }

    if (currentIndex == null && !_isEmptyRow(_loadingCurrent)) {
      rows = [...rows, Map<String, String>.from(_loadingCurrent)];
      currentIndex = rows.length - 1;
      await _saveRows(rows);
    }

    final currentTypeIsIron =
        currentIndex != null && currentIndex >= 0 && currentIndex < rows.length
        ? _isIronLoadingRow(rows[currentIndex])
        : _isIronLoadingRow(_loadingCurrent);
    final sameTypeIndexes = <int>[
      for (var i = 0; i < rows.length; i++)
        if (currentTypeIsIron
            ? _isIronLoadingRow(rows[i])
            : _isAluminumLoadingRow(rows[i]))
          i,
    ];
    if (sameTypeIndexes.isEmpty) {
      _showNotReady('请先通过铝物料或铁物料新增数据');
      return;
    }

    final position = currentIndex == null
        ? -1
        : sameTypeIndexes.indexOf(currentIndex);
    if (position < 0) {
      final firstIndex = sameTypeIndexes.first;
      setState(() {
        _editingLoadingRowIndex = firstIndex;
        _loadingCurrent = Map<String, String>.from(rows[firstIndex]);
      });
      return;
    }

    if (position + 1 >= sameTypeIndexes.length) {
      _showNotReady('请通过铝物料或铁物料新增数据');
      return;
    }

    final nextIndex = sameTypeIndexes[position + 1];
    setState(() {
      _editingLoadingRowIndex = nextIndex;
      _loadingCurrent = Map<String, String>.from(rows[nextIndex]);
    });
  }

  void _resetCurrentField() {
    switch (_mode) {
      case MainMode.standard:
        _standardField = StandardField.installNumber;
        _editingStandardRowIndex = null;
        _pendingReplaceStandardEditing = false;
      case MainMode.fast:
        _fastField = FastField.width;
        _editingFastRowIndex = null;
        _pendingReplaceFastEditing = false;
      case MainMode.loading:
        _loadingField = LoadingField.material;
        _editingLoadingRowIndex = null;
      case MainMode.quality:
        _qualityField = QualityField.installNumber;
        _editingQualityRowIndex = null;
    }
  }

  void _clearCurrentRow() {
    setState(() {
      switch (_mode) {
        case MainMode.standard:
          _standardCurrent = _emptyStandardRow();
          _standardField = StandardField.installNumber;
          _editingStandardRowIndex = null;
          _pendingReplaceStandardEditing = false;
        case MainMode.fast:
          _fastCurrent = _emptyFastRow();
          _lastSubDisplayPayload = null;
          _fastField = FastField.width;
          _editingFastRowIndex = null;
          _pendingReplaceFastEditing = false;
        case MainMode.loading:
          _loadingCurrent = _emptyLoadingRow();
          _syncLoadingModesFromCurrentTrip();
          _vehicleInfo = _vehicleInfoForCurrentTrip();
          _loadingField = LoadingField.material;
          _editingLoadingRowIndex = null;
        case MainMode.quality:
          _qualityCurrent = _emptyQualityRow();
          _qualityField = QualityField.installNumber;
          _editingQualityRowIndex = null;
      }
    });
  }

  Future<T?> _showAnchoredMenu<T>({
    required BuildContext anchorContext,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) {
      return showAppMenuCardPopup<T>(
        context: context,
        title: title,
        subtitle: subtitle,
        children: children,
      );
    }
    final anchorOffset = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorRect = anchorOffset & anchorBox.size;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 90),
      pageBuilder: (dialogContext, _, _) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final popupWidth = (screenSize.width - 24).clamp(0.0, 320.0);
        final preferredLeft =
            anchorRect.left + (anchorRect.width - popupWidth) / 2;
        final left = preferredLeft.clamp(
          12.0,
          screenSize.width - popupWidth - 12.0,
        );
        const gap = 10.0;
        final maxHeight = (screenSize.height * 0.55).clamp(0.0, 390.0);
        final belowTop = anchorRect.bottom + gap;
        final aboveTop = anchorRect.top - gap - maxHeight;
        final hasBelowSpace = belowTop + maxHeight <= screenSize.height - 12;
        final top = hasBelowSpace
            ? belowTop
            : aboveTop.clamp(12.0, screenSize.height - maxHeight - 12.0);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              child: _AnchoredMenuCard(
                title: title,
                subtitle: subtitle,
                maxHeight: maxHeight,
                children: children,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<T?> _showAnchoredCard<T>({
    required BuildContext anchorContext,
    required Widget child,
    required double width,
    double maxHeight = 390,
  }) {
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) {
      return showDialog<T>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) =>
            Dialog(backgroundColor: Colors.transparent, child: child),
      );
    }
    final anchorOffset = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorRect = anchorOffset & anchorBox.size;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 90),
      pageBuilder: (dialogContext, _, _) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final popupWidth = (screenSize.width - 24).clamp(0.0, width);
        final preferredLeft =
            anchorRect.left + (anchorRect.width - popupWidth) / 2;
        final left = preferredLeft.clamp(
          12.0,
          screenSize.width - popupWidth - 12.0,
        );
        const gap = 8.0;
        final popupHeight = maxHeight.clamp(0.0, screenSize.height - 24.0);
        final belowTop = anchorRect.bottom + gap;
        final aboveTop = anchorRect.top - gap - popupHeight;
        final hasBelowSpace = belowTop + popupHeight <= screenSize.height - 12;
        final top = hasBelowSpace
            ? belowTop
            : aboveTop.clamp(12.0, screenSize.height - popupHeight - 12.0);
        return Stack(
          children: [
            Positioned(left: left, top: top, width: popupWidth, child: child),
          ],
        );
      },
    );
  }

  void _showProjectMenu(BuildContext anchorContext) {
    _showAnchoredMenu<void>(
      anchorContext: anchorContext,
      title: '项目菜单',
      subtitle: _project?.name ?? '请选择项目',
      children: [
        AppDialogListItem(
          label: '选择项目',
          accent: true,
          onTap: () {
            Navigator.of(context).pop();
            _selectProject();
          },
        ),
        AppDialogListItem(
          label: '新建项目',
          onTap: () {
            Navigator.of(context).pop();
            _createProject();
          },
        ),
        AppDialogListItem(
          label: '查看服务器项目',
          onTap: () {
            Navigator.of(context).pop();
            _showServerProjectDialog();
          },
        ),
      ],
    );
  }

  Future<void> _selectProject() async {
    if (_projects.isEmpty) {
      _showNotReady('暂无项目');
      return;
    }
    await showAppCardDialog<void>(
      context: context,
      title: '选择项目',
      subtitle: '点击切换项目，右侧可删除项目',
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < _projects.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      AppDialogListItem(
                        label: _projects[index].name,
                        subtitle: _projects[index].id == _project?.id
                            ? '当前项目'
                            : null,
                        selected: _projects[index].id == _project?.id,
                        trailing: _ProjectDeleteButton(
                          onPressed: () {
                            final project = _projects[index];
                            Navigator.of(context).pop();
                            unawaited(_deleteProject(project));
                          },
                        ),
                        onTap: () {
                          final project = _projects[index];
                          Navigator.of(context).pop();
                          unawaited(_switchProject(project));
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: AppDialogActionButton(
                text: '关闭',
                primary: false,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchProject(ProjectEntity project) async {
    if (project.id == _project?.id) return;
    await _saveCurrentDraft();
    if (!mounted) return;
    setState(() {
      _project = project;
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    _clearCurrentRow();
    await _saveMainState();
  }

  Future<void> _deleteProject(ProjectEntity project) async {
    final confirmed = await _confirmDanger(
      title: '删除项目',
      message: '是否删除项目“${project.name}”？删除后该项目的本地数据会被清空。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    final deletingCurrent = project.id == _project?.id;
    await _repository.delete(project);
    if (!mounted) return;
    _projects.removeWhere((item) => item.id == project.id);
    if (!deletingCurrent) {
      setState(() {});
      _showNotReady('已删除项目：${project.name}');
      return;
    }

    final nextProject = _projects.firstOrNull ?? await _createDefaultProject();
    if (!_projects.any((item) => item.id == nextProject.id)) {
      _projects.insert(0, nextProject);
    }
    if (!mounted) return;
    setState(() {
      _project = nextProject;
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    _clearCurrentRow();
    await _saveMainState();
    _showNotReady('已删除项目：${project.name}');
  }

  Future<void> _showServerProjectDialog() async {
    final selectedName = await _showServerProjectPicker();
    if (!mounted || selectedName == null) return;
    await _syncServerProject(selectedName);
  }

  Future<String?> _showServerProjectPicker() {
    return showAppCardDialog<String>(
      context: context,
      title: '新建项目',
      subtitle: '搜索服务器项目并同步到本地',
      builder: (context) =>
          _ServerProjectPickerBody(serverRepository: _serverRepository),
    );
  }

  Future<void> _syncServerProject(String projectName) async {
    final safeProjectName = projectName.trim();
    if (safeProjectName.isEmpty) {
      _showNotReady('项目名称无效');
      return;
    }

    final sameNameProjects = await _repository.getByNameList(safeProjectName);
    if (!mounted) return;
    final existing = sameNameProjects.firstOrNull;
    if (existing != null) {
      if (existing.id == _project?.id) {
        _showNotReady('当前项目“$safeProjectName”已经打开，原有数据已保留。');
        return;
      }
      if (!_projects.any((project) => project.id == existing.id)) {
        setState(() => _projects.insert(0, existing));
      }
      await _switchProject(existing);
      if (!mounted) return;
      _showNotReady('项目“$safeProjectName”已存在，已切换到现有项目，原有数据已保留。');
      return;
    }

    var buildingNames = <String>['1号楼'];
    try {
      final buildingResponse = await _serverRepository.getProjectBuildings(
        safeProjectName,
      );
      if (!mounted) return;
      if (!buildingResponse.isSuccess) {
        _showNotReady(buildingResponse.displayMessage.ifEmpty('获取楼栋失败'));
        return;
      }
      final serverBuildings = buildingResponse.data
          ?.map((item) => item.buildingName.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      if (serverBuildings != null && serverBuildings.isNotEmpty) {
        buildingNames = serverBuildings;
      }
    } catch (_) {
      if (!mounted) return;
      _showNotReady('获取楼栋失败，请检查网络和登录状态');
      return;
    }

    await _saveCurrentDraft();
    if (!mounted) return;
    final buildingName = buildingNames.first;
    final contents = _emptyProjectContents(buildingNames, buildingName);
    final id = await _repository.insert(
      ProjectEntity(
        name: safeProjectName,
        buildingName: buildingName,
        standardContent: contents.standard,
        fastContent: contents.fast,
        loadingContent: contents.loading,
        qualityContent: contents.quality,
      ),
    );
    final project = ProjectEntity(
      id: id,
      name: safeProjectName,
      buildingName: buildingName,
      standardContent: contents.standard,
      fastContent: contents.fast,
      loadingContent: contents.loading,
      qualityContent: contents.quality,
    );
    if (!mounted) return;
    setState(() {
      _projects.insert(0, project);
      _project = project;
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    _clearCurrentRow();
    await _saveMainState();
    if (!mounted) return;
    _showNotReady('已同步项目：$safeProjectName');
  }

  Future<ProjectEntity> _createDefaultProject() async {
    const buildingName = '1号楼';
    final contents = _emptyProjectContents(const [buildingName], buildingName);
    final id = await _repository.insert(
      ProjectEntity(
        name: '默认项目',
        buildingName: buildingName,
        standardContent: contents.standard,
        fastContent: contents.fast,
        loadingContent: contents.loading,
        qualityContent: contents.quality,
      ),
    );
    return ProjectEntity(
      id: id,
      name: '默认项目',
      buildingName: buildingName,
      standardContent: contents.standard,
      fastContent: contents.fast,
      loadingContent: contents.loading,
      qualityContent: contents.quality,
    );
  }

  Future<void> _createProject() async {
    await _showServerProjectDialog();
  }

  Future<void> _showBuildingMenu(BuildContext anchorContext) async {
    if (_project == null) {
      _showNotReady('请先选择或新建项目');
      return;
    }
    final buildings = _buildingNames();
    await _showAnchoredMenu<void>(
      anchorContext: anchorContext,
      title: '楼栋管理',
      subtitle: _currentBuildingName.ifEmpty('请选择楼栋'),
      children: [
        const _DialogSectionTitle(text: '当前楼栋'),
        for (final building in buildings)
          AppDialogListItem(
            label: building,
            selected: building == _currentBuildingName,
            onTap: () {
              Navigator.of(context).pop();
              _switchBuilding(building);
            },
          ),
        const _DialogSectionTitle(text: '操作'),
        AppDialogListItem(
          label: '增加楼栋',
          accent: true,
          onTap: () {
            Navigator.of(context).pop();
            _addBuilding();
          },
        ),
        AppDialogListItem(
          label: '删除当前楼栋',
          danger: true,
          onTap: () {
            Navigator.of(context).pop();
            _deleteCurrentBuilding();
          },
        ),
      ],
    );
  }

  List<String> _buildingNames() {
    final project = _project;
    if (project == null) return ['1号楼'];
    final names = <String>{
      if (project.buildingName.isNotEmpty) project.buildingName,
      ..._readBuildingScopedData(project.standardContent).keys,
      ..._readBuildingScopedData(project.fastContent).keys,
      ..._readBuildingScopedData(project.loadingContent).keys,
      ..._readBuildingScopedData(project.qualityContent).keys,
    }.toList();
    return names.isEmpty ? ['1号楼'] : names;
  }

  Future<void> _switchBuilding(String buildingName) async {
    final project = _project;
    if (project == null || buildingName.trim().isEmpty) return;
    if (buildingName == _currentBuildingName) return;
    await _saveCurrentDraft();
    final updated = _ensureBuildingContent(
      project,
      buildingName,
    ).copyWith(buildingName: buildingName);
    if (!mounted) return;
    setState(() {
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    await _updateProject(updated);
    _clearCurrentRow();
  }

  Future<void> _addBuilding() async {
    final value = await _showTextInputDialog(
      title: '增加楼栋',
      subtitle: '新增后会自动切换到新楼栋',
      label: '楼栋名称',
      hintText: '请输入楼栋号，如：2号楼',
    );
    final buildingName = value?.trim();
    if (buildingName == null || buildingName.isEmpty) {
      _showNotReady('楼栋号不能为空');
      return;
    }
    if (_buildingNames().contains(buildingName)) {
      _showNotReady('楼栋已存在');
      return;
    }
    final project = _project;
    if (project == null) return;
    await _saveCurrentDraft();
    final updated = _ensureBuildingContent(
      project,
      buildingName,
    ).copyWith(buildingName: buildingName);
    if (!mounted) return;
    setState(() {
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    await _updateProject(updated);
    _clearCurrentRow();
  }

  Future<void> _deleteCurrentBuilding() async {
    final project = _project;
    if (project == null) return;
    final current = project.buildingName;
    if (current.isEmpty) return;
    final buildings = _buildingNames();
    if (buildings.length <= 1) {
      _showNotReady('至少需要保留一个楼栋');
      return;
    }
    final confirmed = await _confirmDanger(
      title: '确认删除',
      message: '是否删除$current数据？\n删除后无法恢复。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    await _saveCurrentDraft();
    final currentIndex = buildings.indexOf(current);
    final remaining = buildings.where((name) => name != current).toList();
    final fallback = remaining.elementAtOrNull(currentIndex) ?? remaining.last;
    final standard = _readBuildingScopedData(project.standardContent)
      ..remove(current);
    final fast = _readBuildingScopedData(project.fastContent)..remove(current);
    final loading = _readLoadingBuildingContents(project.loadingContent)
      ..remove(current);
    final quality = _readBuildingScopedData(project.qualityContent)
      ..remove(current);
    if (!mounted) return;
    setState(() {
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    await _updateProject(
      project.copyWith(
        buildingName: fallback,
        standardContent: _encodeBuildingScopedData(
          standard,
          currentBuildingName: fallback,
        ),
        fastContent: _encodeBuildingScopedData(
          fast,
          currentBuildingName: fallback,
        ),
        loadingContent: _encodeLoadingBuildingContents(
          loading,
          currentBuildingName: fallback,
        ),
        qualityContent: _encodeBuildingScopedData(
          quality,
          currentBuildingName: fallback,
        ),
      ),
    );
    _clearCurrentRow();
    _showNotReady('已删除：$current');
  }

  Future<void> _editScope(BuildContext anchorContext) async {
    if (_project == null) {
      _showNotReady('请先选择或新建项目');
      return;
    }
    if (_mode == MainMode.quality) {
      await _showQualityFloorInputDialog(anchorContext: anchorContext);
      return;
    }
    final scopes = _scopeNamesForMode();
    final isLoading = _mode == MainMode.loading;
    final title = isLoading ? '车次管理' : '包号管理';
    final subtitle = _scopeName.isEmpty
        ? (isLoading ? '请选择或新增车次' : '请选择或新增包号')
        : _scopeName;
    final currentSection = isLoading ? '当前车次' : '当前包号';
    await _showAnchoredMenu<void>(
      anchorContext: anchorContext,
      title: title,
      subtitle: subtitle,
      children: [
        _DialogSectionTitle(text: currentSection),
        for (final scope in scopes)
          AppDialogListItem(
            label: scope,
            selected: scope == _scopeName,
            onTap: () {
              Navigator.of(context).pop();
              _setScope(scope);
            },
          ),
        const _DialogSectionTitle(text: '操作'),
        AppDialogListItem(
          label: '新增${_mode.scopeLabel}',
          accent: true,
          onTap: () {
            Navigator.of(context).pop();
            _addScope();
          },
        ),
        AppDialogListItem(
          label: '删除当前${_mode.scopeLabel}',
          danger: true,
          onTap: () {
            Navigator.of(context).pop();
            _deleteCurrentScope();
          },
        ),
      ],
    );
  }

  List<String> _scopeNamesForMode() {
    final names = _mode == MainMode.loading
        ? _readLoadingTripNames(
            _contentForMode(_mode),
            buildingName: _currentBuildingName,
          )
        : _readScopedData(
            _contentForMode(_mode),
            _currentBuildingName,
          ).keys.toList();
    if (!names.contains(_scopeName)) names.insert(0, _scopeName);
    return names.isEmpty ? [_scopeName] : names;
  }

  void _setScope(String scope) {
    setState(() {
      switch (_mode) {
        case MainMode.loading:
          _tripName = scope;
        case MainMode.quality:
          _qualityFloor = scope;
        case MainMode.standard:
        case MainMode.fast:
          _packageName = scope;
      }
    });
    _clearCurrentRow();
    _saveMainState();
  }

  Future<void> _addScope() async {
    if (_mode == MainMode.quality) {
      await _showQualityFloorInputDialog();
      return;
    }
    _setScope(_nextScopeName());
  }

  Future<void> _deleteCurrentScope() async {
    final project = _project;
    if (project == null) return;
    final confirmed = await _confirmDanger(
      title: '删除当前${_mode.scopeLabel}',
      message: '是否删除$_scopeName数据？\n删除后无法恢复。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    final content = _mode == MainMode.loading
        ? _removeLoadingTrip(
            _contentForMode(_mode),
            _tripName,
            buildingName: _currentBuildingName,
          )
        : () {
            final buildingScoped = _readBuildingScopedData(
              _contentForMode(_mode),
            );
            final scoped = Map<String, List<Map<String, String>>>.from(
              buildingScoped[_currentBuildingName] ?? const {},
            );
            scoped.remove(_scopeName);
            buildingScoped[_currentBuildingName] = scoped;
            return _encodeBuildingScopedData(
              buildingScoped,
              currentBuildingName: _currentBuildingName,
            );
          }();
    final fallback = _mode == MainMode.loading
        ? (_readLoadingTripNames(
                content,
                buildingName: _currentBuildingName,
              ).firstOrNull ??
              _defaultScopeName())
        : _readScopedData(content, _currentBuildingName).keys.firstOrNull ??
              _defaultScopeName();
    final nextContent =
        _mode == MainMode.loading &&
            _readLoadingTripNames(
              content,
              buildingName: _currentBuildingName,
            ).isEmpty
        ? _encodeLoadingRowsForTrip(
            content,
            fallback,
            const <Map<String, String>>[],
            buildingName: _currentBuildingName,
          )
        : content;
    final updated = switch (_mode) {
      MainMode.standard => project.copyWith(standardContent: nextContent),
      MainMode.fast => project.copyWith(fastContent: nextContent),
      MainMode.loading => project.copyWith(loadingContent: nextContent),
      MainMode.quality => project.copyWith(qualityContent: nextContent),
    };
    _setScope(fallback);
    await _updateProject(updated);
  }

  String _nextScopeName() {
    final prefix = switch (_mode) {
      MainMode.loading => '第',
      MainMode.quality => '铝模',
      _ => '第',
    };
    final suffix = switch (_mode) {
      MainMode.loading => '车',
      MainMode.quality => '层',
      _ => '包',
    };
    final existing = _scopeNamesForMode().toSet();
    for (var index = 1; index < 100; index++) {
      final name = _mode == MainMode.quality
          ? '$prefix$index$suffix'
          : '$prefix$index$suffix';
      if (!existing.contains(name)) return name;
    }
    return _scopeName;
  }

  String _defaultScopeName() => switch (_mode) {
    MainMode.loading => '第1车',
    MainMode.quality => '铝模1层',
    _ => '第1包',
  };

  Future<void> _showQualityFloorInputDialog({
    BuildContext? anchorContext,
  }) async {
    final currentNumber =
        RegExp(r'\d+').firstMatch(_qualityFloor)?.group(0) ?? '';
    final value = await _showTextInputDialog(
      anchorContext: anchorContext,
      title: '输入铝模层数',
      subtitle: '当前质量反馈模式下的楼层标签',
      label: '铝模层数',
      hintText: '请输入层数',
      initialValue: currentNumber,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
    final text = value?.trim();
    if (text == null) return;
    if (text.isEmpty) {
      _showNotReady('请输入层数');
      return;
    }
    _setScope('铝模$text层');
  }

  Future<String?> _showTextInputDialog({
    BuildContext? anchorContext,
    required String title,
    required String label,
    String? subtitle,
    String? hintText,
    String initialValue = '',
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final controller = TextEditingController(text: initialValue);
    final field = TextField(
      controller: controller,
      autofocus: true,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(labelText: label, hintText: hintText),
    );
    final actions = AppDialogActionRow(
      onCancel: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop();
      },
      onConfirm: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(controller.text);
      },
    );
    final future = anchorContext == null
        ? showAppCardDialog<String>(
            context: context,
            title: title,
            subtitle: subtitle ?? label,
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [field, const SizedBox(height: 16), actions],
            ),
          )
        : _showAnchoredCard<String>(
            anchorContext: anchorContext,
            width: 320,
            maxHeight: 260,
            child: _AnchoredMenuCard(
              title: title,
              subtitle: subtitle ?? label,
              maxHeight: 170,
              children: [field, actions],
            ),
          );
    return future;
  }

  Future<bool> _confirmDanger({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showAppCardDialog<bool>(
      context: context,
      title: title,
      subtitle: message,
      builder: (context) => AppDialogActionRow(
        danger: true,
        confirmText: confirmText,
        onCancel: () => Navigator.of(context).pop(false),
        onConfirm: () => Navigator.of(context).pop(true),
      ),
    );
    return result == true;
  }

  void _showMoreMenu(BuildContext anchorContext) {
    _showAnchoredMenu<void>(
      anchorContext: anchorContext,
      title: '更多功能',
      subtitle: '导出、分享、更新、历史与服务器操作',
      children: [
        const _DialogSectionTitle(text: '常用功能'),
        AppDialogListItem(
          label: '导出',
          accent: true,
          onTap: () {
            Navigator.of(context).pop();
            _exportCurrentModeExcel();
          },
        ),
        AppDialogListItem(
          label: '分享',
          onTap: () {
            Navigator.of(context).pop();
            _shareCurrentModeExcel();
          },
        ),
        AppDialogListItem(
          label: '一键导出返厂汇总表',
          onTap: () {
            Navigator.of(context).pop();
            _shareLoadingSummaryProject();
          },
        ),
        AppDialogListItem(
          label: '检查更新',
          onTap: () {
            Navigator.of(context).pop();
            _checkAppUpdate();
          },
        ),
        const _DialogSectionTitle(text: '扩展能力'),
        AppDialogListItem(
          label: '二维码识别',
          onTap: () {
            Navigator.of(context).pop();
            _showFeatureComingSoon(
              title: '二维码识别',
              message:
                  '你发现了一个新功能，这个功能通过摄像头连续扫描模板二维码，即可连续统计模板的安装编号及型号。但目前资金不足，人员不够，代码未写，敬请期待',
            );
          },
        ),
        AppDialogListItem(
          label: 'NFC碰一碰',
          onTap: () {
            Navigator.of(context).pop();
            _showFeatureComingSoon(
              title: 'NFC碰一碰',
              message:
                  '你发现了一个更加强大的功能，这个功能通过手机靠近模板编码位置，即可自动统计模板的安装编号及型号。但目前资金不足，人员不够，代码未写，敬请期待',
            );
          },
        ),
        AppDialogListItem(
          label: '历史数据',
          onTap: () {
            Navigator.of(context).pop();
            _showHistoryDialog();
          },
        ),
        const _DialogSectionTitle(text: '服务器'),
        AppDialogListItem(
          label: '上传当前文件到服务器',
          onTap: () {
            Navigator.of(context).pop();
            _uploadCurrentModeToServer();
          },
        ),
        AppDialogListItem(
          label: '查看服务器统计',
          onTap: () {
            Navigator.of(context).pop();
            _showServerStats();
          },
        ),
        AppDialogListItem(
          label: '上传发货清单',
          onTap: () {
            Navigator.of(context).pop();
            context.go('/delivery-order');
          },
        ),
        AppDialogListItem(
          label: '数据生成查询',
          onTap: () {
            Navigator.of(context).pop();
            context.go('/settlement-data');
          },
        ),
      ],
    );
  }

  Future<void> _showFeatureComingSoon({
    required String title,
    required String message,
  }) {
    return showAppCardDialog<void>(
      context: context,
      title: title,
      subtitle: '功能迁移中',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 16),
          AppDialogActionButton(
            text: '知道了',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountMenu(BuildContext anchorContext) async {
    final username = await _preferences.getUsername();
    final isLoggedIn = await _preferences.isLoggedIn();
    if (!mounted || !anchorContext.mounted) return;
    setState(() => _username = username);

    await _showAnchoredCard<void>(
      anchorContext: anchorContext,
      width: 300,
      maxHeight: 270,
      child: _AccountPopupCard(
        username: username.ifEmpty('未登录账号'),
        avatarText: _avatarText,
        online: isLoggedIn,
        connectionCountText: '$_subDisplaySessionCount台',
        subDisplayStatusText: _subDisplayStatusText,
        hasSubDisplayCode: _subDisplayCode.isNotEmpty,
        onViewDevices: () {
          Navigator.of(context).pop();
          _showSubDisplayDevicesDialog();
        },
        onSubDisplayCode: () {
          Navigator.of(context).pop();
          _showSubDisplayDialog();
        },
        onOpenBackend: () {
          Navigator.of(context).pop();
          _openBackend();
        },
        onRelogin: () {
          Navigator.of(context).pop();
          _logout();
        },
        onLogout: () {
          Navigator.of(context).pop();
          _logout();
        },
      ),
    );
  }

  Future<void> _logout() async {
    await _preferences.clearLogin();
    if (mounted) context.go('/login');
  }

  Future<void> _openBackend() async {
    try {
      await _updateChannel.invokeMethod<void>('openUrl', {
        'url': 'https://yxff.work/',
      });
    } catch (_) {
      if (mounted) _showNotReady('后台打开失败');
    }
  }

  Future<void> _showSubDisplayDevicesDialog() async {
    if (_subDisplayCode.isEmpty) {
      _showNotReady('未生成连接码');
      return;
    }
    try {
      final status = await _serverRepository.getSubDisplayStatus(
        _subDisplayCode,
      );
      if (!mounted) return;
      if (!status.isSuccess) {
        _showNotReady(status.displayMessage.ifEmpty('连接状态刷新失败'));
        return;
      }
      final data = status.data;
      final devices = data?.devices ?? const <AppSubDisplayDevice>[];
      setState(() {
        _subDisplayConnected = data?.connected == true;
        _subDisplaySessionCount = data?.sessionCount ?? devices.length;
      });
      await showAppCardDialog<void>(
        context: context,
        title: '连接设备',
        subtitle: '当前连接 $_subDisplaySessionCount 台',
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.56,
          ),
          child: devices.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: Text('暂无连接设备')),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < devices.length; index++) ...[
                        if (index > 0) const SizedBox(height: 8),
                        AppDialogListItem(
                          label: devices[index].deviceModel.ifEmpty('未知设备'),
                          subtitle:
                              '设备：${devices[index].deviceId.ifEmpty('-')}\n最后活跃：${devices[index].lastActiveTime.ifEmpty('-')}',
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      );
    } catch (_) {
      if (mounted) _showNotReady('连接状态刷新失败，请检查网络');
    }
  }

  void _showNotReady(String message) {
    showAppToast(context, message);
  }

  Future<void> _showServerStats() async {
    try {
      final response = await _serverRepository.getStatSummary();
      if (!mounted) return;
      final data = response.data;
      if (!response.isSuccess || data == null) {
        _showNotReady(response.displayMessage.ifEmpty('服务器统计获取失败'));
        return;
      }
      await showAppCardDialog<void>(
        context: context,
        title: '服务器统计',
        subtitle: '当前账号上传统计汇总',
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '今日：${data.todayCount}\n本周：${data.weekCount}\n本月：${data.monthCount}\n本季度：${data.quarterCount}\n本年：${data.yearCount}',
            ),
            const SizedBox(height: 16),
            AppDialogActionButton(
              text: '确定',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _showNotReady('网络异常，服务器统计获取失败');
    }
  }

  Future<void> _checkAppUpdate() async {
    try {
      final response = await _versionRepository.getLatestVersion();
      final info = response.data;
      if (!mounted) return;
      if (!response.isSuccess || info == null || info.downloadUrl.isEmpty) {
        _showNotReady(response.displayMessage.ifEmpty('当前已是最新版本'));
        return;
      }
      final shouldUpdate = await showAppCardDialog<bool>(
        context: context,
        title: info.updateTitle.ifEmpty('发现新版本 ${info.versionName}'),
        subtitle: info.isForceUpdate ? '本次更新为强制更新' : '应用更新',
        barrierDismissible: !info.isForceUpdate,
        showCloseButton: !info.isForceUpdate,
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(info.updateContent.ifEmpty('是否下载并安装新版本？')),
            const SizedBox(height: 16),
            if (info.isForceUpdate)
              AppDialogActionButton(
                text: '立即更新',
                onPressed: () => Navigator.of(context).pop(true),
              )
            else
              AppDialogActionRow(
                cancelText: '暂不更新',
                confirmText: '立即更新',
                onCancel: () => Navigator.of(context).pop(false),
                onConfirm: () => Navigator.of(context).pop(true),
              ),
          ],
        ),
      );
      if (shouldUpdate != true) return;
      _showNotReady('正在下载更新，请稍候');
      await _updateChannel.invokeMethod<String>('downloadAndInstall', {
        'url': info.downloadUrl,
        'versionCode': info.versionCode,
      });
    } catch (error) {
      if (mounted) _showNotReady('更新检查失败，请检查网络');
    }
  }

  Future<void> _showHistoryDialog() async {
    final history = await _listHistory();
    if (!mounted) return;
    await showAppCardDialog<void>(
      context: context,
      title: '历史数据',
      subtitle: '手动备份、恢复或删除本地历史数据',
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDialogActionButton(
              text: '备份当前数据',
              onPressed: () {
                Navigator.of(context).pop();
                _saveCurrentHistory();
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: history.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('暂无历史备份'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final path = item['path']?.toString() ?? '';
                        return AppDialogListItem(
                          label: item['name']?.toString() ?? '',
                          subtitle: _formatHistoryTime(item['modified']),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteHistory(path);
                            },
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            _restoreHistory(path);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, Object?>>> _listHistory() async {
    final result = await _exportChannel.invokeListMethod<Object?>(
      'listHistory',
    );
    return (result ?? [])
        .whereType<Map<Object?, Object?>>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }

  Future<void> _saveCurrentHistory({bool showToast = true}) async {
    final project = _project;
    if (project == null) return;
    final content = jsonEncode({
      'projectId': project.id,
      'projectName': project.name,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'standardContent': project.standardContent,
      'fastContent': project.fastContent,
      'loadingContent': project.loadingContent,
      'qualityContent': project.qualityContent,
      'vehicleInfo': _vehicleInfo,
      'currentModeType': _mode.name,
      'packageName': _packageName,
      'tripName': _tripName,
      'qualityFloor': _qualityFloor,
      'buildingName': project.buildingName,
    });
    final fileName =
        '${project.name}_历史数据自动备份_${DateTime.now().millisecondsSinceEpoch}.json';
    await _exportChannel.invokeMethod<String>('saveHistory', {
      'fileName': fileName,
      'content': content,
    });
    if (showToast && mounted) _showNotReady('历史数据已备份');
  }

  Future<void> _restoreHistory(String path) async {
    if (path.isEmpty) return;
    final confirmed = await _confirmDanger(
      title: '恢复历史数据',
      message: '恢复会覆盖当前项目四类数据，是否继续？',
      confirmText: '恢复',
    );
    if (!confirmed) return;
    final project = _project;
    if (project == null) return;
    final content = await _exportChannel.invokeMethod<String>('readHistory', {
      'path': path,
    });
    if (content == null || content.isEmpty) return;
    final json = jsonDecode(content) as Map<String, Object?>;
    final restoredBuildingName = json['buildingName']?.toString();
    final updated = project.copyWith(
      buildingName: restoredBuildingName == null || restoredBuildingName.isEmpty
          ? project.buildingName
          : restoredBuildingName,
      standardContent:
          json['standardContent']?.toString() ?? project.standardContent,
      fastContent: json['fastContent']?.toString() ?? project.fastContent,
      loadingContent:
          json['loadingContent']?.toString() ?? project.loadingContent,
      qualityContent:
          json['qualityContent']?.toString() ?? project.qualityContent,
    );
    final restoredVehicleInfo = json['vehicleInfo'];
    if (restoredVehicleInfo is Map) {
      _vehicleInfo = restoredVehicleInfo.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
    }
    final restoredMode = MainMode.values.firstWhere(
      (mode) => mode.name == json['currentModeType']?.toString(),
      orElse: () => _mode,
    );
    setState(() {
      _mode = restoredMode;
      _packageName =
          json['packageName']?.toString().ifEmpty(_packageName) ?? _packageName;
      _tripName = json['tripName']?.toString().ifEmpty(_tripName) ?? _tripName;
      _qualityFloor =
          json['qualityFloor']?.toString().ifEmpty(_qualityFloor) ??
          _qualityFloor;
    });
    await _updateProject(updated);
    _clearCurrentRow();
    if (mounted) _showNotReady('历史数据已恢复');
  }

  Future<void> _deleteHistory(String path) async {
    if (path.isEmpty) return;
    final confirmed = await _confirmDanger(
      title: '删除历史备份',
      message: '是否删除该历史备份？删除后无法恢复。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    await _exportChannel.invokeMethod<bool>('deleteHistory', {'path': path});
    if (mounted) _showNotReady('历史备份已删除');
  }

  String _formatHistoryTime(Object? value) {
    final millis = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    if (millis <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(millis).toString();
  }

  Future<void> _uploadCurrentModeToServer() async {
    await _saveCurrentDraft();
    final project = _project;
    final rows = _rows;
    if (project == null || rows.isEmpty) {
      _showNotReady('当前模式暂无可上传的数据');
      return;
    }
    if (_mode == MainMode.quality) {
      await _shareQualityDocument(project, rows);
      return;
    }
    try {
      final filePath = await _saveCurrentModeExcelFile(project, rows);
      final buildingName = project.buildingName.isEmpty
          ? '1号楼'
          : project.buildingName;
      final response = switch (_mode) {
        MainMode.standard => await _serverRepository.uploadModelStatFile(
          projectName: project.name,
          buildingName: buildingName,
          filePath: filePath,
        ),
        MainMode.fast => await _serverRepository.uploadReturnStatFile(
          projectName: project.name,
          buildingName: buildingName,
          filePath: filePath,
        ),
        MainMode.loading => await _serverRepository.uploadReturnLoadFile(
          projectName: project.name,
          buildingName: buildingName,
          filePath: filePath,
        ),
        MainMode.quality => throw StateError('质量反馈暂不上传'),
      };
      if (!mounted) return;
      _showNotReady(
        response.isSuccess ? '上传成功' : response.displayMessage.ifEmpty('上传失败'),
      );
    } catch (error) {
      if (mounted) _showNotReady('上传失败，请检查网络和登录状态');
    }
  }

  Future<String> _saveCurrentModeExcelFile(
    ProjectEntity project,
    List<Map<String, String>> rows,
  ) async {
    final bytes = _mode == MainMode.loading
        ? _buildLoadingExcel(project)
        : _buildCurrentModeExcel(project, rows);
    return _saveExcelFile(_currentModeExcelFileName(project), bytes);
  }

  Future<String> _saveExcelFile(String fileName, List<int> bytes) async {
    final result = await _exportChannel.invokeMethod<String>('saveBytesFile', {
      'fileName': fileName,
      'bytes': bytes,
    });
    return result ?? '';
  }

  Future<void> _shareLoadingSummaryProject() async {
    final project = _project;
    if (project == null) return;
    final buildingName = project.buildingName.ifEmpty('1号楼');
    final tripNames = _readLoadingTripNames(
      project.loadingContent,
      buildingName: buildingName,
    );
    if (tripNames.isEmpty) {
      _showNotReady('暂无返厂装车数据');
      return;
    }
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = '返厂汇总';
    final headers = ['项目', '楼栋', '车次', '铝模重量', '铁件重量', '装车时间', '车牌号'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
    }
    for (var i = 0; i < tripNames.length; i++) {
      final tripName = tripNames[i];
      final rows = _decodeLoadingRowsForTrip(
        project.loadingContent,
        tripName,
        buildingName: buildingName,
      );
      final meta = rows.firstWhere(_isLoadingMetaRow, orElse: _emptyLoadingRow);
      final vehicleInfo = _emptyVehicleInfo().map(
        (key, value) => MapEntry(key, meta['vehicle_$key'] ?? value),
      );
      final aluminumRows = rows.where(_isAluminumLoadingRow).toList();
      final ironRows = rows.where(_isIronLoadingRow).toList();
      final aluminumTotal =
          meta['loadingAluminumWeightMode'] == 'WEIGHBRIDGE_TOTAL'
          ? _loadingAluminumWeighbridgeWeightFromInfo(vehicleInfo)
          : _sumDouble(aluminumRows, 'weight');
      final ironTotal = meta['loadingIronWeightMode'] == 'WEIGHBRIDGE_TOTAL'
          ? _loadingIronWeighbridgeWeightFromInfo(vehicleInfo)
          : _sumDouble(ironRows, 'weight');
      final rowIndex = i + 2;
      sheet.getRangeByIndex(rowIndex, 1).setText(project.name);
      sheet
          .getRangeByIndex(rowIndex, 2)
          .setText(project.buildingName.ifEmpty('1号楼'));
      sheet.getRangeByIndex(rowIndex, 3).setText(tripName);
      sheet.getRangeByIndex(rowIndex, 4).setNumber(aluminumTotal);
      sheet.getRangeByIndex(rowIndex, 5).setNumber(ironTotal);
      sheet
          .getRangeByIndex(rowIndex, 6)
          .setText(vehicleInfo['loadingDate'].orEmpty());
      sheet
          .getRangeByIndex(rowIndex, 7)
          .setText(vehicleInfo['vehiclePlateNumber'].orEmpty());
    }
    for (var i = 1; i <= headers.length; i++) {
      sheet.autoFitColumn(i);
    }
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    await _exportChannel.invokeMethod<void>('shareBytesFile', {
      'fileName':
          '${project.name}_返厂汇总表_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      'bytes': bytes,
      'mimeType':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'title': '${project.name}返厂汇总表',
    });
  }

  Future<void> _exportCurrentModeExcel() async {
    await _saveCurrentDraft();
    final project = _project;
    if (project == null) {
      _showNotReady('请先选择项目');
      return;
    }
    final rows = _rows;
    if (_mode == MainMode.quality) {
      if (rows.isEmpty) {
        _showNotReady('当前模式暂无可导出的数据');
        return;
      }
      final path = await _saveQualityDocumentFile(project, rows);
      if (mounted) _showNotReady(path.isEmpty ? '导出失败' : '已导出：$path');
      return;
    }
    final paths = await _exportAllStatisticsFiles(project);
    if (!mounted) return;
    _showNotReady(
      paths.any((path) => path.isEmpty) ? '导出失败' : '型号统计、返厂统计、返厂装车已分别导出',
    );
  }

  Future<List<String>> _exportAllStatisticsFiles(ProjectEntity project) async {
    return [
      await _saveExcelFile(
        _excelFileNameForMode(project, MainMode.standard),
        _buildStandardExcel(project),
      ),
      await _saveExcelFile(
        _excelFileNameForMode(project, MainMode.fast),
        _buildFastReturnExcel(project),
      ),
      await _saveExcelFile(
        _excelFileNameForMode(project, MainMode.loading),
        _buildLoadingExcel(project),
      ),
    ];
  }

  Future<void> _shareCurrentModeExcel() async {
    await _saveCurrentDraft();
    final project = _project;
    final rows = _rows;
    if (project == null || rows.isEmpty) return;
    if (_mode == MainMode.quality) {
      await _shareQualityDocument(project, rows);
      return;
    }
    final bytes = _mode == MainMode.loading
        ? _buildLoadingExcel(project)
        : _buildCurrentModeExcel(project, rows);
    await _exportChannel.invokeMethod<void>('shareBytesFile', {
      'fileName': _currentModeExcelFileName(project),
      'bytes': bytes,
      'mimeType':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'title': '${project.name}${_mode.label}',
    });
  }

  Future<String> _saveQualityDocumentFile(
    ProjectEntity project,
    List<Map<String, String>> rows,
  ) async {
    final photoMap = await _readQualityPhotoBase64(rows);
    final result = await _exportChannel.invokeMethod<String>('saveBytesFile', {
      'fileName': _qualityDocumentFileName(project),
      'bytes': utf8.encode(_buildQualityDocumentHtml(project, rows, photoMap)),
    });
    return result ?? '';
  }

  Future<void> _shareQualityDocument(
    ProjectEntity project,
    List<Map<String, String>> rows,
  ) async {
    final photoMap = await _readQualityPhotoBase64(rows);
    await _exportChannel.invokeMethod<void>('shareTextFile', {
      'fileName': _qualityDocumentFileName(project),
      'content': _buildQualityDocumentHtml(project, rows, photoMap),
      'mimeType': 'application/msword',
      'title': '${project.name}质量反馈',
    });
  }

  String _qualityDocumentFileName(ProjectEntity project) {
    final building = project.buildingName.ifEmpty('1号楼');
    return '${project.name}_${building}_质量反馈_${DateTime.now().millisecondsSinceEpoch}.doc';
  }

  Future<Map<String, String>> _readQualityPhotoBase64(
    List<Map<String, String>> rows,
  ) async {
    final result = <String, String>{};
    final uris = rows
        .expand((row) => row['photoUris'].orEmpty().split('|'))
        .where((uri) => uri.trim().isNotEmpty)
        .toSet();
    for (final uri in uris) {
      final data = await _exportChannel.invokeMethod<String>(
        'readBytesBase64',
        {'uri': uri},
      );
      if (data != null && data.isNotEmpty) result[uri] = data;
    }
    return result;
  }

  String _buildQualityDocumentHtml(
    ProjectEntity project,
    List<Map<String, String>> rows,
    Map<String, String> photoMap,
  ) {
    final exportDate = DateTime.now();
    final dateText = '${exportDate.year}-${exportDate.month}-${exportDate.day}';
    final buildingName = project.buildingName.ifEmpty('1号楼');
    final buffer = StringBuffer()
      ..writeln('<html><head><meta charset="utf-8"><style>')
      ..writeln(
        'body{font-family:"Microsoft YaHei",Arial,sans-serif;font-size:12pt;}',
      )
      ..writeln(
        '.company{text-align:center;font-size:20pt;font-weight:bold;margin:0;}',
      )
      ..writeln(
        '.title{text-align:center;font-size:14pt;font-weight:bold;margin:8px 0;}',
      )
      ..writeln('.report-no{text-align:right;font-weight:bold;font-size:11pt;}')
      ..writeln('.desc{font-weight:bold;margin:14px 0 8px 0;}')
      ..writeln(
        'table{width:100%;border-collapse:collapse;table-layout:fixed;}',
      )
      ..writeln(
        'th,td{border:1px solid #000;padding:6px;text-align:center;vertical-align:middle;word-break:break-all;}',
      )
      ..writeln('th{font-weight:bold;}')
      ..writeln('.left{text-align:left;}')
      ..writeln(
        '.photo{max-width:130px;max-height:100px;display:block;margin:2px auto;}',
      )
      ..writeln('</style></head><body>')
      ..writeln('<p class="company">中建铝新材料有限公司</p>')
      ..writeln('<p class="title">项目现场质量问题报告单</p>')
      ..writeln('<p class="report-no">报告编号：ZJL-GCZ-0</p>')
      ..writeln(
        '<p>项目：${_escapeHtml(project.name)}　　　楼栋：${_escapeHtml(buildingName)}　　　铝模层数：${_escapeHtml(_qualityFloor)}</p>',
      )
      ..writeln(
        '<p class="desc">质量问题描述：${_escapeHtml(buildingName)}在铝模第${_escapeHtml(_qualityFloor)}层施工过程中发现以下问题</p>',
      )
      ..writeln('<table>')
      ..writeln(
        '<colgroup><col style="width:12%"><col style="width:13%"><col style="width:13%"><col style="width:13%"><col style="width:28%"><col style="width:21%"></colgroup>',
      )
      ..writeln(
        '<tr><th>材料类型</th><th>安装编号</th><th>型号</th><th>质量类型</th><th>反馈说明</th><th>附图</th></tr>',
      );
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final photos = row['photoUris']
          .orEmpty()
          .split('|')
          .where((uri) => uri.trim().isNotEmpty)
          .map((uri) {
            final data = photoMap[uri];
            if (data == null || data.isEmpty) return _escapeHtml(uri);
            return '<img class="photo" src="data:image/jpeg;base64,$data" />';
          })
          .join('<br>');
      buffer.writeln(
        '<tr><td>${_escapeHtml(row['materialType'])}</td><td>${_escapeHtml(row['installNumber'])}</td><td>${_escapeHtml(row['model'])}</td><td>${_escapeHtml(row['qualityType'])}</td><td class="left">${_escapeHtml(row['description'])}</td><td>$photos</td></tr>',
      );
    }
    buffer
      ..writeln('</table>')
      ..writeln('<p class="desc">原因分析：</p>')
      ..writeln('<p class="desc">处理意见：</p>')
      ..writeln(
        '<p style="text-align:right;margin-top:32px;">反馈人：　　　　　　　　日期：$dateText</p>',
      )
      ..writeln('</body></html>');
    return buffer.toString();
  }

  String _currentModeExcelFileName(ProjectEntity project) =>
      _excelFileNameForMode(project, _mode);

  String _excelFileNameForMode(ProjectEntity project, MainMode mode) {
    final building = project.buildingName.ifEmpty('1号楼');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${project.name}_${building}_${mode.label}_$timestamp.xlsx';
  }

  List<int> _buildLoadingExcel(ProjectEntity project) {
    final workbook = xlsio.Workbook();
    final buildingName = project.buildingName.ifEmpty('1号楼');
    final tripNames = _readLoadingTripNames(
      project.loadingContent,
      buildingName: buildingName,
    );
    final names = tripNames.isEmpty ? [_tripName] : tripNames;
    for (var sheetIndex = 0; sheetIndex < names.length; sheetIndex++) {
      final tripName = names[sheetIndex];
      final sheet = sheetIndex == 0
          ? workbook.worksheets[0]
          : workbook.worksheets.addWithName(tripName);
      sheet.name = tripName;
      _fillLoadingTripSheet(sheet, project, tripName);
    }
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }

  void _fillLoadingTripSheet(
    xlsio.Worksheet sheet,
    ProjectEntity project,
    String tripName,
  ) {
    final buildingName = project.buildingName.ifEmpty('1号楼');
    final tripRows = _decodeLoadingRowsForTrip(
      project.loadingContent,
      tripName,
      buildingName: buildingName,
    );
    final rows = tripRows.where((row) => !_isLoadingMetaRow(row)).toList();
    final meta = tripRows.firstWhere(
      _isLoadingMetaRow,
      orElse: _emptyLoadingRow,
    );
    final vehicleInfo = _emptyVehicleInfo().map(
      (key, value) => MapEntry(key, meta['vehicle_$key'] ?? value),
    );
    final aluminumMode = meta['loadingAluminumWeightMode'] ?? 'UNSELECTED';
    final ironMode = meta['loadingIronWeightMode'] ?? 'UNSELECTED';
    final aluminumRows = rows.where(_isAluminumLoadingRow).toList();
    final ironRows = rows.where(_isIronLoadingRow).toList();
    final aluminumTotal = aluminumMode == 'WEIGHBRIDGE_TOTAL'
        ? _loadingAluminumWeighbridgeWeightFromInfo(vehicleInfo)
        : _sumDouble(aluminumRows, 'weight');
    final ironTotal = ironMode == 'WEIGHBRIDGE_TOTAL'
        ? _loadingIronWeighbridgeWeightFromInfo(vehicleInfo)
        : _sumDouble(ironRows, 'weight');

    for (var col = 1; col <= 9; col++) {
      sheet.setColumnWidthInPixels(col, col == 1 ? 92 : 108);
    }

    void set(int row, int col, String value) {
      final range = sheet.getRangeByIndex(row, col);
      range.setText(value);
      range.cellStyle.hAlign = xlsio.HAlignType.center;
      range.cellStyle.vAlign = xlsio.VAlignType.center;
      range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }

    void merge(int row1, int col1, int row2, int col2) {
      sheet.getRangeByIndex(row1, col1, row2, col2).merge();
    }

    set(1, 1, '返厂物料交接单（统计表）');
    merge(1, 1, 1, 9);
    sheet.getRangeByIndex(1, 1).cellStyle.bold = true;
    set(2, 1, '项目名称');
    set(2, 2, project.name);
    merge(2, 2, 2, 3);
    set(2, 4, '楼栋号');
    set(2, 5, project.buildingName.ifEmpty('1号楼'));
    set(2, 6, '车次');
    set(2, 7, tripName);
    merge(2, 7, 2, 9);
    set(3, 1, '是否为最后一车材料：');
    merge(3, 1, 3, 2);
    set(3, 3, '○是');
    set(3, 4, '○否');
    set(3, 5, '装车时间');
    set(3, 6, vehicleInfo['loadingDate'].orEmpty());
    merge(3, 6, 3, 9);

    set(4, 1, '物料类别');
    set(4, 2, '物料名称');
    set(4, 3, meta['loadingAluminumColumnMode'] == 'COUNT' ? '包数' : '包号');
    set(4, 4, '面积（㎡）');
    set(4, 5, '重量（kg）');
    set(4, 6, '备      注');
    merge(4, 6, 4, 9);

    var rowIndex = 5;
    final aluminumStart = rowIndex;
    for (final item in aluminumRows) {
      set(rowIndex, 2, item['material'].orEmpty());
      set(rowIndex, 3, item['packages'].orEmpty());
      set(rowIndex, 4, item['quantity'].orEmpty());
      set(
        rowIndex,
        5,
        aluminumMode == 'WEIGHBRIDGE_TOTAL' ? '' : item['weight'].orEmpty(),
      );
      set(rowIndex, 6, item['remark'].orEmpty());
      merge(rowIndex, 6, rowIndex, 9);
      rowIndex++;
    }
    if (aluminumRows.isNotEmpty) {
      set(aluminumStart, 1, '铝件/ 铝模板（含混凝土）');
      merge(aluminumStart, 1, rowIndex - 1, 1);
    }
    set(rowIndex, 2, '返厂合计');
    set(rowIndex, 5, _formatNumber(aluminumTotal));
    merge(rowIndex, 6, rowIndex, 9);
    rowIndex++;
    set(rowIndex, 3, '成品库确认');
    merge(rowIndex, 3, rowIndex, 4);
    set(rowIndex, 6, '成品库：');
    merge(rowIndex, 6, rowIndex, 9);
    rowIndex++;
    set(rowIndex, 3, '子公司接收入确认');
    merge(rowIndex, 3, rowIndex, 4);
    set(rowIndex, 6, '子公司接收入：');
    merge(rowIndex, 6, rowIndex, 9);
    rowIndex++;

    set(rowIndex, 2, '物料名称');
    set(rowIndex, 3, '包数');
    set(rowIndex, 4, '数量（件/套）');
    set(rowIndex, 5, '重量（kg）');
    set(rowIndex, 6, '备      注');
    merge(rowIndex, 6, rowIndex, 9);
    rowIndex++;

    final ironStart = rowIndex;
    for (final item in ironRows) {
      set(rowIndex, 2, item['material'].orEmpty());
      set(rowIndex, 3, item['packages'].orEmpty());
      set(rowIndex, 4, item['quantity'].orEmpty());
      set(
        rowIndex,
        5,
        ironMode == 'WEIGHBRIDGE_TOTAL' ? '' : item['weight'].orEmpty(),
      );
      set(rowIndex, 6, item['remark'].orEmpty());
      merge(rowIndex, 6, rowIndex, 9);
      rowIndex++;
    }
    if (ironRows.isNotEmpty) {
      set(ironStart, 1, '铁件');
      merge(ironStart, 1, rowIndex - 1, 1);
    }
    set(rowIndex, 2, '返厂合计');
    set(rowIndex, 5, _formatNumber(ironTotal));
    merge(rowIndex, 6, rowIndex, 9);
    rowIndex++;
    set(rowIndex, 3, '成品库确认');
    merge(rowIndex, 3, rowIndex, 4);
    set(rowIndex, 6, '成品库：');
    merge(rowIndex, 6, rowIndex, 9);
    rowIndex++;
    set(rowIndex, 3, '子公司接收入确认');
    merge(rowIndex, 3, rowIndex, 4);
    set(rowIndex, 6, '子公司接收入：');
    merge(rowIndex, 6, rowIndex, 9);
  }

  List<int> _buildFastReturnExcel(ProjectEntity project) {
    final workbook = xlsio.Workbook();
    final building = project.buildingName.ifEmpty('1号楼');
    final scopedRows = _readScopedData(project.fastContent, building);
    final packageNames = <String>{_packageName, ...scopedRows.keys}.where((
      name,
    ) {
      final rows = scopedRows[name] ?? const <Map<String, String>>[];
      return rows.isNotEmpty ||
          name == _packageName && !_isEmptyRow(_fastCurrent);
    }).toList();

    final summarySheet = workbook.worksheets[0];
    summarySheet.name = '返厂面积汇总';
    _fillFastSummarySheet(summarySheet, project, packageNames, scopedRows);
    for (final packageName in packageNames) {
      final sheet = workbook.worksheets.addWithName(packageName);
      final rows = [
        ...scopedRows[packageName] ?? const <Map<String, String>>[],
        if (packageName == _packageName && !_isEmptyRow(_fastCurrent))
          _fastCurrent,
      ];
      _fillFastPackageSheet(sheet, project, packageName, rows);
    }
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }

  void _fillFastSummarySheet(
    xlsio.Worksheet sheet,
    ProjectEntity project,
    List<String> packageNames,
    Map<String, List<Map<String, String>>> scopedRows,
  ) {
    final building = project.buildingName.ifEmpty('1号楼');
    for (var col = 1; col <= 6; col++) {
      sheet.setColumnWidthInPixels(col, col == 1 ? 72 : 120);
    }
    void set(int row, int col, String value, {bool bold = false}) {
      final range = sheet.getRangeByIndex(row, col);
      range.setText(value);
      range.cellStyle.hAlign = xlsio.HAlignType.center;
      range.cellStyle.vAlign = xlsio.VAlignType.center;
      range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      range.cellStyle.bold = bold;
    }

    void merge(int r1, int c1, int r2, int c2) =>
        sheet.getRangeByIndex(r1, c1, r2, c2).merge();
    set(1, 1, '中建铝新材料成都有限公司', bold: true);
    merge(1, 1, 1, 6);
    set(2, 1, '返厂面积汇总表', bold: true);
    merge(2, 1, 2, 6);
    set(3, 1, '项目名称', bold: true);
    set(3, 2, project.name);
    merge(3, 2, 3, 3);
    set(3, 4, '楼栋号：', bold: true);
    set(3, 5, building);
    merge(3, 5, 3, 6);
    set(4, 1, '包数合计', bold: true);
    set(4, 2, packageNames.length.toString());
    merge(4, 2, 4, 3);
    set(4, 4, '打包日期', bold: true);
    set(4, 5, _todayText());
    merge(4, 5, 4, 6);
    const headers = ['序号', '包号', '角铝长度（m）', '模板数量（件）', '合计面积（㎡）', '备注'];
    for (var i = 0; i < headers.length; i++) {
      set(5, i + 1, headers[i], bold: true);
    }
    var totalAngleLength = 0.0;
    var totalQuantity = 0;
    var totalArea = 0.0;
    for (var i = 0; i < packageNames.length; i++) {
      final name = packageNames[i];
      final rows = [
        ...scopedRows[name] ?? const <Map<String, String>>[],
        if (name == _packageName && !_isEmptyRow(_fastCurrent)) _fastCurrent,
      ];
      final angleLength = _fastAngleLengthMeter(rows);
      final quantity = _sum(rows, 'quantity');
      final area = _fastArea(rows);
      totalAngleLength += angleLength;
      totalQuantity += quantity;
      totalArea += area;
      final rowIndex = i + 6;
      set(rowIndex, 1, '${i + 1}');
      set(rowIndex, 2, name);
      set(rowIndex, 3, _formatFastSummaryNumber(angleLength));
      set(rowIndex, 4, quantity.toString());
      set(rowIndex, 5, area.toStringAsFixed(2));
      set(rowIndex, 6, '');
    }
    final totalRow = packageNames.length + 6;
    set(totalRow, 1, '合计', bold: true);
    merge(totalRow, 1, totalRow, 2);
    set(totalRow, 3, _formatFastSummaryNumber(totalAngleLength), bold: true);
    set(totalRow, 4, totalQuantity.toString(), bold: true);
    set(totalRow, 5, totalArea.toStringAsFixed(2), bold: true);
    set(totalRow, 6, '', bold: true);
    final signRow = totalRow + 1;
    set(signRow, 1, '项目记录人：', bold: true);
    merge(signRow, 1, signRow, 3);
    set(signRow, 4, '中建铝记录人：', bold: true);
    merge(signRow, 4, signRow, 6);
  }

  void _fillFastPackageSheet(
    xlsio.Worksheet sheet,
    ProjectEntity project,
    String packageName,
    List<Map<String, String>> rows,
  ) {
    final building = project.buildingName.ifEmpty('1号楼');
    for (var col = 1; col <= 9; col++) {
      sheet.setColumnWidthInPixels(col, col == 1 ? 72 : 112);
    }
    void set(int row, int col, String value, {bool bold = false}) {
      final range = sheet.getRangeByIndex(row, col);
      range.setText(value);
      range.cellStyle.hAlign = xlsio.HAlignType.center;
      range.cellStyle.vAlign = xlsio.VAlignType.center;
      range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      range.cellStyle.bold = bold;
    }

    void merge(int r1, int c1, int r2, int c2) =>
        sheet.getRangeByIndex(r1, c1, r2, c2).merge();
    set(1, 1, '中建铝新材料成都有限公司', bold: true);
    merge(1, 1, 1, 9);
    set(2, 1, '返厂铝件登记表', bold: true);
    merge(2, 1, 2, 9);
    set(3, 1, '项目名称', bold: true);
    set(3, 3, project.name);
    merge(3, 1, 3, 2);
    merge(3, 3, 3, 5);
    set(3, 6, '楼栋号：', bold: true);
    set(3, 7, building);
    merge(3, 7, 3, 9);
    set(4, 1, '包  号', bold: true);
    set(4, 3, packageName);
    merge(4, 1, 4, 2);
    merge(4, 3, 4, 5);
    set(4, 6, '打包日期', bold: true);
    set(4, 7, _todayText());
    merge(4, 7, 4, 9);
    const headers = [
      '序号',
      '材料名称',
      '宽度',
      '型号',
      '长度',
      '数量（件）',
      '单位面积（㎡）',
      '合计面积（㎡）',
      '备注',
    ];
    for (var i = 0; i < headers.length; i++) {
      set(5, i + 1, headers[i], bold: true);
    }
    var totalQuantity = 0;
    var totalUnitArea = 0.0;
    var totalArea = 0.0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final quantity = _fastQuantity(row);
      final unitArea = _fastUnitArea(row);
      final area = unitArea * quantity;
      totalQuantity += quantity;
      totalUnitArea += unitArea;
      totalArea += area;
      final rowIndex = i + 6;
      set(rowIndex, 1, '${i + 1}');
      set(rowIndex, 2, '铝模');
      set(rowIndex, 3, row['width'].orEmpty());
      set(rowIndex, 4, row['model'].orEmpty());
      set(rowIndex, 5, row['length'].orEmpty());
      set(rowIndex, 6, quantity.toString());
      set(rowIndex, 7, unitArea.toStringAsFixed(2));
      set(rowIndex, 8, area.toStringAsFixed(2));
      set(rowIndex, 9, '');
    }
    final totalRow = rows.length + 6;
    set(totalRow, 1, '合计', bold: true);
    merge(totalRow, 1, totalRow, 2);
    set(totalRow, 6, totalQuantity.toString(), bold: true);
    set(totalRow, 7, totalUnitArea.toStringAsFixed(2), bold: true);
    set(totalRow, 8, totalArea.toStringAsFixed(2), bold: true);
    set(totalRow, 9, '', bold: true);
    final signRow = totalRow + 1;
    set(signRow, 1, '项目记录人：', bold: true);
    merge(signRow, 1, signRow, 5);
    set(signRow, 6, '中建铝记录人：', bold: true);
    merge(signRow, 6, signRow, 9);
  }

  List<int> _buildStandardExcel(ProjectEntity project) {
    final workbook = xlsio.Workbook();
    final building = project.buildingName.ifEmpty('1号楼');
    final scopedRows = _readScopedData(project.standardContent, building);
    final packageNames = scopedRows.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => entry.key)
        .toList();
    if (packageNames.isEmpty) {
      workbook.worksheets[0].name = '无数据';
      workbook.worksheets[0].getRangeByIndex(1, 1).setText('暂无数据');
    } else {
      for (var i = 0; i < packageNames.length; i++) {
        final packageName = packageNames[i];
        final sheet = i == 0
            ? workbook.worksheets[0]
            : workbook.worksheets.addWithName(packageName);
        sheet.name = packageName;
        _fillModeSheet(
          sheet: sheet,
          project: project,
          mode: MainMode.standard,
          scopeName: packageName,
          rows: scopedRows[packageName] ?? const <Map<String, String>>[],
        );
      }
    }
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }

  List<int> _buildCurrentModeExcel(
    ProjectEntity project,
    List<Map<String, String>> rows,
  ) {
    if (_mode == MainMode.fast) return _buildFastReturnExcel(project);
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    _fillModeSheet(
      sheet: sheet,
      project: project,
      mode: _mode,
      scopeName: _scopeName,
      rows: rows,
    );
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }

  void _fillModeSheet({
    required xlsio.Worksheet sheet,
    required ProjectEntity project,
    required MainMode mode,
    required String scopeName,
    required List<Map<String, String>> rows,
  }) {
    sheet.name = mode == MainMode.standard ? scopeName : mode.label;
    final columns = _columnsForMode(mode);
    final lastColumn = columns.length + 1;

    void set(int row, int col, String value, {bool bold = false}) {
      final range = sheet.getRangeByIndex(row, col);
      range.setText(value);
      range.cellStyle.hAlign = xlsio.HAlignType.center;
      range.cellStyle.vAlign = xlsio.VAlignType.center;
      range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      range.cellStyle.bold = bold;
    }

    void merge(int row1, int col1, int row2, int col2) {
      if (col2 > col1 || row2 > row1) {
        sheet.getRangeByIndex(row1, col1, row2, col2).merge();
      }
    }

    for (var col = 1; col <= lastColumn; col++) {
      sheet.setColumnWidthInPixels(col, col == 1 ? 72 : 112);
    }

    set(1, 1, '中建铝新材料有限公司', bold: true);
    merge(1, 1, 1, lastColumn);
    set(2, 1, mode == MainMode.standard ? '型号统计登记表' : '返厂面积统计表', bold: true);
    merge(2, 1, 2, lastColumn);
    set(3, 1, '项目名称');
    set(3, 2, project.name);
    merge(3, 2, 3, lastColumn >= 3 ? 3 : 2);
    set(3, lastColumn - 1, '楼栋');
    set(3, lastColumn, project.buildingName.ifEmpty('1号楼'));
    set(4, 1, mode.scopeLabel);
    set(4, 2, scopeName);
    merge(4, 2, 4, lastColumn >= 3 ? 3 : 2);
    set(4, lastColumn - 1, '导出时间');
    set(4, lastColumn, DateTime.now().toString().split('.').first);

    set(5, 1, '序号', bold: true);
    for (var i = 0; i < columns.length; i++) {
      set(5, i + 2, columns[i].label, bold: true);
    }
    for (var r = 0; r < rows.length; r++) {
      set(r + 6, 1, '${r + 1}');
      for (var c = 0; c < columns.length; c++) {
        final column = columns[c];
        final cell = sheet.getRangeByIndex(r + 6, c + 2);
        cell.cellStyle.hAlign = xlsio.HAlignType.center;
        cell.cellStyle.vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        final value = rows[r][column.key] ?? '';
        if (column.number) {
          cell.setNumber(_parseDouble(value));
        } else {
          cell.setText(value);
        }
      }
    }
    final totalRow = rows.length + 6;
    set(totalRow, 1, _summaryPrimaryTextForMode(mode, rows), bold: true);
    merge(totalRow, 1, totalRow, lastColumn);
    final secondaryText = _summarySecondaryTextForMode(mode, rows);
    if (secondaryText.isNotEmpty) {
      final secondRow = totalRow + 1;
      set(secondRow, 1, secondaryText, bold: true);
      merge(secondRow, 1, secondRow, lastColumn);
    }
    final signRow = totalRow + (secondaryText.isNotEmpty ? 2 : 1);
    set(signRow, 1, '统计人：');
    merge(signRow, 1, signRow, (lastColumn / 2).floor());
    set(signRow, (lastColumn / 2).floor() + 1, '确认人：');
    merge(signRow, (lastColumn / 2).floor() + 1, signRow, lastColumn);
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    if (_loading || project == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final rows = _rows;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Column(
            children: [
              _TopMenu(
                projectLabel: '项目',
                buildingLabel: project.buildingName.isEmpty
                    ? '楼栋'
                    : _topButtonLabel(project.buildingName),
                scopeLabel: _topButtonLabel(_scopeName),
                avatarText: _avatarText,
                onProject: _showProjectMenu,
                onBuilding: _showBuildingMenu,
                onScope: _editScope,
                onMore: _showMoreMenu,
                onAvatar: _showAccountMenu,
              ),
              const SizedBox(height: 2),
              _ProjectBar(
                projectName: project.name,
                modeLabel: '切换模式',
                connectCodeLabel: _subDisplayButtonText(),
                showConnectCode: false,
                onConnectCode: _showSubDisplayDialog,
                onMode: _showModePicker,
              ),
              const SizedBox(height: 4),
              Expanded(
                flex: 31,
                child: _mode == MainMode.loading
                    ? _LoadingDisplayCard(
                        rows: rows,
                        currentRow: _loadingCurrent,
                        currentKey: _currentKey,
                        editingRowIndex: _editingLoadingRowIndex,
                        aluminumPackageTitle: _loadingAluminumUsePackageCount
                            ? '包数'
                            : '包号',
                        aluminumWeightTitle: _loadingWeightHeader(true),
                        aluminumUseWeighbridge:
                            _loadingAluminumWeightMode == 'WEIGHBRIDGE_TOTAL',
                        summaryPrimary: _summaryPrimaryText(_summaryRows(rows)),
                        summarySecondary: _summarySecondaryText(
                          _summaryRows(rows),
                        ),
                        onDelete: _deleteRow,
                        onSelectField: _selectFieldByKey,
                        onPackageHeader: _showLoadingAluminumColumnModeDialog,
                        onWeightHeader: () =>
                            _showLoadingWeightModeDialog(aluminum: true),
                      )
                    : _DisplayCard(
                        mode: _mode,
                        rows: rows,
                        currentRow: _currentRow,
                        currentKey: _currentKey,
                        summaryPrimary: _summaryPrimaryText(_summaryRows(rows)),
                        summarySecondary: _summarySecondaryText(
                          _summaryRows(rows),
                        ),
                        editingRowIndex: _editingRowIndex,
                        showIndexColumn: _mode != MainMode.quality,
                        allowDelete: _mode != MainMode.quality,
                        onDelete: _deleteDisplayRow,
                        onSelectField: _selectFieldByKey,
                      ),
              ),
              const SizedBox(height: 6),
              Expanded(flex: 69, child: _modePanel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modePanel() {
    return switch (_mode) {
      MainMode.standard => _StandardKeyboard(
        onToken: _appendToken,
        onSymbol: _showSymbolDialog,
        onBackspace: _backspace,
        onNewColumn: _nextColumn,
        onNewLine: _newLine,
      ),
      MainMode.fast => _FastKeyboard(
        onToken: _appendToken,
        onBackspace: _backspace,
        onNewColumn: _nextColumn,
        onNewLine: _newLine,
        voicePressed: _fastVoicePressed,
        onVoiceStart: _startFastVoiceHold,
        onVoiceEnd: () => unawaited(_finishFastVoiceHold()),
        onVoiceCancel: () => unawaited(_cancelFastVoiceHold()),
      ),
      MainMode.loading => _LoadingKeyboard(
        rows: _rows,
        currentRow: _loadingCurrent,
        currentKey: _currentKey,
        editingRowIndex: _editingLoadingRowIndex,
        ironWeightTitle: _loadingWeightHeader(false),
        ironUseWeighbridge: _loadingIronWeightMode == 'WEIGHBRIDGE_TOTAL',
        vehicleInfo: _vehicleInfoForCurrentTrip(),
        onToken: _appendToken,
        onBackspace: _backspace,
        onNewColumn: _nextColumn,
        onNewLine: _newLine,
        onAluminumMaterial: _showAluminumMaterialDialog,
        onIronMaterial: _showIronMaterialDialog,
        onVehicleInfo: _showVehicleInfoDialog,
        onDelete: _deleteRow,
        onSelectField: _selectFieldByKey,
        onIronWeightHeader: () => _showLoadingWeightModeDialog(aluminum: false),
        onDeductAluminumBox: _deductAluminumBoxWeight,
      ),
      MainMode.quality => _QualityKeyboard(
        onToken: _appendToken,
        onSymbol: _showSymbolDialog,
        onBackspace: _backspace,
        onNewColumn: _nextColumn,
        onNewLine: _newLine,
      ),
    };
  }

  void _startFastVoiceHold() {
    unawaited(_beginFastVoiceHold());
  }

  Future<void> _beginFastVoiceHold() async {
    if (_fastVoiceStarting || _fastVoiceListening || _fastVoiceWaitingResult) {
      _showNotReady('语音识别正在进行中');
      return;
    }
    final holdGeneration = ++_fastVoiceHoldGeneration;
    setState(() {
      _fastVoicePressed = true;
      _fastVoiceStarting = true;
      _fastVoicePressStartedAt = DateTime.now();
    });
    try {
      await _fastVoiceChannel.invokeMethod<void>('startListening');
      if (!mounted || holdGeneration != _fastVoiceHoldGeneration) return;
      if (!_fastVoicePressed) {
        setState(() {
          _fastVoiceStarting = false;
          _fastVoiceListening = false;
          _fastVoicePressStartedAt = null;
        });
        await _fastVoiceChannel.invokeMethod<void>('cancelListening');
        return;
      }
      setState(() {
        _fastVoiceStarting = false;
        _fastVoiceListening = true;
      });
      _showFastVoiceHoldDialog();
      _fastVoiceTimeoutTimer?.cancel();
      _fastVoiceTimeoutTimer = Timer(
        const Duration(seconds: 12),
        () => unawaited(_finishFastVoiceHold(timedOut: true)),
      );
    } catch (error) {
      _fastVoiceTimeoutTimer?.cancel();
      _dismissFastVoiceHoldDialog();
      if (!mounted || holdGeneration != _fastVoiceHoldGeneration) return;
      setState(() {
        _fastVoicePressed = false;
        _fastVoiceStarting = false;
        _fastVoiceListening = false;
        _fastVoiceWaitingResult = false;
        _fastVoicePressStartedAt = null;
      });
      _showNotReady(_fastVoiceErrorMessage(error));
    }
  }

  Future<void> _finishFastVoiceHold({bool timedOut = false}) async {
    if (!_fastVoiceStarting && !_fastVoiceListening && !_fastVoicePressed) {
      _dismissFastVoiceHoldDialog();
      return;
    }
    final startedAt = _fastVoicePressStartedAt;
    final tooShort = !timedOut &&
        startedAt != null &&
        DateTime.now().difference(startedAt).inMilliseconds < 300;
    _fastVoiceTimeoutTimer?.cancel();
    if (tooShort || _fastVoiceStarting) {
      await _cancelFastVoiceHold(showTooShortToast: tooShort);
      return;
    }
    setState(() {
      _fastVoicePressed = false;
      _fastVoiceStarting = false;
      _fastVoiceListening = false;
      _fastVoiceWaitingResult = true;
      _fastVoicePressStartedAt = null;
    });
    try {
      final text = await _fastVoiceChannel.invokeMethod<String>('stopListening');
      _dismissFastVoiceHoldDialog();
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        _showNotReady('未识别到清晰语音');
        return;
      }
      await _applyFastVoiceText(text);
    } catch (error) {
      _dismissFastVoiceHoldDialog();
      if (mounted) _showNotReady(_fastVoiceErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _fastVoicePressed = false;
          _fastVoiceStarting = false;
          _fastVoiceListening = false;
          _fastVoiceWaitingResult = false;
          _fastVoicePressStartedAt = null;
        });
      }
    }
  }

  Future<void> _cancelFastVoiceHold({bool showTooShortToast = false}) async {
    _fastVoiceHoldGeneration++;
    _fastVoiceTimeoutTimer?.cancel();
    try {
      await _fastVoiceChannel.invokeMethod<void>('cancelListening');
    } catch (_) {}
    _dismissFastVoiceHoldDialog();
    if (!mounted) return;
    setState(() {
      _fastVoicePressed = false;
      _fastVoiceStarting = false;
      _fastVoiceListening = false;
      _fastVoiceWaitingResult = false;
      _fastVoicePressStartedAt = null;
    });
    if (showTooShortToast) {
      _showNotReady('请长按后说话');
    }
  }

  void _showFastVoiceHoldDialog() {
    if (_fastVoiceDialogVisible || !mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _fastVoiceDialogVisible = true;
    _fastVoiceDialogEntry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Material(
          color: Colors.black.withValues(alpha: 0.28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '正在收听',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '松开按钮后开始识别',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 14),
                    _FastVoiceHoldDialogBody(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_fastVoiceDialogEntry!);
  }

  void _dismissFastVoiceHoldDialog() {
    if (!_fastVoiceDialogVisible) return;
    _fastVoiceDialogVisible = false;
    _fastVoiceDialogEntry?.remove();
    _fastVoiceDialogEntry = null;
  }

  Future<void> _applyFastVoiceText(String text) async {
    final pair = _parseFastVoiceSizePair(text);
    if (pair == null) {
      _showNotReady('未识别到尺寸格式，请说类似‘200乘300’或‘400乘1米1’');
      return;
    }
    final width = double.tryParse(pair.$1) ?? 0;
    final length = double.tryParse(pair.$2) ?? 0;
    if (width <= 0 || length <= 0 || width > 600 || length > 4500) {
      _showNotReady('识别成功，但尺寸超出当前 FAST 可录入范围');
      return;
    }
    setState(() {
      _fastCurrent['width'] = pair.$1;
      _fastCurrent['length'] = pair.$2;
      _fastField = FastField.width;
    });
    await _finishCurrentRow();
  }

  String _fastVoiceErrorMessage(Object error) {
    if (error is PlatformException) {
      return switch (error.code) {
        'permission_denied' => '未授予录音权限，无法使用语音识别',
        'speech_permission_denied' => '未授予语音识别权限，无法使用语音识别',
        'unavailable' => '当前设备不支持系统语音识别',
        'start_failed' => '语音识别启动失败，请稍后重试',
        _ => error.message?.ifBlank('语音识别失败，请检查录音权限和系统语音服务') ??
            '语音识别失败，请检查录音权限和系统语音服务',
      };
    }
    if (error is MissingPluginException) {
      return '当前平台暂不支持语音识别';
    }
    return '语音识别失败，请检查录音权限和系统语音服务';
  }

  (String, String)? _parseFastVoiceSizePair(String text) {
    final normalized = text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('乘以', '乘')
        .replaceAll('乘号', '乘')
        .replaceAll('成', '乘')
        .replaceAll('＊', '乘')
        .replaceAll('×', '乘')
        .replaceAll('*', '乘')
        .replaceAll('x', '乘')
        .replaceAll('X', '乘')
        .replaceAll('公分', '厘米')
        .replaceAll('cm', '厘米')
        .replaceAll('CM', '厘米')
        .replaceAll('mm', '毫米')
        .replaceAll('MM', '毫米')
        .replaceAll('m', '米')
        .replaceAll('M', '米');
    final parts = normalized.split('乘');
    if (parts.length != 2) return null;
    final width = _parseFastVoiceDimension(parts[0]);
    final length = _parseFastVoiceDimension(parts[1]);
    if (width == null || length == null) return null;
    return (
      _formatFastVoiceDimension(width),
      _formatFastVoiceDimension(length),
    );
  }

  double? _parseFastVoiceDimension(String text) {
    if (text.isEmpty || text == '.') return null;
    if (text.endsWith('毫米')) {
      return double.tryParse(text.substring(0, text.length - 2));
    }
    if (text.endsWith('厘米')) {
      final value = double.tryParse(text.substring(0, text.length - 2));
      return value == null ? null : value * 10;
    }
    if (text.contains('米')) {
      final segments = text.split('米');
      if (segments.length != 2) return null;
      final meters = double.tryParse(segments[0].ifBlank('0'));
      if (meters == null) return null;
      final tail = segments[1];
      if (tail.isEmpty) return meters * 1000;
      if (segments[0].contains('.')) return null;
      final decimal = double.tryParse('0.$tail');
      return decimal == null ? null : (meters + decimal) * 1000;
    }
    return double.tryParse(text);
  }

  String _formatFastVoiceDimension(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  Future<void> _showSubDisplayDialog() async {
    try {
      if (_subDisplayCode.isEmpty) {
        final response = await _serverRepository.generateSubDisplayCode();
        final code = response.data?.code ?? '';
        if (!response.isSuccess || code.isEmpty) {
          _showNotReady(response.displayMessage.ifEmpty('连接码生成失败'));
          return;
        }
        _subDisplayCode = code;
        _lastSubDisplayPayload = null;
        await _saveMainState();
        _syncSubDisplayPolling();
      }
      final status = await _serverRepository.getSubDisplayStatus(
        _subDisplayCode,
      );
      if (!mounted) return;
      if (!status.isSuccess) {
        final message = status.displayMessage;
        if (message.contains('失效') ||
            message.contains('过期') ||
            message.contains('不存在')) {
          _clearSubDisplayCode(message);
        } else {
          _showNotReady(message.ifEmpty('连接状态刷新失败'));
        }
        return;
      }
      setState(() {
        _subDisplayConnected = status.data?.connected == true;
        _subDisplaySessionCount = status.data?.sessionCount ?? 0;
      });
      await showAppCardDialog<void>(
        context: context,
        title: '子软件连接',
        subtitle: _subDisplayConnected == true
            ? '已连接 $_subDisplaySessionCount 台设备'
            : '等待子软件连接',
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '连接码：$_subDisplayCode\n连接状态：${_subDisplayConnected == true ? '已连接' : '未连接'}\n设备数量：$_subDisplaySessionCount',
            ),
            const SizedBox(height: 12),
            AppDialogActionButton(
              text: '复制连接码',
              primary: false,
              onPressed: () {
                final code = _subDisplayCode;
                Navigator.of(context).pop();
                Clipboard.setData(ClipboardData(text: code));
                showAppToast(this.context, '连接码已复制');
              },
            ),
            const SizedBox(height: 16),
            AppDialogActionRow(
              cancelText: '关闭',
              confirmText: '推送返厂数据',
              onCancel: () => Navigator.of(context).pop(),
              onConfirm: () {
                Navigator.of(context).pop();
                _pushFastSnapshotToSubDisplay();
              },
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _showNotReady('连接码操作失败，请检查网络和登录状态');
    }
  }

  Future<void> _pushFastSnapshotToSubDisplay({bool force = false}) async {
    if (_subDisplayCode.isEmpty) return;
    final project = _project;
    if (project == null) return;
    final scopedRows = _readScopedData(
      project.fastContent,
      _currentBuildingName,
    );
    final rows = scopedRows[_packageName] ?? const <Map<String, String>>[];
    final packageNames = <String>{_packageName, ...scopedRows.keys};
    final packages = packageNames
        .map((packageName) {
          return {
            'packageName': packageName,
            'savedRows':
                scopedRows[packageName] ?? const <Map<String, String>>[],
            'currentRow': packageName == _packageName
                ? _fastCurrent
                : _emptyFastRow(),
          };
        })
        .where((packageData) {
          final savedRows = packageData['savedRows'];
          final currentRow = packageData['currentRow'];
          return savedRows is List && savedRows.isNotEmpty ||
              currentRow is Map<String, String> && !_isEmptyRow(currentRow);
        })
        .toList();
    final summaryRows = _summaryRows(rows);
    final payload = {
      'projectName': project.name,
      'buildingName': project.buildingName,
      'currentPackageName': _packageName,
      'packages': packages,
      'summary': {
        'totalArea': _fastArea(summaryRows).toStringAsFixed(2),
        'totalQuantity': _sum(summaryRows, 'quantity').toString(),
      },
      'clientTime': DateTime.now().toIso8601String(),
      'payloadVersion': 1,
    };
    final payloadHash = jsonEncode(payload);
    if (!force && payloadHash == _lastSubDisplayPayload) return;
    try {
      final response = await _serverRepository.pushReturnData(
        code: _subDisplayCode,
        payload: payload,
      );
      if (response.isSuccess) {
        _lastSubDisplayPayload = payloadHash;
        if (!mounted) return;
        setState(() {
          _subDisplayConnected =
              response.data?.connected == true ||
              (response.data?.sessionCount ?? 0) > 0;
          _subDisplaySessionCount =
              response.data?.sessionCount ?? _subDisplaySessionCount;
        });
        _showNotReady('返厂数据已推送');
        return;
      }
      final message = response.displayMessage;
      if (message.contains('失效') ||
          message.contains('过期') ||
          message.contains('不存在')) {
        _clearSubDisplayCode(message);
      } else if (mounted) {
        _showNotReady(message.ifEmpty('返厂数据推送失败'));
      }
    } catch (error) {
      if (mounted) _showNotReady('返厂数据推送失败，请检查网络');
    }
  }

  Future<void> _showQualityMaterialTypeDialog() async {
    final selected = await _showOptionDialog(
      title: '选择材料类型',
      options: _qualityMaterialTypes,
    );
    if (selected == null) return;
    setState(() {
      _qualityCurrent['materialType'] = selected;
      final qualityType = _qualityCurrent['qualityType'].orEmpty();
      if (qualityType.isNotEmpty) {
        _qualityCurrent['description'] = _buildQualityFeedbackDesc(
          materialType: selected,
          qualityType: qualityType,
        );
      }
      _qualityField = QualityField.installNumber;
    });
    await _saveQualityEditedRow(_qualityCurrent);
  }

  Future<void> _showQualityTypeDialog() async {
    final selected = await _showOptionDialog(
      title: '选择质量类型',
      options: _qualityTypes,
    );
    if (selected == null) return;
    setState(() {
      _qualityCurrent['qualityType'] = selected;
      _qualityCurrent['description'] = _buildQualityFeedbackDesc(
        materialType: _qualityCurrent['materialType'].orEmpty(),
        qualityType: selected,
      );
      _qualityField = QualityField.installNumber;
    });
    await _saveQualityEditedRow(_qualityCurrent);
  }

  Future<void> _showQualityDescriptionEditor() async {
    final controller = TextEditingController(
      text: _qualityCurrent['description'].orEmpty(),
    );
    final value = await showAppCardDialog<String>(
      context: context,
      title: '编辑反馈说明',
      subtitle: '填写质量问题描述',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            minLines: 6,
            maxLines: 8,
            decoration: const InputDecoration(labelText: '反馈内容'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppDialogActionButton(
                  text: '清空',
                  primary: false,
                  onPressed: () => controller.clear(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppDialogActionButton(
                  text: '取消',
                  primary: false,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppDialogActionButton(
                  text: '确定',
                  onPressed: () => Navigator.of(context).pop(controller.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    setState(() {
      _qualityCurrent['description'] = value.trim();
      _qualityField = QualityField.installNumber;
    });
    await _saveQualityEditedRow(_qualityCurrent);
  }

  Future<void> _showSymbolDialog() async {
    final selected = await showAppMenuCardPopup<String>(
      context: context,
      title: '符号',
      subtitle: '选择要输入的符号',
      children: [
        for (final symbol in ['+', '-', '/', 'G', 'L', '()'])
          AppDialogListItem(
            label: symbol,
            onTap: () => Navigator.of(context).pop(symbol),
          ),
      ],
    );
    if (!mounted || selected == null) return;
    _appendToken(selected);
  }

  Future<String?> _showOptionDialog({
    required String title,
    String? subtitle,
    required List<String> options,
    String? current,
  }) {
    final currentValue =
        current ??
        (title.contains('材料')
            ? _qualityCurrent['materialType'].orEmpty()
            : _qualityCurrent['qualityType'].orEmpty());
    return showAppMenuCardPopup<String>(
      context: context,
      title: title,
      subtitle: subtitle ?? '选择后会写入当前质量反馈行',
      children: [
        for (final option in options)
          AppDialogListItem(
            label: option,
            selected: option == currentValue,
            onTap: () => Navigator.of(context).pop(option),
          ),
      ],
    );
  }

  Future<void> _showQualityPhotoPreview(String photoUris) async {
    final photos = photoUris
        .split('|')
        .where((uri) => uri.trim().isNotEmpty)
        .toList();
    if (photos.isEmpty) {
      _showNotReady('当前没有附图');
      return;
    }
    final imageWidgets = await Future.wait(
      photos.map((uri) async {
        try {
          final base64 = await _exportChannel.invokeMethod<String>(
            'readBytesBase64',
            {'uri': uri},
          );
          if (base64 == null || base64.isEmpty) return null;
          return Image.memory(base64Decode(base64), fit: BoxFit.cover);
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;
    await showAppCardDialog<void>(
      context: context,
      title: '附图预览',
      subtitle: '共 ${photos.length} 张',
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child:
                            imageWidgets[i] ??
                            Center(
                              child: Text(
                                '第${i + 1}张',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showQualityPhotoMenu() async {
    final photoCount = _qualityCurrent['photoUris']
        .orEmpty()
        .split('|')
        .where((uri) => uri.trim().isNotEmpty)
        .length;
    final selected = await showAppMenuCardPopup<String>(
      context: context,
      title: '附图',
      subtitle: photoCount == 0 ? '当前未添加附图' : '当前已有 $photoCount 张附图',
      children: [
        AppDialogListItem(
          label: '拍照',
          subtitle: '调用相机添加现场照片',
          accent: true,
          onTap: () => Navigator.of(context).pop('camera'),
        ),
        AppDialogListItem(
          label: '从相册添加',
          subtitle: '选择已有图片作为附图',
          onTap: () => Navigator.of(context).pop('gallery'),
        ),
        AppDialogListItem(
          label: '预览附图',
          subtitle: photoCount == 0 ? '当前没有可预览的附图' : '查看当前行已有附图',
          onTap: () => Navigator.of(context).pop('preview'),
        ),
        AppDialogListItem(
          label: '删除附图',
          subtitle: photoCount == 0 ? '当前没有可删除的附图' : '选择单张删除或清空全部',
          danger: true,
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    );
    switch (selected) {
      case 'camera':
        await _addQualityPhoto(takePhoto: true);
      case 'gallery':
        await _addQualityPhoto(takePhoto: false);
      case 'preview':
        await _showQualityPhotoPreview(_qualityCurrent['photoUris'].orEmpty());
      case 'delete':
        await _deleteQualityPhotos();
    }
  }

  Future<void> _deleteQualityPhotos() async {
    final photos = _qualityCurrent['photoUris']
        .orEmpty()
        .split('|')
        .where((uri) => uri.trim().isNotEmpty)
        .toList();
    if (photos.isEmpty) {
      _showNotReady('当前没有附图');
      return;
    }
    final selected = await showAppMenuCardPopup<int>(
      context: context,
      title: '删除附图',
      subtitle: '当前已有 ${photos.length} 张附图',
      children: [
        for (var i = 0; i < photos.length; i++)
          AppDialogListItem(
            label: '删除第 ${i + 1} 张',
            subtitle: photos[i],
            danger: true,
            onTap: () => Navigator.of(context).pop(i),
          ),
        AppDialogListItem(
          label: '清空全部附图',
          subtitle: '删除当前行所有附图',
          danger: true,
          onTap: () => Navigator.of(context).pop(-1),
        ),
      ],
    );
    if (selected == null) return;
    final updated = selected < 0
        ? <String>[]
        : [
            for (var i = 0; i < photos.length; i++)
              if (i != selected) photos[i],
          ];
    setState(() {
      _qualityCurrent['photoUris'] = updated.join('|');
      _qualityField = QualityField.installNumber;
    });
    await _saveQualityEditedRow(_qualityCurrent);
  }

  Future<void> _addQualityPhoto({required bool takePhoto}) async {
    if (_mode != MainMode.quality) return;
    try {
      final uri = await _photoChannel.invokeMethod<String>(
        takePhoto ? 'takePhoto' : 'pickPhoto',
      );
      if (uri == null || uri.isEmpty) return;
      setState(() {
        final existing = _qualityCurrent['photoUris'].orEmpty();
        _qualityCurrent['photoUris'] = existing.isEmpty
            ? uri
            : '$existing|$uri';
      });
      await _saveQualityEditedRow(_qualityCurrent);
      if (mounted) _showNotReady('附图已添加');
    } catch (error) {
      if (mounted) _showNotReady('附图添加失败，请检查权限');
    }
  }

  Future<void> _showVehicleInfoDialog() async {
    _vehicleInfo = _vehicleInfoForCurrentTrip();
    final controllers = {
      for (final entry in _vehicleInfo.entries)
        entry.key: TextEditingController(text: entry.value),
    };
    await showAppCardDialog<void>(
      context: context,
      title: '过磅信息',
      subtitle: '当前车次：$_tripName',
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double value(String key) => _parseDouble(controllers[key]?.text);
          final gross = value('grossWeight');
          final tare = value('tareWeight');
          final wood = value('woodEstimate');
          final middleAluminum = controllers['middleAluminumWeight']!.text
              .trim();
          final middleIron = controllers['middleIronWeight']!.text.trim();
          final middleAluminumValue = double.tryParse(middleAluminum);
          final middleIronValue = double.tryParse(middleIron);
          final netWeight = gross - tare - wood;
          final aluminumWeight = middleAluminumValue != null
              ? middleAluminumValue - tare
              : (middleIronValue != null ? gross - middleIronValue : 0.0);
          final ironWeight = middleAluminumValue != null
              ? gross - middleAluminumValue
              : (middleIronValue != null ? middleIronValue - tare : 0.0);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _VehicleInput(
                    controller: controllers['vehiclePlateNumber']!,
                    label: '运输车牌号',
                  ),
                  _VehicleInput(
                    controller: controllers['loadingDate']!,
                    label: '装车时间',
                  ),
                  _VehicleInput(
                    controller: controllers['grossWeight']!,
                    label: '装车毛重',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  _VehicleInput(
                    controller: controllers['tareWeight']!,
                    label: '车辆皮重',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  _VehicleInput(
                    controller: controllers['middleAluminumWeight']!,
                    label: '中途铝重',
                    enabled: middleIron.isEmpty,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  _VehicleInput(
                    controller: controllers['middleIronWeight']!,
                    label: '中途铁重',
                    enabled: middleAluminum.isEmpty,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  _VehicleInput(
                    controller: controllers['woodEstimate']!,
                    label: '木方估算',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  _VehicleReadonly(
                    label: '装车净重',
                    value: _formatNumber(netWeight),
                  ),
                  _VehicleReadonly(
                    label: '铝模重量',
                    value: _formatNumber(aluminumWeight),
                  ),
                  _VehicleReadonly(
                    label: '铁件重量',
                    value: _formatNumber(ironWeight),
                  ),
                  const SizedBox(height: 8),
                  AppDialogActionRow(
                    onCancel: () => Navigator.of(context).pop(),
                    confirmText: '保存',
                    onConfirm: () {
                      setState(() {
                        _vehicleInfo = {
                          for (final entry in controllers.entries)
                            entry.key: entry.value.text.trim(),
                        };
                      });
                      _saveLoadingMetaOnly();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _showModePicker(BuildContext anchorContext) async {
    const modeOrder = [
      MainMode.fast,
      MainMode.standard,
      MainMode.loading,
      MainMode.quality,
    ];
    final selected = await _showAnchoredMenu<MainMode>(
      anchorContext: anchorContext,
      title: '切换模式',
      subtitle: '快速切换当前录入方式',
      children: [
        for (final mode in modeOrder)
          AppDialogListItem(
            label: mode.label,
            subtitle: mode.scopeLabel,
            selected: mode == _mode,
            onTap: () => Navigator.of(context).pop(mode),
          ),
      ],
    );
    if (selected != null && selected != _mode && mounted) {
      await _saveCurrentDraft();
      if (!mounted) return;
      setState(() => _mode = selected);
      await _saveMainState();
      _syncSubDisplayPolling();
      if (selected == MainMode.fast) _refreshSubDisplayStatus();
    }
  }

  void _selectFieldByKey(int? rowIndex, String key) {
    var openQualityMaterialType = false;
    var openQualityType = false;
    var openQualityDescription = false;
    var openQualityPhoto = false;

    setState(() {
      switch (_mode) {
        case MainMode.standard:
          _standardField = switch (key) {
            'installNumber' => StandardField.installNumber,
            'model' => StandardField.model,
            _ => StandardField.quantity,
          };
          _editingStandardRowIndex = rowIndex;
          _pendingReplaceStandardEditing = rowIndex != null;
          _standardCurrent = rowIndex == null
              ? _standardCurrent
              : Map<String, String>.from(_rows[rowIndex]);
        case MainMode.fast:
          _fastField = switch (key) {
            'width' => FastField.width,
            'model' => FastField.model,
            'length' => FastField.length,
            _ => FastField.quantity,
          };
          _editingFastRowIndex = rowIndex;
          _pendingReplaceFastEditing = rowIndex != null;
          _fastCurrent = rowIndex == null
              ? _fastCurrent
              : Map<String, String>.from(_rows[rowIndex]);
          _lastSubDisplayPayload = null;
        case MainMode.loading:
          _loadingField = LoadingField.values.firstWhere(
            (field) => field.name == key,
            orElse: () => LoadingField.material,
          );
          _editingLoadingRowIndex = rowIndex;
          _loadingCurrent = rowIndex == null
              ? _loadingCurrent
              : Map<String, String>.from(_rows[rowIndex]);
        case MainMode.quality:
          _qualityField = QualityField.values.firstWhere(
            (field) => field.name == key,
            orElse: () => QualityField.materialType,
          );
          _editingQualityRowIndex = rowIndex;
          _qualityCurrent = rowIndex == null
              ? _qualityCurrent
              : Map<String, String>.from(_rows[rowIndex]);
          openQualityMaterialType = key == 'materialType';
          openQualityType = key == 'qualityType';
          openQualityDescription = key == 'description';
          openQualityPhoto = key == 'photoUris';
      }
    });

    if (openQualityMaterialType) unawaited(_showQualityMaterialTypeDialog());
    if (openQualityType) unawaited(_showQualityTypeDialog());
    if (openQualityDescription) unawaited(_showQualityDescriptionEditor());
    if (openQualityPhoto) unawaited(_showQualityPhotoMenu());
  }

  List<Map<String, String>> _summaryRows(List<Map<String, String>> rows) {
    final current = Map<String, String>.from(_currentRow);
    if (_isEmptyRow(current)) return rows;
    return [...rows, current];
  }

  String _summaryPrimaryText(List<Map<String, String>> rows) =>
      _summaryPrimaryTextForMode(_mode, rows);

  String _summaryPrimaryTextForMode(
    MainMode mode,
    List<Map<String, String>> rows,
  ) {
    return switch (mode) {
      MainMode.standard => '合计数量：${_sum(rows, 'quantity')}',
      MainMode.fast => '合计面积：${_fastArea(rows).toStringAsFixed(2)}㎡',
      MainMode.loading =>
        '铝模单包称重合计：${_formatNumber(_loadingAluminumSummaryWeight(rows))}',
      MainMode.quality => '',
    };
  }

  String _summarySecondaryText(List<Map<String, String>> rows) =>
      _summarySecondaryTextForMode(_mode, rows);

  String _summarySecondaryTextForMode(
    MainMode mode,
    List<Map<String, String>> rows,
  ) {
    return switch (mode) {
      MainMode.fast => '合计数量：${_sum(rows, 'quantity')}',
      MainMode.loading =>
        '铝模过磅重量：${_formatNumber(_loadingAluminumWeighbridgeWeight())}',
      _ => '',
    };
  }
}

class _ServerProjectPickerBody extends StatefulWidget {
  const _ServerProjectPickerBody({required this.serverRepository});

  final ServerRepository serverRepository;

  @override
  State<_ServerProjectPickerBody> createState() =>
      _ServerProjectPickerBodyState();
}

class _ServerProjectPickerBodyState extends State<_ServerProjectPickerBody> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  var _loading = true;
  var _message = '请输入关键字搜索项目名称';
  var _projectNames = <String>[];
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjects(''));
  }

  @override
  void dispose() {
    _requestId++;
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _triggerSearch({bool immediate = false}) {
    _searchDebounce?.cancel();
    final keyword = _searchController.text.trim();
    if (immediate) {
      unawaited(_loadProjects(keyword));
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _loadProjects(keyword),
    );
  }

  Future<void> _loadProjects(String keyword) async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _message = '正在加载项目...';
      _projectNames = [];
    });
    try {
      final response = await widget.serverRepository.getProjectInfoList(
        keyword: keyword.trim(),
      );
      if (!mounted || requestId != _requestId) return;
      final names = (response.data ?? const <ServerProjectInfo>[])
          .map((item) => item.projectName.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      setState(() {
        _loading = false;
        _projectNames = response.isSuccess ? names : [];
        _message = response.isSuccess
            ? (names.isEmpty ? '未搜索到匹配项目' : '')
            : response.displayMessage.ifEmpty('加载项目失败');
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _projectNames = [];
        _message = '加载项目失败，请检查网络和登录状态';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '输入关键字搜索项目名称',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => _triggerSearch(),
                  onSubmitted: (_) => _triggerSearch(immediate: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _triggerSearch(immediate: true),
                child: const Text('搜索'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _projectNames.isEmpty
                ? Center(child: Text(_message))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _projectNames.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final name = _projectNames[index];
                      return AppDialogListItem(
                        label: name,
                        subtitle: '服务器项目',
                        onTap: () => Navigator.of(context).pop(name),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AppDialogActionButton(
              text: '关闭',
              primary: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnchoredMenuCard extends StatelessWidget {
  const _AnchoredMenuCard({
    required this.title,
    this.subtitle,
    required this.maxHeight,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final double maxHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFF8F5FF)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE4DAFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF211B31),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8572B8),
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primary,
                    Color(0xFFA98CF7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < children.length; index++) ...[
                      if (index > 0) const SizedBox(height: 9),
                      children[index],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogSectionTitle extends StatelessWidget {
  const _DialogSectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2, left: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF8572B8),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _AccountPopupCard extends StatelessWidget {
  const _AccountPopupCard({
    required this.username,
    required this.avatarText,
    required this.online,
    required this.connectionCountText,
    required this.subDisplayStatusText,
    required this.hasSubDisplayCode,
    required this.onViewDevices,
    required this.onSubDisplayCode,
    required this.onOpenBackend,
    required this.onRelogin,
    required this.onLogout,
  });

  final String username;
  final String avatarText;
  final bool online;
  final String connectionCountText;
  final String subDisplayStatusText;
  final bool hasSubDisplayCode;
  final VoidCallback onViewDevices;
  final VoidCallback onSubDisplayCode;
  final VoidCallback onOpenBackend;
  final VoidCallback onRelogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFF8F5FF)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4DAFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _AccountAvatar(text: avatarText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF2F2A3D),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      online ? '当前账号在线' : '当前账号离线',
                      style: const TextStyle(
                        color: Color(0xFF8A7AB8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(text: online ? '在线' : '离线', active: online),
              if (!online) ...[
                const SizedBox(width: 8),
                _AccountSmallButton(
                  text: '重新登录',
                  primary: true,
                  onTap: onRelogin,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _AccountInfoRow(
            label: '当前连接',
            value: connectionCountText,
            buttonText: '查看设备',
            primaryButton: false,
            onTap: onViewDevices,
          ),
          const SizedBox(height: 8),
          _AccountInfoRow(
            label: '子软件状态',
            valueWidget: _StatusPill(
              text: subDisplayStatusText,
              active: subDisplayStatusText == '已连接',
            ),
            buttonText: hasSubDisplayCode ? '查看连接码' : '生成连接码',
            primaryButton: !hasSubDisplayCode,
            onTap: onSubDisplayCode,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AccountLargeButton(
                  text: '访问后台',
                  primary: true,
                  onTap: onOpenBackend,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AccountLargeButton(text: '退出登录', onTap: onLogout),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [_legacyPurpleStart, Color(0xFF8B74D1)],
        ),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AccountInfoRow extends StatelessWidget {
  const _AccountInfoRow({
    required this.label,
    this.value,
    this.valueWidget,
    required this.buttonText,
    required this.primaryButton,
    required this.onTap,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final String buttonText;
  final bool primaryButton;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4DAFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8A7AB8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                valueWidget ??
                    Text(
                      value ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF2F2A3D),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _AccountSmallButton(
            text: buttonText,
            primary: primaryButton,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEAF8F0) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFFBFE7CF) : const Color(0xFFD7DCE2),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? const Color(0xFF2E8B57) : const Color(0xFF6B7280),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AccountSmallButton extends StatelessWidget {
  const _AccountSmallButton({
    required this.text,
    required this.onTap,
    this.primary = false,
  });

  final String text;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: _AccountButtonContent(text: text, primary: primary, onTap: onTap),
    );
  }
}

class _AccountLargeButton extends StatelessWidget {
  const _AccountLargeButton({
    required this.text,
    required this.onTap,
    this.primary = false,
  });

  final String text;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: _AccountButtonContent(text: text, primary: primary, onTap: onTap),
    );
  }
}

class _AccountButtonContent extends StatelessWidget {
  const _AccountButtonContent({
    required this.text,
    required this.primary,
    required this.onTap,
  });

  final String text;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: primary
            ? const LinearGradient(
                colors: [AppColors.primaryAlt, Color(0xFF8067C8)],
              )
            : null,
        color: primary ? null : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primary ? Colors.transparent : const Color(0xFFDCE3F1),
        ),
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: primary ? Colors.white : AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _TopMenu extends StatelessWidget {
  const _TopMenu({
    required this.projectLabel,
    required this.buildingLabel,
    required this.scopeLabel,
    required this.avatarText,
    required this.onProject,
    required this.onBuilding,
    required this.onScope,
    required this.onMore,
    required this.onAvatar,
  });
  final String projectLabel;
  final String buildingLabel;
  final String scopeLabel;
  final String avatarText;
  final void Function(BuildContext context) onProject;
  final void Function(BuildContext context) onBuilding;
  final void Function(BuildContext context) onScope;
  final void Function(BuildContext context) onMore;
  final void Function(BuildContext context) onAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: _groupDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: projectLabel,
                onPressed: () => onProject(buttonContext),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: buildingLabel,
                onPressed: () => onBuilding(buttonContext),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: scopeLabel,
                onPressed: () => onScope(buttonContext),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: '更多',
                onPressed: () => onMore(buttonContext),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Builder(
            builder: (avatarContext) => InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onAvatar(avatarContext),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_legacyPurpleStart, Color(0xFF8B74D1)],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    avatarText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectBar extends StatelessWidget {
  const _ProjectBar({
    required this.projectName,
    required this.modeLabel,
    required this.connectCodeLabel,
    required this.showConnectCode,
    required this.onConnectCode,
    required this.onMode,
  });
  final String projectName;
  final String modeLabel;
  final String connectCodeLabel;
  final bool showConnectCode;
  final VoidCallback onConnectCode;
  final void Function(BuildContext context) onMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
              child: Text(
                '当前项目：$projectName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (showConnectCode) ...[
            SizedBox(
              width: 96,
              height: 30,
              child: _PurpleButton(
                text: connectCodeLabel,
                onPressed: onConnectCode,
              ),
            ),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 86,
            height: 30,
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: modeLabel,
                onPressed: () => onMode(buttonContext),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _tableIndexColumnWidth = 40;

double _tableWidthFor(
  double availableWidth,
  int dataColumnCount, {
  bool showIndexColumn = true,
}) {
  return availableWidth;
}

double _tableDataColumnWidth(
  double tableWidth,
  int dataColumnCount, {
  bool showIndexColumn = true,
}) {
  final indexWidth = showIndexColumn ? _tableIndexColumnWidth : 0;
  return (tableWidth - indexWidth) / dataColumnCount;
}

class _DisplayCard extends StatefulWidget {
  const _DisplayCard({
    required this.mode,
    required this.rows,
    required this.currentRow,
    required this.currentKey,
    required this.editingRowIndex,
    required this.showIndexColumn,
    required this.allowDelete,
    required this.summaryPrimary,
    required this.summarySecondary,
    required this.onDelete,
    required this.onSelectField,
  });
  final MainMode mode;
  final List<Map<String, String>> rows;
  final Map<String, String> currentRow;
  final String currentKey;
  final int? editingRowIndex;
  final bool showIndexColumn;
  final bool allowDelete;
  final String summaryPrimary;
  final String summarySecondary;
  final ValueChanged<int?> onDelete;
  final void Function(int? index, String key) onSelectField;

  @override
  State<_DisplayCard> createState() => _DisplayCardState();
}

class _DisplayCardState extends State<_DisplayCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _DisplayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollToCurrentInputRow();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentInputRow() {
    if (widget.editingRowIndex != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columnsForMode(widget.mode);
    final editingIndex =
        widget.editingRowIndex != null &&
            widget.editingRowIndex! >= 0 &&
            widget.editingRowIndex! < widget.rows.length
        ? widget.editingRowIndex
        : null;
    final displayRows = [
      for (var index = 0; index < widget.rows.length; index++)
        index == editingIndex ? widget.currentRow : widget.rows[index],
      if (editingIndex == null) widget.currentRow,
    ];
    final selectedDisplayIndex = editingIndex ?? widget.rows.length;
    _scrollToCurrentInputRow();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: _groupDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = _tableWidthFor(
            constraints.maxWidth,
            columns.length,
            showIndexColumn: widget.showIndexColumn,
          );
          final dataColumnWidth = _tableDataColumnWidth(
            tableWidth,
            columns.length,
            showIndexColumn: widget.showIndexColumn,
          );
          return Column(
            children: [
              SizedBox(
                width: tableWidth,
                child: _TableLine(
                  rowNumber: null,
                  showIndexColumn: widget.showIndexColumn,
                  columns: columns,
                  row: null,
                  currentKey: widget.currentKey,
                  selectedRow: false,
                  dataColumnWidth: dataColumnWidth,
                  onDelete: null,
                  onSelectField: (key) => widget.onSelectField(null, key),
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: SizedBox(
                  width: tableWidth,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: displayRows.length,
                    itemBuilder: (context, index) {
                      final rowIndex = index < widget.rows.length ? index : null;
                      final selectedRow = index == selectedDisplayIndex;
                      return _TableLine(
                        rowNumber: index + 1,
                        showIndexColumn: widget.showIndexColumn,
                        columns: columns,
                        row: displayRows[index],
                        currentKey: selectedRow ? widget.currentKey : '',
                        selectedRow: selectedRow,
                        dataColumnWidth: dataColumnWidth,
                        onDelete:
                            widget.allowDelete &&
                                (rowIndex != null ||
                                    !_isEmptyRow(displayRows[index]))
                            ? () => widget.onDelete(rowIndex)
                            : null,
                        onSelectField: (key) => widget.onSelectField(rowIndex, key),
                      );
                    },
                  ),
                ),
              ),
              if (widget.summaryPrimary.isNotEmpty ||
                  widget.summarySecondary.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: _groupDecoration(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.summaryPrimary,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.summarySecondary.isNotEmpty)
                        Expanded(
                          child: Text(
                            widget.summarySecondary,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _IndexedLoadingRow {
  const _IndexedLoadingRow(this.index, this.row);

  final int index;
  final Map<String, String> row;
}

class _LoadingDisplayCard extends StatelessWidget {
  const _LoadingDisplayCard({
    required this.rows,
    required this.currentRow,
    required this.currentKey,
    required this.editingRowIndex,
    required this.aluminumPackageTitle,
    required this.aluminumWeightTitle,
    required this.aluminumUseWeighbridge,
    required this.summaryPrimary,
    required this.summarySecondary,
    required this.onDelete,
    required this.onSelectField,
    required this.onPackageHeader,
    required this.onWeightHeader,
  });

  final List<Map<String, String>> rows;
  final Map<String, String> currentRow;
  final String currentKey;
  final int? editingRowIndex;
  final String aluminumPackageTitle;
  final String aluminumWeightTitle;
  final bool aluminumUseWeighbridge;
  final String summaryPrimary;
  final String summarySecondary;
  final ValueChanged<int> onDelete;
  final void Function(int? rowIndex, String key) onSelectField;
  final VoidCallback onPackageHeader;
  final VoidCallback onWeightHeader;

  @override
  Widget build(BuildContext context) {
    final indexedRows = [
      for (var index = 0; index < rows.length; index++)
        _IndexedLoadingRow(index, rows[index]),
    ];
    final aluminumRows = indexedRows
        .where((item) => _isAluminumLoadingRow(item.row))
        .toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: _groupDecoration(),
      child: Column(
        children: [
          Expanded(
            child: _LoadingSection(
              title: null,
              rows: aluminumRows,
              currentRow: _isAluminumLoadingRow(currentRow) ? currentRow : null,
              currentKey: currentKey,
              editingRowIndex: editingRowIndex,
              columns: _loadingColumns(
                packageTitle: aluminumPackageTitle,
                quantityTitle: '面积',
                weightTitle: aluminumWeightTitle,
              ),
              hideWeight: aluminumUseWeighbridge,
              onDelete: onDelete,
              onSelectField: onSelectField,
              onHeaderSelect: (key) {
                if (key == 'packages') onPackageHeader();
                if (key == 'weight') onWeightHeader();
              },
            ),
          ),
          if (summaryPrimary.isNotEmpty || summarySecondary.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(6),
              decoration: _groupDecoration(),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      summaryPrimary,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (summarySecondary.isNotEmpty)
                    Expanded(
                      child: Text(
                        summarySecondary,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingSection extends StatefulWidget {
  const _LoadingSection({
    required this.title,
    required this.rows,
    required this.currentRow,
    required this.currentKey,
    required this.editingRowIndex,
    required this.columns,
    required this.hideWeight,
    required this.onDelete,
    required this.onSelectField,
    this.onHeaderSelect,
    this.onRemarkLongPress,
  });

  final String? title;
  final List<_IndexedLoadingRow> rows;
  final Map<String, String>? currentRow;
  final String currentKey;
  final int? editingRowIndex;
  final List<_ModeColumn> columns;
  final bool hideWeight;
  final ValueChanged<int> onDelete;
  final void Function(int? rowIndex, String key) onSelectField;
  final ValueChanged<String>? onHeaderSelect;
  final ValueChanged<int>? onRemarkLongPress;

  @override
  State<_LoadingSection> createState() => _LoadingSectionState();
}

class _LoadingSectionState extends State<_LoadingSection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _LoadingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollToCurrentInputRow();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentInputRow() {
    if (widget.editingRowIndex != null || widget.currentRow == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasEditingRow = widget.rows.any(
      (item) => item.index == widget.editingRowIndex,
    );
    final displayRows = [
      for (final item in widget.rows)
        _IndexedLoadingRow(
          item.index,
          item.index == widget.editingRowIndex && widget.currentRow != null
              ? widget.currentRow!
              : item.row,
        ),
      if (widget.currentRow != null && !hasEditingRow)
        _IndexedLoadingRow(-1, widget.currentRow!),
    ];
    _scrollToCurrentInputRow();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Text(
              widget.title!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = _tableWidthFor(
                constraints.maxWidth,
                widget.columns.length,
              );
              final dataColumnWidth = _tableDataColumnWidth(
                tableWidth,
                widget.columns.length,
              );
              return SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    _TableLine(
                      rowNumber: null,
                      showIndexColumn: true,
                      columns: widget.columns,
                      row: null,
                      currentKey: widget.currentKey,
                      selectedRow: false,
                      dataColumnWidth: dataColumnWidth,
                      onDelete: null,
                      onSelectField: (key) => widget.onHeaderSelect?.call(key),
                      headerSelectable: widget.onHeaderSelect != null,
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: displayRows.isEmpty ? 1 : displayRows.length,
                        itemBuilder: (context, index) {
                          if (displayRows.isEmpty) {
                            return _TableLine(
                              rowNumber: 1,
                              showIndexColumn: true,
                              columns: widget.columns,
                              row: const {},
                              currentKey: '',
                              selectedRow: false,
                              dataColumnWidth: dataColumnWidth,
                              onDelete: null,
                              onSelectField: (_) {},
                            );
                          }
                          final item = displayRows[index];
                          final selectedRow =
                              item.index == widget.editingRowIndex ||
                              item.index < 0;
                          return _TableLine(
                            rowNumber: index + 1,
                            showIndexColumn: true,
                            columns: widget.columns,
                            row: widget.hideWeight
                                ? {...item.row, 'weight': ''}
                                : item.row,
                            currentKey: selectedRow ? widget.currentKey : '',
                            selectedRow: selectedRow,
                            dataColumnWidth: dataColumnWidth,
                            onDelete: item.index >= 0
                                ? () => widget.onDelete(item.index)
                                : null,
                            onSelectField: (key) => widget.onSelectField(
                              item.index >= 0 ? item.index : null,
                              key,
                            ),
                            onLongPressField: (key) {
                              if (key == 'remark' && item.index >= 0) {
                                widget.onRemarkLongPress?.call(item.index);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TableLine extends StatelessWidget {
  const _TableLine({
    required this.rowNumber,
    required this.showIndexColumn,
    required this.columns,
    required this.row,
    required this.currentKey,
    required this.selectedRow,
    required this.dataColumnWidth,
    required this.onDelete,
    required this.onSelectField,
    this.headerSelectable = false,
    this.onLongPressField,
  });
  final int? rowNumber;
  final bool showIndexColumn;
  final List<_ModeColumn> columns;
  final Map<String, String>? row;
  final String currentKey;
  final bool selectedRow;
  final double dataColumnWidth;
  final VoidCallback? onDelete;
  final ValueChanged<String> onSelectField;
  final bool headerSelectable;
  final ValueChanged<String>? onLongPressField;

  @override
  Widget build(BuildContext context) {
    final isHeader = row == null;
    return Row(
      children: [
        if (showIndexColumn)
          GestureDetector(
            onLongPress: isHeader ? null : onDelete,
            child: _Cell(
              text: isHeader ? '序号' : rowNumber.toString(),
              width: _tableIndexColumnWidth,
              header: isHeader,
              selected: false,
              selectedRow: selectedRow,
            ),
          ),
        for (final column in columns)
          GestureDetector(
            onTap: isHeader && !headerSelectable
                ? null
                : () => onSelectField(column.key),
            onLongPress: isHeader
                ? null
                : () => onLongPressField?.call(column.key),
            child: _Cell(
              text: isHeader
                  ? column.label
                  : _displayCellText(row!, column.key),
              width: dataColumnWidth,
              header: isHeader,
              selected: currentKey == column.key,
              selectedRow: selectedRow,
            ),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.width,
    required this.header,
    required this.selected,
    required this.selectedRow,
  });
  final String text;
  final double width;
  final bool header;
  final bool selected;
  final bool selectedRow;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? const Color(0xFFF0EAFF)
        : selectedRow
        ? const Color(0xFFF8F5FF)
        : header
        ? const Color(0xFFF2F5FB)
        : Colors.white;
    final borderColor = selected
        ? _legacyPurpleStart
        : header
        ? const Color(0xFFD6DEEC)
        : const Color(0xFFE1E7F2);
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 30),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: selected ? 1.2 : 0.8),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? _legacyPurpleStart : Colors.black87,
          fontSize: header ? 10 : 11,
          fontWeight: selected || header ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _StandardKeyboard extends StatelessWidget {
  const _StandardKeyboard({
    required this.onToken,
    required this.onSymbol,
    required this.onBackspace,
    required this.onNewColumn,
    required this.onNewLine,
  });
  final ValueChanged<String> onToken;
  final VoidCallback onSymbol;
  final VoidCallback onBackspace;
  final VoidCallback onNewColumn;
  final VoidCallback onNewLine;

  @override
  Widget build(BuildContext context) {
    return _KeyboardCard(
      children: [
        Expanded(
          flex: 98,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(
                  child: _KeyGrid(
                    keys: const ['符号', 'K', 'Y', '空格', '回退'],
                    columns: 5,
                    decorated: false,
                    onToken: (v) {
                      if (v == '回退') {
                        onBackspace();
                      } else if (v == '符号') {
                        onSymbol();
                      } else {
                        onToken(v);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: _KeyGrid(
                    keys: const ['A', 'B', 'C', 'D', 'E', 'F'],
                    columns: 6,
                    decorated: false,
                    onToken: onToken,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 245,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(child: _NumberPad(onToken: onToken)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 82,
                  child: _ActionColumn(
                    buttons: [
                      _ActionSpec('换行', onNewLine),
                      _ActionSpec('换列', onNewColumn),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(flex: 157, child: _ModelShortcutGroups(onToken: onToken)),
      ],
    );
  }
}

class _FastVoiceHoldDialogBody extends StatefulWidget {
  const _FastVoiceHoldDialogBody();

  @override
  State<_FastVoiceHoldDialogBody> createState() =>
      _FastVoiceHoldDialogBodyState();
}

class _FastVoiceHoldDialogBodyState extends State<_FastVoiceHoldDialogBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '请按住说出尺寸，例如 200乘300、400乘1米1、50乘80厘米',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _FastVoiceWaveBar(height: 18, progress: _waveProgress(0)),
                const SizedBox(width: 8),
                _FastVoiceWaveBar(height: 28, progress: _waveProgress(1)),
                const SizedBox(width: 8),
                _FastVoiceWaveBar(height: 22, progress: _waveProgress(2)),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        const Text(
          '请持续按住并清晰说出尺寸',
          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  double _waveProgress(int index) {
    final shifted = (_controller.value + index * 0.23) % 1.0;
    return shifted <= 0.5 ? shifted * 2 : (1 - shifted) * 2;
  }
}

class _FastVoiceWaveBar extends StatelessWidget {
  const _FastVoiceWaveBar({required this.height, required this.progress});

  final double height;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleY: 0.7 + progress * 0.55,
      alignment: Alignment.bottomCenter,
      child: Opacity(
        opacity: 0.45 + progress * 0.55,
        child: Container(
          width: 8,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

class _FastKeyboard extends StatelessWidget {
  const _FastKeyboard({
    required this.onToken,
    required this.onBackspace,
    required this.onNewColumn,
    required this.onNewLine,
    required this.voicePressed,
    required this.onVoiceStart,
    required this.onVoiceEnd,
    required this.onVoiceCancel,
  });
  final ValueChanged<String> onToken;
  final VoidCallback onBackspace;
  final VoidCallback onNewColumn;
  final VoidCallback onNewLine;
  final bool voicePressed;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  final VoidCallback onVoiceCancel;

  @override
  Widget build(BuildContext context) {
    return _KeyboardCard(
      children: [
        Expanded(
          flex: 56,
          child: _KeyGrid(
            keys: const ['50', '45', '95', '65', '85'],
            columns: 5,
            padding: const EdgeInsets.all(3),
            onToken: onToken,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 56,
          child: _KeyGrid(
            keys: const ['100', '200', '300', '400', '500'],
            columns: 5,
            padding: const EdgeInsets.all(3),
            onToken: onToken,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 56,
          child: _KeyGrid(
            keys: const ['700', '900', '1100', '2700', '2745'],
            columns: 5,
            padding: const EdgeInsets.all(3),
            onToken: onToken,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 252,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(2),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Row(
                children: [
                  Expanded(flex: 100, child: _NumberPad(onToken: onToken)),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 28,
                    child: _ActionColumn(
                      margin: const EdgeInsets.all(2),
                      fontSize: 13,
                      buttons: [
                        _ActionSpec('换列', onNewColumn),
                        _ActionSpec('换行', onNewLine),
                        _ActionSpec('回退', onBackspace),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          flex: 80,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(2),
            child: Row(
              children: [
                for (final key in const ['E', 'F', 'SP']) ...[
                  Expanded(
                    child: _KeyButton(text: key, onPressed: () => onToken(key)),
                  ),
                  const SizedBox(width: 3),
                ],
                Expanded(
                  child: _FastVoiceButton(
                    pressed: voicePressed,
                    onHoldStart: onVoiceStart,
                    onHoldEnd: onVoiceEnd,
                    onHoldCancel: onVoiceCancel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FastVoiceButton extends StatelessWidget {
  const _FastVoiceButton({
    required this.pressed,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  final bool pressed;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => onHoldStart(),
          onPointerUp: (_) => onHoldEnd(),
          onPointerCancel: (_) {},
          child: AnimatedScale(
            scale: pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: CustomPaint(
              painter: _FastVoiceButtonPainter(pressed: pressed),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _FastVoiceButtonPainter extends CustomPainter {
  const _FastVoiceButtonPainter({required this.pressed});

  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = size.shortestSide;
    final outerRadius = shortest * (pressed ? 0.46 : 0.43);
    final innerRadius = shortest * (pressed ? 0.36 : 0.34);
    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);

    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..shader = RadialGradient(
          colors: pressed
              ? const [Color(0x3A8E79F5), Color(0x24725EFF)]
              : const [Color(0x2C8B77F0), Color(0x1A6E5BFF)],
        ).createShader(outerRect),
    );
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA58BFF), Color(0xFF8266F0), Color(0xFF5E40C9)],
        ).createShader(innerRect),
    );
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: pressed ? 0.30 : 0.25),
    );

    final highlightRect = Rect.fromCenter(
      center: center.translate(0, -innerRadius * 0.42),
      width: innerRadius * 1.55,
      height: innerRadius * 0.72,
    );
    canvas.drawOval(
      highlightRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: pressed ? 0.40 : 0.34),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(highlightRect),
    );

    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: pressed ? 0.13 : 0.09),
          ],
        ).createShader(innerRect),
    );
    _paintMic(canvas, center, shortest * 0.28);
  }

  void _paintMic(Canvas canvas, Offset center, double iconSize) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = iconSize * 0.09
      ..strokeCap = StrokeCap.round;
    final unit = iconSize / 24;
    final micRect = Rect.fromCenter(
      center: center.translate(0, -2 * unit),
      width: 6 * unit,
      height: 12 * unit,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(micRect, Radius.circular(3 * unit)),
      paint,
    );
    final arcRect = Rect.fromCenter(
      center: center.translate(0, 1.5 * unit),
      width: 14 * unit,
      height: 14 * unit,
    );
    canvas.drawArc(arcRect, 0.12, 2.9, false, stroke);
    canvas.drawLine(
      center.translate(0, 8 * unit),
      center.translate(0, 12 * unit),
      stroke,
    );
    canvas.drawLine(
      center.translate(-4 * unit, 12 * unit),
      center.translate(4 * unit, 12 * unit),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _FastVoiceButtonPainter oldDelegate) {
    return oldDelegate.pressed != pressed;
  }
}

class _LoadingKeyboard extends StatelessWidget {
  const _LoadingKeyboard({
    required this.rows,
    required this.currentRow,
    required this.currentKey,
    required this.editingRowIndex,
    required this.ironWeightTitle,
    required this.ironUseWeighbridge,
    required this.vehicleInfo,
    required this.onToken,
    required this.onBackspace,
    required this.onNewColumn,
    required this.onNewLine,
    required this.onAluminumMaterial,
    required this.onIronMaterial,
    required this.onVehicleInfo,
    required this.onDelete,
    required this.onSelectField,
    required this.onIronWeightHeader,
    required this.onDeductAluminumBox,
  });
  final List<Map<String, String>> rows;
  final Map<String, String> currentRow;
  final String currentKey;
  final int? editingRowIndex;
  final String ironWeightTitle;
  final bool ironUseWeighbridge;
  final Map<String, String> vehicleInfo;
  final ValueChanged<String> onToken;
  final VoidCallback onBackspace;
  final VoidCallback onNewColumn;
  final VoidCallback onNewLine;
  final VoidCallback onAluminumMaterial;
  final VoidCallback onIronMaterial;
  final VoidCallback onVehicleInfo;
  final ValueChanged<int> onDelete;
  final void Function(int? rowIndex, String key) onSelectField;
  final VoidCallback onIronWeightHeader;
  final ValueChanged<int> onDeductAluminumBox;

  @override
  Widget build(BuildContext context) {
    final indexedRows = [
      for (var index = 0; index < rows.length; index++)
        _IndexedLoadingRow(index, rows[index]),
    ];
    final ironRows = indexedRows
        .where((item) => _isIronLoadingRow(item.row))
        .toList();
    final ironWeighbridge = _loadingIronWeighbridgeWeightFromInfo(vehicleInfo);
    final ironTotal = ironUseWeighbridge
        ? ironWeighbridge
        : _sumDouble(rows.where(_isIronLoadingRow).toList(), 'weight');
    return _KeyboardCard(
      children: [
        Expanded(
          flex: 72,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(
                  child: _LoadingSection(
                    title: null,
                    rows: ironRows,
                    currentRow: _isIronLoadingRow(currentRow)
                        ? currentRow
                        : null,
                    currentKey: currentKey,
                    editingRowIndex: editingRowIndex,
                    columns: _loadingColumns(
                      packageTitle: '包数',
                      quantityTitle: '数量',
                      weightTitle: ironWeightTitle,
                    ),
                    hideWeight: ironUseWeighbridge,
                    onDelete: onDelete,
                    onSelectField: onSelectField,
                    onHeaderSelect: (key) {
                      if (key == 'weight') onIronWeightHeader();
                    },
                    onRemarkLongPress: onDeductAluminumBox,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '铁件过磅重量：${_formatNumber(ironWeighbridge)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '铁件单包称重合计：${_formatNumber(ironTotal)}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 100,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                SizedBox(
                  height: 42,
                  child: Row(
                    children: [
                      Expanded(
                        child: _PurpleButton(
                          text: '铝物料',
                          onPressed: onAluminumMaterial,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _PurpleButton(
                          text: '铁物料',
                          onPressed: onIronMaterial,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _PurpleButton(
                          text: '过磅信息',
                          onPressed: onVehicleInfo,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _NumberPad(onToken: onToken)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 82,
                        child: _ActionColumn(
                          buttons: [
                            _ActionSpec('换列', onNewColumn),
                            _ActionSpec('换行', onNewLine),
                            _ActionSpec('回退', onBackspace),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QualityKeyboard extends StatelessWidget {
  const _QualityKeyboard({
    required this.onToken,
    required this.onSymbol,
    required this.onBackspace,
    required this.onNewColumn,
    required this.onNewLine,
  });
  final ValueChanged<String> onToken;
  final VoidCallback onSymbol;
  final VoidCallback onBackspace;
  final VoidCallback onNewColumn;
  final VoidCallback onNewLine;

  @override
  Widget build(BuildContext context) {
    return _KeyboardCard(
      children: [
        Expanded(
          flex: 62,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(
                  child: _KeyGrid(
                    keys: const ['符号', 'K', 'Y', '空格', '回退'],
                    columns: 5,
                    decorated: false,
                    onToken: (v) {
                      if (v == '回退') {
                        onBackspace();
                      } else if (v == '符号') {
                        onSymbol();
                      } else if (v == 'K') {
                        onToken('L');
                      } else {
                        onToken(v);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: _KeyGrid(
                    keys: const ['A', 'B', 'C', 'D', 'E', 'F'],
                    columns: 6,
                    decorated: false,
                    onToken: onToken,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 152,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(child: _NumberPad(onToken: onToken)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 82,
                  child: _ActionColumn(
                    buttons: [
                      _ActionSpec('换行', onNewLine),
                      _ActionSpec('换列', onNewColumn),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(flex: 125, child: _ModelShortcutGroups(onToken: onToken)),
      ],
    );
  }
}

class _VehicleInput extends StatelessWidget {
  const _VehicleInput({
    required this.controller,
    required this.label,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: label.contains('车牌') || label.contains('时间')
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF2F2F2),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _VehicleReadonly extends StatelessWidget {
  const _VehicleReadonly({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFFF2F2F2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

const _legacyPurpleStart = Color(0xFF6E57B5);
const _legacyPurpleEnd = Color(0xFF7E63C5);
const _legacyKeyPurpleEnd = Color(0xFF8067C8);
const _legacyGroupBorder = Color(0xFFE3E8F4);
const _legacyCardBorder = Color(0xFFDCE3F1);
const _legacyKeyBorder = Color(0xFFD4DDEA);
const _legacyNumberBorder = Color(0xFFD8E0F1);
const _legacyKeyPressedFill = Color(0xFFEEF2F8);

const _legacyPurpleButtonGradient = LinearGradient(
  colors: [_legacyPurpleStart, _legacyPurpleEnd],
);
const _legacyKeyboardButtonGradient = LinearGradient(
  colors: [_legacyPurpleStart, _legacyKeyPurpleEnd],
);

class _KeyboardCard extends StatelessWidget {
  const _KeyboardCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(),
      child: Column(children: children),
    );
  }
}

class _LegacyGroup extends StatelessWidget {
  const _LegacyGroup({
    required this.child,
    this.padding = const EdgeInsets.all(4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: _groupDecoration(),
      child: child,
    );
  }
}

class _ModelShortcutGroups extends StatelessWidget {
  const _ModelShortcutGroups({required this.onToken});

  final ValueChanged<String> onToken;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _KeyGrid(
                  keys: const ['W', 'WE', 'WED', 'BQ', 'IC', 'ICA'],
                  columns: 3,
                  onToken: onToken,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _KeyGrid(
                  keys: const ['B', 'BS', 'BC', 'BP', 'X', 'N'],
                  columns: 3,
                  onToken: onToken,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _KeyGrid(
                  keys: const ['S', 'SC', 'M', 'MB', 'SP', 'Q'],
                  columns: 3,
                  onToken: onToken,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _KeyGrid(
                  keys: const ['LT', 'JT', 'GT', 'DM', 'H', 'P'],
                  columns: 3,
                  onToken: onToken,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.onToken});
  final ValueChanged<String> onToken;

  @override
  Widget build(BuildContext context) => _KeyGrid(
    keys: const ['7', '8', '9', '4', '5', '6', '1', '2', '3', '0', '00', '.'],
    columns: 3,
    onToken: onToken,
    dark: true,
    decorated: false,
  );
}

class _KeyGrid extends StatelessWidget {
  const _KeyGrid({
    required this.keys,
    required this.columns,
    required this.onToken,
    this.dark = false,
    this.decorated = true,
    this.padding = const EdgeInsets.all(4),
  });
  final List<String> keys;
  final int columns;
  final ValueChanged<String> onToken;
  final bool dark;
  final bool decorated;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    const spacing = 3.0;
    final rows = (keys.length / columns).ceil();
    final grid = Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) SizedBox(height: spacing),
          Expanded(
            child: Row(
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) SizedBox(width: spacing),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final index = row * columns + column;
                        if (index >= keys.length) {
                          return const SizedBox.shrink();
                        }
                        final key = keys[index];
                        return _KeyButton(
                          text: key,
                          onPressed: () => onToken(key),
                          dark: dark,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );

    if (!decorated) return grid;
    return _LegacyGroup(padding: padding, child: grid);
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.text,
    required this.onPressed,
    this.dark = false,
  });
  final String text;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return _LegacyButton(
      text: text,
      onPressed: onPressed,
      gradient: dark ? _legacyKeyboardButtonGradient : null,
      color: dark ? null : Colors.white,
      border: dark
          ? Border.all(color: _legacyNumberBorder)
          : Border.all(color: _legacyKeyBorder),
      borderRadius: BorderRadius.circular(dark ? 16 : 10),
      padding: EdgeInsets.zero,
      overlayColor: dark ? Colors.white24 : _legacyKeyPressedFill,
      textStyle: TextStyle(
        color: dark ? Colors.white : AppColors.textPrimary,
        fontSize: dark ? 18 : 11,
        fontWeight: dark ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

class _PurpleButton extends StatelessWidget {
  const _PurpleButton({required this.text, required this.onPressed});
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _LegacyButton(
    text: text,
    onPressed: onPressed,
    gradient: _legacyPurpleButtonGradient,
    borderRadius: BorderRadius.circular(20),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    textStyle: const TextStyle(color: Colors.white, fontSize: 13),
  );
}

class _ActionSpec {
  const _ActionSpec(this.text, this.onPressed);

  final String text;
  final VoidCallback onPressed;
}

class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.buttons,
    this.margin = const EdgeInsets.all(1),
    this.fontSize = 11,
  });

  final List<_ActionSpec> buttons;
  final EdgeInsetsGeometry margin;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < buttons.length; index++)
          Expanded(
            child: Padding(
              padding: margin,
              child: _LegacyButton(
                text: buttons[index].text,
                onPressed: buttons[index].onPressed,
                gradient: _legacyKeyboardButtonGradient,
                borderRadius: BorderRadius.circular(16),
                padding: EdgeInsets.zero,
                textStyle: TextStyle(color: Colors.white, fontSize: fontSize),
              ),
            ),
          ),
      ],
    );
  }
}

class _LegacyButton extends StatelessWidget {
  const _LegacyButton({
    required this.text,
    required this.onPressed,
    required this.borderRadius,
    required this.textStyle,
    this.gradient,
    this.color,
    this.border,
    this.padding = EdgeInsets.zero,
    this.overlayColor = Colors.white24,
  });

  final String text;
  final VoidCallback onPressed;
  final Gradient? gradient;
  final Color? color;
  final BoxBorder? border;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final TextStyle textStyle;
  final Color overlayColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          border: border,
          borderRadius: borderRadius,
        ),
        child: InkWell(
          borderRadius: borderRadius,
          overlayColor: WidgetStatePropertyAll(overlayColor),
          onTap: onPressed,
          child: Padding(
            padding: padding,
            child: Center(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
  if (row['_type'] == 'iron') return false;
  final material = row['material']?.trim() ?? '';
  return material.isEmpty ||
      material.contains('铝') ||
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
