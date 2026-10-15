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
    if (!RegExp(r'^[+0-9\s().-]+$').hasMatch(raw) ||
        '+'.allMatches(raw).length > 1 ||
        (raw.contains('+') && !raw.startsWith('+'))) {
      return const PhoneNumberValidation.invalid(
        'Masukkan nomor ponsel Indonesia yang valid.',
      );
    }
    final digits = raw.replaceAll(RegExp(r'[\s().-]'), '');
    String national;

    if (digits.startsWith('+62')) {
      national = digits.substring(3);
    } else if (digits.startsWith('62')) {
      national = digits.substring(2);
    } else if (digits.startsWith('0')) {
      national = digits.substring(1);
    } else {
      national = digits;
    }

    if (national.isEmpty || !RegExp(r'^8\d+$').hasMatch(national)) {
      return const PhoneNumberValidation.invalid(
        'Masukkan nomor ponsel Indonesia yang valid.',
      );
    }
    if (national.length < 9 || national.length > 13) {
      return const PhoneNumberValidation.invalid(
        'Nomor ponsel harus terdiri dari 9–13 digit setelah +62.',
      );
    }

    return PhoneNumberValidation.valid('+62$national');
  }
}
