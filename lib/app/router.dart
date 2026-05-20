import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/delivery_order/delivery_order_page.dart';
import '../features/main/main_page.dart';
import '../features/settlement/settlement_data_page.dart';
import '../features/splash/splash_page.dart';
import '../features/update/update_page.dart';
import '../features/welcome/welcome_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashPage()),
    GoRoute(path: '/welcome', builder: (context, state) => const WelcomePage()),
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(path: '/update', builder: (context, state) => const UpdatePage()),
    GoRoute(
      path: '/delivery-order',
      builder: (context, state) => const DeliveryOrderPage(),
    ),
    GoRoute(
      path: '/settlement-data',
      builder: (context, state) => const SettlementDataPage(),
    ),
    GoRoute(path: '/main', builder: (context, state) => const MainPage()),
  ],
);
