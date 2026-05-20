import 'dart:async';

import 'legacy_android_bridge.dart';

class AppPreferences {
  AppPreferences({LegacyAndroidBridge bridge = const LegacyAndroidBridge()})
    : _bridge = bridge;

  static const _tokenKey = 'token';
  static const _usernameKey = 'username';
  static const _userIdKey = 'user_id';
  static const _logoutReasonKey = 'logout_reason';
  static const _rememberKey = 'remember_account_password';
  static const _savedUsernameKey = 'saved_username';
  static const _savedPasswordKey = 'saved_password';
  static const _mainModeKey = 'flutter_main_mode';
  static const _packageNameKey = 'flutter_package_name';
  static const _tripNameKey = 'flutter_trip_name';
  static const _qualityFloorKey = 'flutter_quality_floor';
  static const _subDisplayCodeKey = 'flutter_sub_display_code';
  static const _lastProjectIdKey = 'last_project_id';
  static const _noticeShownPrefix = 'notice_shown_';
  static const _sessionPrefs = 'user_session';
  static const _appPrefs = 'app_prefs';
  static const _disclaimerAgreedKey = 'disclaimer_agreed';

  static final Map<String, Object?> _values = {};
  static final StreamController<String> _logoutEvents =
      StreamController<String>.broadcast();

  static Stream<String> get logoutEvents => _logoutEvents.stream;

  final LegacyAndroidBridge _bridge;

  Future<void> migrateLegacyPreferences() async {
    if (_values.isNotEmpty) {
      return;
    }
    _values.addAll(await _bridge.readPreferences(_sessionPrefs));
  }

  Future<String> getToken() async {
    await migrateLegacyPreferences();
    return _values[_tokenKey]?.toString() ?? '';
  }

  Future<void> saveLogin({
    required String token,
    required String username,
    required int userId,
  }) async {
    final values = {
      _tokenKey: token,
      _usernameKey: username,
      _userIdKey: userId,
    };
    _values.addAll(values);
    await _bridge.writePreferences(_sessionPrefs, values);
  }

  Future<String> getUsername() async {
    await migrateLegacyPreferences();
    return _values[_usernameKey]?.toString() ?? '';
  }

  Future<int> getUserId() async {
    await migrateLegacyPreferences();
    final value = _values[_userIdKey];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    final username = await getUsername();
    return token.isNotEmpty && username.isNotEmpty;
  }

  Future<void> clearLogin() async {
    _values.remove(_tokenKey);
    _values.remove(_usernameKey);
    _values.remove(_userIdKey);
    await _bridge.removePreferences(_sessionPrefs, [
      _tokenKey,
      _usernameKey,
      _userIdKey,
    ]);
  }

  Future<void> forceLogout(String reason) async {
    await saveLogoutReason(reason);
    await clearLogin();
    _logoutEvents.add(reason);
  }

  Future<String> getShownNoticeKey() async {
    await migrateLegacyPreferences();
    final username = (await getUsername()).trim();
    return _values['$_noticeShownPrefix$username']?.toString() ?? '';
  }

  Future<void> saveShownNoticeKey(String noticeKey) async {
    final username = (await getUsername()).trim();
    final key = '$_noticeShownPrefix$username';
    _values[key] = noticeKey;
    await _bridge.writePreferences(_sessionPrefs, {key: noticeKey});
  }

  Future<void> saveLogoutReason(String reason) async {
    _values[_logoutReasonKey] = reason;
    await _bridge.writePreferences(_sessionPrefs, {_logoutReasonKey: reason});
  }

  Future<String> consumeLogoutReason() async {
    final reason = _values[_logoutReasonKey]?.toString() ?? '';
    _values.remove(_logoutReasonKey);
    await _bridge.removePreferences(_sessionPrefs, [_logoutReasonKey]);
    return reason;
  }

  Future<String> getSavedUsername() async {
    await migrateLegacyPreferences();
    return _values[_savedUsernameKey]?.toString() ?? '';
  }

  Future<String> getSavedPassword() async {
    await migrateLegacyPreferences();
    return _values[_savedPasswordKey]?.toString() ?? '';
  }

  Future<bool> isRememberEnabled() async {
    await migrateLegacyPreferences();
    return _values[_rememberKey] == true;
  }

  Future<void> saveRememberedAccount(String username, String password) async {
    final values = {
      _rememberKey: true,
      _savedUsernameKey: username,
      _savedPasswordKey: password,
    };
    _values.addAll(values);
    await _bridge.writePreferences(_sessionPrefs, values);
  }

  Future<void> clearRememberedAccount() async {
    _values[_rememberKey] = false;
    _values.remove(_savedUsernameKey);
    _values.remove(_savedPasswordKey);
    await _bridge.writePreferences(_sessionPrefs, {_rememberKey: false});
    await _bridge.removePreferences(_sessionPrefs, [
      _savedUsernameKey,
      _savedPasswordKey,
    ]);
  }

  Future<Map<String, String>> getMainState() async {
    await migrateLegacyPreferences();
    return {
      _mainModeKey: _values[_mainModeKey]?.toString() ?? '',
      _packageNameKey: _values[_packageNameKey]?.toString() ?? '',
      _tripNameKey: _values[_tripNameKey]?.toString() ?? '',
      _qualityFloorKey: _values[_qualityFloorKey]?.toString() ?? '',
      _subDisplayCodeKey: _values[_subDisplayCodeKey]?.toString() ?? '',
    };
  }

  Future<void> saveMainState({
    required String mode,
    required String packageName,
    required String tripName,
    required String qualityFloor,
    required String subDisplayCode,
  }) async {
    final values = {
      _mainModeKey: mode,
      _packageNameKey: packageName,
      _tripNameKey: tripName,
      _qualityFloorKey: qualityFloor,
      _subDisplayCodeKey: subDisplayCode,
    };
    _values.addAll(values);
    await _bridge.writePreferences(_sessionPrefs, values);
  }

  Future<int> getLastProjectId() async {
    final values = await _bridge.readPreferences(_appPrefs);
    final value = values[_lastProjectIdKey];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> saveLastProjectId(int id) async {
    await _bridge.writePreferences(_appPrefs, {_lastProjectIdKey: id});
  }

  Future<bool> isDisclaimerAgreed() async {
    final values = await _bridge.readPreferences(_appPrefs);
    return values[_disclaimerAgreedKey] == true;
  }

  Future<void> saveDisclaimerAgreed() async {
    await _bridge.writePreferences(_appPrefs, {_disclaimerAgreedKey: true});
  }
}
