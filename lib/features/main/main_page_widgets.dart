part of 'main_page.dart';

class _AnchoredMenuCard extends StatelessWidget {
  const _AnchoredMenuCard({
    required this.title,
    this.subtitle,
    required this.maxHeight,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final double maxHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFF8F5FF)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE4DAFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF211B31),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8572B8),
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primary,
                    Color(0xFFA98CF7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < children.length; index++) ...[
                      if (index > 0) const SizedBox(height: 9),
                      children[index],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogSectionTitle extends StatelessWidget {
  const _DialogSectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2, left: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF8572B8),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _AccountPopupCard extends StatelessWidget {
  const _AccountPopupCard({
    required this.username,
    required this.avatarText,
    required this.online,
    required this.connectionCountText,
    required this.subDisplayStatusText,
    required this.hasSubDisplayCode,
    required this.onViewDevices,
    required this.onSubDisplayCode,
    required this.onOpenBackend,
    required this.onRelogin,
    required this.onLogout,
  });

  final String username;
  final String avatarText;
  final bool online;
  final String connectionCountText;
  final String subDisplayStatusText;
  final bool hasSubDisplayCode;
  final VoidCallback onViewDevices;
  final VoidCallback onSubDisplayCode;
  final VoidCallback onOpenBackend;
  final VoidCallback onRelogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFF8F5FF)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE4DAFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _AccountAvatar(text: avatarText),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF2F2A3D),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        online ? '当前账号在线' : '当前账号离线',
                        style: const TextStyle(
                          color: Color(0xFF8A7AB8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(text: online ? '在线' : '离线', active: online),
                if (!online) ...[
                  const SizedBox(width: 8),
                  _AccountSmallButton(
                    text: '重新登录',
                    primary: true,
                    onTap: onRelogin,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _AccountInfoRow(
              label: '当前连接',
              value: connectionCountText,
              buttonText: '查看设备',
              primaryButton: false,
              onTap: onViewDevices,
            ),
            const SizedBox(height: 8),
            _AccountInfoRow(
              label: '子软件状态',
              valueWidget: _StatusPill(
                text: subDisplayStatusText,
                active: subDisplayStatusText == '已连接',
              ),
              buttonText: hasSubDisplayCode ? '查看连接码' : '生成连接码',
              primaryButton: !hasSubDisplayCode,
              onTap: onSubDisplayCode,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _AccountLargeButton(
                    text: '访问后台',
                    primary: true,
                    onTap: onOpenBackend,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AccountLargeButton(text: '退出登录', onTap: onLogout),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [_legacyPurpleStart, Color(0xFF8B74D1)],
        ),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AccountInfoRow extends StatelessWidget {
  const _AccountInfoRow({
    required this.label,
    this.value,
    this.valueWidget,
    required this.buttonText,
    required this.primaryButton,
    required this.onTap,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final String buttonText;
  final bool primaryButton;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4DAFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8A7AB8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                valueWidget ??
                    Text(
                      value ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF2F2A3D),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _AccountSmallButton(
            text: buttonText,
            primary: primaryButton,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEAF8F0) : const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFFBFE7CF) : const Color(0xFFD7DCE2),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? const Color(0xFF2E8B57) : const Color(0xFF6B7280),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AccountSmallButton extends StatelessWidget {
  const _AccountSmallButton({
    required this.text,
    required this.onTap,
    this.primary = false,
  });

  final String text;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: _AccountButtonContent(text: text, primary: primary, onTap: onTap),
    );
  }
}

class _AccountLargeButton extends StatelessWidget {
  const _AccountLargeButton({
    required this.text,
    required this.onTap,
    this.primary = false,
  });

  final String text;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: _AccountButtonContent(text: text, primary: primary, onTap: onTap),
    );
  }
}

class _AccountButtonContent extends StatelessWidget {
  const _AccountButtonContent({
    required this.text,
    required this.primary,
    required this.onTap,
  });

  final String text;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: primary
            ? const LinearGradient(
                colors: [AppColors.primaryAlt, Color(0xFF8067C8)],
              )
            : null,
        color: primary ? null : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primary ? Colors.transparent : const Color(0xFFDCE3F1),
        ),
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: primary ? Colors.white : AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _TopMenu extends StatelessWidget {
  const _TopMenu({
    required this.projectLabel,
    required this.buildingLabel,
    required this.scopeLabel,
    required this.avatarText,
    required this.onProject,
    required this.onBuilding,
    required this.onScope,
    required this.onMore,
    required this.onAvatar,
  });
  final String projectLabel;
  final String buildingLabel;
  final String scopeLabel;
  final String avatarText;
  final void Function(BuildContext context) onProject;
  final void Function(BuildContext context) onBuilding;
  final void Function(BuildContext context) onScope;
  final void Function(BuildContext context) onMore;
  final void Function(BuildContext context) onAvatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: _groupDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: projectLabel,
                onPressed: () => onProject(buttonContext),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: buildingLabel,
                onPressed: () => onBuilding(buttonContext),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: scopeLabel,
                onPressed: () => onScope(buttonContext),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: '更多',
                onPressed: () => onMore(buttonContext),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Builder(
            builder: (avatarContext) => InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onAvatar(avatarContext),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [_legacyPurpleStart, Color(0xFF8B74D1)],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    avatarText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectBar extends StatelessWidget {
  const _ProjectBar({
    required this.projectName,
    required this.modeLabel,
    required this.connectCodeLabel,
    required this.showConnectCode,
    required this.onConnectCode,
    required this.onMode,
  });
  final String projectName;
  final String modeLabel;
  final String connectCodeLabel;
  final bool showConnectCode;
  final VoidCallback onConnectCode;
  final void Function(BuildContext context) onMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
              child: Text(
                '当前项目：$projectName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (showConnectCode) ...[
            SizedBox(
              width: 96,
              height: 30,
              child: _PurpleButton(
                text: connectCodeLabel,
                onPressed: onConnectCode,
              ),
            ),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 86,
            height: 30,
            child: Builder(
              builder: (buttonContext) => _PurpleButton(
                text: modeLabel,
                onPressed: () => onMode(buttonContext),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const double _tableIndexColumnWidth = 40;

double _tableWidthFor(
  double availableWidth,
  int dataColumnCount, {
  bool showIndexColumn = true,
}) {
  return availableWidth;
}

double _tableDataColumnWidth(
  double tableWidth,
  int dataColumnCount, {
  bool showIndexColumn = true,
}) {
  final indexWidth = showIndexColumn ? _tableIndexColumnWidth : 0;
  return (tableWidth - indexWidth) / dataColumnCount;
}

class _DisplayCard extends StatefulWidget {
  const _DisplayCard({
    required this.mode,
    required this.rows,
    required this.currentRow,
    required this.currentKey,
    required this.editingRowIndex,
    required this.showIndexColumn,
    required this.allowDelete,
    required this.summaryPrimary,
    required this.summarySecondary,
    required this.onDelete,
    required this.onSelectField,
  });
  final MainMode mode;
  final List<Map<String, String>> rows;
  final Map<String, String> currentRow;
  final String currentKey;
  final int? editingRowIndex;
  final bool showIndexColumn;
  final bool allowDelete;
  final String summaryPrimary;
  final String summarySecondary;
  final ValueChanged<int?> onDelete;
  final void Function(int? index, String key) onSelectField;

  @override
  State<_DisplayCard> createState() => _DisplayCardState();
}

class _DisplayCardState extends State<_DisplayCard> {
  final ScrollController _scrollController = ScrollController();
  bool _scrollScheduled = false;
  late String _inputSignature;

  @override
  void initState() {
    super.initState();
    _inputSignature = _currentInputSignature();
    _scrollToCurrentInputRow();
  }

  @override
  void didUpdateWidget(covariant _DisplayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _currentInputSignature();
    if (signature != _inputSignature ||
        widget.rows.length > oldWidget.rows.length ||
        widget.editingRowIndex != oldWidget.editingRowIndex) {
      _inputSignature = signature;
      _scrollToCurrentInputRow();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int? _editingIndex() {
    final index = widget.editingRowIndex;
    return index != null && index >= 0 && index < widget.rows.length
        ? index
        : null;
  }

  String _currentInputSignature() {
    final entries = widget.currentRow.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return '${widget.currentKey}|${widget.editingRowIndex}|${entries.map((entry) => '${entry.key}=${entry.value}').join('|')}';
  }

  void _scrollToCurrentInputRow() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final maxScrollExtent = _scrollController.position.maxScrollExtent;
      final editingIndex = _editingIndex();
      final targetOffset = editingIndex == null
          ? maxScrollExtent
          : (editingIndex * 34.0).clamp(0.0, maxScrollExtent);
      if ((targetOffset - _scrollController.offset).abs() < 1) return;
      _scrollController.jumpTo(targetOffset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columnsForMode(widget.mode);
    final editingIndex = _editingIndex();
    final itemCount = widget.rows.length + (editingIndex == null ? 1 : 0);
    final selectedDisplayIndex = editingIndex ?? widget.rows.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: _groupDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = _tableWidthFor(
            constraints.maxWidth,
            columns.length,
            showIndexColumn: widget.showIndexColumn,
          );
          final dataColumnWidth = _tableDataColumnWidth(
            tableWidth,
            columns.length,
            showIndexColumn: widget.showIndexColumn,
          );
          return Column(
            children: [
              SizedBox(
                width: tableWidth,
                child: _TableLine(
                  rowNumber: null,
                  showIndexColumn: widget.showIndexColumn,
                  columns: columns,
                  row: null,
                  currentKey: widget.currentKey,
                  selectedRow: false,
                  dataColumnWidth: dataColumnWidth,
                  onDelete: null,
                  onSelectField: (key) => widget.onSelectField(null, key),
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: SizedBox(
                  width: tableWidth,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      final rowIndex = index < widget.rows.length
                          ? index
                          : null;
                      final row = rowIndex == null || rowIndex == editingIndex
                          ? widget.currentRow
                          : widget.rows[rowIndex];
                      final selectedRow = index == selectedDisplayIndex;
                      return _TableLine(
                        rowNumber: index + 1,
                        showIndexColumn: widget.showIndexColumn,
                        columns: columns,
                        row: row,
                        currentKey: selectedRow ? widget.currentKey : '',
                        selectedRow: selectedRow,
                        dataColumnWidth: dataColumnWidth,
                        onDelete:
                            widget.allowDelete &&
                                (rowIndex != null || !_isEmptyRow(row))
                            ? () => widget.onDelete(rowIndex)
                            : null,
                        onSelectField: (key) =>
                            widget.onSelectField(rowIndex, key),
                      );
                    },
                  ),
                ),
              ),
              if (widget.summaryPrimary.isNotEmpty ||
                  widget.summarySecondary.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: _groupDecoration(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.summaryPrimary,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.summarySecondary.isNotEmpty)
                        Expanded(
                          child: Text(
                            widget.summarySecondary,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _IndexedLoadingRow {
  const _IndexedLoadingRow(this.index, this.row);

  final int index;
  final Map<String, String> row;
}

class _LoadingDisplayCard extends StatelessWidget {
  const _LoadingDisplayCard({
    required this.rows,
    required this.currentRow,
    required this.currentKey,
    required this.editingRowIndex,
    required this.aluminumPackageTitle,
    required this.aluminumWeightTitle,
    required this.aluminumUseWeighbridge,
    required this.ironWeightTitle,
    required this.ironUseWeighbridge,
    required this.vehicleInfo,
    required this.summaryPrimary,
    required this.summarySecondary,
    required this.onDelete,
    required this.onSelectField,
    required this.onPackageHeader,
    required this.onWeightHeader,
    required this.onIronWeightHeader,
    required this.onDeductAluminumBox,
  });

  final List<Map<String, String>> rows;
  final Map<String, String> currentRow;
  final String currentKey;
  final int? editingRowIndex;
  final String aluminumPackageTitle;
  final String aluminumWeightTitle;
  final bool aluminumUseWeighbridge;
  final String ironWeightTitle;
  final bool ironUseWeighbridge;
  final Map<String, String> vehicleInfo;
  final String summaryPrimary;
  final String summarySecondary;
  final ValueChanged<int> onDelete;
  final void Function(int? rowIndex, String key) onSelectField;
  final VoidCallback onPackageHeader;
  final VoidCallback onWeightHeader;
  final VoidCallback onIronWeightHeader;
  final ValueChanged<int> onDeductAluminumBox;

  @override
  Widget build(BuildContext context) {
    final indexedRows = [
      for (var index = 0; index < rows.length; index++)
        _IndexedLoadingRow(index, rows[index]),
    ];
    final aluminumRows = indexedRows
        .where((item) => _isAluminumLoadingRow(item.row))
        .toList();
    final ironRows = indexedRows
        .where((item) => _isIronLoadingRow(item.row))
        .toList();
    final ironWeighbridge = _loadingIronWeighbridgeWeightFromInfo(vehicleInfo);
    final ironTotal = ironUseWeighbridge
        ? ironWeighbridge
        : _sumDouble(rows.where(_isIronLoadingRow).toList(), 'weight');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: _groupDecoration(),
      child: Column(
        children: [
          Expanded(
            child: _LoadingSection(
              title: '铝物料',
              rows: aluminumRows,
              currentRow: _isAluminumLoadingRow(currentRow) ? currentRow : null,
              currentKey: currentKey,
              editingRowIndex: editingRowIndex,
              columns: _loadingColumns(
                packageTitle: aluminumPackageTitle,
                quantityTitle: '面积',
                weightTitle: aluminumWeightTitle,
              ),
              hideWeight: aluminumUseWeighbridge,
              onDelete: onDelete,
              onSelectField: onSelectField,
              onHeaderSelect: (key) {
                if (key == 'packages') onPackageHeader();
                if (key == 'weight') onWeightHeader();
              },
            ),
          ),
          if (summaryPrimary.isNotEmpty || summarySecondary.isNotEmpty)
            _LoadingSummaryRow(left: summaryPrimary, right: summarySecondary),
          const SizedBox(height: 4),
          Expanded(
            child: _LoadingSection(
              title: '铁物料',
              rows: ironRows,
              currentRow: _isIronLoadingRow(currentRow) ? currentRow : null,
              currentKey: currentKey,
              editingRowIndex: editingRowIndex,
              columns: _loadingColumns(
                packageTitle: '包数',
                quantityTitle: '数量',
                weightTitle: ironWeightTitle,
              ),
              hideWeight: ironUseWeighbridge,
              onDelete: onDelete,
              onSelectField: onSelectField,
              onHeaderSelect: (key) {
                if (key == 'weight') onIronWeightHeader();
              },
              onRemarkLongPress: onDeductAluminumBox,
            ),
          ),
          _LoadingSummaryRow(
            left: '铁件过磅重量：${_formatNumber(ironWeighbridge)}',
            right: '铁件单包称重合计：${_formatNumber(ironTotal)}',
          ),
        ],
      ),
    );
  }
}

class _LoadingSummaryRow extends StatelessWidget {
  const _LoadingSummaryRow({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 3),
      padding: const EdgeInsets.all(5),
      decoration: _groupDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          if (right.isNotEmpty)
            Expanded(
              child: Text(
                right,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingSection extends StatefulWidget {
  const _LoadingSection({
    required this.title,
    required this.rows,
    required this.currentRow,
    required this.currentKey,
    required this.editingRowIndex,
    required this.columns,
    required this.hideWeight,
    required this.onDelete,
    required this.onSelectField,
    this.onHeaderSelect,
    this.onRemarkLongPress,
  });

  final String? title;
  final List<_IndexedLoadingRow> rows;
  final Map<String, String>? currentRow;
  final String currentKey;
  final int? editingRowIndex;
  final List<_ModeColumn> columns;
  final bool hideWeight;
  final ValueChanged<int> onDelete;
  final void Function(int? rowIndex, String key) onSelectField;
  final ValueChanged<String>? onHeaderSelect;
  final ValueChanged<int>? onRemarkLongPress;

  @override
  State<_LoadingSection> createState() => _LoadingSectionState();
}

class _LoadingSectionState extends State<_LoadingSection> {
  final ScrollController _scrollController = ScrollController();
  bool _scrollScheduled = false;
  late String _inputSignature;

  @override
  void initState() {
    super.initState();
    _inputSignature = _currentInputSignature();
    _scrollToInputRow();
  }

  @override
  void didUpdateWidget(covariant _LoadingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _currentInputSignature();
    if (signature != _inputSignature ||
        widget.rows.length > oldWidget.rows.length ||
        widget.editingRowIndex != oldWidget.editingRowIndex) {
      _inputSignature = signature;
      _scrollToInputRow();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _currentInputSignature() {
    final row = widget.currentRow ?? const <String, String>{};
    final entries = row.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return '${widget.currentKey}|${widget.editingRowIndex}|${entries.map((entry) => '${entry.key}=${entry.value}').join('|')}';
  }

  void _scrollToInputRow() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      final maxScrollExtent = _scrollController.position.maxScrollExtent;
      if ((maxScrollExtent - _scrollController.offset).abs() < 1) return;
      _scrollController.jumpTo(maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final allDisplayRows = [
      for (final item in widget.rows)
        _IndexedLoadingRow(
          item.index,
          item.index == widget.editingRowIndex && widget.currentRow != null
              ? widget.currentRow!
              : item.row,
        ),
    ];
    final skipCount = allDisplayRows.length > 5 ? allDisplayRows.length - 5 : 0;
    final displayRows = allDisplayRows.skip(skipCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Text(
              widget.title!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = _tableWidthFor(
                constraints.maxWidth,
                widget.columns.length,
              );
              final dataColumnWidth = _tableDataColumnWidth(
                tableWidth,
                widget.columns.length,
              );
              return SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    _TableLine(
                      rowNumber: null,
                      showIndexColumn: true,
                      columns: widget.columns,
                      row: null,
                      currentKey: widget.currentKey,
                      selectedRow: false,
                      dataColumnWidth: dataColumnWidth,
                      onDelete: null,
                      onSelectField: (key) => widget.onHeaderSelect?.call(key),
                      headerSelectable: widget.onHeaderSelect != null,
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: displayRows.isEmpty ? 1 : displayRows.length,
                        itemBuilder: (context, index) {
                          if (displayRows.isEmpty) {
                            return _TableLine(
                              rowNumber: 1,
                              showIndexColumn: true,
                              columns: widget.columns,
                              row: const {},
                              currentKey: '',
                              selectedRow: false,
                              dataColumnWidth: dataColumnWidth,
                              onDelete: null,
                              onSelectField: (_) {},
                            );
                          }
                          final item = displayRows[index];
                          final selectedRow =
                              item.index == widget.editingRowIndex ||
                              item.index < 0;
                          return _TableLine(
                            rowNumber: index + 1,
                            showIndexColumn: true,
                            columns: widget.columns,
                            row: widget.hideWeight
                                ? {...item.row, 'weight': ''}
                                : item.row,
                            currentKey: selectedRow ? widget.currentKey : '',
                            selectedRow: selectedRow,
                            dataColumnWidth: dataColumnWidth,
                            onDelete: item.index >= 0
                                ? () => widget.onDelete(item.index)
                                : null,
                            onSelectField: (key) => widget.onSelectField(
                              item.index >= 0 ? item.index : null,
                              key,
                            ),
                            onLongPressField: (key) {
                              if (key == 'remark' && item.index >= 0) {
                                widget.onRemarkLongPress?.call(item.index);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TableLine extends StatelessWidget {
  const _TableLine({
    required this.rowNumber,
    required this.showIndexColumn,
    required this.columns,
    required this.row,
    required this.currentKey,
    required this.selectedRow,
    required this.dataColumnWidth,
    required this.onDelete,
    required this.onSelectField,
    this.headerSelectable = false,
    this.onLongPressField,
  });
  final int? rowNumber;
  final bool showIndexColumn;
  final List<_ModeColumn> columns;
  final Map<String, String>? row;
  final String currentKey;
  final bool selectedRow;
  final double dataColumnWidth;
  final VoidCallback? onDelete;
  final ValueChanged<String> onSelectField;
  final bool headerSelectable;
  final ValueChanged<String>? onLongPressField;

  @override
  Widget build(BuildContext context) {
    final isHeader = row == null;
    return Row(
      children: [
        if (showIndexColumn)
          GestureDetector(
            onLongPress: isHeader ? null : onDelete,
            child: _Cell(
              text: isHeader ? '序号' : rowNumber.toString(),
              width: _tableIndexColumnWidth,
              header: isHeader,
              selected: false,
              selectedRow: selectedRow,
            ),
          ),
        for (final column in columns)
          GestureDetector(
            onTap: isHeader && !headerSelectable
                ? null
                : () => onSelectField(column.key),
            onLongPress: isHeader
                ? null
                : () => onLongPressField?.call(column.key),
            child: _Cell(
              text: isHeader
                  ? column.label
                  : _displayCellText(row!, column.key),
              width: dataColumnWidth,
              header: isHeader,
              selected: !isHeader && currentKey == column.key,
              selectedRow: selectedRow,
            ),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.width,
    required this.header,
    required this.selected,
    required this.selectedRow,
  });
  final String text;
  final double width;
  final bool header;
  final bool selected;
  final bool selectedRow;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? const Color(0xFFF0EAFF)
        : selectedRow
        ? const Color(0xFFF8F5FF)
        : header
        ? const Color(0xFFF2F5FB)
        : Colors.white;
    final borderColor = selected
        ? _legacyPurpleStart
        : header
        ? const Color(0xFFD6DEEC)
        : const Color(0xFFE1E7F2);
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 30),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: selected ? 1.2 : 0.8),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? _legacyPurpleStart : Colors.black87,
          fontSize: header ? 10 : 11,
          fontWeight: selected || header ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _StandardKeyboard extends StatelessWidget {
  const _StandardKeyboard({
    required this.onToken,
    required this.onSymbol,
    required this.onBackspace,
    required this.onNewColumn,
    required this.onNewLine,
  });
  final ValueChanged<String> onToken;
  final VoidCallback onSymbol;
  final VoidCallback onBackspace;
  final VoidCallback onNewColumn;
  final VoidCallback onNewLine;

  @override
  Widget build(BuildContext context) {
    return _KeyboardCard(
      children: [
        Expanded(
          flex: 98,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(
                  child: _KeyGrid(
                    keys: const ['符号', 'K', 'Y', '空格', '回退'],
                    columns: 5,
                    decorated: false,
                    onToken: (v) {
                      if (v == '回退') {
                        onBackspace();
                      } else if (v == '符号') {
                        onSymbol();
                      } else {
                        onToken(v);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: _KeyGrid(
                    keys: const ['A', 'B', 'C', 'D', 'E', 'F'],
                    columns: 6,
                    decorated: false,
                    onToken: onToken,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 245,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(child: _NumberPad(onToken: onToken)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 82,
                  child: _ActionColumn(
                    buttons: [
                      _ActionSpec('换行', onNewLine),
                      _ActionSpec('换列', onNewColumn),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(flex: 157, child: _ModelShortcutGroups(onToken: onToken)),
      ],
    );
  }
}

class _FastVoiceHoldDialogBody extends StatefulWidget {
  const _FastVoiceHoldDialogBody();

  @override
  State<_FastVoiceHoldDialogBody> createState() =>
      _FastVoiceHoldDialogBodyState();
}

class _FastVoiceHoldDialogBodyState extends State<_FastVoiceHoldDialogBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '请按住说出尺寸，例如 200乘300、400乘1米1、50乘80厘米',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _FastVoiceWaveBar(height: 18, progress: _waveProgress(0)),
                const SizedBox(width: 8),
                _FastVoiceWaveBar(height: 28, progress: _waveProgress(1)),
                const SizedBox(width: 8),
                _FastVoiceWaveBar(height: 22, progress: _waveProgress(2)),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        const Text(
          '请持续按住并清晰说出尺寸',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  double _waveProgress(int index) {
    final shifted = (_controller.value + index * 0.23) % 1.0;
    return shifted <= 0.5 ? shifted * 2 : (1 - shifted) * 2;
  }
}

class _FastVoiceWaveBar extends StatelessWidget {
  const _FastVoiceWaveBar({required this.height, required this.progress});

  final double height;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleY: 0.7 + progress * 0.55,
      alignment: Alignment.bottomCenter,
      child: Opacity(
        opacity: 0.45 + progress * 0.55,
        child: Container(
          width: 8,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

class _FastKeyboard extends StatelessWidget {
  const _FastKeyboard({
    required this.onToken,
    required this.onBackspace,
    required this.onNewColumn,
    required this.onNewLine,
    required this.voicePressed,
    required this.onVoiceStart,
    required this.onVoiceEnd,
    required this.onVoiceCancel,
  });
  final ValueChanged<String> onToken;
  final VoidCallback onBackspace;
  final VoidCallback onNewColumn;
  final VoidCallback onNewLine;
  final bool voicePressed;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  final VoidCallback onVoiceCancel;

  @override
  Widget build(BuildContext context) {
    return _KeyboardCard(
      children: [
        Expanded(
          flex: 56,
          child: _KeyGrid(
            keys: const ['50', '45', '95', '65', '85'],
            columns: 5,
            padding: const EdgeInsets.all(3),
            onToken: onToken,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 56,
          child: _KeyGrid(
            keys: const ['100', '200', '300', '400', '500'],
            columns: 5,
            padding: const EdgeInsets.all(3),
            onToken: onToken,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 56,
          child: _KeyGrid(
            keys: const ['700', '900', '1100', '2700', '2745'],
            columns: 5,
            padding: const EdgeInsets.all(3),
            onToken: onToken,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 252,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(2),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Row(
                children: [
                  Expanded(flex: 100, child: _NumberPad(onToken: onToken)),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 28,
                    child: _ActionColumn(
                      margin: const EdgeInsets.all(2),
                      fontSize: 13,
                      buttons: [
                        _ActionSpec('换列', onNewColumn),
                        _ActionSpec('换行', onNewLine),
                        _ActionSpec('回退', onBackspace),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          flex: 80,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(2),
            child: Row(
              children: [
                for (final key in const ['E', 'F', 'SP']) ...[
                  Expanded(
                    child: _KeyButton(text: key, onPressed: () => onToken(key)),
                  ),
                  const SizedBox(width: 3),
                ],
                Expanded(
                  child: _FastVoiceButton(
                    pressed: voicePressed,
                    onHoldStart: onVoiceStart,
                    onHoldEnd: onVoiceEnd,
                    onHoldCancel: onVoiceCancel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FastVoiceButton extends StatelessWidget {
  const _FastVoiceButton({
    required this.pressed,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  final bool pressed;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => onHoldStart(),
          onPointerUp: (_) => onHoldEnd(),
          onPointerCancel: (_) {},
          child: AnimatedScale(
            scale: pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: CustomPaint(
              painter: _FastVoiceButtonPainter(pressed: pressed),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

class _FastVoiceButtonPainter extends CustomPainter {
  const _FastVoiceButtonPainter({required this.pressed});

  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = size.shortestSide;
    final outerRadius = shortest * (pressed ? 0.46 : 0.43);
    final innerRadius = shortest * (pressed ? 0.36 : 0.34);
    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);

    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..shader = RadialGradient(
          colors: pressed
              ? const [Color(0x3A8E79F5), Color(0x24725EFF)]
              : const [Color(0x2C8B77F0), Color(0x1A6E5BFF)],
        ).createShader(outerRect),
    );
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA58BFF), Color(0xFF8266F0), Color(0xFF5E40C9)],
        ).createShader(innerRect),
    );
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: pressed ? 0.30 : 0.25),
    );

    final highlightRect = Rect.fromCenter(
      center: center.translate(0, -innerRadius * 0.42),
      width: innerRadius * 1.55,
      height: innerRadius * 0.72,
    );
    canvas.drawOval(
      highlightRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: pressed ? 0.40 : 0.34),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(highlightRect),
    );

    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: pressed ? 0.13 : 0.09),
          ],
        ).createShader(innerRect),
    );
    _paintMic(canvas, center, shortest * 0.28);
  }

  void _paintMic(Canvas canvas, Offset center, double iconSize) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = iconSize * 0.09
      ..strokeCap = StrokeCap.round;
    final unit = iconSize / 24;
    final micRect = Rect.fromCenter(
      center: center.translate(0, -2 * unit),
      width: 6 * unit,
      height: 12 * unit,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(micRect, Radius.circular(3 * unit)),
      paint,
    );
    final arcRect = Rect.fromCenter(
      center: center.translate(0, 1.5 * unit),
      width: 14 * unit,
      height: 14 * unit,
    );
    canvas.drawArc(arcRect, 0.12, 2.9, false, stroke);
    canvas.drawLine(
      center.translate(0, 8 * unit),
      center.translate(0, 12 * unit),
      stroke,
    );
    canvas.drawLine(
      center.translate(-4 * unit, 12 * unit),
      center.translate(4 * unit, 12 * unit),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _FastVoiceButtonPainter oldDelegate) {
    return oldDelegate.pressed != pressed;
  }
}

class _LoadingKeyboard extends StatelessWidget {
  const _LoadingKeyboard({
    required this.onToken,
    required this.onBackspace,
    required this.onNewColumn,
    required this.onNewLine,
    required this.onAluminumMaterial,
    required this.onIronMaterial,
    required this.onVehicleInfo,
  });

  final ValueChanged<String> onToken;
  final VoidCallback onBackspace;
  final VoidCallback onNewColumn;
  final VoidCallback onNewLine;
  final VoidCallback onAluminumMaterial;
  final VoidCallback onIronMaterial;
  final VoidCallback onVehicleInfo;

  @override
  Widget build(BuildContext context) {
    return _KeyboardCard(
      children: [
        Expanded(
          flex: 100,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                SizedBox(
                  height: 42,
                  child: Row(
                    children: [
                      Expanded(
                        child: _PurpleButton(
                          text: '铝物料',
                          onPressed: onAluminumMaterial,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _PurpleButton(
                          text: '铁物料',
                          onPressed: onIronMaterial,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _PurpleButton(
                          text: '过磅信息',
                          onPressed: onVehicleInfo,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _NumberPad(onToken: onToken)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 82,
                        child: _ActionColumn(
                          buttons: [
                            _ActionSpec('换列', onNewColumn),
                            _ActionSpec('换行', onNewLine),
                            _ActionSpec('回退', onBackspace),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QualityKeyboard extends StatelessWidget {
  const _QualityKeyboard({
    required this.onToken,
    required this.onSymbol,
    required this.onBackspace,
    required this.onNewColumn,
    required this.onNewLine,
  });
  final ValueChanged<String> onToken;
  final VoidCallback onSymbol;
  final VoidCallback onBackspace;
  final VoidCallback onNewColumn;
  final VoidCallback onNewLine;

  @override
  Widget build(BuildContext context) {
    return _KeyboardCard(
      children: [
        Expanded(
          flex: 62,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(
                  child: _KeyGrid(
                    keys: const ['符号', 'K', 'Y', '空格', '回退'],
                    columns: 5,
                    decorated: false,
                    onToken: (v) {
                      if (v == '回退') {
                        onBackspace();
                      } else if (v == '符号') {
                        onSymbol();
                      } else if (v == 'K') {
                        onToken('L');
                      } else {
                        onToken(v);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: _KeyGrid(
                    keys: const ['A', 'B', 'C', 'D', 'E', 'F'],
                    columns: 6,
                    decorated: false,
                    onToken: onToken,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 152,
          child: _LegacyGroup(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(child: _NumberPad(onToken: onToken)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 82,
                  child: _ActionColumn(
                    buttons: [
                      _ActionSpec('换行', onNewLine),
                      _ActionSpec('换列', onNewColumn),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(flex: 125, child: _ModelShortcutGroups(onToken: onToken)),
      ],
    );
  }
}

const _legacyPurpleStart = Color(0xFF6E57B5);
const _legacyPurpleEnd = Color(0xFF7E63C5);
const _legacyKeyPurpleEnd = Color(0xFF8067C8);
const _legacyGroupBorder = Color(0xFFE3E8F4);
const _legacyCardBorder = Color(0xFFDCE3F1);
const _legacyKeyBorder = Color(0xFFD4DDEA);
const _legacyNumberBorder = Color(0xFFD8E0F1);
const _legacyKeyPressedFill = Color(0xFFEEF2F8);

const _legacyPurpleButtonGradient = LinearGradient(
  colors: [_legacyPurpleStart, _legacyPurpleEnd],
);
const _legacyKeyboardButtonGradient = LinearGradient(
  colors: [_legacyPurpleStart, _legacyKeyPurpleEnd],
);

class _KeyboardCard extends StatelessWidget {
  const _KeyboardCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(),
      child: Column(children: children),
    );
  }
}

class _LegacyGroup extends StatelessWidget {
  const _LegacyGroup({
    required this.child,
    this.padding = const EdgeInsets.all(4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: _groupDecoration(),
      child: child,
    );
  }
}

class _ModelShortcutGroups extends StatelessWidget {
  const _ModelShortcutGroups({required this.onToken});

  final ValueChanged<String> onToken;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _KeyGrid(
                  keys: const ['W', 'WE', 'WED', 'BQ', 'IC', 'ICA'],
                  columns: 3,
                  onToken: onToken,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _KeyGrid(
                  keys: const ['B', 'BS', 'BC', 'BP', 'X', 'N'],
                  columns: 3,
                  onToken: onToken,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _KeyGrid(
                  keys: const ['S', 'SC', 'M', 'MB', 'SP', 'Q'],
                  columns: 3,
                  onToken: onToken,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _KeyGrid(
                  keys: const ['LT', 'JT', 'GT', 'DM', 'H', 'P'],
                  columns: 3,
                  onToken: onToken,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumberPad extends StatelessWidget {
  const _NumberPad({required this.onToken});
  final ValueChanged<String> onToken;

  @override
  Widget build(BuildContext context) => _KeyGrid(
    keys: const ['7', '8', '9', '4', '5', '6', '1', '2', '3', '0', '00', '.'],
    columns: 3,
    onToken: onToken,
    dark: true,
    decorated: false,
  );
}

class _KeyGrid extends StatelessWidget {
  const _KeyGrid({
    required this.keys,
    required this.columns,
    required this.onToken,
    this.dark = false,
    this.decorated = true,
    this.padding = const EdgeInsets.all(4),
  });
  final List<String> keys;
  final int columns;
  final ValueChanged<String> onToken;
  final bool dark;
  final bool decorated;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    const spacing = 3.0;
    final rows = (keys.length / columns).ceil();
    final grid = Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) SizedBox(height: spacing),
          Expanded(
            child: Row(
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) SizedBox(width: spacing),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final index = row * columns + column;
                        if (index >= keys.length) {
                          return const SizedBox.shrink();
                        }
                        final key = keys[index];
                        return _KeyButton(
                          text: key,
                          onPressed: () => onToken(key),
                          dark: dark,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );

    if (!decorated) return grid;
    return _LegacyGroup(padding: padding, child: grid);
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.text,
    required this.onPressed,
    this.dark = false,
  });
  final String text;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return _LegacyButton(
      text: text,
      onPressed: onPressed,
      gradient: dark ? _legacyKeyboardButtonGradient : null,
      color: dark ? null : Colors.white,
      border: dark
          ? Border.all(color: _legacyNumberBorder)
          : Border.all(color: _legacyKeyBorder),
      borderRadius: BorderRadius.circular(dark ? 16 : 10),
      padding: EdgeInsets.zero,
      overlayColor: dark ? Colors.white24 : _legacyKeyPressedFill,
      textStyle: TextStyle(
        color: dark ? Colors.white : AppColors.textPrimary,
        fontSize: dark ? 18 : 11,
        fontWeight: dark ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

class _PurpleButton extends StatelessWidget {
  const _PurpleButton({required this.text, required this.onPressed});
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _LegacyButton(
    text: text,
    onPressed: onPressed,
    gradient: _legacyPurpleButtonGradient,
    borderRadius: BorderRadius.circular(20),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    textStyle: const TextStyle(color: Colors.white, fontSize: 13),
  );
}

class _ActionSpec {
  const _ActionSpec(this.text, this.onPressed);

  final String text;
  final VoidCallback onPressed;
}

class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.buttons,
    this.margin = const EdgeInsets.all(1),
    this.fontSize = 11,
  });

  final List<_ActionSpec> buttons;
  final EdgeInsetsGeometry margin;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < buttons.length; index++)
          Expanded(
            child: Padding(
              padding: margin,
              child: _LegacyButton(
                text: buttons[index].text,
                onPressed: buttons[index].onPressed,
                gradient: _legacyKeyboardButtonGradient,
                borderRadius: BorderRadius.circular(16),
                padding: EdgeInsets.zero,
                textStyle: TextStyle(color: Colors.white, fontSize: fontSize),
              ),
            ),
          ),
      ],
    );
  }
}

class _LegacyButton extends StatelessWidget {
  const _LegacyButton({
    required this.text,
    required this.onPressed,
    required this.borderRadius,
    required this.textStyle,
    this.gradient,
    this.color,
    this.border,
    this.padding = EdgeInsets.zero,
    this.overlayColor = Colors.white24,
  });

  final String text;
  final VoidCallback onPressed;
  final Gradient? gradient;
  final Color? color;
  final BoxBorder? border;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final TextStyle textStyle;
  final Color overlayColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          border: border,
          borderRadius: borderRadius,
        ),
        child: InkWell(
          borderRadius: borderRadius,
          overlayColor: WidgetStatePropertyAll(overlayColor),
          onTap: onPressed,
          child: Padding(
            padding: padding,
            child: Center(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
