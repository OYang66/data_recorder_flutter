class LoginResponse {
  const LoginResponse({
    required this.token,
    required this.username,
    required this.userId,
  });

  final String token;
  final String username;
  final int userId;

  factory LoginResponse.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return LoginResponse(
      token: json['token']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      userId: (json['userId'] as num?)?.toInt() ?? 0,
    );
  }
}

class AccountStatusResponse {
  const AccountStatusResponse({
    required this.valid,
    this.message,
    this.onlineStatus,
    this.lastActiveTime,
  });

  final bool valid;
  final String? message;
  final String? onlineStatus;
  final String? lastActiveTime;

  factory AccountStatusResponse.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return AccountStatusResponse(
      valid: json['valid'] == true,
      message: json['message']?.toString(),
      onlineStatus: json['onlineStatus']?.toString(),
      lastActiveTime: json['lastActiveTime']?.toString(),
    );
  }
}
