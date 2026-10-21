import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApplicationTrackerPage extends StatefulWidget {
  const ApplicationTrackerPage({super.key});

  @override
  State<ApplicationTrackerPage> createState() => _ApplicationTrackerPageState();
}

class _ApplicationTrackerPageState extends State<ApplicationTrackerPage> {
  final _phoneController = TextEditingController();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _application;

  String _normalize(String value) => value.replaceAll(RegExp(r'\D'), '');

  Future<void> _track() async {
    final phone = _normalize(_phoneController.text.trim());

    if (phone.isEmpty) {
      setState(() {
        _error = 'أدخل رقم التليفون الذي قدمت به الطلب';
        _application = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _application = null;
    });

    try {
      final data = await Supabase.instance.client.rpc(
        'get_my_application_by_phone',
        params: {'p_phone': phone},
      );

      Map<String, dynamic>? result;

      if (data is List && data.isNotEmpty && data.first is Map) {
        result = Map<String, dynamic>.from(data.first as Map);
      } else if (data is Map) {
        result = Map<String, dynamic>.from(data);
      }

      if (!mounted) return;

      setState(() {
        _application = result;
        if (result == null) {
          _error = 'لم يتم العثور على طلب بهذا الرقم.\nتأكد من إدخال نفس رقم الهاتف الذي سجلت به.';
        }
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.isEmpty
            ? 'تعذر متابعة الطلب حاليًا.'
            : 'تعذر متابعة الطلب حاليًا.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر متابعة الطلب حاليًا.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FCFF),
        appBar: AppBar(
          title: const Text('متابعة طلب التقديم'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF062E49),
          elevation: 0,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final contentWidth = width < 600 ? width - 32 : 520.0;

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: contentWidth.clamp(280.0, 520.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 18),
                        const Icon(
                          Icons.assignment_turned_in_outlined,
                          size: 52,
                          color: Color(0xFF0878BD),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'تابع حالة طلبك',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF062E49),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'لو قدمت كفني بالفعل، اكتب رقم تليفونك لمعرفة هل تم قبول طلبك أو رفضه.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Color(0xFF55758D),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textDirection: TextDirection.ltr,
                                decoration: InputDecoration(
                                  labelText: 'رقم التليفون',
                                  hintText: 'رقم التليفون الذي قدمت به الطلب',
                                  prefixIcon: const Icon(Icons.phone_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onSubmitted: (_) => _track(),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _track,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0878BD),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
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
                                          'متابعة الطلب',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          _MessageCard(
                            icon: Icons.info_outline,
                            text: _error!,
                            color: const Color(0xFFB42318),
                          ),
                        if (_application != null)
                          _ApplicationResult(
                            application: _application!,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ApplicationResult extends StatelessWidget {
  const _ApplicationResult({required this.application});

  final Map<String, dynamic> application;

  @override
  Widget build(BuildContext context) {
    final status = application['application_status']?.toString();
    final number = application['application_number']?.toString();
    final rejectionReason = application['rejection_reason']?.toString();
    final fixable = application['rejection_fixable'] == true;

    late final IconData icon;
    late final Color color;
    late final String title;
    String message = '';

    if (status == 'pending') {
      icon = Icons.hourglass_top_rounded;
      color = const Color(0xFFD88A00);
      title = 'طلبك قيد المراجعة';
      message = 'الحد الأقصى لمراجعة الطلب هو 24 ساعة.';
    } else if (status == 'approved') {
      icon = Icons.check_circle_outline;
      color = const Color(0xFF168A4A);
      title = 'تم قبول طلبك 🎉';
      message = 'يمكنك الآن استكمال بيانات WhatsApp ووسيلة استلام الأموال وخدماتك وأسعارك.';
    } else {
      icon = Icons.cancel_outlined;
      color = const Color(0xFFB42318);
      title = 'لم يتم قبول الطلب';
      message = 'السبب: ${rejectionReason?.isNotEmpty == true ? rejectionReason : 'لم يتم ذكر سبب.'}';
      if (fixable) {
        message += '\nيمكنك تعديل البيانات وإعادة التقديم.';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 42),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (number != null && number.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'رقم الطلب: $number',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF55758D),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF3F5362),
            ),
          ),
          if (status == 'approved') ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: () {
                  // نفس المرحلة الموجودة في اللاندينج: استكمال الملف.
                  // ربط صفحة technician.html لاحقًا بصفحة استكمال الملف داخل Flutter.
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('استكمال بيانات الفني'),
              ),
            ),
          ],
          if (status != 'pending' && status != 'approved' && fixable) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('تعديل وإعادة التقديم'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
