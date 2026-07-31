part of 'main_page.dart';

class _ServerProjectPickerBody extends StatefulWidget {
  const _ServerProjectPickerBody({required this.serverRepository});

  final ServerRepository serverRepository;

  @override
  State<_ServerProjectPickerBody> createState() =>
      _ServerProjectPickerBodyState();
}

class _ServerProjectPickerBodyState extends State<_ServerProjectPickerBody> {
  final _searchController = TextEditingController();
  var _loading = true;
  var _message = '请输入关键字搜索项目名称';
  var _allProjectNames = <String>[];
  var _projectNames = <String>[];
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjects());
  }

  @override
  void dispose() {
    _requestId++;
    _searchController.dispose();
    super.dispose();
  }

  void _filterProjects() {
    final matches = filterProjectNames(
      _allProjectNames,
      _searchController.text,
    );
    setState(() {
      _projectNames = matches;
      _message = matches.isEmpty ? '未搜索到匹配项目' : '';
    });
  }

  Future<void> _loadProjects() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _message = '正在加载项目...';
      _projectNames = [];
    });
    try {
      final response = await widget.serverRepository.getProjectInfoList();
      if (!mounted || requestId != _requestId) return;
      final names = filterProjectNames(
        (response.data ?? const <ServerProjectInfo>[]).map(
          (item) => item.projectName,
        ),
        '',
      );
      final matches = filterProjectNames(names, _searchController.text);
      setState(() {
        _loading = false;
        _allProjectNames = response.isSuccess ? names : [];
        _projectNames = response.isSuccess ? matches : [];
        _message = response.isSuccess
            ? (matches.isEmpty ? '未搜索到匹配项目' : '')
            : response.displayMessage.ifEmpty('加载项目失败');
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _projectNames = [];
        _message = '加载项目失败，请检查网络和登录状态';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '输入关键字搜索项目名称',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => _filterProjects(),
                  onSubmitted: (_) => _filterProjects(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _filterProjects, child: const Text('搜索')),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _projectNames.isEmpty
                ? Center(child: Text(_message))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _projectNames.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final name = _projectNames[index];
                      return AppDialogListItem(
                        label: name,
                        subtitle: '服务器项目',
                        onTap: () => Navigator.of(context).pop(name),
                      );
                    },
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
    );
  }
}
