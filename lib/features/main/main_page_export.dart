part of 'main_page.dart';

extension _MainPageExport on _MainPageState {
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
    final result = await _MainPageState._exportChannel.invokeMethod<String>(
      'saveBytesFile',
      {'fileName': fileName, 'bytes': bytes},
    );
    final path = result?.trim() ?? '';
    if (path.isEmpty) {
      throw StateError('文件保存失败');
    }
    return path;
  }

  Future<void> _shareLoadingSummaryProject() async {
    await _saveCurrentDraft();
    final project = _project;
    if (project == null) {
      _showNotReady('请先选择项目');
      return;
    }
    final buildingName = project.buildingName.ifEmpty('1号楼');
    final tripNames = _loadingTripNamesWithData(project, buildingName);
    if (tripNames.isEmpty) {
      _showNoDataMessage(forExport: false);
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
    await _MainPageState._exportChannel.invokeMethod<void>('shareBytesFile', {
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
    final files = _mode == MainMode.quality
        ? await _qualityExportFiles(project, rows)
        : _currentProjectStatisticsExportFiles(project);
    if (files.isEmpty) {
      _showNoDataMessage(forExport: true);
      return;
    }
    final result = await _MainPageState._exportChannel
        .invokeMethod<List<dynamic>>('exportBytesFiles', {
          'title': '选择导出位置',
          'files': files.map((file) => file.toChannelMap()).toList(),
        });
    if (!mounted) return;
    final exportedCount = result?.length ?? 0;
    if (exportedCount == 0) {
      _showNotReady('已取消导出');
    } else {
      _showNotReady(exportedCount == 1 ? '已导出文件' : '已导出$exportedCount个文件');
    }
  }

  Future<List<_ExportFilePayload>> _qualityExportFiles(
    ProjectEntity project,
    List<Map<String, String>> rows,
  ) async {
    if (!_hasRowsData(rows, MainMode.quality)) return const [];
    final photoMap = await _readQualityPhotoBase64(rows);
    return [
      _ExportFilePayload(
        fileName: _qualityDocumentFileName(project),
        bytes: utf8.encode(_buildQualityDocumentHtml(project, rows, photoMap)),
        mimeType: 'application/msword',
      ),
    ];
  }

  List<_ExportFilePayload> _currentProjectStatisticsExportFiles(
    ProjectEntity project,
  ) {
    const mimeType =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    final files = <_ExportFilePayload>[];
    if (_hasStandardData(project)) {
      files.add(
        _ExportFilePayload(
          fileName: _excelFileNameForMode(project, MainMode.standard),
          bytes: _buildStandardExcel(project),
          mimeType: mimeType,
        ),
      );
    }
    if (_hasFastData(project)) {
      files.add(
        _ExportFilePayload(
          fileName: _excelFileNameForMode(project, MainMode.fast),
          bytes: _buildFastReturnExcel(project),
          mimeType: mimeType,
        ),
      );
    }
    if (_hasLoadingData(project)) {
      files.add(
        _ExportFilePayload(
          fileName: _excelFileNameForMode(project, MainMode.loading),
          bytes: _buildLoadingExcel(project),
          mimeType: mimeType,
        ),
      );
    }
    return files;
  }

  Future<void> _shareCurrentModeExcel() async {
    await _saveCurrentDraft();
    final project = _project;
    if (project == null) {
      _showNotReady('请先选择项目');
      return;
    }
    final rows = _rows;
    if (!_hasRowsData(rows, _mode)) {
      _showNoDataMessage(forExport: false);
      return;
    }
    if (_mode == MainMode.quality) {
      await _shareQualityDocument(project, rows);
      return;
    }
    final bytes = _mode == MainMode.loading
        ? _buildLoadingExcel(project)
        : _buildCurrentModeExcel(project, rows);
    await _MainPageState._exportChannel.invokeMethod<void>('shareBytesFile', {
      'fileName': _currentModeExcelFileName(project),
      'bytes': bytes,
      'mimeType':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'title': '${project.name}${_mode.label}',
    });
  }

  void _showNoDataMessage({required bool forExport}) {
    _showNotReady(forExport ? '当前项目未录入数据，请录入数据再导出' : '当前项目未录入数据，请录入数据再分享');
  }

  bool _hasRowsData(List<Map<String, String>> rows, MainMode mode) {
    return rows.any((row) {
      if (mode == MainMode.loading && _isLoadingMetaRow(row)) return false;
      return !_isEmptyRow(row);
    });
  }

  bool _hasStandardData(ProjectEntity project) {
    final building = project.buildingName.ifEmpty('1号楼');
    final scopedRows = _readScopedData(project.standardContent, building);
    return scopedRows.values.any(
      (rows) => _hasRowsData(rows, MainMode.standard),
    );
  }

  bool _hasFastData(ProjectEntity project) {
    final building = project.buildingName.ifEmpty('1号楼');
    final scopedRows = _readScopedData(project.fastContent, building);
    return scopedRows.values.any((rows) => _hasRowsData(rows, MainMode.fast));
  }

  bool _hasLoadingData(ProjectEntity project) {
    final building = project.buildingName.ifEmpty('1号楼');
    return _loadingTripNamesWithData(project, building).isNotEmpty;
  }

  List<String> _loadingTripNamesWithData(
    ProjectEntity project,
    String buildingName,
  ) {
    return _readLoadingTripNames(
      project.loadingContent,
      buildingName: buildingName,
    ).where((tripName) {
      final rows = _decodeLoadingRowsForTrip(
        project.loadingContent,
        tripName,
        buildingName: buildingName,
      );
      return _hasRowsData(rows, MainMode.loading);
    }).toList();
  }

  Future<void> _shareQualityDocument(
    ProjectEntity project,
    List<Map<String, String>> rows,
  ) async {
    final photoMap = await _readQualityPhotoBase64(rows);
    await _MainPageState._exportChannel.invokeMethod<void>('shareTextFile', {
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
      final data = await _MainPageState._exportChannel.invokeMethod<String>(
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
}
