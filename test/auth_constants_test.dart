import 'package:flutter_test/flutter_test.dart';
import 'package:homagram/features/auth/domain/auth_constants.dart';

void main() {
  group('HomaGram username validation', () {
    test('accepts valid lowercase username', () {
      expect(validateHomagramUsername('homa_gram7'), isNull);
    });
    test('rejects too-short username', () {
      expect(validateHomagramUsername('abcd'), isNotNull);
      expect(validateHomagramUsername('abcde'), isNull);
    });
    test('allows the three-character admin username only for the admin email', () {
      expect(validateHomagramUsername('ali', accountEmail: 'theslyapex@gmail.com'), isNull);
      expect(validateHomagramUsername('ali', accountEmail: 'someone@example.com'), isNotNull);
      expect(validateHomagramUsername('ali', accountEmail: 'theslyapex@gmail.com '), isNull);
    });
    test('rejects uppercase and spaces', () {
      expect(validateHomagramUsername('Homa Gram'), isNotNull);
    });
    test('trims surrounding whitespace', () {
      expect(validateHomagramUsername('  homa_gram  '), isNull);
    });
  });
}
