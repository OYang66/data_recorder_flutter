import 'dart:async';

import 'package:flutter/services.dart';

class ExternalDeliveryOrderFile {
  const ExternalDeliveryOrderFile({
    required this.path,
    required this.fileName,
    required this.source,
  });

  final String path;
  final String fileName;
  final String source;

  static ExternalDeliveryOrderFile? fromMap(Object? value) {
    if (value is! Map) return null;
    final path = value['path']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    final fileName = value['fileName']?.toString().trim() ?? '';
    final source = value['source']?.toString().trim() ?? '';
    return ExternalDeliveryOrderFile(
      path: path,
      fileName: fileName.isEmpty ? path.split(RegExp(r'[\\/]')).last : fileName,
      source: source.isEmpty ? 'external' : source,
    );
  }
}

class DeliveryOrderIntakeService {
  DeliveryOrderIntakeService._();

  static final DeliveryOrderIntakeService instance = DeliveryOrderIntakeService._();

  static const _channel = MethodChannel(
    'com.example.datarecorder/delivery_order_intake',
  );

  final _controller = StreamController<ExternalDeliveryOrderFile>.broadcast();
  bool _initialized = false;
  String? _lastPath;

  Stream<ExternalDeliveryOrderFile> get files => _controller.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeliveryOrderFile') {
        _emit(ExternalDeliveryOrderFile.fromMap(call.arguments));
      }
    });
    try {
      final initial = await _channel.invokeMethod<Object?>(
        'getInitialDeliveryOrderFile',
      );
      _emit(ExternalDeliveryOrderFile.fromMap(initial));
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  void _emit(ExternalDeliveryOrderFile? file) {
    if (file == null) return;
    if (_lastPath == file.path) return;
    _lastPath = file.path;
    _controller.add(file);
  }
}
