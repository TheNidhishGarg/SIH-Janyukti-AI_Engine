import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract class AppDimensions {
  // Spacing
  static const double spacing4 = 4.0;
  static const double spacing6 = 6.0;
  static const double spacingSmall = 8.0;
  static const double spacing10 = 10.0;
  static const double spacing12 = 12.0;
  static const double spacingMedium = 16.0;
  static const double spacing20 = 20.0;
  static const double spacingLarge = 24.0;
  static const double spacingExLarge = 32.0;
  static const double spacing36 = 36.0;
  static const double spacing40 = 40.0;

  // Paddings
  static const EdgeInsets padding4 = EdgeInsets.all(4);
  static const EdgeInsets padding5 = EdgeInsets.all(5);
  static const EdgeInsets padding6 = EdgeInsets.all(6);
  static const EdgeInsets padding = EdgeInsets.all(8);
  static const EdgeInsets padding10 = EdgeInsets.all(10);
  static const EdgeInsets padding12 = EdgeInsets.all(12);
  static const EdgeInsets padding16 = EdgeInsets.all(16);
  static const EdgeInsets padding20 = EdgeInsets.all(20);
  static const EdgeInsets padding48 = EdgeInsets.all(48);
  static const EdgeInsets paddingHV16 = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 16,
  );
  static const EdgeInsets paddingHV1614 = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );
  static const EdgeInsets paddingHV12 = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );
  // Margins
  static const EdgeInsets margin5 = EdgeInsets.all(5);
  static const EdgeInsets margin10 = EdgeInsets.all(10);
  static const EdgeInsets margin16 = EdgeInsets.all(16);
  static const EdgeInsets marginV5 = EdgeInsets.symmetric(vertical: 5);
  static const EdgeInsets marginV10 = EdgeInsets.symmetric(vertical: 10);
  static const EdgeInsets marginH5 = EdgeInsets.symmetric(horizontal: 5);
  static const EdgeInsets marginH10 = EdgeInsets.symmetric(horizontal: 10);
  static const EdgeInsets margin20 = EdgeInsets.all(20);
  static const EdgeInsets marginB16 = EdgeInsets.only(bottom: 16);
  static const EdgeInsets marginB4 = EdgeInsets.only(bottom: 4);

  /// List padding is equal on `LTR` and extra on `Bottom`
  static const EdgeInsets listPadding = EdgeInsets.fromLTRB(10, 10, 10, 120);

  static const BorderRadius borderRadius5 =
      BorderRadius.all(Radius.circular(5));
  static const BorderRadius borderRadius = BorderRadius.all(
    Radius.circular(8),
  );
  static const BorderRadius borderRadius6 = BorderRadius.all(
    Radius.circular(6),
  );
  static const BorderRadius borderRadius10 = BorderRadius.all(
    Radius.circular(10),
  );
  static const BorderRadius borderRadius8 = BorderRadius.all(
    Radius.circular(8),
  );
  static const BorderRadius borderRadius12 = BorderRadius.all(
    Radius.circular(12),
  );
  static const BorderRadius borderRadius16 = BorderRadius.all(
    Radius.circular(16),
  );
  static const BorderRadius borderRadius20 = BorderRadius.all(
    Radius.circular(20),
  );
  static const BorderRadius borderRadius30 = BorderRadius.all(
    Radius.circular(30),
  );
  static const BorderRadius borderRadiusCircle = BorderRadius.all(
    Radius.circular(80),
  );
  static Border border1 = Border.all(
    width: 1,
    color: AppColors.border,
  );

  static const BorderRadius borderRadiusBottomSheet = BorderRadius.only(
    topRight: Radius.circular(20),
    topLeft: Radius.circular(20),
  );
  static const BorderRadius borderRadiusBottomSheetLarge = BorderRadius.only(
    topRight: Radius.circular(80),
    topLeft: Radius.circular(80),
  );

  /// Primary box shadow - Light Black Shadow
  static const BoxShadow otpShadow = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.05),
    blurRadius: 4,
    spreadRadius: 0,
    offset: Offset(0.0, 1.0),
  );

  /// Primary box shadow - Light Black Shadow
  static const BoxShadow primaryShadow = BoxShadow(
    color: Color.fromARGB(255, 230, 230, 230),
    blurRadius: 15,
    spreadRadius: 3,
    offset: Offset(0.0, 3.0),
  );

  /// Primary box shadow - dark Black Shadow
  static const BoxShadow primaryShadowDark = BoxShadow(
    color: Colors.black38,
    blurRadius: 15,
    spreadRadius: 3,
    offset: Offset(0.0, 3.0),
  );

  static const BoxShadow productItemCardShadow = BoxShadow(
    color: Color.fromARGB(255, 230, 230, 230),
    blurRadius: 5,
    spreadRadius: 2,
    offset: Offset(0.0, 3.0),
  );

  static const BoxShadow productItemCardShadowDark = BoxShadow(
    color: Colors.black38,
    blurRadius: 5,
    spreadRadius: 2,
    offset: Offset(0.0, 3.0),
  );

  static const BoxShadow textFieldShadow = BoxShadow(
    color: Color.fromARGB(255, 230, 230, 230),
    blurRadius: 20,
    spreadRadius: 2,
    offset: Offset(0.0, 3.0),
  );

  static const BoxShadow textFieldShadowDark = BoxShadow(
    color: Colors.black38,
    blurRadius: 20,
    spreadRadius: 2,
    offset: Offset(0.0, 3.0),
  );

  static const BoxShadow darkShadow = BoxShadow(
    color: Color.fromARGB(100, 150, 150, 150),
    spreadRadius: 1,
    blurRadius: 20,
    offset: Offset(0.0, 2.0),
  );

  /// Checks if the theme is in dark mode
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == ThemeData.dark().brightness;
  }
}
