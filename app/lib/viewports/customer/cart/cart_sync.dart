import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/order.dart';
import 'cart_controller.dart';

/// Pushes a single vendor cart to the database and invokes the stripe-split
/// edge function, which creates exactly one order + PaymentIntent for that
/// vendor.
class CheckoutService {
  CheckoutService(this._db);

  final SupabaseClient _db;

  Future<CheckoutResult> checkout(VendorCart cart, {String? note}) async {
    final row = await _db.rpc<dynamic>('get_or_create_cart', params: {'p_vendor_id': cart.vendorId});
    final cartId = (row as Map)['id'] as String;

    await _db.from('cart_items').delete().eq('cart_id', cartId);
    if (cart.lines.isNotEmpty) {
      await _db.from('cart_items').insert([
        for (final line in cart.lines)
          {
            'cart_id': cartId,
            'product_id': line.product.id,
            'quantity': line.quantity,
            'modifiers': line.modifierIds,
            'note': line.note,
          },
      ]);
    }

    final response = await _db.functions.invoke(
      'stripe-split',
      body: {'vendor_id': cart.vendorId, if (note != null && note.isNotEmpty) 'note': note},
    );
    final data = (response.data as Map).cast<String, dynamic>();
    if (response.status >= 400) {
      throw CheckoutException(data['error'] as String? ?? 'checkout failed');
    }
    final intent = (data['payment_intent'] as Map).cast<String, dynamic>();
    return CheckoutResult(
      order: OrderSummary.fromJson((data['order'] as Map).cast<String, dynamic>()),
      paymentIntentId: intent['id'] as String,
      clientSecret: intent['client_secret'] as String,
    );
  }
}

class CheckoutResult {
  const CheckoutResult({required this.order, required this.paymentIntentId, required this.clientSecret});

  final OrderSummary order;
  final String paymentIntentId;

  /// Hand this to the Stripe payment sheet on the device.
  final String clientSecret;
}

class CheckoutException implements Exception {
  const CheckoutException(this.message);

  final String message;

  @override
  String toString() => message;
}
