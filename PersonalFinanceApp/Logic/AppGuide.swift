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
    case captureApplePay
    case captureBank
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
        GuideTopic(id: "applePay", title: "Save Apple Pay purchases automatically", symbol: "wallet.pass.fill",
                   steps: ["Open the More tab, then Automatic capture, then Apple Pay.",
                           "Tap Add the Apple Pay shortcut."]
                           + applePaySetupSteps
                           + ["Pay with Apple Pay once. The purchase appears on Home under Needs you."],
                   tip: "Shortcuts adds the automation switched off, so you turn it on once.",
                   action: .captureApplePay, actionTitle: "Set up Apple Pay now",
                   keywords: ["apple pay", "wallet", "tap to pay", "card purchase", "transaction automation", "automation", "automatic", "auto", "card"]),
        GuideTopic(id: "bankMessages", title: "Save bank messages automatically", symbol: "message.fill",
                   steps: ["Open the More tab, then Automatic capture, then Bank messages.",
                           "Tap Add the bank alerts shortcut."]
                           + bankSetupSteps(keyword: nil)
                           + ["Back in Nokael Money, add your bank under Your banks. New purchases appear on Home under Needs you."],
                   tip: "iOS doesn't let any app read old messages, so capture starts from the moment you set it up. Use a statement import for earlier ones.",
                   action: .captureBank, actionTitle: "Set up bank messages now",
                   keywords: ["sms", "message", "messages", "bank alert", "alert", "text message", "message automation", "automation", "automatic", "auto", "sync"]),
        GuideTopic(id: "automationOff", title: "Purchases aren't saved automatically", symbol: "exclamationmark.arrow.circlepath",
                   steps: ["Open Shortcuts. Tap \u{2039} at the top left until you reach Library, then tap Automation.",
                           "Check the Wallet one, or the message one with your currency, is switched on.",
                           "Not listed? Add the shortcut again from More › Automatic capture."],
                   tip: "Automatic capture shows when the last purchase or message arrived, so you can see it working.",
                   action: .capture, actionTitle: "Open Automatic capture",
                   keywords: ["not working", "isn't working", "doesn't work", "not saving", "nothing saved", "not saved", "turned off", "disabled", "switch on", "turn on", "enable", "automation off", "stopped"]),
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
        GuideTopic(id: "addLoan", title: "Add something you owe", symbol: "creditcard.fill",
                   steps: ["On Accounts, tap + at the bottom right and choose Add Debt.",
                           "Pick who you owe: a person, a loan or a credit card.",
                           "Enter what you still owe today. For a loan or card, add the monthly payment too.",
                           "Pick the day it's paid, and it's added to your bills automatically."],
                   tip: "The interest rate is optional. Each payment then lowers what you owe.",
                   action: .addLoan, actionTitle: "Add what you owe now",
                   keywords: ["add a debt", "add debt", "i owe", "owe someone", "owe a friend", "add a loan", "add my loan", "new loan", "took a loan", "got a loan", "add a card", "add credit card", "new credit card", "mortgage", "car loan", "personal loan"]),
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

    // MARK: Turning on an automation

    /// The bank shortcut's name once added (the link in legal-docs/_redirects); change it here if it's renamed
    static let bankShortcutName = "Nokael Money Bank Alerts"

    /// After tapping the button that opens a shared shortcut: it brings its automation, but Shortcuts adds
    /// that switched off. These follow Shortcuts screen by screen, so the setup pages and Help agree.
    static let applePaySetupSteps = [
        "Tap Add Shortcut.",
        "Tap \u{2039} at the top left to go to Library.",
        "Tap Automation.",
        "Turn on \u{201C}When I tap a Wallet pass or payment card\u{201D}. It's near the bottom.",
    ]

    /// What the shared bank shortcut's message automations look for, one automation each. Keep in
    /// step with the shortcut the /s/bank-alerts link opens.
    static let sharedMessageKeywords: Set<String> = ["円", "¥", "JPY", "Rs", "INR", "€", "EUR", "£", "GBP", "$", "USD",
                                                     "OMR", "BHD", "KWD", "QAR", "SAR", "AED"]

    /// The same for bank messages: turn on the automation for the person's currency. A currency the
    /// shortcut doesn't cover gets an automation of its own.
    static func bankSetupSteps(keyword: String?) -> [String] {
        let open = ["Tap Add Shortcut.", "Tap \u{2039} at the top left to go to Library.", "Tap Automation."]
        guard let keyword else {
            return open + ["Turn on the \u{201C}When I Get a Message Containing\u{201D} one with your currency, such as \u{2018}EUR\u{2019} or \u{2018}£\u{2019}."]
        }
        guard sharedMessageKeywords.contains(keyword) else {
            return open + ["Tap +, choose Message, enter \u{201C}\(keyword)\u{201D} in Message Contains, choose Run Immediately and tap Next.",
                           "Pick \u{201C}\(bankShortcutName)\u{201D}."]
        }
        return open + ["Turn on \u{201C}When I Get a Message Containing \u{2018}\(keyword)\u{2019}\u{201D}."]
    }

    /// Best topics for what the person typed, most relevant first
    static func match(_ text: String) -> [GuideTopic] {
        let lower = text.lowercased()
        let scored = topics.map { topic in
            (topic, topic.keywords.reduce(0) { $0 + (lower.contains($1) ? ($1.contains(" ") ? 3 : 2) : 0) }
                + (lower.contains(topic.title.lowercased()) ? 4 : 0)
                + (topic.id == "addLoan" && addsALoan(lower) ? 6 : 0)
                + (topic.id == "automationOff" && notWorking(lower) ? 6 : 0))
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// "How do I add my car loan" is about adding one, "I paid my car loan" about paying it
    private static func addsALoan(_ lower: String) -> Bool {
        ["loan", "card", "mortgage", "debt"].contains(where: lower.contains)
            && ["add", "new", "took", "got a", "have a", "set up", "setup", "enter", "where"].contains(where: lower.contains)
            && !["pay", "paid", "instal"].contains(where: lower.contains)
    }

    /// "My Apple Pay automation isn't working" is about fixing it, not setting it up
    private static func notWorking(_ lower: String) -> Bool {
        ["not working", "isn't working", "isnt working", "doesn't work", "doesnt work", "not saving", "not saved",
         "nothing saved", "stopped", "disabled", "turned off", "not showing", "isn't showing"].contains(where: lower.contains)
    }

    /// Every topic as plain text, for the on-device model
    static var reference: String {
        topics.map { t in
            "\(t.title):\n" + t.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                + (t.tip.map { "\nTip: \($0)" } ?? "")
        }.joined(separator: "\n\n")
    }
}
