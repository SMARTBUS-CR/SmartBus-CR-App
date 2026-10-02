import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbus_drivers/core/theme.dart';
import 'package:smartbus_drivers/widgets/smartbus_header.dart';

final _header = find.byKey(const Key('smartbus_header'));
final _bus = find.byKey(const Key('smartbus_header_bus'));
final _pin = find.byKey(const Key('smartbus_header_pin'));
final _back = find.byTooltip('Volver');

Future<void> _pump(
  WidgetTester tester,
  SmartBusHeader header, {
  Size size = const Size(390, 844),
  double statusBar = 0,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(top: statusBar * 3);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Column(children: [header])),
    ),
  );
}

List<Color> _gradientColors(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.ancestor(of: _header, matching: find.byType(DecoratedBox)).first,
  );
  return ((box.decoration as BoxDecoration).gradient! as LinearGradient).colors;
}

void main() {
  testWidgets('shows the title and the optional subtitle', (tester) async {
    await _pump(
      tester,
      const SmartBusHeader(
        title: 'Recorrido',
        subtitle: 'Viaje #a1b2',
        type: SmartBusUserType.driver,
      ),
    );

    expect(find.text('Recorrido'), findsOneWidget);
    expect(find.text('Viaje #a1b2'), findsOneWidget);
  });

  group('back button', () {
    testWidgets('is hidden without onBack', (tester) async {
      await _pump(
        tester,
        const SmartBusHeader(title: 'Inicio', type: SmartBusUserType.passenger),
      );

      expect(_back, findsNothing);
    });

    testWidgets('is shown with onBack and calls it', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        SmartBusHeader(
          title: 'Mi Cuenta',
          type: SmartBusUserType.passenger,
          onBack: () => taps++,
        ),
      );

      await tester.tap(_back);
      expect(taps, 1);
    });
  });

  group('role identity', () {
    testWidgets('driver: blue theme gradient and a bus', (tester) async {
      await _pump(
        tester,
        const SmartBusHeader(title: 'Mis Rutas', type: SmartBusUserType.driver),
      );

      expect(_gradientColors(tester), [
        SmartBusColors.azulDriverCobalto,
        SmartBusColors.azulDriverBrillante,
        SmartBusColors.azulDriverIndigo,
        SmartBusColors.azulDriverMarino,
        SmartBusColors.azulDriverElectrico,
      ]);
      expect(_bus, findsOneWidget);
      expect(_pin, findsOneWidget);
    });

    testWidgets('passenger: green theme gradient and no bus', (tester) async {
      await _pump(
        tester,
        const SmartBusHeader(
          title: 'Mis Viajes',
          type: SmartBusUserType.passenger,
        ),
      );

      expect(_gradientColors(tester), [
        SmartBusColors.verdePasajeroIntenso,
        SmartBusColors.verdePasajero,
        SmartBusColors.verdePasajeroClaro,
      ]);
      expect(_bus, findsNothing);
      expect(_pin, findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('compact variant is shorter than the regular one', (
      tester,
    ) async {
      await _pump(
        tester,
        const SmartBusHeader(title: 'A', type: SmartBusUserType.driver),
      );
      final regular = tester.getSize(_header).height;

      await _pump(
        tester,
        const SmartBusHeader(
          title: 'A',
          type: SmartBusUserType.driver,
          compact: true,
        ),
      );
      final compact = tester.getSize(_header).height;

      expect(compact, lessThan(regular));
    });

    testWidgets('makes room for the status bar / notch', (tester) async {
      const header = SmartBusHeader(
        title: 'Mi Cuenta',
        type: SmartBusUserType.driver,
      );
      await _pump(tester, header);
      final withoutInset = tester.getSize(_header).height;

      await _pump(tester, header, statusBar: 47);
      expect(tester.getSize(_header).height, withoutInset + 47);
      // The title starts below the status bar.
      expect(tester.getTopLeft(find.text('Mi Cuenta')).dy, greaterThan(47));
    });

    testWidgets('long title fits a small phone without overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        SmartBusHeader(
          title: 'Un título muy largo que no cabe en la pantalla' * 2,
          subtitle: 'Ruta 4 · Sarapiquí – Puerto Viejo',
          type: SmartBusUserType.passenger,
          compact: true,
          onBack: () {},
        ),
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(
        find.textContaining('Un título muy largo'),
      );
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('driver and passenger share the compact header composition', (
      tester,
    ) async {
      await _pump(
        tester,
        const SmartBusHeader(title: 'Mi Cuenta', type: SmartBusUserType.driver),
      );
      final driverHeight = tester.getSize(_header).height;

      await _pump(
        tester,
        const SmartBusHeader(
          title: 'Mi Cuenta',
          type: SmartBusUserType.passenger,
        ),
      );

      expect(tester.getSize(_header).height, driverHeight);
      // Both roles share the title row composition; the driver adds its bus.
      expect(
        tester.getTopLeft(_pin).dy,
        lessThan(tester.getBottomLeft(find.text('Mi Cuenta')).dy),
      );
      await _pump(
        tester,
        const SmartBusHeader(title: 'Mi Cuenta', type: SmartBusUserType.driver),
      );
      expect(_bus, findsOneWidget);
    });

    testWidgets('passenger with subtitle: the drawing goes below the text', (
      tester,
    ) async {
      await _pump(
        tester,
        const SmartBusHeader(
          title: 'Rastreando tu bus',
          subtitle: 'Ruta 4 · Sarapiquí – Puerto Viejo',
          type: SmartBusUserType.passenger,
          compact: true,
        ),
      );

      expect(
        tester.getTopLeft(_pin).dy,
        greaterThanOrEqualTo(
          tester
              .getBottomLeft(find.text('Ruta 4 · Sarapiquí – Puerto Viejo'))
              .dy,
        ),
      );
    });

    testWidgets('uses light status bar icons', (tester) async {
      await _pump(
        tester,
        const SmartBusHeader(title: 'Inicio', type: SmartBusUserType.driver),
      );

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(region.value, SystemUiOverlayStyle.light);
    });
  });
}
