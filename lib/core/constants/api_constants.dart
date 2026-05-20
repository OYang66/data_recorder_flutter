class ApiConstants {
  const ApiConstants._();

  static const baseUrl = String.fromEnvironment(
    'DATARECORDER_BASE_URL',
    defaultValue: 'https://yxff.work/prod-api/',
  );
}
