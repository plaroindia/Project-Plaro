// ================================================================
// pro_provider.dart
//
// Handles:
//   - Pro subscription status check (reads user_profiles.subscription_tier)
//   - Razorpay order creation via Edge Function 'create-razorpay-order'
//   - Payment verification via Edge Function 'verify-razorpay-payment'
//   - Local pro status cache so UI reacts immediately after purchase
//
// DB dependencies (migrations already applied):
//   user_profiles.subscription_tier  ('free' | 'pro')
//   user_profiles.pro_expires_at     (timestamptz)
//   plaro_transactions.source        ('pro_purchase' added to constraint)
//
// Edge Functions required (to be deployed separately):
//   create-razorpay-order  — creates a Razorpay order, returns { orderId, amount, currency, keyId }
//   verify-razorpay-payment — HMAC-SHA256 verify + DB update, returns { success, expiresAt }
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'user_provider.dart';

// ── Pro plan definitions ──────────────────────────────────────────────────────

enum ProPlan { monthly, annual }

extension ProPlanExt on ProPlan {
  String get id => switch (this) {
    ProPlan.monthly => 'pro_monthly',
    ProPlan.annual  => 'pro_annual',
  };

  String get label => switch (this) {
    ProPlan.monthly => 'Monthly',
    ProPlan.annual  => 'Annual',
  };

  /// Display price — update these when Razorpay plan prices change.
  String get priceLabel => switch (this) {
    ProPlan.monthly => '₹299/month',
    ProPlan.annual  => '₹1,999/year',
  };
}

// ── Models ────────────────────────────────────────────────────────────────────

class RazorpayOrderDetails {
  final String orderId;
  final int    amount;   // paise
  final String currency;
  final String keyId;

  const RazorpayOrderDetails({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.keyId,
  });

  factory RazorpayOrderDetails.fromMap(Map<String, dynamic> m) =>
      RazorpayOrderDetails(
        orderId:  m['orderId']  as String,
        amount:   (m['amount'] as num).toInt(),
        currency: m['currency'] as String? ?? 'INR',
        keyId:    m['keyId']   as String,
      );
}

// ── State ─────────────────────────────────────────────────────────────────────

enum ProPurchaseStep { idle, creatingOrder, awaitingPayment, verifying, done }

class ProState {
  // Subscription info
  final String  subscriptionTier; // 'free' | 'pro'
  final DateTime? proExpiresAt;
  final bool    isProStatusLoading;

  // Purchase flow
  final ProPurchaseStep purchaseStep;
  final RazorpayOrderDetails? pendingOrder;
  final String? purchaseError;
  final bool    purchaseSuccess;

  const ProState({
    this.subscriptionTier    = 'free',
    this.proExpiresAt,
    this.isProStatusLoading  = false,
    this.purchaseStep        = ProPurchaseStep.idle,
    this.pendingOrder,
    this.purchaseError,
    this.purchaseSuccess     = false,
  });

  bool get isPro =>
      subscriptionTier == 'pro' &&
      (proExpiresAt == null || proExpiresAt!.isAfter(DateTime.now()));

  ProState copyWith({
    String?               subscriptionTier,
    DateTime?             proExpiresAt,
    bool?                 isProStatusLoading,
    ProPurchaseStep?      purchaseStep,
    RazorpayOrderDetails? pendingOrder,
    String?               purchaseError,
    bool?                 purchaseSuccess,
    bool                  clearPurchaseError = false,
  }) => ProState(
    subscriptionTier:   subscriptionTier   ?? this.subscriptionTier,
    proExpiresAt:       proExpiresAt       ?? this.proExpiresAt,
    isProStatusLoading: isProStatusLoading ?? this.isProStatusLoading,
    purchaseStep:       purchaseStep       ?? this.purchaseStep,
    pendingOrder:       pendingOrder       ?? this.pendingOrder,
    purchaseError:      clearPurchaseError ? null : (purchaseError ?? this.purchaseError),
    purchaseSuccess:    purchaseSuccess    ?? this.purchaseSuccess,
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ProNotifier extends StateNotifier<ProState> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Ref _ref;

  ProNotifier(this._ref) : super(const ProState());

  String? get _userId => _supabase.auth.currentUser?.id;

  // ── Status check ──────────────────────────────────────────────────────────

  Future<void> checkProStatus() async {
    final userId = _userId;
    if (userId == null) return;

    state = state.copyWith(isProStatusLoading: true);
    try {
      final row = await _supabase
          .from('user_profiles')
          .select('subscription_tier, pro_expires_at')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) {
        state = state.copyWith(isProStatusLoading: false);
        return;
      }

      final expiresAt = row['pro_expires_at'] == null
          ? null
          : DateTime.parse(row['pro_expires_at'] as String);

      state = state.copyWith(
        subscriptionTier:   (row['subscription_tier'] as String?) ?? 'free',
        proExpiresAt:       expiresAt,
        isProStatusLoading: false,
      );
    } catch (e) {
      debugPrint('[Pro] checkProStatus error: $e');
      state = state.copyWith(isProStatusLoading: false);
    }
  }

  // ── Step 1: Create Razorpay order ─────────────────────────────────────────

  /// Call this when the user taps "Subscribe". Returns the order details so
  /// the caller can open the Razorpay checkout sheet.
  /// Returns null on failure (check state.purchaseError).
  Future<RazorpayOrderDetails?> createOrder(ProPlan plan) async {
    final userId = _userId;
    if (userId == null) {
      state = state.copyWith(purchaseError: 'Not authenticated');
      return null;
    }

    state = state.copyWith(
      purchaseStep:       ProPurchaseStep.creatingOrder,
      clearPurchaseError: true,
      purchaseSuccess:    false,
    );

    try {
      final response = await _supabase.functions.invoke(
        'create-razorpay-order',
        body: {
          'userId': userId,
          'plan':   plan.id,
        },
      );

      if (response.data == null) {
        throw Exception('Empty response from create-razorpay-order');
      }

      final data = response.data as Map<String, dynamic>;
      if (data['error'] != null) throw Exception(data['error']);

      final order = RazorpayOrderDetails.fromMap(data);
      state = state.copyWith(
        purchaseStep: ProPurchaseStep.awaitingPayment,
        pendingOrder: order,
      );
      return order;
    } catch (e) {
      debugPrint('[Pro] createOrder error: $e');
      state = state.copyWith(
        purchaseStep:  ProPurchaseStep.idle,
        purchaseError: 'Failed to create payment order. Please try again.',
      );
      return null;
    }
  }

  // ── Step 2: Verify payment + activate Pro ─────────────────────────────────

  /// Call this from the Razorpay `onSuccess` callback.
  /// [paymentId], [orderId], [signature] come from the Razorpay SDK.
  Future<bool> verifyAndActivate({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    final userId = _userId;
    if (userId == null) return false;

    state = state.copyWith(purchaseStep: ProPurchaseStep.verifying);

    try {
      final response = await _supabase.functions.invoke(
        'verify-razorpay-payment',
        body: {
          'userId':    userId,
          'orderId':   orderId,
          'paymentId': paymentId,
          'signature': signature,
        },
      );

      if (response.data == null) {
        throw Exception('Empty response from verify-razorpay-payment');
      }

      final data = response.data as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Payment verification failed');
      }

      final expiresAt = data['expiresAt'] == null
          ? null
          : DateTime.parse(data['expiresAt'] as String);

      state = state.copyWith(
        purchaseStep:     ProPurchaseStep.done,
        subscriptionTier: 'pro',
        proExpiresAt:     expiresAt,
        purchaseSuccess:  true,
      );

      // Invalidate the userProfileProvider cache so any widget watching
      // UserProfile.isPro gets the updated value immediately.
      if (userId != null) {
        _ref.invalidate(userProfileProvider(userId));
      }

      return true;
    } catch (e) {
      debugPrint('[Pro] verifyAndActivate error: $e');
      state = state.copyWith(
        purchaseStep:  ProPurchaseStep.idle,
        purchaseError: 'Payment verification failed. Contact support if amount was deducted.',
      );
      return false;
    }
  }

  // ── Payment cancelled / failed callbacks ──────────────────────────────────

  void onPaymentCancelled() {
    state = state.copyWith(
      purchaseStep:  ProPurchaseStep.idle,
      pendingOrder:  null,
      purchaseError: 'Payment was cancelled.',
    );
  }

  void onPaymentError(String description) {
    state = state.copyWith(
      purchaseStep:  ProPurchaseStep.idle,
      pendingOrder:  null,
      purchaseError: description,
    );
  }

  void clearPurchaseError() => state = state.copyWith(clearPurchaseError: true);
  void resetPurchaseFlow()  => state = state.copyWith(
    purchaseStep:       ProPurchaseStep.idle,
    pendingOrder:       null,
    purchaseSuccess:    false,
    clearPurchaseError: true,
  );
}

// ── Providers ─────────────────────────────────────────────────────────────────

final proProvider = StateNotifierProvider<ProNotifier, ProState>((ref) {
  final notifier = ProNotifier(ref);
  // Auto-check status when auth user is present
  final session = ref.watch(authStateProvider).valueOrNull;
  if (session?.user != null) notifier.checkProStatus();
  return notifier;
});

/// Convenience: reactive isPro bool for gating UI elements.
final isProProvider = Provider<bool>((ref) => ref.watch(proProvider).isPro);
