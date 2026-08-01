/// Product copy for destructive actions whose backend lifecycle is not
/// necessarily an immediate physical erase.
///
/// Keep the distinction visible in the UI: hiding/removing content from an
/// audience is different from deleting a user's local bookmark, and a
/// server-side tombstone can remain for synchronization or safety records.
const insightDeletionDialogTitle = 'Remove reflection?';

const insightDeletionDialogBody =
    'This stops sharing the reflection. Braid keeps a deletion status for '
    'synchronization and safety records; final physical deletion follows the '
    'retention policy. Saved bookmarks to this reflection will no longer be '
    'available.';

const insightDeletionActionLabel = 'Remove';
const insightDeletionSuccessMessage = 'Reflection no longer shared.';

const accountDeletionDialogBody =
    'This starts a durable deletion process for your profile, private notes, '
    'saved items, reflections, and account media. Your account is disabled '
    'first. Shared messages may remain as a deleted-account tombstone, and '
    'safety records may be retained; final physical deletion follows the '
    'applicable retention policy. The request cannot be undone after '
    'processing begins.\n\n'
    'You must transfer ownership of shared studies first.';

const accountDeletionSubtitle =
    'Starts irreversible cleanup; some safety records may remain';

const savedInsightRemovalLabel = 'Remove bookmark';

const messageRemovedForEveryoneLabel =
    'Message removed for everyone. Some safety metadata may be retained.';
