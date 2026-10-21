import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/customer_home_page.dart';

class CustomerRegistrationPage extends StatefulWidget {
  const CustomerRegistrationPage({super.key});

  @override
  State<CustomerRegistrationPage> createState() =>
      _CustomerRegistrationPageState();
}

class _CustomerRegistrationPageState
    extends State<CustomerRegistrationPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loading = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;

  String? _error;

  List<Map<String, dynamic>> _cities = [];
  List<Map<String, dynamic>> _areas = [];

  int? _selectedCityId;
  int? _selectedAreaId;

  bool _loadingCities = true;
  bool _loadingAreas = false;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  // ============================================================
  // LOAD CITIES
  // ============================================================

  Future<void> _loadCities() async {
    try {
      final result = await _supabase
          .from('cities')
          .select('id, name_ar, name_en')
          .eq('is_active', true)
          .order('sort_order')
          .order('id');

      if (!mounted) return;

      setState(() {
        _cities = List<Map<String, dynamic>>.from(result);
        _loadingCities = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingCities = false;
        _error = 'تعذر تحميل المدن.';
      });
    }
  }

  // ============================================================
  // LOAD AREAS
  // ============================================================

  Future<void> _loadAreas(int cityId) async {
    setState(() {
      _loadingAreas = true;
      _areas = [];
      _selectedAreaId = null;
    });

    try {
      final result = await _supabase
          .from('areas')
          .select('id, name_ar, name_en')
          .eq('city_id', cityId)
          .eq('is_active', true)
          .order('sort_order')
          .order('id');

      if (!mounted) return;

      setState(() {
        _areas = List<Map<String, dynamic>>.from(result);
        _loadingAreas = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingAreas = false;
        _error = 'تعذر تحميل المناطق.';
      });
    }
  }

  // ============================================================
  // PHONE
  // ============================================================

  String _normalizePhone(String value) {
    var phone = value.trim().replaceAll(' ', '');

    if (phone.startsWith('+20')) {
      return phone;
    }

    if (phone.startsWith('0020')) {
      return '+${phone.substring(2)}';
    }

    if (phone.startsWith('01') && phone.length == 11) {
      return '+20${phone.substring(1)}';
    }

    return phone;
  }

  // الحساب الداخلي للعميل داخل Supabase Auth.
  // العميل لا يرى هذا الـEmail؛ هو يستخدم رقم الهاتف فقط.
  String _customerInternalEmail(String normalizedPhone) {
    var localPhone = normalizedPhone;

    if (localPhone.startsWith('+20')) {
      localPhone = '0${localPhone.substring(3)}';
    } else if (localPhone.startsWith('0020')) {
      localPhone = '0${localPhone.substring(4)}';
    }

    return 'customer.$localPhone@sana3y.app';
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  String? _validate() {
    final name = _nameController.text.trim();
    final phone = _normalizePhone(_phoneController.text);
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty) {
      return 'من فضلك أدخل الاسم بالكامل.';
    }

    if (name.length < 3) {
      return 'الاسم يجب أن يكون 3 أحرف على الأقل.';
    }

    if (phone.isEmpty) {
      return 'من فضلك أدخل رقم الهاتف.';
    }

    if (!RegExp(r'^\+20(10|11|12|15)\d{8}$').hasMatch(phone)) {
      return 'من فضلك أدخل رقم هاتف مصري صحيح.';
    }

    if (pin.length != 6) {
      return 'الـ PIN يجب أن يتكون من 6 أرقام.';
    }

    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      return 'الـ PIN يجب أن يحتوي على أرقام فقط.';
    }

    if (pin != confirmPin) {
      return 'تأكيد الـ PIN غير مطابق.';
    }

    if (_selectedCityId == null) {
      return 'من فضلك اختر المدينة.';
    }

    if (_selectedAreaId == null) {
      return 'من فضلك اختر المنطقة.';
    }

    if (address.isEmpty) {
      return 'من فضلك أدخل العنوان.';
    }

    return null;
  }

  // ============================================================
  // REGISTER
  // ============================================================

  Future<Map<String, dynamic>> _customerAuth({
    required String action,
    required String phone,
    required String pin,
  }) async {
    final response = await _supabase.functions.invoke(
      'customer-auth',
      body: {'action': action, 'phone': phone, 'pin': pin},
    );

    final data = response.data;
    if (data is! Map) {
      throw const AuthException('تعذر قراءة استجابة نظام تسجيل العميل.');
    }

    final result = Map<String, dynamic>.from(data);
    if (response.status < 200 || response.status >= 300) {
      final message = result['error']?.toString();
      throw AuthException(
        message == null || message.isEmpty
            ? 'تعذر إنشاء حساب العميل. حاول مرة أخرى.'
            : message,
      );
    }

    return result;
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var phone = _phoneController.text.trim().replaceAll(RegExp(r'\s+'), '');
      if (phone.startsWith('+20')) {
        phone = '0${phone.substring(3)}';
      } else if (phone.startsWith('0020')) {
        phone = '0${phone.substring(4)}';
      }
      final pin = _pinController.text.trim();

      // التسجيل يستخدم نفس customer-auth المستخدم في تسجيل الدخول.
      // بذلك تصبح صيغة حساب Auth وكلمة المرور موحدة ولا يحدث 401 بسبب اختلاف مسار التسجيل.
      final result = await _customerAuth(
        action: 'register',
        phone: phone,
        pin: pin,
      );

      final refreshToken = result['refresh_token']?.toString();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const AuthException('تم إنشاء الحساب لكن تعذر إنشاء جلسة العميل.');
      }

      await _supabase.auth.setSession(refreshToken);
      final userId = result['user_id']?.toString() ?? _supabase.auth.currentUser?.id;
      final customerId = result['customer_id'];

      if (userId == null || userId.isEmpty) {
        throw const AuthException('تم إنشاء الحساب لكن تعذر تحديد حساب العميل.');
      }

      final update = <String, dynamic>{
        'full_name': _nameController.text.trim(),
        'phone': phone,
        'city_id': _selectedCityId,
        'default_area_id': _selectedAreaId,
        'address': _addressController.text.trim(),
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      };

      if (customerId != null) {
        await _supabase.from('customers').update(update).eq('id', customerId);
      } else {
        await _supabase.from('customers').update(update).eq('user_id', userId);
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const CustomerHomePage()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ============================================================
  // AUTH ERROR
  // ============================================================

  String _translateAuthError(AuthException e) {
    final message = e.message.toLowerCase();

    if (message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('user already')) {
      return 'رقم الهاتف مسجل بالفعل.';
    }

    if (message.contains('invalid phone')) {
      return 'رقم الهاتف غير صحيح.';
    }

    if (message.contains('password')) {
      return 'الـ PIN غير صالح.';
    }

    if (message.contains('email') &&
        (message.contains('already') || message.contains('exists'))) {
      return 'رقم الهاتف مسجل بالفعل.';
    }

    return e.message;
  }

  // ============================================================
  // DATABASE ERROR
  // ============================================================

  String _translateDatabaseError(PostgrestException e) {
    if (e.code == '23505') {
      return 'رقم الهاتف مسجل بالفعل.';
    }

    if (e.code == '23503') {
      return 'المدينة أو المنطقة المختارة غير صحيحة.';
    }

    if (e.code == '42501') {
      return 'ليس لديك صلاحية إنشاء حساب العميل.';
    }

    return e.message;
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontSize: 12,
        color: Colors.grey,
      ),
      prefixIcon: Icon(
        icon,
        size: 19,
        color: const Color(0xFF55758D),
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: Color(0xFFD7E5EF),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: Color(0xFFD7E5EF),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(
          color: Color(0xFF0878BD),
          width: 1.5,
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _addressController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5FAFD),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF062E49),
          centerTitle: true,
          title: const Text(
            'إنشاء حساب عميل',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 480,
                ),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildForm(),
                    const SizedBox(height: 20),
                    _buildLoginHint(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 78,
          height: 78,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(21),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/account_type/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'صنايعي',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            color: Color(0xFF062E49),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'أنشئ حسابك وابحث عن الحرفي المناسب لك',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF55758D),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // FORM
  // ============================================================

  Widget _buildForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _label('الاسم بالكامل'),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              hint: 'مثال: أحمد محمد',
              icon: Icons.person_outline,
            ),
          ),

          const SizedBox(height: 13),

          Align(
            alignment: Alignment.centerRight,
            child: _label('رقم الهاتف'),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              hint: '01xxxxxxxxx',
              icon: Icons.phone_outlined,
            ),
          ),

          const SizedBox(height: 13),

          Align(
            alignment: Alignment.centerRight,
            child: _label('كلمة المرور PIN'),
          ),
          const SizedBox(height: 2),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              '6 أرقام تستخدمها عند تسجيل الدخول',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 6),

          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            maxLength: 6,
            obscureText: _obscurePin,
            decoration: _decoration(
              hint: '••••••',
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscurePin = !_obscurePin;
                  });
                },
                icon: Icon(
                  _obscurePin
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                ),
              ),
            ).copyWith(
              counterText: '',
            ),
          ),

          const SizedBox(height: 13),

          Align(
            alignment: Alignment.centerRight,
            child: _label('تأكيد كلمة المرور'),
          ),
          const SizedBox(height: 6),

          TextField(
            controller: _confirmPinController,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            maxLength: 6,
            obscureText: _obscureConfirmPin,
            decoration: _decoration(
              hint: '••••••',
              icon: Icons.lock_reset_outlined,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscureConfirmPin = !_obscureConfirmPin;
                  });
                },
                icon: Icon(
                  _obscureConfirmPin
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                ),
              ),
            ).copyWith(
              counterText: '',
            ),
          ),

          const SizedBox(height: 13),

          Align(
            alignment: Alignment.centerRight,
            child: _label('المدينة'),
          ),
          const SizedBox(height: 6),
          _buildCityDropdown(),

          const SizedBox(height: 13),

          Align(
            alignment: Alignment.centerRight,
            child: _label('المنطقة'),
          ),
          const SizedBox(height: 6),
          _buildAreaDropdown(),

          const SizedBox(height: 13),

          Align(
            alignment: Alignment.centerRight,
            child: _label('العنوان'),
          ),
          const SizedBox(height: 6),

          TextField(
            controller: _addressController,
            maxLines: 2,
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              hint: 'اسم الشارع ورقم العقار والشقة',
              icon: Icons.location_on_outlined,
            ),
          ),

          const SizedBox(height: 13),

          Align(
            alignment: Alignment.centerRight,
            child: _label('ملاحظات إضافية (اختياري)'),
          ),
          const SizedBox(height: 6),

          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: _decoration(
              hint: 'أي تفاصيل إضافية عن العنوان',
              icon: Icons.notes_outlined,
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 13),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: Colors.red.shade100,
                ),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _loading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0878BD),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'إنشاء الحساب',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CITY DROPDOWN
  // ============================================================

  Widget _buildCityDropdown() {
    if (_loadingCities) {
      return _loadingBox('جاري تحميل المدن...');
    }

    return DropdownButtonFormField<int>(
      initialValue: _selectedCityId,
      isExpanded: true,
      decoration: _decoration(
        hint: 'اختر المدينة',
        icon: Icons.location_city_outlined,
      ),
      items: _cities.map((city) {
        return DropdownMenuItem<int>(
          value: (city['id'] as num).toInt(),
          child: Text(
            city['name_ar']?.toString() ?? '',
            style: const TextStyle(fontSize: 12),
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        setState(() {
          _selectedCityId = value;
          _error = null;
        });

        _loadAreas(value);
      },
    );
  }

  // ============================================================
  // AREA DROPDOWN
  // ============================================================

  Widget _buildAreaDropdown() {
    if (_loadingAreas) {
      return _loadingBox('جاري تحميل المناطق...');
    }

    return DropdownButtonFormField<int>(
      initialValue: _selectedAreaId,
      isExpanded: true,
      decoration: _decoration(
        hint: _selectedCityId == null
            ? 'اختر المدينة أولًا'
            : 'اختر المنطقة',
        icon: Icons.map_outlined,
      ),
      items: _areas.map((area) {
        return DropdownMenuItem<int>(
          value: (area['id'] as num).toInt(),
          child: Text(
            area['name_ar']?.toString() ?? '',
            style: const TextStyle(fontSize: 12),
          ),
        );
      }).toList(),
      onChanged: _selectedCityId == null
          ? null
          : (value) {
              setState(() {
                _selectedAreaId = value;
                _error = null;
              });
            },
    );
  }

  // ============================================================
  // LOADING BOX
  // ============================================================

  Widget _loadingBox(String text) {
    return Container(
      width: double.infinity,
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: const Color(0xFFD7E5EF),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF0878BD),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LABEL
  // ============================================================

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: Color(0xFF062E49),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // ============================================================
  // LOGIN HINT
  // ============================================================

  Widget _buildLoginHint() {
    return const Text(
      'لديك حساب بالفعل؟ يمكنك تسجيل الدخول باستخدام رقم الهاتف والـ PIN.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 10,
        color: Color(0xFF8093A2),
      ),
    );
  }
}