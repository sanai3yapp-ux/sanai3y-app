import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

const _techBlue = Color(0xFF087FD0);

const _techDark = Color(0xFF073A68);

const _techBg = Color(0xFFF5FAFD);

const _techBorder = Color(0xFFDDEAF2);

class CraftsmanOrdersPage extends StatefulWidget {
  const CraftsmanOrdersPage({super.key});

  @override
  State<CraftsmanOrdersPage> createState() => _CraftsmanOrdersPageState();
}

class _CraftsmanOrdersPageState extends State<CraftsmanOrdersPage> {
  final _db = Supabase.instance.client;

  bool _loading = true;

  String? _error;

  List<Map<String, dynamic>> _orders = [];
  RealtimeChannel? _ordersChannel;
  Timer? _realtimeDebounce;
  bool _autoRefreshing = false;
  bool _loadInProgress = false;

  // Orders whose visible data changed since the previous successful refresh.
  final Set<String> _unreadOrderIds = <String>{};
  final Map<String, String> _orderSignatures = <String, String>{};
  final Map<int, TextEditingController> _inspectionPriceControllers =
      <int, TextEditingController>{};

  String _orderKey(Map<String, dynamic> order) =>
      (order['order_id'] ?? order['id'] ?? '').toString();

  String _orderSignature(Map<String, dynamic> order) {
    // Track fields that represent meaningful order/offer/payment updates.
    const fields = <String>[
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
      'technician_available_from',
      'technician_available_to',
      'scheduled_at',
      'scheduled_to',
      'total_offer_price',
      'labor_price',
      'response_note',
      'payout_status',
      'payout_amount',
      'inspection_settlement_mode',
    ];
    return fields.map((field) => '$field=${order[field]}').join('|');
  }

  void _markOrderRead(Map<String, dynamic> order) {
    final key = _orderKey(order);
    if (key.isEmpty || !_unreadOrderIds.contains(key)) return;
    setState(() => _unreadOrderIds.remove(key));
  }

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToOrderChanges();
  }

  void _subscribeToOrderChanges() {
    _ordersChannel =
        _db.channel('craftsman-orders-${_db.auth.currentUser?.id ?? 'guest'}')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_technician_offers',
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inspection_settlements',
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_technician_payouts',
            callback: (_) => _scheduleRealtimeRefresh(),
          )
          ..subscribe();
  }

  void _scheduleRealtimeRefresh() {
    if (!mounted) return;
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      if (_loadInProgress) {
        _scheduleRealtimeRefresh();
        return;
      }
      _autoRefreshing = true;
      await _load();
      _autoRefreshing = false;
    });
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    final channel = _ordersChannel;
    if (channel != null) {
      _db.removeChannel(channel);
    }
    for (final controller in _inspectionPriceControllers.values) {
      controller.dispose();
    }
    _inspectionPriceControllers.clear();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    try {
      if (!_autoRefreshing && mounted) {
        setState(() {
          if (_orders.isEmpty) _loading = true;
          _error = null;
        });
      }

      if (_db.auth.currentUser == null) {
        throw Exception('يجب تسجيل الدخول أولًا.');
      }

      final result = await _db.rpc('get_technician_order_feed_v3');

      final freshOrders = (result as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Include the authoritative payout status so the completion card can
      // turn green only after the administration marks the payout as paid.
      final orderIds = freshOrders
          .map((order) => order['order_id'])
          .where((id) => id != null)
          .toList();
      if (orderIds.isNotEmpty) {
        final payoutRows = await _db
            .from('order_technician_payouts')
            .select('order_id,status,amount')
            .inFilter('order_id', orderIds);
        final payoutsByOrder = <String, Map<String, dynamic>>{
          for (final row in payoutRows)
            row['order_id'].toString(): Map<String, dynamic>.from(row),
        };

        // The technician feed RPC can omit final financial columns for
        // completed orders. Fetch the authoritative order and settlement
        // records so completed cards (including older order #24) keep showing
        // the actual agreed labor amount after the order is closed.
        final orderRows = await _db
            .from('orders')
            .select(
              'id,total_price,inspection_labor_price,inspection_settlement_mode,'
              'technician_platform_fee,technician_net_amount',
            )
            .inFilter('id', orderIds);
        final orderFinancials = <String, Map<String, dynamic>>{
          for (final row in orderRows)
            row['id'].toString(): Map<String, dynamic>.from(row),
        };

        final settlementRows = await _db
            .from('inspection_settlements')
            .select(
              'order_id,labor_price,settlement_mode,technician_fee,'
              'technician_amount,status',
            )
            .inFilter('order_id', orderIds);
        final settlementsByOrder = <String, Map<String, dynamic>>{
          for (final row in settlementRows)
            row['order_id'].toString(): Map<String, dynamic>.from(row),
        };

        for (final order in freshOrders) {
          final key = order['order_id']?.toString();
          if (key == null) continue;

          final payout = payoutsByOrder[key];
          if (payout != null) {
            order['payout_status'] = payout['status'];
            order['payout_amount'] = payout['amount'];
          }

          final financial = orderFinancials[key];
          if (financial != null) {
            for (final field in const [
              'total_price',
              'inspection_labor_price',
              'inspection_settlement_mode',
              'technician_platform_fee',
              'technician_net_amount',
            ]) {
              if (financial[field] != null) order[field] = financial[field];
            }
          }

          final settlement = settlementsByOrder[key];
          if (settlement != null) {
            if (settlement['labor_price'] != null) {
              order['labor_price'] = settlement['labor_price'];
            }
            if (settlement['settlement_mode'] != null) {
              order['inspection_settlement_mode'] =
                  settlement['settlement_mode'];
            }
            if (settlement['technician_fee'] != null) {
              order['technician_platform_fee'] = settlement['technician_fee'];
            }
            if (settlement['technician_amount'] != null) {
              order['technician_net_amount'] = settlement['technician_amount'];
            }
          }
        }
      }

      // First load establishes a baseline; subsequent refreshes flag only
      // orders whose tracked fields changed. This avoids marking every order
      // as new when the technician opens the page for the first time.
      for (final order in freshOrders) {
        final key = _orderKey(order);
        if (key.isEmpty) continue;
        final signature = _orderSignature(order);
        final previous = _orderSignatures[key];
        if (previous != null && previous != signature) {
          _unreadOrderIds.add(key);
        }
        _orderSignatures[key] = signature;
      }

      // Keep actionable orders first; completed jobs are compact summaries at
      // the bottom so they never compete visually with new/active requests.
      int priority(Map<String, dynamic> order) {
        final status = order['status']?.toString();
        if (status == 'completed') return 2;
        if (status == 'cancelled') return 3;
        return 0;
      }

      freshOrders.sort((a, b) {
        final byPriority = priority(a).compareTo(priority(b));
        if (byPriority != 0) return byPriority;
        final aDate = DateTime.tryParse(
          (a['created_at'] ?? a['scheduled_at'] ?? '').toString(),
        );
        final bDate = DateTime.tryParse(
          (b['created_at'] ?? b['scheduled_at'] ?? '').toString(),
        );
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate);
      });
      _orders = freshOrders;

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _clean(e);
        });
      }
    } finally {
      _loadInProgress = false;
    }
  }

  Future<void> _openOffer(Map<String, dynamic> order) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (_) => _OfferSheet(order: order),
    );

    if (result == null) return;

    try {
      await _db.rpc('submit_technician_order_offer_v3', params: result);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check_circle, color: Color(0xFF168447), size: 64),
                  SizedBox(height: 14),
                  Text(
                    'تم إرسال عرضك بنجاح',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF168447),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'عرضك الآن في انتظار اختيار العميل.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('حسنًا'),
              ),
            ],
          ),
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_clean(e))));
    }
  }

  String _clean(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '');
    if (text.contains('ADMIN_PAYMENT_CONFIRMATION_REQUIRED') ||
        text.contains('FULL_PAYMENT_NOT_CONFIRMED')) {
      return 'لا يمكن بدء الخدمة أو إنهاؤها قبل تأكيد الإدارة اكتمال الدفع.';
    }
    if (text.contains('SERVICE_NOT_STARTED')) {
      return 'تعذر إكمال الخدمة. حدّث الطلب وتأكد من تأكيد الإدارة للدفع.';
    }
    if (text.contains('ORDER_NOT_READY_TO_START')) {
      return 'الطلب غير جاهز لبدء التنفيذ في حالته الحالية.';
    }
    if (text.contains('ORDER_NOT_READY_TO_COMPLETE')) {
      return 'الطلب غير جاهز للإنهاء. تأكد من بدء التنفيذ وتأكيد الدفع.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,

      child: Scaffold(
        backgroundColor: _techBg,

        appBar: AppBar(
          backgroundColor: Colors.white,

          foregroundColor: _techDark,

          elevation: 0,

          title: const Text(
            'طلبات العملاء',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث الطلبات',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),

        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _techBlue))
            : RefreshIndicator(
                onRefresh: _load,

                child: ListView(
                  key: const PageStorageKey<String>('craftsman-orders-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) _errorCard(_error!),
                            if (_orders.isEmpty && _error == null) _empty(),
                            ..._orders.map(_orderCard),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _completedCompactCard(Map<String, dynamic> order) {
    final external =
        order['inspection_settlement_mode']?.toString() == 'external';
    final labor = external
        ? 85
        : (order['labor_price'] ??
              order['inspection_labor_price'] ??
              order['total_offer_price'] ??
              order['total_price'] ??
              0);
    final fee = external ? 10 : (order['technician_platform_fee'] ?? 0);
    final net = external
        ? 75
        : (order['technician_net_amount'] ??
              ((double.tryParse(labor.toString()) ?? 0) -
                  (double.tryParse(
                        (order['technician_platform_fee'] ?? 0).toString(),
                      ) ??
                      0)));
    final service =
        (order['service_description'] ??
                order['problem_description'] ??
                order['service_name'] ??
                'تفاصيل الخدمة غير متاحة')
            .toString()
            .trim();
    final payoutPaid = order['payout_status']?.toString() == 'paid';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E5E9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'طلب #${order['order_id']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF536471),
                  ),
                ),
              ),
              const Icon(
                Icons.check_circle,
                size: 17,
                color: Color(0xFF168447),
              ),
              const SizedBox(width: 4),
              Text(
                'مكتمل',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            service.isEmpty ? 'تفاصيل الخدمة غير متاحة' : service,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _compactAmount('المصنعية', '${_money(labor)} ج'),
              _compactAmount('رسوم الفني', '${_money(fee)} ج'),
              _compactAmount('صافي مستحقاتك', '${_money(net)} ج'),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Icon(
                payoutPaid ? Icons.check_circle : Icons.schedule,
                size: 15,
                color: payoutPaid
                    ? const Color(0xFF168447)
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  payoutPaid
                      ? 'تم تحويل مستحقاتك'
                      : 'سيتم تحويل مستحقاتك خلال دقائق من الإدارة',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: payoutPaid
                        ? const Color(0xFF168447)
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _compactAmount(String label, String amount) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      Text(
        amount,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Color(0xFF536471),
        ),
      ),
    ],
  );

  Widget _orderCard(Map<String, dynamic> order) {
    if (order['status']?.toString() == 'completed') {
      return _completedCompactCard(order);
    }
    final hasOffer = order['offer_id'] != null;

    final revision =
        int.tryParse(order['revision_count']?.toString() ?? '0') ?? 0;

    final selectedOrder = order['selected_offer_id'] != null;

    final myOfferSelected =
        selectedOrder &&
        order['selected_offer_id']?.toString() == order['offer_id']?.toString();

    final canEdit = !selectedOrder && revision < 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),

      child: InkWell(
        onTap: () => _markOrderRead(order),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(18),

            border: Border.all(color: _techBorder, width: 1.2),
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'طلب #${order['order_id']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _techDark,
                      ),
                    ),
                  ),

                  if (_unreadOrderIds.contains(_orderKey(order)))
                    Tooltip(
                      message:
                          'يوجد تحديث جديد — اضغط على الطلب لتمييزه كمقروء',
                      child: Container(
                        width: 11,
                        height: 11,
                        margin: const EdgeInsetsDirectional.only(start: 8),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),

                  if (hasOffer)
                    Text(
                      revision >= 3 ? 'اكتمل 3/3' : 'العرض الحالي $revision/3',

                      style: TextStyle(
                        color: revision >= 3
                            ? Colors.orange.shade800
                            : Colors.green.shade700,

                        fontWeight: FontWeight.w800,

                        fontSize: 12,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              _row('الخدمة', order['service_description']?.toString() ?? '—'),

              if ((order['problem_description']?.toString() ?? '')
                  .trim()
                  .isNotEmpty)
                _row('وصف المشكلة', order['problem_description'].toString()),

              // صور المشكلة متاحة للفني قبل تقديم العرض حتى يستطيع تقدير العمل.
              _problemImagesCard(order),

              if (myOfferSelected && order['contact_released_at'] != null) ...[
                _detailedAddressCard(order),
                const SizedBox(height: 10),
                _customerContactCard(order),
              ] else ...[
                _row('العنوان', _technicianPreviewAddress(order)),

                const Padding(
                  padding: EdgeInsets.only(bottom: 8),

                  child: Text(
                    'سيظهر لك العنوان التفصيلي ورقم التواصل بعد اختيارك من قبل العميل وتأكيد الدفع من الإدارة.',

                    style: TextStyle(
                      fontSize: 13,

                      color: Color(0xFF78909C),

                      height: 1.4,
                    ),
                  ),
                ),
              ],

              _row(
                'الموعد',
                _appointmentLabel(
                  myOfferSelected && order['technician_available_from'] != null
                      ? order['technician_available_from']
                      : order['scheduled_at'],
                  myOfferSelected && order['technician_available_to'] != null
                      ? order['technician_available_to']
                      : order['scheduled_to'],
                ),
              ),

              _row(
                'الخامات',

                order['materials_requested'] == true
                    ? 'العميل يرغب في إمكانية توفير الخامات'
                    : 'العميل لم يطلب توفير الخامات',
              ),

              if (hasOffer && revision > 0) ...[
                const SizedBox(height: 8),

                _myOfferCard(order),
              ],

              if (myOfferSelected) ...[
                const SizedBox(height: 10),

                _selectedAndPaidCard(order),
              ],

              if (!selectedOrder) ...[
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,

                  height: 46,

                  child: ElevatedButton(
                    onPressed: canEdit ? () => _openOffer(order) : null,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: _techBlue,

                      foregroundColor: Colors.white,

                      disabledBackgroundColor: Colors.grey.shade300,
                    ),

                    child: Text(
                      revision >= 3
                          ? 'اكتملت العروض المتاحة'
                          : (revision > 0 ? 'تعديل العرض' : 'تقديم عرض'),

                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _paymentConfirmed(Map<String, dynamic> order) {
    final paymentStatus = order['payment_status']
        ?.toString()
        .toLowerCase()
        .trim();

    final remaining =
        double.tryParse(order['remaining_amount']?.toString() ?? '') ?? 0;

    // contact_released means the deposit/payment needed to reveal contact

    // was paid; it is NOT enough by itself to allow service completion.

    return paymentStatus == 'paid' && remaining <= 0;
  }

  Future<void> _startOrder(Map<String, dynamic> order) async {
    final orderId = int.tryParse(order['order_id']?.toString() ?? '');
    if (orderId == null) return;
    try {
      final fresh = await _db
          .from('orders')
          .select(
            'id,status,payment_status,remaining_amount,admin_completion_payment_confirmed_at',
          )
          .eq('id', orderId)
          .maybeSingle();
      if (fresh == null) {
        throw const PostgrestException(
          message: 'الطلب غير موجود أو لم يعد متاحًا.',
        );
      }
      final status = fresh['status']?.toString();
      final remaining =
          double.tryParse(fresh['remaining_amount']?.toString() ?? '') ?? 0;
      if (!['accepted', 'on_the_way', 'arrived'].contains(status)) {
        throw PostgrestException(
          message: 'لا يمكن بدء التنفيذ في حالة الطلب الحالية: $status',
        );
      }
      if (fresh['payment_status']?.toString() != 'paid' ||
          remaining > 0 ||
          fresh['admin_completion_payment_confirmed_at'] == null) {
        throw const PostgrestException(
          message: 'لا يمكن بدء التنفيذ قبل تأكيد الإدارة اكتمال الدفع.',
        );
      }
      await _db.rpc(
        'technician_start_order_service',
        params: {'p_order_id': orderId},
      );
      if (!mounted) return;
      setState(() => order['status'] = 'in_progress');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم التحقق من الدفع وتجهيز الطلب للتنفيذ.'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_clean(e))));
    }
  }

  Future<void> _finishService(Map<String, dynamic> order) async {
    final status = order['status']?.toString();
    // The UI no longer exposes a separate start button. Keep the secure
    // server-side payment gate, start the service through its RPC, then finish.
    if (status != 'in_progress') {
      await _startOrder(order);
      if (!mounted || order['status']?.toString() != 'in_progress') return;
    }
    await _completeOrder(order);
    if (!mounted || order['status']?.toString() != 'completed') return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.celebration_rounded,
                color: Color(0xFF168447),
                size: 64,
              ),
              SizedBox(height: 14),
              Text(
                'شكرًا لإتمام مهمتك بنجاح، استعد لاستقبال عروض جديدة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF168447),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      ),
    );
    await _load();
  }

  Future<void> _completeOrder(Map<String, dynamic> order) async {
    final orderId = int.tryParse(order['order_id']?.toString() ?? '');

    if (orderId == null) return;

    try {
      // Always refresh the authoritative order before completing it.

      // The card can contain an older snapshot while the admin payment

      // confirmation was just written to Supabase.

      final fresh = await _db
          .from('orders')
          .select(
            'id,status,payment_status,remaining_amount,technician_id,admin_completion_payment_confirmed_at',
          )
          .eq('id', orderId)
          .maybeSingle();

      if (fresh == null) {
        throw const PostgrestException(
          message: 'الطلب غير موجود أو لم يعد متاحًا.',
        );
      }

      final status = fresh['status']?.toString();

      final paymentStatus = fresh['payment_status']?.toString();

      final remaining =
          double.tryParse(fresh['remaining_amount']?.toString() ?? '') ?? 0;

      final adminConfirmed =
          fresh['admin_completion_payment_confirmed_at'] != null;

      if (status != 'in_progress') {
        throw PostgrestException(
          message: 'لا يمكن إنهاء الطلب في حالته الحالية: $status',
        );
      }

      if (paymentStatus != 'paid' || remaining > 0) {
        throw const PostgrestException(
          message: 'لا يمكن إنهاء الخدمة قبل اكتمال الدفع وتأكيده من الإدارة.',
        );
      }

      if (!adminConfirmed) {
        throw const PostgrestException(
          message: 'لم تؤكد الإدارة اكتمال الدفع لهذا الطلب بعد.',
        );
      }

      await _db.rpc('complete_order', params: {'p_order_id': orderId});

      if (!mounted) return;

      setState(() {
        order['status'] = 'completed';

        order['payment_status'] = paymentStatus;

        order['remaining_amount'] = 0;

        order['admin_completion_payment_confirmed_at'] =
            fresh['admin_completion_payment_confirmed_at'];

        order['service_completed_at'] = DateTime.now().toIso8601String();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد إنهاء الخدمة بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_clean(e))));
    }
  }

  Widget _selectedAndPaidCard(Map<String, dynamic> order) {
    final paidInFull = _paymentConfirmed(order);
    final orderId = int.tryParse(order['order_id']?.toString() ?? '');
    final completed = order['status']?.toString() == 'completed';

    if (order['requires_inspection'] == true &&
        order['contact_released_at'] != null &&
        !completed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // The inspection pricing card already owns the finish-service action.
        // Do not render a second identical button outside that card.
        children: [_inspectionPricingCard(order)],
      );
    }

    if (order['status']?.toString() == 'cancelled') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEEEE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFB8B8)),
        ),
        child: const Text(
          'تم إغلاق هذا الطلب أو إلغاؤه بعد التسوية. لا يمكن بدء التنفيذ أو إنهاؤه من هذه الحالة.',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w800,
            height: 1.5,
          ),
        ),
      );
    }

    if (completed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [
          Container(
            padding: const EdgeInsets.all(14),

            decoration: BoxDecoration(
              color: const Color(0xFFEAF8EF),

              borderRadius: BorderRadius.circular(14),

              border: Border.all(color: const Color(0xFFB9E4C8)),
            ),

            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  'تم تنفيذ الطلب وإنهاء الخدمة بنجاح.',

                  style: TextStyle(
                    color: Color(0xFF238B4E),

                    fontWeight: FontWeight.w900,

                    fontSize: 16,
                  ),
                ),

                SizedBox(height: 8),

                Text(
                  'نشكرك على إتمام الخدمة، يمكنك المغادرة الآن والاستعداد لطلبات أخرى.',

                  style: TextStyle(
                    color: Color(0xFF176B3A),

                    height: 1.55,

                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(13),

            decoration: BoxDecoration(
              color: Colors.white,

              borderRadius: BorderRadius.circular(12),

              border: Border.all(color: _techBorder),
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                const Text(
                  'ملخص مستحقاتك',

                  style: TextStyle(
                    color: _techDark,

                    fontWeight: FontWeight.w900,

                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 9),

                _payoutDetailItem(
                  'المصنعية',
                  '${_money(order['inspection_settlement_mode']?.toString() == 'external' ? 85 : (order['labor_price'] ?? order['total_offer_price']))} جنيه',
                  const Color(0xFF238B4E),
                ),

                const SizedBox(height: 8),

                _payoutDetailItem(
                  'رسوم المنصة على الفني',
                  '${_money(order['inspection_settlement_mode']?.toString() == 'external' ? 10 : order['technician_platform_fee'])} جنيه',
                  const Color(0xFFE67E22),
                ),

                const SizedBox(height: 8),

                _payoutDetailItem(
                  'صافي مستحقاتك',
                  '${_money(order['inspection_settlement_mode']?.toString() == 'external' ? 75 : order['technician_net_amount'])} جنيه',
                  const Color(0xFF087FD0),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: order['payout_status']?.toString() == 'paid'
                  ? const Color(0xFFEAF8EF)
                  : const Color(0xFFFFEEEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: order['payout_status']?.toString() == 'paid'
                    ? const Color(0xFF9BD8AF)
                    : const Color(0xFFFFB8B8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  order['payout_status']?.toString() == 'paid'
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  color: order['payout_status']?.toString() == 'paid'
                      ? const Color(0xFF168447)
                      : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order['payout_status']?.toString() == 'paid'
                        ? 'تم تحويل مستحقاتك.'
                        : 'سيتم تحويل مستحقاتك خلال دقائق من الإدارة.',
                    style: TextStyle(
                      color: order['payout_status']?.toString() == 'paid'
                          ? const Color(0xFF168447)
                          : Colors.red,
                      height: 1.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [
        Container(
          padding: const EdgeInsets.all(14),

          decoration: BoxDecoration(
            color: paidInFull
                ? const Color(0xFFEAF8EF)
                : const Color(0xFFE8F7EC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: paidInFull
                  ? const Color(0xFF9BD8AF)
                  : const Color(0xFF70C78D),
              width: 1.4,
            ),
          ),
          child: Text(
            paidInFull
                ? 'أكدت الإدارة استلام الدفع. يمكنك تنفيذ الخدمة، وبعد الانتهاء اضغط «تم التنفيذ/إنهاء الخدمة».'
                : 'مبروك! تم اختيارك من قبل العميل. في انتظار اكتمال الدفع وتأكيد الإدارة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF168447),
              height: 1.55,
              fontWeight: FontWeight.w900,
              fontSize: paidInFull ? 17 : 21,
            ),
          ),
        ),

        if (paidInFull &&
            order['inspection_settlement_mode']?.toString() != 'external' &&
            order['status']?.toString() != 'completed') ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => _finishService(order),
              icon: const Icon(Icons.task_alt_rounded, size: 25),
              label: const Text(
                'تم التنفيذ/إنهاء الخدمة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF168447),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ] else if (!paidInFull) ...[
          const SizedBox.shrink(),
        ] else ...[
          const Text(
            'شكرًا لإتمام مهمتك بنجاح، استعد لاستقبال عروض جديدة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF168447),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],

        if (!paidInFull) ...[
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(11),

            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),

              borderRadius: BorderRadius.circular(12),

              border: Border.all(color: const Color(0xFFFFD18A)),
            ),

            child: Text(
              order['customer_notice_pending'] == true
                  ? 'إشعار السداد قيد المراجعة من الإدارة. انتظر التأكيد قبل استكمال الخدمة.'
                  : 'في انتظار إشعار السداد من العميل. سيظهر لك تحديث الحالة بعد مراجعة الإدارة.',

              style: const TextStyle(
                color: Color(0xFF8A5200),

                height: 1.55,

                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _myOfferCard(Map<String, dynamic> order) {
    final inspection = order['requires_inspection'] == true;

    final revision =
        int.tryParse(order['revision_count']?.toString() ?? '0') ?? 0;

    final status = order['offer_status']?.toString() ?? '';

    final labor = order['labor_price'];

    final total = order['total_offer_price'];

    final from = _parseDate(order['technician_available_from']);

    final to = _parseDate(order['technician_available_to']);

    final note = order['response_note']?.toString().trim() ?? '';

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(13),

      decoration: BoxDecoration(
        color: const Color(0xFFEAF7FF),

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: const Color(0xFFBFE5FA)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: _techBlue),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  'عرضك المقدم',

                  style: TextStyle(
                    fontWeight: FontWeight.w800,

                    color: _techDark,
                  ),
                ),
              ),

              Text(
                '$revision/3',

                style: const TextStyle(
                  fontSize: 11,

                  fontWeight: FontWeight.w800,

                  color: _techBlue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            inspection
                ? 'المصنعية: تحدد بعد الاطلاع'
                : 'المصنعية: ${_money(labor)} جنيه',

            style: const TextStyle(
              fontWeight: FontWeight.w800,

              color: _techDark,
            ),
          ),

          if (!inspection && total != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),

              child: Text(
                'إجمالي العرض: ${_money(total)} جنيه',

                style: const TextStyle(fontSize: 12),
              ),
            ),

          const SizedBox(height: 7),

          Text(
            from != null && to != null
                ? 'موعد تواجدك: ${_appointmentLabel(from, to)}'
                : 'موعد تواجدك: لم يتم تحديده',

            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),

          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),

              child: Text(
                status == 'accepted' || revision > 0
                    ? 'حالة العرض: تم تقديمه للعميل'
                    : 'حالة العرض: $status',

                style: const TextStyle(fontSize: 12, color: Color(0xFF455A64)),
              ),
            ),

          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),

              child: Text(
                'ملاحظاتك: $note',

                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  String _addressValue(
    Map<String, dynamic> order,
    List<String> keys, {
    String fallback = 'غير محدد',
  }) {
    return _firstNonEmpty(order, keys) ?? fallback;
  }

  String _technicianPreviewAddress(Map<String, dynamic> order) {
    // Never fall back to the full customer address before contact is released.
    final combined = _firstNonEmpty(order, const [
      'technician_preview_address',
      'customer_preview_address',
      'address_preview',
    ]);
    final parts = (combined ?? '')
        .split(RegExp(r'\s*(?:—|–|-)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final neighborhood =
        _firstNonEmpty(order, const [
          'neighborhood',
          'neighborhood_name',
          'area_name',
          'district',
        ]) ??
        (parts.isNotEmpty ? parts[0] : 'غير محدد');
    final street =
        _firstNonEmpty(order, const ['street', 'street_name']) ??
        (parts.length > 1 ? parts[1] : 'غير محدد');
    return 'الحي: $neighborhood\nالشارع: $street';
  }

  Widget _detailedAddressCard(Map<String, dynamic> order) {
    final fullAddress = _firstNonEmpty(order, const [
      'full_address',
      'address',
      'customer_address',
    ]);

    final parts = fullAddress
        ?.split(RegExp(r'\s*(?:-|–|—)\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String fallbackPart(int index) {
      if (parts != null && parts.length >= 5 && index < parts.length) {
        return parts[index];
      }
      return 'غير محدد';
    }

    final neighborhood = _addressValue(order, const [
      'neighborhood',
      'neighborhood_name',
      'area_name',
      'district',
    ], fallback: fallbackPart(0));

    final street = _addressValue(order, const [
      'street',
      'street_name',
    ], fallback: fallbackPart(1));

    final building = _addressValue(order, const [
      'building_number',
      'building_no',
      'building',
      'building_name',
    ], fallback: fallbackPart(2));

    final floor = _addressValue(order, const [
      'floor',
      'floor_number',
    ], fallback: fallbackPart(3));

    final apartment = _addressValue(order, const [
      'apartment',
      'apartment_number',
      'unit_number',
    ], fallback: fallbackPart(4));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _techBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'العنوان التفصيلي للعميل',
            style: TextStyle(
              color: _techDark,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 9),
          _addressLine('الحي', neighborhood),
          _addressLine('الشارع', street),
          _addressLine('العمارة أو البلوك', building),
          _addressLine('الدور', floor),
          _addressLine('الشقة', apartment),
        ],
      ),
    );
  }

  Widget _addressLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF78909C),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Text(': ', style: TextStyle(color: Color(0xFF78909C))),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _techDark,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerContactCard(Map<String, dynamic> order) {
    final phone =
        _firstNonEmpty(order, const [
          'customer_phone',
          'customer_phone_number',
          'customer_additional_phone',
          'additional_customer_phone',
          'customer_phone2',
          'customer_phone_2',
          'secondary_phone',
          'phone2',
          'phone',
        ]) ??
        'غير متاح';

    final normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final additionalPhone = _firstNonEmpty(order, const [
      'customer_additional_phone',
      'additional_customer_phone',
      'customer_phone2',
      'customer_phone_2',
      'secondary_phone',
      'phone2',
    ]);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB8B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'رقم تواصل العميل',
            style: TextStyle(
              color: Color(0xFF8B1E1E),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          if (additionalPhone != null &&
              additionalPhone.isNotEmpty &&
              additionalPhone != phone) ...[
            const SizedBox(height: 6),
            const Text(
              'رقم التواصل الإضافي',
              style: TextStyle(
                color: Color(0xFF8B1E1E),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              additionalPhone,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              IconButton(
                tooltip: 'نسخ الرقم',
                onPressed: phone == 'غير متاح'
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: phone));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ رقم العميل.')),
                        );
                      },
                icon: const Icon(Icons.copy, color: Colors.red),
              ),
              const SizedBox(width: 2),
              ElevatedButton.icon(
                onPressed: normalized.isEmpty || phone == 'غير متاح'
                    ? null
                    : () async {
                        final uri = Uri(scheme: 'tel', path: normalized);
                        final ok = await launchUrl(uri);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تعذر فتح الاتصال بهذا الرقم.'),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.call, size: 18),
                label: const Text(
                  'اتصال',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _problemImageUrls(Map<String, dynamic> order) {
    final candidates = [
      order['problem_images'],
      order['problem_image_urls'],
      order['issue_images'],
      order['issue_image_urls'],
      order['customer_problem_images'],
      order['photos'],
      order['image_urls'],
      order['attachments'],
    ];

    final urls = <String>[];

    void add(dynamic value) {
      if (value == null) return;

      if (value is List) {
        for (final item in value) {
          add(item);
        }
        return;
      }

      if (value is Map) {
        for (final key in const ['url', 'image_url', 'public_url', 'path']) {
          final v = value[key];
          if (v != null) add(v);
        }
        return;
      }

      final raw = value.toString().trim();
      if (raw.isEmpty || raw == 'null') return;

      if ((raw.startsWith('[') && raw.endsWith(']')) ||
          (raw.startsWith('{') && raw.endsWith('}'))) {
        try {
          add(jsonDecode(raw));
          return;
        } catch (_) {}
      }

      for (final part in raw.split(RegExp(r'[,\n]+'))) {
        final item = part.trim();
        if (item.startsWith('http://') ||
            item.startsWith('https://') ||
            item.startsWith('orders/')) {
          if (!urls.contains(item)) urls.add(item);
        }
      }
    }

    for (final candidate in candidates) {
      add(candidate);
    }

    return urls;
  }

  Future<List<String>> _loadProblemImageUrls(Map<String, dynamic> order) async {
    final paths = _problemImageUrls(order);
    final orderId = (order['id'] ?? order['order_id'])?.toString().trim();

    // The technician feed RPC may omit the attachments field even though the
    // upload and append_customer_order_attachments RPC succeeded. Read the
    // saved order metadata directly before assuming there are no images.
    if (paths.isEmpty && orderId != null && orderId.isNotEmpty) {
      try {
        final row = await _db
            .from('orders')
            .select('attachments')
            .eq('id', orderId)
            .maybeSingle();
        if (row != null) {
          paths.addAll(_problemImageUrls({'attachments': row['attachments']}));
        }
      } catch (_) {
        // Continue with storage fallback; don't hide the rest of the order.
      }

      // Customer uploads use orders/<order-id>/<filename> in this bucket.
      // Listing is a fallback for older rows without attachment metadata.
      if (paths.isEmpty) {
        try {
          final files = await _db.storage
              .from('customer-order-attachments')
              .list(path: 'orders/$orderId');
          for (final file in files) {
            final name = file.name.trim();
            if (name.isEmpty || name == '.emptyFolderPlaceholder') continue;
            final path = 'orders/$orderId/$name';
            if (!paths.contains(path)) paths.add(path);
          }
        } catch (_) {
          // Storage RLS may deny listing; signed URL resolution below will
          // still work for any paths returned by the RPC/order row.
        }
      }
    }

    return _resolveProblemImageUrls(paths);
  }

  String _canonicalImageKey(String value) {
    final item = value.trim();
    if (item.startsWith('http://') || item.startsWith('https://')) {
      final uri = Uri.tryParse(item);
      if (uri != null) {
        final path = uri.path;
        final marker = '/customer-order-attachments/';
        final markerIndex = path.indexOf(marker);
        if (markerIndex >= 0) {
          return path.substring(markerIndex + marker.length);
        }
        return path;
      }
    }
    return item.replaceFirst(RegExp(r'^/+'), '');
  }

  Future<List<String>> _resolveProblemImageUrls(List<String> values) async {
    final result = <String>[];
    final resultKeys = <String>{};
    final storagePaths = <String>[];
    final storageKeys = <String>{};

    for (final value in values) {
      final item = value.trim();
      if (item.isEmpty) continue;
      final key = _canonicalImageKey(item);
      if (key.isEmpty) continue;
      if (item.startsWith('http://') || item.startsWith('https://')) {
        if (resultKeys.add(key)) result.add(item);
      } else if (storageKeys.add(key)) {
        storagePaths.add(item);
      }
    }

    if (storagePaths.isNotEmpty) {
      try {
        final signed = await _db.storage
            .from('customer-order-attachments')
            .createSignedUrls(storagePaths, 60 * 60);
        for (final entry in signed) {
          final url = entry.signedUrl;
          if (url.isEmpty) continue;
          final key = _canonicalImageKey(url);
          if (resultKeys.add(key)) result.add(url);
        }
      } catch (_) {
        // Resolve individually so one invalid path does not hide other images.
      }

      // Retry individual paths only when no signed URL for that file exists.
      for (final path in storagePaths) {
        final key = _canonicalImageKey(path);
        if (resultKeys.contains(key)) continue;
        try {
          final url = await _db.storage
              .from('customer-order-attachments')
              .createSignedUrl(path, 60 * 60);
          if (url.isNotEmpty && resultKeys.add(_canonicalImageKey(url))) {
            result.add(url);
          }
        } catch (_) {
          // Keep other images visible if one path cannot be signed.
        }
      }
    }

    return result;
  }

  Widget _problemImagesCard(Map<String, dynamic> order) {
    return FutureBuilder<List<String>>(
      future: _loadProblemImageUrls(order),
      builder: (context, snapshot) {
        final urls = snapshot.data ?? const <String>[];
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFD),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _techBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    color: _techBlue,
                    size: 20,
                  ),
                  SizedBox(width: 7),
                  Text(
                    'صور المشكلة',
                    style: TextStyle(
                      color: _techDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SizedBox(
                  height: 70,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (urls.isEmpty)
                const Text(
                  'لا توجد صور متاحة للعرض حاليًا، أو لم تُرفق صور بالمشكلة.',
                  style: TextStyle(
                    color: Color(0xFF78909C),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                SizedBox(
                  height: 125,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: urls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return InkWell(
                        onTap: () => showDialog<void>(
                          context: context,
                          barrierColor: Colors.black87,
                          builder: (dialogContext) => Dialog.fullscreen(
                            backgroundColor: Colors.black,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: InteractiveViewer(
                                    minScale: 0.5,
                                    maxScale: 5,
                                    child: Center(
                                      child: Image.network(
                                        urls[index],
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Text(
                                              'تعذر تحميل الصورة',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                                SafeArea(
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: IconButton(
                                      tooltip: 'إغلاق الصورة',
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(),
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            urls[index],
                            width: 125,
                            height: 125,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 125,
                              height: 125,
                              alignment: Alignment.center,
                              color: const Color(0xFFECEFF1),
                              child: const Text(
                                'تعذر عرض الصورة',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _paymentWaitingNotice() => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFD18A)),
    ),
    child: const Text(
      'إذا تم تحديد المصنعية داخل التطبيق ووافق العميل، يستكمل العميل الدفع وسيظهر لك تأكيد الإدارة.',
      style: TextStyle(
        color: Color(0xFF7A4D00),
        fontWeight: FontWeight.w800,
        height: 1.5,
      ),
    ),
  );

  Widget _inspectionPricingCard(Map<String, dynamic> order) {
    final orderId = int.tryParse(order['order_id']?.toString() ?? '');
    if (orderId == null) return const SizedBox.shrink();
    return FutureBuilder<Map<String, dynamic>?>(
      // Read both the settlement and the admin-controlled contact-deposit
      // release. The button must not appear merely because this is an
      // inspection order; the backend checks the same condition on submit.
      future: () async {
        final rows = await Future.wait<dynamic>([
          _db
              .from('inspection_settlements')
              .select('*')
              .eq('order_id', orderId)
              .maybeSingle(),
          _db
              .from('orders')
              .select(
                'contact_released_at,contact_deposit_paid,selected_offer_id,technician_id,status',
              )
              .eq('id', orderId)
              .maybeSingle(),
        ]);
        final settlement = rows[0] == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(rows[0] as Map);
        final orderState = rows[1] == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(rows[1] as Map);
        return <String, dynamic>{
          ...settlement,
          '_contact_released_at': orderState['contact_released_at'],
          '_contact_deposit_paid': orderState['contact_deposit_paid'],
          '_order_status': orderState['status'],
        };
      }(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final s = snap.data;
        final mode = s?['settlement_mode']?.toString() ?? 'pending';
        final labor = double.tryParse(s?['labor_price']?.toString() ?? '') ?? 0;
        final status = s?['status']?.toString() ?? 'pending';
        final depositPaid =
            double.tryParse(s?['_contact_deposit_paid']?.toString() ?? '') ?? 0;
        final contactReleased = s?['_contact_released_at'] != null;
        final externalAgreementAllowed = contactReleased && depositPaid >= 100;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _techBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'تسعير المصنعية بعد المعاينة',
                    style: TextStyle(
                      color: _techDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'إشعار دفع المعاينة قيد المراجعة من الإدارة.',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (mode == 'pending' && labor <= 0)
                    StatefulBuilder(
                      builder: (context, setLocal) {
                        // Keep the controller stable across Realtime rebuilds;
                        // otherwise a background update can erase typed pricing.
                        final controller = _inspectionPriceControllers
                            .putIfAbsent(orderId, TextEditingController.new);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'بعد المعاينة اكتب قيمة المصنعية النهائية.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF607D8B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: controller,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'قيمة المصنعية',
                                suffixText: 'جنيه',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 9),
                            ElevatedButton(
                              onPressed: () async {
                                final value = double.tryParse(
                                  controller.text.trim(),
                                );
                                if (value == null || value <= 0) {
                                  _message('اكتب قيمة المصنعية بشكل صحيح.');
                                  return;
                                }
                                try {
                                  await _db.rpc(
                                    'technician_set_inspection_labor_price',
                                    params: {
                                      'p_order_id': orderId,
                                      'p_labor_price': value,
                                    },
                                  );
                                  if (!mounted) return;
                                  _message(
                                    'تم إرسال قيمة المصنعية للعميل للموافقة.',
                                  );
                                  await _load();
                                } catch (e) {
                                  _message(_clean(e));
                                }
                              },
                              child: const Text(
                                'إرسال المصنعية للعميل',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  else if (mode == 'pending' && labor > 0) ...[
                    Text(
                      'المصنعية المحددة: ${_money(labor)} جنيه',
                      style: const TextStyle(
                        color: _techBlue,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'في انتظار موافقة العميل داخل التطبيق.',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ] else if (mode == 'external') ...[
                    const Text(
                      'تم تسجيل الاتفاق بالتراضي. يمكنك استكمال تنفيذ الخدمة من الزر الأخضر أدناه.',
                      style: TextStyle(
                        color: Color(0xFF168447),
                        height: 1.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ] else if (mode == 'no_agreement') ...[
                    const Text(
                      'لم يتم الاتفاق بعد المعاينة.',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'انتظر تعليمات الإدارة بشأن الخطوة التالية.',
                      style: TextStyle(
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'تمت تسوية المصنعية داخل التطبيق. يمكن متابعة الدفع/التنفيذ من حالة الطلب.',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!externalAgreementAllowed &&
                mode != 'external' &&
                mode != 'no_agreement') ...[
              const SizedBox(height: 8),
              const Text(
                'سيظهر زر الاتفاق بالتراضي بعد تأكيد الإدارة استلام المبلغ وفتح بيانات التواصل.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ] else if (s?['customer_approved'] != true &&
                mode != 'external' &&
                mode != 'no_agreement') ...[
              const SizedBox(height: 8),
              _paymentWaitingNotice(),
            ],
            if (externalAgreementAllowed &&
                mode != 'external' &&
                mode != 'no_agreement' &&
                status != 'finalized' &&
                status != 'cancelled') ...[
              const SizedBox(height: 9),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('تأكيد الاتفاق بالتراضي'),
                      content: const Text(
                        'هل تم الاتفاق مع العميل على المصنعية خارج التطبيق؟ سيتم إرسال الحالة للإدارة للمراجعة.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('رجوع'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('تأكيد الاتفاق'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                  try {
                    await _db.rpc(
                      'technician_confirm_external_inspection_agreement',
                      params: {'p_order_id': orderId},
                    );
                    if (!mounted) return;
                    _message(
                      'تم تسجيل الاتفاق بالتراضي وإرساله للإدارة للمراجعة.',
                    );
                    await _load();
                  } catch (e) {
                    _message(_clean(e));
                  }
                },
                icon: const Icon(Icons.handshake_outlined),
                label: const Text(
                  'تم الاتفاق بالتراضي',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF168447),
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: Color(0xFF168447)),
                ),
              ),
            ],
            if (mode == 'in_app' ||
                (mode == 'external' &&
                    externalAgreementAllowed &&
                    status != 'cancelled' &&
                    status != 'finalized' &&
                    s?['_order_status']?.toString() != 'completed')) ...[
              const SizedBox(height: 10),
              if (mode == 'external' &&
                  externalAgreementAllowed &&
                  status != 'cancelled' &&
                  status != 'finalized' &&
                  s?['_order_status']?.toString() != 'completed')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _finishService(order),
                    icon: const Icon(Icons.task_alt_rounded, size: 24),
                    label: const Text(
                      'تم التنفيذ/إنهاء الخدمة',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: const Color(0xFF168447),
                      foregroundColor: Colors.white,
                    ),
                  ),
                )
              else
                _paymentStatusCard(orderId, order),
            ],
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  Widget _paymentStatusCard(int orderId, Map<String, dynamic> order) {
    return FutureBuilder<dynamic>(
      future: _db.rpc(
        'technician_get_order_payment_state',
        params: {'p_order_id': orderId},
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        final raw = snapshot.data;
        final state = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
        final remaining =
            double.tryParse(state['remaining_amount']?.toString() ?? '') ?? 0;
        final noticePending = state['remaining_notice_pending'] == true;
        final adminConfirmed = state['admin_payment_confirmed_at'] != null;
        final String message;
        final Color color;
        final IconData icon;
        if (adminConfirmed &&
            remaining <= 0 &&
            state['payment_status'] == 'paid') {
          message = state['status']?.toString() == 'completed'
              ? 'شكرًا لإتمام مهمتك بنجاح، استعد لاستقبال عروض جديدة.'
              : 'أكدت الإدارة استلام الدفع. يمكنك تنفيذ الخدمة، وبعد الانتهاء اضغط «إنهاء الخدمة».';
          color = const Color(0xFF168447);
          icon = Icons.verified_rounded;
        } else if (state['customer_notice_pending'] == true) {
          message = noticePending
              ? 'العميل أرسل إشعار سداد المتبقي. الطلب في انتظار تأكيد الإدارة الفعلي.'
              : (order['requires_inspection'] == true &&
                        order['contact_released_at'] == null
                    ? 'العميل أرسل إشعار دفع المعاينة. في انتظار تأكيد الإدارة الفعلي.'
                    : 'العميل أرسل إشعار الدفع. في انتظار تأكيد الإدارة الفعلي.');
          color = const Color(0xFF9A6200);
          icon = Icons.hourglass_top_rounded;
        } else if (remaining > 0) {
          message =
              order['requires_inspection'] == true &&
                  order['contact_released_at'] == null
              ? 'في انتظار إشعار سداد المعاينة ومراجعته من الإدارة.'
              : 'في انتظار إشعار السداد من العميل وتأكيد الإدارة.';
          color = const Color(0xFF9A6200);
          icon = Icons.payments_outlined;
        } else {
          message = 'في انتظار تحديث حالة الدفع.';
          color = const Color(0xFF607D8B);
          icon = Icons.info_outline;
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (adminConfirmed &&
                  remaining <= 0 &&
                  state['payment_status'] == 'paid' &&
                  state['status']?.toString() != 'completed' &&
                  state['status']?.toString() != 'cancelled') ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: state['status']?.toString() == 'completed'
                        ? null
                        : () => _finishService(order),
                    icon: const Icon(Icons.task_alt_rounded, size: 24),
                    label: const Text(
                      'تم التنفيذ/إنهاء الخدمة',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: const Color(0xFF168447),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _payoutDetailItem(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),

      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),

        borderRadius: BorderRadius.circular(10),

        border: Border.all(color: _techBorder),
      ),

      child: Row(
        children: [
          Expanded(
            child: Text(
              label,

              style: const TextStyle(
                color: Color(0xFF546E7A),

                fontWeight: FontWeight.w700,

                fontSize: 12,
              ),
            ),
          ),

          const SizedBox(width: 8),

          Text(
            value,

            style: TextStyle(
              color: valueColor,

              fontWeight: FontWeight.w900,

              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  String _money(dynamic value) {
    if (value == null) return '—';

    final n = double.tryParse(value.toString());

    if (n == null) return value.toString();

    if (n == n.roundToDouble()) return n.toStringAsFixed(0);

    return n.toStringAsFixed(2);
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          SizedBox(
            width: 105,

            child: Text(
              label,

              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF607D8B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          Expanded(
            child: Text(
              value,

              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: Color(0xFF263746),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _firstNonEmpty(Map<String, dynamic> order, List<String> keys) {
    for (final key in keys) {
      final value = order[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }

    return null;
  }

  String _appointmentLabel(dynamic fromValue, dynamic toValue) {
    final from = _parseDate(fromValue);

    final to = _parseDate(toValue);

    if (from == null && to == null) return '—';

    final dayDate = from != null
        ? '${_arabicDayName(from)}\n${_dateOnly(from)}'
        : '${_arabicDayName(to!)}\n${_dateOnly(to)}';

    if (from == null) {
      return '$dayDate\nإلى ${_timeOnly12(to!)}';
    }

    if (to == null) {
      return '$dayDate\nمن ${_timeOnly12(from)}';
    }

    final sameDate =
        from.year == to.year && from.month == to.month && from.day == to.day;

    if (sameDate) {
      return '$dayDate\nمن ${_timeOnly12(from)} إلى ${_timeOnly12(to)}';
    }

    return '$dayDate\nمن ${_timeOnly12(from)} إلى '
        '${_arabicDayName(to)} ${_dateOnly(to)} ${_timeOnly12(to)}';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _dateOnly(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _timeOnly12(DateTime date) {
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;

    final minute = date.minute.toString().padLeft(2, '0');

    final period = date.hour < 12 ? 'صباحًا' : 'مساءً';

    return '$hour12:$minute $period';
  }

  String _arabicDayName(DateTime date) {
    const days = <String>[
      'الاثنين',

      'الثلاثاء',

      'الأربعاء',

      'الخميس',

      'الجمعة',

      'السبت',

      'الأحد',
    ];

    return days[date.weekday - 1];
  }

  Widget _empty() {
    return const Padding(
      padding: EdgeInsets.all(30),

      child: Text(
        'لا توجد طلبات جديدة متاحة لمهنتك حاليًا. استعد لاستقبال طلبات جديدة.',

        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _errorCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: Colors.red.shade50,

        borderRadius: BorderRadius.circular(14),
      ),

      child: Text(
        text,

        textAlign: TextAlign.center,

        style: TextStyle(color: Colors.red.shade700),
      ),
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _OfferSheet extends StatefulWidget {
  const _OfferSheet({required this.order});

  final Map<String, dynamic> order;

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  final _price = TextEditingController();

  final _note = TextEditingController();

  bool _inspection = false;
  bool _same = false;
  bool _suppliesProvided = false;

  DateTime? _from;

  DateTime? _to;

  @override
  void initState() {
    super.initState();

    _same = false;

    _inspection = widget.order['requires_inspection'] == true;
    _suppliesProvided = widget.order['supplies_provided'] == true;

    final existingPrice = widget.order['labor_price'];

    if (existingPrice != null) {
      _price.text = existingPrice.toString();
    }

    if (widget.order['response_note'] != null) {
      _note.text = widget.order['response_note'].toString();
    }

    _from = _parse(widget.order['technician_available_from']);

    _to = _parse(widget.order['technician_available_to']);

    // لا نملأ الموعد البديل تلقائيًا بموعد العميل.

    // الفني يحدد الموعد البديل بنفسه إذا لم يختر نفس موعد العميل.
  }

  @override
  void dispose() {
    _price.dispose();

    _note.dispose();
    super.dispose();
  }

  DateTime? _parse(dynamic value) {
    if (value == null) return null;

    return DateTime.tryParse(value.toString())?.toLocal();
  }

  Future<void> _pickTime(bool from) async {
    final base =
        _parse(
          from ? widget.order['scheduled_at'] : widget.order['scheduled_to'],
        ) ??
        DateTime.now();

    final date = await showDatePicker(
      context: context,

      initialDate: (from ? _from : _to) ?? base,

      firstDate: DateTime.now(),

      lastDate: DateTime.now().add(const Duration(days: 90)),

      locale: const Locale('ar'),
    );

    if (date == null) return;

    final time = await showTimePicker(
      context: context,

      initialTime: TimeOfDay.fromDateTime((from ? _from : _to) ?? base),

      builder: (context, child) {
        final media = MediaQuery.of(context);

        return MediaQuery(
          data: media.copyWith(alwaysUse24HourFormat: false),

          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (time == null) return;

    final value = DateTime(
      date.year,

      date.month,

      date.day,

      time.hour,

      time.minute,
    );

    setState(() {
      if (from) {
        _from = value;
      } else {
        _to = value;
      }

      _same = false;
    });
  }

  void _submit() {
    DateTime? availableFrom = _same
        ? _parse(widget.order['scheduled_at'])
        : _from;
    DateTime? availableTo = _same ? _parse(widget.order['scheduled_to']) : _to;

    if (availableFrom == null ||
        availableTo == null ||
        !availableTo.isAfter(availableFrom)) {
      _message(
        'حدد فترة تواجد صحيحة، أو اختر نفس موعد العميل إذا كان مناسبًا لك.',
      );
      return;
    }

    final price = double.tryParse(_price.text.trim());
    if (!_inspection && (price == null || price <= 0)) {
      _message('اكتب المصنعية أو اختر المعاينة.');
      return;
    }

    Navigator.pop(context, {
      'p_order_id': widget.order['order_id'],
      'p_labor_price': _inspection ? null : price,
      'p_requires_inspection': _inspection,
      'p_supplies_provided': _suppliesProvided,
      // No material price/proof/shop/delivery values are sent in an initial offer.
      'p_available_from': availableFrom.toUtc().toIso8601String(),
      'p_available_to': availableTo.toUtc().toIso8601String(),
      'p_response_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),

      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),

        padding: const EdgeInsets.all(20),

        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const Text(
                'تقديم عرضك',

                style: TextStyle(
                  fontSize: 20,

                  fontWeight: FontWeight.w800,

                  color: _techDark,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'حدد المصنعية وموعد تواجدك. إذا فعّلت خيار توفير الخامات، ستظهر الشروط والحقول اللازمة لإرسال العرض.',

                style: TextStyle(color: Color(0xFF607D8B), height: 1.5),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: _price,

                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),

                enabled: !_inspection,

                decoration: const InputDecoration(
                  labelText: 'المصنعية بالجنيه',

                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 6),

              CheckboxListTile(
                contentPadding: EdgeInsets.zero,

                value: _inspection,

                onChanged: (v) {
                  setState(() {
                    _inspection = v ?? false;
                  });
                },

                title: const Text('لا يمكن تحديد المصنعية إلا بعد الاطلاع'),
              ),

              const Divider(),

              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _suppliesProvided,
                onChanged: (value) => setState(() {
                  _suppliesProvided = value ?? false;
                }),
                title: const Text(
                  'أستطيع توفير الخامات عند الحاجة',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'هذا تأكيد للاستعداد للتوفير فقط، وليس اعتمادًا لسعر الخامات.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              if (_suppliesProvided)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FBF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB7E4C7)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Color(0xFF168447),
                          ),
                          SizedBox(width: 7),
                          Text(
                            'شروط توفير الخامات',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF126B39),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• يجب توفير الفاتورة أو اسم ورقم المحل للعميل.',
                        style: TextStyle(fontSize: 11, height: 1.6),
                      ),
                      Text(
                        '• عند الحاجة للنقل، يجب توفير اسم ورقم السائق للعميل.',
                        style: TextStyle(fontSize: 11, height: 1.6),
                      ),
                      Text(
                        '• مستحق الفني مقابل خدمة توفير الخامات 3% من قيمة الخامات، بحد أدنى 15 جنيهًا؛ ويُحسب بعد اعتماد القيمة الفعلية، وليس في هذا النموذج.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF126B39),
                        ),
                      ),
                    ],
                  ),
                ),

              const Divider(),

              CheckboxListTile(
                contentPadding: EdgeInsets.zero,

                value: _same,

                onChanged: (v) {
                  final same = v ?? false;

                  setState(() {
                    _same = same;
                    if (same) {
                      _from = _parse(widget.order['scheduled_at']);
                      _to = _parse(widget.order['scheduled_to']);
                    } else {
                      _from = null;
                      _to = null;
                    }
                  });
                },

                title: const Text(
                  'متوفر في نفس الموعد الذي حدده العميل',

                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),

              if (!_same) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),

                  child: Text(
                    'موعد بديل متاح لك',

                    style: TextStyle(
                      fontWeight: FontWeight.w800,

                      color: _techDark,
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.only(bottom: 10),

                  child: Text(
                    'إذا لم تكن متاحًا في موعد العميل، حدّد تاريخ ووقت البداية والنهاية للموعد البديل. هذا الموعد سيُرسل للعميل مع عرضك.',

                    style: TextStyle(
                      fontSize: 11,

                      color: Color(0xFF607D8B),

                      height: 1.5,
                    ),
                  ),
                ),

                Row(
                  children: [
                    Expanded(
                      child: _timeButton('من', _from, () => _pickTime(true)),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: _timeButton('إلى', _to, () => _pickTime(false)),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              TextField(
                controller: _note,

                maxLines: 3,

                decoration: const InputDecoration(
                  labelText: 'ملاحظات العرض (اختياري)',

                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,

                height: 50,

                child: ElevatedButton(
                  onPressed: _submit,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: _techBlue,

                    foregroundColor: Colors.white,
                  ),

                  child: const Text(
                    'إرسال العرض',

                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeOnly12(DateTime date) {
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;

    final minute = date.minute.toString().padLeft(2, '0');

    final period = date.hour < 12 ? 'صباحًا' : 'مساءً';

    return '$hour12:$minute $period';
  }

  Widget _timeButton(String label, DateTime? date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(12),

      child: Container(
        height: 62,

        padding: const EdgeInsets.all(12),

        decoration: BoxDecoration(
          border: Border.all(color: _techBorder),

          borderRadius: BorderRadius.circular(12),
        ),

        child: Text(
          '$label: ${date == null ? 'حدد الموعد' : '${date.day}/${date.month}/${date.year}\n${_timeOnly12(date)}'}',

          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
