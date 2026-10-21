import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'craftsman_orders_page.dart';
import '../auth/account_type_page.dart';

class CraftsmanHomePage extends StatefulWidget {
  const CraftsmanHomePage({super.key});

  @override
  State<CraftsmanHomePage> createState() => _CraftsmanHomePageState();
}

class _CraftsmanHomePageState extends State<CraftsmanHomePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  int? _technicianId;
  int _newOrdersCount = 0;

  String _name = 'الفني';
  String _phone = '';
  String _phone2 = '';
  String _phone3 = '';
  String _whatsappPhone = '';
  String _whatsappPhone2 = '';
  String _contactEmail = '';
  String _address = '';
  int? _cityId;
  int _yearsExperience = 0;
  String _description = '';
  bool _isAvailable = true;
  String _transportationType = '';
  String _status = 'قيد المراجعة';
  String? _profileImage;
  String _nationalIdNumber = '';
  String? _nationalIdImage;

  List<int> _professionIds = [];
  List<String> _professions = [];
  List<int> _areaIds = [];
  List<String> _areaNames = [];
  List<String> _experienceRanges = [];
  List<String> _transportationTypes = [];
  List<Map<String, dynamic>> _payoutMethods = [];
  List<Map<String, dynamic>> _technicianPayouts = [];
  RealtimeChannel? _homeOrdersChannel;
  Timer? _badgeRefreshDebounce;
  bool _profileLoadInProgress = false;
  bool _hasOrderBaseline = false;
  final Set<String> _unreadOrderIds = <String>{};
  final Map<String, String> _orderSignatures = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadCraftsman();
    _subscribeToHomeOrderChanges();
  }

  void _subscribeToHomeOrderChanges() {
    final userId = _supabase.auth.currentUser?.id ?? 'guest';
    _homeOrdersChannel = _supabase.channel('craftsman-home-orders-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        callback: (_) => _scheduleBadgeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'order_technician_offers',
        callback: (_) => _scheduleBadgeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'inspection_settlements',
        callback: (_) => _scheduleBadgeRefresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'order_technician_payouts',
        callback: (_) => _scheduleBadgeRefresh(),
      )
      ..subscribe();
  }

  void _scheduleBadgeRefresh() {
    if (!mounted) return;
    _badgeRefreshDebounce?.cancel();
    _badgeRefreshDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      await _loadNewOrdersCount();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _badgeRefreshDebounce?.cancel();
    final channel = _homeOrdersChannel;
    if (channel != null) _supabase.removeChannel(channel);
    super.dispose();
  }

  Future<void> _loadCraftsman() async {
    if (_profileLoadInProgress) return;
    _profileLoadInProgress = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        _setError('لا يوجد حساب فني مسجل الدخول');
        return;
      }

      final rawProfile = await _supabase.rpc('get_my_technician_profile');

      if (rawProfile is! Map) {
        _setError('تعذر قراءة بيانات الفني من قاعدة البيانات.');
        return;
      }

      final profile = Map<String, dynamic>.from(rawProfile);

      if (profile['found'] != true) {
        _setError('تم تسجيل الدخول بحساب Auth، لكن الحساب غير مرتبط بسجل فني.');
        return;
      }

      _applyProfile(profile);

      await _loadNewOrdersCount();

      if (_technicianId != null) {
        try {
          await _loadTechnicianPayouts(_technicianId!);
        } catch (_) {
          _technicianPayouts = [];
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } on PostgrestException catch (e) {
      _setError('خطأ من قاعدة البيانات: ${e.message}');
    } catch (e) {
      _setError('تعذر تحميل بيانات الفني: $e');
    } finally {
      _profileLoadInProgress = false;
    }
  }

  void _applyProfile(Map<String, dynamic> profile) {
    _technicianId = _toInt(profile['technician_id']);
    _name = _cleanString(profile['full_name']).isNotEmpty
        ? _cleanString(profile['full_name'])
        : 'الفني';
    _phone = _cleanString(profile['phone']);
    _phone2 = _cleanString(profile['phone2']);
    _phone3 = _cleanString(profile['phone3']);
    _whatsappPhone = _cleanString(profile['whatsapp_phone']);
    _whatsappPhone2 = _cleanString(profile['whatsapp_phone2']);
    _contactEmail = _cleanString(profile['contact_email']);
    _address = _cleanString(profile['address']);
    _cityId = _toInt(profile['city_id']);
    _yearsExperience = _toInt(profile['years_experience']) ?? 0;
    _description = _cleanString(profile['description']);
    _isAvailable = profile['is_available'] != false;
    _transportationType = _cleanString(profile['transportation_type']);
    _profileImage = _cleanString(profile['profile_image']).isEmpty
        ? null
        : _cleanString(profile['profile_image']);
    _nationalIdNumber = _cleanString(profile['national_id_number']);
    _nationalIdImage = _cleanString(profile['national_id_image']).isEmpty
        ? null
        : _cleanString(profile['national_id_image']);

    final applicationStatus = _cleanString(profile['application_status']);
    final accountStatus = _cleanString(profile['account_status']);

    if (applicationStatus.isNotEmpty) {
      _status = _translateApplicationStatus(applicationStatus);
    } else if (accountStatus.isNotEmpty) {
      _status = _translateAccountStatus(accountStatus);
    }

    _professionIds = _extractIds(profile['professions'], 'profession_id');
    _professions = _extractNames(profile['professions'], 'name_ar');
    _areaIds = _extractIds(profile['areas'], 'area_id');
    _areaNames = _extractNames(profile['areas'], 'name_ar');
    _experienceRanges = _extractStrings(
      profile['experience_ranges'],
      'experience_range',
    );
    _transportationTypes = _extractStrings(
      profile['transportation_types'],
      'transportation_type',
    );
    _payoutMethods = _extractMaps(profile['payout_methods']);
  }

  Future<void> _loadNewOrdersCount() async {
    try {
      final result = await _supabase.rpc('get_technician_order_feed_v3');
      final orders = (result as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final currentKeys = <String>{};
      const trackedFields = <String>[
        'status',
        'offer_status',
        'offer_id',
        'selected_offer_id',
        'revision_count',
        'contact_released_at',
        'payment_status',
        'remaining_amount',
        'customer_notice_pending',
        'customer_notice_pending_at',
        'admin_completion_payment_confirmed_at',
        'scheduled_at',
        'scheduled_to',
        'total_offer_price',
        'labor_price',
        'response_note',
        'inspection_settlement_mode',
      ];
      for (final order in orders) {
        final id = (order['order_id'] ?? order['id'] ?? '').toString();
        if (id.isEmpty) continue;
        currentKeys.add(id);
        final signature = trackedFields
            .map((field) => '$field=${order[field]}')
            .join('|');
        final previous = _orderSignatures[id];
        if (_hasOrderBaseline && (previous == null || previous != signature)) {
          _unreadOrderIds.add(id);
        }
        _orderSignatures[id] = signature;
      }
      if (_hasOrderBaseline) {
        // A feed entry disappearing (e.g. an offer/state change) is not itself
        // a new notification. Keep unread IDs only while they remain relevant.
        _unreadOrderIds.removeWhere((id) => !currentKeys.contains(id));
      }
      _hasOrderBaseline = true;
      _newOrdersCount = _unreadOrderIds.length;
    } catch (_) {
      // Keep the last known badge during a transient network/RPC failure.
    }
  }

  Future<void> _loadTechnicianPayouts(int technicianId) async {
    final result = await _supabase
        .from('order_technician_payouts')
        .select('''
          id,
          order_id,
          technician_id,
          amount,
          status,
          ready_at,
          paid_at,
          payment_reference,
          notes,
          created_at,
          orders (
            id,
            service_id,
            completed_at,
            services (
              service_name
            )
          )
        ''')
        .eq('technician_id', technicianId)
        .order('ready_at', ascending: false);

    _technicianPayouts = result
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _openPayouts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CraftsmanPayoutsPage(payouts: _technicianPayouts),
      ),
    );
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Future<void> _logout() async {
    try {
      await _supabase.auth.signOut();
    } finally {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountTypePage()),
        (route) => false,
      );
    }
  }

  Future<void> _openProfile() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CraftsmanProfilePage(
          name: _name,
          phone: _phone,
          phone2: _phone2,
          phone3: _phone3,
          whatsappPhone: _whatsappPhone,
          whatsappPhone2: _whatsappPhone2,
          contactEmail: _contactEmail,
          address: _address,
          cityId: _cityId,
          yearsExperience: _yearsExperience,
          description: _description,
          isAvailable: _isAvailable,
          transportationType: _transportationType,
          status: _status,
          profileImage: _profileImage,
          nationalIdNumber: _nationalIdNumber,
          nationalIdImage: _nationalIdImage,
          professionIds: _professionIds,
          professions: _professions,
          areaIds: _areaIds,
          areaNames: _areaNames,
          experienceRanges: _experienceRanges,
          transportationTypes: _transportationTypes,
          payoutMethods: _payoutMethods,
        ),
      ),
    );

    if (changed == true) {
      await _loadCraftsman();
    }
  }

  Future<void> _openSupport() async {
    const phone = '01505013234';
    final uri = Uri.parse(
      'https://wa.me/201505013234?text=${Uri.encodeComponent('مرحبًا، أحتاج إلى المساعدة والدعم الفني من صنايعي بصفتي فنيًا.')}',
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.support_agent_outlined, color: Color(0xFF087FD0)),
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5FAFD),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF073A68),
          centerTitle: true,
          title: const Text(
            'حساب الفني',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث البيانات',
              onPressed: _loading ? null : _loadCraftsman,
              icon: const Icon(Icons.refresh_rounded),
            ),
            TextButton.icon(
              onPressed: _openSupport,
              icon: const Icon(Icons.support_agent_outlined, size: 20),
              label: const Text(
                'المساعدة والدعم الفني',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF073A68),
              ),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF0787D1)),
              )
            : RefreshIndicator(
                onRefresh: _loadCraftsman,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(18),
                  children: [
                    _buildHadithCard(),
                    const SizedBox(height: 14),
                    _buildWelcome(),
                    const SizedBox(height: 22),
                    _HomeActionCard(
                      icon: Icons.assignment_outlined,
                      title: 'طلباتي',
                      subtitle: 'عرض كل الطلبات الخاصة بك ومتابعتها',
                      badge: _newOrdersCount > 0 ? _newOrdersCount : null,
                      onTap: () {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => const CraftsmanOrdersPage(),
                              ),
                            )
                            .then((_) async {
                              _unreadOrderIds.clear();
                              _newOrdersCount = 0;
                              await _loadNewOrdersCount();
                              if (mounted) setState(() {});
                            });
                      },
                    ),
                    const SizedBox(height: 12),
                    _HomeActionCard(
                      icon: Icons.person_outline,
                      title: 'الملف الشخصي',
                      subtitle:
                          'عرض وتعديل بياناتك الشخصية والمهنية وبيانات التحصيل',
                      onTap: _openProfile,
                    ),
                    const SizedBox(height: 12),
                    _HomeActionCard(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'المستحقات',
                      subtitle: 'عرض مستحقاتك وحالتها وتفاصيل التحصيل',
                      onTap: _openPayouts,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),
                    const Text(
                      'صنايعي',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF78909C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 15),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHadithCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8D9A8)),
      ),
      child: const Column(
        children: [
          Text(
            'قال رسول الله صلي الله عليه وسلم',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF073A68),
            ),
          ),
          SizedBox(height: 10),
          Text(
            '"إِنَّ اللَّهَ يُحِبُّ إِذَا عَمِلَ أَحَدُكُمْ عَمَلًا أَنْ يُتْقِنَهُ"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              height: 1.7,
              fontWeight: FontWeight.w900,
              color: Color(0xFF073A68),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'أهلاً بيك يا $_name 👋',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF073A68),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'نتمنى لك يومًا موفقًا مع صنايعي',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF607D8B)),
          ),
        ],
      ),
    );
  }

  String _cleanString(dynamic value) => value?.toString().trim() ?? '';

  int? _toInt(dynamic value) => int.tryParse(value?.toString() ?? '');

  List<Map<String, dynamic>> _extractMaps(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<int> _extractIds(dynamic raw, String key) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _toInt(e[key]))
        .whereType<int>()
        .toList();
  }

  List<String> _extractNames(dynamic raw, String key) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => _cleanString(e[key]))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _extractStrings(dynamic raw, String key) =>
      _extractNames(raw, key);

  String _translateApplicationStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'قيد المراجعة';
      case 'approved':
        return 'تم قبول الحساب';
      case 'rejected':
        return 'تم رفض الطلب';
      case 'active':
        return 'الحساب مفعل';
      case 'blocked':
      case 'suspended':
      case 'banned':
        return 'الحساب موقوف';
      default:
        return status;
    }
  }

  String _translateAccountStatus(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'الحساب مفعل';
      case 'approved':
        return 'تم قبول الحساب';
      case 'blocked':
      case 'suspended':
      case 'banned':
        return 'الحساب موقوف';
      default:
        return status;
    }
  }
}

class CraftsmanProfilePage extends StatefulWidget {
  const CraftsmanProfilePage({
    super.key,
    required this.name,
    required this.phone,
    required this.phone2,
    required this.phone3,
    required this.whatsappPhone,
    required this.whatsappPhone2,
    required this.contactEmail,
    required this.address,
    required this.cityId,
    required this.yearsExperience,
    required this.description,
    required this.isAvailable,
    required this.transportationType,
    required this.status,
    required this.profileImage,
    required this.nationalIdNumber,
    required this.nationalIdImage,
    required this.professionIds,
    required this.professions,
    required this.areaIds,
    required this.areaNames,
    required this.experienceRanges,
    required this.transportationTypes,
    required this.payoutMethods,
  });

  final String name;
  final String phone;
  final String phone2;
  final String phone3;
  final String whatsappPhone;
  final String whatsappPhone2;
  final String contactEmail;
  final String address;
  final int? cityId;
  final int yearsExperience;
  final String description;
  final bool isAvailable;
  final String transportationType;
  final String status;
  final String? profileImage;
  final String nationalIdNumber;
  final String? nationalIdImage;
  final List<int> professionIds;
  final List<String> professions;
  final List<int> areaIds;
  final List<String> areaNames;
  final List<String> experienceRanges;
  final List<String> transportationTypes;
  final List<Map<String, dynamic>> payoutMethods;

  @override
  State<CraftsmanProfilePage> createState() => _CraftsmanProfilePageState();
}

class _CraftsmanProfilePageState extends State<CraftsmanProfilePage> {
  late String name;
  late String phone;
  late String phone2;
  late String phone3;
  late String whatsappPhone;
  late String whatsappPhone2;
  late String contactEmail;
  late String address;
  late int? cityId;
  late int yearsExperience;
  late String description;
  late bool isAvailable;
  late String transportationType;
  late String status;
  late String? profileImage;
  late String nationalIdNumber;
  late String? nationalIdImage;
  late List<int> professionIds;
  late List<String> professions;
  late List<int> areaIds;
  late List<String> areaNames;
  late List<String> experienceRanges;
  late List<String> transportationTypes;
  late List<Map<String, dynamic>> payoutMethods;

  @override
  void initState() {
    super.initState();
    _copyFromWidget();
  }

  void _copyFromWidget() {
    name = widget.name;
    phone = widget.phone;
    phone2 = widget.phone2;
    phone3 = widget.phone3;
    whatsappPhone = widget.whatsappPhone;
    whatsappPhone2 = widget.whatsappPhone2;
    contactEmail = widget.contactEmail;
    address = widget.address;
    cityId = widget.cityId;
    yearsExperience = widget.yearsExperience;
    description = widget.description;
    isAvailable = widget.isAvailable;
    transportationType = widget.transportationType;
    status = widget.status;
    profileImage = widget.profileImage;
    nationalIdNumber = widget.nationalIdNumber;
    nationalIdImage = widget.nationalIdImage;
    professionIds = [...widget.professionIds];
    professions = [...widget.professions];
    areaIds = [...widget.areaIds];
    areaNames = [...widget.areaNames];
    experienceRanges = [...widget.experienceRanges];
    transportationTypes = [...widget.transportationTypes];
    payoutMethods = widget.payoutMethods
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _editProfile() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CraftsmanEditProfilePage(
          name: name,
          phone: phone,
          phone2: phone2,
          phone3: phone3,
          whatsappPhone: whatsappPhone,
          whatsappPhone2: whatsappPhone2,
          contactEmail: contactEmail,
          address: address,
          cityId: cityId,
          yearsExperience: yearsExperience,
          description: description,
          isAvailable: isAvailable,
          transportationType: transportationType,
          profileImage: profileImage,
          professionIds: professionIds,
          areaIds: areaIds,
          experienceRanges: experienceRanges,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _reloadOwnProfile();
    }
  }

  Future<void> _reloadOwnProfile() async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'get_my_technician_profile',
      );
      if (raw is! Map || raw['found'] != true) return;
      final p = Map<String, dynamic>.from(raw);
      if (!mounted) return;
      setState(() {
        name = _s(p['full_name'], 'الفني');
        phone = _s(p['phone']);
        phone2 = _s(p['phone2']);
        phone3 = _s(p['phone3']);
        whatsappPhone = _s(p['whatsapp_phone']);
        whatsappPhone2 = _s(p['whatsapp_phone2']);
        contactEmail = _s(p['contact_email']);
        address = _s(p['address']);
        cityId = _i(p['city_id']);
        yearsExperience = _i(p['years_experience']) ?? 0;
        description = _s(p['description']);
        isAvailable = p['is_available'] != false;
        transportationType = _s(p['transportation_type']);
        profileImage = _s(p['profile_image']).isEmpty
            ? null
            : _s(p['profile_image']);
        nationalIdNumber = _s(p['national_id_number']);
        nationalIdImage = _s(p['national_id_image']).isEmpty
            ? null
            : _s(p['national_id_image']);
        professionIds = _ids(p['professions'], 'profession_id');
        professions = _names(p['professions'], 'name_ar');
        areaIds = _ids(p['areas'], 'area_id');
        areaNames = _names(p['areas'], 'name_ar');
        experienceRanges = _strings(p['experience_ranges'], 'experience_range');
        transportationTypes = _strings(
          p['transportation_types'],
          'transportation_type',
        );
        payoutMethods = _maps(p['payout_methods']);
      });
    } catch (_) {
      // لا نغلق الصفحة إذا فشل التحديث؛ البيانات القديمة تظل ظاهرة.
    }
  }

  Future<void> _editPayout() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CraftsmanPayoutEditPage(methods: payoutMethods),
      ),
    );
    if (changed == true) {
      await _reloadOwnProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5FAFD),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF073A68),
          centerTitle: true,
          title: const Text(
            'الملف الشخصي',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: 'تعديل البيانات',
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.center,
              child: FilledButton.icon(
                onPressed: _editProfile,
                icon: const Icon(Icons.edit),
                label: const Text('تعديل بيانات الملف'),
              ),
            ),
            const SizedBox(height: 18),
            _SectionCard(
              title: 'المهنة / المهن',
              icon: Icons.engineering_outlined,
              child: professions.isEmpty
                  ? const Text('لا توجد مهن مسجلة حاليًا.')
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: professions
                          .map((p) => Chip(label: Text(p)))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'البيانات الشخصية والمهنية',
              icon: Icons.person_outline,
              child: Column(
                children: [
                  _InfoRow(label: 'الاسم', value: name),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(label: 'رقم الهاتف', value: phone, ltr: true),
                  ],
                  if (phone2.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(label: 'هاتف إضافي', value: phone2, ltr: true),
                  ],
                  if (phone3.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(label: 'هاتف إضافي 2', value: phone3, ltr: true),
                  ],
                  if (contactEmail.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      label: 'البريد الإلكتروني',
                      value: contactEmail,
                      ltr: true,
                    ),
                  ],
                  const SizedBox(height: 10),
                  _InfoRow(
                    label: 'سنوات الخبرة',
                    value: '$yearsExperience سنة',
                  ),
                  if (experienceRanges.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      label: 'نطاق الخبرة',
                      value: experienceRanges.join('، '),
                    ),
                  ],
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(label: 'العنوان', value: address),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(label: 'نبذة', value: description),
                  ],
                  const SizedBox(height: 10),
                  _InfoRow(
                    label: 'وسيلة الانتقال',
                    value: _translateTransportation(transportationType),
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    label: 'حالة التوفر',
                    value: isAvailable
                        ? 'متاح لاستقبال الطلبات'
                        : 'غير متاح حاليًا',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'مناطق التغطية',
              icon: Icons.location_on_outlined,
              child: areaNames.isEmpty
                  ? const Text('لا توجد مناطق تغطية مسجلة حاليًا.')
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: areaNames
                          .map((a) => Chip(label: Text(a)))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'بيانات التواصل',
              icon: Icons.phone_outlined,
              child: Column(
                children: [
                  if (whatsappPhone.isNotEmpty)
                    _InfoRow(label: 'واتساب', value: whatsappPhone, ltr: true),
                  if (whatsappPhone2.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _InfoRow(
                      label: 'واتساب إضافي',
                      value: whatsappPhone2,
                      ltr: true,
                    ),
                  ],
                  if (whatsappPhone.isEmpty && whatsappPhone2.isEmpty)
                    const Text('لا توجد بيانات واتساب مسجلة.'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'بيانات التحصيل',
              icon: Icons.account_balance_wallet_outlined,
              child: Column(
                children: [
                  if (payoutMethods.isEmpty)
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text('لا توجد وسيلة تحصيل مسجلة حاليًا.'),
                    ),
                  ...payoutMethods.map(
                    (method) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PayoutMethodCard(method: method),
                    ),
                  ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _editPayout,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل بيانات التحصيل'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'بيانات الهوية',
              icon: Icons.badge_outlined,
              child: Column(
                children: [
                  _InfoRow(
                    label: 'الرقم القومي',
                    value: nationalIdNumber.isEmpty
                        ? 'غير مسجل'
                        : _maskNationalId(nationalIdNumber),
                    ltr: true,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تعديل بيانات الهوية يظل ضمن إجراءات التحقق الخاصة بالإدارة.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF78909C)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _editProfile,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F5FF),
                    borderRadius: BorderRadius.circular(30),
                    image: profileImage != null
                        ? DecorationImage(
                            image: NetworkImage(profileImage!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: profileImage == null
                      ? const Icon(
                          Icons.person_outline,
                          size: 58,
                          color: Color(0xFF0787D1),
                        )
                      : null,
                ),
                Positioned(
                  bottom: -5,
                  left: -5,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0787D1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      size: 17,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'اضغط على الصورة لتعديلها',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF78909C),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF073A68),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF8EF),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: Color(0xFF008A4C),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _maskNationalId(String value) {
    if (value.length <= 4) return value;
    return '${value.substring(0, 3)}********${value.substring(value.length - 2)}';
  }

  String _translateTransportation(String value) {
    switch (value) {
      case 'motorcycle':
        return 'موتوسيكل';
      case 'car':
        return 'سيارة';
      case 'none':
        return 'بدون وسيلة انتقال';
      default:
        return value.isEmpty ? 'غير محددة' : value;
    }
  }

  String _s(dynamic value, [String fallback = '']) =>
      value?.toString().trim().isNotEmpty == true
      ? value.toString().trim()
      : fallback;
  int? _i(dynamic value) => int.tryParse(value?.toString() ?? '');
  List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];
  List<int> _ids(dynamic raw, String key) => raw is List
      ? raw.whereType<Map>().map((e) => _i(e[key])).whereType<int>().toList()
      : [];
  List<String> _names(dynamic raw, String key) => raw is List
      ? raw
            .whereType<Map>()
            .map((e) => _s(e[key]))
            .where((e) => e.isNotEmpty)
            .toList()
      : [];
  List<String> _strings(dynamic raw, String key) => _names(raw, key);
}

class CraftsmanEditProfilePage extends StatefulWidget {
  const CraftsmanEditProfilePage({
    super.key,
    required this.name,
    required this.phone,
    required this.phone2,
    required this.phone3,
    required this.whatsappPhone,
    required this.whatsappPhone2,
    required this.contactEmail,
    required this.address,
    required this.cityId,
    required this.yearsExperience,
    required this.description,
    required this.isAvailable,
    required this.transportationType,
    required this.profileImage,
    required this.professionIds,
    required this.areaIds,
    required this.experienceRanges,
  });

  final String name;
  final String phone;
  final String phone2;
  final String phone3;
  final String whatsappPhone;
  final String whatsappPhone2;
  final String contactEmail;
  final String address;
  final int? cityId;
  final int yearsExperience;
  final String description;
  final bool isAvailable;
  final String transportationType;
  final String? profileImage;
  final List<int> professionIds;
  final List<int> areaIds;
  final List<String> experienceRanges;

  @override
  State<CraftsmanEditProfilePage> createState() =>
      _CraftsmanEditProfilePageState();
}

class _CraftsmanEditProfilePageState extends State<CraftsmanEditProfilePage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _phone2;
  late final TextEditingController _phone3;
  late final TextEditingController _whatsapp;
  late final TextEditingController _whatsapp2;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _description;
  late final TextEditingController _years;
  late final TextEditingController _profileImage;

  bool _loading = true;
  bool _saving = false;
  bool _isAvailable = true;
  String? _error;
  int? _cityId;
  String _transportationType = 'none';

  List<Map<String, dynamic>> _professions = [];
  List<Map<String, dynamic>> _cities = [];
  List<Map<String, dynamic>> _areas = [];
  Set<int> _selectedProfessions = {};
  Set<int> _selectedAreas = {};
  Set<String> _selectedExperience = {};

  static const List<String> _experienceOptions = ['1-3', '4-6', '>6'];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
    _phone = TextEditingController(text: widget.phone);
    _phone2 = TextEditingController(text: widget.phone2);
    _phone3 = TextEditingController(text: widget.phone3);
    _whatsapp = TextEditingController(text: widget.whatsappPhone);
    _whatsapp2 = TextEditingController(text: widget.whatsappPhone2);
    _email = TextEditingController(text: widget.contactEmail);
    _address = TextEditingController(text: widget.address);
    _description = TextEditingController(text: widget.description);
    _years = TextEditingController(text: widget.yearsExperience.toString());
    _profileImage = TextEditingController(text: widget.profileImage ?? '');
    _cityId = widget.cityId;
    _transportationType = widget.transportationType.isEmpty
        ? 'none'
        : widget.transportationType;
    _isAvailable = widget.isAvailable;
    _selectedProfessions = widget.professionIds.toSet();
    _selectedAreas = widget.areaIds.toSet();
    _selectedExperience = widget.experienceRanges.toSet();
    _loadLists();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _phone2.dispose();
    _phone3.dispose();
    _whatsapp.dispose();
    _whatsapp2.dispose();
    _email.dispose();
    _address.dispose();
    _description.dispose();
    _years.dispose();
    _profileImage.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    try {
      final professions = await _supabase
          .from('professions')
          .select('id,name_ar')
          .eq('is_active', true)
          .order('sort_order');

      final cities = await _supabase
          .from('cities')
          .select('id,name_ar')
          .eq('is_active', true)
          .order('sort_order');

      if (!mounted) return;
      setState(() {
        _professions = professions
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
        _cities = cities
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });

      if (_cityId != null) {
        await _loadAreas(_cityId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل المهن والمدن: $e';
      });
    }
  }

  Future<void> _loadAreas(int cityId) async {
    try {
      final areas = await _supabase
          .from('areas')
          .select('id,name_ar,city_id')
          .eq('city_id', cityId)
          .eq('is_active', true)
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        _areas = areas
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل المناطق: $e';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProfessions.isEmpty) {
      _showError('اختر مهنة واحدة على الأقل.');
      return;
    }
    if (_cityId == null) {
      _showError('اختر المدينة.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _supabase.rpc(
        'update_my_technician_profile_v2',
        params: {
          'p_full_name': _name.text.trim(),
          'p_phone': _phone.text.trim(),
          'p_phone2': _nullable(_phone2.text),
          'p_phone3': _nullable(_phone3.text),
          'p_whatsapp_phone': _nullable(_whatsapp.text),
          'p_whatsapp_phone2': _nullable(_whatsapp2.text),
          'p_contact_email': _nullable(_email.text),
          'p_address': _nullable(_address.text),
          'p_city_id': _cityId,
          'p_years_experience': int.tryParse(_years.text.trim()) ?? 0,
          'p_description': _nullable(_description.text),
          'p_is_available': _isAvailable,
          'p_profile_image': _nullable(_profileImage.text),
          'p_transportation_type': _transportationType,
          'p_profession_ids': _selectedProfessions.toList(),
          'p_area_ids': _selectedAreas.toList(),
          'p_experience_ranges': _selectedExperience.toList(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ بيانات الملف بنجاح')),
      );
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      _showError(_friendlyError(e.message));
    } catch (e) {
      _showError('تعذر حفظ البيانات: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String? _nullable(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }

  String _friendlyError(String message) {
    final m = message.toLowerCase();
    if (m.contains('phone_required')) return 'رقم الهاتف مطلوب.';
    if (m.contains('full_name_required')) return 'الاسم مطلوب.';
    if (m.contains('invalid_city')) return 'المدينة المختارة غير صحيحة.';
    if (m.contains('invalid_area'))
      return 'يوجد منطقة غير تابعة للمدينة المختارة.';
    if (m.contains('invalid_profession')) return 'يوجد مهنة غير متاحة حاليًا.';
    if (m.contains('duplicate key') && m.contains('phone'))
      return 'رقم الهاتف مستخدم بالفعل.';
    return message;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red.shade700, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5FAFD),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF073A68),
          centerTitle: true,
          title: const Text(
            'تعديل بيانات الملف',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF0787D1)),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    _field(
                      _name,
                      'الاسم',
                      Icons.person_outline,
                      requiredField: true,
                    ),
                    _field(
                      _phone,
                      'رقم الهاتف / رقم الدخول',
                      Icons.phone_outlined,
                      ltr: true,
                      requiredField: true,
                    ),
                    _field(
                      _phone2,
                      'رقم هاتف إضافي',
                      Icons.phone_android_outlined,
                      ltr: true,
                    ),
                    _field(
                      _phone3,
                      'رقم هاتف إضافي 2',
                      Icons.phone_android_outlined,
                      ltr: true,
                    ),
                    _field(_whatsapp, 'واتساب', Icons.chat_outlined, ltr: true),
                    _field(
                      _whatsapp2,
                      'واتساب إضافي',
                      Icons.chat_bubble_outline,
                      ltr: true,
                    ),
                    _field(
                      _email,
                      'البريد الإلكتروني',
                      Icons.email_outlined,
                      ltr: true,
                    ),
                    _field(_address, 'العنوان', Icons.location_on_outlined),
                    _field(
                      _years,
                      'سنوات الخبرة',
                      Icons.timeline,
                      ltr: true,
                      keyboard: TextInputType.number,
                    ),
                    _field(
                      _description,
                      'نبذة عنك',
                      Icons.description_outlined,
                      maxLines: 4,
                    ),
                    _field(
                      _profileImage,
                      'رابط الصورة الشخصية',
                      Icons.image_outlined,
                      ltr: true,
                    ),
                    const SizedBox(height: 8),
                    _sectionTitle('المدينة'),
                    DropdownButtonFormField<int>(
                      initialValue:
                          _cities.any((c) => _toInt(c['id']) == _cityId)
                          ? _cityId
                          : null,
                      decoration: _decoration(Icons.location_city_outlined),
                      items: _cities.map((city) {
                        final id = _toInt(city['id']);
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(city['name_ar']?.toString() ?? ''),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        setState(() {
                          _cityId = value;
                          _selectedAreas.clear();
                          _areas = [];
                        });
                        if (value != null) await _loadAreas(value);
                      },
                      validator: (value) =>
                          value == null ? 'اختر المدينة' : null,
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('المهن'),
                    ..._professions.map((profession) {
                      final id = _toInt(profession['id']);
                      final name = profession['name_ar']?.toString() ?? '';
                      if (id == null) return const SizedBox.shrink();
                      return CheckboxListTile(
                        value: _selectedProfessions.contains(id),
                        title: Text(name),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedProfessions.add(id);
                            } else {
                              _selectedProfessions.remove(id);
                            }
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                    const SizedBox(height: 10),
                    _sectionTitle('مناطق التغطية'),
                    if (_areas.isEmpty)
                      const Text('اختر المدينة أولًا لتحميل المناطق.'),
                    ..._areas.map((area) {
                      final id = _toInt(area['id']);
                      final name = area['name_ar']?.toString() ?? '';
                      if (id == null) return const SizedBox.shrink();
                      return CheckboxListTile(
                        value: _selectedAreas.contains(id),
                        title: Text(name),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedAreas.add(id);
                            } else {
                              _selectedAreas.remove(id);
                            }
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                    const SizedBox(height: 10),
                    _sectionTitle('نطاق الخبرة'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _experienceOptions.map((range) {
                        return FilterChip(
                          label: Text(range),
                          selected: _selectedExperience.contains(range),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedExperience.add(range);
                              } else {
                                _selectedExperience.remove(range);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('وسيلة الانتقال'),
                    DropdownButtonFormField<String>(
                      initialValue:
                          const [
                            'none',
                            'motorcycle',
                            'car',
                          ].contains(_transportationType)
                          ? _transportationType
                          : 'none',
                      decoration: _decoration(
                        Icons.directions_car_outlined,
                        'وسيلة الانتقال',
                      ),
                      items: const [
                        DropdownMenuItem<String>(
                          value: 'none',
                          child: Text('بدون وسيلة'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'motorcycle',
                          child: Text('موتوسيكل'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'car',
                          child: Text('سيارة'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _transportationType = value);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('متاح لاستقبال الطلبات'),
                      value: _isAvailable,
                      onChanged: (value) =>
                          setState(() => _isAvailable = value),
                    ),
                    const SizedBox(height: 18),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving ? 'جارٍ الحفظ...' : 'حفظ التعديلات',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool ltr = false,
    bool requiredField = false,
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboard,
        textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
        decoration: _decoration(icon, label),
        validator: requiredField
            ? (value) => value == null || value.trim().isEmpty
                  ? 'هذا الحقل مطلوب'
                  : null
            : null,
      ),
    );
  }

  InputDecoration _decoration(IconData icon, [String? hint]) {
    return InputDecoration(
      labelText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: Color(0xFF073A68),
        ),
      ),
    );
  }

  int? _toInt(dynamic value) => int.tryParse(value?.toString() ?? '');
}

class CraftsmanPayoutEditPage extends StatefulWidget {
  const CraftsmanPayoutEditPage({super.key, required this.methods});
  final List<Map<String, dynamic>> methods;

  @override
  State<CraftsmanPayoutEditPage> createState() =>
      _CraftsmanPayoutEditPageState();
}

class _CraftsmanPayoutEditPageState extends State<CraftsmanPayoutEditPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _holder = TextEditingController();
  final _wallet = TextEditingController();
  final _instapay = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final method in widget.methods) {
      final type = method['method_type']?.toString().toLowerCase() ?? '';
      final identifier = method['account_identifier']?.toString() ?? '';
      final holder = method['account_holder_name']?.toString() ?? '';
      if (_holder.text.isEmpty && holder.isNotEmpty) _holder.text = holder;
      if (type == 'wallet') _wallet.text = identifier;
      if (type == 'instapay') _instapay.text = identifier;
    }
  }

  @override
  void dispose() {
    _holder.dispose();
    _wallet.dispose();
    _instapay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final holder = _holder.text.trim();
    final wallet = _wallet.text.trim();
    final instapay = _instapay.text.trim();

    if (holder.isEmpty) {
      _showError('اسم صاحب الحساب مطلوب.');
      return;
    }
    if (wallet.isEmpty && instapay.isEmpty) {
      _showError('أدخل المحفظة أو InstaPay على الأقل.');
      return;
    }

    final methods = <Map<String, dynamic>>[];
    if (wallet.isNotEmpty) {
      methods.add({
        'method_type': 'wallet',
        'account_identifier': wallet,
        'account_holder_name': holder,
      });
    }
    if (instapay.isNotEmpty) {
      methods.add({
        'method_type': 'instapay',
        'account_identifier': instapay,
        'account_holder_name': holder,
      });
    }

    setState(() => _saving = true);
    try {
      await _supabase.rpc(
        'update_my_technician_payouts_v2',
        params: {'p_methods': methods},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ بيانات التحصيل بنجاح')),
      );
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      _showError(_friendlyError(e.message));
    } catch (e) {
      _showError('تعذر حفظ بيانات التحصيل: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyError(String message) {
    final m = message.toLowerCase();
    if (m.contains('account_holder_name_required'))
      return 'اسم صاحب الحساب مطلوب.';
    if (m.contains('payout_method_required'))
      return 'يجب تسجيل وسيلة تحصيل واحدة على الأقل.';
    if (m.contains('invalid_wallet_phone')) return 'رقم المحفظة غير صحيح.';
    if (m.contains('invalid_payout_method_type'))
      return 'نوع وسيلة التحصيل غير صحيح.';
    return message;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.red.shade700, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5FAFD),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF073A68),
          centerTitle: true,
          title: const Text(
            'تعديل بيانات التحصيل',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _PayoutInput(
              controller: _holder,
              label: 'اسم صاحب الحساب',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),
            _PayoutInput(
              controller: _wallet,
              label: 'رقم المحفظة الإلكترونية',
              icon: Icons.account_balance_wallet_outlined,
              ltr: true,
            ),
            const SizedBox(height: 12),
            _PayoutInput(
              controller: _instapay,
              label: 'رقم InstaPay',
              icon: Icons.account_balance_outlined,
              ltr: true,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F6FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'يمكنك تعديل بيانات التحصيل في أي وقت. البيانات الجديدة هي التي سيعتمد عليها النظام عند تجهيز مستحقاتك.',
                style: TextStyle(color: Color(0xFF073A68)),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ بيانات التحصيل'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayoutInput extends StatelessWidget {
  const _PayoutInput({
    required this.controller,
    required this.label,
    required this.icon,
    this.ltr = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class CraftsmanPayoutsPage extends StatefulWidget {
  const CraftsmanPayoutsPage({super.key, required this.payouts});

  final List<Map<String, dynamic>> payouts;

  @override
  State<CraftsmanPayoutsPage> createState() => _CraftsmanPayoutsPageState();
}

class _CraftsmanPayoutsPageState extends State<CraftsmanPayoutsPage> {
  final SupabaseClient _db = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadFinancialSummary();
  }

  Future<void> _loadFinancialSummary() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await _db.rpc('get_my_technician_financial_summary');
      if (result is! Map) {
        throw Exception('تعذر قراءة الملخص المالي للفني.');
      }

      final summary = Map<String, dynamic>.from(result);
      final rawTransactions = summary['transactions'];
      final transactions = rawTransactions is List
          ? rawTransactions
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _transactions = transactions.isNotEmpty
            ? transactions
            : List<Map<String, dynamic>>.from(widget.payouts);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _financialError(e);
        _summary = {};
        _transactions = List<Map<String, dynamic>>.from(widget.payouts);
        _loading = false;
      });
    }
  }

  String _financialError(Object e) {
    if (e is PostgrestException) {
      final message = e.message.toLowerCase();
      if (message.contains('technician') || message.contains('فني')) {
        return 'تعذر تحميل المستحقات المالية للفني.';
      }
    }
    return 'تعذر تحميل المستحقات المالية حاليًا. اضغط تحديث للمحاولة مرة أخرى.';
  }

  double _number(String key) =>
      double.tryParse(_summary[key]?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final totalEarned = _number('total_earned');
    final collected = _number('total_collected');
    final ready = _number('ready_to_collect');
    final held = _number('held_amount');
    final platformFees = _number('platform_fees');
    final paidOrders =
        int.tryParse(_summary['paid_orders_count']?.toString() ?? '') ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5FAFD),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF073A68),
          centerTitle: true,
          title: const Text(
            'المستحقات',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadFinancialSummary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              _PayoutSummaryCard(
                title: 'إجمالي المستحقات من الطلبات المدفوعة',
                amount: totalEarned,
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 10),
              _PayoutSummaryCard(
                title: 'تم تحصيله فعليًا',
                amount: collected,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(height: 10),
              _PayoutSummaryCard(
                title: 'جاهز للتحصيل',
                amount: ready,
                icon: Icons.payments_outlined,
              ),
              const SizedBox(height: 10),
              _PayoutSummaryCard(
                title: 'المبلغ المعلق',
                amount: held,
                icon: Icons.hourglass_bottom_outlined,
              ),
              const SizedBox(height: 10),
              _PayoutSummaryCard(
                title: 'رسوم المنصة المسجلة',
                amount: platformFees,
                icon: Icons.receipt_long_outlined,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDDEAF2)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      color: Color(0xFF073A68),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'عدد الطلبات المدفوعة: $paidOrders',
                      style: const TextStyle(
                        color: Color(0xFF073A68),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_transactions.isEmpty && !_loading)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFDDEAF2)),
                  ),
                  child: const Text(
                    'لا توجد حركة مستحقات مسجلة حتى الآن.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF607D8B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                ..._transactions.map(
                  (payout) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TechnicianPayoutCard(payout: payout),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayoutSummaryCard extends StatelessWidget {
  const _PayoutSummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
  });

  final String title;
  final double amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDEAF2)),
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
            child: Icon(icon, color: const Color(0xFF0787D1)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF607D8B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatPayoutAmount(amount),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF073A68),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoutSmallSummary extends StatelessWidget {
  const _PayoutSmallSummary({
    required this.title,
    required this.amount,
    required this.color,
  });

  final String title;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDEAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF78909C),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatPayoutAmount(amount),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicianPayoutCard extends StatelessWidget {
  const _TechnicianPayoutCard({required this.payout});

  final Map<String, dynamic> payout;

  @override
  Widget build(BuildContext context) {
    final orderId = payout['order_id'];
    final amount = double.tryParse(payout['amount']?.toString() ?? '') ?? 0;
    final status = payout['status']?.toString().toLowerCase() ?? '';
    final order = payout['orders'];
    final serviceName = order is Map
        ? (order['services'] is Map
              ? order['services']['service_name']?.toString().trim() ?? ''
              : '')
        : '';
    final reference = payout['payment_reference']?.toString().trim() ?? '';
    final notes = payout['notes']?.toString().trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDEAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'مستحق عن الطلب #$orderId',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF073A68),
                  ),
                ),
              ),
              _PayoutStatusChip(status: status),
            ],
          ),
          if (serviceName.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoRow(label: 'الخدمة', value: serviceName),
          ],
          const SizedBox(height: 10),
          _InfoRow(label: 'المبلغ', value: _formatPayoutAmount(amount)),
          if (payout['ready_at'] != null) ...[
            const SizedBox(height: 10),
            _InfoRow(
              label: 'تاريخ الجاهزية',
              value: _formatDate(payout['ready_at']),
              ltr: true,
            ),
          ],
          if (payout['paid_at'] != null) ...[
            const SizedBox(height: 10),
            _InfoRow(
              label: 'تاريخ التحصيل',
              value: _formatDate(payout['paid_at']),
              ltr: true,
            ),
          ],
          if (reference.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(label: 'مرجع التحصيل', value: reference, ltr: true),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(label: 'ملاحظات', value: notes),
          ],
        ],
      ),
    );
  }
}

class _PayoutStatusChip extends StatelessWidget {
  const _PayoutStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final data = _statusData(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: data.$1.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        data.$2,
        style: TextStyle(
          color: data.$1,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

(Color, String) _statusData(String status) {
  switch (status) {
    case 'ready':
      return (const Color(0xFF0787D1), 'جاهز للتحصيل');
    case 'paid':
      return (const Color(0xFF008A4C), 'تم التحصيل');
    case 'held':
      return (const Color(0xFFF39C12), 'معلق');
    case 'cancelled':
      return (const Color(0xFFC62828), 'ملغي');
    default:
      return (const Color(0xFF607D8B), status.isEmpty ? 'غير محدد' : status);
  }
}

String _formatPayoutAmount(double value) {
  if (value == value.roundToDouble()) {
    return '${value.toInt()} جنيه';
  }
  return '${value.toStringAsFixed(2)} جنيه';
}

String _formatDate(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return value?.toString() ?? '';
  final local = parsed.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _PayoutMethodCard extends StatelessWidget {
  const _PayoutMethodCard({required this.method});
  final Map<String, dynamic> method;

  @override
  Widget build(BuildContext context) {
    final type = method['method_type']?.toString() ?? '';
    final identifier = method['account_identifier']?.toString().trim() ?? '';
    final holder = method['account_holder_name']?.toString().trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _translatePayoutType(type),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF073A68),
            ),
          ),
          if (identifier.isNotEmpty) ...[
            const SizedBox(height: 7),
            _InfoRow(label: 'بيانات الحساب', value: identifier, ltr: true),
          ],
          if (holder.isNotEmpty) ...[
            const SizedBox(height: 7),
            _InfoRow(label: 'اسم صاحب الحساب', value: holder),
          ],
        ],
      ),
    );
  }

  String _translatePayoutType(String type) {
    switch (type.toLowerCase()) {
      case 'instapay':
        return 'InstaPay';
      case 'wallet':
        return 'محفظة إلكترونية';
      default:
        return type.isEmpty ? 'وسيلة تحصيل' : type;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDEAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0787D1)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF073A68),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.ltr = false});
  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 125,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF78909C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF263238),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFDDEAF2)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF0787D1), size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF073A68),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 28),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              badge.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF78909C),
                      ),
                    ),
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
    );
  }
}
