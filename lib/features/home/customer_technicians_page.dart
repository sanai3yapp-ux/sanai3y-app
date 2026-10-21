import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerTechniciansPage extends StatefulWidget {
  const CustomerTechniciansPage({
    super.key,
    required this.professionId,
    required this.professionName,
    required this.service,
    required this.cityId,
    required this.areaId,
    required this.address,
    required this.problemDescription,
    required this.quantity,
    required this.scheduledAt,
  });

  final dynamic professionId;
  final String professionName;
  final Map<String, dynamic> service;

  final dynamic cityId;
  final dynamic areaId;

  final String address;
  final String problemDescription;

  final double? quantity;
  final DateTime scheduledAt;

  @override
  State<CustomerTechniciansPage> createState() =>
      _CustomerTechniciansPageState();
}

class _CustomerTechniciansPageState
    extends State<CustomerTechniciansPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _technicians = [];

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    try {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }

      final serviceId = widget.service['id'];

      if (serviceId == null) {
        throw Exception('service id is missing');
      }

      /*
       * ============================================================
       * 1) نجيب الصنايعية اللي مسجلين على المهنة المطلوبة
       * ============================================================
       */

      final professionTechnicians = await _supabase
          .from('technician_professions')
          .select(
            '''
            technician_id,
            profession_id
            ''',
          )
          .eq('profession_id', widget.professionId);

      final professionRows =
          List<Map<String, dynamic>>.from(professionTechnicians);

      if (professionRows.isEmpty) {
        if (!mounted) return;

        setState(() {
          _technicians = [];
          _loading = false;
        });

        return;
      }

      final technicianIds = professionRows
          .map((row) => row['technician_id'])
          .where((id) => id != null)
          .toList();

      if (technicianIds.isEmpty) {
        if (!mounted) return;

        setState(() {
          _technicians = [];
          _loading = false;
        });

        return;
      }

      /*
       * ============================================================
       * 2) نجيب الصنايعية الأساسيين
       *
       * is_available  = متاح
       * is_visible    = ظاهر للعملاء
       * is_verified   = تم التحقق منه
       * ============================================================
       */

      final techniciansResult = await _supabase
          .from('technicians')
          .select(
            '''
            id,
            full_name,
            phone,
            phone2,
            whatsapp_phone,
            profession_id,
            address,
            years_experience,
            description,
            is_available,
            rating,
            profile_image,
            is_verified,
            city_id,
            account_status,
            application_status,
            is_visible
            ''',
          )
          .inFilter('id', technicianIds)
          .eq('is_available', true)
          .eq('is_verified', true)
          .eq('is_visible', true);

      final technicians =
          List<Map<String, dynamic>>.from(techniciansResult);

      if (technicians.isEmpty) {
        if (!mounted) return;

        setState(() {
          _technicians = [];
          _loading = false;
        });

        return;
      }

      /*
       * ============================================================
       * 3) نجيب الصنايعية اللي بيغطوا المنطقة المطلوبة
       * ============================================================
       */

      final areaTechniciansResult = await _supabase
          .from('technician_areas')
          .select(
            '''
            technician_id,
            area_id
            ''',
          )
          .eq('area_id', widget.areaId)
          .inFilter('technician_id', technicianIds);

      final areaRows =
          List<Map<String, dynamic>>.from(areaTechniciansResult);

      final areaTechnicianIds = areaRows
          .map((row) => row['technician_id'])
          .where((id) => id != null)
          .toSet();

      /*
       * ============================================================
       * 4) نجيب أسعار الخدمة من service_prices
       * ============================================================
       */

      final pricesResult = await _supabase
          .from('service_prices')
          .select(
            '''
            id,
            technician_id,
            service_id,
            price,
            price_note,
            is_active,
            inspection_fee,
            includes_inspection,
            inspection_fee_deductible
            ''',
          )
          .eq('service_id', serviceId)
          .eq('is_active', true)
          .inFilter('technician_id', technicianIds);

      final prices =
          List<Map<String, dynamic>>.from(pricesResult);

      /*
       * نعمل Map للسعر حسب technician_id
       */
      final Map<dynamic, Map<String, dynamic>> priceByTechnician = {};

      for (final price in prices) {
        final technicianId = price['technician_id'];

        if (technicianId != null) {
          priceByTechnician[technicianId] = price;
        }
      }

      /*
       * ============================================================
       * 5) تجهيز القائمة النهائية
       * ============================================================
       */

      final List<Map<String, dynamic>> finalTechnicians = [];

      for (final technician in technicians) {
        final technicianId = technician['id'];

        /*
         * لازم الصنايعي يكون بيغطي المنطقة.
         */
        if (!areaTechnicianIds.contains(technicianId)) {
          continue;
        }

        /*
         * لازم يكون عنده سعر للخدمة.
         *
         * ده مهم لأن النظام عندك بيمنع الصنايعي من ترك
         * أسعار الخدمات المطلوبة بدون سعر.
         */
        final price = priceByTechnician[technicianId];

        if (price == null) {
          continue;
        }

        final item = Map<String, dynamic>.from(technician);

        item['service_price_data'] = price;

        finalTechnicians.add(item);
      }

      /*
       * ============================================================
       * 6) ترتيب القائمة
       *
       * الأول حسب التقييم الأعلى.
       * لو مفيش تقييم، نعتبره صفر.
       * ============================================================
       */

      finalTechnicians.sort((a, b) {
        final ratingA =
            (a['rating'] as num?)?.toDouble() ?? 0.0;

        final ratingB =
            (b['rating'] as num?)?.toDouble() ?? 0.0;

        return ratingB.compareTo(ratingA);
      });

      if (!mounted) return;

      setState(() {
        _technicians = finalTechnicians;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الصنايعية المتاحين حاليًا.';
      });
    }
  }

  String get _serviceName {
    return widget.service['service_name']?.toString() ?? 'الخدمة';
  }

  String get _pricingType {
    return widget.service['pricing_type']?.toString() ?? 'fixed';
  }

  bool get _isInspection {
    return _pricingType == 'inspection';
  }

  String _formatPrice(dynamic value) {
    if (value == null) {
      return '';
    }

    final number = double.tryParse(value.toString());

    if (number == null) {
      return value.toString();
    }

    if (number == number.roundToDouble()) {
      return number.toInt().toString();
    }

    return number.toStringAsFixed(2);
  }

  String _priceText(Map<String, dynamic> technician) {
    final priceData =
        technician['service_price_data'] as Map<String, dynamic>?;

    if (priceData == null) {
      return 'السعر غير متاح';
    }

    final price = priceData['price'];
    final inspectionFee = priceData['inspection_fee'];

    /*
     * خدمة المعاينة
     */
    if (_isInspection) {
      if (inspectionFee != null) {
        final formattedFee = _formatPrice(inspectionFee);

        if (formattedFee.isNotEmpty && formattedFee != '0') {
          return 'معاينة: $formattedFee جنيه';
        }
      }

      return 'السعر بعد المعاينة';
    }

    /*
     * الخدمات ذات السعر
     */
    if (price == null) {
      return 'السعر بعد المعاينة';
    }

    final formattedPrice = _formatPrice(price);

    if (_pricingType == 'per_meter') {
      return '$formattedPrice جنيه / متر';
    }

    if (_pricingType == 'per_piece') {
      return '$formattedPrice جنيه / قطعة';
    }

    return '$formattedPrice جنيه';
  }

  String _experienceText(dynamic years) {
    if (years == null) {
      return 'الخبرة غير محددة';
    }

    final value = int.tryParse(years.toString());

    if (value == null) {
      return 'الخبرة غير محددة';
    }

    if (value == 1) {
      return 'خبرة سنة';
    }

    if (value == 2) {
      return 'خبرة سنتين';
    }

    if (value >= 3 && value <= 10) {
      return 'خبرة $value سنوات';
    }

    return 'خبرة $value سنة';
  }

  void _selectTechnician(
    Map<String, dynamic> technician,
  ) {
    final technicianId = technician['id'];

    if (technicianId == null) {
      _showMessage('تعذر اختيار الصنايعي.');
      return;
    }

    /*
     * لسه مش هننشئ الطلب في قاعدة البيانات هنا.
     *
     * الخطوة الحالية فقط اختيار الصنايعي.
     *
     * بعد الاختيار هنضيف صفحة تأكيد نهائية ثم إنشاء orders.
     */

    _showMessage(
      'تم اختيار ${technician['full_name'] ?? 'الصنايعي'}',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
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
            'اختيار الصنايعي',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF087FD0),
        ),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadTechnicians,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            const SizedBox(height: 100),
            _buildError(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTechnicians,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          _buildOrderSummary(),

          const SizedBox(height: 22),

          const Text(
            'الصنايعية المتاحين',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF073A68),
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'اختر الصنايعي المناسب لتنفيذ الخدمة',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF78909C),
            ),
          ),

          const SizedBox(height: 16),

          if (_technicians.isEmpty)
            _buildEmptyState()
          else
            ..._technicians.map(
              (technician) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildTechnicianCard(technician),
              ),
            ),

          const SizedBox(height: 25),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFDDEAF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تفاصيل الخدمة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF073A68),
            ),
          ),

          const SizedBox(height: 15),

          _buildSummaryRow(
            Icons.handyman_outlined,
            'المهنة',
            widget.professionName,
          ),

          const SizedBox(height: 10),

          _buildSummaryRow(
            Icons.build_outlined,
            'الخدمة',
            _serviceName,
          ),

          const SizedBox(height: 10),

          _buildSummaryRow(
            Icons.location_on_outlined,
            'العنوان',
            widget.address,
          ),

          const SizedBox(height: 10),

          _buildSummaryRow(
            Icons.calendar_month_outlined,
            'الموعد',
            _formatDateTime(widget.scheduledAt),
          ),

          if (widget.quantity != null) ...[
            const SizedBox(height: 10),
            _buildSummaryRow(
              Icons.format_list_numbered,
              'الكمية',
              widget.quantity.toString(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: const Color(0xFF087FD0),
          size: 21,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF78909C),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF073A68),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTechnicianCard(
    Map<String, dynamic> technician,
  ) {
    final name =
        technician['full_name']?.toString().trim().isNotEmpty == true
            ? technician['full_name'].toString().trim()
            : 'صنايعي';

    final rating =
        (technician['rating'] as num?)?.toDouble() ?? 0.0;

    final experience =
        _experienceText(technician['years_experience']);

    final description =
        technician['description']?.toString().trim() ?? '';

    final priceText = _priceText(technician);

    final isAvailable =
        technician['is_available'] == true;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _selectTechnician(technician),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFDDEAF2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildProfileImage(technician),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF073A68),
                          ),
                        ),

                        const SizedBox(height: 6),

                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 17,
                              color: Color(0xFFFFB300),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating > 0
                                  ? rating.toStringAsFixed(1)
                                  : 'جديد',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF607D8B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  _buildAvailabilityBadge(isAvailable),
                ],
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  _buildSmallInfo(
                    Icons.workspace_premium_outlined,
                    experience,
                  ),
                ],
              ),

              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),

                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF78909C),
                    height: 1.5,
                  ),
                ),
              ],

              const SizedBox(height: 15),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F6FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      color: Color(0xFF087FD0),
                      size: 21,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        priceText,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF073A68),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 13),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () =>
                      _selectTechnician(technician),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF087FD0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'اختيار الصنايعي',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
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

  Widget _buildProfileImage(
    Map<String, dynamic> technician,
  ) {
    final imagePath =
        technician['profile_image']?.toString().trim() ?? '';

    if (imagePath.isNotEmpty &&
        (imagePath.startsWith('http://') ||
            imagePath.startsWith('https://'))) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          imagePath,
          width: 62,
          height: 62,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return _buildDefaultAvatar();
          },
        ),
      );
    }

    return _buildDefaultAvatar();
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F6FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(
        Icons.person_outline,
        size: 34,
        color: Color(0xFF087FD0),
      ),
    );
  }

  Widget _buildAvailabilityBadge(
    bool available,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: available
            ? const Color(0xFFE8F7EE)
            : const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        available ? 'متاح' : 'غير متاح',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: available
              ? const Color(0xFF218838)
              : const Color(0xFF78909C),
        ),
      ),
    );
  }

  Widget _buildSmallInfo(
    IconData icon,
    String text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 17,
            color: const Color(0xFF087FD0),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF607D8B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFDDEAF2),
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 55,
            color: Color(0xFF90A4AE),
          ),
          SizedBox(height: 14),
          Text(
            'لا يوجد صنايعية متاحين حاليًا',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF073A68),
            ),
          ),
          SizedBox(height: 7),
          Text(
            'لا يوجد حاليًا صنايعي متاح لهذه الخدمة في المنطقة المختارة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF78909C),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.red.shade100,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 45,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'حدث خطأ.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: _loadTechnicians,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();

    final hour =
        dateTime.hour.toString().padLeft(2, '0');

    final minute =
        dateTime.minute.toString().padLeft(2, '0');

    return '$day/$month/$year - $hour:$minute';
  }
}