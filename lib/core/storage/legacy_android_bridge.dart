import 'package:flutter/services.dart';

class LegacyAndroidBridge {
  const LegacyAndroidBridge({MethodChannel? channel}) : _channel = channel;

  static const _defaultChannel = MethodChannel(
    'com.example.datarecorder/legacy_storage',
  );

  final MethodChannel? _channel;

  MethodChannel get channel => _channel ?? _defaultChannel;

  Future<Map<String, Object?>> readPreferences(String name) async {
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        'readPreferences',
        {'name': name},
      );
      return result ?? <String, Object?>{};
    } on MissingPluginException {
      return <String, Object?>{};
    }
  }

  Future<void> writePreferences(
    String name,
    Map<String, Object?> values,
  ) async {
    try {
      await channel.invokeMethod<void>('writePreferences', {
        'name': name,
        'values': values,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> removePreferences(String name, List<String> keys) async {
    try {
      await channel.invokeMethod<void>('removePreferences', {
        'name': name,
        'keys': keys,
      });
    } on MissingPluginException {
      return;
    }
  }
}
