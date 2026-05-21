class DeliveryOrderUploadFile {
  const DeliveryOrderUploadFile({
    required this.path,
    required this.fileName,
    this.mimeType,
  });

  final String path;
  final String fileName;
  final String? mimeType;
}
