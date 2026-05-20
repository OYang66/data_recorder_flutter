import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/storage/preferences.dart';
import '../../core/widgets/app_dialog_chrome.dart';
import '../../data/repositories/auth_repository.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repository = AuthRepository();
  final _preferences = AppPreferences();
  bool _loading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty) {
      _showMessage('请输入真实姓名');
      return;
    }
    if (password.isEmpty) {
      _showMessage('请输入密码');
      return;
    }
    if (username.length < 2) {
      _showMessage('姓名至少2位');
      return;
    }
    if (password.length < 6) {
      _showMessage('密码至少6位');
      return;
    }

    setState(() => _loading = true);
    try {
      final check = await _repository.checkRegisterAccount(username);
      if (!mounted) {
        return;
      }
      if (!check.isSuccess) {
        _showMessage(check.displayMessage.ifEmpty('该账号不允许注册'));
        return;
      }

      final response = await _repository.register(username, password);
      if (!mounted) {
        return;
      }
      if (response.isSuccess) {
        await _preferences.saveRememberedAccount(username, password);
        if (!mounted) {
          return;
        }
        _showMessage(response.displayMessage.ifEmpty('注册成功'));
        context.go('/login');
      } else {
        _showMessage(response.displayMessage.ifEmpty('注册失败'));
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

  String _networkErrorMessage(Object error) {
    if (error is DioException) {
      final message = error.message ?? '';
      if (message.contains('Operation not permitted') ||
          message.contains('Network is unreachable')) {
        return 'iOS 未放行网络访问，巨魔安装请在“设置-无线局域网/蜂窝网络”查找“铝模工作录”，或卸载后重装触发网络授权';
      }
      if (message.contains('SocketException') ||
          message.contains('Connection failed')) {
        return '网络连接失败：${message.ifEmpty(error.type.name)}';
      }
      if (message.contains('ATS') || message.contains('cleartext')) {
        return 'iOS 已拦截 HTTP 网络请求，请重新打包安装最新版';
      }
      return '网络异常：${message.ifEmpty(error.type.name)}';
    }
    return '网络异常，请稍后重试';
  }

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
                '安卓端注册',
                style: TextStyle(color: Color(0xFF6D7385), fontSize: 15),
              ),
              const SizedBox(height: 18),
              const _RegisterHint(),
              const SizedBox(height: 20),
              _AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AuthTextField(
                      controller: _usernameController,
                      hintText: '请输入真实姓名',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    _AuthTextField(
                      controller: _passwordController,
                      hintText: '请输入密码（至少6位）',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _loading ? null : _register(),
                    ),
                    const SizedBox(height: 18),
                    _AuthButton(
                      text: _loading ? '注册中...' : '注册',
                      backgroundColor: AppColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      onPressed: _loading ? null : _register,
                    ),
                    const SizedBox(height: 12),
                    _AuthButton(
                      text: '已有账号，去登录',
                      backgroundColor: const Color(0xFF8C7BD1),
                      onPressed: _loading ? null : () => context.go('/login'),
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

class _RegisterHint extends StatelessWidget {
  const _RegisterHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFFFFF6EB),
      child: const Text(
        '提示：注册账号时必须输入自己的真实姓名，否则无法注册成功。',
        style: TextStyle(color: Color(0xFF9A5B00), fontSize: 14),
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
