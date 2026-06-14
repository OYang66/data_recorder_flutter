part of 'main_page.dart';

extension _MainPageInput on _MainPageState {
  void _appendToken(String token) {
    var saveQualityEdit = false;
    var saveLoadingEdit = false;
    String? warning;
    _setMainState(() {
      switch (_mode) {
        case MainMode.standard:
          warning = _appendStandardToken(token);
        case MainMode.fast:
          warning = _appendFastToken(token);
          _lastSubDisplayPayload = null;
        case MainMode.loading:
          warning = _appendLoadingToken(token);
          saveLoadingEdit = warning == null && _editingLoadingRowIndex != null;
        case MainMode.quality:
          if (_qualityField == QualityField.installNumber ||
              _qualityField == QualityField.model) {
            warning = _appendQualityToken(token);
            saveQualityEdit =
                warning == null && _editingQualityRowIndex != null;
          }
      }
    });
    if (warning != null) {
      _showNotReady(warning!);
    } else if (!saveLoadingEdit && !saveQualityEdit) {
      _queueCurrentDraftStateSave();
    }
    if (saveLoadingEdit || saveQualityEdit) {
      unawaited(_clearSavedCurrentDraftState());
      _queueEditedRowSave();
    }
  }

  void _backspace() {
    final saveQualityEdit =
        _mode == MainMode.quality && _editingQualityRowIndex != null;
    final saveLoadingEdit =
        _mode == MainMode.loading && _editingLoadingRowIndex != null;
    _setMainState(() {
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
    if (saveLoadingEdit || saveQualityEdit) {
      unawaited(_clearSavedCurrentDraftState());
      _queueEditedRowSave();
    } else {
      _queueCurrentDraftStateSave();
    }
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
    _setMainState(() {
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
          final fields = LoadingField.values;
          var nextField = fields[(_loadingField.index + 1) % fields.length];
          if (nextField == LoadingField.weight &&
              !_loadingWeightEditableForRow(_loadingCurrent)) {
            nextField = fields[(nextField.index + 1) % fields.length];
          }
          _loadingField = nextField;
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
      _setMainState(() {
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
    _setMainState(() {
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
    unawaited(_clearSavedCurrentDraftState());
    _setMainState(() {
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
}
