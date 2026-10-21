import 'package:flutter/material.dart';

import 'login_page.dart';
import 'admin_login_page.dart';

const Color navy = Color(0xFF064B7A);

enum AccountType {
  customer,
  craftsman,
}

class AccountTypePage extends StatelessWidget {
  const AccountTypePage({super.key});

  static const Color blue = Color(0xFF1477D4);
  static const Color gold = Color(0xFFE7A51E);

  static const String assets = 'assets/images/account_type/';

  void _openLogin(
    BuildContext context,
    AccountType accountType,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginPage(
          accountType: accountType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FBFE),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;

            final bool isPhone = screenWidth < 600;
            final bool isSmallPhone = screenWidth < 360;
            final bool isShortScreen = screenHeight < 700;

            // ------------------------------------------------------------
            // عرض المحتوى
            // ------------------------------------------------------------

            final double contentWidth;

            if (screenWidth >= 1200) {
              contentWidth = 620;
            } else if (screenWidth >= 900) {
              contentWidth = 570;
            } else if (screenWidth >= 600) {
              contentWidth = screenWidth * 0.72;
            } else {
              contentWidth = screenWidth - (isSmallPhone ? 20 : 28);
            }

            // ------------------------------------------------------------
            // المقاسات الرأسية
            // ------------------------------------------------------------

            final double topPadding = isSmallPhone
                ? 7
                : isPhone
                    ? 10
                    : 14;

            final double logoWidth = isSmallPhone
                ? 145
                : screenWidth < 390
                    ? 165
                    : screenWidth < 600
                        ? 180
                        : screenWidth < 900
                            ? 205
                            : 220;

            final double logoHeight = isSmallPhone
                ? 90
                : screenWidth < 390
                    ? 100
                    : screenWidth < 600
                        ? 108
                        : 120;

            final double sloganSize = isSmallPhone
                ? 15
                : screenWidth < 390
                    ? 16
                    : 18;

            final double sectionTitleSize = isSmallPhone
                ? 18
                : screenWidth < 390
                    ? 20
                    : screenWidth < 600
                        ? 21
                        : 23;

            final double sectionSpacing = isShortScreen
                ? 10
                : isSmallPhone
                    ? 12
                    : 16;

            return Stack(
              fit: StackFit.expand,
              children: [
                // ==========================================================
                // BACKGROUND
                // ==========================================================

                Positioned.fill(
                  child: IgnorePointer(
                    child: Image.asset(
                      '${assets}background_tools.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) {
                        return const ColoredBox(
                          color: Color(0xFFF7FBFE),
                        );
                      },
                    ),
                  ),
                ),

                // ==========================================================
                // طبقة شفافة خفيفة
                // ==========================================================

                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Color.fromRGBO(
                        255,
                        255,
                        255,
                        0.10,
                      ),
                    ),
                  ),
                ),

                // ==========================================================
                // CONTENT
                // ==========================================================

                SafeArea(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: isPhone ? 14 : 20,
                      right: isPhone ? 14 : 20,
                      top: topPadding,
                      bottom: 12,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: contentWidth,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // =================================================
                            // LANGUAGE
                            // =================================================

                            Align(
                              alignment: Alignment.topRight,
                              child: const _LanguageButton(),
                            ),

                            SizedBox(
                              height: isShortScreen ? 3 : 6,
                            ),

                            // =================================================
                            // LOGO
                            // =================================================

                            SizedBox(
                              width: logoWidth,
                              height: logoHeight,
                              child: Image.asset(
                                '${assets}logo.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                errorBuilder: (_, __, ___) {
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),

                            SizedBox(
                              height: isSmallPhone ? 0 : 2,
                            ),

                            // =================================================
                            // SLOGAN
                            // =================================================

                            Text(
                              'كل الصنايعية في مكان واحد',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: sloganSize,
                                fontWeight: FontWeight.w700,
                                color: navy,
                                height: 1.15,
                              ),
                            ),

                            SizedBox(
                              height: isShortScreen
                                  ? 9
                                  : isSmallPhone
                                      ? 11
                                      : 14,
                            ),

                            // =================================================
                            // SECTION TITLE
                            // =================================================

                            _SectionTitle(
                              fontSize: sectionTitleSize,
                            ),

                            SizedBox(
                              height: sectionSpacing,
                            ),

                            // =================================================
                            // CUSTOMER
                            // =================================================

                            _AccountCard(
                              title: 'عميل',
                              subtitle: 'اطلب خدمتك بسهولة',
                              description:
                                  'ابحث عن الصنايعي المناسب لخدمتك',
                              iconAsset:
                                  '${assets}customer_icon.png',
                              arrowAsset:
                                  '${assets}arrow_customer.svg',
                              background:
                                  const Color(0xFFDDF3FF),
                              borderColor:
                                  const Color(0xFF5BC0F5),
                              arrowColor: blue,
                              compact: isSmallPhone,
                              onTap: () {
                                _openLogin(
                                  context,
                                  AccountType.customer,
                                );
                              },
                            ),

                            SizedBox(
                              height: isShortScreen ? 8 : 11,
                            ),

                            // =================================================
                            // CRAFTSMAN
                            // =================================================

                            _AccountCard(
                              title: 'فني / صنايعي',
                              subtitle: 'مقدم خدمات',
                              description:
                                  'سجل وقدم خدماتك للعملاء',
                              iconAsset:
                                  '${assets}craftsman_icon.png',
                              arrowAsset:
                                  '${assets}arrow_worker.svg',
                              background:
                                  const Color(0xFFFFEBC4),
                              borderColor:
                                  const Color(0xFFFFC24B),
                              arrowColor:
                                  const Color(0xFFFFA000),
                              compact: isSmallPhone,
                              onTap: () {
                                _openLogin(
                                  context,
                                  AccountType.craftsman,
                                );
                              },
                            ),

                            SizedBox(
                              height: isShortScreen
                                  ? 10
                                  : isSmallPhone
                                      ? 12
                                      : 15,
                            ),

                            // =================================================
                            // LOWER TITLE
                            // =================================================

                            Text(
                              'انضم إلى أكبر شبكة صنايعية في مصر',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isSmallPhone ? 15 : 18,
                                fontWeight: FontWeight.w800,
                                color: navy,
                                height: 1.15,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Container(
                              width: isSmallPhone ? 60 : 75,
                              height: 3,
                              decoration: BoxDecoration(
                                color: gold,
                                borderRadius:
                                    BorderRadius.circular(20),
                              ),
                            ),

                            SizedBox(
                              height: isShortScreen
                                  ? 7
                                  : isSmallPhone
                                      ? 9
                                      : 11,
                            ),

                            // =================================================
                            // BOTTOM SCENE
                            // =================================================

                            const _BottomScene(),

                            const SizedBox(height: 8),

                            // مدخل الإدارة صغير عمدًا حتى تظل واجهتا العميل والفني هما الأساس.
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AdminLoginPage(),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF607D8B),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                minimumSize: const Size(0, 26),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'دخول الإدارة',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            const SizedBox(height: 3),
                          ],
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

// ============================================================================
// SECTION TITLE
// ============================================================================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.fontSize,
  });

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1.2,
            color: const Color(0xFFD5E2EF),
          ),
        ),

        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
            ),
            child: Text(
              'اختر نوع الحساب',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: navy,
                height: 1.1,
              ),
            ),
          ),
        ),

        Expanded(
          child: Container(
            height: 1.2,
            color: const Color(0xFFD5E2EF),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// LOGO / LANGUAGE
// ============================================================================

class _LanguageButton extends StatelessWidget {
  const _LanguageButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: const Color(0xFFD4E1EF),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.language,
            size: 17,
            color: navy,
          ),
          SizedBox(width: 5),
          Text(
            'العربية',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: navy,
            ),
          ),
          SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: navy,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ACCOUNT CARD
// ============================================================================

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.iconAsset,
    required this.arrowAsset,
    required this.background,
    required this.borderColor,
    required this.arrowColor,
    required this.onTap,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final String description;

  final String iconAsset;
  final String arrowAsset;

  final Color background;
  final Color borderColor;
  final Color arrowColor;

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double iconSize = compact ? 52 : 60;
    final double arrowSize = compact ? 40 : 44;

    final double titleSize = compact ? 17 : 20;
    final double subtitleSize = compact ? 12 : 13;
    final double descriptionSize = compact ? 9 : 10;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 12,
            vertical: compact ? 7 : 8,
          ),
          decoration: BoxDecoration(
            color: background.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: borderColor,
              width: 1.15,
            ),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.13),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // =============================================================
              // ACCOUNT ICON
              // =============================================================

              SizedBox(
                width: iconSize,
                height: iconSize,
                child: Image.asset(
                  iconAsset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) {
                    return const SizedBox.shrink();
                  },
                ),
              ),

              SizedBox(
                width: compact ? 8 : 11,
              ),

              // =============================================================
              // TEXT
              // =============================================================

              Expanded(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          color: navy,
                          height: 1.05,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        subtitle,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w700,
                          color: arrowColor,
                          height: 1.05,
                        ),
                      ),

                      const SizedBox(height: 1),

                      Text(
                        description,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: descriptionSize,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF536D89),
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(
                width: compact ? 7 : 9,
              ),

              // =============================================================
              // ARROW
              // =============================================================

              SizedBox(
                width: arrowSize,
                height: arrowSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: arrowColor,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(
                      compact ? 8 : 9,
                    ),
                    child: Image.asset(
                      arrowAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        return Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: compact ? 22 : 25,
                        );
                      },
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
}

// ============================================================================
// BOTTOM SCENE
// ============================================================================

class _BottomScene extends StatelessWidget {
  const _BottomScene();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // نسبة ثابتة تقريبًا بدل ارتفاع ثابت.
        // ده يمنع شكل المستطيل من التمدد بشكل غريب على الأجهزة المختلفة.

        final double height;

        if (width <= 320) {
          height = 68;
        } else if (width <= 360) {
          height = 73;
        } else if (width <= 430) {
          height = 80;
        } else if (width <= 600) {
          height = 88;
        } else if (width <= 900) {
          height = 96;
        } else {
          height = 105;
        }

        return SizedBox(
          width: double.infinity,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.asset(
              '${AccountTypePage.assets}bottom_background.png',
              width: double.infinity,
              height: height,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) {
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      },
    );
  }
}