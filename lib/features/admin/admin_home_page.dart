import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/account_type_page.dart';

const _adminBlue = Color(0xFF087FD0);
const _adminDark = Color(0xFF073A68);
const _adminBg = Color(0xFFF5FAFD);
const _adminBorder = Color(0xFFDDEAF2);

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  int _section = 0;

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _technicians = [];
  List<Map<String, dynamic>> _technicianProfessions = [];
  List<Map<String, dynamic>> _professions = [];
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _commissionReport = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _supportConversations = [];
  List<Map<String, dynamic>> _pendingPaymentReviews = [];
  RealtimeChannel? _dashboardChannel;
  Timer? _dashboardRealtimeDebounce;
  bool _autoRefreshingDashboard = false;
  bool _dashboardLoadInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _subscribeToDashboardChanges();
  }

  void _subscribeToDashboardChanges() {
    // Event-driven refresh replaces the old 10-second polling timer.
    // A single channel and debounce combine bursts of related database events
    // into one dashboard reload without flashing the whole page.
    _dashboardChannel = _db.channel('admin-dashboard-realtime')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'order_technician_offers',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'technicians',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'technician_professions',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'customers',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'payments',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'inspection_settlements',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'order_technician_payouts',
        callback: (_) => _scheduleDashboardRealtimeRefresh(),
      )
      ..subscribe();
  }

  void _scheduleDashboardRealtimeRefresh() {
    if (!mounted) return;
    _dashboardRealtimeDebounce?.cancel();
    _dashboardRealtimeDebounce = Timer(
      const Duration(milliseconds: 500),
      () async {
        if (!mounted) return;
        if (_dashboardLoadInProgress) {
          _scheduleDashboardRealtimeRefresh();
          return;
        }
        _autoRefreshingDashboard = true;
        await _loadDashboard();
        _autoRefreshingDashboard = false;
      },
    );
  }

  @override
  void dispose() {
    _dashboardRealtimeDebounce?.cancel();
    final channel = _dashboardChannel;
    if (channel != null) _db.removeChannel(channel);
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    if (_dashboardLoadInProgress) return;
    _dashboardLoadInProgress = true;
    if (mounted && !_autoRefreshingDashboard) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final Future<dynamic> ordersFuture = _db.rpc(
        'admin_list_orders_v2',
        params: {
          'p_status': null,
          'p_offers_status': null,
          'p_limit': 100,
          'p_offset': 0,
        },
      );
      final Future<dynamic> techFuture = _db.rpc(
        'admin_list_technicians_for_control_v2',
      );
      final Future<dynamic> paymentsFuture = _db.rpc(
        'admin_list_confirmed_payments',
      );
      final Future<dynamic> pendingPaymentsFuture = _db.rpc(
        'admin_list_pending_payment_reviews',
      );
      final Future<dynamic> notificationsFuture = _db.rpc(
        'admin_list_notifications',
        params: {'p_limit': 100, 'p_offset': 0},
      );
      final Future<dynamic> supportFuture = _db.rpc(
        'admin_support_conversations',
        params: {'p_status': null},
      );
      final Future<dynamic> professionTechFuture = _db.rpc(
        'admin_list_profession_technicians',
      );

      final results = await Future.wait<dynamic>([
        ordersFuture,
        _safeTable('customers'),
        techFuture,
        professionTechFuture,
        _safeTable('professions'),
        _safeTable('services'),
        paymentsFuture,
        notificationsFuture,
        supportFuture,
        pendingPaymentsFuture,
      ]);

      _orders = _asMaps(results[0]);
      _customers = results[1];
      _technicians = _asMaps(results[2]).map((row) {
        final normalized = Map<String, dynamic>.from(row);
        normalized['id'] = row['technician_id'] ?? row['id'];
        return normalized;
      }).toList();
      _technicianProfessions = _asMaps(results[3]);
      _professions = results[4];
      _services = results[5];
      _payments = _asMaps(results[6]);
      _notifications = _asMaps(results[7]);
      _supportConversations = _asMaps(results[8]);
      _pendingPaymentReviews = _asMaps(results[9]);
      try {
        _commissionReport = _asMaps(
          await _db.rpc('admin_platform_commission_report'),
        );
      } catch (_) {
        // فشل التقرير المالي لا يمنع بقية لوحة الإدارة من العمل.
        _commissionReport = [];
      }

      // إذا كانت RLS تمنع القراءة المباشرة لجدول professions، نبني قائمة المهن
      // من مصدر الإدارة الموثوق admin_list_profession_technicians بدل اختراع بيانات.
      if (_professions.isEmpty && _technicianProfessions.isNotEmpty) {
        final byId = <String, Map<String, dynamic>>{};
        for (final row in _technicianProfessions) {
          final id = row['profession_id']?.toString();
          if (id == null || id.isEmpty) continue;
          byId.putIfAbsent(
            id,
            () => {
              'id': row['profession_id'],
              'name_ar': row['profession_name'] ?? 'مهنة #$id',
              'is_active': true,
            },
          );
        }
        _professions = byId.values.toList();
      }
    } catch (e) {
      _error = _clean(e);
    } finally {
      if (mounted) setState(() => _loading = false);
      _dashboardLoadInProgress = false;
    }
  }

  Future<List<Map<String, dynamic>>> _safeTable(String table) async {
    try {
      final result = await _db.from(table).select('*').limit(100);
      return _asMaps(result);
    } catch (_) {
      // عدم توفر صلاحية قراءة جدول جانبي لا يمنع لوحة الإدارة من العمل.
      return [];
    }
  }

  List<Map<String, dynamic>> _asMaps(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>?> _details(int orderId) async {
    try {
      final result = await _db.rpc(
        'admin_get_order_control',
        params: {'p_order_id': orderId},
      );
      return result is Map ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      if (mounted) _snack(_clean(e));
      return null;
    }
  }

  Future<void> _confirmFullPayment(int orderId) async {
    try {
      await _db.rpc(
        'admin_confirm_order_completion_payment',
        params: {
          'p_order_id': orderId,
          'p_admin_notes': 'تم تأكيد اكتمال الدفع من داخل تطبيق الإدارة.',
        },
      );
      await _loadDashboard();
      if (mounted) _snack('تم تأكيد اكتمال الدفع بنجاح.');
    } catch (e) {
      if (mounted) _snack(_clean(e));
    }
  }

  Future<void> _completeExternalLabor(int orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إنهاء طلب بمصنعية خارج التطبيق'),
          content: const Text(
            'سيتم اعتماد تسوية المعاينة وفق الاختيار المسجل للعميل والتحقق من بيانات الدفع. هل تريد اعتماد التسوية؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد الإنهاء'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.rpc(
        'admin_finalize_inspection_settlement',
        params: {
          'p_order_id': orderId,
          'p_admin_notes':
              'تم اعتماد تسوية خدمة المعاينة وفق الحالة المختارة من العميل.',
        },
      );
      await _loadDashboard();
      if (mounted) _snack('تم اعتماد تسوية خدمة المعاينة بنجاح.');
    } catch (e) {
      if (mounted) _snack(_clean(e));
    }
  }

  Future<void> _emergencyComplete(int orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنهاء الخدمة للطوارئ'),
        content: const Text(
          'هذا الإجراء مخصص فقط إذا نفذ الفني الخدمة ولم يتمكن من إنهائها من التطبيق بسبب مشكلة اتصال. هل تريد تأكيد الإنهاء؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد الإنهاء'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _db.rpc(
        'admin_complete_order_emergency',
        params: {
          'p_order_id': orderId,
          'p_admin_notes': 'تم إنهاء الخدمة بواسطة الإدارة كإجراء طوارئ.',
        },
      );
      await _loadDashboard();
      if (mounted) _snack('تم إنهاء الخدمة من الإدارة.');
    } catch (e) {
      if (mounted) _snack(_clean(e));
    }
  }

  Future<void> _openOrder(Map<String, dynamic> summary) async {
    final orderId = _toInt(summary['order_id']);
    if (orderId == null) return;
    final data = await _details(orderId);
    if (!mounted || data == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminOrderDetailsPage(
          initial: data,
          onChanged: _loadDashboard,
          onConfirmPayment: () => _confirmFullPayment(orderId),
          onEmergencyComplete: () => _emergencyComplete(orderId),
          onCompleteExternalLabor: () => _completeExternalLabor(orderId),
          onMarkPayoutPaid: () => _markTechnicianPayoutPaid(orderId),
        ),
      ),
    );
  }

  int? _toInt(dynamic value) => int.tryParse(value?.toString() ?? '');

  String _clean(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('FULL_PAYMENT_NOT_CONFIRMED')) {
      return 'لم يتم تأكيد سداد كامل المبلغ بعد.';
    }
    if (text.contains('ORDER_NOT_FOUND')) {
      return 'الطلب غير موجود أو لم يعد متاحًا.';
    }
    if (text.contains('ORDER_HAS_NO_SELECTED_TECHNICIAN')) {
      return 'لا يوجد فني أو عرض محدد لهذا الطلب.';
    }
    if (text.contains('ORDER_NOT_READY_FOR_COMPLETION_PAYMENT_CONFIRMATION')) {
      return 'الطلب غير جاهز لتأكيد اكتمال الدفع في الوقت الحالي.';
    }
    if (text.contains('ADMIN_ONLY')) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
    if (text.contains('PGRST116') ||
        text.contains('Cannot coerce the result to a single JSON object') ||
        text.contains('0 rows')) {
      return 'لم يتم العثور على البيانات المطلوبة. يرجى تحديث الصفحة والمحاولة مرة أخرى.';
    }
    if (text.contains('violates row-level security') ||
        text.contains('permission denied') ||
        text.contains('not authorized')) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
    if (text.startsWith('PostgrestException')) {
      final match = RegExp(
        r'message:\s*(.*?)(?:, code:|, details:|, hint:|\)$)',
      ).firstMatch(text);
      final databaseMessage = match?.group(1)?.trim();
      if (databaseMessage != null && databaseMessage.isNotEmpty) {
        return databaseMessage;
      }
      return 'تعذر تأكيد الدفع. حدّث بيانات الطلب وتحقق من تسجيل الدفعة قبل المحاولة مرة أخرى.';
    }
    return text.isEmpty ? 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.' : text;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _status(dynamic value) {
    switch (value?.toString()) {
      case 'pending':
        return 'جديد';
      case 'accepted':
        return 'تم القبول';
      case 'on_the_way':
        return 'في الطريق';
      case 'arrived':
        return 'وصل الفني';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'مكتمل';
      case 'cancelled':
        return 'ملغي';
      default:
        return value?.toString() ?? '—';
    }
  }

  Future<void> _logout() async {
    await _db.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountTypePage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _adminBg,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Row(
              textDirection: TextDirection.rtl,
              children: [
                if (wide) _desktopSidebar(),
                Expanded(child: _content(wide)),
              ],
            );
          },
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 900
            ? _mobileNavigation()
            : null,
      ),
    );
  }

  Widget _desktopSidebar() {
    final items = _sections();
    return Container(
      width: 235,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: _adminBorder)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _adminDark,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.build, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'صنايعي',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _adminDark,
                          ),
                        ),
                        Text(
                          'إدارة المنصة',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: items.length,
                itemBuilder: (_, i) => _navItem(items[i], i),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('تسجيل الخروج'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _sections() => const [
    {'title': 'الرئيسية', 'icon': Icons.dashboard_outlined},
    {'title': 'الطلبات', 'icon': Icons.receipt_long_outlined},
    {'title': 'العملاء', 'icon': Icons.person_outline},
    {'title': 'الفنيون', 'icon': Icons.engineering_outlined},
    {'title': 'المهن والخدمات', 'icon': Icons.handyman_outlined},
    {'title': 'المدفوعات', 'icon': Icons.payments_outlined},
    {'title': 'التقارير', 'icon': Icons.bar_chart_outlined},
    {'title': 'الإشعارات', 'icon': Icons.notifications_none},
    {'title': 'شات الفنيين', 'icon': Icons.chat_bubble_outline},
    {'title': 'إعدادات النظام', 'icon': Icons.settings_outlined},
  ];

  Widget _navItem(
    Map<String, dynamic> item,
    int index, {
    VoidCallback? afterTap,
  }) {
    final selected = _section == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        selected: selected,
        selectedTileColor: const Color(0xFFFFF1CF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          item['icon'] as IconData,
          color: selected ? const Color(0xFFB87800) : _adminDark,
        ),
        title: Text(
          item['title'] as String,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            color: _adminDark,
          ),
        ),
        onTap: () {
          setState(() => _section = index);
          afterTap?.call();
        },
      ),
    );
  }

  Widget _mobileNavigation() {
    final selected = _section.clamp(0, 4).toInt();
    return NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (index) => setState(() => _section = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          label: 'الرئيسية',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'الطلبات',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'العملاء',
        ),
        NavigationDestination(
          icon: Icon(Icons.engineering_outlined),
          label: 'الفنيون',
        ),
        NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد'),
      ],
    );
  }

  Widget _content(bool wide) {
    return SafeArea(
      child: Column(
        children: [
          _topBar(wide),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadDashboard,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        wide ? 28 : 16,
                        20,
                        wide ? 28 : 16,
                        30,
                      ),
                      children: [
                        if (_error != null) _errorCard(_error!),
                        _sectionBody(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(bool wide) {
    final user = _db.auth.currentUser;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _adminBorder)),
      ),
      child: Row(
        children: [
          if (!wide)
            IconButton(
              onPressed: () => _showMobileMenu(),
              icon: const Icon(Icons.menu),
            ),
          const Expanded(
            child: Text(
              'لوحة تحكم صنايعي',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: _adminDark,
              ),
            ),
          ),
          if (wide)
            Text(
              user?.email ?? 'حساب الإدارة',
              style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B)),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh),
            color: _adminBlue,
          ),
          IconButton(
            tooltip: 'خروج',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            color: _adminDark,
          ),
        ],
      ),
    );
  }

  void _showMobileMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 4; i < _sections().length; i++)
                _navItem(
                  _sections()[i],
                  i,
                  afterTap: () => Navigator.of(context).pop(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionBody() {
    switch (_section) {
      case 1:
        return _ordersSection();
      case 2:
        return _customersSection();
      case 3:
        return _techniciansSection();
      case 4:
        return _professionsSection();
      case 5:
        return _paymentsSection();
      case 6:
        return _reportsSection();
      case 7:
        return _notificationsSection();
      case 8:
        return _supportSection();
      case 9:
        return _settingsSection();
      default:
        return _dashboardSection();
    }
  }

  bool _isExternalLaborPending(Map<String, dynamic> order) {
    final status = order['status']?.toString();
    final paymentType = order['payment_type']?.toString();
    final paymentStatus = order['payment_status']?.toString();
    final technicianId = order['technician_id'];
    final inspection = order['requires_inspection'] == true;
    return inspection &&
        technicianId != null &&
        paymentType == 'inspection_fee' &&
        paymentStatus == 'paid' &&
        status != 'completed' &&
        status != 'cancelled';
  }

  Widget _dashboardSection() {
    final active = _orders.where(_isExternalLaborPending).length;
    final completed = _orders
        .where((o) => o['status']?.toString() == 'completed')
        .length;
    final waiting = _orders.where((o) {
      final s = o['status']?.toString();
      return s != 'completed' && s != 'cancelled';
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _welcomeHeader(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (_, c) {
            final columns = c.maxWidth >= 1000
                ? 4
                : c.maxWidth >= 650
                ? 2
                : 1;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _metric(
                  'إجمالي الطلبات',
                  _orders.length,
                  Icons.receipt_long_outlined,
                ),
                _metric('قيد التنفيذ', active, Icons.build_outlined),
                _metric('تحتاج متابعة', waiting, Icons.notifications_none),
                _metric('مكتملة', completed, Icons.verified_outlined),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _quickCard(
                'العملاء',
                _customers.length,
                Icons.person_outline,
                2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickCard(
                'الفنيون',
                _technicians.length,
                Icons.engineering_outlined,
                3,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickCard(
                'المهن',
                _professions.length,
                Icons.handyman_outlined,
                4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _panel(
          title: 'قيد التنفيذ — المصنعية لم تُحدد',
          icon: Icons.engineering_outlined,
          child: _orders.where(_isExternalLaborPending).isEmpty
              ? const Text(
                  'لا توجد حاليًا طلبات بانتظار تحديد/تسوية المصنعية خارج التطبيق.',
                )
              : Column(
                  children: _orders
                      .where(_isExternalLaborPending)
                      .take(8)
                      .map(_compactOrder)
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        _panel(
          title: 'أحدث الطلبات',
          icon: Icons.receipt_long_outlined,
          child: _orders.isEmpty
              ? const Text('لا توجد طلبات حالية.')
              : Column(children: _orders.take(8).map(_compactOrder).toList()),
        ),
      ],
    );
  }

  Widget _welcomeHeader() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF073A68), Color(0xFF087FD0)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'مرحبًا بك مجددًا 👋',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'تابع نشاط منصة صنايعي والطلبات والعملاء والفنيين من مكان واحد.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
      ],
    ),
  );

  Widget _metric(String title, int value, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _adminBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF7FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: _adminBlue),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 11, color: Color(0xFF607D8B)),
              ),
              const SizedBox(height: 2),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _adminDark,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _quickCard(String title, int count, IconData icon, int section) =>
      InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => setState(() => _section = section),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _adminBorder),
          ),
          child: Column(
            children: [
              Icon(icon, color: _adminBlue),
              const SizedBox(height: 5),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _adminDark,
                ),
              ),
              Text(
                title,
                style: const TextStyle(fontSize: 11, color: Color(0xFF607D8B)),
              ),
            ],
          ),
        ),
      );

  Widget _ordersSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _pageTitle('طلبات العملاء', Icons.receipt_long_outlined),
      const SizedBox(height: 12),
      if (_orders.isEmpty) _empty() else ..._orders.map(_orderCard),
    ],
  );

  Widget _orderCard(Map<String, dynamic> order) {
    final id = order['order_id'];
    final status = order['status'];
    final customer = order['customer_name']?.toString() ?? '—';
    final phone = order['customer_phone']?.toString() ?? '—';
    final total =
        order['service_total']?.toString() ??
        order['total_price']?.toString() ??
        '—';
    final paid = order['paid_amount']?.toString() ?? '0';
    final inspection = order['requires_inspection'] == true;
    final techName = order['technician_name']?.toString();
    final techPhone = order['technician_phone']?.toString();
    final techProfession = order['technician_profession']?.toString();
    final technician = order['technician_id']?.toString();

    return _panel(
      onTap: () => _openOrder(order),
      title: 'طلب #$id',
      icon: Icons.receipt_long_outlined,
      trailing: _statusChip(_status(status)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line('العميل', customer),
          _line('الهاتف', phone),
          _line(
            'الفني',
            techName?.isNotEmpty == true
                ? techName!
                : (technician ?? 'لم يتم اختيار فني'),
          ),
          if (techProfession?.isNotEmpty == true)
            _line('مهنة الفني', techProfession!),
          if (techPhone?.isNotEmpty == true) _line('هاتف الفني', techPhone!),
          if (inspection) _line('نوع الطلب', 'يحتاج معاينة'),
          _line('إجمالي الخدمة', total),
          _line('المدفوع فعليًا', '$paid جنيه'),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.chevron_left, color: _adminBlue),
          ),
        ],
      ),
    );
  }

  Widget _compactOrder(Map<String, dynamic> order) {
    final id = order['order_id'];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFEAF7FF),
        child: Text(
          '$id',
          style: const TextStyle(
            color: _adminBlue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      title: Text(
        order['customer_name']?.toString() ?? 'عميل',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(order['service_description']?.toString() ?? 'طلب خدمة'),
      trailing: _statusChip(_status(order['status'])),
      onTap: () => _openOrder(order),
    );
  }

  Widget _customersSection() {
    final rows = List<Map<String, dynamic>>.from(_customers)
      ..sort((a, b) {
        final aId = _toInt(a['id']) ?? 0;
        final bId = _toInt(b['id']) ?? 0;
        return aId.compareTo(bId);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageTitle('العملاء', Icons.person_outline),
        const SizedBox(height: 8),
        Text(
          'كل عميل له رقم ثابت داخل لوحة الإدارة لتسهيل المتابعة والرجوع للطلبات.',
          style: const TextStyle(color: Color(0xFF607D8B), height: 1.5),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          _emptyWithHint('لا توجد بيانات عملاء متاحة لحساب الإدارة.')
        else
          ...rows.asMap().entries.map(
            (entry) => _customerCard(entry.key + 1, entry.value),
          ),
      ],
    );
  }

  Widget _customerCard(int number, Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['full_name']?.toString().trim();
    final phone = row['phone']?.toString().trim();
    final status = row['account_status']?.toString().trim();
    final created = row['created_at']?.toString().trim();

    return _numberedCard(
      number: number,
      icon: Icons.person_outline,
      title: name?.isNotEmpty == true ? name! : 'عميل بدون اسم',
      subtitle: phone?.isNotEmpty == true ? phone! : 'الهاتف غير مسجل',
      trailing: _statusChip(status == 'blocked' ? 'محظور' : 'نشط'),
      children: [
        _detailItem('رقم العميل', id ?? '—'),
        _detailItem('حالة الحساب', status == 'blocked' ? 'محظور' : 'نشط'),
        _detailItem('تاريخ التسجيل', created ?? '—'),
      ],
    );
  }

  Widget _techniciansSection() {
    final rows = List<Map<String, dynamic>>.from(_technicians)
      ..sort((a, b) {
        final aId = _toInt(a['id']) ?? 0;
        final bId = _toInt(b['id']) ?? 0;
        return aId.compareTo(bId);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageTitle('الفنيون', Icons.engineering_outlined),
        const SizedBox(height: 8),
        Text(
          'عرض كل الفنيين الموجودين في قاعدة البيانات، بما في ذلك حالة التسجيل والتحقق والظهور للعملاء.',
          style: const TextStyle(color: Color(0xFF607D8B), height: 1.5),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          _emptyWithHint(
            'لا توجد بيانات فنيين ظاهرة لحساب الإدارة. إذا كان الفنيون موجودين في Supabase فراجع صلاحيات RLS الخاصة بجدول الفنيين.',
          )
        else
          ...rows.asMap().entries.map(
            (entry) => _technicianCard(entry.key + 1, entry.value),
          ),
      ],
    );
  }

  Widget _technicianCard(int number, Map<String, dynamic> row) {
    final application = row['application_status']?.toString() ?? '—';
    final account = row['account_status']?.toString() ?? '—';
    final verified = row['is_verified'] == true;
    final visible = row['is_visible'] == true;
    final available = row['is_available'] == true;

    String applicationText;
    switch (application) {
      case 'approved':
        applicationText = 'مقبول';
        break;
      case 'rejected':
        applicationText = 'مرفوض';
        break;
      default:
        applicationText = 'قيد المراجعة';
    }

    final technicianId = _toInt(row['technician_id'] ?? row['id']);
    final profileButton = technicianId == null
        ? null
        : TextButton.icon(
            onPressed: () => _showTechnicianProfile(technicianId),
            icon: const Icon(Icons.visibility_outlined, size: 17),
            label: const Text('عرض الملف'),
          );

    return _numberedCard(
      number: number,
      icon: Icons.engineering_outlined,
      title: row['full_name']?.toString() ?? 'فني بدون اسم',
      subtitle: row['phone']?.toString() ?? 'الهاتف غير مسجل',
      trailing: _statusChip(applicationText),
      children: [
        _detailItem('رقم الفني', technicianId ?? '—'),
        _detailItem(
          'المهنة الأساسية',
          row['profession_name'] ?? _professionName(row['profession_id']),
        ),
        _detailItem('الهاتف', row['phone'] ?? '—'),
        _detailItem('الواتساب', row['whatsapp_phone'] ?? '—'),
        _detailItem('التحقق', verified ? 'تم التحقق' : 'لم يتم التحقق'),
        _detailItem('حالة الحساب', _accountStatusText(account)),
        _detailItem('الظهور للعملاء', visible ? 'ظاهر' : 'مخفي'),
        _detailItem('التوافر', available ? 'متاح' : 'غير متاح'),
        if (profileButton != null) profileButton,
        if (technicianId != null) ...[
          TextButton.icon(
            onPressed: () => _showSupportChatForTechnician(technicianId),
            icon: const Icon(Icons.chat_bubble_outline, size: 17),
            label: const Text('الشات'),
          ),
          TextButton.icon(
            onPressed: () => _resetTechnicianPassword(
              technicianId,
              row['full_name']?.toString() ?? 'الفني',
            ),
            icon: const Icon(Icons.lock_reset_outlined, size: 17),
            label: const Text('إعادة كلمة المرور'),
          ),
          TextButton.icon(
            onPressed: () =>
                _technicianAction(technicianId, visible ? 'hide' : 'unhide'),
            icon: Icon(
              visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 17,
            ),
            label: Text(visible ? 'إخفاء' : 'إظهار'),
          ),
          TextButton.icon(
            onPressed: () => _technicianAction(
              technicianId,
              account == 'banned' ? 'unsuspend' : 'ban',
            ),
            icon: Icon(
              account == 'banned' ? Icons.lock_open : Icons.block,
              size: 17,
            ),
            label: Text(account == 'banned' ? 'رفع الحظر' : 'حظر'),
          ),
          TextButton.icon(
            onPressed: () => _technicianAction(
              technicianId,
              account == 'suspended' ? 'unsuspend' : 'suspend',
            ),
            icon: Icon(
              account == 'suspended'
                  ? Icons.play_circle_outline
                  : Icons.pause_circle_outline,
              size: 17,
            ),
            label: Text(account == 'suspended' ? 'رفع الإيقاف' : 'إيقاف'),
          ),
        ],
      ],
    );
  }

  Future<void> _technicianAction(int technicianId, String action) async {
    String reason = 'إجراء إداري من لوحة التحكم.';
    int? durationDays;

    if (action == 'suspend' || action == 'ban' || action == 'hide') {
      final controller = TextEditingController();
      final durationController = TextEditingController(
        text: action == 'suspend' ? '7' : '',
      );
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              action == 'suspend'
                  ? 'إيقاف الفني'
                  : action == 'ban'
                  ? 'حظر الفني'
                  : 'إخفاء الفني',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'السبب'),
                ),
                if (action == 'suspend')
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'مدة الإيقاف بالأيام',
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, {
                  'reason': controller.text.trim(),
                  'duration': int.tryParse(durationController.text.trim()),
                }),
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      );
      if (result == null) return;
      if ((result['reason']?.toString().trim() ?? '').isNotEmpty)
        reason = result['reason'].toString().trim();
      durationDays = result['duration'] as int?;
    }

    try {
      await _db.rpc(
        'admin_apply_technician_action',
        params: {
          'p_technician_id': technicianId,
          'p_action': action,
          'p_reason': reason,
          'p_notes': null,
          'p_duration_days': durationDays,
        },
      );
      await _loadDashboard();
      if (mounted) _snack('تم تنفيذ الإجراء الإداري بنجاح.');
    } catch (e) {
      if (mounted) _snack(_clean(e));
    }
  }

  Future<void> _markTechnicianPayoutPaid(int orderId) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد صرف مستحقات الفني'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'مرجع التحويل/الصرف (اختياري)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تم الصرف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      controller.dispose();
      return;
    }
    try {
      await _db.rpc(
        'admin_mark_technician_payout_paid',
        params: {
          'p_order_id': orderId,
          'p_payment_reference': controller.text.trim().isEmpty
              ? null
              : controller.text.trim(),
          'p_notes': 'تم تسجيل صرف مستحقات الفني من لوحة الإدارة.',
        },
      );
      if (mounted) _snack('تم تسجيل صرف مستحقات الفني.');
      controller.dispose();
    } catch (e) {
      controller.dispose();
      if (mounted) _snack(_clean(e));
    }
  }

  Future<void> _resetTechnicianPassword(
    int technicianId,
    String technicianName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعادة تعيين كلمة المرور'),
          content: Text(
            'سيتم إنشاء كلمة مرور مؤقتة جديدة للفني $technicianName، وسيُطلب منه تغييرها بعد الدخول. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إعادة التعيين'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await _db.functions.invoke(
        'set-technician-password',
        body: {'action': 'admin_reset', 'technician_id': technicianId},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (data['success'] != true) {
        throw Exception(
          data['error']?.toString() ?? 'تعذر إعادة تعيين كلمة المرور.',
        );
      }
      if (!mounted) return;
      final temp = data['temporary_password']?.toString() ?? '';
      await showDialog<void>(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تمت إعادة التعيين بنجاح'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('كلمة المرور المؤقتة للفني:'),
                const SizedBox(height: 10),
                SelectableText(
                  temp,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: _adminDark,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'احفظها وأرسلها للفني بشكل آمن. سيُطلب منه تغييرها بعد الدخول.',
                  style: TextStyle(color: Color(0xFF607D8B)),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: temp));
                  if (mounted) _snack('تم نسخ كلمة المرور المؤقتة.');
                },
                icon: const Icon(Icons.copy),
                label: const Text('نسخ'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('تم'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _snack(_clean(e));
    }
  }

  Future<void> _showSupportChatForTechnician(int technicianId) async {
    final existing = _supportConversations
        .where((c) => _toInt(c['technician_id']) == technicianId)
        .toList();
    if (existing.isNotEmpty) {
      await _openSupportChat(existing.first);
      return;
    }
    if (mounted)
      _snack(
        'لا توجد محادثة دعم مفتوحة لهذا الفني حاليًا. يمكنه بدء المحادثة من زر الدعم داخل التطبيق.',
      );
  }

  Future<void> _openSupportChat(Map<String, dynamic> conversation) async {
    final conversationId = _toInt(conversation['id']);
    if (conversationId == null) return;
    try {
      final result = await _db.rpc(
        'admin_support_messages_fast',
        params: {'p_conversation_id': conversationId},
      );
      final messages = _asMaps(result);
      if (!mounted) return;
      final controller = TextEditingController();
      await showDialog<void>(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              '${conversation['technician_name'] ?? 'الفني'} — شات الدعم',
            ),
            content: SizedBox(
              width: 620,
              height: 430,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'الهاتف: ${conversation['technician_phone'] ?? '—'}  •  ${conversation['subject'] ?? 'دعم'}',
                      style: const TextStyle(color: Color(0xFF607D8B)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: messages.isEmpty
                        ? const Center(child: Text('لا توجد رسائل بعد.'))
                        : ListView.builder(
                            itemCount: messages.length,
                            itemBuilder: (_, i) {
                              final m = messages[i];
                              final admin = m['sender_type'] == 'admin';
                              return Align(
                                alignment: admin
                                    ? Alignment.centerLeft
                                    : Alignment.centerRight,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 460,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: admin
                                        ? const Color(0xFFEAF7FF)
                                        : const Color(0xFFEAF9F0),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(m['body']?.toString() ?? ''),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالة للفني',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'إرسال',
                        onPressed: () async {
                          final body = controller.text.trim();
                          if (body.isEmpty) return;
                          try {
                            await _db.rpc(
                              'admin_support_send_message',
                              params: {
                                'p_conversation_id': conversationId,
                                'p_body': body,
                                'p_close': false,
                              },
                            );
                            controller.clear();
                            if (mounted) Navigator.pop(context);
                            await _loadDashboard();
                            if (mounted)
                              _openSupportChat(
                                _supportConversations.firstWhere(
                                  (c) => _toInt(c['id']) == conversationId,
                                  orElse: () => conversation,
                                ),
                              );
                          } catch (e) {
                            if (mounted) _snack(_clean(e));
                          }
                        },
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await _db.rpc(
                      'admin_support_set_status',
                      params: {
                        'p_conversation_id': conversationId,
                        'p_status': 'closed',
                        'p_priority': conversation['priority'],
                      },
                    );
                    if (mounted) Navigator.pop(context);
                    await _loadDashboard();
                  } catch (e) {
                    if (mounted) _snack(_clean(e));
                  }
                },
                child: const Text('إغلاق المحادثة'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      );
      controller.dispose();
    } catch (e) {
      if (mounted) _snack(_clean(e));
    }
  }

  Future<String?> _signedStorageUrl(String bucket, String? rawPath) async {
    final path = rawPath?.trim() ?? '';
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try {
      return await _db.storage.from(bucket).createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _loadTechnicianMedia(
    Map<String, dynamic> tech,
  ) async {
    final userId = tech['user_id']?.toString().trim() ?? '';
    String? profileUrl = await _signedStorageUrl(
      'technician-documents',
      tech['profile_image']?.toString(),
    );
    String? nationalIdUrl = await _signedStorageUrl(
      'technician-documents',
      tech['national_id_image']?.toString(),
    );
    final workUrls = <String>[];

    if (userId.isNotEmpty) {
      try {
        final objects = await _db.storage
            .from('technician-documents')
            .list(path: userId);
        final names = objects
            .map((object) => object.name)
            .where((name) => name.trim().isNotEmpty)
            .toList();

        // بعض السجلات القديمة لا تحتوي على profile_image/national_id_image
        // رغم أن الملفات موجودة فعليًا داخل مجلد الفني.
        profileUrl ??= await _signedStorageUrl(
          'technician-documents',
          names.any((name) => name.startsWith('profile_'))
              ? '$userId/${names.firstWhere((name) => name.startsWith('profile_'))}'
              : null,
        );
        nationalIdUrl ??= await _signedStorageUrl(
          'technician-documents',
          names.any((name) => name.startsWith('national_id_'))
              ? '$userId/${names.firstWhere((name) => name.startsWith('national_id_'))}'
              : null,
        );

        for (final name in names.where((name) => name.startsWith('work_'))) {
          final url = await _signedStorageUrl(
            'technician-documents',
            '$userId/$name',
          );
          if (url != null) workUrls.add(url);
        }
      } catch (_) {
        // إذا كانت صلاحية listing غير متاحة، نظهر فقط الملفات المعروفة من بيانات الفني.
      }
    }

    return {
      'profile': profileUrl,
      'national_id': nationalIdUrl,
      'works': workUrls,
    };
  }

  Widget _mediaCard({
    required String title,
    required String? url,
    required IconData icon,
    String emptyText = 'غير متاحة',
    VoidCallback? onTap,
  }) {
    if (url == null || url.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FCFE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _adminBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF78909C)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '$title: $emptyText',
                style: const TextStyle(color: Color(0xFF607D8B)),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            color: _adminBg,
            border: Border.all(color: _adminBorder),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(icon, size: 42, color: const Color(0xFF78909C)),
                ),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMediaImage(String title, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(18),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(child: Image.network(url, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTechnicianProfile(int technicianId) async {
    try {
      final result = await _db.rpc(
        'admin_get_technician_profile',
        params: {'p_technician_id': technicianId},
      );
      if (!mounted || result is! Map) return;
      final data = Map<String, dynamic>.from(result);
      final tech = Map<String, dynamic>.from(
        (data['technician'] as Map?) ?? const {},
      );
      final professions = (data['professions'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final areas = (data['areas'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final media = await _loadTechnicianMedia(tech);
      if (!mounted) return;

      final profileUrl = media['profile']?.toString();
      final nationalIdUrl = media['national_id']?.toString();
      final workUrls = (media['works'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();

      showDialog<void>(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(
              tech['full_name']?.toString() ?? 'ملف الفني',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _line('الهاتف', tech['phone']),
                    _line('هاتف إضافي', tech['phone2']),
                    _line('واتساب', tech['whatsapp_phone']),
                    _line(
                      'المهنة',
                      professions.map((e) => e['name_ar']).join('، '),
                    ),
                    _line('المدينة', tech['city_name_ar']),
                    _line(
                      'الظهور',
                      tech['is_visible'] == true ? 'ظاهر للعملاء' : 'مخفي',
                    ),
                    _line(
                      'حالة الحساب',
                      _accountStatusText(
                        tech['account_status']?.toString() ?? '—',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'صور الفني',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _adminDark,
                      ),
                    ),
                    const SizedBox(height: 9),
                    _mediaCard(
                      title: 'الصورة الشخصية',
                      url: profileUrl,
                      icon: Icons.person_outline,
                      onTap: profileUrl == null
                          ? null
                          : () => _showMediaImage('الصورة الشخصية', profileUrl),
                    ),
                    const SizedBox(height: 10),
                    _mediaCard(
                      title: 'صورة البطاقة القومية',
                      url: nationalIdUrl,
                      icon: Icons.badge_outlined,
                      onTap: nationalIdUrl == null
                          ? null
                          : () => _showMediaImage(
                              'صورة البطاقة القومية',
                              nationalIdUrl,
                            ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'المناطق: ${areas.map((e) => e['name_ar']).join('، ')}',
                      style: const TextStyle(color: Color(0xFF607D8B)),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'صور أعمال الفني',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _adminDark,
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (workUrls.isEmpty)
                      const Text(
                        'لا توجد صور أعمال مرفوعة لهذا الفني حاليًا.',
                        style: TextStyle(color: Color(0xFF607D8B)),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: workUrls.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                        itemBuilder: (_, index) {
                          final url = workUrls[index];
                          return _mediaCard(
                            title: 'عمل ${index + 1}',
                            url: url,
                            icon: Icons.photo_library_outlined,
                            onTap: () =>
                                _showMediaImage('صورة عمل ${index + 1}', url),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showSupportChatForTechnician(technicianId);
                },
                child: const Text('شات الفني'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _resetTechnicianPassword(
                    technicianId,
                    tech['full_name']?.toString() ?? 'الفني',
                  );
                },
                child: const Text('إعادة تعيين كلمة المرور'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _snack(_clean(e));
    }
  }

  String _accountStatusText(String value) {
    switch (value) {
      case 'active':
        return 'نشط';
      case 'suspended':
        return 'موقوف';
      case 'banned':
        return 'محظور';
      case 'deactivated':
        return 'غير مفعل';
      default:
        return value == '—' ? '—' : value;
    }
  }

  String _professionName(dynamic professionId) {
    if (professionId == null) return 'غير محددة';

    for (final profession in _professions) {
      if (profession['id'].toString() == professionId.toString()) {
        final name = profession['name_ar']?.toString().trim();
        if (name?.isNotEmpty == true) return name!;
      }
    }

    return 'مهنة #$professionId';
  }

  Widget _professionsSection() {
    final professions = List<Map<String, dynamic>>.from(_professions)
      ..sort((a, b) {
        final aOrder = _toInt(a['sort_order']) ?? 0;
        final bOrder = _toInt(b['sort_order']) ?? 0;
        return aOrder.compareTo(bOrder);
      });

    final professionIds = <dynamic>{};
    for (final technician in _technicians) {
      if (technician['profession_id'] != null) {
        professionIds.add(technician['profession_id']);
      }
    }
    for (final row in _technicianProfessions) {
      if (row['profession_id'] != null) professionIds.add(row['profession_id']);
    }

    final cards = <Map<String, dynamic>>[...professions];

    // لو المهنة موجودة على الفنيين لكن جدول professions لا يعيدها،
    // نظهرها بدل اختفائها من لوحة الإدارة.
    for (final id in professionIds) {
      final exists = cards.any((p) => p['id'].toString() == id.toString());
      if (!exists) {
        cards.add({'id': id, 'name_ar': 'مهنة #$id', 'is_active': true});
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageTitle('المهن والخدمات', Icons.handyman_outlined),
        const SizedBox(height: 8),
        const Text(
          'كل مهنة في بطاقة مستقلة، مع عدد الفنيين المرتبطين بها. اضغط على أي مهنة لعرض الفنيين وتفاصيل الخدمات المتاحة من البيانات الحالية.',
          style: TextStyle(color: Color(0xFF607D8B), height: 1.5),
        ),
        const SizedBox(height: 14),
        if (cards.isEmpty)
          _emptyWithHint(
            'لا توجد مهن مسجلة حاليًا في جدول professions. لا يمكن إنشاء أسماء مهن أو خدمات من عندنا بدون بيانات قاعدة البيانات.',
          )
        else
          LayoutBuilder(
            builder: (_, constraints) {
              final columns = constraints.maxWidth >= 1100
                  ? 4
                  : constraints.maxWidth >= 760
                  ? 3
                  : constraints.maxWidth >= 480
                  ? 2
                  : 1;

              return GridView.builder(
                itemCount: cards.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                itemBuilder: (_, index) {
                  final profession = cards[index];
                  return _professionCard(profession);
                },
              );
            },
          ),
        const SizedBox(height: 18),
        _servicesOverview(),
      ],
    );
  }

  int _technicianCountForProfession(dynamic professionId) {
    final ids = <String>{};

    for (final row in _technicianProfessions) {
      if (row['profession_id']?.toString() == professionId?.toString() &&
          row['technician_id'] != null) {
        ids.add(row['technician_id'].toString());
      }
    }

    // دعم profession_id القديم/الأساسي في جدول technicians.
    for (final technician in _technicians) {
      if (technician['profession_id']?.toString() == professionId?.toString() &&
          technician['id'] != null) {
        ids.add(technician['id'].toString());
      }
    }

    return ids.length;
  }

  List<Map<String, dynamic>> _techniciansForProfession(dynamic professionId) {
    final ids = <String>{};

    for (final row in _technicianProfessions) {
      if (row['profession_id']?.toString() == professionId?.toString() &&
          row['technician_id'] != null) {
        ids.add(row['technician_id'].toString());
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final technician in _technicians) {
      final id = technician['id']?.toString();
      if (id != null &&
          (ids.contains(id) ||
              technician['profession_id']?.toString() ==
                  professionId?.toString())) {
        result.add(technician);
      }
    }

    return result;
  }

  Widget _professionCard(Map<String, dynamic> profession) {
    final id = profession['id'];
    final name = profession['name_ar']?.toString().trim();
    final count = _technicianCountForProfession(id);

    return InkWell(
      onTap: () => _showProfessionDetails(profession),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _adminBorder),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 5),
              color: Color(0x0C073A68),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7FF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.handyman_outlined, color: _adminBlue),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F7FB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count فني',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: _adminDark,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              name?.isNotEmpty == true ? name! : 'مهنة #$id',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: _adminDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'عرض الفنيين والتفاصيل',
              style: TextStyle(fontSize: 11, color: Color(0xFF607D8B)),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 14,
                color: _adminBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _servicesOverview() {
    if (_services.isEmpty) {
      return _panel(
        title: 'الخدمات',
        icon: Icons.build_circle_outlined,
        child: const Text(
          'لا توجد حاليًا بيانات خدمات في قاعدة البيانات الحالية. تم تجهيز واجهة الخدمات لتظهر تلقائيًا عند إضافة مصدر الخدمات، ولن يتم اختراع أسماء خدمات غير موجودة في Supabase.',
          style: TextStyle(color: Color(0xFF607D8B), height: 1.5),
        ),
      );
    }

    return _panel(
      title: 'الخدمات',
      icon: Icons.build_circle_outlined,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 600
              ? 3
              : 2;

          return GridView.builder(
            itemCount: _services.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.4,
            ),
            itemBuilder: (_, index) {
              final service = _services[index];
              final name =
                  service['name_ar'] ??
                  service['service_name'] ??
                  service['name'] ??
                  'خدمة';
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _adminBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.build_outlined, color: _adminBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name.toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showProfessionDetails(Map<String, dynamic> profession) {
    final id = profession['id'];
    final name = profession['name_ar']?.toString() ?? 'المهنة';
    final technicians = _techniciansForProfession(id);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _adminDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${technicians.length} فني مرتبط بهذه المهنة',
                      style: const TextStyle(color: Color(0xFF607D8B)),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: technicians.isEmpty
                          ? _emptyWithHint('لا يوجد فنيون مرتبطون بهذه المهنة.')
                          : ListView.separated(
                              itemCount: technicians.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, index) {
                                final tech = technicians[index];
                                return _technicianMiniCard(tech, index + 1);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _technicianMiniCard(Map<String, dynamic> tech, int number) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _adminBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFEAF7FF),
            child: Text(
              '$number',
              style: const TextStyle(
                color: _adminBlue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tech['full_name']?.toString() ?? 'فني',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _adminDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  tech['phone']?.toString() ?? 'الهاتف غير مسجل',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF607D8B),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _smallTag(
                      tech['is_verified'] == true ? 'موثق' : 'غير موثق',
                      tech['is_verified'] == true,
                    ),
                    _smallTag(
                      tech['is_visible'] == true ? 'ظاهر' : 'مخفي',
                      tech['is_visible'] == true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallTag(String text, bool positive) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: positive ? const Color(0xFFEAF9F0) : const Color(0xFFFFF2F2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: positive ? const Color(0xFF238B4E) : Colors.red.shade700,
      ),
    ),
  );

  Widget _numberedCard({
    required int number,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _adminBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '#$number',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: _adminBlue,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F7FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _adminBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _adminDark,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing,
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF607D8B),
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(spacing: 18, runSpacing: 7, children: children),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailItem(String label, dynamic value) => RichText(
    text: TextSpan(
      style: const TextStyle(fontSize: 11, color: Color(0xFF263238)),
      children: [
        TextSpan(
          text: '$label: ',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _adminDark,
          ),
        ),
        TextSpan(text: value?.toString() ?? '—'),
      ],
    ),
  );

  Widget _paymentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageTitle('المدفوعات', Icons.payments_outlined),
        const SizedBox(height: 12),
        if (_pendingPaymentReviews.isNotEmpty)
          _panel(
            title: 'مدفوعات تحتاج مراجعة وتأكيد الإدارة',
            icon: Icons.pending_actions_outlined,
            child: Column(
              children: _pendingPaymentReviews
                  .map((p) => _pendingPaymentRow(p))
                  .toList(),
            ),
          ),
        _panel(
          title: 'المدفوعات المؤكدة',
          icon: Icons.verified_outlined,
          child: _payments.isEmpty
              ? const Text('لا توجد مدفوعات مؤكدة حاليًا.')
              : Column(children: _payments.map(_paymentRow).toList()),
        ),
      ],
    );
  }

  Widget _pendingPaymentRow(Map<String, dynamic> row) {
    final orderId = _toInt(row['order_id']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE2A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB87800)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'طلب #${orderId ?? '—'} • ${row['customer_name'] ?? 'عميل'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _adminDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'العميل دفع: ${row['amount'] ?? 0} جنيه • ${row['payment_method'] ?? '—'} • ${row['payment_type'] ?? '—'}',
                  style: const TextStyle(color: Color(0xFF607D8B)),
                ),
                Text(
                  'رقم عملية الدفع: ${row['payment_id'] ?? '—'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF607D8B),
                  ),
                ),
              ],
            ),
          ),
          if (orderId != null)
            ElevatedButton(
              onPressed: () => _openOrder({'order_id': orderId}),
              child: const Text('مراجعة وتأكيد'),
            ),
        ],
      ),
    );
  }

  Widget _paymentRow(Map<String, dynamic> row) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEAF1F5))),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          _detailItem('طلب', row['order_id'] ?? '—'),
          _detailItem('العميل', row['customer_name'] ?? '—'),
          _detailItem('المبلغ المدفوع', '${row['amount'] ?? 0} جنيه'),
          _detailItem('النوع', row['payment_type'] ?? '—'),
          _detailItem('الطريقة', row['payment_method'] ?? '—'),
          _detailItem('الفني', row['technician_name'] ?? '—'),
          _detailItem('مهنة الفني', row['profession_name'] ?? '—'),
          _detailItem('هاتف الفني', row['technician_phone'] ?? '—'),
        ],
      ),
    );
  }

  Widget _notificationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageTitle('الإشعارات', Icons.notifications_none),
        const SizedBox(height: 12),
        if (_notifications.isEmpty)
          _emptyWithHint('لا توجد إشعارات حاليًا.')
        else
          ..._notifications.map((n) => _notificationCard(n)),
      ],
    );
  }

  Widget _notificationCard(Map<String, dynamic> n) {
    final title = n['title']?.toString().trim();
    final body = n['body']?.toString().trim();
    return _panel(
      title: title?.isNotEmpty == true ? title! : 'إشعار',
      icon: n['is_read'] == true
          ? Icons.notifications_none
          : Icons.notifications_active_outlined,
      trailing: n['is_read'] == true
          ? _statusChip('مقروء')
          : _statusChip('جديد'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (body?.isNotEmpty == true)
            Text(body!, style: const TextStyle(height: 1.45)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _detailItem('العميل', n['customer_name'] ?? '—'),
              _detailItem('هاتف العميل', n['customer_phone'] ?? '—'),
              _detailItem('الفني', n['technician_name'] ?? '—'),
              _detailItem('مهنة الفني', n['technician_profession'] ?? '—'),
              _detailItem('هاتف الفني', n['technician_phone'] ?? '—'),
              _detailItem('المبلغ', n['payment_amount'] ?? '—'),
              _detailItem('نوع الدفع', n['payment_type'] ?? '—'),
              _detailItem('حالة الدفع', n['payment_status'] ?? '—'),
              _detailItem('طلب', n['order_id'] ?? '—'),
              _detailItem('التاريخ', n['created_at'] ?? '—'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _supportSection() {
    final conversations = List<Map<String, dynamic>>.from(
      _supportConversations,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageTitle('شات الفنيين', Icons.chat_bubble_outline),
        const SizedBox(height: 8),
        const Text(
          'محادثات مباشرة بين الإدارة والفنيين، مع اسم الفني ورقم هاتفه وحالة المحادثة والرسائل غير المقروءة.',
          style: TextStyle(color: Color(0xFF607D8B), height: 1.5),
        ),
        const SizedBox(height: 14),
        if (conversations.isEmpty)
          _emptyWithHint('لا توجد محادثات دعم مفتوحة حاليًا.')
        else
          ...conversations.map((c) => _supportConversationCard(c)),
      ],
    );
  }

  Widget _supportConversationCard(Map<String, dynamic> c) {
    final unread = _toInt(c['unread_count']) ?? 0;
    return _panel(
      onTap: () => _openSupportChat(c),
      title: c['technician_name']?.toString() ?? 'فني',
      icon: Icons.chat_bubble_outline,
      trailing: unread > 0
          ? _statusChip('$unread جديد')
          : _statusChip(c['status']?.toString() ?? '—'),
      child: Wrap(
        spacing: 18,
        runSpacing: 7,
        children: [
          _detailItem('الهاتف', c['technician_phone'] ?? '—'),
          _detailItem('الموضوع', c['subject'] ?? '—'),
          _detailItem('التصنيف', c['category'] ?? '—'),
          _detailItem('الأولوية', c['priority'] ?? '—'),
          _detailItem('آخر تحديث', c['updated_at'] ?? '—'),
          const Text(
            'اضغط لفتح المحادثة والرد',
            style: TextStyle(color: _adminBlue, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  double _reportAmount(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  String _egp(dynamic value) =>
      '${_reportAmount(value).toStringAsFixed(2)} جنيه';

  Widget _reportsSection() {
    final completed = _orders
        .where((o) => o['status']?.toString() == 'completed')
        .length;
    final cancelled = _orders
        .where((o) => o['status']?.toString() == 'cancelled')
        .length;
    final active = _orders.length - completed - cancelled;
    final eligibleRows = _commissionReport.where((row) {
      return row['order_status']?.toString() == 'completed' &&
          row['payment_status']?.toString() == 'paid';
    }).toList();
    final totalCustomerCommission = eligibleRows.fold<double>(
      0,
      (sum, row) => sum + _reportAmount(row['customer_commission']),
    );
    final totalTechnicianCommission = eligibleRows.fold<double>(
      0,
      (sum, row) => sum + _reportAmount(row['technician_commission']),
    );
    final totalPlatformCommission = eligibleRows.fold<double>(
      0,
      (sum, row) => sum + _reportAmount(row['platform_commission']),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageTitle('التقارير', Icons.bar_chart_outlined),
        const SizedBox(height: 12),
        _panel(
          title: 'ملخص الأداء الحالي',
          icon: Icons.insights_outlined,
          child: Column(
            children: [
              _reportLine('إجمالي الطلبات', _orders.length),
              _reportLine('قيد المتابعة / التنفيذ', active),
              _reportLine('طلبات مكتملة', completed),
              _reportLine('طلبات ملغاة', cancelled),
              _reportLine('العملاء المسجلون', _customers.length),
              _reportLine('الفنيون المسجلون', _technicians.length),
            ],
          ),
        ),
        _panel(
          title: 'دخل المنصة من العمولات',
          icon: Icons.account_balance_wallet_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _moneyReportLine(
                'عمولة المنصة من العملاء',
                totalCustomerCommission,
              ),
              _moneyReportLine(
                'عمولة المنصة من الفنيين',
                totalTechnicianCommission,
              ),
              const Divider(height: 22),
              _moneyReportLine(
                'إجمالي عمولات المنصة',
                totalPlatformCommission,
                emphasize: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'يُحتسب التقرير للطلبات المكتملة التي حالتها مدفوعة، ويجمع عمولة العميل وعمولة الفني المسجلتين على الطلب. هذا تقرير عمولات مسجلة وليس إثباتًا مستقلًا للتحويل البنكي.',
                style: TextStyle(
                  color: Color(0xFF607D8B),
                  height: 1.45,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        _panel(
          title: 'عمولة كل طلب',
          icon: Icons.receipt_long_outlined,
          trailing: _statusChip('${_commissionReport.length} طلب'),
          child: _commissionReport.isEmpty
              ? const Text(
                  'لا توجد بيانات للتقرير حاليًا أو تعذر تحميلها. حدّث الصفحة وحاول مرة أخرى.',
                  style: TextStyle(color: Color(0xFF607D8B)),
                )
              : Column(
                  children: _commissionReport.map((row) {
                    final eligible =
                        row['order_status']?.toString() == 'completed' &&
                        row['payment_status']?.toString() == 'paid';
                    final orderId = row['order_id']?.toString() ?? '—';
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _adminBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'طلب #$orderId — ${row['customer_name'] ?? 'عميل'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: _adminDark,
                                  ),
                                ),
                              ),
                              Text(
                                _egp(row['platform_commission']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: _adminBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          _line('الفني', row['technician_name'] ?? '—'),
                          _line('قيمة الخدمة', _egp(row['service_total'])),
                          _line(
                            'عمولة العميل',
                            _egp(row['customer_commission']),
                          ),
                          _line(
                            'عمولة الفني',
                            _egp(row['technician_commission']),
                          ),
                          _line('حالة الطلب', row['order_status'] ?? '—'),
                          _line('حالة الدفع', row['payment_status'] ?? '—'),
                          if (!eligible)
                            const Text(
                              'العمولة غير محسوبة ضمن الإجمالي حتى يكتمل الطلب ويُعتمد مدفوعًا.',
                              style: TextStyle(
                                color: Color(0xFF8A6D3B),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _moneyReportLine(
    String label,
    double value, {
    bool emphasize = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
              color: emphasize ? _adminDark : null,
            ),
          ),
        ),
        Text(
          _egp(value),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: emphasize ? 18 : 14,
            color: emphasize ? const Color(0xFF12805C) : _adminBlue,
          ),
        ),
      ],
    ),
  );

  Widget _settingsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _pageTitle('إعدادات النظام', Icons.settings_outlined),
      const SizedBox(height: 12),
      _panel(
        title: 'حساب الإدارة',
        icon: Icons.admin_panel_settings_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _line('البريد', _db.auth.currentUser?.email ?? '—'),
            const SizedBox(height: 8),
            const Text(
              'صلاحيات الإدارة يتم التحقق منها من Supabase قبل فتح لوحة التحكم.',
              style: TextStyle(color: Color(0xFF607D8B), height: 1.5),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _pageTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, color: _adminBlue),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w900,
          color: _adminDark,
        ),
      ),
    ],
  );

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _adminBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: _adminBlue, size: 21),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: _adminDark,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(17),
              child: content,
            ),
    );
  }

  Widget _line(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF607D8B),
            ),
          ),
        ),
        Expanded(child: Text(value?.toString() ?? '—')),
      ],
    ),
  );

  Widget _reportLine(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          '$value',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: _adminBlue,
          ),
        ),
      ],
    ),
  );

  Widget _statusChip(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF7FF),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: _adminDark,
      ),
    ),
  );

  Widget _errorCard(String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.red.shade700),
    ),
  );

  Widget _empty() => const Padding(
    padding: EdgeInsets.all(35),
    child: Text('لا توجد طلبات حالية.', textAlign: TextAlign.center),
  );

  Widget _emptyWithHint(String text) => Padding(
    padding: const EdgeInsets.all(20),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF607D8B)),
    ),
  );
}

class AdminOrderDetailsPage extends StatefulWidget {
  const AdminOrderDetailsPage({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.onConfirmPayment,
    required this.onEmergencyComplete,
    required this.onCompleteExternalLabor,
    required this.onMarkPayoutPaid,
  });

  final Map<String, dynamic> initial;
  final Future<void> Function() onChanged;
  final Future<void> Function() onConfirmPayment;
  final Future<void> Function() onEmergencyComplete;
  final Future<void> Function() onCompleteExternalLabor;
  final Future<void> Function() onMarkPayoutPaid;

  @override
  State<AdminOrderDetailsPage> createState() => _AdminOrderDetailsPageState();
}

class _AdminOrderDetailsPageState extends State<AdminOrderDetailsPage> {
  late Map<String, dynamic> _data;
  bool _loading = false;
  bool _loadingMedia = false;
  List<String> _resolvedOrderAttachments = [];
  Map<String, dynamic>? _inspectionSettlement;
  RealtimeChannel? _orderDetailsChannel;
  Timer? _orderDetailsRealtimeDebounce;
  bool _detailsRefreshInProgress = false;

  final _db = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.initial);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadOrderMedia();
      await _loadInspectionSettlement();
      _subscribeToOrderDetailsChanges();
    });
  }

  void _subscribeToOrderDetailsChanges() {
    final orderId = int.tryParse(_order['id']?.toString() ?? '');
    if (orderId == null) return;
    _orderDetailsChannel = _db.channel('admin-order-details-$orderId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: orderId,
        ),
        callback: (_) => _scheduleOrderDetailsRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'inspection_settlements',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'order_id',
          value: orderId,
        ),
        callback: (_) => _scheduleOrderDetailsRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'order_technician_payouts',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'order_id',
          value: orderId,
        ),
        callback: (_) => _scheduleOrderDetailsRealtimeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'payments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'order_id',
          value: orderId,
        ),
        callback: (_) => _scheduleOrderDetailsRealtimeRefresh(),
      )
      ..subscribe();
  }

  void _scheduleOrderDetailsRealtimeRefresh() {
    if (!mounted) return;
    _orderDetailsRealtimeDebounce?.cancel();
    _orderDetailsRealtimeDebounce = Timer(
      const Duration(milliseconds: 400),
      () async {
        if (!mounted || _detailsRefreshInProgress) return;
        _detailsRefreshInProgress = true;
        try {
          await _refresh();
        } finally {
          _detailsRefreshInProgress = false;
        }
      },
    );
  }

  @override
  void dispose() {
    _orderDetailsRealtimeDebounce?.cancel();
    final channel = _orderDetailsChannel;
    if (channel != null) _db.removeChannel(channel);
    super.dispose();
  }

  Map<String, dynamic> get _order =>
      Map<String, dynamic>.from((_data['order'] as Map?) ?? const {});
  Map<String, dynamic> get _paymentSummary =>
      Map<String, dynamic>.from((_data['payment_summary'] as Map?) ?? const {});
  Map<String, dynamic> get _technician =>
      Map<String, dynamic>.from((_data['technician'] as Map?) ?? const {});
  Map<String, dynamic> get _technicianPayout => Map<String, dynamic>.from(
    (_data['technician_payout'] as Map?) ?? const {},
  );

  List<String> get _rawOrderAttachments {
    final raw = _data['attachments'] ?? _order['attachments'];
    if (raw is! List) return const [];
    final unique = <String>{};
    for (final item in raw) {
      final value = item is Map
          ? ((item['url'] ?? item['image_url'] ?? item['path'] ?? '')
                .toString())
          : item.toString();
      final clean = value.trim();
      if (clean.isNotEmpty) unique.add(clean);
    }
    return unique.toList();
  }

  Widget _adminAddressDetails() {
    final raw = (_order['address'] ?? _order['full_address'] ?? '')
        .toString()
        .trim();
    final parts = raw
        .split(RegExp(r'\s*(?:—|–|-)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    String part(int index) => parts.length > index ? parts[index] : 'غير محدد';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'عنوان العميل بالتفصيل',
            style: TextStyle(fontWeight: FontWeight.w900, color: _adminDark),
          ),
        ),
        _line('الحي', part(0)),
        _line('الشارع', part(1)),
        _line('العمارة أو البلوك', part(2)),
        _line('الدور', part(3)),
        _line(
          'الشقة',
          parts.length > 4 ? parts.sublist(4).join(' — ') : 'غير محدد',
        ),
      ],
    );
  }

  Future<String?> _signedOrderAttachmentUrl(String rawPath) async {
    final path = rawPath.trim();
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try {
      return await _db.storage
          .from('customer-order-attachments')
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadInspectionSettlement() async {
    final id = int.tryParse(_order['id']?.toString() ?? '');
    final hasInspectionFlow =
        _order['requires_inspection'] == true ||
        _order['inspection_settlement_mode'] != null ||
        _order['inspection_labor_price'] != null;
    if (id == null || !hasInspectionFlow) {
      if (mounted) setState(() => _inspectionSettlement = null);
      return;
    }
    try {
      final row = await _db
          .from('inspection_settlements')
          .select('*')
          .eq('order_id', id)
          .maybeSingle();
      if (mounted)
        setState(
          () => _inspectionSettlement = row == null
              ? null
              : Map<String, dynamic>.from(row),
        );
    } catch (_) {}
  }

  Future<void> _loadOrderMedia() async {
    final raw = _rawOrderAttachments;
    if (raw.isEmpty) {
      if (mounted) setState(() => _resolvedOrderAttachments = []);
      return;
    }
    if (mounted) setState(() => _loadingMedia = true);
    try {
      final urls = <String>[];
      final seen = <String>{};
      for (final path in raw) {
        final url = await _signedOrderAttachmentUrl(path);
        if (url == null) continue;
        final uri = Uri.tryParse(url);
        var key = uri?.path ?? url;
        const bucketMarker = '/customer-order-attachments/';
        final markerIndex = key.indexOf(bucketMarker);
        if (markerIndex >= 0)
          key = key.substring(markerIndex + bucketMarker.length);
        if (seen.add(key)) urls.add(url);
      }
      if (mounted) setState(() => _resolvedOrderAttachments = urls);
    } finally {
      if (mounted) setState(() => _loadingMedia = false);
    }
  }

  List<String> get _orderAttachments => _resolvedOrderAttachments;

  bool get _paid =>
      (_paymentSummary['payment_status'] ?? _order['payment_status'])
          ?.toString()
          .toLowerCase() ==
      'paid';
  bool get _completed => _order['status']?.toString() == 'completed';
  bool get _adminPaymentConfirmed =>
      _order['admin_completion_payment_confirmed_at'] != null;
  bool get _isExternalLaborOrder =>
      _order['requires_inspection'] == true &&
      _order['technician_id'] != null &&
      _inspectionSettlement?['settlement_mode']?.toString() == 'external' &&
      !_completed &&
      (_inspectionSettlement?['status']?.toString() == 'awaiting_admin');

  Future<void> _completeExternalLabor() async {
    await widget.onCompleteExternalLabor();
    await _refresh();
    await widget.onChanged();
  }

  bool get _canEmergencyComplete =>
      !_isExternalLaborOrder &&
      (_order['status']?.toString() == 'in_progress' ||
          _order['status']?.toString() == 'arrived') &&
      _paid &&
      _adminPaymentConfirmed;

  Future<void> _refresh() async {
    final id = int.tryParse(_order['id']?.toString() ?? '');
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final result = await _db.rpc(
        'admin_get_order_control',
        params: {'p_order_id': id},
      );
      if (result is Map && mounted) {
        setState(() => _data = Map<String, dynamic>.from(result));
        await _loadOrderMedia();
        await _loadInspectionSettlement();
      }
    } catch (_) {
      // حالة الواجهة الحالية تظل كما هي عند فشل التحديث.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmPayment() async {
    await widget.onConfirmPayment();
    await _refresh();
    await widget.onChanged();
  }

  Future<void> _emergencyComplete() async {
    await widget.onEmergencyComplete();
    await _refresh();
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _order['remaining_amount']?.toString() ?? '0';
    final paymentRows = (_data['payments'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final pendingPaymentNotice = paymentRows.any(
      (row) => row['status']?.toString() == 'pending',
    );
    final pendingRemainingNotice = paymentRows.any(
      (row) =>
          row['status']?.toString() == 'pending' &&
          row['payment_type']?.toString() == 'remaining_payment',
    );
    final paidRemaining = paymentRows.any(
      (row) =>
          row['status']?.toString() == 'paid' &&
          row['payment_type']?.toString() == 'remaining_payment',
    );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _adminBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _adminDark,
          elevation: 0,
          title: Text(
            'تفاصيل الطلب #${_order['id'] ?? '—'}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _box(
              title: 'بيانات الطلب',
              children: [
                _line('العميل', _order['customer_name']),
                _line('الهاتف', _order['customer_phone']),
                _line(
                  'الفني',
                  _technician['full_name'] ?? _order['technician_id'],
                ),
                _line('مهنة الفني', _technician['profession_name']),
                _line('هاتف الفني', _technician['phone']),
                _line('واتساب الفني', _technician['whatsapp_phone']),
                _line('الخدمة', _order['service_description']),
                _adminAddressDetails(),
                _line('الحالة', _order['status']),
                _line(
                  'نوع الطلب',
                  _order['requires_inspection'] == true
                      ? 'يحتاج معاينة'
                      : 'سعر محدد',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _orderAttachmentsBox(),
            const SizedBox(height: 12),
            _box(
              title: 'الدفع',
              children: [
                _line(
                  'حالة الدفع',
                  _paymentSummary['payment_status'] ?? _order['payment_status'],
                ),
                _line(
                  'إجمالي الخدمة',
                  _paymentSummary['service_total'] ?? _order['total_price'],
                ),
                _line(
                  'إجمالي العميل',
                  _paymentSummary['customer_total_amount'] ??
                      _order['customer_total_amount'],
                ),
                _line(
                  'المدفوع فعليًا',
                  '${_paymentSummary['paid_amount'] ?? 0} جنيه',
                ),
                _line(
                  'المبلغ المتبقي',
                  _paymentSummary['remaining_amount'] ?? remaining,
                ),
                _line(
                  'مستحقات الفني',
                  '${_order['technician_net_amount'] ?? _paymentSummary['technician_net_amount'] ?? 0} جنيه',
                ),
                _line(
                  'حالة مستحقات الفني',
                  _technicianPayout['status'] ??
                      (_order['technician_release_ready_at'] != null
                          ? 'ready'
                          : 'pending'),
                ),
                _line(
                  'إشعار العميل بالدفع',
                  pendingPaymentNotice
                      ? (pendingRemainingNotice
                            ? 'أرسل إشعار سداد المتبقي — بانتظار المراجعة'
                            : 'أرسل إشعار دفع — بانتظار المراجعة')
                      : (paidRemaining
                            ? 'تم تأكيد سداد المتبقي'
                            : 'لا يوجد إشعار دفع معلّق'),
                ),
                _line(
                  'تأكيد الإدارة للدفعة النهائية',
                  _adminPaymentConfirmed
                      ? 'تم التأكيد الفعلي'
                      : 'لم يتم تأكيد الدفعة النهائية',
                ),
                _line(
                  'الـ100 جنيه تحت الحساب',
                  _paymentSummary['requires_inspection'] == true
                      ? '${_paymentSummary['contact_deposit_paid'] ?? 0} جنيه'
                      : '—',
                ),
                const SizedBox(height: 10),
                if (pendingPaymentNotice &&
                    !_completed &&
                    !_isExternalLaborOrder)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _confirmPayment,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('تأكيد اكتمال الدفع'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _adminBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            if (_order['requires_inspection'] == true ||
                _order['inspection_settlement_mode'] != null ||
                _order['inspection_labor_price'] != null) ...[
              const SizedBox(height: 12),
              _box(
                title: 'متابعة المعاينة وتحديد المصنعية',
                children: [
                  _line(
                    'قيمة المصنعية',
                    (_inspectionSettlement?['labor_price'] ??
                                _order['inspection_labor_price']) ==
                            null
                        ? 'في انتظار تحديد الفني بعد المعاينة'
                        : '${_inspectionSettlement?['labor_price'] ?? _order['inspection_labor_price']} جنيه',
                  ),
                  _line(
                    'مسار الاتفاق',
                    switch (_inspectionSettlement?['settlement_mode']
                        ?.toString()) {
                      'in_app' => 'اتفاق داخل المنصة',
                      'external' => 'اتفاق بالتراضي خارج المنصة',
                      'no_agreement' => 'لم يتم الاتفاق بعد المعاينة',
                      _ => 'بانتظار تحديد المصنعية وقرار العميل',
                    },
                  ),
                  _line(
                    'حالة التسوية',
                    _inspectionSettlement?['status']?.toString() ??
                        'بانتظار تحديث الفني',
                  ),
                  _line(
                    'موافقة العميل',
                    _inspectionSettlement?['customer_approved'] == true
                        ? 'تمت الموافقة'
                        : (_inspectionSettlement?['customer_decided_at'] != null
                              ? 'اتخذ العميل قرارًا'
                              : 'في انتظار قرار العميل'),
                  ),
                  if (_inspectionSettlement?['settlement_mode']?.toString() ==
                          'pending' &&
                      _inspectionSettlement?['labor_price'] != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'الفني أرسل المصنعية؛ انتظر موافقة العميل داخل التطبيق أو اختياره الاتفاق الخارجي/عدم الاتفاق. لا تعتمد التسوية قبل تسجيل قرار العميل.',
                        style: TextStyle(color: Color(0xFF607D8B), height: 1.5),
                      ),
                    ),
                  if (_inspectionSettlement == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'لم يسجل الفني سعر المصنعية بعد. تأكد أن مبلغ المعاينة مؤكد وأن بيانات التواصل مفتوحة للفني.',
                        style: TextStyle(color: Color(0xFF607D8B), height: 1.5),
                      ),
                    ),
                ],
              ),
            ],
            if (_isExternalLaborOrder) ...[
              const SizedBox(height: 12),
              _box(
                title: 'تسوية المعاينة',
                children: [
                  _line('المبلغ المدفوع تحت الحساب', '100 جنيه'),
                  _line(
                    'رسوم المنصة على العميل',
                    '${_inspectionSettlement?['customer_fee'] ?? 15} جنيه',
                  ),
                  _line(
                    'رسوم المنصة على الفني',
                    '${_inspectionSettlement?['technician_fee'] ?? 10} جنيه',
                  ),
                  _line(
                    'صافي التسوية للفني',
                    '${_inspectionSettlement?['technician_amount'] ?? 75} جنيه',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تُعرض للإدارة التسوية الكاملة. في الاتفاق خارج التطبيق: 15 جنيهًا رسوم على العميل و10 جنيهات على الفني، ويُجهز باقي الـ100 جنيه للفني ضمن المصنعية. وفي عدم الاتفاق تكون التسوية 70 جنيهًا للعميل و20 جنيهًا للفني و10 جنيهات للمنصة.',
                    style: TextStyle(color: Color(0xFF607D8B), height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _completeExternalLabor,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('اعتماد تسوية المعاينة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _adminBlue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _box(
              title: 'مستحقات الفني',
              children: [
                _line(
                  'المستحق للفني',
                  '${_order['technician_net_amount'] ?? _paymentSummary['technician_net_amount'] ?? 0} جنيه',
                ),
                _line(
                  'حالة الاستحقاق',
                  _technicianPayout['status'] == 'paid'
                      ? 'تم الصرف'
                      : _technicianPayout['status'] == 'ready'
                      ? 'جاهز للصرف'
                      : 'في انتظار اكتمال الشروط',
                ),
                _line(
                  'مرجع الصرف',
                  _technicianPayout['payment_reference'] ?? '—',
                ),
                _line('الفني', _technician['full_name'] ?? '—'),
                _line('هاتف الفني', _technician['phone'] ?? '—'),
                if (_technicianPayout['status'] == 'ready')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading
                          ? null
                          : () async {
                              await widget.onMarkPayoutPaid();
                              await _refresh();
                            },
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('تسجيل صرف مستحقات الفني'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF238B4E),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _box(
              title: 'إنهاء الخدمة',
              children: [
                Text(
                  _completed
                      ? 'تم إنهاء الخدمة بالفعل.'
                      : _canEmergencyComplete
                      ? 'الطلب جاهز للإنهاء. زر الإدارة هنا مخصص للطوارئ إذا تعذر على الفني التأكيد من التطبيق.'
                      : 'لن يتاح إنهاء الخدمة من الإدارة قبل اكتمال الدفع وتأكيده، ما لم يتم اعتماد إجراء طوارئ وفق صلاحيات النظام.',
                  style: TextStyle(
                    color: _completed
                        ? const Color(0xFF238B4E)
                        : const Color(0xFF607D8B),
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (!_completed && _canEmergencyComplete && !_loading)
                        ? _emergencyComplete
                        : null,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('إنهاء الخدمة من الإدارة - طوارئ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _adminBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderAttachmentsBox() {
    final images = _orderAttachments;
    return _box(
      title: 'صور المشكلة المرفقة من العميل',
      children: [
        const Text(
          'الصور التي أرسلها العميل مع الطلب — إن وجدت.',
          style: TextStyle(color: Color(0xFF607D8B), height: 1.4),
        ),
        const SizedBox(height: 12),
        if (_loadingMedia)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (images.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _adminBorder),
            ),
            child: const Text(
              'لا توجد صور مشكلة مرفقة من العميل لهذا الطلب.',
              style: TextStyle(
                color: Color(0xFF607D8B),
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 760
                  ? 4
                  : constraints.maxWidth >= 480
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: images.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final url = images[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _showOrderImage(url, index + 1),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        color: _adminBg,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 34,
                                  color: Color(0xFF78909C),
                                ),
                              ),
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              },
                            ),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'صورة ${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  void _showOrderImage(String url, int number) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(18),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 56,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'صورة المشكلة $number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box({required String title, required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _adminBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: _adminDark,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  Widget _line(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF607D8B),
            ),
          ),
        ),
        Expanded(child: Text(value?.toString() ?? '—')),
      ],
    ),
  );
}
