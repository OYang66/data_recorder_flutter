import 'dart:convert';

import '../../data/models/project_entity.dart';
import 'legacy_android_bridge.dart';
import 'legacy_database_bridge.dart';

class LocalDatabase {
  LocalDatabase._({
    LegacyDatabaseBridge bridge = const LegacyDatabaseBridge(),
    LegacyAndroidBridge preferencesBridge = const LegacyAndroidBridge(),
  }) : _bridge = bridge,
       _preferencesBridge = preferencesBridge;

  static const _fallbackPrefs = 'flutter_local_database';
  static const _projectsKey = 'projects_json';
  static final instance = LocalDatabase._();

  final LegacyDatabaseBridge _bridge;
  final LegacyAndroidBridge _preferencesBridge;
  final List<ProjectEntity> _projects = [];
  int _nextId = 1;
  bool _loadedLegacyProjects = false;

  Future<void> _loadLegacyProjects() async {
    if (_loadedLegacyProjects) {
      return;
    }
    _loadedLegacyProjects = true;
    final nativeProjects = await _bridge.getAllProjects();
    final projects = nativeProjects.isNotEmpty
        ? nativeProjects
        : await _loadFallbackProjects();
    if (projects.isEmpty) return;
    _projects
      ..clear()
      ..addAll(projects);
    _refreshNextId();
  }

  Future<List<ProjectEntity>> _loadFallbackProjects() async {
    final values = await _preferencesBridge.readPreferences(_fallbackPrefs);
    final content = values[_projectsKey]?.toString() ?? '';
    if (content.isEmpty) return const [];
    try {
      final decoded = jsonDecode(content);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((item) {
        final map = item.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        return ProjectEntity.fromMap(map);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _syncFallbackProjects() async {
    await _preferencesBridge.writePreferences(_fallbackPrefs, {
      _projectsKey: jsonEncode(
        _projects.map((project) => project.toMap()).toList(),
      ),
    });
  }

  void _refreshNextId() {
    final maxId = _projects
        .map((project) => project.id ?? 0)
        .fold<int>(0, (max, id) => id > max ? id : max);
    _nextId = maxId + 1;
  }

  Future<int> insert(ProjectEntity project) async {
    await _loadLegacyProjects();
    final nativeId = await _bridge.insert(project);
    final id = nativeId > 0 ? nativeId : _nextId++;
    _projects.add(
      ProjectEntity(
        id: id,
        name: project.name,
        buildingName: project.buildingName,
        standardContent: project.standardContent,
        fastContent: project.fastContent,
        loadingContent: project.loadingContent,
        qualityContent: project.qualityContent,
      ),
    );
    await _syncFallbackProjects();
    return id;
  }

  Future<void> update(ProjectEntity project) async {
    await _loadLegacyProjects();
    final id = project.id;
    if (id == null) {
      return;
    }
    await _bridge.update(project);
    final index = _projects.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _projects[index] = project;
      await _syncFallbackProjects();
    }
  }

  Future<void> delete(ProjectEntity project) async {
    await _loadLegacyProjects();
    await _bridge.delete(project);
    _projects.removeWhere((item) => item.id == project.id);
    await _syncFallbackProjects();
  }

  Future<List<ProjectEntity>> getAllProjects() async {
    await _loadLegacyProjects();
    return _projects.reversed.toList(growable: false);
  }

  Future<ProjectEntity?> getById(int id) async {
    await _loadLegacyProjects();
    for (final project in _projects) {
      if (project.id == id) {
        return project;
      }
    }
    final project = await _bridge.getById(id);
    if (project != null) {
      _projects.add(project);
    }
    return project;
  }

  Future<ProjectEntity?> getByName(String name) async {
    final list = await getByNameList(name);
    return list.isEmpty ? null : list.first;
  }

  Future<List<ProjectEntity>> getByNameList(String name) async {
    await _loadLegacyProjects();
    return _projects.where((project) => project.name == name).toList();
  }
}
