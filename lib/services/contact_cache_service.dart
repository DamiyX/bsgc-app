/// Compatibility adapter for older UI call sites.
///
/// Braid no longer reads a member's address book or matches phone-number
/// suffixes. Names come from the authenticated public profile contract.
class ContactCacheService {
  static final ContactCacheService _instance = ContactCacheService._internal();

  factory ContactCacheService() => _instance;

  ContactCacheService._internal();

  Future<void> loadCache() async {}

  @Deprecated('Contact discovery was removed. Use server-authorized invites.')
  Future<void> syncContactsInBackground() async {}

  String getContactName(String uid, String publicProfileName) {
    final normalized = publicProfileName.trim();
    return normalized.isEmpty ? 'Believer' : normalized;
  }
}
