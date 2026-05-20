import '../../data/models/project_entity.dart';
import 'legacy_database_bridge.dart';

class LocalDatabase {
  LocalDatabase._({LegacyDatabaseBridge bridge = const LegacyDatabaseBridge()})
    : _bridge = bridge;

  static final instance = LocalDatabase._();

  final LegacyDatabaseBridge _bridge;
  final List<ProjectEntity> _projects = [];
  int _nextId = 1;
  bool _loadedLegacyProjects = false;

  Future<void> _loadLegacyProjects() async {
    if (_loadedLegacyProjects) {
      return;
    }
    _loadedLegacyProjects = true;
    final projects = await _bridge.getAllProjects();
    if (projects.isNotEmpty) {
      _projects
        ..clear()
        ..addAll(projects);
      final maxId = projects
          .map((project) => project.id ?? 0)
          .fold<int>(0, (max, id) => id > max ? id : max);
      _nextId = maxId + 1;
    }
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
    }
  }

  Future<void> delete(ProjectEntity project) async {
    await _loadLegacyProjects();
    await _bridge.delete(project);
    _projects.removeWhere((item) => item.id == project.id);
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
