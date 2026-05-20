import 'package:dio/dio.dart';

import '../constants/api_constants.dart';
import '../storage/preferences.dart';

class DioClient {
  DioClient({AppPreferences? preferences})
    : _preferences = preferences ?? AppPreferences();

  final AppPreferences _preferences;

  Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _preferences.getToken();
          if (token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await _preferences.forceLogout('登录状态已失效，请重新登录');
          }
          handler.next(error);
        },
      ),
    );
    return dio;
  }
}
