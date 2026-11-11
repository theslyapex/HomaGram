import 'package:flutter_test/flutter_test.dart';
import 'package:homagram/app/homagram_app.dart';

void main() {
  testWidgets('shows HomaGram bootstrap screen without backend config',
      (tester) async {
    await tester.pumpWidget(const HomaGramApp(supabaseConfigured: false));

    expect(find.text('HomaGram'), findsOneWidget);
    expect(find.text('ارتباطی فراتر از مرزها'), findsOneWidget);
    expect(find.text('اتصال Supabase هنوز پیکربندی نشده است'), findsOneWidget);
  });
}
