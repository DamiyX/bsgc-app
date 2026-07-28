# Braid release checklist

## Required gates

- [ ] Flutter format, analyze, and tests pass on a clean clone.
- [ ] Functions syntax/unit tests pass.
- [ ] Firestore and Storage Emulator tests pass.
- [ ] Signed release AAB builds with R8/resource shrinking.
- [ ] `--analyze-size` report reviewed; Play device-specific download recorded.
- [ ] Production signing secrets are outside Git; debug signing absent.
- [ ] `assetlinks.json` has the release certificate SHA-256 and verifies.
- [ ] Apple association file has the real Team ID before iOS claims support.
- [ ] Canonical `/join/{token}` tested through install/sign-in/onboarding.
- [ ] Production backend exported; migration dry-run reviewed; rollback owner named.
- [ ] Rules, indexes, Functions, Storage rules, and App Check state recorded.
- [ ] Airplane cold/warm tests pass for avatar, cover, Bible, cached messages, draft, text queue, media retry, and sign-out cache separation.
- [ ] TalkBack core-flow test and 200% text/contrast pass.
- [ ] Account deletion, report, block, invite revoke, capacity, owner transfer, and lifecycle tested.
- [ ] Unsupported backup/video/document/phone discovery features remain hidden.
- [ ] Verified operator contact, privacy notice, terms, retention, data-safety, UGC moderation, and deletion declarations are live.

## Distribution

Use Play internal testing first, then closed testing. Do not serve repository APKs from the invite website. Promote only the exact reviewed AAB and retain its commit, version, mapping/symbol files, test evidence, and signer fingerprint.
