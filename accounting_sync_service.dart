/// Abstraction over the accounting API sync channel. Isolated behind an
/// interface (same pattern as LocationResolutionService) so a real
/// QuickBooks Online OAuth implementation can be dropped in without
/// touching the repository or UI. No live implementation ships here —
/// this environment has no OAuth credentials or network access to build
/// and test against a real QuickBooks sandbox.
abstract class AccountingSyncService {
  /// Pushes a single transaction and returns the external transaction ID
  /// QuickBooks assigns, or null on failure.
  Future<String?> pushTransaction({
    required double amount,
    required DateTime transactionDate,
    required String? category,
    required String sourceDescription,
  });

  /// Whether the service currently has a valid, connected session.
  Future<bool> isConnected();
}

/// Placeholder implementation — throws until real QuickBooks Online OAuth
/// (authorization code flow, token refresh, Journal Entry or Purchase API
/// calls) is built. Kept explicit rather than silently no-op-ing so it's
/// obvious this isn't wired up yet.
class QuickBooksOnlineSyncService implements AccountingSyncService {
  QuickBooksOnlineSyncService();

  @override
  Future<bool> isConnected() async => false;

  @override
  Future<String?> pushTransaction({
    required double amount,
    required DateTime transactionDate,
    required String? category,
    required String sourceDescription,
  }) async {
    throw UnimplementedError(
      'QuickBooks Online OAuth flow is not implemented in this scaffold. '
      'Needs: authorization code exchange, token storage (encrypted, same '
      'pattern as accounting_integrations.credentialsRef), token refresh, '
      'and the actual Purchase/JournalEntry API call.',
    );
  }
}
