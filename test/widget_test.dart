// Basic startup smoke test for SmartBus Global.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartbus_drivers/main.dart';

void main() {
  testWidgets('App starts on the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartBusApp());

    // The splash shows a progress bar while the route is being decided.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
