class PasswordRule {
  const PasswordRule({required this.label, required this.met});

  final String label;
  final bool met;
}

const passwordSymbols = r"""!$%^&*()_-+=[]{}|;:'",.<>?/""";

List<PasswordRule> passwordRules(String password) {
  return [
    PasswordRule(label: 'Minimum 8 characters', met: password.length >= 8),
    PasswordRule(label: 'Uppercase', met: password.contains(RegExp(r'[A-Z]'))),
    PasswordRule(label: 'Lowercase', met: password.contains(RegExp(r'[a-z]'))),
    PasswordRule(
      label: 'Numbers 1234567890',
      met: password.contains(RegExp(r'[0-9]')),
    ),
    PasswordRule(
      label: 'A symbol $passwordSymbols',
      met: password.split('').any(passwordSymbols.contains),
    ),
  ];
}

bool passwordMeetsRules(String password) {
  return passwordRules(password).every((rule) => rule.met);
}

bool signupEmailLooksValid(String value) {
  final email = value.trim();
  final at = email.indexOf('@');
  return at > 0 && email.substring(at + 1).contains('.');
}

String signupDisplayName(String firstName, String lastName) {
  return '${firstName.trim()} ${lastName.trim()}'.trim();
}
