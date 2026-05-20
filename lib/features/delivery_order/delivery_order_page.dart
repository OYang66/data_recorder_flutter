import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/storage/preferences.dart';
import '../../core/widgets/app_dialog_chrome.dart';
import '../../data/models/api/server_models.dart';
import '../../data/repositories/server_repository.dart';
import 'delivery_order_intake_service.dart';

class DeliveryOrderPage extends StatefulWidget {
  const DeliveryOrderPage({super.key, this.externalFile});

  final ExternalDeliveryOrderFile? externalFile;

  @override
  State<DeliveryOrderPage> createState() => _DeliveryOrderPageState();
}

class _DeliveryOrderPageState extends State<DeliveryOrderPage> {
  static const _pageSize = 20;
  static const _exportChannel = MethodChannel(
    'com.example.datarecorder/export_share',
  );

  final _preferences = AppPreferences();
  late final _repository = ServerRepository(preferences: _preferences);
  final _projectController = TextEditingController();
  final _fileController = TextEditingController();
  final List<DeliveryOrderFileItem> _files = [];
  final List<String> _projectNames = [];
  int _currentUserId = 0;

  int _pageNum = 1;
  int _total = 0;
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _loadProjectNames();
    _loadFiles();
    final externalFile = widget.externalFile;
    if (externalFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _confirmExternalDeliveryOrderFile(externalFile);
      });
    }
  }

  Future<void> _loadCurrentUserId() async {
    final userId = await _preferences.getUserId();
    if (!mounted) return;
    setState(() => _currentUserId = userId);
  }

  @override
  void didUpdateWidget(covariant DeliveryOrderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final externalFile = widget.externalFile;
    if (externalFile != null && externalFile.path != oldWidget.externalFile?.path) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _confirmExternalDeliveryOrderFile(externalFile);
      });
    }
  }

  @override
  void dispose() {
    _projectController.dispose();
    _fileController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectNames() async {
    try {
      final response = await _repository.getDeliveryOrderProjectNames();
      if (!mounted || !response.isSuccess) return;
      setState(() {
        _projectNames
          ..clear()
          ..addAll(response.data ?? const []);
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _loadFiles({int? pageNum}) async {
    setState(() {
      _loading = true;
      if (pageNum != null) _pageNum = pageNum;
    });
    try {
      final response = await _repository.getDeliveryOrderFiles(
        projectName: _projectController.text,
        fileName: _fileController.text,
        pageNum: _pageNum,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      if (!response.isSuccess || response.data == null) {
        _showMessage(response.displayMessage.ifEmpty('发货清单加载失败'));
        setState(() => _loading = false);
        return;
      }
      final page = response.data!;
      setState(() {
        _files
          ..clear()
          ..addAll(page.rows);
        _total = page.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('网络异常，发货清单加载失败');
    }
  }

  Future<void> _uploadDeliveryOrder({required bool calculateNetWeight}) async {
    if (_uploading) return;
    try {
      final path = await _exportChannel.invokeMethod<String>('pickDeliveryOrderFile');
      if (path == null || path.isEmpty) return;
      await _uploadDeliveryOrderFromPath(
        path,
        calculateNetWeight: calculateNetWeight,
      );
    } on MissingPluginException {
      if (mounted) _showMessage('当前版本不支持选择文件，请更新应用');
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? '文件选择失败，请检查文件权限');
    } catch (_) {
      if (mounted) _showMessage('文件选择失败，请检查文件权限');
    }
  }

  Future<void> _uploadDeliveryOrderFromPath(
    String path, {
    required bool calculateNetWeight,
  }) async {
    if (_uploading || path.trim().isEmpty) return;
    setState(() => _uploading = true);
    try {
      final response = await _repository.uploadDeliveryOrder(
        filePath: path,
        calculateNetWeight: calculateNetWeight,
      );
      if (!mounted) return;
      _showMessage(response.isSuccess
          ? response.displayMessage.ifEmpty('上传成功')
          : response.displayMessage.ifEmpty('上传失败'));
      if (response.isSuccess) await _loadFiles(pageNum: 1);
    } catch (_) {
      if (mounted) _showMessage('上传失败，请检查网络、登录状态和文件格式');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmExternalDeliveryOrderFile(
    ExternalDeliveryOrderFile file,
  ) async {
    if (_uploading) return;
    final confirmed = await showAppCardDialog<bool>(
      context: context,
      title: '上传发货清单',
      subtitle: '是否上传文件“${file.fileName}”？',
      builder: (context) => AppDialogActionRow(
        cancelText: '取消',
        confirmText: '上传',
        onCancel: () => Navigator.of(context).pop(false),
        onConfirm: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed == true) {
      await _uploadDeliveryOrderFromPath(
        file.path,
        calculateNetWeight: false,
      );
    }
  }

  Future<void> _showMissingMaterials() async {
    try {
      final response = await _repository.getDeliveryMissingMaterials();
      if (!mounted) return;
      if (!response.isSuccess) {
        _showMessage(response.displayMessage.ifEmpty('缺失物料加载失败'));
        return;
      }
      final items = response.data ?? const [];
      await showAppCardDialog<void>(
        context: context,
        title: '缺失物料',
        subtitle: items.isEmpty ? '暂无缺失物料' : '共 ${items.length} 类缺失物料',
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: items.isEmpty
              ? const Text('暂无缺失物料')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return AppDialogListItem(
                      label: item.materialName.ifEmpty('未命名物料'),
                      subtitle:
                          '出现次数：${item.count}\n来源：${item.sources.join('、').ifEmpty('-')}',
                      trailing: TextButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: item.materialName));
                          _showMessage('已复制：${item.materialName.ifEmpty('未命名物料')}');
                        },
                        child: const Text('复制'),
                      ),
                    );
                  },
                ),
        ),
      );
    } catch (error) {
      if (mounted) _showMessage('缺失物料加载失败，请检查网络和登录状态');
    }
  }

  Future<void> _showMaterialNames() async {
    try {
      final materialResponse = await _repository.getDeliveryMaterialNames();
      final missingResponse = await _repository.getDeliveryMissingMaterials();
      if (!mounted) return;
      if (!materialResponse.isSuccess) {
        _showMessage(materialResponse.displayMessage.ifEmpty('物料配置加载失败'));
        return;
      }
      final columns = _materialColumnsFromItems(materialResponse.data ?? const []);
      final missingNames = (missingResponse.data ?? const <MissingMaterialItem>[])
          .map((item) => item.materialName.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      await showAppCardDialog<void>(
        context: context,
        title: '物料配置',
        subtitle: '点击物料列，可从缺失物料中加入识别名字',
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: columns.isEmpty
                        ? const Center(child: Text('暂无物料配置'))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: columns.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final column = columns[index];
                              return AppDialogListItem(
                                label: column.materialLabel.ifEmpty(column.materialKey),
                                subtitle:
                                    '已识别名字：${column.aliases.isEmpty ? '暂无' : column.aliases.join('、')}',
                                onTap: () async {
                                  final added = await _pickMissingAlias(
                                    column: column,
                                    missingNames: missingNames,
                                  );
                                  if (added != null) {
                                    setDialogState(() => column.aliases.add(added));
                                  }
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final column = await _createMaterialColumn(
                          columns: columns,
                          missingNames: missingNames,
                        );
                        if (column != null) {
                          setDialogState(() => columns.add(column));
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('新增物料'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppDialogActionRow(
                    confirmText: '保存',
                    onCancel: () => Navigator.of(context).pop(),
                    onConfirm: () async {
                      final saved = await _saveMaterialColumns(columns);
                      if (saved && context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            );
          },
        ),
      );
    } catch (error) {
      if (mounted) _showMessage('物料配置加载失败，请检查网络和登录状态');
    }
  }

  Future<String?> _pickMissingAlias({
    required _MaterialColumnState column,
    required List<String> missingNames,
  }) async {
    final names = missingNames
        .where((name) => !column.aliases.contains(name))
        .toList();
    if (names.isEmpty) {
      _showMessage('没有可新增名字');
      return null;
    }
    return showAppMenuCardPopup<String>(
      context: context,
      title: '加入到：${column.materialLabel}',
      subtitle: '只能从缺失物料列表中选择名字',
      children: [
        for (final name in names)
          AppDialogListItem(
            label: name,
            onTap: () => Navigator.of(context).pop(name),
          ),
      ],
    );
  }

  Future<_MaterialColumnState?> _createMaterialColumn({
    required List<_MaterialColumnState> columns,
    required List<String> missingNames,
  }) async {
    if (missingNames.isEmpty) {
      _showMessage('没有缺失物料，无法新增物料列');
      return null;
    }
    final label = await _showTextInputDialog(
      title: '新增物料',
      hintText: '请输入物料列名称',
    );
    if (label == null) return null;
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty) {
      _showMessage('请输入物料列名称');
      return null;
    }
    if (!mounted) return null;
    final key = _buildMaterialKey(trimmedLabel, columns);
    final alias = await showAppMenuCardPopup<String>(
      context: context,
      title: '选择识别名字',
      subtitle: '从缺失物料中选择一个名字加入新物料列',
      children: [
        for (final name in missingNames)
          AppDialogListItem(
            label: name,
            onTap: () => Navigator.of(context).pop(name),
          ),
      ],
    );
    if (alias == null) return null;
    return _MaterialColumnState(
      materialKey: key,
      materialLabel: trimmedLabel,
      recordType: 'quantity',
      sortOrder: columns.length,
      aliases: [alias],
    );
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String hintText,
  }) {
    final controller = TextEditingController();
    return showAppCardDialog<String>(
      context: context,
      title: title,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hintText),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          const SizedBox(height: 14),
          AppDialogActionRow(
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
  }

  Future<bool> _saveMaterialColumns(List<_MaterialColumnState> columns) async {
    final confirmed = await _confirmDanger(
      title: '保存物料配置',
      message: '保存后服务器会重新解析发货清单文件，是否继续？',
      confirmText: '保存',
    );
    if (!confirmed) return false;
    try {
      final response = await _repository.saveDeliveryMaterialNames(
        _materialItemsFromColumns(columns),
      );
      if (!mounted) return false;
      _showMessage(response.isSuccess
          ? response.displayMessage.ifEmpty('保存成功')
          : response.displayMessage.ifEmpty('保存失败'));
      if (response.isSuccess) await _loadFiles(pageNum: 1);
      return response.isSuccess;
    } catch (error) {
      if (mounted) _showMessage('保存失败，请检查网络和登录状态');
      return false;
    }
  }

  Future<void> _reparseDeliveryOrders() async {
    final confirmed = await _confirmDanger(
      title: '重新解析全部发货清单',
      message: '该操作会重新解析服务器所有发货清单文件，可能耗时较久，是否继续？',
      confirmText: '重解析',
    );
    if (!confirmed) return;
    try {
      final response = await _repository.reparseDeliveryOrders();
      if (!mounted) return;
      _showMessage(response.isSuccess
          ? response.displayMessage.ifEmpty('重解析完成')
          : response.displayMessage.ifEmpty('重解析失败'));
      if (response.isSuccess) await _loadFiles(pageNum: 1);
    } catch (error) {
      if (mounted) _showMessage('重解析失败，请检查网络和登录状态');
    }
  }

  Future<void> _showUploadMenu() async {
    final selected = await showAppMenuCardPopup<bool>(
      context: context,
      title: '上传发货清单',
      subtitle: '支持 Excel 或压缩包文件',
      children: [
        AppDialogListItem(
          label: '普通上传',
          subtitle: '上传后按服务器默认规则解析',
          accent: true,
          onTap: () => Navigator.of(context).pop(false),
        ),
        AppDialogListItem(
          label: '上传并扣除配件重',
          subtitle: '上传后按净重规则解析',
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (selected == null) return;
    await _uploadDeliveryOrder(calculateNetWeight: selected);
  }

  Future<void> _showProjectPicker() async {
    if (_projectNames.isEmpty) {
      _showMessage('暂无服务器项目');
      return;
    }
    final selected = await showAppMenuCardPopup<String>(
      context: context,
      title: '选择项目',
      subtitle: '服务器发货清单项目',
      children: [
        for (final name in _projectNames)
          AppDialogListItem(
            label: name,
            selected: name == _projectController.text.trim(),
            onTap: () => Navigator.of(context).pop(name),
          ),
      ],
    );
    if (selected == null) return;
    _projectController.text = selected;
    await _loadFiles(pageNum: 1);
  }

  Future<void> _showFileActions(DeliveryOrderFileItem item) async {
    final selected = await showAppMenuCardPopup<String>(
      context: context,
      title: item.fileName.ifEmpty('发货清单'),
      subtitle: '项目：${item.projectName.ifEmpty('-')}',
      children: [
        AppDialogListItem(
          label: '查看明细',
          subtitle: '查看该文件解析出的 Sheet 明细',
          onTap: () => Navigator.of(context).pop('sheets'),
        ),
        AppDialogListItem(
          label: '下载文件',
          subtitle: '下载并分享原始发货清单文件',
          onTap: () => Navigator.of(context).pop('download'),
        ),
        AppDialogListItem(
          label: '确认净重重算',
          subtitle: '按服务器规则重新解析并扣除配件重',
          onTap: () => Navigator.of(context).pop('netWeight'),
        ),
        if (_canDeleteFile(item))
          AppDialogListItem(
            label: '删除文件',
            subtitle: '删除服务器中的该发货清单及明细',
            danger: true,
            onTap: () => Navigator.of(context).pop('delete'),
          ),
      ],
    );
    switch (selected) {
      case 'sheets':
        await _loadSheets(item.fileId);
      case 'download':
        await _downloadFile(item);
      case 'netWeight':
        await _confirmNetWeight(item.fileId);
      case 'delete':
        await _deleteFile(item);
    }
  }

  bool _canDeleteFile(DeliveryOrderFileItem item) {
    return _currentUserId > 0 && item.uploadUserId == _currentUserId;
  }

  Future<void> _downloadFile(DeliveryOrderFileItem item) async {
    final fileId = item.fileId;
    if (fileId == null) return;
    try {
      _showMessage('正在下载发货清单');
      final response = await _repository.downloadDeliveryOrder(fileId);
      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) {
        _showMessage('下载失败，服务器未返回文件');
        return;
      }
      await _exportChannel.invokeMethod<void>('shareBytesFile', {
        'fileName': item.fileName.ifEmpty('发货清单_$fileId.xlsx'),
        'bytes': bytes,
        'mimeType':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'title': '分享发货清单',
      });
    } on MissingPluginException {
      if (mounted) _showMessage('当前版本不支持系统分享，请更新应用');
    } on PlatformException catch (error) {
      if (mounted) _showMessage(error.message ?? '系统分享失败，请稍后重试');
    } catch (_) {
      if (mounted) _showMessage('下载失败，请检查网络和登录状态');
    }
  }

  Future<void> _confirmNetWeight(int? fileId) async {
    if (fileId == null) return;
    final confirmed = await _confirmDanger(
      title: '确认净重重算',
      message: '将按服务器规则重新解析该文件并扣除配件重，是否继续？',
      confirmText: '继续',
    );
    if (!confirmed) return;
    try {
      final response = await _repository.confirmDeliveryOrderNetWeight(fileId);
      if (!mounted) return;
      _showMessage(response.isSuccess
          ? response.displayMessage.ifEmpty('重算完成')
          : response.displayMessage.ifEmpty('重算失败'));
      if (response.isSuccess) await _loadFiles();
    } catch (error) {
      if (mounted) _showMessage('重算失败，请检查网络和登录状态');
    }
  }

  Future<void> _deleteFile(DeliveryOrderFileItem item) async {
    if (!_canDeleteFile(item)) {
      _showMessage('只能删除自己上传的发货清单');
      return;
    }
    final fileId = item.fileId;
    if (fileId == null) return;
    final confirmed = await _confirmDanger(
      title: '删除发货清单',
      message: '删除后服务器中的该发货清单及明细会被移除，是否继续？',
      confirmText: '删除',
    );
    if (!confirmed) return;
    try {
      final response = await _repository.deleteDeliveryOrder(fileId);
      if (!mounted) return;
      _showMessage(response.isSuccess
          ? response.displayMessage.ifEmpty('删除成功')
          : response.displayMessage.ifEmpty('删除失败'));
      if (response.isSuccess) await _loadFiles();
    } catch (error) {
      if (mounted) _showMessage('删除失败，请检查网络和登录状态');
    }
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

  Future<void> _loadSheets(int? fileId) async {
    if (fileId == null) return;
    try {
      final response = await _repository.getDeliveryOrderSheets(fileId: fileId);
      if (!mounted) return;
      if (!response.isSuccess) {
        _showMessage(response.displayMessage.ifEmpty('明细加载失败'));
        return;
      }
      final sheets = response.data ?? const [];
      await showAppCardDialog<void>(
        context: context,
        title: '发货明细',
        subtitle: sheets.isEmpty ? '暂无明细' : '共 ${sheets.length} 个 Sheet',
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          child: sheets.isEmpty
              ? const Text('暂无明细')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: sheets.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = sheets[index];
                    return AppDialogListItem(
                      label: item.sheetName.ifEmpty('未命名 Sheet'),
                      subtitle:
                          '项目：${item.projectName.ifEmpty('-')}  楼栋：${item.buildingName.ifEmpty('-')}\n日期：${item.deliveryDate.ifEmpty('-')}  车牌：${item.vehicleNo.ifEmpty('-')}\n铝重：${item.aluminumWeight}kg  面积：${item.aluminumArea}㎡\n铁件：${item.ironTotalWeight}kg  背楞：${item.ironBackWeight}kg  吊架：${item.hangerWeight}kg',
                    );
                  },
                ),
        ),
      );
    } catch (error) {
      if (mounted) _showMessage('网络异常，明细加载失败');
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
              _DeliveryHeader(onBack: () => context.go('/main')),
              const SizedBox(height: 12),
              _FilterCard(
                projectController: _projectController,
                fileController: _fileController,
                onPickProject: _showProjectPicker,
                onSearch: () => _loadFiles(pageNum: 1),
                onUpload: _showUploadMenu,
                onMissingMaterials: _showMissingMaterials,
                onMaterialNames: _showMaterialNames,
                onReparse: _reparseDeliveryOrders,
                loading: _loading,
                uploading: _uploading,
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildList()),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pageNum <= 1 || _loading
                          ? null
                          : () => _loadFiles(pageNum: _pageNum - 1),
                      child: const Text('上一页'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('第 $_pageNum 页'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _files.length < _pageSize || _loading
                          ? null
                          : () => _loadFiles(pageNum: _pageNum + 1),
                      child: const Text('下一页'),
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

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_files.isEmpty) {
      return const Center(child: Text('暂无发货清单文件'));
    }
    return ListView.separated(
      itemCount: _files.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _InfoCard(title: '共 $_total 个文件', subtitle: '当前第 $_pageNum 页，每页 $_pageSize 条');
        }
        final item = _files[index - 1];
        return AppDialogListItem(
          label: item.fileName.ifEmpty('未命名文件'),
          subtitle:
              '项目：${item.projectName.ifEmpty('-')}\nSheet：${item.sheetCount}  上传人：${item.uploadUserName.ifEmpty('-')}\n时间：${item.createTime.ifEmpty('-')}',
          onTap: () => _showFileActions(item),
        );
      },
    );
  }
}

class _MaterialColumnState {
  _MaterialColumnState({
    required this.materialKey,
    required this.materialLabel,
    required this.recordType,
    required this.sortOrder,
    required this.aliases,
  });

  final String materialKey;
  final String materialLabel;
  final String recordType;
  final int sortOrder;
  final List<String> aliases;
}

List<_MaterialColumnState> _materialColumnsFromItems(
  List<DeliveryMaterialNameItem> items,
) {
  final map = <String, _MaterialColumnState>{};
  final sorted = [...items]..sort((a, b) {
    final sort = a.sortOrder.compareTo(b.sortOrder);
    return sort != 0 ? sort : a.materialKey.compareTo(b.materialKey);
  });
  for (final item in sorted) {
    final key = item.materialKey;
    if (key.isEmpty) continue;
    final column = map.putIfAbsent(
      key,
      () => _MaterialColumnState(
        materialKey: key,
        materialLabel: item.materialLabel.ifEmpty(key),
        recordType: item.recordType.ifEmpty('quantity'),
        sortOrder: item.sortOrder,
        aliases: [],
      ),
    );
    final alias = item.aliasName.trim();
    if (alias.isNotEmpty && !column.aliases.contains(alias)) {
      column.aliases.add(alias);
    }
  }
  return map.values.toList();
}

String _buildMaterialKey(
  String label,
  List<_MaterialColumnState> columns,
) {
  final normalized = label
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^0-9A-Za-z_一-龥]'), '');
  final base = normalized.isEmpty ? 'custom' : 'custom_$normalized';
  var key = base;
  var index = 1;
  final existing = columns.map((column) => column.materialKey).toSet();
  while (existing.contains(key)) {
    key = '${base}_$index';
    index++;
  }
  return key;
}

List<DeliveryMaterialNameItem> _materialItemsFromColumns(
  List<_MaterialColumnState> columns,
) {
  final result = <DeliveryMaterialNameItem>[];
  for (var index = 0; index < columns.length; index++) {
    final column = columns[index];
    final aliases = column.aliases.where((alias) => alias.trim().isNotEmpty).toList();
    final values = aliases.isEmpty ? [column.materialLabel] : aliases;
    for (final alias in values) {
      result.add(
        DeliveryMaterialNameItem(
          materialKey: column.materialKey,
          materialLabel: column.materialLabel,
          aliasName: alias,
          recordType: column.recordType,
          sortOrder: index,
        ),
      );
    }
  }
  return result;
}

class _DeliveryHeader extends StatelessWidget {
  const _DeliveryHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 8),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '发货清单',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                '服务器发货清单查询、上传、下载与管理',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.projectController,
    required this.fileController,
    required this.onPickProject,
    required this.onSearch,
    required this.onUpload,
    required this.onMissingMaterials,
    required this.onMaterialNames,
    required this.onReparse,
    required this.loading,
    required this.uploading,
  });

  final TextEditingController projectController;
  final TextEditingController fileController;
  final VoidCallback onPickProject;
  final VoidCallback onSearch;
  final VoidCallback onUpload;
  final VoidCallback onMissingMaterials;
  final VoidCallback onMaterialNames;
  final VoidCallback onReparse;
  final bool loading;
  final bool uploading;

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
            decoration: InputDecoration(
              labelText: '项目名称',
              suffixIcon: IconButton(
                onPressed: onPickProject,
                icon: const Icon(Icons.arrow_drop_down_circle_outlined),
              ),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: fileController,
            decoration: const InputDecoration(labelText: '文件名，可留空'),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => loading ? null : onSearch(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: FilledButton(
                    onPressed: loading || uploading ? null : onSearch,
                    child: const Text('查询'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed: loading || uploading ? null : onUpload,
                    child: Text(uploading ? '上传中...' : '上传'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: loading || uploading ? null : onMissingMaterials,
                  child: const Text('缺失物料'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: loading || uploading ? null : onMaterialNames,
                  child: const Text('物料配置'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: loading || uploading ? null : onReparse,
                  child: const Text('重解析'),
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
          Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
