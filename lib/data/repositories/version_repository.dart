import 'package:dio/dio.dart';

import '../../core/network/api_response.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/preferences.dart';
import '../models/api/version_models.dart';

class VersionRepository {
  VersionRepository({Dio? dio, AppPreferences? preferences})
    : _dio = dio ?? DioClient(preferences: preferences).create();

  final Dio _dio;

  Future<ApiResponse<AppVersionInfo>> getLatestVersion() async {
    final response = await _dio.get<Map<String, Object?>>(
      'api/app/version/latest',
    );
    return ApiResponse<AppVersionInfo>.fromJson(
      response.data ?? {},
      AppVersionInfo.fromJson,
    );
  }
}
