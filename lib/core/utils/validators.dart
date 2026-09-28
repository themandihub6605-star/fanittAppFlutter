import 'package:flutter/services.dart';

typedef FieldValidator = String? Function(String? value);

abstract final class Validators {
  static final RegExp _email = RegExp(r"^[\w.+'-]+@[\w-]+(\.[\w-]+)+$");
  static final RegExp _indianMobile = RegExp(r'^(\+91)?[6-9]\d{9}$');

  static String? email(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter your email address';
    if (!_email.hasMatch(input)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password';
    return null;
  }

  static String? newPassword(String? value) {
    if ((value ?? '').isEmpty) return 'Create a password';
    if (value!.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static FieldValidator requiredText(String fieldName, {int minLength = 2}) {
    return (value) {
      final input = value?.trim() ?? '';
      if (input.isEmpty) return 'Enter your ${fieldName.toLowerCase()}';
      if (input.length < minLength) return '$fieldName must be at least $minLength characters';
      return null;
    };
  }

  static String? optionalMobile(String? value) {
    final input = normalizeMobile(value);
    if (input.isEmpty) return null;
    if (!_indianMobile.hasMatch(input)) return 'Enter a valid 10-digit mobile number';
    return null;
  }

  static String normalizeMobile(String? value) => (value ?? '').replaceAll(RegExp(r'[\s-]'), '');

  /// Referral codes are exactly 8 characters: 2 letters + 6 letters/digits (e.g. CRK7F3QX).
  static const int referralCodeLength = 8;
  static final RegExp _referralCode = RegExp(r'^[A-Z]{2}[A-Z0-9]{6}$');

  static String? optionalReferralCode(String? value) {
    final input = (value ?? '').trim().toUpperCase();
    if (input.isEmpty) return null;
    if (!_referralCode.hasMatch(input)) return 'Referral code must be exactly 8 characters';
    return null;
  }

  static String? referralCode(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Enter the code';
    return optionalReferralCode(value);
  }

  /// Letters/digits only, uppercase, max 8 characters.
  static List<TextInputFormatter> get referralCodeFormatters => [
    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
    LengthLimitingTextInputFormatter(referralCodeLength),
    const UpperCaseTextFormatter(),
  ];
}

class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}