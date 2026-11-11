import 'package:flutter_test/flutter_test.dart';
import 'package:homagram/features/auth/domain/auth_constants.dart';

void main() {
  group('HomaGram username validation', () {
    test('accepts valid lowercase username', () {
      expect(validateHomagramUsername('homa_gram7'), isNull);
    });
    test('rejects too-short username', () {
      expect(validateHomagramUsername('ab'), isNotNull);
    });
    test('rejects uppercase and spaces', () {
      expect(validateHomagramUsername('Homa Gram'), isNotNull);
    });
    test('trims surrounding whitespace', () {
      expect(validateHomagramUsername('  homa_gram  '), isNull);
    });
  });
}
