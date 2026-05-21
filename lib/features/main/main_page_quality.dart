part of 'main_page.dart';

extension _MainPageQuality on _MainPageState {
  Future<void> _showQualityMaterialTypeDialog() async {
    final selected = await _showOptionDialog(
      title: '选择材料类型',
      options: _qualityMaterialTypes,
    );
    if (selected == null) return;
    _setMainState(() {
      _qualityCurrent['materialType'] = selected;
      final qualityType = _qualityCurrent['qualityType'].orEmpty();
      if (qualityType.isNotEmpty) {
        _qualityCurrent['description'] = _buildQualityFeedbackDesc(
          materialType: selected,
          qualityType: qualityType,
        );
      }
      _qualityField = QualityField.installNumber;
    });
    await _saveQualityEditedRow(_qualityCurrent);
  }

  Future<void> _showQualityTypeDialog() async {
    final selected = await _showOptionDialog(
      title: '选择质量类型',
      options: _qualityTypes,
    );
    if (selected == null) return;
    _setMainState(() {
      _qualityCurrent['qualityType'] = selected;
      _qualityCurrent['description'] = _buildQualityFeedbackDesc(
        materialType: _qualityCurrent['materialType'].orEmpty(),
        qualityType: selected,
      );
      _qualityField = QualityField.installNumber;
    });
    await _saveQualityEditedRow(_qualityCurrent);
  }

  Future<void> _showQualityDescriptionEditor() async {
    final controller = TextEditingController(
      text: _qualityCurrent['description'].orEmpty(),
    );
    final value = await showAppCardDialog<String>(
      context: context,
      title: '编辑反馈说明',
      subtitle: '填写质量问题描述',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            minLines: 6,
            maxLines: 8,
            decoration: const InputDecoration(labelText: '反馈内容'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppDialogActionButton(
                  text: '清空',
                  primary: false,
                  onPressed: () => controller.clear(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppDialogActionButton(
                  text: '取消',
                  primary: false,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppDialogActionButton(
                  text: '确定',
                  onPressed: () => Navigator.of(context).pop(controller.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    _setMainState(() {
      _qualityCurrent['description'] = value.trim();
      _qualityField = QualityField.installNumber;
    });
    await _saveQualityEditedRow(_qualityCurrent);
  }

  Future<void> _showSymbolDialog() async {
    final selected = await showAppMenuCardPopup<String>(
      context: context,
      title: '符号',
      subtitle: '选择要输入的符号',
      children: [
        for (final symbol in ['+', '-', '/', 'G', 'L', '()'])
          AppDialogListItem(
            label: symbol,
            onTap: () => Navigator.of(context).pop(symbol),
          ),
      ],
    );
    if (!mounted || selected == null) return;
    _appendToken(selected);
  }

  Future<String?> _showOptionDialog({
    required String title,
    String? subtitle,
    required List<String> options,
    String? current,
  }) {
    final currentValue =
        current ??
        (title.contains('材料')
            ? _qualityCurrent['materialType'].orEmpty()
            : _qualityCurrent['qualityType'].orEmpty());
    return showAppMenuCardPopup<String>(
      context: context,
      title: title,
      subtitle: subtitle ?? '选择后会写入当前质量反馈行',
      children: [
        for (final option in options)
          AppDialogListItem(
            label: option,
            selected: option == currentValue,
            onTap: () => Navigator.of(context).pop(option),
          ),
      ],
    );
  }

  Future<void> _showQualityPhotoPreview(String photoUris) async {
    final photos = photoUris
        .split('|')
        .where((uri) => uri.trim().isNotEmpty)
        .toList();
    if (photos.isEmpty) {
      _showNotReady('当前没有附图');
      return;
    }
    final imageWidgets = await Future.wait(
      photos.map((uri) async {
        try {
          final base64 = await _MainPageState._exportChannel
              .invokeMethod<String>('readBytesBase64', {'uri': uri});
          if (base64 == null || base64.isEmpty) return null;
          return Image.memory(base64Decode(base64), fit: BoxFit.cover);
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;
    await showAppCardDialog<void>(
      context: context,
      title: '附图预览',
      subtitle: '共 ${photos.length} 张',
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < photos.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child:
                            imageWidgets[i] ??
                            Center(
                              child: Text(
                                '第${i + 1}张',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
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

  Future<void> _showQualityPhotoMenu() async {
    final photoCount = _qualityCurrent['photoUris']
        .orEmpty()
        .split('|')
        .where((uri) => uri.trim().isNotEmpty)
        .length;
    final selected = await showAppMenuCardPopup<String>(
      context: context,
      title: '附图',
      subtitle: photoCount == 0 ? '当前未添加附图' : '当前已有 $photoCount 张附图',
      children: [
        AppDialogListItem(
          label: '拍照',
          subtitle: '调用相机添加现场照片',
          accent: true,
          onTap: () => Navigator.of(context).pop('camera'),
        ),
        AppDialogListItem(
          label: '从相册添加',
          subtitle: '选择已有图片作为附图',
          onTap: () => Navigator.of(context).pop('gallery'),
        ),
        AppDialogListItem(
          label: '预览附图',
          subtitle: photoCount == 0 ? '当前没有可预览的附图' : '查看当前行已有附图',
          onTap: () => Navigator.of(context).pop('preview'),
        ),
        AppDialogListItem(
          label: '删除附图',
          subtitle: photoCount == 0 ? '当前没有可删除的附图' : '选择单张删除或清空全部',
          danger: true,
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    );
    switch (selected) {
      case 'camera':
        await _addQualityPhoto(takePhoto: true);
      case 'gallery':
        await _addQualityPhoto(takePhoto: false);
      case 'preview':
        await _showQualityPhotoPreview(_qualityCurrent['photoUris'].orEmpty());
      case 'delete':
        await _deleteQualityPhotos();
    }
  }

  Future<void> _deleteQualityPhotos() async {
    final photos = _qualityCurrent['photoUris']
        .orEmpty()
        .split('|')
        .where((uri) => uri.trim().isNotEmpty)
        .toList();
    if (photos.isEmpty) {
      _showNotReady('当前没有附图');
      return;
    }
    final selected = await showAppMenuCardPopup<int>(
      context: context,
      title: '删除附图',
      subtitle: '当前已有 ${photos.length} 张附图',
      children: [
        for (var i = 0; i < photos.length; i++)
          AppDialogListItem(
            label: '删除第 ${i + 1} 张',
            subtitle: photos[i],
            danger: true,
            onTap: () => Navigator.of(context).pop(i),
          ),
        AppDialogListItem(
          label: '清空全部附图',
          subtitle: '删除当前行所有附图',
          danger: true,
          onTap: () => Navigator.of(context).pop(-1),
        ),
      ],
    );
    if (selected == null) return;
    final updated = selected < 0
        ? <String>[]
        : [
            for (var i = 0; i < photos.length; i++)
              if (i != selected) photos[i],
          ];
    _setMainState(() {
      _qualityCurrent['photoUris'] = updated.join('|');
      _qualityField = QualityField.installNumber;
    });
    await _saveQualityEditedRow(_qualityCurrent);
  }

  Future<void> _addQualityPhoto({required bool takePhoto}) async {
    if (_mode != MainMode.quality) return;
    try {
      final uri = await _MainPageState._photoChannel.invokeMethod<String>(
        takePhoto ? 'takePhoto' : 'pickPhoto',
      );
      if (uri == null || uri.isEmpty) return;
      _setMainState(() {
        final existing = _qualityCurrent['photoUris'].orEmpty();
        _qualityCurrent['photoUris'] = existing.isEmpty
            ? uri
            : '$existing|$uri';
      });
      await _saveQualityEditedRow(_qualityCurrent);
      if (mounted) _showNotReady('附图已添加');
    } catch (error) {
      if (mounted) _showNotReady('附图添加失败，请检查权限');
    }
  }
}
