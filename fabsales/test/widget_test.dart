import 'package:flutter_test/flutter_test.dart';
import 'package:schematic_studio/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SchematicStudioApp());
    expect(find.byType(SchematicStudioApp), findsOneWidget);
  });
}
