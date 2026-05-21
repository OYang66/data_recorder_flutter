import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/preferences.dart';
import '../../data/repositories/auth_repository.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _navigationStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_navigationStarted) {
        _navigationStarted = true;
        unawaited(_openNextPage());
      }
    });
  }

  Future<void> _openNextPage() async {
    final preferences = AppPreferences();
    await preferences.migrateLegacyPreferences();
    final disclaimerAgreed = await preferences.isDisclaimerAgreed();
    if (!disclaimerAgreed) {
      if (mounted) {
        context.go('/welcome');
      }
      return;
    }

    final loggedIn = await preferences.isLoggedIn();
    if (!loggedIn) {
      if (mounted) {
        context.go('/login');
      }
      return;
    }

    final username = await preferences.getUsername();
    try {
      final response = await AuthRepository(
        preferences: preferences,
      ).checkAccountStatus(username).timeout(const Duration(seconds: 3));
      if (!mounted) {
        return;
      }
      if (response.isSuccess && response.data?.valid != false) {
        context.go('/main');
      } else {
        await preferences.forceLogout(
          response.displayMessage.ifEmpty('账号状态异常，请重新登录'),
        );
        if (mounted) {
          context.go('/login');
        }
      }
    } catch (error) {
      if (mounted) {
        context.go('/main');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF4F6FB),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '铝模工作录',
              style: TextStyle(
                color: Color(0xFF222222),
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Text(
              '正在检查更新...',
              style: TextStyle(color: Color(0xFF666666), fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
