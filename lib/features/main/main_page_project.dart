part of 'main_page.dart';

extension _MainPageProject on _MainPageState {
  void _showProjectMenu(BuildContext anchorContext) {
    _showAnchoredMenu<void>(
      anchorContext: anchorContext,
      title: '项目菜单',
      subtitle: _project?.name ?? '请选择项目',
      children: [
        AppDialogListItem(
          label: '选择项目',
          accent: true,
          onTap: () {
            Navigator.of(context).pop();
            _selectProject();
          },
        ),
        AppDialogListItem(
          label: '新建项目',
          onTap: () {
            Navigator.of(context).pop();
            _createProject();
          },
        ),
        AppDialogListItem(
          label: '查看服务器项目',
          onTap: () {
            Navigator.of(context).pop();
            _showServerProjectDialog();
          },
        ),
      ],
    );
  }

  Future<void> _selectProject() async {
    if (_projects.isEmpty) {
      _showNotReady('暂无项目');
      return;
    }
    await showAppCardDialog<void>(
      context: context,
      title: '选择项目',
      subtitle: '点击切换项目，右侧可删除项目',
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < _projects.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      AppDialogListItem(
                        label: _projects[index].name,
                        subtitle: _projects[index].id == _project?.id
                            ? '当前项目'
                            : null,
                        selected: _projects[index].id == _project?.id,
                        trailing: _ProjectDeleteButton(
                          onPressed: () {
                            final project = _projects[index];
                            Navigator.of(context).pop();
                            unawaited(_deleteProject(project));
                          },
                        ),
                        onTap: () {
                          final project = _projects[index];
                          Navigator.of(context).pop();
                          unawaited(_switchProject(project));
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: AppDialogActionButton(
                text: '关闭',
                primary: false,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchProject(ProjectEntity project) async {
    if (project.id == _project?.id) return;
    await _saveCurrentDraft();
    if (!mounted) return;
    _setMainState(() {
      _project = project;
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    _clearCurrentRow();
    await _saveMainState();
  }

  Future<void> _deleteProject(ProjectEntity project) async {
    final confirmed = await _confirmDanger(
      title: '删除项目',
      message: '是否删除项目“${project.name}”？删除后该项目的本地数据会被清空。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    final deletingCurrent = project.id == _project?.id;
    await _repository.delete(project);
    if (!mounted) return;
    _projects.removeWhere((item) => item.id == project.id);
    if (!deletingCurrent) {
      _setMainState(() {});
      _showNotReady('已删除项目：${project.name}');
      return;
    }

    final nextProject = _projects.firstOrNull ?? await _createDefaultProject();
    if (!_projects.any((item) => item.id == nextProject.id)) {
      _projects.insert(0, nextProject);
    }
    if (!mounted) return;
    _setMainState(() {
      _project = nextProject;
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    _clearCurrentRow();
    await _saveMainState();
    _showNotReady('已删除项目：${project.name}');
  }

  Future<void> _showServerProjectDialog() async {
    final selectedName = await _showServerProjectPicker();
    if (!mounted || selectedName == null) return;
    await _syncServerProject(selectedName);
  }

  Future<String?> _showServerProjectPicker() {
    return showAppCardDialog<String>(
      context: context,
      title: '新建项目',
      subtitle: '搜索服务器项目并同步到本地',
      builder: (context) =>
          _ServerProjectPickerBody(serverRepository: _serverRepository),
    );
  }

  Future<void> _syncServerProject(String projectName) async {
    final safeProjectName = projectName.trim();
    if (safeProjectName.isEmpty) {
      _showNotReady('项目名称无效');
      return;
    }

    final sameNameProjects = await _repository.getByNameList(safeProjectName);
    if (!mounted) return;
    final existing = sameNameProjects.firstOrNull;
    if (existing != null) {
      if (existing.id == _project?.id) {
        _showNotReady('当前项目“$safeProjectName”已经打开，原有数据已保留。');
        return;
      }
      if (!_projects.any((project) => project.id == existing.id)) {
        _setMainState(() => _projects.insert(0, existing));
      }
      await _switchProject(existing);
      if (!mounted) return;
      _showNotReady('项目“$safeProjectName”已存在，已切换到现有项目，原有数据已保留。');
      return;
    }

    var buildingNames = <String>['1号楼'];
    try {
      final buildingResponse = await _serverRepository.getProjectBuildings(
        safeProjectName,
      );
      if (!mounted) return;
      if (!buildingResponse.isSuccess) {
        _showNotReady(buildingResponse.displayMessage.ifEmpty('获取楼栋失败'));
        return;
      }
      final serverBuildings = buildingResponse.data
          ?.map((item) => item.buildingName.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      if (serverBuildings != null && serverBuildings.isNotEmpty) {
        buildingNames = serverBuildings;
      }
    } catch (_) {
      if (!mounted) return;
      _showNotReady('获取楼栋失败，请检查网络和登录状态');
      return;
    }

    await _saveCurrentDraft();
    if (!mounted) return;
    final buildingName = buildingNames.first;
    final contents = _emptyProjectContents(buildingNames, buildingName);
    final id = await _repository.insert(
      ProjectEntity(
        name: safeProjectName,
        buildingName: buildingName,
        standardContent: contents.standard,
        fastContent: contents.fast,
        loadingContent: contents.loading,
        qualityContent: contents.quality,
      ),
    );
    final project = ProjectEntity(
      id: id,
      name: safeProjectName,
      buildingName: buildingName,
      standardContent: contents.standard,
      fastContent: contents.fast,
      loadingContent: contents.loading,
      qualityContent: contents.quality,
    );
    if (!mounted) return;
    _setMainState(() {
      _projects.insert(0, project);
      _project = project;
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    _clearCurrentRow();
    await _saveMainState();
    if (!mounted) return;
    _showNotReady('已同步项目：$safeProjectName');
  }

  Future<ProjectEntity> _createDefaultProject() async {
    const buildingName = '1号楼';
    final contents = _emptyProjectContents(const [buildingName], buildingName);
    final id = await _repository.insert(
      ProjectEntity(
        name: '默认项目',
        buildingName: buildingName,
        standardContent: contents.standard,
        fastContent: contents.fast,
        loadingContent: contents.loading,
        qualityContent: contents.quality,
      ),
    );
    return ProjectEntity(
      id: id,
      name: '默认项目',
      buildingName: buildingName,
      standardContent: contents.standard,
      fastContent: contents.fast,
      loadingContent: contents.loading,
      qualityContent: contents.quality,
    );
  }

  Future<void> _createProject() async {
    await _showServerProjectDialog();
  }

  Future<void> _showBuildingMenu(BuildContext anchorContext) async {
    if (_project == null) {
      _showNotReady('请先选择或新建项目');
      return;
    }
    final buildings = _buildingNames();
    await _showAnchoredMenu<void>(
      anchorContext: anchorContext,
      title: '楼栋管理',
      subtitle: _currentBuildingName.ifEmpty('请选择楼栋'),
      children: [
        const _DialogSectionTitle(text: '当前楼栋'),
        for (final building in buildings)
          AppDialogListItem(
            label: building,
            selected: building == _currentBuildingName,
            onTap: () {
              Navigator.of(context).pop();
              _switchBuilding(building);
            },
          ),
        const _DialogSectionTitle(text: '操作'),
        AppDialogListItem(
          label: '增加楼栋',
          accent: true,
          onTap: () {
            Navigator.of(context).pop();
            _addBuilding();
          },
        ),
        AppDialogListItem(
          label: '删除当前楼栋',
          danger: true,
          onTap: () {
            Navigator.of(context).pop();
            _deleteCurrentBuilding();
          },
        ),
      ],
    );
  }

  List<String> _buildingNames() {
    final project = _project;
    if (project == null) return ['1号楼'];
    final names = <String>{
      if (project.buildingName.isNotEmpty) project.buildingName,
      ..._readBuildingScopedData(project.standardContent).keys,
      ..._readBuildingScopedData(project.fastContent).keys,
      ..._readBuildingScopedData(project.loadingContent).keys,
      ..._readBuildingScopedData(project.qualityContent).keys,
    }.toList();
    return names.isEmpty ? ['1号楼'] : names;
  }

  Future<void> _switchBuilding(String buildingName) async {
    final project = _project;
    if (project == null || buildingName.trim().isEmpty) return;
    if (buildingName == _currentBuildingName) return;
    await _saveCurrentDraft();
    final updated = _ensureBuildingContent(
      project,
      buildingName,
    ).copyWith(buildingName: buildingName);
    if (!mounted) return;
    _setMainState(() {
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    await _updateProject(updated);
    _clearCurrentRow();
  }

  Future<void> _addBuilding() async {
    final value = await _showTextInputDialog(
      title: '增加楼栋',
      subtitle: '新增后会自动切换到新楼栋',
      label: '楼栋名称',
      hintText: '请输入楼栋号，如：2号楼',
    );
    final buildingName = value?.trim();
    if (buildingName == null || buildingName.isEmpty) {
      _showNotReady('楼栋号不能为空');
      return;
    }
    if (_buildingNames().contains(buildingName)) {
      _showNotReady('楼栋已存在');
      return;
    }
    final project = _project;
    if (project == null) return;
    await _saveCurrentDraft();
    final updated = _ensureBuildingContent(
      project,
      buildingName,
    ).copyWith(buildingName: buildingName);
    if (!mounted) return;
    _setMainState(() {
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    await _updateProject(updated);
    _clearCurrentRow();
  }

  Future<void> _deleteCurrentBuilding() async {
    final project = _project;
    if (project == null) return;
    final current = project.buildingName;
    if (current.isEmpty) return;
    final buildings = _buildingNames();
    if (buildings.length <= 1) {
      _showNotReady('至少需要保留一个楼栋');
      return;
    }
    final confirmed = await _confirmDanger(
      title: '确认删除',
      message: '是否删除$current数据？\n删除后无法恢复。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    await _saveCurrentDraft();
    final currentIndex = buildings.indexOf(current);
    final remaining = buildings.where((name) => name != current).toList();
    final fallback = remaining.elementAtOrNull(currentIndex) ?? remaining.last;
    final standard = _readBuildingScopedData(project.standardContent)
      ..remove(current);
    final fast = _readBuildingScopedData(project.fastContent)..remove(current);
    final loading = _readLoadingBuildingContents(project.loadingContent)
      ..remove(current);
    final quality = _readBuildingScopedData(project.qualityContent)
      ..remove(current);
    if (!mounted) return;
    _setMainState(() {
      _packageName = '第1包';
      _tripName = '第1车';
      _qualityFloor = '铝模1层';
    });
    await _updateProject(
      project.copyWith(
        buildingName: fallback,
        standardContent: _encodeBuildingScopedData(
          standard,
          currentBuildingName: fallback,
        ),
        fastContent: _encodeBuildingScopedData(
          fast,
          currentBuildingName: fallback,
        ),
        loadingContent: _encodeLoadingBuildingContents(
          loading,
          currentBuildingName: fallback,
        ),
        qualityContent: _encodeBuildingScopedData(
          quality,
          currentBuildingName: fallback,
        ),
      ),
    );
    _clearCurrentRow();
    _showNotReady('已删除：$current');
  }

  Future<void> _editScope(BuildContext anchorContext) async {
    if (_project == null) {
      _showNotReady('请先选择或新建项目');
      return;
    }
    if (_mode == MainMode.quality) {
      await _showQualityFloorInputDialog(anchorContext: anchorContext);
      return;
    }
    final scopes = _scopeNamesForMode();
    final isLoading = _mode == MainMode.loading;
    final title = isLoading ? '车次管理' : '包号管理';
    final subtitle = _scopeName.isEmpty
        ? (isLoading ? '请选择或新增车次' : '请选择或新增包号')
        : _scopeName;
    final currentSection = isLoading ? '当前车次' : '当前包号';
    await _showAnchoredMenu<void>(
      anchorContext: anchorContext,
      title: title,
      subtitle: subtitle,
      children: [
        _DialogSectionTitle(text: currentSection),
        for (final scope in scopes)
          AppDialogListItem(
            label: scope,
            selected: scope == _scopeName,
            onTap: () {
              Navigator.of(context).pop();
              unawaited(_setScope(scope));
            },
          ),
        const _DialogSectionTitle(text: '操作'),
        AppDialogListItem(
          label: '新增${_mode.scopeLabel}',
          accent: true,
          onTap: () {
            Navigator.of(context).pop();
            _addScope();
          },
        ),
        AppDialogListItem(
          label: '删除当前${_mode.scopeLabel}',
          danger: true,
          onTap: () {
            Navigator.of(context).pop();
            _deleteCurrentScope();
          },
        ),
      ],
    );
  }

  List<String> _scopeNamesForMode() {
    final names = _mode == MainMode.loading
        ? _readLoadingTripNames(
            _contentForMode(_mode),
            buildingName: _currentBuildingName,
          )
        : _readScopedData(
            _contentForMode(_mode),
            _currentBuildingName,
          ).keys.toList();
    if (!names.contains(_scopeName)) names.insert(0, _scopeName);
    return names.isEmpty ? [_scopeName] : names;
  }

  Future<void> _setScope(String scope, {bool saveBeforeSwitch = true}) async {
    if (saveBeforeSwitch) {
      await _saveCurrentDraft();
      if (!mounted) return;
    }
    _setMainState(() {
      switch (_mode) {
        case MainMode.loading:
          _tripName = scope;
        case MainMode.quality:
          _qualityFloor = scope;
        case MainMode.standard:
        case MainMode.fast:
          _packageName = scope;
      }
    });
    _clearCurrentRow();
    await _saveMainState();
  }

  Future<void> _addScope() async {
    if (_mode == MainMode.quality) {
      await _showQualityFloorInputDialog();
      return;
    }
    final project = _project;
    if (project == null) return;
    await _saveCurrentDraft();
    if (!mounted) return;
    final scope = _nextScopeName();
    final content = _mode == MainMode.loading
        ? _encodeLoadingRowsForTrip(
            _contentForMode(_mode),
            scope,
            const <Map<String, String>>[],
            buildingName: _currentBuildingName,
          )
        : _encodeRowsForScope(
            _contentForMode(_mode),
            _currentBuildingName,
            scope,
            const <Map<String, String>>[],
          );
    final updated = switch (_mode) {
      MainMode.standard => (_project ?? project).copyWith(
        standardContent: content,
      ),
      MainMode.fast => (_project ?? project).copyWith(fastContent: content),
      MainMode.loading => (_project ?? project).copyWith(
        loadingContent: content,
      ),
      MainMode.quality => (_project ?? project).copyWith(
        qualityContent: content,
      ),
    };
    await _updateProject(updated);
    if (!mounted) return;
    await _setScope(scope, saveBeforeSwitch: false);
  }

  Future<void> _deleteCurrentScope() async {
    final project = _project;
    if (project == null) return;
    final confirmed = await _confirmDanger(
      title: '删除当前${_mode.scopeLabel}',
      message: '是否删除$_scopeName数据？\n删除后无法恢复。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    final content = _mode == MainMode.loading
        ? _removeLoadingTrip(
            _contentForMode(_mode),
            _tripName,
            buildingName: _currentBuildingName,
          )
        : () {
            final buildingScoped = _readBuildingScopedData(
              _contentForMode(_mode),
            );
            final scoped = Map<String, List<Map<String, String>>>.from(
              buildingScoped[_currentBuildingName] ?? const {},
            );
            scoped.remove(_scopeName);
            buildingScoped[_currentBuildingName] = scoped;
            return _encodeBuildingScopedData(
              buildingScoped,
              currentBuildingName: _currentBuildingName,
            );
          }();
    final fallback = _mode == MainMode.loading
        ? (_readLoadingTripNames(
                content,
                buildingName: _currentBuildingName,
              ).firstOrNull ??
              _defaultScopeName())
        : _readScopedData(content, _currentBuildingName).keys.firstOrNull ??
              _defaultScopeName();
    final nextContent =
        _mode == MainMode.loading &&
            _readLoadingTripNames(
              content,
              buildingName: _currentBuildingName,
            ).isEmpty
        ? _encodeLoadingRowsForTrip(
            content,
            fallback,
            const <Map<String, String>>[],
            buildingName: _currentBuildingName,
          )
        : content;
    final updated = switch (_mode) {
      MainMode.standard => project.copyWith(standardContent: nextContent),
      MainMode.fast => project.copyWith(fastContent: nextContent),
      MainMode.loading => project.copyWith(loadingContent: nextContent),
      MainMode.quality => project.copyWith(qualityContent: nextContent),
    };
    await _updateProject(updated);
    if (!mounted) return;
    await _setScope(fallback, saveBeforeSwitch: false);
  }

  String _nextScopeName() {
    final prefix = switch (_mode) {
      MainMode.loading => '第',
      MainMode.quality => '铝模',
      _ => '第',
    };
    final suffix = switch (_mode) {
      MainMode.loading => '车',
      MainMode.quality => '层',
      _ => '包',
    };
    final existing = _scopeNamesForMode().toSet();
    for (var index = 1; index < 100; index++) {
      final name = _mode == MainMode.quality
          ? '$prefix$index$suffix'
          : '$prefix$index$suffix';
      if (!existing.contains(name)) return name;
    }
    return _scopeName;
  }

  String _defaultScopeName() => switch (_mode) {
    MainMode.loading => '第1车',
    MainMode.quality => '铝模1层',
    _ => '第1包',
  };

  Future<void> _showQualityFloorInputDialog({
    BuildContext? anchorContext,
  }) async {
    final currentNumber =
        RegExp(r'\d+').firstMatch(_qualityFloor)?.group(0) ?? '';
    final value = await _showTextInputDialog(
      anchorContext: anchorContext,
      title: '输入铝模层数',
      subtitle: '当前质量反馈模式下的楼层标签',
      label: '铝模层数',
      hintText: '请输入层数',
      initialValue: currentNumber,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
    final text = value?.trim();
    if (text == null) return;
    if (text.isEmpty) {
      _showNotReady('请输入层数');
      return;
    }
    await _setScope('铝模$text层');
  }

  Future<String?> _showTextInputDialog({
    BuildContext? anchorContext,
    required String title,
    required String label,
    String? subtitle,
    String? hintText,
    String initialValue = '',
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final controller = TextEditingController(text: initialValue);
    final field = TextField(
      controller: controller,
      autofocus: true,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(labelText: label, hintText: hintText),
    );
    final actions = AppDialogActionRow(
      onCancel: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop();
      },
      onConfirm: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(controller.text);
      },
    );
    final future = anchorContext == null
        ? showAppCardDialog<String>(
            context: context,
            title: title,
            subtitle: subtitle ?? label,
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [field, const SizedBox(height: 16), actions],
            ),
          )
        : _showAnchoredCard<String>(
            anchorContext: anchorContext,
            width: 320,
            maxHeight: 260,
            child: _AnchoredMenuCard(
              title: title,
              subtitle: subtitle ?? label,
              maxHeight: 170,
              children: [field, actions],
            ),
          );
    return future.whenComplete(controller.dispose);
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
}
