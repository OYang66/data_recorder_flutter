import 'package:flutter/widgets.dart';

class AppLifecycleObserver extends StatefulWidget {
  const AppLifecycleObserver({super.key, required this.child, this.onPause});

  final Widget child;
  final Future<void> Function()? onPause;

  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      widget.onPause?.call();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
