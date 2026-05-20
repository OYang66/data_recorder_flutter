import '../../core/storage/local_database.dart';
import '../models/project_entity.dart';

class ProjectRepository {
  const ProjectRepository({LocalDatabase? database}) : _database = database;

  final LocalDatabase? _database;

  LocalDatabase get database => _database ?? LocalDatabase.instance;

  Future<int> insert(ProjectEntity project) => database.insert(project);

  Future<void> update(ProjectEntity project) => database.update(project);

  Future<void> delete(ProjectEntity project) => database.delete(project);

  Future<List<ProjectEntity>> getAllProjects() => database.getAllProjects();

  Future<ProjectEntity?> getById(int id) => database.getById(id);

  Future<ProjectEntity?> getByName(String name) => database.getByName(name);

  Future<List<ProjectEntity>> getByNameList(String name) =>
      database.getByNameList(name);
}
