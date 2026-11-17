# TestFlight — Nokael Money 2.1.4

## What to Test (paste into App Store Connect › TestFlight › Test Details, 4,000 max)

```
Thanks for testing Nokael Money. Please try these, with your own bank if you can:

• Account numbers (optional). In an account's details, type its number, or just the digits your bank's messages show. Leaving it empty is fine. If two of your accounts end the same way, the app tells you and shows enough digits to tell them apart.
• "Which account is this?" When a bank message names an account the app doesn't know, tap the right account (or "Add an account…") on the entry. Later messages for that number go there by themselves.
• Moving money between your own accounts. When a money-out message and a money-in message match, they should become one transfer, not two entries.
• Importing a statement (CSV or PDF). After import, check "Not on this statement" (entries the statement doesn't have, with Keep or Delete) and "Not on the statement yet" (card payments the bank hasn't posted).
• The balance check after import. Do the numbers make sense? Is it clear whether a correction adds money or takes it off?
• The home screen widget.

Tell us anything that's confusing, especially amounts or account numbers that don't look right. Use Send Beta Feedback (take a screenshot in the app). Screenshots are sent to the developer, so hide amounts first with Privacy Mode if you prefer.
```

## Before uploading

- [ ] All tests pass (core, app, screen tests)
- [ ] Version 2.1.4; the build number is set by Xcode on upload (ExportOptions.plist: manageAppVersionAndBuildNumber)
- [ ] Encryption: ITSAppUsesNonExemptEncryption = NO (already set, so no export question)
- [ ] Privacy policy mentions on-phone crash reports (legal-docs/privacy-policy.html, 16 Nov 2026), and is published
- [ ] Archive: Product › Archive in Xcode, or `xcodebuild archive`, then Distribute App › TestFlight & App Store
