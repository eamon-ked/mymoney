# Redesigning the UI

The screens in `PersonalFinanceApp/Features/` and `Design/` can be thrown away
and rebuilt. Everything below them stays, and new screens call it.

## Keep, don't rewrite

| Layer | Where | What it does |
|---|---|---|
| Core | `Packages/NokaelCore` | Money, ledger, budget, bills, safe to spend, debts, forecast, CSV reading, capture parsing. Pure Swift, `swift test`. |
| Store | `Store/LedgerStore.swift` | The only code that changes data. Every save goes through it. |
| Snapshot | `Store/FinanceSnapshot.swift` | Everything a screen reads, cached per change. |
| Logic | `Logic/` | What screens need that isn't drawing: see below. |
| App | `App/NokaelMoneyApp.swift`, `App/AppDuties.swift` | Database, widget refresh, bill reminders, schedules. Attached above the root view, so screens can't drop them. |
| Outside the app | `Intents/`, `NokaelWidget/`, `Store/CaptureService.swift`, `Store/Payday.swift` | Siri, Shortcuts, widget, Apple Pay and SMS capture. None of it uses views. |

## What a new screen calls

| To | Call |
|---|---|
| Add or edit an expense, income, transfer or balance correction | Fill an `EntryForm`, then `store.save(form, replacing: editing?.id)`. `EntryForm.AmountProblem` is the error to show beside the amount; anything else is a `StoreError`. |
| Add an account, card or loan | `store.addAccount(name:kind:balance:…)`, with the balance as typed (what's owed is positive). |
| Add or edit a category | `store.saveCategory(editing, name:isIncome:group:policy:reserve:icon:colorHex:)` |
| Set up pay | `store.setUpSalary(_:every:nextPayday:)` |
| Budget | `store.setAllocation`, `moveAllocation`, `copyPlan`. Groups come from `snapshot.expenseCategoryGroups`. |
| Import a statement | Make one `StatementReview(accountId:store:)`, show its `rows`, `inbox`, `options(for:)` and `label(for:)`, then call `add()`. |
| Home's to-do list | `HomeTask.all(snapshot)` |
| "This month so far" | `MonthSoFar(snapshot).sentence` |
| Bills, debts, goals, lending, reconcile, Payday | The `LedgerStore` methods under each `// MARK:` |

## The root view must

- Handle every `AppRoute` in `AppRouter.shared.pending`, then set it to `nil`. Tapping a bill reminder opens `.bills`.
- Show onboarding until `store.settings.onboardingDone`, and the lock screen while `settings.biometricLock` is on.
- Provide the `addEntry`, `chooseAdd` and `selectTab` environment actions, or replace their callers.

## Change along with the screens

- **`Logic/AppGuide.swift`**: the Help guide's steps name buttons and tabs, and the on-device AI repeats them to people. Rewrite the steps whenever a label or place changes.
- **UI tests** (`PersonalFinanceAppUITests`): they find elements by `accessibilityIdentifier`. Keep the identifiers, or update the tests. The UI test target isn't in the scheme, so nothing fails on its own.
- **Debug launch arguments** in `RootView`: `-tab` and `-screen …`, used for screenshots and the iPhone tour (which taps `askSend`).
- **App Store screenshots** in `AppStore/screenshots`, and the paywall's review screenshots.
