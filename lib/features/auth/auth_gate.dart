import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_type_page.dart';
import '../home/craftsman_home_page.dart';
import '../home/customer_home_page.dart';
import '../admin/admin_home_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  Widget? _home;

  @override
  void initState() { super.initState(); _resolve(); }

  Future<void> _resolve() async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      if (mounted) setState(() { _loading=false; _home=const AccountTypePage(); });
      return;
    }
    try {
      final uid = session.user.id;

      // الإدارة لها مسار مستقل داخل نفس التطبيق.
      final activeAdmin = await _supabase.rpc('is_active_admin');
      if (activeAdmin == true) {
        _home = const AdminHomePage();
      } else {
        final customer = await _supabase
            .from('customers')
            .select('id')
            .eq('user_id', uid)
            .maybeSingle();
        if (customer != null) {
          _home = const CustomerHomePage();
        } else {
          final tech = await _supabase
              .from('technicians')
              .select('id')
              .eq('user_id', uid)
              .maybeSingle();
          _home = tech != null ? const CraftsmanHomePage() : const AccountTypePage();
        }
      }
    } catch (_) {
      _home = const AccountTypePage();
    }
    if (mounted) setState(() => _loading=false);
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : _home ?? const AccountTypePage();
}
