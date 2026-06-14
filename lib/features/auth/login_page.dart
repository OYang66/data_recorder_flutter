import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/storage/preferences.dart';
import '../../core/widgets/app_dialog_chrome.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_network_retry.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repository = AuthRepository();
  final _preferences = AppPreferences();

  bool _remember = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedAccount();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedAccount() async {
    await _preferences.migrateLegacyPreferences();
    final remember = await _preferences.isRememberEnabled();
    final username = await _preferences.getSavedUsername();
    final password = await _preferences.getSavedPassword();
    final logoutReason = await _preferences.consumeLogoutReason();
    if (!mounted) {
      return;
    }
    setState(() {
      _remember = remember || username.isNotEmpty || password.isNotEmpty;
      _usernameController.text = username;
      _passwordController.text = password;
    });
    if (logoutReason.isNotEmpty) {
      _showMessage(logoutReason);
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showMessage('请输入账号和密码');
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await runWithIosNetworkAuthorizationRetry(
        () => _repository.login(username, password),
        isMounted: () => mounted,
        onWaitingForAuthorization: () {
          if (mounted) {
            _showMessage('请先完成系统网络授权，授权后自动继续登录');
          }
        },
      );
      if (!mounted) {
        return;
      }
      if (response.isSuccess) {
        if (_remember) {
          await _preferences.saveRememberedAccount(username, password);
        } else {
          await _preferences.clearRememberedAccount();
        }
        if (!mounted) {
          return;
        }
        context.go('/main');
      } else {
        _showMessage(response.displayMessage.ifEmpty('登录失败'));
      }
    } catch (error) {
      if (mounted) {
        _showMessage(_networkErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showMessage(String message) {
    showAppToast(context, message);
  }

  String _networkErrorMessage(Object error) => authNetworkErrorMessage(error);

  Future<void> _openTutorial() async {
    const url = 'https://yxff.work/';
    try {
      await const MethodChannel(
        'com.example.datarecorder/update',
      ).invokeMethod('openUrl', {'url': url});
    } on MissingPluginException {
      await Clipboard.setData(const ClipboardData(text: url));
      if (mounted) {
        _showMessage('教程地址已复制');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 28),
              const Text(
                '毅想非凡管理系统',
                style: TextStyle(
                  color: Color(0xFF222222),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '安卓端登录',
                style: TextStyle(color: Color(0xFF6D7385), fontSize: 15),
              ),
              const SizedBox(height: 28),
              _AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AuthTextField(
                      controller: _usernameController,
                      hintText: '请输入用户名',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    _AuthTextField(
                      controller: _passwordController,
                      hintText: '请输入密码',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () => setState(() => _remember = !_remember),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _remember,
                            activeColor: AppColors.primary,
                            onChanged: (value) => setState(() {
                              _remember = value ?? false;
                            }),
                          ),
                          const Text(
                            '记住账号密码',
                            style: TextStyle(
                              color: Color(0xFF5E6575),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AuthButton(
                      text: _loading ? '登录中...' : '登录',
                      backgroundColor: AppColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      onPressed: _loading ? null : _login,
                    ),
                    const SizedBox(height: 12),
                    _AuthButton(
                      text: '没有账号，去注册',
                      backgroundColor: const Color(0xFF8C7BD1),
                      onPressed: _loading
                          ? null
                          : () => context.go('/register'),
                    ),
                    const SizedBox(height: 12),
                    _AuthButton(
                      text: '查看教程',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      borderColor: AppColors.primary,
                      onPressed: _loading ? null : _openTutorial,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EAF3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide(color: Color(0xFFDCE3F1)),
    );

    return SizedBox(
      height: 50,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        cursorColor: AppColors.primary,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF8FAFF),
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFF9AA1B2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.text,
    required this.backgroundColor,
    required this.onPressed,
    this.foregroundColor = Colors.white,
    this.borderColor,
    this.fontSize = 15,
    this.fontWeight = FontWeight.normal,
  });

  final String text;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final double fontSize;
  final FontWeight fontWeight;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.55),
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.7),
          side: borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor!, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: fontWeight),
        ),
        onPressed: onPressed,
        child: Text(text),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
