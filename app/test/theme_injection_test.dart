import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hubble/core/theme/hubble_theme.dart';
import 'package:hubble/core/theme/theme_scope.dart';
import 'package:hubble/core/theme/tokens.dart';

class _AccentProbe extends StatelessWidget {
  const _AccentProbe();

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeInjector.tokensOf(context);
    return ColoredBox(color: tokens.accent, child: const SizedBox(width: 10, height: 10));
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('tapping into a vendor re-skins listeners and leaving resets', (tester) async {
    final controller = VendorThemeController();
    var builds = 0;
    await tester.pumpWidget(
      ThemeInjector(
        controller: controller,
        child: Builder(
          builder: (context) {
            builds++;
            return const Directionality(textDirection: TextDirection.ltr, child: _AccentProbe());
          },
        ),
      ),
    );
    ColoredBox probe() => tester.widget<ColoredBox>(find.byType(ColoredBox));
    expect(probe().color, HubbleTokens.host.accent);
    expect(controller.isHost, isTrue);

    controller.applyVendor('v1', {'accent': '#00AAFF', 'canvas': 'garbage'});
    await tester.pump();
    expect(probe().color, const Color(0xFF00AAFF));
    expect(controller.vendorId, 'v1');

    final before = builds;
    controller.applyVendor('v1', {'accent': '#00AAFF'});
    await tester.pump();
    expect(builds, before, reason: 'identical tokens do not trigger a rebuild');

    controller.reset();
    await tester.pump();
    expect(probe().color, HubbleTokens.host.accent);
    expect(controller.isHost, isTrue);
  });

  test('buildHubbleTheme maps tokens onto the material scheme', () {
    final tokens = HubbleTokens.host.merge({'accent': '#00AAFF', 'canvas': '#000000'});
    final theme = buildHubbleTheme(tokens);
    expect(theme.colorScheme.primary, const Color(0xFF00AAFF));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(theme.colorScheme.error, HubbleTokens.host.alert);
    expect(theme.brightness, Brightness.dark);
  });
}
