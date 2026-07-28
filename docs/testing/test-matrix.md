# Test matrix

## Automated

| Layer | Required checks |
| --- | --- |
| Dart | format, analyze, model/service unit tests, widget tests |
| Functions | syntax, callable contracts, invite entropy/hash, migration, notification preview/token cleanup |
| Firestore rules | public/private boundaries, group query/membership, progress isolation, lifecycle posting, message fields/space, contacts Insights, comments/reactions, reports, devices, notes |
| Storage rules | profile owner/type/size, cover owner/member read, message member/type/metadata/size, nonmember denial |
| Android | release AAB, R8/resource shrink, size analysis |

## Manual device scenarios

Run on a low-memory Android device and a current Android device:

- fresh sign-in and onboarding;
- installed/not-installed invite continuation;
- expired/revoked/full/already-member/blocked invite;
- scheduled → active → completed → archived group;
- owner transfer, member removal, owner/member leave;
- Plan progress, Reflection, Discussion, Prayer;
- offline text send, process death, reconnect, duplicate prevention;
- offline image/voice outbox retry and discard;
- cold/warm airplane avatar, cover, Bible, cached messages;
- foreground/background/terminated notification routing;
- lock-screen preview off/on, device category off, group mute;
- sign-out and second-account cache isolation;
- report, block, unblock, hide, delete;
- account deletion with and without owned shared group.

## Accessibility

Complete core flows with TalkBack; test 200% font scale, large display size, dark/light contrast, switch access/keyboard focus, reduced motion, RTL pseudo-locale, and status announcements. No essential control may be icon-only without a tooltip/semantic label.

## Scale/load evidence

Record Firestore reads/writes for a 12-member group with 1,000 messages, 500 accepted connections, 20 active Insights per contact, ten devices per account, and concurrent invite redemption. Alert on Function errors, rule denials, invalid-token rate, notification failures, invite failures, and migration exceptions without logging private content.
