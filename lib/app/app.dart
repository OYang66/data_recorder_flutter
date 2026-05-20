import 'dart:async';

import 'package:flutter/material.dart';

import '../core/storage/preferences.dart';
import '../features/delivery_order/delivery_order_intake_service.dart';
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
  StreamSubscription<ExternalDeliveryOrderFile>? _deliveryOrderSubscription;

  @override
  void initState() {
    super.initState();
    _logoutSubscription = AppPreferences.logoutEvents.listen((_) {
      appRouter.go('/login');
    });
    DeliveryOrderIntakeService.instance.initialize();
    _deliveryOrderSubscription = DeliveryOrderIntakeService.instance.files.listen((file) {
      appRouter.go('/delivery-order', extra: file);
    });
  }

  @override
  void dispose() {
    _logoutSubscription?.cancel();
    _deliveryOrderSubscription?.cancel();
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
