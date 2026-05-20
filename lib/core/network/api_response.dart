class ApiResponse<T> {
  const ApiResponse({required this.code, this.msg, this.message, this.data});

  final int code;
  final String? msg;
  final String? message;
  final T? data;

  bool get isSuccess => code == 200;
  String get displayMessage => msg ?? message ?? '';

  factory ApiResponse.fromJson(
    Map<String, Object?> json,
    T Function(Object? value) parseData,
  ) {
    return ApiResponse<T>(
      code: (json['code'] as num?)?.toInt() ?? -1,
      msg: json['msg']?.toString(),
      message: json['message']?.toString(),
      data: json.containsKey('data') ? parseData(json['data']) : null,
    );
  }
}
