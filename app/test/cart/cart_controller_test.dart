import 'package:flutter_test/flutter_test.dart';
import 'package:hubble/core/models/product.dart';
import 'package:hubble/viewports/customer/cart/cart_controller.dart';

const taco = Product(
  id: 'p1',
  vendorId: 'taco',
  name: 'Street Taco',
  priceCents: 350,
  modifiers: [ProductModifier(id: 'm1', name: 'Extra meat', priceDeltaCents: 150)],
);
const horchata = Product(id: 'p2', vendorId: 'taco', name: 'Horchata', priceCents: 400);
const booster = Product(id: 'p3', vendorId: 'cards', name: 'Booster Pack', priceCents: 499);

void main() {
  group('CartController (single-store boundary)', () {
    test('items are grouped into independent carts keyed by vendor', () {
      final c = CartController();
      c.add(taco, vendorId: 'taco', vendorName: 'Taco Bolt', quantity: 2, modifierIds: ['m1']);
      c.add(horchata, vendorId: 'taco', vendorName: 'Taco Bolt');
      c.add(booster, vendorId: 'cards', vendorName: 'Card Forge');

      expect(c.vendorCount, 2);
      expect(c.totalItems, 4);
      expect(c.cartFor('taco')!.subtotalCents, (350 + 150) * 2 + 400);
      expect(c.cartFor('cards')!.subtotalCents, 499);
      expect(c.carts.first.vendorId, 'cards', reason: 'most recently touched first');
    });

    test('a product can never enter another vendor cart', () {
      final c = CartController();
      expect(() => c.add(booster, vendorId: 'taco'), throwsA(isA<CartBoundaryException>()));
      expect(c.vendorCount, 0);
    });

    test('same product + modifiers merge; different modifiers stay separate', () {
      final c = CartController();
      c.add(taco, vendorId: 'taco');
      c.add(taco, vendorId: 'taco');
      c.add(taco, vendorId: 'taco', modifierIds: ['m1']);
      final lines = c.cartFor('taco')!.lines;
      expect(lines, hasLength(2));
      expect(lines.first.quantity, 2);
      expect(lines.last.unitPriceCents, 500);
    });

    test('quantity edits, removal and clearing notify listeners', () {
      final c = CartController();
      var ticks = 0;
      c.addListener(() => ticks++);
      c.add(taco, vendorId: 'taco');
      final key = c.cartFor('taco')!.lines.single.key;
      c.setQuantity('taco', key, 5);
      expect(c.cartFor('taco')!.itemCount, 5);
      c.setQuantity('taco', key, 0);
      expect(c.cartFor('taco')!.isEmpty, isTrue);
      expect(c.carts, isEmpty);
      c.add(taco, vendorId: 'taco');
      c.clear('taco');
      expect(c.cartFor('taco'), isNull);
      expect(ticks, 5);
    });

    test('quantity is clamped to 1..99 and rejects zero on add', () {
      final c = CartController();
      c.add(taco, vendorId: 'taco', quantity: 98);
      c.add(taco, vendorId: 'taco', quantity: 5);
      expect(c.cartFor('taco')!.itemCount, 99);
      expect(() => c.add(taco, vendorId: 'taco', quantity: 0), throwsArgumentError);
    });

    test('serialises per vendor and survives corrupt entries', () {
      final c = CartController();
      c.add(taco, vendorId: 'taco', vendorName: 'Taco Bolt', modifierIds: ['m1'], note: 'no onions');
      c.add(booster, vendorId: 'cards', vendorName: 'Card Forge');
      final json = c.toJson();
      expect(json.keys, containsAll(['taco', 'cards']));

      final restored = CartController.fromJson({...json, 'broken': 'nope'});
      expect(restored.vendorCount, 2);
      final line = restored.cartFor('taco')!.lines.single;
      expect(line.note, 'no onions');
      expect(line.modifierIds, ['m1']);
      expect(line.product.name, 'Street Taco');
      expect(restored.cartFor('taco')!.subtotalCents, 350);
    });
  });
}
