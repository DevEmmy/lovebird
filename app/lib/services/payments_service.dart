/// Phase 5 boundary (brief §43). The MVP is free; nothing here charges money.
///
/// When payments are added:
///  * Implement this interface with Paystack (NGN & African markets) and Stripe (elsewhere).
///  * Never trust the client: a provider webhook → edge function verifies the event,
///    then flips `competition_entries.payment_status` / inserts `entitlements` with the
///    service role. The app only *reads* entitlements.
///  * Votes are never purchasable — there is deliberately no API for it.
abstract class PaymentsService {
  Future<PaymentResult> payCompetitionEntry({required String entryId, required String currency, required int amountMinor});
  Future<PaymentResult> subscribe({required String planId});
}

enum PaymentStatus { succeeded, cancelled, failed, notAvailable }

class PaymentResult {
  const PaymentResult(this.status, {this.message});
  final PaymentStatus status;
  final String? message;
}

class PaymentsNotConfigured implements PaymentsService {
  const PaymentsNotConfigured();
  static const _msg = 'Payments aren\'t available yet. Your entry is saved — we\'ll let you know when you can complete it.';
  @override
  Future<PaymentResult> payCompetitionEntry({required String entryId, required String currency, required int amountMinor}) async =>
      const PaymentResult(PaymentStatus.notAvailable, message: _msg);
  @override
  Future<PaymentResult> subscribe({required String planId}) async => const PaymentResult(PaymentStatus.notAvailable, message: _msg);
}

const PaymentsService payments = PaymentsNotConfigured();
