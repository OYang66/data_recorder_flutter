import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_dialog_chrome.dart';
import '../../data/models/api/server_models.dart';
import '../../data/repositories/server_repository.dart';

class SettlementDataPage extends StatefulWidget {
  const SettlementDataPage({super.key});

  @override
  State<SettlementDataPage> createState() => _SettlementDataPageState();
}

class _SettlementDataPageState extends State<SettlementDataPage> {
  static const _exportChannel = MethodChannel(
    'com.example.datarecorder/export_share',
  );

  final _repository = ServerRepository();
  final _projectController = TextEditingController();
  final List<SettlementTypeOption> _typeOptions = [];
  final List<String> _projectNames = [];
  final List<SettlementColumnItem> _columns = [];
  final List<Map<String, Object?>> _rows = [];

  String _dataType = 'deliveryOrder';
  String _dataTypeLabel = '发货清单数据';
  String _listTitle = '发货台账';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTypeOptions();
  }

  @override
  void dispose() {
    _projectController.dispose();
    super.dispose();
  }

  Future<void> _loadTypeOptions() async {
    try {
      final response = await _repository.getSettlementTypeOptions();
      if (!mounted) return;
      final options = response.data ?? const <SettlementTypeOption>[];
      setState(() {
        _typeOptions
          ..clear()
          ..addAll(
            options.isEmpty
                ? const [
                    SettlementTypeOption(
                      label: '发货清单数据',
                      value: 'deliveryOrder',
                    ),
                    SettlementTypeOption(
                      label: '材料进场汇总单',
                      value: 'materialSummary',
                    ),
                  ]
                : options,
          );
        final first = _typeOptions.first;
        _dataType = first.value.ifEmpty(_dataType);
        _dataTypeLabel = first.label.ifEmpty(_dataTypeLabel);
      });
      await _loadProjectNames();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('数据类型加载失败，请检查网络和登录状态');
    }
  }

  Future<bool> _loadProjectNames({
    bool showPageLoading = true,
    bool clearResults = true,
  }) async {
    if (showPageLoading) {
      setState(() => _loading = true);
    }
    try {
      final response = await _repository.getSettlementProjectNames(_dataType);
      if (!mounted) return false;
      setState(() {
        _projectNames
          ..clear()
          ..addAll(response.data ?? const []);
        if (clearResults) {
          _rows.clear();
          _columns.clear();
        }
        if (showPageLoading) {
          _loading = false;
        }
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      if (showPageLoading) {
        setState(() => _loading = false);
      }
      _showMessage('项目列表加载失败，请检查网络和登录状态');
      return false;
    }
  }

  Future<void> _chooseDataType() async {
    final selected = await showAppMenuCardPopup<SettlementTypeOption>(
      context: context,
      title: '选择数据类型',
      subtitle: '切换后会重新加载项目列表',
      children: [
        for (final option in _typeOptions)
          AppDialogListItem(
            label: option.label.ifEmpty(option.value),
            selected: option.value == _dataType,
            onTap: () => Navigator.of(context).pop(option),
          ),
      ],
    );
    if (selected == null) return;
    setState(() {
      _dataType = selected.value;
      _dataTypeLabel = selected.label;
      _projectController.clear();
    });
    await _loadProjectNames();
  }

  Future<void> _chooseProject() async {
    await _loadProjectNames(showPageLoading: false, clearResults: false);
    if (!mounted) return;
    if (_projectNames.isEmpty) {
      _showMessage('暂无服务器项目');
      return;
    }
    final selected = await showAppCardDialog<String>(
      context: context,
      title: '选择项目',
      subtitle: _dataTypeLabel,
      builder: (context) => _ProjectPickerDialogBody(
        projectNames: _projectNames,
        initialKeyword: _projectController.text,
        currentProjectName: _projectController.text.trim(),
      ),
    );
    if (!mounted || selected == null) return;
    _projectController.text = selected;
  }

  Future<void> _queryData() async {
    final projectName = _projectController.text.trim();
    if (projectName.isEmpty) {
      _showMessage('请先选择或输入项目名称');
      return;
    }
    setState(() => _loading = true);
    try {
      if (_dataType == 'materialSummary') {
        final response = await _repository.getSettlementMaterialSummaryRows(
          projectName,
        );
        if (!mounted) return;
        if (!response.isSuccess) {
          _showMessage(response.displayMessage.ifEmpty('查询失败'));
          setState(() => _loading = false);
          return;
        }
        setState(() {
          _listTitle = '材料进场汇总';
          _columns
            ..clear()
            ..addAll(const [
              SettlementColumnItem(prop: 'rowNo', label: '序号'),
              SettlementColumnItem(prop: 'buildingName', label: '楼栋号'),
              SettlementColumnItem(prop: 'materialName', label: '材料名称'),
              SettlementColumnItem(prop: 'area', label: '面积'),
              SettlementColumnItem(prop: 'weight', label: '重量'),
              SettlementColumnItem(prop: 'quantity', label: '数量'),
              SettlementColumnItem(prop: 'remark', label: '备注'),
            ]);
          _rows
            ..clear()
            ..addAll(response.data ?? const []);
          _loading = false;
        });
      } else {
        final columnsResponse = await _repository.getSettlementDeliveryColumns(
          projectName,
        );
        final rowsResponse = await _repository.getSettlementDeliveryRows(
          projectName,
        );
        if (!mounted) return;
        if (!columnsResponse.isSuccess || !rowsResponse.isSuccess) {
          _showMessage(
            rowsResponse.displayMessage.ifEmpty(
              columnsResponse.displayMessage.ifEmpty('查询失败'),
            ),
          );
          setState(() => _loading = false);
          return;
        }
        setState(() {
          _listTitle = '发货台账';
          _columns
            ..clear()
            ..addAll([
              const SettlementColumnItem(prop: 'rowNo', label: '序号'),
              const SettlementColumnItem(prop: 'buildingName', label: '楼栋号'),
              const SettlementColumnItem(prop: 'deliveryDate', label: '发货日期'),
              const SettlementColumnItem(prop: 'vehicleNo', label: '车牌号'),
              const SettlementColumnItem(
                prop: 'aluminumWeight',
                label: '铝模板重量',
              ),
              const SettlementColumnItem(prop: 'aluminumArea', label: '铝模板面积'),
              const SettlementColumnItem(
                prop: 'ironTotalWeight',
                label: '铁件总重',
              ),
              const SettlementColumnItem(prop: 'ironBackWeight', label: '背楞重量'),
              const SettlementColumnItem(prop: 'hangerWeight', label: '吊架重量'),
              ...(columnsResponse.data ?? const []),
            ]);
          _rows
            ..clear()
            ..addAll(rowsResponse.data ?? const []);
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('查询失败，请检查网络和登录状态');
    }
  }

  Future<void> _exportData() async {
    final projectName = _projectController.text.trim();
    if (projectName.isEmpty) {
      _showMessage('请先选择或输入项目名称');
      return;
    }
    try {
      _showMessage('正在导出$_dataTypeLabel');
      final response = _dataType == 'materialSummary'
          ? await _repository.exportSettlementMaterialSummary(projectName)
          : await _repository.exportSettlementDeliveryOrder(projectName);
      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) {
        _showMessage('导出失败，服务器未返回文件');
        return;
      }
      await _exportChannel.invokeMethod<void>('shareBytesFile', {
        'fileName':
            '${projectName}_${_dataTypeLabel}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        'bytes': bytes,
        'mimeType':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'title': '分享$_dataTypeLabel',
      });
    } on MissingPluginException {
      if (mounted) _showMessage('当前版本不支持系统分享，请更新应用');
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? '系统分享失败，请稍后重试');
    } catch (_) {
      if (mounted) _showMessage('导出失败，请检查网络和登录状态');
    }
  }

  void _showMessage(String message) {
    showAppToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettlementHeader(onBack: () => context.go('/main')),
              const SizedBox(height: 12),
              _SettlementFilterCard(
                dataTypeLabel: _dataTypeLabel,
                projectController: _projectController,
                loading: _loading,
                onChooseType: _chooseDataType,
                onChooseProject: _chooseProject,
                onSyncProjects: _loadProjectNames,
                onQuery: _queryData,
                onExport: _exportData,
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildRows()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRows() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      final projectName = _projectController.text.trim();
      return _InfoCard(
        title: _dataTypeLabel,
        subtitle: projectName.isEmpty ? '请选择项目后查询。' : '当前项目暂无数据：$projectName',
      );
    }
    return ListView.separated(
      itemCount: _rows.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _InfoCard(
            title: _listTitle,
            subtitle:
                '共 ${_rows.length} 条，项目：${_projectController.text.trim()}',
          );
        }
        final row = _rows[index - 1];
        final title =
            '${_valueText(row['rowNo'])}　${_valueText(row['buildingName'])}'
                .trim();
        final subtitle = _columns
            .map((column) {
              final value = _valueText(row[column.prop]);
              return value.isEmpty
                  ? ''
                  : '${column.label.ifEmpty(column.prop)}：$value';
            })
            .where((line) => line.isNotEmpty)
            .join('\n');
        return AppDialogListItem(
          label: title.ifEmpty('第 $index 条'),
          subtitle: subtitle,
        );
      },
    );
  }
}

String _valueText(Object? value) {
  if (value == null) return '';
  return value.toString();
}

class _ProjectPickerDialogBody extends StatefulWidget {
  const _ProjectPickerDialogBody({
    required this.projectNames,
    required this.initialKeyword,
    required this.currentProjectName,
  });

  final List<String> projectNames;
  final String initialKeyword;
  final String currentProjectName;

  @override
  State<_ProjectPickerDialogBody> createState() =>
      _ProjectPickerDialogBodyState();
}

class _ProjectPickerDialogBodyState extends State<_ProjectPickerDialogBody> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _searchController.text.trim();
    final filtered = keyword.isEmpty
        ? widget.projectNames
        : widget.projectNames.where((name) => name.contains(keyword)).toList();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: '搜索项目',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: filtered.isEmpty
                ? const Center(child: Text('没有匹配项目，可继续输入关键字'))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final name = filtered[index];
                      return AppDialogListItem(
                        label: name,
                        selected: name == widget.currentProjectName,
                        onTap: () => Navigator.of(context).pop(name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SettlementHeader extends StatelessWidget {
  const _SettlementHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '结算数据查询',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                '服务器发货台账与材料进场汇总查询、导出',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettlementFilterCard extends StatelessWidget {
  const _SettlementFilterCard({
    required this.dataTypeLabel,
    required this.projectController,
    required this.loading,
    required this.onChooseType,
    required this.onChooseProject,
    required this.onSyncProjects,
    required this.onQuery,
    required this.onExport,
  });

  final String dataTypeLabel;
  final TextEditingController projectController;
  final bool loading;
  final VoidCallback onChooseType;
  final VoidCallback onChooseProject;
  final VoidCallback onSyncProjects;
  final VoidCallback onQuery;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          TextField(
            controller: projectController,
            readOnly: true,
            showCursor: false,
            onTap: loading ? null : onChooseProject,
            decoration: const InputDecoration(labelText: '项目名称'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: loading ? null : onChooseType,
                  child: Text(dataTypeLabel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: loading ? null : onSyncProjects,
                  child: const Text('同步项目'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: loading ? null : onQuery,
                  child: const Text('查询'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: loading ? null : onExport,
                  child: const Text('分享'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
