import 'package:beta_care/models/status_level.dart';
import 'package:beta_care/widgets/status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the default label for its status level', (tester) async {
    await tester.pumpWidget(_wrap(const StatusIndicator(level: StatusLevel.attention)));
    expect(find.text('Needs attention'), findsOneWidget);
  });

  testWidgets('an explicit label overrides the default one', (tester) async {
    await tester.pumpWidget(_wrap(const StatusIndicator(level: StatusLevel.normal, label: 'Taken')));
    expect(find.text('Taken'), findsOneWidget);
    expect(find.text('Normal'), findsNothing);
  });

  testWidgets('compact mode renders only the icon, no label text', (tester) async {
    await tester.pumpWidget(_wrap(const StatusIndicator(level: StatusLevel.emergency, compact: true)));
    expect(find.byIcon(statusIcon(StatusLevel.emergency)), findsOneWidget);
    expect(find.text('Emergency'), findsNothing);
  });
}
