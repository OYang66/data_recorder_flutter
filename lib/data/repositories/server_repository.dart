import 'package:dio/dio.dart';

import '../../core/network/api_response.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/preferences.dart';
import '../models/api/server_models.dart';
import '../models/api/sub_display_models.dart';

class ServerRepository {
  ServerRepository({Dio? dio, AppPreferences? preferences})
    : _dio = dio ?? DioClient(preferences: preferences).create();

  final Dio _dio;

  Future<ApiResponse<List<ServerProjectInfo>>> getProjectInfoList({
    String keyword = '',
  }) async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/projectInfo/list',
      queryParameters: keyword.isEmpty ? null : {'projectName': keyword},
    );
    return ApiResponse<List<ServerProjectInfo>>.fromJson(
      response.data ?? {},
      (value) => _readList(value, ServerProjectInfo.fromJson),
    );
  }

  Future<ApiResponse<List<ServerBuildingInfo>>> getProjectBuildings(
    String projectName,
  ) async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/projectInfo/buildings',
      queryParameters: {'projectName': projectName},
    );
    return ApiResponse<List<ServerBuildingInfo>>.fromJson(
      response.data ?? {},
      (value) => _readList(value, ServerBuildingInfo.fromJson),
    );
  }

  Future<ApiResponse<ServerStatSummary>> getStatSummary() async {
    final response = await _dio.get<Map<String, Object?>>('app/stat/summary');
    return ApiResponse<ServerStatSummary>.fromJson(
      response.data ?? {},
      ServerStatSummary.fromJson,
    );
  }

  Future<ApiResponse<AppNoticeInfo>> getLatestNotice() async {
    final response = await _dio.get<Map<String, Object?>>('app/notice/latest');
    return ApiResponse<AppNoticeInfo>.fromJson(
      response.data ?? {},
      AppNoticeInfo.fromJson,
    );
  }

  Future<ApiResponse<Object?>> uploadModelStatFile({
    required String projectName,
    required String buildingName,
    required String filePath,
  }) {
    return _uploadFile(
      path: 'app/upload/modelStatFile',
      projectName: projectName,
      buildingName: buildingName,
      filePath: filePath,
    );
  }

  Future<ApiResponse<Object?>> uploadReturnStatFile({
    required String projectName,
    required String buildingName,
    required String filePath,
  }) {
    return _uploadFile(
      path: 'app/upload/returnStatFile',
      projectName: projectName,
      buildingName: buildingName,
      filePath: filePath,
    );
  }

  Future<ApiResponse<Object?>> uploadReturnLoadFile({
    required String projectName,
    required String buildingName,
    required String filePath,
  }) {
    return _uploadFile(
      path: 'app/upload/returnLoadFile',
      projectName: projectName,
      buildingName: buildingName,
      filePath: filePath,
    );
  }

  Future<ApiResponse<AppConnectionCodeData>> generateSubDisplayCode() async {
    final response = await _dio.post<Map<String, Object?>>(
      'api/app/generate-code',
    );
    return ApiResponse<AppConnectionCodeData>.fromJson(
      response.data ?? {},
      AppConnectionCodeData.fromJson,
    );
  }

  Future<ApiResponse<AppSubDisplayConnectionStatus>> getSubDisplayStatus(
    String code,
  ) async {
    final response = await _dio.post<Map<String, Object?>>(
      'api/app/connection-status',
      data: {'code': code},
    );
    return ApiResponse<AppSubDisplayConnectionStatus>.fromJson(
      response.data ?? {},
      AppSubDisplayConnectionStatus.fromJson,
    );
  }

  Future<ApiResponse<ServerPageResult<DeliveryOrderFileItem>>>
  getDeliveryOrderFiles({
    String projectName = '',
    String fileName = '',
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/deliveryOrder/list',
      queryParameters: {
        if (projectName.trim().isNotEmpty) 'projectName': projectName.trim(),
        if (fileName.trim().isNotEmpty) 'fileName': fileName.trim(),
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    return ApiResponse<ServerPageResult<DeliveryOrderFileItem>>.fromJson(
      response.data ?? {},
      (value) =>
          ServerPageResult.fromJson(value, DeliveryOrderFileItem.fromJson),
    );
  }

  Future<ApiResponse<List<DeliveryOrderSheetItem>>> getDeliveryOrderSheets({
    int? fileId,
  }) async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/deliveryOrder/sheetList',
      queryParameters: {'fileId': ?fileId},
    );
    return ApiResponse<List<DeliveryOrderSheetItem>>.fromJson(
      response.data ?? {},
      (value) => _readList(value, DeliveryOrderSheetItem.fromJson),
    );
  }

  Future<ApiResponse<List<String>>> getDeliveryOrderProjectNames() async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/deliveryOrder/projectNames',
    );
    return ApiResponse<List<String>>.fromJson(
      response.data ?? {},
      (value) => value is List
          ? value.map((item) => item.toString()).toList()
          : <String>[],
    );
  }

  Future<ApiResponse<Object?>> uploadDeliveryOrder({
    required String filePath,
    String? fileName,
    bool calculateNetWeight = false,
  }) async {
    final uploadFileName = fileName?.trim();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: uploadFileName == null || uploadFileName.isEmpty
            ? null
            : uploadFileName,
      ),
    });
    final response = await _dio.post<Map<String, Object?>>(
      'app/deliveryOrder/upload',
      queryParameters: {'calculateNetWeight': calculateNetWeight},
      data: formData,
    );
    return ApiResponse<Object?>.fromJson(response.data ?? {}, (value) => value);
  }

  Future<ApiResponse<Object?>> confirmDeliveryOrderNetWeight(int fileId) async {
    final response = await _dio.post<Map<String, Object?>>(
      'app/deliveryOrder/confirmNetWeight/$fileId',
    );
    return ApiResponse<Object?>.fromJson(response.data ?? {}, (value) => value);
  }

  Future<ApiResponse<Object?>> deleteDeliveryOrder(int fileId) async {
    final response = await _dio.delete<Map<String, Object?>>(
      'app/deliveryOrder/$fileId',
    );
    return ApiResponse<Object?>.fromJson(response.data ?? {}, (value) => value);
  }

  Future<Response<List<int>>> downloadDeliveryOrder(int fileId) {
    return _dio.get<List<int>>(
      'app/deliveryOrder/download/$fileId',
      options: Options(responseType: ResponseType.bytes),
    );
  }

  Future<ApiResponse<List<MissingMaterialItem>>>
  getDeliveryMissingMaterials() async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/deliveryOrder/missingMaterials',
    );
    return ApiResponse<List<MissingMaterialItem>>.fromJson(
      response.data ?? {},
      (value) => _readList(value, MissingMaterialItem.fromJson),
    );
  }

  Future<ApiResponse<List<DeliveryMaterialNameItem>>>
  getDeliveryMaterialNames() async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/deliveryOrder/materialNames',
    );
    return ApiResponse<List<DeliveryMaterialNameItem>>.fromJson(
      response.data ?? {},
      (value) => _readList(value, DeliveryMaterialNameItem.fromJson),
    );
  }

  Future<ApiResponse<Object?>> saveDeliveryMaterialNames(
    List<DeliveryMaterialNameItem> items,
  ) async {
    final response = await _dio.post<Map<String, Object?>>(
      'app/deliveryOrder/materialNames',
      data: items.map((item) => item.toJson()).toList(),
    );
    return ApiResponse<Object?>.fromJson(response.data ?? {}, (value) => value);
  }

  Future<ApiResponse<Object?>> reparseDeliveryOrders() async {
    final response = await _dio.post<Map<String, Object?>>(
      'app/deliveryOrder/reparse',
    );
    return ApiResponse<Object?>.fromJson(response.data ?? {}, (value) => value);
  }

  Future<ApiResponse<List<SettlementTypeOption>>>
  getSettlementTypeOptions() async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/settlementData/typeOptions',
    );
    return ApiResponse<List<SettlementTypeOption>>.fromJson(
      response.data ?? {},
      (value) => _readList(value, SettlementTypeOption.fromJson),
    );
  }

  Future<ApiResponse<List<String>>> getSettlementProjectNames(
    String dataType,
  ) async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/settlementData/projectNames',
      queryParameters: {'dataType': dataType},
    );
    return ApiResponse<List<String>>.fromJson(
      response.data ?? {},
      (value) => value is List
          ? value.map((item) => item.toString()).toList()
          : <String>[],
    );
  }

  Future<ApiResponse<List<SettlementColumnItem>>> getSettlementDeliveryColumns(
    String projectName,
  ) async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/settlementData/deliveryOrder/columns',
      queryParameters: {'projectName': projectName},
    );
    return ApiResponse<List<SettlementColumnItem>>.fromJson(
      response.data ?? {},
      (value) => _readList(value, SettlementColumnItem.fromJson),
    );
  }

  Future<ApiResponse<List<Map<String, Object?>>>> getSettlementDeliveryRows(
    String projectName,
  ) async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/settlementData/deliveryOrder/list',
      queryParameters: {'projectName': projectName},
    );
    return ApiResponse<List<Map<String, Object?>>>.fromJson(
      response.data ?? {},
      _readMapRows,
    );
  }

  Future<ApiResponse<List<Map<String, Object?>>>>
  getSettlementMaterialSummaryRows(String projectName) async {
    final response = await _dio.get<Map<String, Object?>>(
      'app/settlementData/materialSummary/list',
      queryParameters: {'projectName': projectName},
    );
    return ApiResponse<List<Map<String, Object?>>>.fromJson(
      response.data ?? {},
      _readMapRows,
    );
  }

  Future<Response<List<int>>> exportSettlementDeliveryOrder(
    String projectName,
  ) {
    return _dio.post<List<int>>(
      'app/settlementData/deliveryOrder/export',
      queryParameters: {'projectName': projectName},
      options: Options(responseType: ResponseType.bytes),
    );
  }

  Future<Response<List<int>>> exportSettlementMaterialSummary(
    String projectName,
  ) {
    return _dio.post<List<int>>(
      'app/settlementData/materialSummary/export',
      queryParameters: {'projectName': projectName},
      options: Options(responseType: ResponseType.bytes),
    );
  }

  Future<ApiResponse<AppPushReturnDataResult>> pushReturnData({
    required String code,
    required Map<String, Object?> payload,
  }) async {
    final response = await _dio.post<Map<String, Object?>>(
      'api/app/push-return-data',
      data: {'code': code, 'payload': payload},
    );
    return ApiResponse<AppPushReturnDataResult>.fromJson(
      response.data ?? {},
      AppPushReturnDataResult.fromJson,
    );
  }

  Future<ApiResponse<Object?>> _uploadFile({
    required String path,
    required String projectName,
    required String buildingName,
    required String filePath,
  }) async {
    final formData = FormData.fromMap({
      'projectName': projectName,
      'buildingName': buildingName,
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await _dio.post<Map<String, Object?>>(
      path,
      data: formData,
    );
    return ApiResponse<Object?>.fromJson(response.data ?? {}, (value) => value);
  }
}

List<T> _readList<T>(Object? value, T Function(Object?) parse) {
  final rawList = switch (value) {
    {'rows': final rows} => rows,
    {'list': final list} => list,
    _ => value,
  };
  if (rawList is! List) {
    return [];
  }
  return rawList.map(parse).toList();
}

List<Map<String, Object?>> _readMapRows(Object? value) {
  final rawList = switch (value) {
    {'rows': final rows} => rows,
    {'list': final list} => list,
    _ => value,
  };
  if (rawList is! List) return [];
  return rawList
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
      .toList();
}
