import 'package:flutter/services.dart';

import '../../data/models/project_entity.dart';

class LegacyDatabaseBridge {
  const LegacyDatabaseBridge({MethodChannel? channel}) : _channel = channel;

  static const _defaultChannel = MethodChannel(
    'com.example.datarecorder/legacy_database',
  );

  final MethodChannel? _channel;

  MethodChannel get channel => _channel ?? _defaultChannel;

  Future<List<ProjectEntity>> getAllProjects() async {
    try {
      final result = await channel.invokeListMethod<Object?>('getAllProjects');
      return (result ?? [])
          .whereType<Map<Object?, Object?>>()
          .map((item) => ProjectEntity.fromMap(item.cast<String, Object?>()))
          .toList();
    } on MissingPluginException {
      return [];
    }
  }

  Future<ProjectEntity?> getById(int id) async {
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        'getProjectById',
        {'id': id},
      );
      return result == null ? null : ProjectEntity.fromMap(result);
    } on MissingPluginException {
      return null;
    }
  }

  Future<int> insert(ProjectEntity project) async {
    try {
      final result = await channel.invokeMethod<int>(
        'insertProject',
        project.toMap(),
      );
      return result ?? 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<bool> update(ProjectEntity project) async {
    try {
      final result = await channel.invokeMethod<int>(
        'updateProject',
        project.toMap(),
      );
      return (result ?? 0) > 0;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> delete(ProjectEntity project) async {
    final id = project.id;
    if (id == null) {
      return false;
    }
    try {
      final result = await channel.invokeMethod<int>('deleteProject', {
        'id': id,
      });
      return (result ?? 0) > 0;
    } on MissingPluginException {
      return false;
    }
  }
}
