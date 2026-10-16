import 'package:phone_numbers_parser/phone_numbers_parser.dart';

class PhoneNumberValidation {
  const PhoneNumberValidation.valid(this.e164) : error = null;

  const PhoneNumberValidation.invalid(this.error) : e164 = null;

  final String? e164;
  final String? error;

  bool get isValid => e164 != null;
}

class IndonesianPhoneNumber {
  IndonesianPhoneNumber._();

  static PhoneNumberValidation normalize(String input) {
    final raw = input.trim();
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final isIndonesian =
        raw.startsWith('+62') ||
        (!raw.startsWith('+') &&
            (digits.startsWith('62') ||
                digits.startsWith('0') ||
                digits.startsWith('8')));
    if (!isIndonesian) {
      return const PhoneNumberValidation.invalid(
        'Masukkan nomor ponsel Indonesia yang valid.',
      );
    }
    return PhoneNumberNormalizer.normalize(input, isoCode: 'ID');
  }
}

/// Normalizes country-local and pasted international numbers to E.164.
///
/// An explicit international prefix always wins over the selected country.
/// Indonesian numbers without a plus continue to accept the legacy `62...`
/// format alongside local numbers beginning with `0`.
class PhoneNumberNormalizer {
  PhoneNumberNormalizer._();

  /// Returns the shared calling code for an ISO region, or null when unknown.
  /// Some country lists include area codes in their `phoneCode` (for example
  /// Bahamas `1242`); the phone parser correctly treats these as +1 regions.
  static String? dialCodeForIso(String isoCode) {
    try {
      return PhoneNumber(
        isoCode: IsoCode.values.byName(isoCode.toUpperCase()),
        nsn: '',
      ).countryCode;
    } on Object {
      return null;
    }
  }

  static PhoneNumberValidation normalize(
    String input, {
    required String isoCode,
  }) {
    final raw = input.trim();
    if (raw.isEmpty ||
        !RegExp(r'^[+0-9\s().-]+$').hasMatch(raw) ||
        '+'.allMatches(raw).length > 1 ||
        (raw.contains('+') && !raw.startsWith('+'))) {
      return const PhoneNumberValidation.invalid(
        'Masukkan nomor ponsel yang valid.',
      );
    }

    var parseable = raw;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.startsWith('00')) {
      parseable = '+${raw.substring(2)}';
    } else if (isoCode.toUpperCase() == 'ID' && digits.startsWith('62')) {
      // Keep the formats previously accepted by IndonesianPhoneNumber.
      parseable = '+$digits';
    }

    try {
      final number = PhoneNumber.parse(
        parseable,
        callerCountry: parseable.startsWith('+')
            ? null
            : IsoCode.values.byName(isoCode.toUpperCase()),
      );
      if (!number.isValid(type: PhoneNumberType.mobile)) {
        return const PhoneNumberValidation.invalid(
          'Masukkan nomor ponsel yang valid untuk negara yang dipilih.',
        );
      }
      return PhoneNumberValidation.valid(number.international);
    } on Object {
      return const PhoneNumberValidation.invalid(
        'Masukkan nomor ponsel yang valid untuk negara yang dipilih.',
      );
    }
  }
}
