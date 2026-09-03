import 'package:flutter_test/flutter_test.dart';
import 'package:hubble/interpreter/ast_node.dart';

void main() {
  group('LayoutNode.parse', () {
    test('parses the starter layout shape', () {
      final root = LayoutNode.parse({
        'type': 'screen',
        'props': {'scroll': true},
        'children': [
          {
            'type': 'hero',
            'props': {
              'title': 'Taco Bolt',
              'logo': {r'$bind': 'vendor.logo_url'},
              'background': {r'$token': 'surface'},
            },
          },
          {'type': 'divider'},
          {
            'type': 'product_list',
            'props': {'source': 'vendor.products', 'layout': 'list'},
          },
          {
            'type': 'button',
            'props': {'label': 'VIEW CART', 'action': 'open_cart'},
          },
        ],
      });
      expect(root.type, NodeType.screen);
      expect(root.children, hasLength(4));
      expect(root.children.first.props['logo'], const BindRef('vendor.logo_url'));
      expect(root.children.first.props['background'], const TokenRef('surface'));
      expect(root.nodeCount, 5);
    });

    test('round-trips through toJson', () {
      final json = {
        'type': 'screen',
        'children': [
          {
            'type': 'text',
            'props': {
              'text': 'hi',
              'color': {r'$token': 'accent'},
            },
          },
        ],
      };
      expect(LayoutNode.parse(json).toJson(), json);
    });

    test('root must be a screen', () {
      expect(() => LayoutNode.parse({'type': 'column'}), throwsA(isA<LayoutValidationException>()));
    });

    test('screens cannot nest', () {
      expect(
        () => LayoutNode.parse({
          'type': 'screen',
          'children': [
            {'type': 'screen'},
          ],
        }),
        throwsA(isA<LayoutValidationException>().having((e) => e.message, 'message', contains('root'))),
      );
    });

    test('unknown node types are rejected, never executed', () {
      expect(
        () => LayoutNode.parse({
          'type': 'screen',
          'children': [
            {
              'type': 'webview',
              'props': {'url': 'https://evil'},
            },
          ],
        }),
        throwsA(isA<LayoutValidationException>().having((e) => e.path, 'path', r'$.children[0]')),
      );
    });

    test('leaves cannot have children', () {
      expect(
        () => LayoutNode.parse({
          'type': 'screen',
          'children': [
            {'type': 'text', 'children': <Object?>[]},
          ],
        }),
        throwsA(
          isA<LayoutValidationException>().having(
            (e) => e.message,
            'message',
            contains('cannot have children'),
          ),
        ),
      );
    });

    test('binds and actions are whitelisted', () {
      expect(
        () => LayoutNode.parse({
          'type': 'screen',
          'children': [
            {
              'type': 'hero',
              'props': {
                'logo': {r'$bind': 'vendor.stripe_account_id'},
              },
            },
          ],
        }),
        throwsA(
          isA<LayoutValidationException>().having((e) => e.message, 'message', contains('unknown bind')),
        ),
      );
      expect(
        () => LayoutNode.parse({
          'type': 'screen',
          'children': [
            {
              'type': 'button',
              'props': {'action': 'run_script'},
            },
          ],
        }),
        throwsA(
          isA<LayoutValidationException>().having(
            (e) => e.message,
            'message',
            contains('unknown button action'),
          ),
        ),
      );
      expect(
        () => LayoutNode.parse({
          'type': 'screen',
          'children': [
            {
              'type': 'button',
              'props': {'action': 'open_url', 'url': 'javascript:alert(1)'},
            },
          ],
        }),
        throwsA(isA<LayoutValidationException>().having((e) => e.message, 'message', contains('https'))),
      );
      expect(
        () => LayoutNode.parse({
          'type': 'screen',
          'children': [
            {
              'type': 'image',
              'props': {'src': 'http://insecure'},
            },
          ],
        }),
        throwsA(isA<LayoutValidationException>()),
      );
    });

    test('depth is bounded', () {
      Map<String, Object?> node = {'type': 'column'};
      for (var i = 0; i < 30; i++) {
        node = {
          'type': 'column',
          'children': <Object?>[node],
        };
      }
      expect(
        () => LayoutNode.parse({
          'type': 'screen',
          'children': [node],
        }),
        throwsA(isA<LayoutValidationException>().having((e) => e.message, 'message', contains('deeper'))),
      );
    });
  });
}
