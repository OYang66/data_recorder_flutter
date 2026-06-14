part of 'main_page.dart';

extension _MainPageLifecycle on _MainPageState {
  Future<void> _saveCurrentDraft() async {
    final flushedEditedRow = _editedRowSavePending;
    await _flushQueuedEditedRowSave();
    await _saveMainState();
    if (_project == null) return;
    final hasCurrentRow = !_isEmptyRow(_currentRow);
    if (hasCurrentRow) {
      await _saveCurrentDraftState();
    } else {
      await _clearSavedCurrentDraftState();
    }
    if (_hasEditingRow) {
      if (!flushedEditedRow) await _saveEditedCurrentRow();
      await _clearSavedCurrentDraftState();
      return;
    }
    if (!hasCurrentRow) return;
    final rows = _rows;
    if (rows.any((row) => identical(row, _currentRow))) {
      await _clearSavedCurrentDraftState();
      return;
    }
    await _saveRows([...rows, Map<String, String>.from(_currentRow)]);
    if (mounted) {
      _clearCurrentRow();
    } else {
      await _clearSavedCurrentDraftState();
    }
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
    final projectsFuture = _repository.getAllProjects();
    final lastProjectIdFuture = _preferences.getLastProjectId();
    final mainStateFuture = _preferences.getMainState();
    final usernameFuture = _preferences.getUsername();
    try {
      final projects = await projectsFuture;
      ProjectEntity project;
      if (projects.isEmpty) {
        try {
          await lastProjectIdFuture;
        } catch (_) {}
        project = await _createDefaultProject();
        projects.add(project);
      } else {
        final lastProjectId = await lastProjectIdFuture;
        project = projects.firstWhere(
          (item) => item.id == lastProjectId,
          orElse: () => projects.first,
        );
      }
      final mainState = await mainStateFuture;
      final username = await usernameFuture;
      final savedMode = MainMode.values.firstWhere(
        (mode) => mode.name == mainState['flutter_main_mode'],
        orElse: () => _mode,
      );
      if (!mounted) return;
      _setMainState(() {
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
        if (savedMode == MainMode.loading) {
          final loadingMeta = _loadingMetaForCurrentTrip();
          _syncLoadingModesFromMeta(loadingMeta);
          _vehicleInfo = _vehicleInfoFromMeta(loadingMeta);
        }
      });
      _scheduleDeferredStartupTasks();
    } catch (_) {
      try {
        await lastProjectIdFuture;
      } catch (_) {}
      try {
        await mainStateFuture;
      } catch (_) {}
      const buildingName = '1号楼';
      final contents = _emptyProjectContents(const [
        buildingName,
      ], buildingName);
      final username = await usernameFuture.catchError((_) => '');
      if (!mounted) return;
      _setMainState(() {
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
      _scheduleDeferredStartupTasks();
      _showNotReady('本地数据加载失败，已进入默认项目');
    }
  }

  void _scheduleDeferredStartupTasks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_runDeferredStartupTasks());
      }
    });
  }

  Future<void> _runDeferredStartupTasks() async {
    await _restoreCurrentDraftState();
    if (!mounted) return;
    _syncSubDisplayPolling();
    if (_mode == MainMode.fast && _subDisplayCode.isNotEmpty) {
      unawaited(_refreshSubDisplayStatus());
    }
    await _checkStartupAppUpdateOnce();
    if (!mounted) return;
    unawaited(_checkLatestNoticeAndShowOnce());
  }

  Future<void> _checkStartupAppUpdateOnce() async {
    if (_MainPageState._startupUpdateCheckedThisSession) return;
    _MainPageState._startupUpdateCheckedThisSession = true;
    await _checkAppUpdate(showNoUpdateToast: false, showErrorToast: false);
  }

  Future<void> _restoreCurrentDraftState() async {
    final project = _project;
    if (project == null) return;
    final draft = await _preferences.getCurrentDraftState();
    if (!mounted) return;
    if (draft['flutter_draft_project_id'] != '${project.id ?? 0}' ||
        draft['flutter_draft_mode'] != _mode.name ||
        draft['flutter_draft_building'] != _currentBuildingName ||
        draft['flutter_draft_scope'] != _scopeName) {
      return;
    }
    final rowJson = draft['flutter_draft_row'] ?? '';
    if (rowJson.isEmpty) return;
    try {
      final decoded = jsonDecode(rowJson);
      if (decoded is! Map) return;
      final row = decoded.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
      if (_isEmptyRow(row)) return;
      final fieldName = draft['flutter_draft_field'] ?? '';
      _setMainState(() {
        switch (_mode) {
          case MainMode.standard:
            _standardCurrent = Map<String, String>.from(row);
            _standardField = StandardField.values.firstWhere(
              (field) => field.name == fieldName,
              orElse: () => StandardField.installNumber,
            );
          case MainMode.fast:
            _fastCurrent = Map<String, String>.from(row);
            _fastField = FastField.values.firstWhere(
              (field) => field.name == fieldName,
              orElse: () => FastField.width,
            );
          case MainMode.loading:
            _loadingCurrent = Map<String, String>.from(row);
            _loadingField = LoadingField.values.firstWhere(
              (field) => field.name == fieldName,
              orElse: () => LoadingField.material,
            );
          case MainMode.quality:
            _qualityCurrent = Map<String, String>.from(row);
            _qualityField = QualityField.values.firstWhere(
              (field) => field.name == fieldName,
              orElse: () => QualityField.installNumber,
            );
        }
      });
    } on FormatException {
      return;
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
    final mode = _mode;
    final content = _contentForMode(mode);
    final buildingName = _currentBuildingName;
    final scopeName = _scopeName;
    final cachedRows = _rowsCache;
    if (cachedRows != null &&
        _rowsCacheMode == mode &&
        _rowsCacheContent == content &&
        _rowsCacheBuildingName == buildingName &&
        _rowsCacheScopeName == scopeName) {
      return cachedRows;
    }

    final rows = mode == MainMode.loading
        ? _decodeLoadingRowsForTrip(
            content,
            _tripName,
            buildingName: buildingName,
          ).where((row) => !_isLoadingMetaRow(row)).toList()
        : _decodeRowsForScope(content, buildingName, scopeName);
    _rowsCacheMode = mode;
    _rowsCacheContent = content;
    _rowsCacheBuildingName = buildingName;
    _rowsCacheScopeName = scopeName;
    _rowsCache = rows;
    return rows;
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

  String get _currentFieldName => switch (_mode) {
    MainMode.standard => _standardField.name,
    MainMode.fast => _fastField.name,
    MainMode.loading => _loadingField.name,
    MainMode.quality => _qualityField.name,
  };

  void _queueCurrentDraftStateSave() {
    _draftStateTimer?.cancel();
    _draftStateTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_saveCurrentDraftState()),
    );
  }

  Future<void> _saveCurrentDraftState() async {
    final project = _project;
    if (project == null) return;
    final row = Map<String, String>.from(_currentRow);
    if (_isEmptyRow(row)) {
      await _preferences.clearCurrentDraftState();
      return;
    }
    await _preferences.saveCurrentDraftState(
      projectId: project.id ?? 0,
      mode: _mode.name,
      buildingName: _currentBuildingName,
      scopeName: _scopeName,
      fieldName: _currentFieldName,
      row: row,
    );
  }

  Future<void> _clearSavedCurrentDraftState() async {
    _draftStateTimer?.cancel();
    await _preferences.clearCurrentDraftState();
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
      final statusData = status.data;
      final sessionCount = statusData?.sessionCount ?? 0;
      final connected = statusData?.connected == true || sessionCount > 0;
      _setMainState(() {
        _subDisplayConnected = connected;
        _subDisplaySessionCount = sessionCount;
      });
      if (!wasConnected && connected) {
        unawaited(_pushFastSnapshotToSubDisplay(force: true));
      }
    } catch (_) {
      if (!mounted) return;
      _setMainState(() {
        _subDisplayConnected = false;
        _subDisplaySessionCount = 0;
      });
      if (showError) _showNotReady('连接状态刷新失败，请检查网络');
    }
  }

  void _clearSubDisplayCode([String? message]) {
    _subDisplayStatusTimer?.cancel();
    _subDisplayStatusTimer = null;
    _setMainState(() {
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
}
