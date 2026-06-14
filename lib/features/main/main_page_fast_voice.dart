part of 'main_page.dart';

extension _MainPageFastVoice on _MainPageState {
  void _startFastVoiceHold() {
    unawaited(_beginFastVoiceHold());
  }

  Future<void> _beginFastVoiceHold() async {
    if (_fastVoiceStarting || _fastVoiceListening || _fastVoiceWaitingResult) {
      _showFastVoiceToast('语音识别正在进行中');
      return;
    }
    final holdGeneration = ++_fastVoiceHoldGeneration;
    _fastVoicePressed = true;
    _fastVoiceStarting = true;
    _fastVoicePressStartedAt = DateTime.now();
    _showFastVoiceHoldDialog();
    _scheduleFastVoiceStartTimeout(holdGeneration);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          holdGeneration != _fastVoiceHoldGeneration ||
          !_fastVoicePressed) {
        return;
      }
      unawaited(HapticFeedback.lightImpact());
      await _MainPageState._fastVoiceChannel.invokeMethod<void>(
        'startListening',
      );
      if (!mounted || holdGeneration != _fastVoiceHoldGeneration) return;
      _fastVoiceStartTimeoutTimer?.cancel();
      if (!_fastVoicePressed) {
        _setMainState(() {
          _fastVoiceStarting = false;
          _fastVoiceListening = false;
          _fastVoicePressStartedAt = null;
        });
        await _MainPageState._fastVoiceChannel.invokeMethod<void>(
          'cancelListening',
        );
        return;
      }
      _setMainState(() {
        _fastVoiceStarting = false;
        _fastVoiceListening = true;
      });
      _fastVoiceTimeoutTimer?.cancel();
      _fastVoiceTimeoutTimer = Timer(
        const Duration(seconds: 12),
        () => unawaited(_finishFastVoiceHold(timedOut: true)),
      );
    } catch (error) {
      _fastVoiceStartTimeoutTimer?.cancel();
      _fastVoiceTimeoutTimer?.cancel();
      _dismissFastVoiceHoldDialog();
      if (!mounted || holdGeneration != _fastVoiceHoldGeneration) return;
      _setMainState(() {
        _fastVoicePressed = false;
        _fastVoiceStarting = false;
        _fastVoiceListening = false;
        _fastVoiceWaitingResult = false;
        _fastVoicePressStartedAt = null;
      });
      _showFastVoiceToast(_fastVoiceErrorMessage(error));
    }
  }

  Future<void> _finishFastVoiceHold({bool timedOut = false}) async {
    if (!_fastVoiceStarting && !_fastVoiceListening && !_fastVoicePressed) {
      _dismissFastVoiceHoldDialog();
      return;
    }
    final startedAt = _fastVoicePressStartedAt;
    final tooShort =
        !timedOut &&
        startedAt != null &&
        DateTime.now().difference(startedAt).inMilliseconds < 300;
    _fastVoiceStartTimeoutTimer?.cancel();
    _fastVoiceTimeoutTimer?.cancel();
    if (tooShort || _fastVoiceStarting) {
      unawaited(_cancelFastVoiceHold(showTooShortToast: tooShort));
      return;
    }
    _setMainState(() {
      _fastVoicePressed = false;
      _fastVoiceStarting = false;
      _fastVoiceListening = false;
      _fastVoiceWaitingResult = true;
      _fastVoicePressStartedAt = null;
    });
    try {
      final text = await _MainPageState._fastVoiceChannel.invokeMethod<String>(
        'stopListening',
      );
      _dismissFastVoiceHoldDialog();
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        _showFastVoiceToast('未识别到清晰语音');
        return;
      }
      await _applyFastVoiceText(text);
    } catch (error) {
      _dismissFastVoiceHoldDialog();
      if (mounted) _showFastVoiceToast(_fastVoiceErrorMessage(error));
    } finally {
      if (mounted) {
        _setMainState(() {
          _fastVoicePressed = false;
          _fastVoiceStarting = false;
          _fastVoiceListening = false;
          _fastVoiceWaitingResult = false;
          _fastVoicePressStartedAt = null;
        });
      }
    }
  }

  Future<void> _cancelFastVoiceHold({bool showTooShortToast = false}) {
    _fastVoiceHoldGeneration++;
    _fastVoiceStartTimeoutTimer?.cancel();
    _fastVoiceTimeoutTimer?.cancel();
    _dismissFastVoiceHoldDialog();
    if (!mounted) return Future<void>.value();
    _setMainState(() {
      _fastVoicePressed = false;
      _fastVoiceStarting = false;
      _fastVoiceListening = false;
      _fastVoiceWaitingResult = false;
      _fastVoicePressStartedAt = null;
    });
    if (showTooShortToast) {
      _showFastVoiceToast('请长按后说话');
    }
    unawaited(
      _MainPageState._fastVoiceChannel
          .invokeMethod<void>('cancelListening')
          .catchError((_) {}),
    );
    return Future<void>.value();
  }

  void _scheduleFastVoiceStartTimeout(int holdGeneration) {
    _fastVoiceStartTimeoutTimer?.cancel();
    _fastVoiceStartTimeoutTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted ||
          holdGeneration != _fastVoiceHoldGeneration ||
          !_fastVoiceStarting) {
        return;
      }
      unawaited(_cancelFastVoiceHold());
      _showFastVoiceToast('语音启动较慢，请稍后重试');
    });
  }

  void _showFastVoiceToast(String message) {
    final bottomMargin = MediaQuery.sizeOf(context).height * 0.28;
    showAppToast(context, message, bottomMargin: bottomMargin);
  }

  void _showFastVoiceHoldDialog() {
    if (_fastVoiceDialogVisible || !mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _fastVoiceDialogVisible = true;
    _fastVoiceDialogEntry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Material(
          color: Colors.black.withValues(alpha: 0.28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '正在收听',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '松开按钮后开始识别',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 14),
                    _FastVoiceHoldDialogBody(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_fastVoiceDialogEntry!);
  }

  void _dismissFastVoiceHoldDialog() {
    if (!_fastVoiceDialogVisible) return;
    _fastVoiceDialogVisible = false;
    _fastVoiceDialogEntry?.remove();
    _fastVoiceDialogEntry = null;
  }

  Future<void> _applyFastVoiceText(String text) async {
    final pair = _parseFastVoiceSizePair(text);
    if (pair == null) {
      _showFastVoiceToast('未识别到尺寸格式，请说类似‘200乘300’或‘400乘1米1’');
      return;
    }
    final width = double.tryParse(pair.$1) ?? 0;
    final length = double.tryParse(pair.$2) ?? 0;
    if (width <= 0 || length <= 0 || width > 600 || length > 4500) {
      _showFastVoiceToast('识别成功，但尺寸超出当前 FAST 可录入范围');
      return;
    }
    _setMainState(() {
      _fastCurrent['width'] = pair.$1;
      _fastCurrent['length'] = pair.$2;
      _fastField = FastField.width;
    });
    await _finishCurrentRow();
  }

  String _fastVoiceErrorMessage(Object error) {
    if (error is PlatformException) {
      return switch (error.code) {
        'permission_denied' => '未授予录音权限，无法使用语音识别',
        'speech_permission_denied' => '未授予语音识别权限，无法使用语音识别',
        'unavailable' => '当前设备不支持系统语音识别',
        'start_failed' => '语音识别启动失败，请稍后重试',
        _ =>
          error.message?.ifBlank('语音识别失败，请检查录音权限和系统语音服务') ??
              '语音识别失败，请检查录音权限和系统语音服务',
      };
    }
    if (error is MissingPluginException) {
      return '当前平台暂不支持语音识别';
    }
    return '语音识别失败，请检查录音权限和系统语音服务';
  }

  (String, String)? _parseFastVoiceSizePair(String text) {
    final normalized = text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('乘以', '乘')
        .replaceAll('乘号', '乘')
        .replaceAll('成', '乘')
        .replaceAll('＊', '乘')
        .replaceAll('×', '乘')
        .replaceAll('*', '乘')
        .replaceAll('x', '乘')
        .replaceAll('X', '乘')
        .replaceAll('公分', '厘米')
        .replaceAll('cm', '厘米')
        .replaceAll('CM', '厘米')
        .replaceAll('mm', '毫米')
        .replaceAll('MM', '毫米')
        .replaceAll('m', '米')
        .replaceAll('M', '米');
    final parts = normalized.split('乘');
    if (parts.length != 2) return null;
    final width = _parseFastVoiceDimension(parts[0]);
    final length = _parseFastVoiceDimension(parts[1]);
    if (width == null || length == null) return null;
    return (
      _formatFastVoiceDimension(width),
      _formatFastVoiceDimension(length),
    );
  }

  double? _parseFastVoiceDimension(String text) {
    if (text.isEmpty || text == '.') return null;
    if (text.endsWith('毫米')) {
      return double.tryParse(text.substring(0, text.length - 2));
    }
    if (text.endsWith('厘米')) {
      final value = double.tryParse(text.substring(0, text.length - 2));
      return value == null ? null : value * 10;
    }
    if (text.contains('米')) {
      final segments = text.split('米');
      if (segments.length != 2) return null;
      final meters = double.tryParse(segments[0].ifBlank('0'));
      if (meters == null) return null;
      final tail = segments[1];
      if (tail.isEmpty) return meters * 1000;
      if (segments[0].contains('.')) return null;
      final decimal = double.tryParse('0.$tail');
      return decimal == null ? null : (meters + decimal) * 1000;
    }
    return double.tryParse(text);
  }

  String _formatFastVoiceDimension(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  Future<void> _showSubDisplayDialog() async {
    try {
      if (_subDisplayCode.isEmpty) {
        final response = await _serverRepository.generateSubDisplayCode();
        final code = response.data?.code ?? '';
        if (!response.isSuccess || code.isEmpty) {
          _showNotReady(response.displayMessage.ifEmpty('连接码生成失败'));
          return;
        }
        _subDisplayCode = code;
        _lastSubDisplayPayload = null;
        await _saveMainState();
        _syncSubDisplayPolling();
      }
      final status = await _serverRepository.getSubDisplayStatus(
        _subDisplayCode,
      );
      if (!mounted) return;
      if (!status.isSuccess) {
        final message = status.displayMessage;
        if (message.contains('失效') ||
            message.contains('过期') ||
            message.contains('不存在')) {
          _clearSubDisplayCode(message);
        } else {
          _showNotReady(message.ifEmpty('连接状态刷新失败'));
        }
        return;
      }
      final statusData = status.data;
      final sessionCount = statusData?.sessionCount ?? 0;
      _setMainState(() {
        _subDisplayConnected =
            statusData?.connected == true || sessionCount > 0;
        _subDisplaySessionCount = sessionCount;
      });
      await showAppCardDialog<void>(
        context: context,
        title: '子软件连接',
        subtitle: _subDisplayConnected == true
            ? '已连接 $_subDisplaySessionCount 台设备'
            : '等待子软件连接',
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '连接码：$_subDisplayCode\n连接状态：${_subDisplayConnected == true ? '已连接' : '未连接'}\n设备数量：$_subDisplaySessionCount',
            ),
            const SizedBox(height: 12),
            AppDialogActionButton(
              text: '复制连接码',
              primary: false,
              onPressed: () {
                final code = _subDisplayCode;
                Navigator.of(context).pop();
                Clipboard.setData(ClipboardData(text: code));
                showAppToast(this.context, '连接码已复制');
              },
            ),
            const SizedBox(height: 16),
            AppDialogActionRow(
              cancelText: '关闭',
              confirmText: '推送返厂数据',
              onCancel: () => Navigator.of(context).pop(),
              onConfirm: () {
                Navigator.of(context).pop();
                _pushFastSnapshotToSubDisplay(showNoReceiverMessage: true);
              },
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _showNotReady('连接码操作失败，请检查网络和登录状态');
    }
  }

  Future<void> _pushFastSnapshotToSubDisplay({
    bool force = false,
    bool showNoReceiverMessage = false,
  }) async {
    if (_subDisplayCode.isEmpty) return;
    if (!_hasSubDisplayReceiver) {
      if (showNoReceiverMessage && mounted) {
        _showNotReady('暂无子软件连接，已停止推送');
      }
      return;
    }
    final project = _project;
    if (project == null) return;
    final scopedRows = _readScopedData(
      project.fastContent,
      _currentBuildingName,
    );
    final rows = scopedRows[_packageName] ?? const <Map<String, String>>[];
    final packageNames = <String>{_packageName, ...scopedRows.keys};
    final packages = packageNames
        .map((packageName) {
          return {
            'packageName': packageName,
            'savedRows':
                scopedRows[packageName] ?? const <Map<String, String>>[],
            'currentRow': packageName == _packageName
                ? _fastCurrent
                : _emptyFastRow(),
          };
        })
        .where((packageData) {
          final savedRows = packageData['savedRows'];
          final currentRow = packageData['currentRow'];
          return savedRows is List && savedRows.isNotEmpty ||
              currentRow is Map<String, String> && !_isEmptyRow(currentRow);
        })
        .toList();
    final summaryRows = _summaryRows(rows);
    final payload = {
      'projectName': project.name,
      'buildingName': project.buildingName,
      'currentPackageName': _packageName,
      'packages': packages,
      'summary': {
        'totalArea': _fastArea(summaryRows).toStringAsFixed(2),
        'totalQuantity': _sum(summaryRows, 'quantity').toString(),
      },
      'clientTime': DateTime.now().toIso8601String(),
      'payloadVersion': 1,
    };
    final payloadHash = jsonEncode(payload);
    if (!force && payloadHash == _lastSubDisplayPayload) return;
    try {
      final response = await _serverRepository.pushReturnData(
        code: _subDisplayCode,
        payload: payload,
      );
      if (response.isSuccess) {
        _lastSubDisplayPayload = payloadHash;
        if (!mounted) return;
        _setMainState(() {
          _subDisplayConnected =
              response.data?.connected == true ||
              (response.data?.sessionCount ?? 0) > 0;
          _subDisplaySessionCount =
              response.data?.sessionCount ?? _subDisplaySessionCount;
        });
        _showNotReady('返厂数据已推送');
        return;
      }
      final message = response.displayMessage;
      if (message.contains('失效') ||
          message.contains('过期') ||
          message.contains('不存在')) {
        _clearSubDisplayCode(message);
      } else if (mounted) {
        _showNotReady(message.ifEmpty('返厂数据推送失败'));
      }
    } catch (error) {
      if (mounted) _showNotReady('返厂数据推送失败，请检查网络');
    }
  }
}
