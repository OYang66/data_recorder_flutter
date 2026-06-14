part of 'main_page.dart';

extension _MainPageRows on _MainPageState {
  Future<void> _saveRows(
    List<Map<String, String>> rows, {
    Map<String, String>? loadingVehicleInfo,
  }) async {
    final project = _project;
    if (project == null) return;
    final rowsToSave = _mode == MainMode.loading
        ? _withLoadingVehicleInfo(rows, vehicleInfo: loadingVehicleInfo)
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
    _setMainState(() {
      _project = updated;
      final index = _projects.indexWhere((item) => item.id == updated.id);
      if (index >= 0) _projects[index] = updated;
    });
    await _saveMainState();
  }

  void _queueEditedRowSave() {
    if (!_hasEditingRow) return;
    _editedRowSavePending = true;
    _editedRowSaveTimer?.cancel();
    _editedRowSaveTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_flushQueuedEditedRowSave()),
    );
  }

  Future<void> _flushQueuedEditedRowSave() async {
    if (!_editedRowSavePending) return;
    _editedRowSaveTimer?.cancel();
    _editedRowSaveTimer = null;
    _editedRowSavePending = false;
    await _saveEditedCurrentRow();
  }

  void _clearQueuedEditedRowSave() {
    _editedRowSaveTimer?.cancel();
    _editedRowSaveTimer = null;
    _editedRowSavePending = false;
  }

  void _queueFastRowsSave(List<Map<String, String>> rows) {
    _pendingFastRowsSave = rows;
    _pendingFastRowsSaveBuildingName = _currentBuildingName;
    _pendingFastRowsSavePackageName = _packageName;
    _fastRowsSaveTimer?.cancel();
    _fastRowsSaveTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_flushFastRowsSave()),
    );
  }

  Future<void> _flushFastRowsSave() async {
    final rows = _pendingFastRowsSave;
    final buildingName = _pendingFastRowsSaveBuildingName;
    final packageName = _pendingFastRowsSavePackageName;
    if (rows == null || buildingName == null || packageName == null) return;
    _fastRowsSaveTimer?.cancel();
    _fastRowsSaveTimer = null;
    _pendingFastRowsSave = null;
    _pendingFastRowsSaveBuildingName = null;
    _pendingFastRowsSavePackageName = null;

    final project = _project;
    if (project == null) return;
    final content = _encodeRowsForScope(
      project.fastContent,
      buildingName,
      packageName,
      rows,
    );
    await _updateProject(project.copyWith(fastContent: content));
    if (_mode == MainMode.fast &&
        _currentBuildingName == buildingName &&
        _packageName == packageName) {
      unawaited(_pushFastSnapshotToSubDisplay());
    }
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
      _setMainState(() {});
      return;
    }
    final rows = [..._rows, current];
    _rowsCache = rows;
    _clearCurrentRow();
    if (_mode == MainMode.fast) {
      _queueFastRowsSave(rows);
      return;
    }
    await _saveRows(rows);
  }

  Future<void> _saveEditedCurrentRow() async {
    _clearQueuedEditedRowSave();
    final index = _editingRowIndex;
    if (index == null) return;
    final rows = _rows;
    if (index < 0 || index >= rows.length) return;
    rows[index] = Map<String, String>.from(_currentRow);
    await _saveRows(rows);
  }

  Future<void> _saveQualityEditedRow(Map<String, String> row) async {
    if (_mode == MainMode.quality) _clearQueuedEditedRowSave();
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
    _setMainState(() {
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
    List<Map<String, String>> rows, {
    Map<String, String>? vehicleInfo,
  }) {
    final info = vehicleInfo ?? _vehicleInfo;
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
}
