# Nokael Money features and their place in the new design

Every feature the app had before the redesign, and where it lives now. The
new design (`PersonalFinanceApp/Redesign/`) is kept as drawn; a feature it
had no screen for is placed inside an existing screen or pattern rather than
adding new navigation.

Status:
- **In design**: the new design already had a place for it; it's now wired to real data.
- **Added**: the design had no place for it, so it was put where the "New home" column says, in the design's own style.
- **Changed**: it works differently now; the reason is given.

## App shell

| Feature | Was | New home | Status |
|---|---|---|---|
| Tabs | Home, Budget, Activity, Accounts, Reports | Home, Accounts, Budget, Bills, More. Activity and Reports are pages in More (Activity is also Home's "See all") | Changed: the design's tabs |
| Add anything (+) | Toolbar + opened "What happened?" | Floating +, which changes with the tab. On Home it fans out to Expense, Income, Transfer and **More…** ("What happened?") | In design + Added (More…) |
| "What happened?" chooser | `AddChooser` | The + fan's More… and Help. Choices: salary, spent, received, paid a bill, paid a loan or card, moved money, have a loan or card, a balance is wrong, ask the guide | Added |
| Onboarding (currency, starter categories, first accounts, pay, bills and savings, essentials budget, restore) | `OnboardingView` | Full-screen flow in the design's style, with the same six steps | Added |
| Face ID lock | `RootView` LockView | Lock screen in the design's style (the Privacy cover look). Turned on in More › Privacy & Security | Added |
| Welcome tour | `WelcomeTour` | Same sheet in the design's style, describing the new places | Added |
| Bill reminder taps open Bills | `AppRouter` `.bills` | Bills tab | In design |
| Undo after saving | none | Toast Undo deletes what was just added | In design |
| Privacy Mode | none | Eye on Home; More › Privacy & Security › Privacy Mode | In design |

## Home

| Feature | Was | New home | Status |
|---|---|---|---|
| Safe to spend | Banner, then `SafeToSpendView` | Hero card, then the Breakdown sheet | In design |
| Period: until payday, 7 days, month end, a date | `SafeToSpendView` | Pills at the top of the Breakdown sheet | Added |
| Breakdown: spendable accounts, bills, protected savings, essentials, total | `SafeToSpendView` | Breakdown sheet | In design + Added (savings, essentials) |
| Safety buffer | `SafeToSpendView` | Breakdown sheet, under the total | Added |
| If income arrives (projection) | `SafeToSpendView` | Breakdown sheet, last section | Added |
| Status: estimates, out-of-date balances, shortfall | `SafeToSpendView` | One line under the Breakdown total | Added |
| Set money aside | `ReserveEditor` from Safe to spend | Breakdown sheet's "Set money aside", and Budget › Savings | Added |
| To-do list (overdue bills, bill links, payday, overspending, no budget, unplanned money, review, stale account, backup) | Home "To do" | "Needs you" under the shortfall line (top 3, then "Show more"), only when there's something to do | Added |
| This month so far | Home card | First line of the Intelligence summary | Added |
| Pinned categories | Home | "Watching" on Home, only when something is pinned. Pin from the category page | Added |
| Coming up (bills in 14 days) | Home | Upcoming Bills | In design |
| Credit card summary | none | Your Credit Card, only when a card exists | In design |
| Accounts, recent activity | Accounts tab, Activity tab | Your Accounts, Recent Activity | In design |
| Ask (Apple Intelligence) | Home toolbar | Intelligence button in Home's header | In design + Added (chat) |
| Help | Settings toolbar, chooser | Help button in Home's header and More › Help & Support | In design |

## Accounts

| Feature | Was | New home | Status |
|---|---|---|---|
| Groups by kind | Accounts tab | "Your money" (cash, bank, savings, investment, other), "What you owe" (cards, loans), "People" (friends and family, either way) | In design + Added (People) |
| Net worth | Accounts banner | Total Cash card's breakdown: owned, owed, net worth | Added |
| Add account (bank, cash, savings, investment, lent, other) | `NewAccountSheet` | + on Accounts: the Add Account form, with every kind | In design |
| Add loan or credit card (lender, owed, payment, due day, paid from, rate, category) | `NewLoanSheet` | Add Account form: choosing Loan or Credit card shows those fields | Added |
| Archived accounts | Accounts | "Archived" row at the end of Accounts | Added |
| Account page: balance, transactions with running balance | `AccountDetailView` | Account page, Transactions tab (balance after each entry) | In design + Added (running balance) |
| Reconcile against a statement | `ReconcileSheet` | Account page › More › Check against a statement | Added |
| Import a statement (CSV; first per account free, more with Plus) | `ImportStatementView` | Account page › More › Import a statement; More › Import a statement | Added |
| Change account type, moving entries | `ChangeAccountTypeSheet` | Account page › More › Change type | Added |
| Fix starting amount | `StartingAmountSheet` | Account page › More › Fix starting amount | Added |
| Rename; counts in net worth; money I can spend; part of my budget | `AccountSettingsSection` | Account page, Details tab | Added |
| Archive and restore | `AccountSettingsSection` | Account page › More | Added |
| Card or loan terms (rate, payment, due day, paid from, category) | `DebtTermsEditor` | Card and loan pages: "Terms" › Edit | Added |
| Payoff (debt-free date, payments left, interest) | `PayoffSummary` | Card and loan pages | Added |
| Pay extra planner (Plus) | `PayoffComparison` | Card and loan pages, under Payoff | Added |
| Pay a card or loan, split into principal, interest and fees | `PayDebtSheet` | Card page "Make a Repayment" and loan page "Make a payment" | In design + Added (split) |
| Money with a person, both ways: lend, paid back, forgive; borrow, pay back | `LentSection` | A person's page, its actions following who owes whom; What happened? › I lent someone money / Someone lent me money / Someone paid me back; + on Accounts › Lend Money | Added |
| Lend from a credit card | — | Lend form › From lists cards | Added |
| Split a bill with friends | — | Expense form › Split with others (Split evenly, new names allowed); only your share is spending | Added |
| A bill a friend paid for you | — | Expense form › Paid from › the person; your spending, and you owe them | Added |
| Pay-back-by date and reminders | — | Lend form and person details; Needs you on Home when the date passes, or after 30 quiet days of being owed | Added |

## Budget

| Feature | Was | New home | Status |
|---|---|---|---|
| Month switcher | Toolbar arrows | "This month ▾" menu at the top of Budget | In design |
| Totals ring: budget, spent, remaining | none | Ring card | In design |
| Not planned yet | Budget summary | Footnote under the category list ("Unallocated") | In design |
| Filter: over, no budget, money left | Toolbar menu | Pills above the category list | Added |
| Needs attention (overspent, spending with no budget) | Budget | One line above the list, opening the category | Added |
| First job ("Set budgets for your main costs") | Budget | Same line, when nothing is planned | Added |
| Starter categories | Budget empty state | Empty state | Added |
| Copy last month's plan | Budget | Button under the ring when this month is empty | Added |
| Categories by group | Budget | Spending by Category, grouped | In design |
| Category page: budget this month, spent, left, bills | `CategoryDetailView` | Category page Overview | In design |
| Carried in, overspent last month, added for bills | `CategoryDetailView` | Category page Overview | Added |
| What went in (breakdown, loans) | `CategoryDetailView` | Category page Overview | Added |
| Move money from another category | `MoveMoneySheet` | Category page: "Move money" | Added |
| Category settings (name, group, rollover, keep out of safe to spend, icon, colour, archive) | `CategoryEditor` | Category page: "Edit category"; + on Budget for new ones | In design + Added |
| Loans in a category | `LoansInCategoryView` | Category page | Added |
| Pin to Home | Category toolbar | Category page | Added |
| Savings goals (3 free, more with Plus) | Budget › Savings | Budget › Savings section; goal page | Added |
| Money set aside | Budget › Savings | Budget › Savings section | Added |
| Goal: add money, take out, edit, monthly advice | `GoalDetailView`, `GoalMoneySheet` | Goal page | Added |

## Bills

| Feature | Was | New home | Status |
|---|---|---|---|
| Bills list and status | `BillsView` (from Home) | Bills tab with Upcoming, Paid, All and Overdue | In design |
| Expected income | `BillsView` | Bills tab: "Expected income" section; + offers "Expected income" | Added |
| Add or edit a bill (amount, estimate, next due, frequency, end, reminder, account, category) | `PlannedItemEditor` | Add Bill form (+ on Bills), also used to edit | In design + Added (fields) |
| Record a payment (amount, part payment, account, category, date) | `PayOccurrenceSheet` | Bill page: Record Payment | In design + Added (part payment, choices) |
| Link a payment already in Activity | `PayOccurrenceSheet` | Bill page › Link an existing payment | In design |
| Unlink | `PayOccurrenceSheet` | Bill page, under the linked payment | Added |
| Skip this one / undo skip | `PayOccurrenceSheet` | Bill page | Added |
| Change when it's due, stop this bill | `PayOccurrenceSheet`, editor | Bill page › Edit bill | Added |
| Reminders before bills are due, with an hour | Settings › Bill reminders | More › Settings › Bill reminders; Bill page › Set Reminder | In design (now real) |
| Loan bills | `PayScheduledSheet` | A bill for a loan opens the payment form with the split | Added |
| Money ahead (30/60/90 day forecast, Plus) | `ForecastView` | More › Money ahead | Added |

## Activity and entries

| Feature | Was | New home | Status |
|---|---|---|---|
| Search; filter by type | Activity tab | Activity page | In design |
| Filter: to review, scheduled | Activity | Pills on the Activity page | Added |
| Date and account filters | none | Activity page filters | In design |
| Deleted entries | Activity | Shown struck through | Added |
| Add expense, income, transfer | `EntryEditor` | Add forms from the + | In design |
| Category grid, all categories | `EntryEditor` | Category picker in the form (most used first) | In design |
| Describe it (Apple Intelligence; 10 a month free, unlimited with Plus) | `EntryEditor` | Add form: "Describe it" line | Added |
| Category from history and AI suggestion | `EntryEditor` | Add form (suggested category is picked for you) | Added |
| This pays a bill | `EntryEditor` | Add form toggle | Added |
| Repeats | `EntryEditor` | Add form toggle | Added |
| Fix a balance (adjustment with reason) | `EntryEditor` adjustment | "What happened?" › A balance is wrong | Added |
| Entry detail: what moved, source, badges | `EntryDetailView` | Transaction page | In design |
| Edit (amount, date, account, category, note) | `EntryEditor` | Transaction page › Edit: the add form, filled in | Changed: the design's edit form only changed the name, category and note |
| Delete | `EntryDetailView` | Transaction page › Delete | Added |
| Debt payment parts | `EntryDetailView` | Transaction page | Added |
| Review a captured entry; always use an account for a card | `EntryDetailView` | Transaction page | Added |
| It was a loan or card payment | `EntryDetailView` | Transaction page › More | Added |
| I lent this / it came from a person / split it with others | `EntryDetailView` | Transaction page › It was something else | Added |
| Change history for an entry | `EntryDetailView` | Transaction page | Added |
| Payday (salary, budget copy, goals) | `PaydaySheet` | "What happened?" › I got my salary; Needs you on payday; Help | Added |

## Reports, AI and help

| Feature | Was | New home | Status |
|---|---|---|---|
| Reports: spent, in and out, where it went, all categories | `ReportsView` tab | More › Reports | Added (the design's page was a placeholder) |
| Reports: last 3 months free; 6-month trend and every month with Plus | `ReportsView` | More › Reports | Added |
| Month story (Apple Intelligence) | `ReportsView` | More › Reports | Added |
| Ask about your money (chat) | `AskMoneyView` | Intelligence: "Ask" box | Added |
| Guide: search, topics, salary and draft cards, AI answer | `GuideView` | Help page | Added (the design had FAQs only) |

## Settings and data

| Feature | Was | New home | Status |
|---|---|---|---|
| Profile name | none | More › My Profile (stored, shown on Home) | In design |
| Appearance | System only | More › Settings › Appearance | In design |
| Currency (read-only), week starts on | Settings › Currency & categories | More › Settings | In design + Added |
| Categories list (spending, income, archived) | Settings | More › Settings › Categories | Added |
| Apple Intelligence on/off, cloud model | Settings | More › Settings › Apple Intelligence | Added |
| Siri, Apple Pay and bank SMS capture setup | `CaptureSetupView` | More › Siri & automatic capture | Added |
| Backup, restore | Settings | More › Backup & your data | Added |
| Export entries as CSV (free) | Settings › Your data | More › Backup & your data | Added |
| Change history | Settings › Your data | More › Backup & your data | Added |
| Delete all data | Settings › Your data | More › Backup & your data | Added |
| Nokael Plus: plans, buy, restore, manage | Settings, paywall | More › Nokael Plus; paywall in the design's style | Added |

## Not drawn on any screen (unchanged)

Siri and Shortcuts intents, Apple Pay and SMS capture, the widget, bill
reminder notifications, schedules extended on launch, the backup reminder.

## How it was checked

- The app builds, and the 118 unit tests pass.
- `PersonalFinanceAppUITests` drives these through the real interface, and all 10 pass:
  - setup on an empty store, then a first budget;
  - adding an expense once;
  - a transfer;
  - paying a bill;
  - a car loan payment with the interest split off;
  - adding money to a goal;
  - payday;
  - "What happened?";
  - every page in More;
  - the paywall without Plus.
- Payday, statement import, capture, the safe-to-spend breakdown, Budget, Accounts, Bills, Reports and Help were looked at in the simulator on the demo household.
- Not checked by hand yet:
  - the Face ID lock on a device;
  - a statement import from a real CSV;
  - dark mode and the largest text size on every new screen;
  - an App Store screenshot pass.

## Free and Plus

Free covers everything needed to keep an accurate picture and make everyday decisions; Plus saves work and looks further ahead. The limits live in `FreePlan` (`Store/PlusStore.swift`); monthly AI uses are counted in `Logic/FreeAllowance.swift`.

| Feature | Free | Plus |
|---|---|---|
| Accounts, transactions, budgets, bills, debts, safe to spend, Siri | Everything | Everything |
| Statement import | First import for each account | Unlimited |
| Ask about your money | 3 questions a month | Unlimited, cloud model where available |
| Describe it in a sentence | 10 a month | Unlimited |
| Reports | Last 3 months | Every month, 6-month trend, month story |
| Savings goals | 3 (set-asides unlimited) | Unlimited |
| Export, backup, restore, Privacy Mode, Face ID | Everything | Everything |
| Automatic capture (Apple Pay, SMS) | — | Yes |
| 60-day forecast, debt payoff simulations | — | Yes |
| Home screen widget | — (basic free widget planned) | Yes |
