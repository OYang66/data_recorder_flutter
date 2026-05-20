import 'dart:async';

import 'package:flutter/material.dart';

import '../core/storage/preferences.dart';
import 'lifecycle_observer.dart';
import 'router.dart';
import 'theme.dart';

class DataRecorderApp extends StatefulWidget {
  const DataRecorderApp({super.key});

  @override
  State<DataRecorderApp> createState() => _DataRecorderAppState();
}

class _DataRecorderAppState extends State<DataRecorderApp> {
  StreamSubscription<String>? _logoutSubscription;

  @override
  void initState() {
    super.initState();
    _logoutSubscription = AppPreferences.logoutEvents.listen((_) {
      appRouter.go('/login');
    });
  }

  @override
  void dispose() {
    _logoutSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLifecycleObserver(
      child: MaterialApp.router(
        title: '铝模板统计',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: appRouter,
      ),
    );
  }
}
