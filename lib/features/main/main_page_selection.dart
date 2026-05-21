part of 'main_page.dart';

extension _MainPageSelection on _MainPageState {
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
      await _flushFastRowsSave();
      await _saveCurrentDraft();
      if (!mounted) return;
      _setMainState(() => _mode = selected);
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

    _setMainState(() {
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
    final current = _currentRow;
    if (_isEmptyRow(current)) return rows;
    final index = _editingRowIndex;
    if (index != null && index >= 0 && index < rows.length) {
      return [
        for (var i = 0; i < rows.length; i++) i == index ? current : rows[i],
      ];
    }
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
