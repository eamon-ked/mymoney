# The app's screens

The interface lives in `PersonalFinanceApp/Redesign/`. It's the "Build missing
app screens" design from Figma, built in SwiftUI on the real store.
[FEATURES.md](FEATURES.md) lists every feature and where it lives.

The screens can be redrawn without touching what's below them.

## Keep, don't rewrite

| Layer | Where | What it does |
|---|---|---|
| Core | `Packages/NokaelCore` | Money, ledger, budget, bills, safe to spend, debts, forecast, CSV reading, capture parsing. Pure Swift, `swift test`. |
| Store | `Store/LedgerStore.swift` | The only code that changes data. Every save goes through it. |
| Snapshot | `Store/FinanceSnapshot.swift` | Everything a screen reads, cached per change. |
| Logic | `Logic/` | What screens need that isn't drawing: entry forms, Home's to-do list, statement review, the guide, reminders, text for amounts. |
| App | `App/NokaelMoneyApp.swift`, `App/AppDuties.swift` | Database, widget refresh, bill reminders, schedules. Attached above the root view, so screens can't drop them. |
| Outside the app | `Intents/`, `NokaelWidget/`, `Store/CaptureService.swift`, `Store/Payday.swift` | Siri, Shortcuts, widget, Apple Pay and SMS capture. None of it uses views. |

## How the screens are put together

| File | What's in it |
|---|---|
| `RedesignModel.swift` | `Redesign.AppModel`: navigation (tab, sheet, pages, toast), Privacy Mode, and the display types (`Account`, `Transaction`, `Bill`, `Category`) built from `store.snapshot`. Every change goes through `attempt(_:closing:undo:_:)`, which shows the toast and keeps Undo. |
| `RedesignRoot.swift` | `AppRoot`: onboarding until `settings.onboardingDone`, the lock while `settings.biometricLock` is on, then the shell. It handles `AppRouter.pending` (a bill reminder opens Bills) and shows the welcome tour once. |
| `RedesignKit.swift` | Colours (light and dark), the type roles, and the building blocks. |
| `RedesignTabs.swift` | Home, Accounts, Budget, Bills, and the rows they share. Activity is a page, not a tab. |
| `RedesignSheets.swift` | The sheet router, the form parts (`AmountBox`, `Field`, `Choice`, `AccountChoice`, `CategoryChoice`, `ToggleRow`), the safe-to-spend breakdown and "What happened?". |
| `RedesignEntry.swift` | Add and edit entries (one form, through `EntryForm`) and the transaction page. |
| `RedesignAccounts.swift` | Account pages, cards and loans, paying debts, terms, reconcile, type, starting amount, lending. |
| `RedesignBills.swift` | Bill pages, linking payments, the bill form and schedules. |
| `RedesignBudget.swift` | Category pages, the category form, moving money, goals and set-asides. |
| `RedesignMore.swift` | More and its pages: profile, settings, reminders, privacy, backup and data, history, categories, Plus and the paywall. |
| `RedesignInsights.swift` | Intelligence, Ask, Reports, Money ahead and Help. |
| `RedesignSetup.swift` | Onboarding, the lock screen and the welcome tour. |
| `RedesignFlows.swift` | Payday, statement import, Siri and automatic capture, and the debug launch options. |

## Rules every screen follows

- **Read** from `app.snapshot` or the model's lists. **Write** through a `LedgerStore` method inside `app.attempt`, or `app.save(form)` for entries.
- **Every figure and name goes through the model**: `app.money`, `amount`, `number`, `percent`, `accountLabel` and `name(of:)`. One Privacy Mode switch then covers every screen. Standard hides amounts. Enhanced can also hide transaction details, account names and charts.
- **Type goes through `rdText(_:)`** and `Redesign.TextRole`. There's one role per kind of information, and each scales with Dynamic Type. Use a role rather than `.font(...)`.
- **The floating + changes with the screen** (`app.createAction`):
  - Home fans out Expense, Income, Transfer and More… ("What happened?").
  - Accounts, Budget and Bills put their own item on top (an account, a category, a bill or expected income), above the same Expense, Income and Transfer.
  - It's hidden on More and on pages with nothing to create.
- **The tab bar and + float over the screen.** Every scroll area reserves `app.barHeight` at its end (`safeAreaPadding`), so the last row always scrolls clear of them.
- **The currency comes from `store.currency`.** Don't assume AED, English or the Gulf in labels or examples.

Privacy Mode and appearance belong to the phone, not the data. They're kept in UserDefaults (`redesignPrivacy`, `appearance`), read before the first frame, and left out of backups. The profile name is `SettingsRecord.displayName`, and backups include it.

## Change along with the screens

- **`Logic/AppGuide.swift`**: the Help guide's steps name buttons and tabs, and the on-device AI repeats them to people. Rewrite the steps whenever a label or place changes.
- **UI tests** (`PersonalFinanceAppUITests`): they find elements by `accessibilityIdentifier`, so keep the identifiers or update the tests.
  - The target isn't in the shared scheme. Run it from a scheme that tests `PersonalFinanceAppUITests`.
- **Debug launch arguments** (`Redesign.DebugScreens` in `RedesignFlows.swift`), used for screenshots and the iPhone tour:
  - `-tab budget|accounts|bills|more|activity|reports`
  - `-screen payday|choose|guide|capture|settings|add|ask|debtpay|loan|paywall|import|forecast|reports`
  - `-demoData` and `-uiTesting` start on an in-memory store; `-plus` and `-noPlus` set Plus.
- **App Store screenshots** in `AppStore/screenshots`, and the paywall's review screenshots, need retaking for the new design.
