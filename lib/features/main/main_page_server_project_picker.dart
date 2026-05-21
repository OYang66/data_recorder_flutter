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
  Timer? _searchDebounce;
  var _loading = true;
  var _message = '请输入关键字搜索项目名称';
  var _projectNames = <String>[];
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjects(''));
  }

  @override
  void dispose() {
    _requestId++;
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _triggerSearch({bool immediate = false}) {
    _searchDebounce?.cancel();
    final keyword = _searchController.text.trim();
    if (immediate) {
      unawaited(_loadProjects(keyword));
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _loadProjects(keyword),
    );
  }

  Future<void> _loadProjects(String keyword) async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _message = '正在加载项目...';
      _projectNames = [];
    });
    try {
      final response = await widget.serverRepository.getProjectInfoList(
        keyword: keyword.trim(),
      );
      if (!mounted || requestId != _requestId) return;
      final names = (response.data ?? const <ServerProjectInfo>[])
          .map((item) => item.projectName.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      setState(() {
        _loading = false;
        _projectNames = response.isSuccess ? names : [];
        _message = response.isSuccess
            ? (names.isEmpty ? '未搜索到匹配项目' : '')
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
                  onChanged: (_) => _triggerSearch(),
                  onSubmitted: (_) => _triggerSearch(immediate: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _triggerSearch(immediate: true),
                child: const Text('搜索'),
              ),
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
