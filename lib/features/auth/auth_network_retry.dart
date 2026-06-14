import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';

Future<T> runWithIosNetworkAuthorizationRetry<T>(
  Future<T> Function() request, {
  required bool Function() isMounted,
  void Function()? onWaitingForAuthorization,
}) async {
  const retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
  ];
  for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
    try {
      return await request();
    } catch (error) {
      if (!isIosNetworkAuthorizationError(error) ||
          attempt >= retryDelays.length) {
        rethrow;
      }
      if (attempt == 0) onWaitingForAuthorization?.call();
      await Future<void>.delayed(retryDelays[attempt]);
      if (!isMounted()) rethrow;
    }
  }
  return request();
}

bool isIosNetworkAuthorizationError(Object error) {
  if (!Platform.isIOS || error is! DioException) return false;
  final text = [error.message ?? '', error.error?.toString() ?? ''].join(' ');
  return text.contains('Operation not permitted') ||
      text.contains('Network is unreachable') ||
      text.contains('No route to host');
}

String authNetworkErrorMessage(Object error) {
  if (error is DioException) {
    final message = error.message ?? '';
    final fallback = message.isEmpty ? error.type.name : message;
    if (isIosNetworkAuthorizationError(error)) {
      return 'iOS 网络授权未完成，请在系统弹窗中允许“无线局域网与蜂窝网络”后再试';
    }
    if (message.contains('SocketException') ||
        message.contains('Connection failed')) {
      return '网络连接失败：$fallback';
    }
    if (message.contains('ATS') || message.contains('cleartext')) {
      return 'iOS 已拦截 HTTP 网络请求，请重新打包安装最新版';
    }
    return '网络异常：$fallback';
  }
  return '网络异常，请稍后重试';
}
