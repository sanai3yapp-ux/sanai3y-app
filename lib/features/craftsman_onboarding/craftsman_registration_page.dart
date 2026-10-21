import 'dart:typed_data';
import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class CraftsmanRegistrationPage extends StatefulWidget {
  const CraftsmanRegistrationPage({super.key});

  @override
  State<CraftsmanRegistrationPage> createState() =>
      _CraftsmanRegistrationPageState();
}

class _CraftsmanRegistrationPageState
    extends State<CraftsmanRegistrationPage> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;

  String? _error;

  List<Map<String, dynamic>> _professions = [];
  List<Map<String, dynamic>> _areas = [];

  final Set<int> _selectedProfessionIds = {};
  final Set<int> _selectedAreaIds = {};

  int? _selectedCityId;
  String? _selectedExperience;
  String? _selectedTransportation;

  Uint8List? _nationalIdBytes;
  String? _nationalIdFileName;

  Uint8List? _profileImageBytes;
  String? _profileImageFileName;

  final List<Uint8List> _workImages = [];
  final List<String> _workImageNames = [];

  bool _acceptedTerms = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    try {
      final professionsResponse = await _supabase
          .from('professions')
          .select('id,name_ar,is_active,sort_order')
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final citiesResponse = await _supabase
          .from('cities')
          .select('id,name_ar,name_en,is_active,sort_order')
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final cities = List<Map<String, dynamic>>.from(citiesResponse);
      Map<String, dynamic>? obourCity;

      for (final city in cities) {
        final nameAr = '${city['name_ar'] ?? ''}'.trim();
        final nameEn = '${city['name_en'] ?? ''}'.trim().toLowerCase();
        if (nameAr == 'العبور' || nameEn == 'obour' ||
            nameEn == 'el obour' || nameEn == 'al obour') {
          obourCity = city;
          break;
        }
      }

      if (obourCity == null || obourCity['id'] == null) {
        throw Exception('لم يتم العثور على مدينة العبور في قاعدة البيانات.');
      }

      final cityId = (obourCity['id'] as num).toInt();

      if (!mounted) return;
      setState(() {
        _professions = List<Map<String, dynamic>>.from(professionsResponse);
        _selectedCityId = cityId;
        _loading = false;
        _error = null;
      });

      await _loadAreas(cityId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل المهن أو أحياء مدينة العبور.';
      });
      debugPrint('CRAFTSMAN REGISTRATION LOAD ERROR: $e');
    }
  }

  // ============================================================
  // LOAD AREAS
  // ============================================================

  Future<void> _loadAreas(int cityId) async {
    setState(() {
      _selectedAreaIds.clear();
      _areas = [];
    });

    try {
      final response = await _supabase
          .from('areas')
          .select('id,city_id,name_ar,is_active,sort_order')
          .eq('city_id', cityId)
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      if (!mounted) return;

      setState(() {
        _areas = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'تعذر تحميل الأحياء.';
      });
    }
  }

  // ============================================================
  // PICK NATIONAL ID
  // ============================================================

  Future<void> _pickNationalId() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        _nationalIdBytes = bytes;
        _nationalIdFileName = image.name;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'تعذر اختيار صورة البطاقة.';
      });
    }
  }

  // ============================================================
  // PICK PROFILE IMAGE
  // ============================================================

  Future<void> _pickProfileImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();

      if (!mounted) return;

      setState(() {
        _profileImageBytes = bytes;
        _profileImageFileName = image.name;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'تعذر اختيار الصورة الشخصية.';
      });
    }
  }

  // ============================================================
  // PICK WORK IMAGES
  // ============================================================

  Future<void> _pickWorkImages() async {
    try {
      final images = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (images.isEmpty) return;

      final remaining = 10 - _workImages.length;

      for (final image in images.take(remaining)) {
        final bytes = await image.readAsBytes();

        _workImages.add(bytes);
        _workImageNames.add(image.name);
      }

      if (!mounted) return;

      setState(() {});
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'تعذر اختيار صور الأعمال.';
      });
    }
  }

  // ============================================================
  // STORAGE
  // ============================================================

  Future<String> _uploadFile({
    required String bucket,
    required String path,
    required Uint8List bytes,
  }) async {
    await _supabase.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: false,
          ),
        );

    return path;
  }

  // ============================================================
  // REGISTER
  // ============================================================

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // ----------------------------------------------------------
    // professions
    // ----------------------------------------------------------

    if (_selectedProfessionIds.isEmpty) {
      setState(() {
        _error = 'اختر مهنة واحدة على الأقل.';
      });
      return;
    }

    // ----------------------------------------------------------
    // city
    // ----------------------------------------------------------

    if (_selectedCityId == null) {
      setState(() {
        _error = 'اختر المدينة.';
      });
      return;
    }

    // ----------------------------------------------------------
    // areas
    // ----------------------------------------------------------

    if (_selectedAreaIds.isEmpty) {
      setState(() {
        _error = 'اختر حيًا واحدًا على الأقل.';
      });
      return;
    }

    // ----------------------------------------------------------
    // experience
    // ----------------------------------------------------------

    if (_selectedExperience == null) {
      setState(() {
        _error = 'اختر سنوات الخبرة.';
      });
      return;
    }

    // ----------------------------------------------------------
    // transportation
    // ----------------------------------------------------------

    if (_selectedTransportation == null) {
      setState(() {
        _error = 'اختر وسيلة الانتقال.';
      });
      return;
    }

    // ----------------------------------------------------------
    // national ID image
    // ----------------------------------------------------------

    if (_nationalIdBytes == null) {
      setState(() {
        _error = 'اختيار صورة البطاقة مطلوب.';
      });
      return;
    }

    // ----------------------------------------------------------
    // terms
    // ----------------------------------------------------------

    if (!_acceptedTerms) {
      setState(() {
        _error = 'يجب الموافقة على الشروط والأحكام وسياسة الخصوصية.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // ========================================================
      // 1. AUTHENTICATED APPLICATION SESSION
      // ========================================================
      // Phone Provider is intentionally OFF.
      // The registration RPC requires auth.uid(), so the application
      // creates a temporary anonymous authenticated user, submits the
      // technician application under that user, then signs out after
      // the application is successfully saved.

      if (_supabase.auth.currentSession != null) {
        await _supabase.auth.signOut();
      }

      final authResponse = await _supabase.auth.signInAnonymously(
        data: {
          'role': 'technician_applicant',
        },
      );

      final user = authResponse.user;

      if (user == null || _supabase.auth.currentSession == null) {
        throw Exception('تعذر إنشاء جلسة تسجيل الطلب.');
      }

      // ========================================================
      // 3. UPLOAD NATIONAL ID
      // ========================================================

      final nationalIdExtension =
          _extensionFromName(_nationalIdFileName);

      final nationalIdPath =
          '${user.id}/national_id_${DateTime.now().millisecondsSinceEpoch}.$nationalIdExtension';

      await _uploadFile(
        bucket: 'technician-documents',
        path: nationalIdPath,
        bytes: _nationalIdBytes!,
      );

      // ========================================================
      // 4. YEARS EXPERIENCE
      // ========================================================

      int yearsExperience;

      switch (_selectedExperience) {
        case '1-3':
          yearsExperience = 1;
          break;

        case '4-6':
          yearsExperience = 4;
          break;

        case '6+':
          yearsExperience = 7;
          break;

        default:
          yearsExperience = 0;
      }

      // ========================================================
      // 5. REGISTER TECHNICIAN
      // ========================================================

      final technician = await _supabase.rpc(
        'register_technician',
        params: {
          'p_full_name': _nameController.text.trim(),
          'p_phone': _phoneController.text.trim(),
          'p_national_id_number':
              _nationalIdController.text.trim(),
          'p_profession_ids':
              _selectedProfessionIds.toList(),
          'p_city_id': _selectedCityId,
          'p_area_ids': _selectedAreaIds.toList(),
          'p_phone2': null,
          'p_address': null,
          'p_years_experience': yearsExperience,
          'p_description': null,
          'p_transportation_type':
              _selectedTransportation,
          'p_national_id_image_path': nationalIdPath,
        },
      );

      // ========================================================
      // 6. EXPERIENCE RANGE
      // ========================================================

      final technicianId = technician['id'];

      if (technicianId != null) {
        await _supabase
            .from('technician_experience_ranges')
            .insert({
          'technician_id': technicianId,
          'experience_range': _selectedExperience,
        });
      }

      // ========================================================
      // 7. OPTIONAL PROFILE IMAGE
      // ========================================================

      if (_profileImageBytes != null) {
        final extension =
            _extensionFromName(_profileImageFileName);

        final path =
            '${user.id}/profile_${DateTime.now().millisecondsSinceEpoch}.$extension';

        await _uploadFile(
          bucket: 'technician-documents',
          path: path,
          bytes: _profileImageBytes!,
        );
      }

      // ========================================================
      // 8. OPTIONAL WORK IMAGES
      // ========================================================

      for (int i = 0; i < _workImages.length; i++) {
        final extension =
            _extensionFromName(_workImageNames[i]);

        final path =
            '${user.id}/works/${DateTime.now().millisecondsSinceEpoch}_$i.$extension';

        await _uploadFile(
          bucket: 'technician-documents',
          path: path,
          bytes: _workImages[i],
        );
      }

      // ========================================================
      // 9. SUCCESS
      // ========================================================

      // The anonymous session is only a technical authentication
      // session needed by register_technician(). Do not leave it
      // active after the application has been submitted.
      await _supabase.auth.signOut();

      if (!mounted) return;

      await _showSuccessDialog();
    } on AuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e
            .toString()
            .replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  // ============================================================
  // EXTENSION
  // ============================================================

  String _extensionFromName(String? name) {
    if (name == null || !name.contains('.')) {
      return 'jpg';
    }

    final extension =
        name.split('.').last.toLowerCase();

    if (extension == 'jpeg') {
      return 'jpg';
    }

    if (![
      'jpg',
      'png',
      'webp',
    ].contains(extension)) {
      return 'jpg';
    }

    return extension;
  }

  // ============================================================
  // SUCCESS
  // ============================================================

  Future<void> _showSuccessDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'تم إرسال طلب الانضمام',
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'تم تسجيل بياناتك بنجاح وإرسال طلبك للمراجعة.\n\n'
            'سيتم مراجعة بياناتك من إدارة صنايعي قبل تفعيل الحساب.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('تم'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();

    super.dispose();
  }

  // ============================================================
  // FIELD DECORATION
  // ============================================================

  InputDecoration _decoration(
    String label, {
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null
          ? null
          : Icon(
              icon,
              color: const Color(0xFF064B7A),
            ),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFFD6E2EC),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFFD6E2EC),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color(0xFF0878BD),
          width: 1.5,
        ),
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
        backgroundColor: const Color(0xFFF3F7FA),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;

                    final contentWidth = width < 600
                        ? width - 24
                        : width < 1000
                            ? 680.0
                            : 760.0;

                    return ScrollConfiguration(
                      behavior: const _AppScrollBehavior(),
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: contentWidth,
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                // ==================================================
                                // BACK
                                // ==================================================

                                Align(
                                  alignment:
                                      Alignment.topRight,
                                  child: TextButton.icon(
                                    onPressed: _submitting
                                        ? null
                                        : () {
                                            Navigator.of(
                                              context,
                                            ).pop();
                                          },
                                    icon: const Icon(
                                      Icons
                                          .arrow_forward,
                                      size: 17,
                                    ),
                                    label: const Text(
                                      'رجوع',
                                    ),
                                  ),
                                ),

                                // ==================================================
                                // TITLE
                                // ==================================================

                                const Text(
                                  'سجل بياناتك كصنايعي',
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight:
                                        FontWeight.w800,
                                    color:
                                        Color(0xFF064B7A),
                                  ),
                                ),

                                const SizedBox(height: 4),

                                const Text(
                                  'الحقول المعلّمة بـ * إجبارية.',
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Color(0xFF55758D),
                                  ),
                                ),

                                const SizedBox(
                                  height: 18,
                                ),

                                Container(
                                  width:
                                      double.infinity,
                                  padding:
                                      const EdgeInsets.all(
                                    16,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      20,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color:
                                            Color(
                                          0x16000000,
                                        ),
                                        blurRadius: 20,
                                        offset: Offset(
                                          0,
                                          6,
                                        ),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .stretch,
                                    children: [
                                      // ==================================================
                                      // BASIC DATA
                                      // ==================================================

                                      const Text(
                                        'البيانات الأساسية',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                          color:
                                              Color(
                                            0xFF064B7A,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 12,
                                      ),

                                      Row(
                                        children: [
                                          Expanded(
                                            child:
                                                TextFormField(
                                              controller:
                                                  _nameController,
                                              textInputAction:
                                                  TextInputAction
                                                      .next,
                                              decoration:
                                                  _decoration(
                                                'الاسم بالكامل *',
                                              ),
                                              validator:
                                                  (value) {
                                                if (value ==
                                                        null ||
                                                    value
                                                        .trim()
                                                        .isEmpty) {
                                                  return 'أدخل الاسم بالكامل';
                                                }

                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 12,
                                          ),
                                          Expanded(
                                            child:
                                                TextFormField(
                                              controller:
                                                  _phoneController,
                                              keyboardType:
                                                  TextInputType
                                                      .phone,
                                              textDirection:
                                                  TextDirection
                                                      .ltr,
                                              decoration:
                                                  _decoration(
                                                'رقم الهاتف *',
                                              ),
                                              validator:
                                                  (value) {
                                                if (value ==
                                                        null ||
                                                    value
                                                        .trim()
                                                        .isEmpty) {
                                                  return 'أدخل رقم الهاتف';
                                                }

                                                return null;
                                              },
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(
                                        height: 5,
                                      ),

                                      const Text(
                                        'رقم الهاتف يُستخدم مرة واحدة فقط لتقديم طلب فني.',
                                        textAlign:
                                            TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              Color(
                                            0xFF718696,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 20,
                                      ),

                                      // ==================================================
                                      // PROFESSIONS
                                      // ==================================================

                                      const Text(
                                        'المهن التي تقدمها *',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                          color:
                                              Color(
                                            0xFF064B7A,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 4,
                                      ),

                                      const Text(
                                        'يمكنك اختيار أكثر من مهنة.',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              Color(
                                            0xFF718696,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 10,
                                      ),

                                      if (_professions
                                          .isEmpty)
                                        const Text(
                                          'لا توجد مهن متاحة حاليًا.',
                                          textAlign:
                                              TextAlign
                                                  .center,
                                        )
                                      else
                                        GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount:
                                                2,
                                            crossAxisSpacing:
                                                8,
                                            mainAxisSpacing:
                                                8,
                                            childAspectRatio:
                                                2.8,
                                          ),
                                          itemCount:
                                              _professions
                                                  .length,
                                          itemBuilder:
                                              (
                                            context,
                                            index,
                                          ) {
                                            final p =
                                                _professions[
                                                    index];

                                            final id =
                                                (p['id']
                                                        as num)
                                                    .toInt();

                                            final selected =
                                                _selectedProfessionIds
                                                    .contains(
                                              id,
                                            );

                                            final name =
                                                p['name_ar'] ??
                                                    p['name_en'] ??
                                                    '';

                                            return InkWell(
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(
                                                10,
                                              ),
                                              onTap: () {
                                                setState(() {
                                                  if (selected) {
                                                    _selectedProfessionIds
                                                        .remove(
                                                      id,
                                                    );
                                                  } else {
                                                    _selectedProfessionIds
                                                        .add(
                                                      id,
                                                    );
                                                  }
                                                });
                                              },
                                              child:
                                                  Container(
                                                padding:
                                                    const EdgeInsets
                                                        .symmetric(
                                                  horizontal:
                                                      8,
                                                ),
                                                decoration:
                                                    BoxDecoration(
                                                  color:
                                                      selected
                                                          ? const Color(
                                                              0xFFE8F4FC,
                                                            )
                                                          : Colors
                                                              .white,
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                    10,
                                                  ),
                                                  border:
                                                      Border
                                                          .all(
                                                    color:
                                                        selected
                                                            ? const Color(
                                                                0xFF0878BD,
                                                              )
                                                            : const Color(
                                                                0xFFD6E2EC,
                                                              ),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Checkbox(
                                                      value:
                                                          selected,
                                                      onChanged:
                                                          (_) {
                                                        setState(
                                                          () {
                                                            if (selected) {
                                                              _selectedProfessionIds.remove(
                                                                id,
                                                              );
                                                            } else {
                                                              _selectedProfessionIds.add(
                                                                id,
                                                              );
                                                            }
                                                          },
                                                        );
                                                      },
                                                    ),
                                                    Expanded(
                                                      child:
                                                          Text(
                                                        '$name',
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines:
                                                            2,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style:
                                                            const TextStyle(
                                                          fontSize:
                                                              12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),

                                      const SizedBox(
                                        height: 20,
                                      ),

                                      // ==================================================
                                      // EXPERIENCE
                                      // ==================================================

                                      const Text(
                                        'سنوات الخبرة *',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                          color:
                                              Color(
                                            0xFF064B7A,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 8,
                                      ),

                                      Row(
                                        children: [
                                          _experienceOption(
                                            value: '1-3',
                                            label:
                                                'من 1 إلى 3 سنوات',
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ),
                                          _experienceOption(
                                            value: '4-6',
                                            label:
                                                'من 4 إلى 6 سنوات',
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ),
                                          _experienceOption(
                                            value: '6+',
                                            label:
                                                'أكثر من 6 سنوات',
                                          ),
                                        ],
                                      ),

                                      const SizedBox(
                                        height: 18,
                                      ),

                                      // ==================================================
                                      // CITY
                                      // ==================================================

                                      TextFormField(
                                        readOnly: true,
                                        initialValue: 'العبور',
                                        decoration: _decoration(
                                          'المدينة *',
                                        ).copyWith(
                                          suffixIcon: const Icon(
                                            Icons.lock_outline,
                                            color: Color(0xFF718696),
                                          ),
                                        ),
                                        validator: (_) {
                                          if (_selectedCityId == null) {
                                            return 'تعذر تحديد مدينة العبور';
                                          }
                                          return null;
                                        },
                                      ),

                                      const SizedBox(
                                        height: 14,
                                      ),

                                      // ==================================================
                                      // AREAS
                                      // ==================================================

                                      if (_selectedCityId !=
                                          null) ...[
                                        const Text(
                                          'الأحياء التي تغطي خدماتها *',
                                          style:
                                              TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                FontWeight
                                                    .bold,
                                            color:
                                                Color(
                                              0xFF064B7A,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(
                                          height: 4,
                                        ),

                                        const Text(
                                          '(اختر حيًا واحدًا أو أكثر)',
                                          style:
                                              TextStyle(
                                            fontSize: 10,
                                            color:
                                                Color(
                                              0xFF718696,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(
                                          height: 8,
                                        ),

                                        if (_areas.isEmpty)
                                          const Padding(
                                            padding:
                                                EdgeInsets
                                                    .all(
                                              10,
                                            ),
                                            child: Text(
                                              'لا توجد أحياء متاحة لهذه المدينة.',
                                              textAlign:
                                                  TextAlign
                                                      .center,
                                            ),
                                          )
                                        else
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(2),
                                            child: GridView.builder(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              gridDelegate:
                                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: 2,
                                                crossAxisSpacing: 8,
                                                mainAxisSpacing: 8,
                                                childAspectRatio: 4.2,
                                              ),
                                              itemCount: _areas.length,
                                              itemBuilder: (context, index) {
                                                final area = _areas[index];
                                                final id = (area['id'] as num).toInt();
                                                final selected = _selectedAreaIds.contains(id);
                                                final name = area['name_ar'] ?? '';

                                                return InkWell(
                                                  borderRadius: BorderRadius.circular(10),
                                                  onTap: () {
                                                    setState(() {
                                                      if (selected) {
                                                        _selectedAreaIds.remove(id);
                                                      } else {
                                                        _selectedAreaIds.add(id);
                                                      }
                                                    });
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                                    decoration: BoxDecoration(
                                                      color: selected
                                                          ? const Color(0xFFE8F4FC)
                                                          : Colors.white,
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(
                                                        color: selected
                                                            ? const Color(0xFF0878BD)
                                                            : const Color(0xFFD6E2EC),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Checkbox(
                                                          value: selected,
                                                          onChanged: (_) {
                                                            setState(() {
                                                              if (selected) {
                                                                _selectedAreaIds.remove(id);
                                                              } else {
                                                                _selectedAreaIds.add(id);
                                                              }
                                                            });
                                                          },
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            '$name',
                                                            textAlign: TextAlign.center,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),

                                      ],
                                      const SizedBox(
                                        height: 18,
                                      ),

                                      // ==================================================
                                      // TRANSPORTATION
                                      // ==================================================

                                      const Text(
                                        'وسيلة الانتقال *',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight
                                                  .bold,
                                          color:
                                              Color(
                                            0xFF064B7A,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 8,
                                      ),

                                      Row(
                                        children: [
                                          _transportOption(
                                            value:
                                                'motorcycle',
                                            label:
                                                'موتوسيكل',
                                            icon: Icons
                                                .two_wheeler,
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ),
                                          _transportOption(
                                            value: 'car',
                                            label:
                                                'سيارة',
                                            icon: Icons
                                                .directions_car,
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ),
                                          _transportOption(
                                            value: 'none',
                                            label: 'بدون',
                                            icon: Icons
                                                .person_outline,
                                          ),
                                        ],
                                      ),

                                      const SizedBox(
                                        height: 20,
                                      ),

                                      // ==================================================
                                      // NATIONAL ID NUMBER
                                      // ==================================================

                                      TextFormField(
                                        controller:
                                            _nationalIdController,
                                        keyboardType:
                                            TextInputType
                                                .number,
                                        textDirection:
                                            TextDirection
                                                .ltr,
                                        maxLength: 14,
                                        decoration:
                                            _decoration(
                                          'رقم البطاقة القومي *',
                                        ).copyWith(
                                          counterText: '',
                                        ),
                                        validator:
                                            (value) {
                                          final v =
                                              value?.trim() ??
                                                  '';

                                          if (v.isEmpty) {
                                            return 'أدخل رقم البطاقة القومي';
                                          }

                                          if (!RegExp(
                                            r'^[0-9]{14}$',
                                          ).hasMatch(v)) {
                                            return 'رقم البطاقة يجب أن يكون 14 رقمًا';
                                          }

                                          return null;
                                        },
                                      ),

                                      const SizedBox(
                                        height: 4,
                                      ),

                                      const Text(
                                        'رقم البطاقة القومي يُستخدم لمراجعة بيانات طلبك.',
                                        textAlign:
                                            TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              Color(
                                            0xFF718696,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 18,
                                      ),

                                      // ==================================================
                                      // NATIONAL ID IMAGE
                                      // ==================================================

                                      _uploadBox(
                                        title:
                                            'صورة البطاقة الشخصية',
                                        subtitle:
                                            'اختر صورة واضحة للوجهين',
                                        requiredText:
                                            'اختيار صورة البطاقة *',
                                        icon: Icons
                                            .badge_outlined,
                                        selected:
                                            _nationalIdBytes !=
                                                null,
                                        fileName:
                                            _nationalIdFileName,
                                        onTap:
                                            _submitting
                                                ? null
                                                : _pickNationalId,
                                      ),

                                      const SizedBox(
                                        height: 2,
                                      ),

                                      const Text(
                                        'JPG / PNG / WEBP — بحد أقصى 5MB',
                                        textAlign:
                                            TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              Color(
                                            0xFF718696,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 12,
                                      ),

                                      // ==================================================
                                      // PROFILE IMAGE
                                      // ==================================================

                                      _uploadBox(
                                        title:
                                            'اختر صورة شخصية واضحة',
                                        subtitle:
                                            'JPG / PNG / WEBP — اختياري',
                                        requiredText:
                                            'اختيار الصورة الشخصية',
                                        icon: Icons
                                            .person_outline,
                                        selected:
                                            _profileImageBytes !=
                                                null,
                                        fileName:
                                            _profileImageFileName,
                                        onTap:
                                            _submitting
                                                ? null
                                                : _pickProfileImage,
                                      ),

                                      const SizedBox(
                                        height: 12,
                                      ),

                                      // ==================================================
                                      // WORK IMAGES
                                      // ==================================================

                                      _uploadBox(
                                        title:
                                            'ارفع صور أعمالك السابقة',
                                        subtitle:
                                            'اختياري — يمكنك رفع أكثر من صورة',
                                        requiredText:
                                            'اختيار صور الأعمال',
                                        icon: Icons
                                            .construction,
                                        selected:
                                            _workImages
                                                .isNotEmpty,
                                        fileName:
                                            _workImages.isEmpty
                                                ? null
                                                : '${_workImages.length} صورة تم اختيارها',
                                        onTap:
                                            _submitting
                                                ? null
                                                : _pickWorkImages,
                                      ),

                                      const SizedBox(
                                        height: 14,
                                      ),

                                      // ==================================================
                                      // TERMS
                                      // ==================================================

                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _acceptedTerms =
                                                !_acceptedTerms;
                                          });
                                        },
                                        child: Row(
                                          children: [
                                            Checkbox(
                                              value:
                                                  _acceptedTerms,
                                              onChanged:
                                                  (value) {
                                                setState(() {
                                                  _acceptedTerms =
                                                      value ??
                                                          false;
                                                });
                                              },
                                            ),
                                            const Expanded(
                                              child: Text(
                                                'أوافق على الشروط والأحكام وسياسة الخصوصية. *',
                                                style:
                                                    TextStyle(
                                                  fontSize:
                                                      12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // ==================================================
                                      // ERROR
                                      // ==================================================

                                      if (_error !=
                                          null) ...[
                                        const SizedBox(
                                          height: 8,
                                        ),
                                        Container(
                                          width:
                                              double.infinity,
                                          padding:
                                              const EdgeInsets
                                                  .all(
                                            10,
                                          ),
                                          decoration:
                                              BoxDecoration(
                                            color:
                                                Colors.red
                                                    .withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius:
                                                BorderRadius
                                                    .circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            _error!,
                                            textAlign:
                                                TextAlign
                                                    .center,
                                            style:
                                                const TextStyle(
                                              color:
                                                  Colors.red,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],

                                      const SizedBox(
                                        height: 14,
                                      ),

                                      // ==================================================
                                      // SUBMIT
                                      // ==================================================

                                      SizedBox(
                                        height: 50,
                                        child:
                                            ElevatedButton(
                                          onPressed:
                                              _submitting
                                                  ? null
                                                  : _register,
                                          style:
                                              ElevatedButton
                                                  .styleFrom(
                                            backgroundColor:
                                                const Color(
                                              0xFFE9A91B,
                                            ),
                                            foregroundColor:
                                                Colors.black,
                                            elevation: 0,
                                            shape:
                                                RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(
                                                10,
                                              ),
                                            ),
                                          ),
                                          child:
                                              _submitting
                                                  ? const SizedBox(
                                                      width:
                                                          22,
                                                      height:
                                                          22,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth:
                                                            2,
                                                        color:
                                                            Colors.white,
                                                      ),
                                                    )
                                                  : const Text(
                                                      'إرسال طلب الانضمام',
                                                      style:
                                                          TextStyle(
                                                        fontSize:
                                                            15,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(
                                  height: 14,
                                ),

                                const Text(
                                  'بياناتك محمية وتخضع للمراجعة قبل تفعيل الحساب',
                                  textAlign:
                                      TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color:
                                        Color(0xFF718696),
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  // ============================================================
  // EXPERIENCE OPTION
  // ============================================================

  Widget _experienceOption({
    required String value,
    required String label,
  }) {
    final selected =
        _selectedExperience == value;

    return Expanded(
      child: InkWell(
        borderRadius:
            BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _selectedExperience = value;
          });
        },
        child: Container(
          height: 48,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 4,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0878BD)
                  : const Color(0xFFD6E2EC),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF0878BD)
                        : const Color(0xFF9FB3C1),
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF0878BD),
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign:
                      TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TRANSPORT OPTION
  // ============================================================

  Widget _transportOption({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final selected =
        _selectedTransportation == value;

    return Expanded(
      child: InkWell(
        borderRadius:
            BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _selectedTransportation =
                value;
          });
        },
        child: Container(
          height: 50,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 4,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0878BD)
                  : const Color(0xFFD6E2EC),
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) {
                  setState(() {
                    _selectedTransportation =
                        value;
                  });
                },
              ),
              Icon(
                icon,
                size: 17,
                color:
                    const Color(0xFF064B7A),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  label,
                  textAlign:
                      TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // UPLOAD BOX
  // ============================================================

  Widget _uploadBox({
    required String title,
    required String subtitle,
    required String requiredText,
    required IconData icon,
    required bool selected,
    required String? fileName,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFCFD),
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFBFCED9),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              selected
                  ? Icons.check_circle
                  : icon,
              size: 32,
              color: selected
                  ? Colors.green
                  : const Color(0xFF0878BD),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF718696),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              selected
                  ? (fileName ?? 'تم اختيار الملف')
                  : requiredText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.green
                    : const Color(0xFF064B7A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
