import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
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
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/server_repository.dart';
import '../../data/repositories/version_repository.dart';

part 'main_page_lifecycle.dart';
part 'main_page_rows.dart';
part 'main_page_loading.dart';
part 'main_page_input.dart';
part 'main_page_dialogs.dart';
part 'main_page_project.dart';
part 'main_page_more.dart';
part 'main_page_export.dart';
part 'main_page_fast_voice.dart';
part 'main_page_quality.dart';
part 'main_page_selection.dart';
part 'main_page_server_project_picker.dart';
part 'main_page_widgets.dart';
part 'main_page_helpers.dart';

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

class _ExportFilePayload {
  const _ExportFilePayload({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final List<int> bytes;
  final String mimeType;

  Map<String, Object> toChannelMap() => {
    'fileName': fileName,
    'bytes': bytes,
    'mimeType': mimeType,
  };
}

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
  MainMode? _rowsCacheMode;
  String? _rowsCacheContent;
  String? _rowsCacheBuildingName;
  String? _rowsCacheScopeName;
  List<Map<String, String>>? _rowsCache;
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
  Timer? _draftStateTimer;
  Timer? _fastRowsSaveTimer;
  List<Map<String, String>>? _pendingFastRowsSave;
  String? _pendingFastRowsSaveBuildingName;
  String? _pendingFastRowsSavePackageName;
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

  void _setMainState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

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
    _draftStateTimer?.cancel();
    unawaited(_flushFastRowsSave());
    _fastVoiceTimeoutTimer?.cancel();
    unawaited(_fastVoiceChannel.invokeMethod<void>('cancelListening'));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushFastRowsSave());
      unawaited(_saveCurrentDraft());
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    if (_loading || project == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final rows = _rows;
    final summaryRows = _summaryRows(rows);
    final summaryPrimary = _summaryPrimaryText(summaryRows);
    final summarySecondary = _summarySecondaryText(summaryRows);
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
                flex: _mode == MainMode.loading ? 50 : 31,
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
                        ironWeightTitle: _loadingWeightHeader(false),
                        ironUseWeighbridge:
                            _loadingIronWeightMode == 'WEIGHBRIDGE_TOTAL',
                        vehicleInfo: _vehicleInfoForCurrentTrip(),
                        summaryPrimary: summaryPrimary,
                        summarySecondary: summarySecondary,
                        onDelete: _deleteRow,
                        onSelectField: _selectFieldByKey,
                        onPackageHeader: _showLoadingAluminumColumnModeDialog,
                        onWeightHeader: () =>
                            _showLoadingWeightModeDialog(aluminum: true),
                        onIronWeightHeader: () =>
                            _showLoadingWeightModeDialog(aluminum: false),
                        onDeductAluminumBox: _deductAluminumBoxWeight,
                      )
                    : _DisplayCard(
                        mode: _mode,
                        rows: rows,
                        currentRow: _currentRow,
                        currentKey: _currentKey,
                        summaryPrimary: summaryPrimary,
                        summarySecondary: summarySecondary,
                        editingRowIndex: _editingRowIndex,
                        showIndexColumn: _mode != MainMode.quality,
                        allowDelete: _mode != MainMode.quality,
                        onDelete: _deleteDisplayRow,
                        onSelectField: _selectFieldByKey,
                      ),
              ),
              const SizedBox(height: 6),
              Expanded(
                flex: _mode == MainMode.loading ? 50 : 69,
                child: _modePanel(),
              ),
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
        onToken: _appendToken,
        onBackspace: _backspace,
        onNewColumn: _nextColumn,
        onNewLine: _newLine,
        onAluminumMaterial: _showAluminumMaterialDialog,
        onIronMaterial: _showIronMaterialDialog,
        onVehicleInfo: _showVehicleInfoDialog,
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
}
