import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/account_type_page.dart';

const _blue = Color(0xFF087FD0);
const _darkBlue = Color(0xFF073A68);
const _bg = Color(0xFFF5FAFD);
const _border = Color(0xFFDDEAF2);

class _CustomerScrollBehavior extends MaterialScrollBehavior {
  const _CustomerScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  final _db = Supabase.instance.client;

  bool _loading = false;
  bool _firstLoadDone = false;
  bool _loggingOut = false;
  String? _error;
  String _name = 'العميل';
  int _pendingOffersCount = 0;
  List<Map<String, dynamic>> _professions = [];
  RealtimeChannel? _realtimeChannel;
  bool _loadingData = false;

  @override
  void initState() {
    super.initState();
    _load();
    _realtimeChannel = _db
        .channel('customer-home-live-${_db.auth.currentUser?.id ?? 'guest'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (mounted) unawaited(_loadPendingOffersCount());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_technician_offers',
          callback: (_) {
            if (mounted) unawaited(_loadPendingOffersCount());
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _realtimeChannel;
    if (channel != null) _db.removeChannel(channel);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadingData) return;
    _loadingData = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _db.auth.currentUser;
      if (user == null) {
        throw Exception('لا يوجد حساب عميل مسجل الدخول.');
      }

      // تحميل بيانات العميل بشكل مستقل عن تحميل المهن؛ حتى لو تعذر استعلام واحد
      // لا تختفي الصفحة بالكامل.
      try {
        final customer = await _db
            .from('customers')
            .select('full_name')
            .eq('user_id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 8));

        final name = customer?['full_name']?.toString().trim();
        if (name != null && name.isNotEmpty && mounted) {
          setState(() => _name = name);
        }
      } catch (_) {
        // الاسم غير أساسي لعرض الصفحة.
      }

      try {
        final result = await _db
            .from('professions')
            .select('id,name_ar,slug,is_active,sort_order,image_path')
            .eq('is_active', true)
            .order('sort_order', ascending: true)
            .timeout(const Duration(seconds: 8));

        _professions = List<Map<String, dynamic>>.from(result);
      } catch (e) {
        if (mounted) {
          setState(
            () => _error = 'تعذر تحميل المهن حاليًا. حاول تحديث الصفحة.',
          );
        }
      }

      unawaited(_loadPendingOffersCount());
    } catch (e) {
      if (mounted) {
        setState(() => _error = _clean(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _firstLoadDone = true;
        });
      }
      _loadingData = false;
    }
  }

  Future<void> _loadPendingOffersCount() async {
    try {
      final customer = await _db
          .from('customers')
          .select('id')
          .eq('user_id', _db.auth.currentUser!.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (customer == null || customer['id'] == null) {
        if (mounted) setState(() => _pendingOffersCount = 0);
        return;
      }

      final orders = await _db
          .from('orders')
          .select('id,selected_offer_id,status')
          .eq('customer_id', customer['id'])
          .timeout(const Duration(seconds: 8));

      var total = 0;
      for (final order in List<Map<String, dynamic>>.from(orders)) {
        final status = order['status']?.toString() ?? '';
        if (order['selected_offer_id'] != null ||
            status == 'completed' ||
            status == 'cancelled') {
          continue;
        }
        try {
          final raw = await _db.rpc(
            'get_customer_order_offers',
            params: {'p_order_id': order['id']},
          );
          final offers = raw is Map
              ? (raw['offers'] as List? ?? const [])
              : (raw as List? ?? const []);
          total += offers.length;
        } catch (_) {
          // لا تمنع أخطاء عداد العروض الصفحة الرئيسية من الظهور.
        }
      }

      if (mounted) {
        setState(() {
          _pendingOffersCount = total;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pendingOffersCount = 0;
        });
      }
    }
  }

  Future<void> _openSupport() async {
    const phone = '01505013234';
    final uri = Uri.parse(
      'https://wa.me/201505013234?text=${Uri.encodeComponent('مرحبًا، أحتاج إلى المساعدة والدعم الفني من صنايعي.')}',
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.support_agent_outlined, color: _blue),
              SizedBox(width: 8),
              Expanded(child: Text('المساعدة والدعم الفني')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'لو محتاج مساعدة أو واجهتك مشكلة أثناء استخدام التطبيق، تواصل معنا مباشرة عبر WhatsApp.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF8EF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.chat_outlined, color: Colors.green, size: 25),
                      SizedBox(width: 10),
                      Text(
                        phone,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Spacer(),
                      Icon(Icons.open_in_new, color: Colors.green, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() => _loggingOut = true);

    try {
      await _db.auth.signOut().timeout(const Duration(seconds: 8));
    } catch (_) {
      // نكمل الرجوع لشاشة نوع الحساب حتى لا يظل زر الخروج عالقًا.
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AccountTypePage()),
      (_) => false,
    );
  }

  void _openProfession(Map<String, dynamic> profession) {
    final id = profession['id'];
    final name = profession['name_ar']?.toString().trim() ?? 'المهنة';

    if (id == null) {
      _message('تعذر فتح المهنة.');
      return;
    }

    // حسب السيناريو المتفق عليه: اختيار المهنة ثم إنشاء الطلب مباشرة.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerOrderDetailsPage(professionId: id, professionName: name),
      ),
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _clean(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('PGRST116') ||
        text.contains('Cannot coerce the result to a single JSON object') ||
        text.contains('0 rows')) {
      return 'لم يتم العثور على البيانات المطلوبة. يرجى تحديث الصفحة والمحاولة مرة أخرى.';
    }
    if (text.contains('FULL_PAYMENT_NOT_CONFIRMED')) {
      return 'لم يتم تأكيد سداد كامل المبلغ بعد.';
    }
    if (text.contains('ORDER_NOT_FOUND')) {
      return 'الطلب غير موجود أو لم يعد متاحًا.';
    }
    if (text.contains('violates row-level security') ||
        text.contains('permission denied') ||
        text.contains('not authorized')) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
    if (text.startsWith('PostgrestException')) {
      return 'حدث خطأ أثناء الاتصال بقاعدة البيانات. يرجى المحاولة مرة أخرى.';
    }
    return text.isEmpty ? 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.' : text;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _darkBlue,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'صنايعي',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            TextButton.icon(
              onPressed: _openSupport,
              icon: const Icon(Icons.support_agent_outlined, size: 20),
              label: const Text(
                'المساعدة والدعم الفني',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(foregroundColor: _darkBlue),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: _loggingOut ? null : _logout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_outlined),
            ),
          ],
        ),
        body: ScrollConfiguration(
          behavior: const _CustomerScrollBehavior(),
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
              children: [
                _welcome(),
                const SizedBox(height: 16),
                _coverage(),
                const SizedBox(height: 24),
                const Text(
                  'اختار المهنة اللي محتاجها',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _darkBlue,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'اختار المهنة، وبعدها اكتب تفاصيل طلبك مباشرة.',
                  style: TextStyle(color: Color(0xFF78909C)),
                ),
                const SizedBox(height: 16),
                if (_error != null) _errorCard(_error!),
                if (_loading && !_firstLoadDone)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: CircularProgressIndicator(color: _blue),
                    ),
                  ),
                if (!_loading && _professions.isEmpty && _error == null)
                  _empty('لا توجد مهن متاحة حاليًا.'),
                if (_professions.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 900
                          ? 4
                          : constraints.maxWidth >= 600
                          ? 3
                          : 2;
                      final spacing = 12.0;
                      final cardWidth =
                          (constraints.maxWidth - (spacing * (columns - 1))) /
                          columns;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: _professions
                            .map(
                              (profession) => SizedBox(
                                width: cardWidth,
                                child: _professionCard(profession),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'أهلاً بك في صنايعي 👋',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _darkBlue,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'كل خدماتك في مكان واحد بسهولة وأمان، مع ضمان على الخدمة المقدمة يصل إلى 30 يومًا.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF607D8B),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _homeActionCard(
                icon: Icons.person_outline,
                title: 'العميل',
                subtitle: _name,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _homeActionCard(
                icon: Icons.receipt_long_outlined,
                title: 'طلباتي',
                subtitle: 'متابعة طلباتك وخدماتك',
                badgeCount: _pendingOffersCount,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CustomerOrdersPage(),
                    ),
                  );
                  if (mounted) _loadPendingOffersCount();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _homeActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    int badgeCount = 0,
    VoidCallback? onTap,
  }) {
    final child = Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A073A68),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _blue, size: 26),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _darkBlue,
                    ),
                  ),
                  if (badgeCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF78909C)),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: child,
      ),
    );
  }

  Widget _coverage() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F6FF),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.location_city_outlined, color: _blue),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'نبدأ حاليًا في مدينة العبور ونعمل على التوسع لمناطق جديدة قريبًا.',
            style: TextStyle(
              color: _darkBlue,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _professionCard(Map<String, dynamic> profession) {
    final name = profession['name_ar']?.toString().trim() ?? 'مهنة';
    final imagePath = profession['image_path']?.toString().trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openProfession(profession),
          child: Container(
            constraints: const BoxConstraints(minHeight: 128),
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _professionLogo(imagePath),
                ),
                const SizedBox(height: 9),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _darkBlue,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                const Icon(
                  Icons.arrow_back_ios_new,
                  size: 12,
                  color: Color(0xFF78909C),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _professionLogo(String? imagePath) {
    if (imagePath != null && imagePath.isNotEmpty) {
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        return Image.network(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.handyman_outlined, color: _blue, size: 28),
        );
      }

      if (imagePath.startsWith('assets/')) {
        return Image.asset(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.handyman_outlined, color: _blue, size: 28),
        );
      }
    }

    return const Icon(Icons.handyman_outlined, color: _blue, size: 28);
  }
}

class CustomerServicesPage extends StatefulWidget {
  const CustomerServicesPage({
    super.key,
    required this.professionId,
    required this.professionName,
  });
  final dynamic professionId;
  final String professionName;

  @override
  State<CustomerServicesPage> createState() => _CustomerServicesPageState();
}

class _CustomerServicesPageState extends State<CustomerServicesPage> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _services = [];
  bool _loadInProgress = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    try {
      // Background polling must never replace the page with a loading screen.
      if (mounted) setState(() => _error = null);
      final result = await _db
          .from('services')
          .select(
            'id,service_name,description,pricing_type,is_active,sort_order,profession_id,is_emergency,image_path',
          )
          .eq('profession_id', widget.professionId)
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      _services = List<Map<String, dynamic>>.from(result);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = _clean(e);
        });
    } finally {
      _loadInProgress = false;
    }
  }

  String _clean(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('PGRST116') ||
        text.contains('Cannot coerce the result to a single JSON object') ||
        text.contains('0 rows')) {
      return 'لم يتم العثور على البيانات المطلوبة. يرجى تحديث الصفحة والمحاولة مرة أخرى.';
    }
    if (text.contains('FULL_PAYMENT_NOT_CONFIRMED')) {
      return 'لم يتم تأكيد سداد كامل المبلغ بعد.';
    }
    if (text.contains('ORDER_NOT_FOUND')) {
      return 'الطلب غير موجود أو لم يعد متاحًا.';
    }
    if (text.contains('violates row-level security') ||
        text.contains('permission denied') ||
        text.contains('not authorized')) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
    if (text.startsWith('PostgrestException')) {
      return 'حدث خطأ أثناء الاتصال بقاعدة البيانات. يرجى المحاولة مرة أخرى.';
    }
    return text.isEmpty ? 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.' : text;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _darkBlue,
          elevation: 0,
          centerTitle: true,
          title: Text(
            widget.professionName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _blue))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(18),
                  children: [
                    const Text(
                      'اختار الخدمة',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: _darkBlue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'الخدمات المتاحة لهذه المهنة.',
                      style: TextStyle(color: Color(0xFF78909C)),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) _errorCard(_error!),
                    if (_services.isEmpty && _error == null)
                      _empty('لا توجد خدمات متاحة حاليًا لهذه المهنة.'),
                    ..._services.map(_serviceCard),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _serviceCard(Map<String, dynamic> service) {
    final name = service['service_name']?.toString() ?? 'الخدمة';
    final description = service['description']?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerOrderDetailsPage(
                professionId: widget.professionId,
                professionName: widget.professionName,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6FF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.build_outlined,
                    color: _blue,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _darkBlue,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF78909C),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: Color(0xFF78909C),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerOrderDetailsPage extends StatefulWidget {
  const CustomerOrderDetailsPage({
    super.key,
    required this.professionId,
    required this.professionName,
    this.existingOrder,
  });
  final dynamic professionId;
  final String professionName;
  final Map<String, dynamic>? existingOrder;

  bool get isEditing => existingOrder != null;

  @override
  State<CustomerOrderDetailsPage> createState() =>
      _CustomerOrderDetailsPageState();
}

class _CustomerOrderDetailsPageState extends State<CustomerOrderDetailsPage> {
  final _db = Supabase.instance.client;
  final _imagePicker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _secondaryPhone = TextEditingController();
  final _area = TextEditingController();
  final _street = TextEditingController();
  final _building = TextEditingController();
  final _floor = TextEditingController();
  final _apartment = TextEditingController();
  final _problem = TextEditingController();

  bool _loading = true;
  bool _creating = false;
  bool _materials = false;
  String? _error;
  String? _nameFieldError;
  DateTime? _date;
  TimeOfDay? _from;
  TimeOfDay? _to;
  List<XFile> _images = [];

  @override
  void initState() {
    super.initState();
    _loadCustomer();
  }

  @override
  void dispose() {
    _name.dispose();
    _secondaryPhone.dispose();
    _area.dispose();
    _street.dispose();
    _building.dispose();
    _floor.dispose();
    _apartment.dispose();
    _problem.dispose();
    super.dispose();
  }

  Future<void> _loadCustomer() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) throw Exception('يجب تسجيل الدخول أولًا.');
      final customer = await _db
          .from('customers')
          .select('full_name,phone')
          .eq('user_id', user.id)
          .maybeSingle();
      if (customer == null) {
        throw Exception(
          'لم يتم العثور على بيانات العميل. يرجى تسجيل الدخول مرة أخرى.',
        );
      }
      _name.text =
          widget.existingOrder?['customer_name']
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
          ? widget.existingOrder!['customer_name'].toString()
          : (customer['full_name']?.toString() ?? '');
      _secondaryPhone.text =
          widget.existingOrder?['secondary_phone']?.toString() ?? '';

      if (widget.existingOrder != null) {
        _hydrateExistingOrder(widget.existingOrder!);
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  void _hydrateExistingOrder(Map<String, dynamic> order) {
    final address = order['address']?.toString().trim() ?? '';
    final parts = address
        .split(RegExp(r'\s*[—-]\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (parts.isNotEmpty) _area.text = parts[0];
    if (parts.length > 1) _street.text = parts[1];
    if (parts.length > 2) _building.text = parts[2];
    if (parts.length > 3) _floor.text = parts[3];
    if (parts.length > 4) _apartment.text = parts.sublist(4).join(' — ');

    _problem.text =
        order['service_description']?.toString() ??
        order['problem_description']?.toString() ??
        '';
    _materials = order['materials_requested'] == true;

    final scheduledAt = DateTime.tryParse(
      order['scheduled_at']?.toString() ?? '',
    )?.toLocal();
    final scheduledTo = DateTime.tryParse(
      order['scheduled_to']?.toString() ?? '',
    )?.toLocal();

    if (scheduledAt != null) {
      _date = DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day);
      _from = TimeOfDay(hour: scheduledAt.hour, minute: scheduledAt.minute);
    }
    if (scheduledTo != null) {
      _to = TimeOfDay(hour: scheduledTo.hour, minute: scheduledTo.minute);
    }
  }

  String _composeAddress() => [
    _area.text.trim(),
    _street.text.trim(),
    _building.text.trim(),
    _floor.text.trim(),
    _apartment.text.trim(),
  ].join(' — ');

  String? _requiredAddressPart(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'اكتب $label.' : null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      locale: const Locale('ar'),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _pickTime(bool from) async {
    final value = await showTimePicker(
      context: context,
      initialTime: from
          ? (_from ?? TimeOfDay.now())
          : (_to ?? _from ?? TimeOfDay.now()),
    );
    if (value != null && mounted)
      setState(() => from ? _from = value : _to = value);
  }

  Future<void> _pickImages() async {
    final picked = await _imagePicker.pickMultiImage(
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (!mounted || picked.isEmpty) return;
    setState(() => _images = [..._images, ...picked].take(5).toList());
  }

  Future<void> _createOrder() async {
    FocusScope.of(context).unfocus();
    _nameFieldError = null;
    if (!_formKey.currentState!.validate()) return;
    final address = _composeAddress();
    if (_date == null || _from == null || _to == null) {
      _message('حدد تاريخ وبداية ونهاية الموعد.');
      return;
    }
    final fromMinutes = _from!.hour * 60 + _from!.minute;
    final toMinutes = _to!.hour * 60 + _to!.minute;
    if (toMinutes <= fromMinutes) {
      _message('وقت النهاية يجب أن يكون بعد البداية.');
      return;
    }
    final scheduledFrom = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _from!.hour,
      _from!.minute,
    ).toUtc();
    final scheduledTo = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _to!.hour,
      _to!.minute,
    ).toUtc();

    try {
      setState(() {
        _creating = true;
        _error = null;
      });

      if (widget.isEditing) {
        await _db.rpc(
          'update_customer_pending_order',
          params: {
            'p_order_id': widget.existingOrder!['id'],
            'p_customer_name': _name.text.trim(),
            'p_secondary_phone': _secondaryPhone.text.trim().isEmpty
                ? null
                : _secondaryPhone.text.trim(),
            'p_service_description': _problem.text.trim(),
            'p_scheduled_at': scheduledFrom.toIso8601String(),
            'p_scheduled_to': scheduledTo.toIso8601String(),
            'p_address': address,
            'p_materials_requested': _materials,
          },
        );

        if (!mounted) return;
        setState(() => _creating = false);
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تم تعديل الطلب'),
              content: const Text(
                'تم حفظ تعديلات طلبك بنجاح، وسيظهر الطلب للفنيين بالبيانات الجديدة.',
                textAlign: TextAlign.center,
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('حسنًا'),
                ),
              ],
            ),
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      final result = await _db.rpc(
        'create_customer_order_v2',
        params: {
          'p_profession_id': widget.professionId,
          'p_service_description': _problem.text.trim(),
          'p_scheduled_at': scheduledFrom.toIso8601String(),
          'p_scheduled_to': scheduledTo.toIso8601String(),
          'p_address': address,
          'p_area_id': null,
          'p_customer_name': _name.text.trim(),
          'p_secondary_phone': _secondaryPhone.text.trim().isEmpty
              ? null
              : _secondaryPhone.text.trim(),
          'p_materials_requested': _materials,
          'p_quantity': null,
          'p_attachments': [],
        },
      );

      final order = Map<String, dynamic>.from(result as Map);
      final orderId = order['id'];

      String? attachmentWarning;
      if (_images.isNotEmpty && orderId != null) {
        final paths = <String>[];

        for (var i = 0; i < _images.length; i++) {
          final file = _images[i];
          try {
            final bytes = await file.readAsBytes();
            if (bytes.isEmpty) throw Exception('ملف الصورة فارغ.');

            final originalName = file.name.toLowerCase();
            final ext = originalName.endsWith('.png')
                ? 'png'
                : originalName.endsWith('.webp')
                ? 'webp'
                : originalName.endsWith('.jpeg')
                ? 'jpeg'
                : 'jpg';
            final contentType = switch (ext) {
              'png' => 'image/png',
              'webp' => 'image/webp',
              'jpeg' => 'image/jpeg',
              _ => 'image/jpeg',
            };
            final path =
                'orders/$orderId/${DateTime.now().microsecondsSinceEpoch}_$i.$ext';

            await _db.storage
                .from('customer-order-attachments')
                .uploadBinary(
                  path,
                  bytes,
                  fileOptions: FileOptions(
                    contentType: contentType,
                    upsert: true,
                  ),
                );
            paths.add(path);
          } catch (_) {
            attachmentWarning =
                'تم إرسال الطلب بنجاح، لكن تعذر رفع إحدى صور المشكلة. يمكنك متابعة الطلب والمحاولة لاحقًا.';
          }
        }

        if (paths.isNotEmpty) {
          try {
            await _db.rpc(
              'append_customer_order_attachments',
              params: {'p_order_id': orderId, 'p_paths': paths},
            );
          } catch (_) {
            attachmentWarning =
                'تم إرسال الطلب بنجاح، لكن تعذر حفظ صور المشكلة حاليًا.';
          }
        }
      }

      if (!mounted) return;
      setState(() => _creating = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تم إرسال الطلب'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 62,
                ),
                const SizedBox(height: 12),
                const Text(
                  'تم إرسال الطلب إلى فنيي المهنة. ستظهر العروض هنا فور وصولها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (attachmentWarning != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      attachmentWarning!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8A5A00),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => CustomerOrderPage(orderId: orderId),
                    ),
                  );
                },
                child: const Text('متابعة الطلب'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final friendly = _cleanOrderError(e);
      setState(() {
        _creating = false;
        _error = friendly;
      });
      if (_nameFieldError != null) {
        _formKey.currentState?.validate();
      }
      _message(friendly);
    }
  }

  String _cleanOrderError(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('customer full name must contain at least three names') ||
        raw.contains('full name must contain at least three names') ||
        raw.contains('at least three names')) {
      _nameFieldError = 'يرجى كتابة الاسم الثلاثي على الأقل.';
      return 'يرجى إدخال البيانات بالشكل الصحيح: اسم العميل يجب أن يتكون من ثلاثة أسماء على الأقل.';
    }
    if (e is PostgrestException && e.code == 'P0001') {
      return 'يرجى إدخال البيانات بالشكل الصحيح ثم المحاولة مرة أخرى.';
    }
    return 'تعذر إرسال الطلب حاليًا. يرجى مراجعة البيانات والمحاولة مرة أخرى.';
  }

  String _clean(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('PGRST116') ||
        text.contains('Cannot coerce the result to a single JSON object') ||
        text.contains('0 rows')) {
      return 'لم يتم العثور على البيانات المطلوبة. يرجى تحديث الصفحة والمحاولة مرة أخرى.';
    }
    if (text.contains('FULL_PAYMENT_NOT_CONFIRMED')) {
      return 'لم يتم تأكيد سداد كامل المبلغ بعد.';
    }
    if (text.contains('ORDER_NOT_FOUND')) {
      return 'الطلب غير موجود أو لم يعد متاحًا.';
    }
    if (text.contains('violates row-level security') ||
        text.contains('permission denied') ||
        text.contains('not authorized')) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
    if (text.startsWith('PostgrestException')) {
      return 'حدث خطأ أثناء الاتصال بقاعدة البيانات. يرجى المحاولة مرة أخرى.';
    }
    return text.isEmpty ? 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.' : text;
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  String _dateText() => _date == null
      ? 'اختار اليوم'
      : '${_date!.day}/${_date!.month}/${_date!.year}';
  String _timeText(TimeOfDay? value) {
    if (value == null) return 'اختار الوقت';
    final hour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
    return '$hour:${value.minute.toString().padLeft(2, '0')} ${value.period == DayPeriod.am ? 'ص' : 'م'}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _darkBlue,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'تفاصيل الطلب',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _loadCustomer,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _blue))
            : ScrollConfiguration(
                behavior: const _CustomerScrollBehavior(),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    children: [
                      _header(),
                      const SizedBox(height: 18),
                      _section('بيانات العميل'),
                      const SizedBox(height: 10),
                      _field(
                        _name,
                        'اسم العميل الثلاثي',
                        'مثال: أحمد محمد علي',
                        Icons.person_outline,
                        validator: (v) => _nameFieldError ?? _threeNames(v),
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _secondaryPhone,
                        'رقم تواصل إضافي (اختياري)',
                        '01xxxxxxxxx',
                        Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 20),
                      _section('تفاصيل الخدمة المطلوبة'),
                      const SizedBox(height: 10),
                      _field(
                        _problem,
                        'وصف الخدمة المطلوبة',
                        'يرجى وصف المشكلة والخدمة المطلوبة بوضوح وتفاصيل كافية ليساعد ذلك الفنيين على تقديم عروض أدق.',
                        Icons.description_outlined,
                        maxLines: 6,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'اكتب وصف الخدمة المطلوبة.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      _imagesCard(),
                      const SizedBox(height: 14),
                      _materialsTile(),
                      const SizedBox(height: 20),
                      _section('الموعد المطلوب'),
                      const SizedBox(height: 10),
                      _datePicker(
                        _dateText(),
                        Icons.calendar_month_outlined,
                        _pickDate,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _datePicker(
                              'من: ${_timeText(_from)}',
                              Icons.access_time_outlined,
                              () => _pickTime(true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _datePicker(
                              'إلى: ${_timeText(_to)}',
                              Icons.access_time_filled_outlined,
                              () => _pickTime(false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'الفني يمكنه تأكيد نفس الموعد أو تقديم موعد بديل داخل عرضه.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78909C),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _section('مكان الخدمة'),
                      const SizedBox(height: 10),
                      _addressEditor(),
                      const SizedBox(height: 20),
                      _notice(),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _errorCard(_error!),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _creating ? null : _createOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _creating
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  widget.isEditing
                                      ? 'حفظ تعديلات الطلب'
                                      : 'إرسال الطلب للصنايعية',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 25),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  String? _threeNames(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'اكتب اسم العميل.';
    if (v.split(RegExp(r'\s+')).length < 3)
      return 'اكتب الاسم الثلاثي على الأقل.';
    return null;
  }

  Widget _header() => _card(
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F6FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.build_outlined, color: _blue, size: 29),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.professionName,
                style: const TextStyle(fontSize: 12, color: Color(0xFF78909C)),
              ),
              const SizedBox(height: 3),
              Text(
                widget.isEditing ? 'تعديل الطلب' : 'إنشاء طلب خدمة',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _darkBlue,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _section(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: _darkBlue,
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboardType,
    validator: validator,
    decoration: _dec(label, icon, hint: hint),
  );

  InputDecoration _dec(String label, IconData icon, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _blue),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      );

  Widget _datePicker(String text, IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: _blue),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _darkBlue,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _materialsTile() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: CheckboxListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      value: _materials,
      onChanged: (v) => setState(() => _materials = v ?? false),
      title: const Text(
        'أرغب في فني يوفر الخامات',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Text(
        'عند توفير الخامات من قبل الفني، يقدّم لك الفاتورة أو اسم ورقم المحل، واسم السائق إذا كانت الخامات تحتاج إلى نقل وتوريد، وذلك للتأكد من صحة الأسعار.\n\nيحصل الفني مقابل توفير الخامات على 3% من قيمة الخامات، بحد أدنى 15 جنيهًا.',
        style: TextStyle(height: 1.5),
      ),
    ),
  );

  Widget _imagesCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'صور المشكلة (اختياري)',
          style: TextStyle(fontWeight: FontWeight.w800, color: _darkBlue),
        ),
        const SizedBox(height: 5),
        const Text(
          'يمكنك إرفاق حتى 5 صور تساعد الفني على تقدير الحالة.',
          style: TextStyle(fontSize: 12, color: Color(0xFF78909C)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._images.asMap().entries.map(
              (e) => Chip(
                label: Text('صورة ${e.key + 1}'),
                onDeleted: () => setState(() => _images.removeAt(e.key)),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('إضافة صور'),
              onPressed: _images.length >= 5 ? null : _pickImages,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _addressEditor() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on_outlined, color: _blue, size: 20),
            const SizedBox(width: 6),
            const Text(
              'العنوان بالتفصيل',
              style: TextStyle(
                color: _darkBlue,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 900 ? 3 : (width >= 560 ? 2 : 1);
            const gap = 8.0;
            final itemWidth = columns == 1
                ? width
                : (width - (gap * (columns - 1))) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _addressPart(_area, 'الحي', 'مثال: الحي الأول'),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _addressPart(
                    _street,
                    'اسم الشارع',
                    'مثال: شارع أحمد عرابي',
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _addressPart(
                    _building,
                    'العمارة/البلوك',
                    'مثال: عمارة 12 / بلوك 5',
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _addressPart(_floor, 'الدور', 'مثال: الدور الثالث'),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _addressPart(_apartment, 'الشقة', 'مثال: شقة 8'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 5),
        const Text(
          'يُحفظ العنوان بالترتيب التالي: الحي — الشارع — العمارة/البلوك — الدور — الشقة.',
          style: TextStyle(fontSize: 10, color: Color(0xFF78909C), height: 1.3),
        ),
      ],
    ),
  );

  Widget _addressPart(
    TextEditingController controller,
    String label,
    String hint,
  ) => TextFormField(
    controller: controller,
    textInputAction: TextInputAction.next,
    style: const TextStyle(fontSize: 12),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(fontSize: 11),
      hintStyle: const TextStyle(fontSize: 10, color: Color(0xFF90A4AE)),
      prefixIcon: const Icon(
        Icons.edit_location_alt_outlined,
        color: _blue,
        size: 17,
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF9FCFE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _blue, width: 1.4),
      ),
    ),
    validator: (value) => _requiredAddressPart(value, label),
  );

  Widget _notice() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F6FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: _blue),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'بعد الإرسال يذهب الطلب لكل الفنيين المناسبين للمهنة. كل فني يقدم عرضه وموعده، ثم تختار أنت العرض المناسب.',
            style: TextStyle(
              fontSize: 12,
              color: _darkBlue,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class CustomerOrdersPage extends StatefulWidget {
  const CustomerOrdersPage({super.key});
  @override
  State<CustomerOrdersPage> createState() => _CustomerOrdersPageState();
}

class _CustomerOrdersPageState extends State<CustomerOrdersPage> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];
  final Set<dynamic> _cancellationRequested = <dynamic>{};
  RealtimeChannel? _realtimeChannel;
  bool _loadInProgress = false;

  @override
  void initState() {
    super.initState();
    _load();
    _realtimeChannel = _db
        .channel('customer-orders-live-${_db.auth.currentUser?.id ?? 'guest'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (mounted) unawaited(_load(silent: true));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_technician_offers',
          callback: (_) {
            if (mounted) unawaited(_load(silent: true));
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _realtimeChannel;
    if (channel != null) _db.removeChannel(channel);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    try {
      if (!silent)
        setState(() {
          _loading = _orders.isEmpty;
          _error = null;
        });
      final user = _db.auth.currentUser;
      if (user == null) throw Exception('يجب تسجيل الدخول أولًا.');
      final customer = await _db
          .from('customers')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (customer == null) {
        throw Exception(
          'لم يتم العثور على حساب العميل. يرجى تسجيل الدخول مرة أخرى.',
        );
      }
      final result = await _db
          .from('orders')
          .select(
            'id,created_at,profession_id,scheduled_at,scheduled_to,service_description,problem_description,address,status,payment_status,payment_type,offers_status,customer_total_amount,remaining_amount,selected_offer_id,customer_selected_at,requires_inspection,materials_requested,full_payment_confirmed_at,contact_released_at,selection_payment_deadline_at,inspection_settlement_mode,professions(name_ar)',
          )
          .eq('customer_id', customer['id'])
          .neq('status', 'cancelled')
          .order('created_at', ascending: false);
      final loadedOrders = List<Map<String, dynamic>>.from(result);

      // احسب عدد العروض لكل طلب حتى يظهر للعميل مباشرة في صفحة "طلباتي".
      // العدد هنا يُقرأ من نفس مصدر العروض المستخدم في صفحة متابعة الطلب.
      for (final order in loadedOrders) {
        var offersCount = 0;
        try {
          final raw = await _db.rpc(
            'get_customer_order_offers',
            params: {'p_order_id': order['id']},
          );
          final offers = raw is Map
              ? (raw['offers'] as List? ?? const [])
              : (raw as List? ?? const []);
          offersCount = offers.length;
        } catch (_) {
          // عدم القدرة على قراءة العدد لا يمنع عرض الطلب نفسه.
        }
        order['_offers_count'] = offersCount;
      }

      _orders = loadedOrders;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = _clean(e);
        });
    } finally {
      _loadInProgress = false;
    }
  }

  String _clean(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains(
      "infinite recursion detected in policy for relation 'orders'",
    )) {
      return 'تعذر تحميل الطلبات بسبب مشكلة في الصلاحيات. يرجى تحديث الصفحة والمحاولة مرة أخرى.';
    }
    if (text.contains('PGRST116') ||
        text.contains('Cannot coerce the result to a single JSON object') ||
        text.contains('0 rows')) {
      return 'لم يتم العثور على البيانات المطلوبة. يرجى تحديث الصفحة والمحاولة مرة أخرى.';
    }
    if (text.contains('FULL_PAYMENT_NOT_CONFIRMED')) {
      return 'لم يتم تأكيد سداد كامل المبلغ بعد.';
    }
    if (text.contains('ORDER_NOT_FOUND')) {
      return 'الطلب غير موجود أو لم يعد متاحًا.';
    }
    if (text.contains('ORDER_NOT_READY_FOR_COMPLETION_PAYMENT_CONFIRMATION')) {
      return 'الطلب غير جاهز لتأكيد اكتمال الدفع في الوقت الحالي.';
    }
    if (text.contains('ADMIN_ONLY')) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
    if (text.contains('AUTH') ||
        text.contains('JWT') ||
        text.contains('Not authenticated')) {
      return 'انتهت جلسة الدخول. يرجى تسجيل الدخول مرة أخرى.';
    }
    if (text.contains('violates row-level security') ||
        text.contains('permission denied') ||
        text.contains('not authorized')) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
    if (text.startsWith('PostgrestException')) {
      return 'حدث خطأ أثناء الاتصال بقاعدة البيانات. يرجى المحاولة مرة أخرى.';
    }
    return text.isEmpty ? 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.' : text;
  }

  String _status(String value) {
    switch (value) {
      case 'pending':
        return 'قيد استقبال العروض';
      case 'accepted':
        return 'تم اختيار فني';
      case 'on_the_way':
        return 'الفني في الطريق';
      case 'arrived':
        return 'الفني وصل';
      case 'in_progress':
        return 'الخدمة قيد التنفيذ';
      case 'completed':
        return 'مكتمل';
      case 'cancelled':
        return 'ملغي';
      default:
        return value.isEmpty ? 'غير محدد' : value;
    }
  }

  Color _statusColor(String value) {
    if (value == 'completed') return Colors.green;
    if (value == 'cancelled') return Colors.red;
    if (value == 'pending') return Colors.orange;
    return _blue;
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _darkBlue,
        elevation: 0,
        title: const Text(
          'طلباتي',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: const PageStorageKey<String>('customer-orders-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  if (_error != null) _errorCard(_error!),
                  if (_orders.isEmpty && _error == null)
                    _empty('لا توجد طلبات حتى الآن.'),
                  ..._orders.map(_card),
                ],
              ),
            ),
    ),
  );

  Future<void> _editOrder(Map<String, dynamic> order) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerOrderDetailsPage(
          professionId: order['profession_id'],
          professionName: (order['professions'] is Map)
              ? (order['professions']['name_ar']?.toString() ?? 'المهنة')
              : 'المهنة',
          existingOrder: order,
        ),
      ),
    );
    if (result == true && mounted) await _load();
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إلغاء الطلب'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'هل أنت متأكد من رغبتك في إلغاء هذا الطلب؟',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'سبب الإلغاء (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('رجوع'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تأكيد الإلغاء'),
            ),
          ],
        ),
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;

    try {
      await _db.rpc(
        'request_order_cancellation',
        params: {
          'p_order_id': order['id'],
          'p_reason': text.isEmpty ? null : text,
        },
      );

      // الإلغاء يجب أن يصبح نهائيًا على الطلب نفسه، وليس مجرد طلب إلغاء.
      // بذلك لا يعود الطلب بعد Refresh أو بعد تسجيل الخروج والدخول مرة أخرى.
      await _db
          .from('orders')
          .update({'status': 'cancelled'})
          .eq('id', order['id']);

      // الطلب الملغي لا يظهر للعميل مرة أخرى. نحذفه من القائمة المحلية فورًا
      // حتى لا يظل ظاهرًا إلى أن يتم عمل Refresh.
      if (!mounted) return;
      setState(() {
        _cancellationRequested.add(order['id']);
        _orders.removeWhere((item) => item['id'] == order['id']);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء الطلب وحذفه من طلباتك.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_clean(e))));
    }
  }

  Widget _card(Map<String, dynamic> order) {
    final p = order['professions'];
    final profession = p is Map
        ? p['name_ar']?.toString() ?? 'المهنة'
        : 'المهنة';
    final status = order['status']?.toString() ?? '';
    final offersCount = order['_offers_count'] is num
        ? (order['_offers_count'] as num).toInt()
        : int.tryParse(order['_offers_count']?.toString() ?? '0') ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomerOrderPage(orderId: order['id']),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$profession • طلب #${order['id']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _darkBlue,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'pending') ...[
                        Container(
                          width: 27,
                          height: 27,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$offersCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _status(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (status == 'pending') ...[
                const SizedBox(height: 10),
                Text(
                  'عدد العروض المقدمة: $offersCount',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                order['service_description']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'الموعد: ${_formatRange(order['scheduled_at'], order['scheduled_to'])}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF607D8B)),
              ),
              if (order['selected_offer_id'] != null) ...[
                const SizedBox(height: 6),
                const Text(
                  'تم اختيار فني — راجع الدفع أو حالة التنفيذ.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (status == 'pending' &&
                  order['selected_offer_id'] == null &&
                  !_cancellationRequested.contains(order['id'])) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 112,
                        height: 30,
                        child: OutlinedButton.icon(
                          onPressed: () => _editOrder(order),
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: const Text(
                            'تعديل الطلب',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      SizedBox(
                        width: 112,
                        height: 30,
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelOrder(order),
                          icon: const Icon(Icons.cancel_outlined, size: 14),
                          label: const Text(
                            'إلغاء الطلب',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatRange(dynamic a, dynamic b) {
    final x = _parse(a);
    final y = _parse(b);
    if (x == null) return '—';
    if (y == null) return _format(x);
    return '${_format(x)} — ${_format(y)}';
  }

  DateTime? _parse(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
  String _format(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class CustomerOrderPage extends StatefulWidget {
  const CustomerOrderPage({super.key, required this.orderId});
  final dynamic orderId;
  @override
  State<CustomerOrderPage> createState() => _CustomerOrderPageState();
}

class _CustomerOrderPageState extends State<CustomerOrderPage> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _selecting = false;
  String? _error;
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _offers = [];
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _payment;
  Map<String, dynamic>? _contact;
  Map<String, dynamic>? _inspectionSettlement;
  Timer? _timer;
  RealtimeChannel? _realtimeChannel;
  bool _dataRefreshInProgress = false;
  Timer? _refreshDebounce;
  Duration _selectionRemaining = Duration.zero;
  Duration _reviewRemaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
    _realtimeChannel = _db
        .channel('customer-order-live-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.orderId,
          ),
          callback: (_) => _scheduleLiveRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_technician_offers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: widget.orderId,
          ),
          callback: (_) => _scheduleLiveRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: widget.orderId,
          ),
          callback: (_) => _scheduleLiveRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inspection_settlements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: widget.orderId,
          ),
          callback: (_) => _scheduleLiveRefresh(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _refreshDebounce?.cancel();
    final channel = _realtimeChannel;
    if (channel != null) _db.removeChannel(channel);
    super.dispose();
  }

  void _scheduleLiveRefresh() {
    if (!mounted || _dataRefreshInProgress) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || _dataRefreshInProgress) return;
      _dataRefreshInProgress = true;
      try {
        await _load(silent: true);
      } finally {
        _dataRefreshInProgress = false;
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    try {
      if (!silent && mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
      final order = await _db
          .from('orders')
          .select(
            'id,created_at,profession_id,scheduled_at,scheduled_to,service_description,address,customer_name,secondary_phone,status,payment_status,payment_type,offers_status,customer_total_amount,customer_platform_fee,technician_platform_fee,technician_net_amount,total_price,remaining_amount,selected_offer_id,customer_selected_at,requires_inspection,inspection_deposit_amount,materials_requested,full_payment_confirmed_at,remaining_payment_confirmed_at,contact_released_at,selection_payment_deadline_at,inspection_settlement_mode,professions(name_ar)',
          )
          .eq('id', widget.orderId)
          .maybeSingle();
      if (order == null) {
        throw Exception('الطلب غير موجود أو لم يعد متاحًا.');
      }
      final raw = await _db.rpc(
        'get_customer_order_offers',
        params: {'p_order_id': widget.orderId},
      );
      final list = raw is Map
          ? (raw['offers'] as List? ?? const [])
          : (raw as List? ?? const []);
      _offers = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _order = Map<String, dynamic>.from(order);
      _summary = null;
      _payment = null;
      _contact = null;
      _inspectionSettlement = null;

      if (order['selected_offer_id'] != null) {
        final summary = await _db.rpc(
          'get_order_payment_summary',
          params: {'p_order_id': widget.orderId},
        );
        _summary = Map<String, dynamic>.from(summary as Map);
        final payments = await _db
            .from('payments')
            .select(
              'id,amount,payment_type,status,payment_method,created_at,review_deadline_at,transaction_reference',
            )
            .eq('order_id', widget.orderId)
            .order('created_at', ascending: false)
            .limit(1);
        if (payments.isNotEmpty)
          _payment = Map<String, dynamic>.from(payments.first);
        if (_payment?['status']?.toString() == 'paid') {
          try {
            await _db.rpc(
              'release_order_contact_after_payment',
              params: {'p_payment_id': _payment!['id']},
            );
          } catch (_) {}
        }
        if (order['requires_inspection'] == true ||
            order['inspection_settlement_mode'] != null) {
          try {
            final settlement = await _db
                .from('inspection_settlements')
                .select('*')
                .eq('order_id', widget.orderId)
                .maybeSingle();
            if (settlement != null) {
              _inspectionSettlement = Map<String, dynamic>.from(settlement);
            }
          } catch (_) {}
        }

        if (order['contact_released_at'] != null &&
            order['status']?.toString() != 'completed') {
          try {
            _contact = Map<String, dynamic>.from(
              await _db.rpc(
                    'get_customer_order_contact',
                    params: {'p_order_id': widget.orderId},
                  )
                  as Map,
            );
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() => _loading = false);
      _restartTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    var lastInspectionRefresh = DateTime.fromMillisecondsSinceEpoch(0);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _order == null) return;
      var changed = false;
      final isInspection =
          _order!['requires_inspection'] == true ||
          _order!['inspection_settlement_mode'] != null;
      if (isInspection &&
          DateTime.now().difference(lastInspectionRefresh).inSeconds >= 5) {
        lastInspectionRefresh = DateTime.now();
        try {
          final fresh = await _db
              .from('inspection_settlements')
              .select('*')
              .eq('order_id', widget.orderId)
              .maybeSingle();
          if (fresh != null) {
            final next = Map<String, dynamic>.from(fresh);
            final old = _inspectionSettlement;
            if (old == null ||
                old['updated_at'] != next['updated_at'] ||
                old['labor_price'] != next['labor_price'] ||
                old['settlement_mode'] != next['settlement_mode'] ||
                old['status'] != next['status']) {
              _inspectionSettlement = next;
              changed = true;
            }
          }
        } catch (_) {}
      }
      final deadline = DateTime.tryParse(
        _order!['selection_payment_deadline_at']?.toString() ?? '',
      )?.toLocal();
      if (deadline != null && _order!['contact_released_at'] == null) {
        final d = deadline.difference(DateTime.now());
        _selectionRemaining = d.isNegative ? Duration.zero : d;
        changed = true;
        if (d.isNegative &&
            _order!['selected_offer_id'] != null &&
            _payment?['status'] != 'paid') {
          try {
            await _db.rpc(
              'expire_order_selection',
              params: {'p_order_id': widget.orderId},
            );
          } catch (_) {}
          await _load();
          return;
        }
      }
      final review = DateTime.tryParse(
        _payment?['review_deadline_at']?.toString() ?? '',
      )?.toLocal();
      if (review != null && _payment?['status'] == 'pending') {
        final d = review.difference(DateTime.now());
        _reviewRemaining = d.isNegative ? Duration.zero : d;
        changed = true;
      }
      if (changed && mounted) setState(() {});
    });
  }

  Future<void> _selectOffer(Map<String, dynamic> offer) async {
    if (_selecting) return;
    try {
      setState(() => _selecting = true);
      await _db.rpc(
        'select_order_technician_offer',
        params: {'p_offer_id': offer['id']},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم اختيار العرض. لديك 7 دقائق لإتمام الدفع.'),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_clean(e))));
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  String _clean(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.contains('PGRST116') ||
        text.contains('Cannot coerce the result to a single JSON object') ||
        text.contains('0 rows')) {
      return 'لم يتم العثور على البيانات المطلوبة. يرجى تحديث الصفحة والمحاولة مرة أخرى.';
    }
    if (text.contains('FULL_PAYMENT_NOT_CONFIRMED')) {
      return 'لم يتم تأكيد سداد كامل المبلغ بعد.';
    }
    if (text.contains('ORDER_NOT_FOUND')) {
      return 'الطلب غير موجود أو لم يعد متاحًا.';
    }
    if (text.contains('violates row-level security') ||
        text.contains('permission denied') ||
        text.contains('not authorized')) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }
    if (text.startsWith('PostgrestException')) {
      return 'حدث خطأ أثناء الاتصال بقاعدة البيانات. يرجى المحاولة مرة أخرى.';
    }
    return text.isEmpty ? 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.' : text;
  }

  String _money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (n == null) return '—';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
  }

  String _status(String value) {
    switch (value) {
      case 'pending':
        return 'قيد استقبال العروض';
      case 'accepted':
        return 'تم اختيار الفني';
      case 'on_the_way':
        return 'الفني في الطريق';
      case 'arrived':
        return 'الفني وصل';
      case 'in_progress':
        return 'الخدمة قيد التنفيذ';
      case 'completed':
        return 'تم إنهاء الخدمة';
      case 'cancelled':
        return 'تم إلغاء الطلب';
      default:
        return value.isEmpty ? 'غير محدد' : value;
    }
  }

  DateTime? _parse(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
  String _formatRange(dynamic a, dynamic b) {
    final x = _parse(a);
    final y = _parse(b);
    if (x == null) return '—';
    if (y == null) return _format(x);
    return '${_format(x)} — ${_format(y)}';
  }

  String _format(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _countdown(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _darkBlue,
          elevation: 0,
          title: const Text(
            'متابعة الطلب',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _blue))
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  key: PageStorageKey<String>(
                    'customer-order-${widget.orderId}',
                  ),
                  padding: const EdgeInsets.all(18),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _summaryCard(),
                    const SizedBox(height: 14),
                    _stateCard(),
                    if (_order!['selected_offer_id'] == null) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'العروض المقدمة',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _darkBlue,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_offers.isEmpty) _empty('لم تصل عروض حتى الآن.'),
                      ..._offers.map(_offerCard),
                    ] else ...[
                      const SizedBox(height: 14),
                      _paymentArea(),
                      if (_order!['status']?.toString() == 'completed' &&
                          _order!['inspection_settlement_mode']?.toString() !=
                              'external') ...[
                        const SizedBox(height: 14),
                        _warrantyCard(),
                      ] else if (_contact != null) ...[
                        const SizedBox(height: 14),
                        _contactCard(),
                      ],
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _summaryCard() {
    final o = _order!;
    final p = o['professions'];
    final profession = p is Map
        ? p['name_ar']?.toString() ?? 'المهنة'
        : 'المهنة';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profession,
            style: const TextStyle(fontSize: 12, color: Color(0xFF78909C)),
          ),
          const SizedBox(height: 5),
          Text(
            o['service_description']?.toString() ?? 'الخدمة',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _darkBlue,
            ),
          ),
          const SizedBox(height: 14),
          _info('العميل', o['customer_name']?.toString() ?? '—'),
          _info('الموعد', _formatRange(o['scheduled_at'], o['scheduled_to'])),
          if ((o['problem_description']?.toString() ?? '').trim().isNotEmpty)
            _info('وصف المشكلة', o['problem_description'].toString()),
          _addressDetails(o),
          _info(
            'الخامات',
            o['materials_requested'] == true
                ? 'العميل طلب إمكانية توفير الخامات'
                : 'لا يوجد طلب لتوفير الخامات',
          ),
          _info('الحالة', _status(o['status']?.toString() ?? '')),
        ],
      ),
    );
  }

  Widget _addressDetails(Map<String, dynamic> order) {
    final raw = (order['address'] ?? order['full_address'] ?? '')
        .toString()
        .trim();
    final parts = raw
        .split(RegExp(r'\s*(?:—|–|-)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    String part(int index) => parts.length > index ? parts[index] : 'غير محدد';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'العنوان بالتفصيل',
          style: TextStyle(fontSize: 11, color: Color(0xFF78909C)),
        ),
        const SizedBox(height: 4),
        _info('الحي', part(0)),
        _info('الشارع', part(1)),
        _info('العمارة أو البلوك', part(2)),
        _info('الدور', part(3)),
        _info(
          'الشقة',
          parts.length > 4 ? parts.sublist(4).join(' — ') : 'غير محدد',
        ),
      ],
    );
  }

  Widget _stateCard() {
    final o = _order!;
    String text;
    if (o['status'] == 'completed' &&
        o['inspection_settlement_mode']?.toString() == 'external')
      text =
          'تم إكمال الطلب بعد الاتفاق بالتراضي خارج التطبيق. لا يشمل هذا الاتفاق ضمان المنصة.';
    else if (o['status'] == 'completed')
      text = 'تم إكمال الطلب بنجاح.';
    else if (o['status'] == 'cancelled' &&
        o['inspection_settlement_mode']?.toString() == 'no_agreement')
      text =
          'لم يتم الاتفاق بعد المعاينة. ستراجع الإدارة التسوية وتبلغك بتفاصيل المبلغ المسترد.';
    else if (o['status'] == 'cancelled')
      text = 'تم إلغاء الطلب.';
    else if (o['contact_released_at'] != null)
      text = 'تم تأكيد الدفع وفتح بيانات التواصل. تابع التنفيذ من نفس الطلب.';
    else if (o['selected_offer_id'] != null)
      text = 'تم اختيار الفني. أكمل خطوة الدفع لفتح التواصل.';
    else if (o['offers_status'] == 'open')
      text = 'جاري استقبال عروض الفنيين المناسبين لطلبك.';
    else
      text = 'انتهت جلسة استقبال العروض لهذا الطلب.';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F6FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.track_changes_outlined, color: _blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _darkBlue,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerCard(Map<String, dynamic> offer) {
    final tech = offer['technician'];
    final t = tech is Map
        ? Map<String, dynamic>.from(tech)
        : <String, dynamic>{};
    final name = t['full_name']?.toString() ?? 'صنايعي';
    final labor = _money(offer['labor_price']);
    final total = _money(offer['total_offer_price']);
    final inspection = offer['requires_inspection'] == true;
    final same = offer['availability_matches_customer_window'] == true;
    final revision = offer['revision_count']?.toString() ?? '0';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F6FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.person_outline, color: _blue, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _darkBlue,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'التقييم ${_money(t['rating'])} • ${t['years_experience']?.toString() ?? '0'} سنة خبرة',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF607D8B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          inspection
              ? const Text(
                  'المصنعية تحدد بعد المعاينة.',
                  style: TextStyle(
                    color: Color(0xFFB8860B),
                    fontWeight: FontWeight.w800,
                  ),
                )
              : Text(
                  'المصنعية: $labor جنيه',
                  style: const TextStyle(
                    fontSize: 15,
                    color: _blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
          if (!inspection)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'إجمالي المصنعية في العرض: $total جنيه',
                style: const TextStyle(fontSize: 12, color: Color(0xFF455A64)),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: same
                  ? Colors.green.withValues(alpha: .08)
                  : const Color(0xFFF5FAFD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  same ? Icons.check_circle_outline : Icons.schedule_outlined,
                  size: 19,
                  color: same ? Colors.green : const Color(0xFF607D8B),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    same
                        ? 'متوفر في نفس الموعد الذي حدده العميل'
                        : 'الفني قدم موعدًا بديلًا: ${_formatRange(offer['technician_available_from'], offer['technician_available_to'])}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: same
                          ? Colors.green.shade700
                          : const Color(0xFF607D8B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (offer['supplies_provided'] == true) ...[
            const SizedBox(height: 8),
            Text(
              'الفني يستطيع توفير الخامات. التكلفة الفعلية + 3% مقابل التوفير (بحد أدنى 15 جنيه).',
              style: const TextStyle(fontSize: 12, color: Color(0xFF455A64)),
            ),
          ],
          if (offer['response_note']?.toString().trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                offer['response_note'].toString(),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF455A64),
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _selecting ? null : () => _selectOffer(offer),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text(
                'اختيار هذا العرض',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentArea() {
    if (_summary == null) return const SizedBox.shrink();
    if (_order?['status']?.toString() == 'completed' ||
        _order?['status']?.toString() == 'cancelled') {
      return const SizedBox.shrink();
    }
    final inspection = _summary!['requires_inspection'] == true;
    if (inspection && _contact != null) return _inspectionSettlementCard();
    final remaining =
        double.tryParse(_summary!['remaining_amount']?.toString() ?? '') ?? 0;
    final paymentStatus = _payment?['status']?.toString();
    if (paymentStatus == 'pending') return _pendingPaymentCard();
    if (paymentStatus == 'paid' && remaining <= 0) {
      return _card(
        child: const Text(
          'تم تأكيد الدفع. يمكنك متابعة حالة تنفيذ الخدمة من تفاصيل الطلب.',
          style: TextStyle(fontWeight: FontWeight.w800, color: _darkBlue),
        ),
      );
    }
    if (_contact != null && remaining <= 0) return const SizedBox.shrink();
    final remainingPayment =
        _contact != null &&
        _order?['payment_type']?.toString() == 'remaining_payment' &&
        remaining > 0;
    return _PaymentCard(
      summary: _summary!,
      inspection: inspection,
      remainingPayment: remainingPayment,
      selectionRemaining: _selectionRemaining,
      onSubmitted: _load,
    );
  }

  Widget _inspectionSettlementCard() {
    final s = _inspectionSettlement;
    final labor = double.tryParse(s?['labor_price']?.toString() ?? '') ?? 0;
    final mode = s?['settlement_mode']?.toString() ?? 'pending';
    final status = s?['status']?.toString() ?? 'pending';

    Future<void> act(String rpc, {String? success}) async {
      try {
        await _db.rpc(rpc, params: {'p_order_id': widget.orderId});
        if (!mounted) return;
        if (success != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(success)));
        }
        await _load();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_clean(e))));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تسوية المصنعية بعد المعاينة',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: _darkBlue,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'المبلغ المدفوع تحت الحساب: 100 جنيه',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              if (s == null) ...[
                const Text(
                  'تم فتح التواصل. في انتظار الفني لإدخال قيمة المصنعية بعد المعاينة.',
                  style: TextStyle(height: 1.5, fontWeight: FontWeight.w700),
                ),
              ] else if (mode == 'pending' && labor <= 0) ...[
                const Text(
                  'الفني يقوم الآن بالمعاينة. بعد المعاينة سيظهر هنا سعر المصنعية للموافقة.',
                  style: TextStyle(height: 1.5, fontWeight: FontWeight.w700),
                ),
              ] else if (mode == 'pending' && labor > 0) ...[
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'المصنعية التي حددها الفني بعد المعاينة',
                        style: TextStyle(
                          color: _darkBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_money(labor)} جنيه',
                        style: const TextStyle(
                          color: _blue,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'إذا وافقت داخل التطبيق، تُحسب رسوم المنصة على الطرفين وتستمر في مسار الدفع العادي، ويظل ضمان المنصة لمدة 30 يومًا سارياً.',
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => act(
                    'customer_approve_inspection_labor',
                    success:
                        'تمت الموافقة على المصنعية واستكمال مسار الدفع داخل التطبيق.',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'موافقة على المصنعية واستكمال الطلب',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('عدم الاتفاق'),
                        content: const Text(
                          'إذا لم يتم الاتفاق بعد المعاينة، ستراجع الإدارة الحالة وتبلغك بتفاصيل المبلغ المسترد.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('تأكيد عدم الاتفاق'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true)
                      await act(
                        'customer_decline_inspection_agreement',
                        success: 'تم تسجيل عدم الاتفاق وإرسال التسوية للإدارة.',
                      );
                  },
                  child: const Text(
                    'لم يتم الاتفاق',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ] else if (mode == 'external') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF8EF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFB9E4C8)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تم دفع 100 جنيه.',
                        style: TextStyle(
                          color: Color(0xFF168447),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'رسوم المنصة: 7% من المبلغ، بحد أدنى 15 جنيهًا.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'المتبقي للفني: 85 جنيهًا.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF168447),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'سيتم تحويل المبلغ المتبقي للفني تلقائيًا.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '⚠️ الاتفاق خارج التطبيق ولا يشمله ضمان المنصة.',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                if (status == 'awaiting_admin')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'التسوية مسجلة وبانتظار اعتماد الإدارة.',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ] else if (mode == 'no_agreement') ...[
                const Text(
                  'تم تسجيل عدم الاتفاق بعد المعاينة.',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'ستراجع الإدارة طلب الاسترداد وتبلغك بالمبلغ المسترد بعد اعتماد التسوية.',
                  style: TextStyle(height: 1.5, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _inspectionChat() {
    return FutureBuilder<List<dynamic>>(
      future: _db
          .rpc(
            'inspection_list_messages',
            params: {'p_order_id': widget.orderId},
          )
          .then((v) => (v as List?) ?? const []),
      builder: (context, snap) {
        final messages = snap.data ?? const [];
        return StatefulBuilder(
          builder: (context, setLocal) {
            final controller = TextEditingController();
            return _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'محادثة المعاينة',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _darkBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (messages.isEmpty)
                    const Text(
                      'ابدأ المحادثة لتوضيح تفاصيل المعاينة والاتفاق على المصنعية.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF607D8B)),
                    ),
                  if (messages.isNotEmpty)
                    ...messages.take(20).map((m) {
                      final x = Map<String, dynamic>.from(m as Map);
                      final mine = x['sender_type'] == 'customer';
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFFE8F6FF)
                                : const Color(0xFFF1F5F7),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(x['body']?.toString() ?? ''),
                        ),
                      );
                    }),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالة...',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      IconButton(
                        onPressed: () async {
                          final b = controller.text.trim();
                          if (b.isEmpty) return;
                          try {
                            await _db.rpc(
                              'inspection_send_message',
                              params: {
                                'p_order_id': widget.orderId,
                                'p_body': b,
                              },
                            );
                            controller.clear();
                            setLocal(() {});
                            await _load();
                          } catch (e) {
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(_clean(e))),
                              );
                          }
                        },
                        icon: const Icon(Icons.send, color: _blue),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _pendingPaymentCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'جاري مراجعة الدفع من الإدارة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _darkBlue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'سيتم مراجعة إثبات الدفع خلال المهلة المحددة. المتبقي من مهلة المراجعة: ${_countdown(_reviewRemaining)}',
          style: const TextStyle(color: Color(0xFF607D8B), height: 1.5),
        ),
        const SizedBox(height: 12),
        const Text(
          'بعد تأكيد الإدارة يتم فتح بيانات التواصل مع الفني تلقائيًا.',
          style: TextStyle(fontWeight: FontWeight.w700, color: _darkBlue),
        ),
      ],
    ),
  );

  Widget _warrantyCard() {
    const phone = '01505013234';
    final whatsappUri = Uri.parse(
      'https://wa.me/201505013234?text=${Uri.encodeComponent('مرحبًا، أريد الاستفسار أو طلب الضمان على مصنعية الخدمة.')}',
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFA8E0BC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: Color(0xFF159447),
                size: 27,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'ضمان المنصة',
                  style: TextStyle(
                    color: Color(0xFF0D6B32),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'تمنحك المنصة ضمانًا لمدة 30 يومًا على مصنعية الخدمة المقدمة.',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Color(0xFF0D6B32),
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'للاستفسار وطلب الضمان:',
            style: TextStyle(
              color: Color(0xFF45615A),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Expanded(
                child: Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: Color(0xFF087F3F),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    if (await canLaunchUrl(whatsappUri)) {
                      await launchUrl(
                        whatsappUri,
                        mode: LaunchMode.externalApplication,
                      );
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تعذر فتح واتساب على هذا الجهاز.'),
                        ),
                      );
                    }
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تعذر فتح واتساب حاليًا.'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.chat, size: 19),
                label: const Text(
                  'واتساب',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF159447),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactCard() {
    final c = _contact!;
    final phone = c['phone']?.toString() ?? '—';
    final wa = c['whatsapp_phone']?.toString();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'بيانات الفني بعد تأكيد الدفع',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _darkBlue,
            ),
          ),
          const SizedBox(height: 12),
          _info('اسم الفني', c['full_name']?.toString() ?? '—'),
          _info('الهاتف', phone),
          if (wa != null && wa.trim().isNotEmpty) _info('WhatsApp', wa),
          const SizedBox(height: 4),
          const Text(
            'سيتم التواصل معك من خلال الفني وتأكيد الموعد.',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: child,
  );
  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF78909C)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF263238),
          ),
        ),
      ],
    ),
  );
}

class _PaymentCard extends StatefulWidget {
  const _PaymentCard({
    required this.summary,
    required this.inspection,
    required this.remainingPayment,
    required this.selectionRemaining,
    required this.onSubmitted,
  });
  final Map<String, dynamic> summary;
  final bool inspection;
  final bool remainingPayment;
  final Duration selectionRemaining;
  final Future<void> Function() onSubmitted;
  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  final _db = Supabase.instance.client;
  String _method = 'instapay';
  bool _saving = false;

  String _money(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    if (n == null) return '—';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);
  }

  double _amount() {
    if (widget.inspection) {
      return double.tryParse(
            widget.summary['inspection_deposit']?.toString() ?? '100',
          ) ??
          100;
    }
    if (widget.remainingPayment) {
      return double.tryParse(
            widget.summary['remaining_amount']?.toString() ?? '0',
          ) ??
          0;
    }
    // الدفع الجزئي ملغى للخدمات ذات السعر المحدد؛ يتم سداد الإجمالي كاملًا.
    return double.tryParse(widget.summary['full_total']?.toString() ?? '0') ??
        0;
  }

  Future<void> _submit() async {
    final amount = _amount();
    if (amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('قيمة الدفع غير صالحة.')));
      return;
    }
    try {
      setState(() => _saving = true);
      await _db.rpc(
        'submit_customer_payment_notice',
        params: {
          'p_order_id': widget.summary['order_id'],
          'p_payment_type': widget.inspection
              ? 'inspection_fee'
              : (widget.remainingPayment
                    ? 'remaining_payment'
                    : 'full_payment'),
          'p_amount': amount,
          'p_payment_method': _method,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل إشعار الدفع. جاري مراجعة الإدارة.'),
        ),
      );
      await widget.onSubmitted();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Color(0xFF607D8B))),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: _darkBlue,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final full =
        double.tryParse(widget.summary['full_total']?.toString() ?? '0') ?? 0;
    final labor =
        double.tryParse(widget.summary['labor_amount']?.toString() ?? '0') ?? 0;
    final customerFee =
        double.tryParse(widget.summary['full_fee']?.toString() ?? '') ??
        (labor * 0.07 < 15 ? 15 : labor * 0.07);
    final materials =
        double.tryParse(
          widget.summary['materials_amount']?.toString() ?? '0',
        ) ??
        0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.remainingPayment
                ? 'سداد المتبقي بعد المعاينة'
                : 'إتمام الطلب وفتح التواصل',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: _darkBlue,
            ),
          ),
          if (!widget.remainingPayment) ...[
            const SizedBox(height: 6),
            Text(
              'المهلة المتبقية للاختيار والدفع: ${widget.selectionRemaining.inMinutes.toString().padLeft(2, '0')}:${widget.selectionRemaining.inSeconds.remainder(60).toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (widget.inspection) ...[
            const Text(
              'معاينة',
              style: TextStyle(fontWeight: FontWeight.w800, color: _darkBlue),
            ),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF8EF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF8BD4A6)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الدفع المطلوب تحت الحساب: 100 جنيه',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Color(0xFF168447),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'ننصحك بإتمام الاتفاق داخل التطبيق؛ فهو الخيار الأكثر أمانًا لك. يحدد الفني قيمة المصنعية بعد المعاينة، وتوافق عليها داخل التطبيق، ثم تستكمل الدفع من خلال المنصة مع ضمانها ومتابعتها للطلب.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Color(0xFF126B39),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.6,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'الاتفاق خارج التطبيق لا يشمله ضمان المنصة. وإذا لم يتم الاتفاق، ستراجع الإدارة التسوية وتبلغك بتفاصيل المبلغ المسترد.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Color(0xFF456B55),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (widget.remainingPayment) ...[
            _info('قيمة المصنعية', '${_money(labor)} جنيه'),
            _info(
              'رسوم العميل حسب إعدادات المنصة',
              '${_money(customerFee)} جنيه',
            ),
            _info('إجمالي المستحق', '${_money(full)} جنيه'),
            _info(
              'المعاينة المدفوعة والمسجلة',
              '${_money(widget.summary['paid_amount'])} جنيه',
            ),
            const Divider(height: 20),
            Text(
              'المبلغ المتبقي المطلوب: ${_money(_amount())} جنيه',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: _blue,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'تم خصم مبلغ المعاينة المسجل مرة واحدة فقط. إرسال الإشعار لا يؤكد السداد؛ تنتظر الدفعة مراجعة الإدارة.',
              style: TextStyle(
                color: Color(0xFF607D8B),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ] else ...[
            _info('قيمة المصنعية', '${_money(labor)} جنيه'),
            const Text(
              'إذا تم توفير الخامات من قبل الفني، يتم سداد تكلفتها طبقًا لشروط توفير الخامات.',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Color(0xFF607D8B),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (materials > 0)
              _info(
                'تكلفة الخامات والتوريد حسب العرض',
                '${_money(materials)} جنيه',
              ),
            _info('رسوم المنصة على العميل', '${_money(customerFee)} جنيه'),
            const Divider(height: 20),
            Text(
              'إجمالي المبلغ المطلوب قبل الدفع: ${_money(full)} جنيه',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: _blue,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(
              labelText: 'طريقة الدفع',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'instapay', child: Text('InstaPay')),
              DropdownMenuItem(value: 'wallet', child: Text('محفظة إلكترونية')),
            ],
            onChanged: (v) => setState(() => _method = v!),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F8FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'بيانات الدفع',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _darkBlue,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'InstaPay',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  '01069897758',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                const Text('احمد ع**ا***** ع**ا*****'),
                const Divider(height: 22),
                const Text(
                  'المحفظة الإلكترونية',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  '01505013234',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                const Text('احمد ع******* ع**ا*****'),
                const SizedBox(height: 10),
                const Text(
                  'بعد التحويل اضغط تأكيد الدفع ليتم فتح مراجعة الإدارة لمدة 15 دقيقة.',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.inspection
                          ? 'تم دفع رسوم المعاينة'
                          : (widget.remainingPayment
                                ? 'تم سداد المتبقي — إرسال للمراجعة'
                                : 'تم الدفع — إرسال للمراجعة'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _card({required Widget child}) => Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: _border),
  ),
  child: child,
);
Widget _errorCard(String text) => Container(
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.red.shade50,
    borderRadius: BorderRadius.circular(14),
  ),
  child: Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
  ),
);
Widget _empty(String text) => Container(
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.all(26),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
  ),
  child: Text(text, textAlign: TextAlign.center),
);
