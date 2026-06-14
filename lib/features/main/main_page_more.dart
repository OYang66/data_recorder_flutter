part of 'main_page.dart';

extension _MainPageMore on _MainPageState {
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

  bool _isOfflineAccountText(String value) {
    final text = value.trim().toLowerCase();
    if (text.isEmpty) return false;
    return text == '0' ||
        text == 'false' ||
        text == 'offline' ||
        text.contains('离线') ||
        text.contains('下线') ||
        text.contains('失效') ||
        text.contains('过期') ||
        text.contains('重新登录');
  }

  Future<bool> _isAccountOnline(String username) async {
    final account = username.trim();
    if (account.isEmpty || !await _preferences.isLoggedIn()) {
      return false;
    }
    try {
      final response = await AuthRepository(
        preferences: _preferences,
      ).checkAccountStatus(account);
      if (!response.isSuccess) {
        return false;
      }
      final status = response.data;
      if (status == null || !status.valid) {
        return false;
      }
      final statusText = [
        status.onlineStatus ?? '',
        status.message ?? '',
        response.displayMessage,
      ].join(' ');
      return !_isOfflineAccountText(statusText);
    } catch (error) {
      if (error is DioException) {
        final errorText = [
          error.response?.data?.toString() ?? '',
          error.message ?? '',
        ].join(' ');
        if (error.response?.statusCode == 401 ||
            _isOfflineAccountText(errorText)) {
          return false;
        }
      }
      return false;
    }
  }

  Future<void> _showAccountMenu(BuildContext anchorContext) async {
    final username = await _preferences.getUsername();
    final isOnline = await _isAccountOnline(username);
    if (!mounted || !anchorContext.mounted) return;
    _setMainState(() => _username = username);

    await _showAnchoredCard<void>(
      anchorContext: anchorContext,
      width: 300,
      maxHeight: 270,
      child: _AccountPopupCard(
        username: username.ifEmpty('未登录账号'),
        avatarText: _avatarText,
        online: isOnline,
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
      await _MainPageState._updateChannel.invokeMethod<void>('openUrl', {
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
      final sessionCount = data?.sessionCount ?? devices.length;
      _setMainState(() {
        _subDisplayConnected = data?.connected == true || sessionCount > 0;
        _subDisplaySessionCount = sessionCount;
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

  String _normalizeAppDownloadUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final baseUrl = ApiConstants.baseUrl.endsWith('/')
        ? ApiConstants.baseUrl.substring(0, ApiConstants.baseUrl.length - 1)
        : ApiConstants.baseUrl;
    final path = url.startsWith('/') ? url : '/$url';
    return '$baseUrl$path';
  }

  Future<void> _showIosUpdateUnavailable(String versionName) {
    return showAppCardDialog<void>(
      context: context,
      title: 'iOS 暂无在线更新方式',
      subtitle: '苹果系统限制',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('已检测到新版本 $versionName，但因苹果系统限制，当前 iOS 版本暂不支持在应用内直接下载安装更新。'),
          const SizedBox(height: 16),
          AppDialogActionButton(
            text: '知道了',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<int> _installedAppVersionCode() async {
    if (!Platform.isAndroid) return 0;
    try {
      final version = await _MainPageState._updateChannel
          .invokeMapMethod<String, Object?>('getInstalledVersion');
      final value = version?['versionCode'];
      return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _checkAppUpdate({
    bool showNoUpdateToast = true,
    bool showErrorToast = true,
  }) async {
    try {
      final response = await _versionRepository.getLatestVersion();
      final info = response.data;
      if (!mounted) return;
      if (!response.isSuccess || info == null || info.downloadUrl.isEmpty) {
        if (showNoUpdateToast) {
          _showNotReady(response.displayMessage.ifEmpty('当前已是最新版本'));
        }
        return;
      }
      final installedVersionCode = await _installedAppVersionCode();
      if (!mounted) return;
      if (installedVersionCode > 0 &&
          info.versionCode <= installedVersionCode) {
        if (showNoUpdateToast) {
          _showNotReady('当前已是最新版本');
        }
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
      if (shouldUpdate != true || !mounted) return;
      if (Platform.isIOS) {
        await _showIosUpdateUnavailable(info.versionName);
        return;
      }
      _showNotReady('正在下载更新，请稍候');
      await _MainPageState._updateChannel
          .invokeMethod<String>('downloadAndInstall', {
            'url': _normalizeAppDownloadUrl(info.downloadUrl),
            'versionCode': info.versionCode,
          });
    } catch (error) {
      if (mounted && showErrorToast) _showNotReady('更新失败，请检查网络');
    }
  }

  Future<void> _showHistoryDialog() async {
    final history = await _listHistory();
    final historyGroups = _groupHistoryByProject(history);
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
              child: historyGroups.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('暂无历史备份'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: historyGroups.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, groupIndex) {
                        final group = historyGroups[groupIndex];
                        return Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            childrenPadding: const EdgeInsets.only(
                              left: 8,
                              right: 8,
                              bottom: 8,
                            ),
                            title: Text(
                              group.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('${group.value.length} 个备份'),
                            children: [
                              for (
                                var index = 0;
                                index < group.value.length;
                                index++
                              ) ...[
                                if (index > 0) const SizedBox(height: 8),
                                Builder(
                                  builder: (context) {
                                    final item = group.value[index];
                                    final path = item['path']?.toString() ?? '';
                                    return AppDialogListItem(
                                      label: _formatHistoryTime(
                                        item['modified'],
                                      ).ifEmpty(item['name']?.toString() ?? ''),
                                      subtitle: item['name']?.toString() ?? '',
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
                              ],
                            ],
                          ),
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
    final result = await _MainPageState._exportChannel
        .invokeListMethod<Object?>('listHistory');
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
    await _MainPageState._exportChannel.invokeMethod<String>('saveHistory', {
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
    final content = await _MainPageState._exportChannel.invokeMethod<String>(
      'readHistory',
      {'path': path},
    );
    if (content == null || content.isEmpty) return;
    final Map<String, Object?> json;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, Object?>) {
        _showNotReady('备份文件格式无效');
        return;
      }
      json = decoded;
    } catch (_) {
      _showNotReady('备份文件格式无效');
      return;
    }
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
    _setMainState(() {
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
    await _MainPageState._exportChannel.invokeMethod<bool>('deleteHistory', {
      'path': path,
    });
    if (mounted) _showNotReady('历史备份已删除');
  }

  List<MapEntry<String, List<Map<String, Object?>>>> _groupHistoryByProject(
    List<Map<String, Object?>> history,
  ) {
    final groups = <String, List<Map<String, Object?>>>{};
    for (final item in history) {
      final projectName = _historyProjectName(item);
      groups.putIfAbsent(projectName, () => []).add(item);
    }
    final entries = groups.entries.toList();
    for (final entry in entries) {
      entry.value.sort(
        (left, right) => _historyModifiedMillis(
          right,
        ).compareTo(_historyModifiedMillis(left)),
      );
    }
    entries.sort((left, right) {
      final rightTime = right.value.isEmpty
          ? 0
          : _historyModifiedMillis(right.value.first);
      final leftTime = left.value.isEmpty
          ? 0
          : _historyModifiedMillis(left.value.first);
      final timeCompare = rightTime.compareTo(leftTime);
      if (timeCompare != 0) return timeCompare;
      return left.key.compareTo(right.key);
    });
    return entries;
  }

  String _historyProjectName(Map<String, Object?> item) {
    const marker = '_历史数据自动备份_';
    final name = item['name']?.toString() ?? '';
    final markerIndex = name.indexOf(marker);
    final projectName = markerIndex <= 0
        ? ''
        : name.substring(0, markerIndex).trim();
    return projectName.isEmpty ? '未分类项目' : projectName;
  }

  int _historyModifiedMillis(Map<String, Object?> item) {
    final value = item['modified'];
    return value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatHistoryTime(Object? value) {
    final millis = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    if (millis <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(millis).toString();
  }
}
