import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hubble/core/theme/tokens.dart';

void main() {
  group('HubbleTokens', () {
    test('host defaults match the Industrial Bolt matrix', () {
      const t = HubbleTokens.host;
      expect(toHex(t.canvas), '#1A1A1A');
      expect(toHex(t.surface), '#222222');
      expect(toHex(t.accent), '#FF7A00');
      expect(toHex(t.iron), '#4A4A4A');
      expect(toHex(t.alert), '#FF3B30');
    });

    test('merge applies valid overrides and ignores junk', () {
      final merged = HubbleTokens.host.merge({
        'accent': '#00AAFF',
        'canvas': 'not-a-color',
        'font': '#FFFFFF',
        'surface': 12,
      });
      expect(toHex(merged.accent), '#00AAFF');
      expect(merged.canvas, HubbleTokens.host.canvas);
      expect(merged.surface, HubbleTokens.host.surface);
    });

    test('diffFromHost only reports changed keys', () {
      final merged = HubbleTokens.host.merge({'accent': '#00AAFF'});
      expect(merged.diffFromHost(), {'accent': '#00AAFF'});
      expect(HubbleTokens.host.diffFromHost(), isEmpty);
    });

    test('hex parsing round-trips', () {
      expect(parseHexColor('#ff7a00'), const Color(0xFFFF7A00));
      expect(parseHexColor('#FF7A00 '), const Color(0xFFFF7A00));
      expect(parseHexColor('FF7A00'), isNull);
      expect(parseHexColor('#FFF'), isNull);
      expect(toHex(const Color(0xFF0000AA)), '#0000AA');
    });

    test('value equality', () {
      expect(HubbleTokens.host.merge({}), HubbleTokens.host);
      expect(HubbleTokens.host.merge({'accent': '#00AAFF'}), isNot(HubbleTokens.host));
    });
  });
}
