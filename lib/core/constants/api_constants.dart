class ApiConstants {
  const ApiConstants._();

  static const baseUrl = String.fromEnvironment(
    'DATARECORDER_BASE_URL',
    defaultValue: 'http://175.178.12.210:82/prod-api/',
  );
}
