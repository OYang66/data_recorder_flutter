part of 'main_page.dart';

extension _MainPageLoading on _MainPageState {
  Map<String, String> _loadingMetaForCurrentTrip() {
    final rows = _decodeLoadingRowsForTrip(
      _contentForMode(MainMode.loading),
      _tripName,
      buildingName: _currentBuildingName,
    );
    return rows.firstWhere(_isLoadingMetaRow, orElse: _emptyLoadingRow);
  }

  void _syncLoadingModesFromCurrentTrip() {
    _syncLoadingModesFromMeta(_loadingMetaForCurrentTrip());
  }

  void _syncLoadingModesFromMeta(Map<String, String> meta) {
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
    return _vehicleInfoFromMeta(_loadingMetaForCurrentTrip());
  }

  Map<String, String> _vehicleInfoFromMeta(Map<String, String> meta) {
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
    _setMainState(() {
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
    await _setLoadingWeightMode(
      aluminum: aluminum,
      mode: selected == '过磅总重量' ? 'WEIGHBRIDGE_TOTAL' : 'SINGLE_PACKAGE',
    );
  }

  Future<void> _setLoadingWeightMode({
    required bool aluminum,
    required String mode,
  }) async {
    _setMainState(() {
      if (aluminum) {
        _loadingAluminumWeightMode = mode;
      } else {
        _loadingIronWeightMode = mode;
      }
    });
    await _saveLoadingMetaOnly(vehicleInfo: _vehicleInfoForCurrentTrip());
  }

  void _resequenceLoadingAluminumPackages(List<Map<String, String>> rows) {
    var packageNo = 1;
    for (final row in rows) {
      if (_isAluminumLoadingRow(row)) row['packages'] = '${packageNo++}';
    }
  }

  Future<void> _saveLoadingMetaOnly({Map<String, String>? vehicleInfo}) async {
    final rows = _rows;
    await _saveRows(rows, loadingVehicleInfo: vehicleInfo);
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

  double _loadingAluminumSummaryWeight(List<Map<String, String>> rows) {
    if (_loadingAluminumWeightMode == 'WEIGHBRIDGE_TOTAL') {
      return _loadingAluminumWeighbridgeWeight();
    }
    return _sumDouble(rows.where(_isAluminumLoadingRow).toList(), 'weight');
  }

  bool _loadingWeightEditableForCurrentRow() {
    if (_loadingField != LoadingField.weight) return true;
    return _loadingWeightEditableForRow(_loadingCurrent);
  }

  bool _loadingWeightEditableForRow(Map<String, String> row) {
    if (_isIronLoadingRow(row)) {
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
    const lengthRequired = {'单支撑', '对拉螺杆', '斜撑', '圆管'};
    final selected = await _showOptionDialog(
      title: '铁物料',
      subtitle: '点击物料后直接新增到当前装车记录',
      options: materials,
      current: _loadingCurrent['material'],
    );
    if (!mounted || selected == null) return;
    var material = selected;
    if (lengthRequired.contains(selected)) {
      final length = await _showTextInputDialog(
        title: '请输入长度',
        label: '长度',
        hintText: '请输入长度',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      );
      if (!mounted || length == null) return;
      final text = length.trim();
      if (text.isNotEmpty) material = '$selected${text}mm';
    }
    await _startLoadingMaterial(aluminum: false, material: material);
  }

  Future<void> _startLoadingMaterial({
    required bool aluminum,
    required String material,
  }) async {
    if (_project == null) {
      _showNotReady('请先选择项目');
      return;
    }
    if (_tripName.trim().isEmpty) {
      _showNotReady('请先增加车次');
      return;
    }
    final weightMode = aluminum
        ? _loadingAluminumWeightMode
        : _loadingIronWeightMode;
    if (weightMode == 'UNSELECTED') {
      final targetName = aluminum ? '铝模' : '铁件';
      _showNotReady('请先点击$targetName重量，选择单包重量或过磅总重量');
      return;
    }
    if (_editingLoadingRowIndex != null) {
      await _saveEditedCurrentRow();
      await _clearSavedCurrentDraftState();
      if (!mounted) return;
      _setMainState(() => _editingLoadingRowIndex = null);
    } else {
      await _saveCurrentDraft();
      if (!mounted) return;
    }
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
    final rows = _rows..add(row);
    await _saveRows(rows);
    if (!mounted) return;
    _setMainState(() {
      _editingLoadingRowIndex = rows.length - 1;
      _loadingCurrent = Map<String, String>.from(row);
      _loadingField = field;
    });
    await _clearSavedCurrentDraftState();
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
    final input = await _showTextInputDialog(
      title: '请输入铝箱重量',
      label: '铝箱重量',
      hintText: '请输入铝箱重量',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (!mounted || input == null) return;
    final value = _parseDouble(input);
    if (value <= 0) return;
    try {
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
      if (!_loadingAluminumUsePackageCount) {
        _resequenceLoadingAluminumPackages(rows);
      }
      await _saveRows(rows);
      if (!mounted) return;
      _setMainState(() {
        _editingLoadingRowIndex = ironRowIndex;
        _loadingCurrent = Map<String, String>.from(rows[ironRowIndex]);
        _loadingField = LoadingField.remark;
      });
    } catch (_) {
      if (mounted) _showNotReady('扣除铝箱重量失败');
    }
  }

  Future<void> _showVehicleInfoDialog() async {
    if (_tripName.trim().isEmpty) {
      _showNotReady('请先增加车次');
      return;
    }
    _vehicleInfo = _vehicleInfoForCurrentTrip();
    await showAppCardDialog<void>(
      context: context,
      title: '过磅信息',
      subtitle: '当前车次：$_tripName',
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String valueText(String key) =>
              _vehicleInfo[key].orEmpty().ifBlank('点击输入');
          final gross = _parseDouble(_vehicleInfo['grossWeight']);
          final tare = _parseDouble(_vehicleInfo['tareWeight']);
          final wood = _parseDouble(_vehicleInfo['woodEstimate']);
          final middleAluminum = _vehicleInfo['middleAluminumWeight']
              .orEmpty()
              .trim();
          final middleIron = _vehicleInfo['middleIronWeight'].orEmpty().trim();
          final middleAluminumValue = double.tryParse(middleAluminum);
          final middleIronValue = double.tryParse(middleIron);
          final netWeight = gross - tare - wood;
          final aluminumWeight = middleAluminumValue != null
              ? middleAluminumValue - tare
              : (middleIronValue != null ? gross - middleIronValue : 0.0);
          final ironWeight = middleAluminumValue != null
              ? gross - middleAluminumValue
              : (middleIronValue != null ? middleIronValue - tare : 0.0);

          Future<void> editValue(
            String key,
            String label, {
            bool number = false,
          }) async {
            final input = await _showTextInputDialog(
              title: label,
              label: label,
              hintText: '点击输入',
              initialValue: _vehicleInfo[key].orEmpty(),
              keyboardType: number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
            );
            if (!mounted || input == null) return;
            _setMainState(() {
              _vehicleInfo = {..._vehicleInfo, key: input.trim()};
            });
            await _saveLoadingMetaOnly(vehicleInfo: _vehicleInfo);
            if (context.mounted) setDialogState(() {});
          }

          AppDialogListItem editableRow(
            String label,
            String key, {
            bool number = false,
            String? overrideValue,
            bool enabled = true,
          }) {
            return AppDialogListItem(
              label: label,
              subtitle: overrideValue ?? valueText(key),
              onTap: enabled
                  ? () => unawaited(editValue(key, label, number: number))
                  : null,
            );
          }

          Widget gap() => const SizedBox(height: 8);

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  editableRow('运输车牌号', 'vehiclePlateNumber'),
                  gap(),
                  editableRow('装车时间', 'loadingDate'),
                  gap(),
                  editableRow('装车毛重', 'grossWeight', number: true),
                  gap(),
                  editableRow('车辆皮重', 'tareWeight', number: true),
                  gap(),
                  editableRow(
                    '中途铝重',
                    'middleAluminumWeight',
                    number: true,
                    overrideValue: middleIron.isNotEmpty ? '请先删除另一个中途数据' : null,
                    enabled: middleIron.isEmpty,
                  ),
                  gap(),
                  editableRow(
                    '中途铁重',
                    'middleIronWeight',
                    number: true,
                    overrideValue: middleAluminum.isNotEmpty
                        ? '请先删除另一个中途数据'
                        : null,
                    enabled: middleAluminum.isEmpty,
                  ),
                  gap(),
                  editableRow('木方估算', 'woodEstimate', number: true),
                  gap(),
                  AppDialogListItem(
                    label: '装车净重',
                    subtitle: _formatNumber(netWeight),
                  ),
                  gap(),
                  AppDialogListItem(
                    label: '铝模重量',
                    subtitle: _formatNumber(aluminumWeight),
                  ),
                  gap(),
                  AppDialogListItem(
                    label: '铁件重量',
                    subtitle: _formatNumber(ironWeight),
                  ),
                  const SizedBox(height: 12),
                  AppDialogActionButton(
                    text: '关闭',
                    primary: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
