//
//  AppGuide.swift
//  Nokael Money
//
//  The Help guide's topics, kept apart from the screen that shows them. The
//  on-device model reads them too (FinanceDigest, MoneyAI) and repeats their
//  button names to people, so the steps must match the screens: when a
//  button, tab or screen is renamed or moved, change its steps here as well.
//

import Foundation

/// Something the guide can open for the person
enum GuideAction: Hashable {
    case add(AddKind)
    case importStatement
    case capture
    case tab(AppTab)
    case backup
    case payDebt
    case addLoan
    case bills
    case notifications
}

struct GuideTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let steps: [String]
    let tip: String?
    let action: GuideAction?
    let actionTitle: String?
    let keywords: [String]
}

enum AppGuide {
    static let topics: [GuideTopic] = [
        GuideTopic(id: "income", title: "Add your salary or other income", symbol: "arrow.down.circle.fill",
                   steps: ["On Home, tap + at the bottom right and choose Add Income. For your salary, choose More…, then “I got my salary”.",
                           "Enter the amount, choose the kind of income (for example Salary) and the account it was paid into.",
                           "Tap Save. Your balance and safe to spend update straight away."],
                   tip: "Paid every month? Turn on Repeats, so next month's salary shows in the Bills tab under Expected income.",
                   action: .add(.income), actionTitle: "Add income now",
                   keywords: ["salary", "income", "paid", "pay", "received", "receive", "got", "earn", "wage", "bonus", "deposit", "money in"]),
        GuideTopic(id: "expense", title: "Add something you spent", symbol: "arrow.up.right.circle.fill",
                   steps: ["On Home, tap + at the bottom right and choose Add Expense.",
                           "Enter the amount, what it was for and the account it was paid from.",
                           "One payment for different things, like food and household at the same shop? Turn on Split across categories and give each category its part.",
                           "Tap Save."],
                   tip: "Faster: say “Log spending in Nokael Money” to Siri, then “45 at the supermarket”.",
                   action: .add(.expense), actionTitle: "Add an expense now",
                   keywords: ["spent", "spend", "expense", "bought", "buy", "purchase", "paid for", "cost", "lunch", "groceries", "split categories", "two categories"]),
        GuideTopic(id: "networth", title: "See your net worth over time", symbol: "chart.line.uptrend.xyaxis",
                   steps: ["Open Accounts and tap Net worth under Total Cash.",
                           "The chart shows what you owned less what you owed at the end of each day. Choose 30 days, 90 days or 1 year.",
                           "Pick a date under the chart to see what you owned and owed that day."],
                   tip: "Entries dated in the future don't count until their day. Accounts you've left out of net worth aren't included.",
                   action: .tab(.accounts), actionTitle: "Open Accounts",
                   keywords: ["net worth", "worth", "wealth", "history", "over time", "own", "owe", "trend"]),
        GuideTopic(id: "import", title: "Import a bank statement", symbol: "square.and.arrow.down.fill",
                   steps: ["In your bank's app or website, open Statements and download the period you want as CSV (sometimes called Excel or spreadsheet) or PDF. Save it to Files.",
                           "In Nokael Money, open the Accounts tab and tap the account the statement is for.",
                           "Tap More, then Import a statement, then Choose file, and pick the file. A PDF with a password asks for it.",
                           "If the date, description or amount look wrong, tap Columns and choose the right ones.",
                           "Check the rows. Ones already recorded are skipped. Tap Add."],
                   tip: "CSV is the most reliable. A PDF works best when it's the bank's own download rather than a scan or photo.",
                   action: .importStatement, actionTitle: "Import a statement now",
                   keywords: ["import", "statement", "csv", "pdf", "columns", "excel", "spreadsheet", "bank file", "download", "history", "past", "old transactions"]),
        GuideTopic(id: "capture", title: "Save Apple Pay purchases and bank SMS automatically", symbol: "wallet.pass.fill",
                   steps: ["Open the More tab, then Siri & automatic capture.",
                           "Follow the steps for Apple Pay: one Shortcuts automation, set up once.",
                           "For bank alerts, tick your bank, then follow the SMS steps.",
                           "New purchases appear on Home under Needs you. Tap one to check it."],
                   tip: "iOS doesn't let any app read old messages; capture starts from the moment you set it up. Use a statement import for earlier ones.",
                   action: .capture, actionTitle: "Set it up now",
                   keywords: ["apple pay", "wallet", "sms", "message", "messages", "alert", "automatic", "auto", "sync", "card", "siri", "voice"]),
        GuideTopic(id: "loan", title: "Pay a loan or credit card", symbol: "creditcard.fill",
                   steps: ["On Home, tap + at the bottom right, choose More…, then “I paid a loan or card”.",
                           "Pick the loan or card if you have more than one.",
                           "Enter what you paid and the account it came from, then tap Save.",
                           "What you owe goes down by the payment minus interest, which is worked out for you."],
                   tip: "Or open the card or loan in the Accounts tab and tap Payment.",
                   action: .payDebt, actionTitle: "Pay a loan or card now",
                   keywords: ["loan", "car loan", "personal loan", "mortgage", "credit card", "card payment", "installment", "instalment", "emi", "debt", "owe", "repay", "repayment"]),
        GuideTopic(id: "transfer", title: "Move money between your accounts", symbol: "arrow.left.arrow.right.circle.fill",
                   steps: ["On Home, tap + at the bottom right and choose Transfer Money.",
                           "Choose where it came from and where it went, then tap Save."],
                   tip: "Paying off a credit card from your bank account is a transfer, not spending.",
                   action: .add(.transfer), actionTitle: "Add a transfer now",
                   keywords: ["transfer", "move", "credit card payment", "pay my card", "savings account", "between"]),
        GuideTopic(id: "fix", title: "Change or delete an entry", symbol: "pencil.circle.fill",
                   steps: ["Open the More tab, then Activity, and tap the entry.",
                           "Tap Edit to change it, or Delete at the bottom.",
                           "Every change is kept in its history."],
                   tip: nil, action: .tab(.activity), actionTitle: "Open Activity",
                   keywords: ["edit", "change", "delete", "remove", "wrong", "mistake", "fix", "undo"]),
        GuideTopic(id: "balance", title: "Correct an account's balance", symbol: "slider.horizontal.3",
                   steps: ["On Home, tap + at the bottom right, choose More…, then “A balance is wrong”.",
                           "Pick the account and enter what it really holds today.",
                           "Add a short reason and tap Save."],
                   tip: "To compare with a statement instead, open the account in Accounts, tap More, then Check against a statement.",
                   action: .add(.adjustment), actionTitle: "Correct a balance now",
                   keywords: ["balance", "wrong balance", "correct", "adjust", "reconcile", "doesn't match", "bank says"]),
        GuideTopic(id: "addLoan", title: "Add a loan or credit card", symbol: "creditcard.fill",
                   steps: ["On Home, tap + at the bottom right, choose More…, then “I have a loan or card”.",
                           "Enter what you still owe today and the monthly payment.",
                           "Pick the day it's paid, and it's added to your bills automatically."],
                   tip: "The interest rate is optional. Each payment then lowers what you owe.",
                   action: .addLoan, actionTitle: "Add a loan or card now",
                   keywords: ["add a loan", "add my loan", "new loan", "took a loan", "got a loan", "add a card", "add credit card", "new credit card", "mortgage", "car loan", "personal loan"]),
        GuideTopic(id: "account", title: "Add a bank account or cash", symbol: "building.columns.fill",
                   steps: ["Open the Accounts tab.",
                           "Tap + at the bottom right.",
                           "Pick the type, name it, enter today's balance and tap Add."],
                   tip: nil, action: .tab(.accounts), actionTitle: "Open Accounts",
                   keywords: ["new account", "add bank", "add account", "cash", "wallet account", "savings account"]),
        GuideTopic(id: "budget", title: "Plan your spending for the month", symbol: "chart.pie.fill",
                   steps: ["Open the Budget tab.",
                           "Tap a category and enter how much you plan to spend this month.",
                           "Next month, tap Copy last month's plan to start quickly. Use the month menu at the top to look back."],
                   tip: nil, action: .tab(.budget), actionTitle: "Open Budget",
                   keywords: ["budget", "plan spending", "limit", "category", "categories", "overspent"]),
        GuideTopic(id: "bills", title: "Add a bill or expected income", symbol: "calendar.badge.plus",
                   steps: ["Open the Bills tab.",
                           "Tap + at the bottom right, then Bill or Expected income.",
                           "Enter the name, amount, date and how often it repeats, then tap Save.",
                           "When it's paid, tap it in the Bills tab or under Upcoming Bills on Home and tap Record Payment."],
                   tip: "Bills are set aside from safe to spend before they're due.",
                   action: .bills, actionTitle: "Open Bills",
                   keywords: ["bill", "bills", "rent", "dewa", "subscription", "due", "recurring", "every month", "expected"]),
        GuideTopic(id: "notifications", title: "Choose your notifications", symbol: "bell.badge",
                   steps: ["Open More › Settings › Notifications.",
                           "Turn each kind on or off: bills, spending as it happens, warnings and keeping things right.",
                           "Pick the time reminders come, and turn on Hide amounts to keep figures off the Lock Screen.",
                           "Press and hold a notification for its buttons: Mark paid or Skip on a bill, Change or Undo on a purchase."],
                   tip: "Everything is planned on this iPhone. Nothing about your money is sent anywhere.",
                   action: .notifications, actionTitle: "Open Notifications",
                   keywords: ["notification", "notifications", "remind", "reminder", "alert", "alerts", "badge", "lock screen", "trial"]),
        GuideTopic(id: "goal", title: "Save for something", symbol: "target",
                   steps: ["Open the Budget tab and scroll to Savings.",
                           "Tap Add, then Savings goal.",
                           "Name it, set the target and the account it's kept in, then tap Save."],
                   tip: nil, action: .tab(.budget), actionTitle: "Open Budget",
                   keywords: ["save", "saving", "goal", "target", "set aside"]),
        GuideTopic(id: "safe", title: "What “Safe to spend” means", symbol: "checkmark.shield.fill",
                   steps: ["It's the money in your spending accounts, minus bills due before your next payday, money set aside and what's left in your budget categories.",
                           "Tap the safe to spend figure on Home to see every part."],
                   tip: nil, action: .tab(.home), actionTitle: "Open Home",
                   keywords: ["safe to spend", "how much can i spend", "left", "afford", "worked out"]),
        GuideTopic(id: "backup", title: "Back up your data", symbol: "externaldrive.fill",
                   steps: ["Open the More tab, then Backup & your data.",
                           "Tap Save a backup and keep the file in iCloud Drive or Files.",
                           "On a new iPhone, use Restore from a backup."],
                   tip: "Your data lives only on this iPhone, so keep a recent backup.",
                   action: .backup, actionTitle: nil,
                   keywords: ["backup", "back up", "restore", "new phone", "export", "lose"]),
    ]

    /// Best topics for what the person typed, most relevant first
    static func match(_ text: String) -> [GuideTopic] {
        let lower = text.lowercased()
        let scored = topics.map { topic in
            (topic, topic.keywords.reduce(0) { $0 + (lower.contains($1) ? ($1.contains(" ") ? 3 : 2) : 0) }
                + (lower.contains(topic.title.lowercased()) ? 4 : 0)
                + (topic.id == "addLoan" && addsALoan(lower) ? 6 : 0))
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// "How do I add my car loan" is about adding one, "I paid my car loan" about paying it
    private static func addsALoan(_ lower: String) -> Bool {
        ["loan", "card", "mortgage", "debt"].contains(where: lower.contains)
            && ["add", "new", "took", "got a", "have a", "set up", "setup", "enter", "where"].contains(where: lower.contains)
            && !["pay", "paid", "instal"].contains(where: lower.contains)
    }

    /// Every topic as plain text, for the on-device model
    static var reference: String {
        topics.map { t in
            "\(t.title):\n" + t.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                + (t.tip.map { "\nTip: \($0)" } ?? "")
        }.joined(separator: "\n\n")
    }
}
