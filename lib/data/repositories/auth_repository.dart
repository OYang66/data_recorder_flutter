import 'package:dio/dio.dart';

import '../../core/network/api_response.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/preferences.dart';
import '../models/api/auth_models.dart';

class AuthRepository {
  AuthRepository({Dio? dio, AppPreferences? preferences})
    : _dio = dio ?? DioClient(preferences: preferences).create(),
      _preferences = preferences ?? AppPreferences();

  final Dio _dio;
  final AppPreferences _preferences;

  Future<ApiResponse<LoginResponse>> login(
    String username,
    String password,
  ) async {
    final response = await _dio.post<Map<String, Object?>>(
      'app/auth/login',
      data: {'username': username, 'password': password},
    );
    final apiResponse = ApiResponse<LoginResponse>.fromJson(
      response.data ?? {},
      LoginResponse.fromJson,
    );
    final data = apiResponse.data;
    if (apiResponse.isSuccess && data != null) {
      await _preferences.saveLogin(
        token: data.token,
        username: data.username,
        userId: data.userId,
      );
    }
    return apiResponse;
  }

  Future<ApiResponse<Object?>> register(
    String username,
    String password,
  ) async {
    final response = await _dio.post<Map<String, Object?>>(
      'app/auth/register',
      data: {'username': username, 'password': password},
    );
    return ApiResponse<Object?>.fromJson(response.data ?? {}, (value) => value);
  }

  Future<ApiResponse<AccountStatusResponse>> checkAccountStatus(
    String username,
  ) async {
    final response = await _dio.post<Map<String, Object?>>(
      'app/auth/checkStatus',
      data: {'username': username},
    );
    return ApiResponse<AccountStatusResponse>.fromJson(
      response.data ?? {},
      AccountStatusResponse.fromJson,
    );
  }

  Future<ApiResponse<AccountStatusResponse>> reportActive() async {
    final response = await _dio.post<Map<String, Object?>>('app/auth/active');
    return ApiResponse<AccountStatusResponse>.fromJson(
      response.data ?? {},
      AccountStatusResponse.fromJson,
    );
  }

  Future<ApiResponse<Object?>> checkRegisterAccount(String accountName) async {
    final response = await _dio.post<Map<String, Object?>>(
      'app/auth/checkRegisterAccount',
      data: {'accountName': accountName},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    return ApiResponse<Object?>.fromJson(response.data ?? {}, (value) => value);
  }
}
