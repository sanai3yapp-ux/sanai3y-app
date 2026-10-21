import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'account_type_page.dart';
import '../home/craftsman_home_page.dart';
import '../home/customer_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.accountType});

  final AccountType accountType;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  final List<TextEditingController> _pinControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  final List<FocusNode> _pinFocusNodes = List.generate(6, (_) => FocusNode());

  final List<TextEditingController> _confirmPinControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  final List<FocusNode> _confirmPinFocusNodes = List.generate(
    6,
    (_) => FocusNode(),
  );

  bool _customerPhoneChecked = false;
  bool _customerIsNew = false;

  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  bool get isCustomer => widget.accountType == AccountType.customer;

  String get pageTitle {
    if (isCustomer) {
      return 'دخول العميل';
    }

    return 'دخول الفني / الصنايعي';
  }

  String get pageSubtitle {
    if (isCustomer) {
      return '';
    }

    return 'سجل دخولك لإدارة خدماتك وطلباتك';
  }

  // ============================================================
  // CUSTOMER HELPERS
  // ============================================================

  String _customerDatabasePhone(String value) {
    var phone = value.trim().replaceAll(RegExp(r'\s+'), '');

    if (phone.startsWith('+20')) {
      phone = '0${phone.substring(3)}';
    } else if (phone.startsWith('0020')) {
      phone = '0${phone.substring(4)}';
    }

    return phone;
  }

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

  String _getCustomerPin() {
    return _pinControllers.map((controller) => controller.text).join();
  }

  String _getCustomerConfirmPin() {
    return _confirmPinControllers.map((controller) => controller.text).join();
  }

  // ============================================================
  // CUSTOMER AUTH - EDGE FUNCTION
  // ============================================================

  Future<Map<String, dynamic>> _customerAuth({
    required String action,
    required String phone,
    String? pin,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'customer-auth',
      body: {'action': action, 'phone': phone, if (pin != null) 'pin': pin},
    );

    final data = response.data;

    if (data is! Map) {
      throw const AuthException('تعذر قراءة استجابة نظام دخول العميل.');
    }

    final result = Map<String, dynamic>.from(data);

    if (response.status < 200 || response.status >= 300) {
      final message = result['error']?.toString();

      throw AuthException(
        message == null || message.isEmpty
            ? 'تعذر تنفيذ العملية. حاول مرة أخرى.'
            : message,
      );
    }

    return result;
  }

  Future<void> _setCustomerSession(Map<String, dynamic> result) async {
    final refreshToken = result['refresh_token']?.toString();

    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthException('تمت العملية لكن تعذر إنشاء جلسة العميل.');
    }

    await Supabase.instance.client.auth.setSession(refreshToken);

    if (Supabase.instance.client.auth.currentSession == null) {
      throw const AuthException('تعذر تثبيت جلسة العميل.');
    }
  }

  // ============================================================
  // TECHNICIAN AUTH EMAIL
  // ============================================================
  //
  // مهم:
  // حساب الفني الداخلي في النسخة الصحيحة يستخدم:
  //
  // tech.<technician_id>@sana3y.app
  //
  // وليس:
  //
  // tech.<technician_id>@auth.sanai3y.com
  //
  // ============================================================

  String _technicianAuthEmail(Map<String, dynamic> info) {
    final returnedEmail = info['auth_email']?.toString().trim();

    if (returnedEmail != null && returnedEmail.isNotEmpty) {
      return returnedEmail;
    }

    final technicianId = info['technician_id'];

    if (technicianId == null) {
      throw const AuthException('تعذر تحديد حساب الفني.');
    }

    return 'tech.$technicianId@sana3y.app';
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> _login() async {
    final phoneInput = _phoneController.text.trim();

    final phone = _normalizePhone(phoneInput);

    if (phoneInput.isEmpty) {
      setState(() {
        _error = 'من فضلك أدخل رقم الهاتف';
      });
      return;
    }

    // ============================================================
    // CUSTOMER - STEP 1
    // ============================================================

    if (isCustomer && !_customerPhoneChecked) {
      final customerPhone = _customerDatabasePhone(phoneInput);

      if (!RegExp(r'^01\d{9}$').hasMatch(customerPhone)) {
        setState(() {
          _error = 'من فضلك أدخل رقم هاتف صحيح';
        });
        return;
      }

      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        final result = await _customerAuth(
          action: 'check',
          phone: customerPhone,
        );

        if (!mounted) return;

        final exists = result['exists'] == true;

        final blocked = result['blocked'] == true;

        setState(() {
          _customerPhoneChecked = true;
          _customerIsNew = !exists;
          _loading = false;
          _error = blocked ? 'هذا الحساب غير متاح حاليًا.' : null;
        });
      } on AuthException catch (e) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _error = e.message;
        });
      } catch (_) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _error = 'تعذر التحقق من رقم الهاتف. حاول مرة أخرى.';
        });
      }

      return;
    }

    String password;

    // ============================================================
    // CUSTOMER
    // ============================================================

    if (isCustomer) {
      password = _getCustomerPin();

      if (!RegExp(r'^[0-9]{6}$').hasMatch(password)) {
        setState(() {
          _error = 'كلمة المرور يجب أن تتكون من 6 أرقام فقط';
        });
        return;
      }

      if (_customerIsNew) {
        final confirmation = _getCustomerConfirmPin();

        if (!RegExp(r'^[0-9]{6}$').hasMatch(confirmation)) {
          setState(() {
            _error = 'من فضلك أكد كلمة المرور المكونة من 6 أرقام';
          });
          return;
        }

        if (password != confirmation) {
          setState(() {
            _error = 'تأكيد كلمة المرور غير مطابق';
          });
          return;
        }
      }
    }
    // ============================================================
    // TECHNICIAN
    // ============================================================
    else {
      password = _passwordController.text.trim();

      if (password.isEmpty) {
        setState(() {
          _error = 'من فضلك أدخل كلمة المرور';
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;

      // ==========================================================
      // CUSTOMER FLOW
      // ==========================================================

      if (isCustomer) {
        final customerPhone = _customerDatabasePhone(phoneInput);

        final result = await _customerAuth(
          action: _customerIsNew ? 'register' : 'login',
          phone: customerPhone,
          pin: password,
        );

        await _setCustomerSession(result);
      }
      // ==========================================================
      // TECHNICIAN FLOW
      // ==========================================================
      else {
        // --------------------------------------------------------
        // 1. جلب بيانات الفني من RPC
        // --------------------------------------------------------

        final authInfo = await supabase.rpc(
          'get_technician_auth_info',
          params: {'p_phone': phone},
        );

        if (authInfo is! Map) {
          throw const AuthException('تعذر التحقق من بيانات الفني.');
        }

        final info = Map<String, dynamic>.from(authInfo);

        // --------------------------------------------------------
        // 2. الحساب موجود؟
        // --------------------------------------------------------

        if (info['found'] != true) {
          throw const AuthException('لا يوجد حساب فني مسجل بهذا الرقم.');
        }

        // --------------------------------------------------------
        // 3. حالة الحساب
        // --------------------------------------------------------

        if (info['application_status'] != 'approved' ||
            info['is_verified'] != true ||
            info['account_status'] != 'active') {
          throw const AuthException('الحساب لم يتم اعتماده أو تفعيله بعد.');
        }

        // --------------------------------------------------------
        // 4. كلمة المرور مفعلة؟
        // --------------------------------------------------------

        if (info['password_set'] != true) {
          throw const AuthException(
            'لم يتم تفعيل كلمة المرور لهذا الحساب بعد.',
          );
        }

        // --------------------------------------------------------
        // 5. الحصول على بريد Auth الداخلي
        // --------------------------------------------------------

        final internalEmail = _technicianAuthEmail(info);

        // --------------------------------------------------------
        // 6. تسجيل الدخول الفعلي
        //
        // هنا تم إصلاح المشكلة:
        //
        // tech.<id>@sana3y.app
        //
        // --------------------------------------------------------

        await supabase.auth.signInWithPassword(
          email: internalEmail,
          password: password,
        );

        // --------------------------------------------------------
        // 7. التأكد من إنشاء الجلسة
        // --------------------------------------------------------

        if (supabase.auth.currentSession == null) {
          throw const AuthException(
            'تم التحقق من بيانات الفني لكن تعذر إنشاء جلسة الدخول.',
          );
        }
      }

      // ==========================================================
      // NAVIGATION
      // ==========================================================

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              isCustomer ? const CustomerHomePage() : const CraftsmanHomePage(),
        ),
        (route) => false,
      );
    }
    // ============================================================
    // AUTH ERROR
    // ============================================================
    on AuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
      });
    }
    // ============================================================
    // DATABASE ERROR
    // ============================================================
    on PostgrestException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
      });
    }
    // ============================================================
    // OTHER ERROR
    // ============================================================
    catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // OPEN CRAFTSMAN REGISTRATION
  // ============================================================

  Future<void> _openCraftsmanLandingPage() async {
    final uri = Uri.parse('https://sanai3y.com/');

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);

      if (!opened && mounted) {
        setState(() {
          _error = 'تعذر فتح صفحة إنشاء الحساب. حاول مرة أخرى.';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
      });
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();

    for (final controller in _pinControllers) {
      controller.dispose();
    }

    for (final node in _pinFocusNodes) {
      node.dispose();
    }

    for (final controller in _confirmPinControllers) {
      controller.dispose();
    }

    for (final node in _confirmPinFocusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  // ============================================================
  // LOGO
  // ============================================================

  Widget _buildLogo() {
    return Container(
      width: 86,
      height: 86,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/account_type/logo.png',
        fit: BoxFit.contain,
      ),
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration({
    required String hintText,
    required Widget prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.96),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFFD7E5EF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFFD7E5EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFF0878BD), width: 1.5),
      ),
    );
  }

  // ============================================================
  // PIN BOXES
  // ============================================================

  Widget _buildDigitBoxes(
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        final width = ((constraints.maxWidth - (gap * 10)) / 6).clamp(
          36.0,
          52.0,
        );

        // نثبت ترتيب الخانات بصريًا حتى يعمل الانتقال التلقائي بشكل متوقع
        // سواء بدأ المستخدم من الخانة اليمنى أو اليسرى.
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                child: SizedBox(
                  width: width,
                  height: 48,
                  child: TextField(
                    controller: controllers[index],
                    focusNode: focusNodes[index],
                    keyboardType: TextInputType.number,
                    textInputAction: index == 5
                        ? TextInputAction.done
                        : TextInputAction.next,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    maxLength: 1,
                    obscureText: false,
                    enableSuggestions: false,
                    autocorrect: false,
                    onChanged: (value) {
                      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

                      if (digits.length > 1) {
                        final remaining = digits.substring(0, 6 - index);
                        for (var i = 0; i < remaining.length; i++) {
                          controllers[index + i].text = remaining[i];
                          controllers[index + i].selection =
                              const TextSelection.collapsed(offset: 1);
                        }
                        final target = (index + remaining.length).clamp(0, 5).toInt();
                        FocusScope.of(context).requestFocus(focusNodes[target]);
                        return;
                      }

                      if (digits.isNotEmpty) {
                        controllers[index].text = digits;
                        controllers[index].selection =
                            const TextSelection.collapsed(offset: 1);
                        if (index < controllers.length - 1) {
                          FocusScope.of(context).requestFocus(focusNodes[index + 1]);
                        } else {
                          FocusScope.of(context).unfocus();
                        }
                      } else if (value.isEmpty && index > 0) {
                        FocusScope.of(context).requestFocus(focusNodes[index - 1]);
                      }
                    },
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide:
                            const BorderSide(color: Color(0xFFD7E5EF)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide:
                            const BorderSide(color: Color(0xFFD7E5EF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: const BorderSide(
                          color: Color(0xFF0878BD),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  // ============================================================
  // LOGIN BOX
  // ============================================================

  Widget _buildLoginBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _phoneController,
            readOnly: isCustomer && _customerPhoneChecked,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: _inputDecoration(
              hintText: 'رقم الهاتف',
              prefixIcon: const Icon(
                Icons.phone_outlined,
                size: 18,
                color: Color(0xFF55758D),
              ),
            ),
          ),

          if (isCustomer && _customerPhoneChecked) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () {
                        setState(() {
                          _customerPhoneChecked = false;
                          _customerIsNew = false;
                          _error = null;

                          for (final c in _pinControllers) {
                            c.clear();
                          }

                          for (final c in _confirmPinControllers) {
                            c.clear();
                          }
                        });
                      },
                child: const Text(
                  'تغيير رقم الهاتف',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ======================================================
          // CUSTOMER
          // ======================================================
          if (isCustomer) ...[
            if (!_customerPhoneChecked) ...[
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'أدخل رقم هاتفك للمتابعة',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF062E49),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else ...[
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _customerIsNew ? 'إنشاء حساب جديد' : 'كلمة مرور حسابك',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF062E49),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 3),

              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _customerIsNew ? 'أدخل 6 أرقام ثم أكدها' : 'أدخل 6 أرقام',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),

              const SizedBox(height: 10),

              _buildDigitBoxes(_pinControllers, _pinFocusNodes),

              if (_customerIsNew) ...[
                const SizedBox(height: 14),

                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'تأكيد كلمة المرور',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF062E49),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                _buildDigitBoxes(_confirmPinControllers, _confirmPinFocusNodes),
              ],
            ],
          ]
          // ======================================================
          // TECHNICIAN
          // ======================================================
          else ...[
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'كلمة المرور',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF062E49),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 6),

            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textDirection: TextDirection.ltr,
              decoration: _inputDecoration(
                hintText: 'كلمة المرور',
                prefixIcon: const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: Color(0xFF55758D),
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],

          // ======================================================
          // ERROR
          // ======================================================
          if (_error != null) ...[
            const SizedBox(height: 4),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // ======================================================
          // LOGIN BUTTON
          // ======================================================
          SizedBox(
            width: double.infinity,
            height: 43,
            child: ElevatedButton(
              onPressed: _loading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0878BD),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isCustomer && !_customerPhoneChecked ? 'متابعة' : 'دخول',
                      style: const TextStyle(
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
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            final contentWidth = width < 600
                ? width - 32
                : width < 1000
                ? 430.0
                : 460.0;

            return Stack(
              fit: StackFit.expand,
              children: [
                // ==================================================
                // BACKGROUND
                // ==================================================

                Image.asset(
                  'assets/images/account_type/background_tools.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),

                // ==================================================
                // OVERLAY
                // ==================================================
                Container(color: Colors.white.withValues(alpha: 0.16)),

                // ==================================================
                // CONTENT
                // ==================================================
                SafeArea(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: width < 600 ? 16 : 24,
                      vertical: width < 600 ? 14 : 20,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            constraints.maxHeight - (width < 600 ? 28 : 40),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: contentWidth.clamp(280.0, 460.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // ==================================
                              // BACK BUTTON
                              // ==================================

                              Align(
                                alignment: Alignment.topRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF062E49),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.88,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_forward,
                                    size: 15,
                                  ),
                                  label: Text(
                                    pageTitle,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 14),

                              // ==================================
                              // LOGO
                              // ==================================
                              _buildLogo(),

                              const SizedBox(height: 22),

                              // ==================================
                              // TITLE
                              // ==================================
                              Text(
                                pageTitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF062E49),
                                ),
                              ),

                              const SizedBox(height: 6),

                              if (pageSubtitle.isNotEmpty) ...[
                                Text(
                                  pageSubtitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF55758D),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],

                              const SizedBox(height: 16),

                              // ==================================
                              // LOGIN BOX
                              // ==================================
                              _buildLoginBox(),

                              const SizedBox(height: 12),

                              // ==================================
                              // TECHNICIAN REGISTRATION
                              // ==================================
                              if (!isCustomer) ...[
                                const Row(
                                  children: [
                                    Expanded(
                                      child: Divider(color: Color(0xFFD8E1E8)),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Text(
                                        'أو',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(color: Color(0xFFD8E1E8)),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    onPressed: _loading
                                        ? null
                                        : _openCraftsmanLandingPage,
                                    icon: const Icon(
                                      Icons.person_add_alt_1,
                                      size: 21,
                                    ),
                                    label: const Text(
                                      'إنشاء حساب جديد',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFB000),
                                      foregroundColor: const Color(0xFF062E49),
                                      disabledBackgroundColor: const Color(
                                        0xFFE5E5E5,
                                      ),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 7),

                                const Text(
                                  'سيتم فتح موقع صنايعي لاستكمال إنشاء حسابك',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF8093A2),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 12),

                              const Text(
                                'آمن وموثوق • في كل أنحاء مصر',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF8093A2),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
