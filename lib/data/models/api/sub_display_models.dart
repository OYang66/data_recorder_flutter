class AppConnectionCodeData {
  const AppConnectionCodeData({
    this.code = '',
    this.status = '',
    this.expireTime = '',
    this.token = '',
    this.idleTimeoutMinutes = 0,
  });

  final String code;
  final String status;
  final String expireTime;
  final String token;
  final int idleTimeoutMinutes;

  factory AppConnectionCodeData.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return AppConnectionCodeData(
      code: json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      expireTime: json['expireTime']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      idleTimeoutMinutes: (json['idleTimeoutMinutes'] as num?)?.toInt() ?? 0,
    );
  }
}

class AppSubDisplayDevice {
  const AppSubDisplayDevice({
    this.deviceId = '',
    this.deviceModel = '',
    this.lastActiveTime = '',
  });

  final String deviceId;
  final String deviceModel;
  final String lastActiveTime;

  factory AppSubDisplayDevice.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return AppSubDisplayDevice(
      deviceId: json['deviceId']?.toString() ?? '',
      deviceModel: json['deviceModel']?.toString() ?? '',
      lastActiveTime: json['lastActiveTime']?.toString() ?? '',
    );
  }
}

class AppSubDisplayConnectionStatus {
  const AppSubDisplayConnectionStatus({
    this.connected = false,
    this.sessionCount = 0,
    this.lastEventTime = '',
    this.source = '',
    this.devices = const [],
  });

  final bool connected;
  final int sessionCount;
  final String lastEventTime;
  final String source;
  final List<AppSubDisplayDevice> devices;

  factory AppSubDisplayConnectionStatus.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return AppSubDisplayConnectionStatus(
      connected: json['connected'] == true,
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      lastEventTime: json['lastEventTime']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      devices: (json['devices'] as List? ?? [])
          .map(AppSubDisplayDevice.fromJson)
          .toList(),
    );
  }
}

class AppPushReturnDataResult extends AppSubDisplayConnectionStatus {
  const AppPushReturnDataResult({
    super.connected,
    super.sessionCount,
    super.lastEventTime,
    super.source,
    super.devices,
    this.receiverCount = 0,
  });

  final int receiverCount;

  factory AppPushReturnDataResult.fromJson(Object? value) {
    final json = value as Map<String, Object?>? ?? {};
    return AppPushReturnDataResult(
      receiverCount: (json['receiverCount'] as num?)?.toInt() ?? 0,
      connected: json['connected'] == true,
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      lastEventTime: json['lastEventTime']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      devices: (json['devices'] as List? ?? [])
          .map(AppSubDisplayDevice.fromJson)
          .toList(),
    );
  }
}
