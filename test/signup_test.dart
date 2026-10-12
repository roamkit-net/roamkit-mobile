import 'package:flutter_test/flutter_test.dart';
import 'package:roamkit_mobile/signup.dart';

void main() {
  test('password rules match the signup checklist', () {
    expect(passwordMeetsRules('short'), isFalse);
    expect(passwordMeetsRules('noupper1!'), isFalse);
    expect(passwordMeetsRules('NOLOWER1!'), isFalse);
    expect(passwordMeetsRules('NoNumber!'), isFalse);
    expect(passwordMeetsRules('NoSymbol1'), isFalse);
    expect(passwordMeetsRules('SecurePass1!'), isTrue);
  });

  test('display name joins the optional last name', () {
    expect(signupDisplayName('Ante', 'Vrcan'), 'Ante Vrcan');
    expect(signupDisplayName('Ante', ''), 'Ante');
  });
}
