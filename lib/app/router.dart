import 'package:flutter/material.dart';

import '../features/auth/auth_gate.dart';

class AppRouter {
  static const home = '/';
  static const login = '/login';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(
          builder: (_) => const AuthGate(),
        );

      case login:
        return MaterialPageRoute(
          builder: (_) => const AuthGate(),
        );

      default:
        return MaterialPageRoute(
          builder: (_) => const AuthGate(),
        );
    }
  }
}