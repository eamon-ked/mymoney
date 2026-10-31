//
//  RedesignModel.swift
//  Nokael Money
//
//  What the screens read and what their buttons do. Every figure comes from
//  `store.snapshot` and every change goes through `LedgerStore`; this adds
//  only what's drawn: the navigation, the confirmation with Undo, Privacy
//  Mode, and the plain values the views lay out.
//

import SwiftUI
import NokaelCore

extension Redesign {
    enum Tab: String, CaseIterable {
        case home = "Home", accounts = "Accounts", budget = "Budget", bills = "Bills", more = "More"

        var symbol: String {
            switch self {
            case .home: return "house"
            case .accounts: return "wallet.bifold"
            case .budget: return "leaf"
            case .bills: return "doc.text"
            case .more: return "square.grid.2x2"
            }
        }
    }

    /// Which way money went, for the sign and colour of an amount
    enum Flow { case out, `in`, move }

    /// One entry in Activity, as it's drawn
    struct Transaction: Identifiable, Equatable {
        let id: UUID
        var name: String
        /// Always positive; `flow` gives the direction
        var amount: Decimal
        var flow: Flow
        var kind: EntryKind
        var categoryId: UUID?
        var category: String
        var symbol: String
        var tone: IconBox.Tone
        var date: Date
        /// The account money left, or the one it came into
        var accountId: UUID?
        /// Where a transfer or payment went
        var destinationId: UUID?
        var note: String
        var occurrenceId: UUID?
        var needsReview: Bool
        var voided: Bool
        var source: String?

        var typeName: String {
            switch kind {
            case .expense: "Expense"
            case .income: "Income"
            case .transfer: "Transfer"
            case .debtPayment: "Card or loan payment"
            case .openingBalance: "Starting balance"
            case .adjustment, .reconciliation: "Correction"
            }
        }
    }

    enum BillStatus { case upcoming, dueToday, overdue, partial, paid, skipped }

    /// One due date of a bill or of expected income
    struct Bill: Identifiable, Equatable {
        let id: UUID
        let itemId: UUID
        var name: String
        /// What's still to pay, or what was paid once settled
        var amount: Decimal
        var expected: Decimal
        var paid: Decimal
        var due: Date
        var status: BillStatus
        var categoryId: UUID?
        var category: String
        var accountId: UUID?
        var recurring: String
        var debtId: UUID?
        var isIncome: Bool
        var isEstimate: Bool
        var paidEntryIds: [UUID]
        var isOpen: Bool { status != .paid && status != .skipped }
    }

    /// A budget category in the month on screen
    struct Category: Identifiable, Equatable {
        let id: UUID
        var name: String
        var group: String
        var symbol: String
        var tone: IconBox.Tone
        /// Planned for the month: allocated, carried in and added for bills
        var budget: Decimal
        var spent: Decimal
        var remaining: Decimal
        var allocated: Decimal
        var carriedIn: Decimal
        var fromBills: Decimal
        var unpaidBills: Decimal
        var archived: Bool
    }

    struct Account: Identifiable, Equatable {
        let id: UUID
        let name: String
        /// The last digits of a card or account, when known
        let number: String
        /// What's held, or what's owed for a card or loan, both shown positive
        let balance: Decimal
        let kind: AccountKind
        let archived: Bool
        var isLiability: Bool { kind.isLiability }
        /// A person you owe, rather than one who owes you
        var youOwe: Bool { kind == .lent && balance < 0 }
        /// What to show: people's balances are positive either way, with "Owes you" or "You owe" beside them
        var shown: Decimal { kind == .lent ? abs(balance) : balance }
        var caption: String { isLiability ? "You owe" : kind == .lent ? (youOwe ? "You owe" : "Owes you") : "Balance" }
        var reference: String { number.isEmpty ? Redesign.kindName(kind) : "•••• \(number)" }
    }

    static func kindName(_ kind: AccountKind) -> String {
        switch kind {
        case .cash: "Cash"
        case .bank: "Current account"
        case .savings: "Savings"
        case .creditCard: "Credit card"
        case .loan: "Loan"
        case .investment: "Investment"
        case .otherAsset: "Other asset"
        case .lent: "Person"
        case .income: "Income"
        case .expense: "Spending"
        case .equity: "Opening balances"
        }
    }

    static func kindSymbol(_ kind: AccountKind) -> String {
        switch kind {
        case .cash: "banknote"
        case .bank: "wallet.bifold"
        case .savings: "leaf"
        case .creditCard: "creditcard"
        case .loan: "building.columns"
        case .investment: "chart.line.uptrend.xyaxis"
        case .otherAsset: "shippingbox"
        case .lent: "person.2"
        default: "tag"
        }
    }

    /// The illustration on an account's card, from the asset catalog
    static func kindArtwork(_ kind: AccountKind) -> String {
        switch kind {
        case .cash: "accountCash"
        case .savings: "accountSavings"
        case .creditCard: "accountCreditCard"
        case .loan: "accountLoan"
        case .investment: "accountInvestment"
        case .otherAsset: "accountOtherAsset"
        case .lent: "accountPerson"
        default: "accountCurrent"
        }
    }

    /// The two ends of an account card's gradient: muted tones that sit with the ivory and gold artwork
    static func kindColors(_ kind: AccountKind) -> (UInt32, UInt32) {
        switch kind {
        case .cash: (0x7A7D5A, 0x474B33)
        case .savings: (0x4F6A62, 0x2A423D)
        case .creditCard: (0x576750, 0x24392E)
        case .loan: (0x6E5C4D, 0x3C3028)
        case .investment: (0x4E5B69, 0x29323D)
        case .otherAsset: (0x7B6A4B, 0x473C2A)
        case .lent: (0x735F5C, 0x413432)
        default: (0x5D6B55, 0x33452F)
        }
    }

    /// What the floating + does where the person is: one button, its action set by the screen
    enum CreateAction: Equatable {
        case transaction, account, category, bill

        var label: String {
            switch self {
            case .transaction: "Add a transaction"
            case .account: "Add an account or a transaction"
            case .category: "Add a category or a transaction"
            case .bill: "Add a bill or a transaction"
            }
        }
    }

    /// The kinds of entry the add form makes
    enum FormKind: Hashable { case expense, income, transfer, adjustment, bill, expectedIncome }

    /// Money with a person: you lend or pay back (out), they pay back or lend you (in), or it's let go
    enum LendAction: Hashable {
        case lend, repaid, forgive, borrow, payBack
        var isOut: Bool { self == .lend || self == .payBack }
    }

    /// Everything a sheet can show; pushing one inside a sheet goes deeper
    enum Sheet: Hashable, Identifiable {
        case breakdown, whatHappened, review, schedules
        case entry(FormKind), editEntry(UUID), splitEntry(UUID), editBill(UUID)
        case account(UUID), bill(UUID), link(UUID), category(UUID), transaction(UUID)
        case payDebt(UUID, occurrence: UUID?), editDebtPayment(UUID), entryAsDebtPayment(UUID)
        case debtTerms(UUID), reconcile(UUID), accountType(UUID), startingAmount(UUID), lend(UUID?, LendAction)
        case importStatement(UUID?), newAccount(loan: Bool), newCash, newCategory, editCategory(UUID), moveMoney(UUID)
        case loansInCategory(UUID), goal(UUID), reserve(UUID?, goal: Bool), goalMoney(UUID, adding: Bool)
        case payday, help, intelligence, ask, paywall(PlusFeature), billLink(UUID)
        var id: Self { self }
    }

    /// Full screens pushed over the tabs, with a back button: Activity and the pages listed in More
    enum Page: Hashable {
        case activity, reports, forecast, profile, settings, privacy, privacyMode, help
        case capture, data, plus, categories, history, reminders, intelligenceSettings
    }

    /// What Privacy Mode hides. It only changes what's drawn; the figures underneath are never touched.
    /// Standard hides amounts; Enhanced also hides whichever of the three details below are switched on.
    /// It belongs to this phone, so it's kept in UserDefaults rather than in the data a backup carries.
    struct Privacy: Codable, Equatable {
        var on = false
        var enhanced = false
        var hideDetails = true
        var hideAccountNames = true
        var hideCharts = true
        /// Reopen the way the person left it; when off, the app always opens with amounts showing
        var remember = true
        /// Cover the screen in the app switcher and whenever the app isn't in front
        var coverInBackground = true

        private static let key = "redesignPrivacy"

        /// Read before the first frame is drawn, so a hidden amount never flashes up at launch
        static func stored() -> Privacy {
            guard let data = UserDefaults.standard.data(forKey: key),
                  var saved = try? JSONDecoder().decode(Privacy.self, from: data) else { return Privacy() }
            if !saved.remember { saved.on = false }
            return saved
        }

        func store() {
            if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
        }
    }

    /// The stand-in for a concealed figure; VoiceOver hears "hidden" rather than the dots
    static let hiddenDigits = "••••••"

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        var isError = false
        var canUndo = false
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    @MainActor @Observable
    final class AppModel {
        let store: LedgerStore
        let plus: PlusStore

        var tab: Tab = .home
        var sheet: Sheet?
        var path: [Sheet] = []
        var pages: [Page] = []
        var toast: Toast?
        var showFilters = false
        var actionsOpen = false
        /// Height of the tab bar and +, which float over the screen; every scroll area keeps this much clear at its end
        var barHeight: CGFloat = 140
        /// How far ahead safe to spend looks, chosen on the breakdown and shown on Home
        var safePeriod = SafePeriod.saved {
            didSet { SafePeriod.saved = safePeriod; WidgetSync.update(snapshot, isPlus: isPlus) }
        }
        var safePeriodDate = SafePeriod.savedDate {
            didSet { SafePeriod.savedDate = safePeriodDate; WidgetSync.update(snapshot, isPlus: isPlus) }
        }
        /// The month Budget shows, as a BudgetMonth key
        var month: String
        var privacy = Privacy() { didSet { privacy.store() } }
        /// Fields worked out by Help or a sentence, picked up by the next add form
        var draft: DraftEntry?
        /// What Help heard as the salary, picked up by Payday
        var paydaySaid: Money?
        /// nil follows the phone; kept on this phone like Privacy Mode
        var dark: Bool? = AppModel.storedAppearance() { didSet { AppModel.storeAppearance(dark) } }

        @ObservationIgnored private var undo: (() throws -> Void)?
        @ObservationIgnored private var cache: (revision: Int, privacyKey: Int, value: Cache)?

        init(store: LedgerStore, plus: PlusStore) {
            self.store = store
            self.plus = plus
            month = store.snapshot.monthKey
            privacy = Privacy.stored()
        }

        private static let appearanceKey = "appearance"
        private static func storedAppearance() -> Bool? {
            switch UserDefaults.standard.string(forKey: appearanceKey) {
            case "dark": true
            case "light": false
            default: nil
            }
        }
        private static func storeAppearance(_ dark: Bool?) {
            UserDefaults.standard.set(dark.map { $0 ? "dark" : "light" }, forKey: appearanceKey)
        }

        var snapshot: FinanceSnapshot { store.snapshot }
        var currency: String { store.currency }
        var today: Date { snapshot.today }
        var calendar: Calendar { snapshot.calendar }
        var isPlus: Bool { plus.isPlus }

        /// The person's name from their profile, shown in the greeting and on the card
        var holder: String {
            get { store.settings.displayName }
            set { try? store.updateSettings { $0.displayName = newValue } }
        }

        // MARK: - Lists, rebuilt once per change

        private struct Cache {
            var accounts: [Account] = []
            var archived: [Account] = []
            var transactions: [Transaction] = []
            var bills: [Bill] = []
        }

        private var lists: Cache {
            let revision = store.revision
            if let cache, cache.revision == revision { return cache.value }
            let s = snapshot
            let digits = cardDigits()
            func account(_ r: LedgerAccountRecord) -> Account {
                let balance = s.balance(r.id)
                return Account(id: r.id, name: r.name, number: digits[r.id] ?? "",
                               balance: (r.kind.isLiability ? balance.negated : balance).decimal,
                               kind: r.kind, archived: r.archived)
            }
            var value = Cache()
            value.accounts = sortedAccounts(s.accounts).map(account)
            value.archived = s.archivedAccounts.map(account)
            value.transactions = s.entries(includeVoided: true).map { transaction($0, in: s) }
            value.bills = s.occurrences.compactMap { bill($0, in: s) }
            cache = (revision, 0, value)
            return value
        }

        private func sortedAccounts(_ records: [LedgerAccountRecord]) -> [LedgerAccountRecord] {
            let order: [AccountKind] = [.bank, .cash, .savings, .investment, .otherAsset, .lent, .creditCard, .loan]
            return records.sorted { (order.firstIndex(of: $0.kind) ?? 99, $0.sortOrder) < (order.firstIndex(of: $1.kind) ?? 99, $1.sortOrder) }
        }

        /// Card endings the person linked, else digits in the bank's name ("Visa 4821")
        private func cardDigits() -> [UUID: String] {
            var digits: [UUID: String] = [:]
            for link in store.fetch(CardLinkRecord.self) {
                let d = String(link.hint.filter(\.isNumber).suffix(4))
                if d.count == 4 { digits[link.accountId] = d }
            }
            for r in snapshot.accounts where digits[r.id] == nil {
                let d = String((r.institution ?? "").filter(\.isNumber).suffix(4))
                if d.count == 4 { digits[r.id] = d }
            }
            return digits
        }

        var accounts: [Account] { lists.accounts }
        var archivedAccounts: [Account] { lists.archived }
        /// Posted entries, newest first
        var transactions: [Transaction] { lists.transactions.filter { !$0.voided } }
        var allTransactions: [Transaction] { lists.transactions }
        /// Bill and income due dates, soonest first
        var allBills: [Bill] { lists.bills }
        var bills: [Bill] { lists.bills.filter { !$0.isIncome } }
        var expectedIncome: [Bill] { lists.bills.filter(\.isIncome) }

        /// Unpaid bills due in the next 30 days, overdue first
        var unpaidBills: [Bill] {
            let end = calendar.date(byAdding: .day, value: 30, to: today) ?? today
            return bills.filter { $0.isOpen && $0.due <= end }
        }

        var moneyAccounts: [Account] { accounts.filter { $0.kind.holdsMoney } }
        var cards: [Account] { accounts.filter { $0.kind == .creditCard } }
        var loans: [Account] { accounts.filter { $0.kind == .loan } }
        var lent: [Account] { accounts.filter { $0.kind == .lent } }

        func account(_ id: UUID?) -> Account? { accounts.first { $0.id == id } ?? archivedAccounts.first { $0.id == id } }
        func record(_ id: UUID?) -> LedgerAccountRecord? { snapshot.account(id) }
        func bill(_ id: UUID?) -> Bill? { lists.bills.first { $0.id == id } }
        func transaction(_ id: UUID?) -> Transaction? { lists.transactions.first { $0.id == id } }
        func entry(_ id: UUID?) -> EntryRecord? { id.flatMap { store.entryRecord($0) } }
        func item(_ id: UUID?) -> PlannedItem? { snapshot.items.first { $0.id == id } }

        func transactions(touching accountId: UUID) -> [Transaction] {
            transactions.filter { $0.accountId == accountId || $0.destinationId == accountId }
        }

        private func transaction(_ record: EntryRecord, in s: FinanceSnapshot) -> Transaction {
            let entry = record.entry
            let lines = entry.lines.compactMap { line in s.account(line.accountId).map { (record: $0, amount: line.amount) } }
            let category = lines.first { $0.record.kind.isCategory }?.record
            let sheet = lines.filter { $0.record.kind.isBalanceSheet }
            let assets = sheet.filter { $0.record.kind.isAsset }
            var flow = Flow.move
            var amount = Money.zero(s.currency)
            var from: UUID?
            var to: UUID?
            switch record.kind {
            case .transfer:
                amount = sheet.first { $0.amount.isPositive }?.amount ?? amount
                from = sheet.first { $0.amount.isNegative }?.record.id
                to = sheet.first { $0.amount.isPositive }?.record.id
            case .debtPayment:
                // What left the paying account, not what came off the loan
                amount = assets.map(\.amount).sum(s.currency).magnitude
                flow = .out
                from = assets.first?.record.id
                to = sheet.first { $0.record.kind.isLiability }?.record.id
            default:
                // A split bill's people only owe part back: what left your account is the amount.
                // With no account of yours, a friend paid
                let own = sheet.filter { $0.record.kind != .lent }
                let paying = own.isEmpty ? sheet : own
                let change = paying.map(\.amount).sum(s.currency)
                amount = change.magnitude
                flow = change.isNegative ? .out : .in
                if record.kind == .expense, paying.first?.record.kind.isLiability == true { flow = .out }
                from = paying.first?.record.id
            }
            let (symbol, tone) = category.map(Self.look) ?? (record.kind == .transfer ? ("arrow.up.arrow.down", .green)
                : record.kind == .debtPayment ? ("creditcard", .green) : ("slider.horizontal.3", .green))
            return Transaction(id: record.id, name: record.memo.isEmpty ? (category?.name ?? "Entry") : record.memo,
                               amount: amount.decimal, flow: flow, kind: record.kind, categoryId: category?.id,
                               category: category?.name ?? (record.kind == .transfer ? "Transfer" : record.kind == .debtPayment ? "Loan or card" : "Correction"),
                               symbol: symbol, tone: tone, date: record.date, accountId: from, destinationId: to,
                               note: record.notes, occurrenceId: record.occurrenceId, needsReview: record.needsReview,
                               voided: record.status == .void, source: record.source?.title)
        }

        private func bill(_ occ: Occurrence, in s: FinanceSnapshot) -> Bill? {
            guard let item = s.item(for: occ) else { return nil }
            let state = s.state(of: occ)
            let status: BillStatus = switch state {
            case .scheduled: .upcoming
            case .dueToday: .dueToday
            case .overdue: .overdue
            case .partiallyPaid: .partial
            case .paid: .paid
            case .skipped: .skipped
            }
            let category = s.account(item.categoryId)
            return Bill(id: occ.id, itemId: item.id, name: item.name,
                        amount: (status == .paid ? occ.paid : occ.remaining).decimal, expected: occ.expected.decimal,
                        paid: occ.paid.decimal, due: occ.dueDate, status: status, categoryId: item.categoryId,
                        category: category?.name ?? (item.debtId != nil ? "Loan payment" : "No category"),
                        accountId: item.accountId, recurring: scheduleLabel(item.schedule), debtId: item.debtId,
                        isIncome: item.direction == .inflow, isEstimate: occ.isEstimate, paidEntryIds: occ.paidEntryIds)
        }

        func scheduleLabel(_ schedule: Schedule) -> String {
            if let end = schedule.end, calendar.isDate(end, inSameDayAs: schedule.start) { return "One time" }
            return schedule.frequency.label
        }

        /// A category's own symbol in the design's outline style, and its tone: warm for food and fun, cool for getting around
        static func look(_ r: LedgerAccountRecord) -> (String, IconBox.Tone) {
            var symbol = r.icon.isEmpty ? "tag" : r.icon
            for suffix in [".fill", ".circle"] where symbol.hasSuffix(suffix) { symbol = String(symbol.dropLast(suffix.count)) }
            if symbol == "ellipsis" { symbol = "ellipsis" }
            let warm = ["cart", "fork.knife", "bag", "film", "cup.and.saucer", "gift", "basket", "party.popper", "gamecontroller"]
            let cool = ["car", "bus", "tram", "airplane", "fuelpump", "bicycle", "wifi", "phone"]
            let tone: IconBox.Tone = warm.contains(symbol) || r.group == "Lifestyle" ? .warm : cool.contains(symbol) ? .cool : .green
            return (symbol, tone)
        }

        // MARK: - Budget

        var monthStart: Date { BudgetMonth.start(of: month, calendar: calendar) ?? today }
        var isThisMonth: Bool { month == snapshot.monthKey }

        func categories(in month: String? = nil) -> [Category] {
            let m = month ?? self.month
            return snapshot.expenseCategoryGroups.flatMap(\.categories).map { category($0, month: m) }
        }

        func category(_ id: UUID?, month: String? = nil) -> Category? {
            guard let r = snapshot.account(id), r.kind.isCategory else { return nil }
            return category(r, month: month ?? self.month)
        }

        private func category(_ r: LedgerAccountRecord, month: String) -> Category {
            let line = snapshot.budget.line(r.id, month: month)
            let (symbol, tone) = Self.look(r)
            return Category(id: r.id, name: r.name, group: r.group.isEmpty ? "Other" : r.group, symbol: symbol, tone: tone,
                            budget: line.planned.decimal, spent: line.spent.decimal, remaining: line.remaining.decimal,
                            allocated: line.allocated.decimal, carriedIn: line.carriedIn.decimal,
                            fromBills: line.fromBills.decimal, unpaidBills: line.unpaidBills.decimal, archived: r.archived)
        }

        var unallocated: Decimal { snapshot.budget.availableToAllocate(month: month).decimal }

        /// Categories most used recently first, for the add form's picker
        func expenseChoices() -> [LedgerAccountRecord] {
            let counts = Dictionary(grouping: snapshot.entryRecords.prefix(200).compactMap { $0.entry.lines.first { snapshot.account($0.accountId)?.kind == .expense }?.accountId }) { $0 }
                .mapValues(\.count)
            return snapshot.expenseCategories.filter { !$0.archived }
                .sorted { (counts[$0.id] ?? 0, -$0.sortOrder) > (counts[$1.id] ?? 0, -$1.sortOrder) }
        }

        // MARK: - Figures

        var safeToSpend: SafeToSpend { snapshot.safeToSpend(through: safePeriod.end(in: snapshot, picked: safePeriodDate)) }

        /// Home's words for the chosen period: "until payday", "for the next 7 days", "until 30 Nov"
        var safePeriodLabel: String {
            let end = safeToSpend.periodEnd.formatted(.dateTime.day().month(.abbreviated))
            switch safePeriod {
            case .untilPayday: return snapshot.nextIncomeDate == nil ? "until \(end)" : "until payday"
            case .week: return "for the next 7 days"
            case .monthEnd, .date: return "until \(end)"
            }
        }
        /// Spendable money: the accounts safe to spend starts from
        var cash: Decimal { safeToSpend.spendableTotal.decimal }
        /// Held back for bills, savings, essentials and the buffer
        var reserved: Decimal {
            let s = safeToSpend
            return (s.obligationsTotal + s.reservesTotal + s.categoryReservationsTotal + s.buffer).decimal
        }
        var safe: Decimal { max(0, safeToSpend.amount?.decimal ?? 0) }
        var shortfall: Decimal { max(0, -(safeToSpend.amount?.decimal ?? 0)) }
        var setupComplete: Bool { safeToSpend.amount != nil }

        func decimal(_ money: Money) -> Decimal { money.decimal }
        func money(from decimal: Decimal) -> Money { Money(decimal, currency: currency) }

        /// What a person typed as an amount; nil when it isn't a number
        func parse(_ text: String) -> Money? { MoneyFormat.parse(text, currency: currency) }
        func editable(_ value: Decimal) -> String { value == 0 ? "" : MoneyFormat.editable(money(from: value)) }

        // MARK: - Privacy Mode
        // Every screen draws figures and names through these, so one switch covers the whole app

        var hidesAmounts: Bool { privacy.on }
        var isEnhanced: Bool { privacy.on && privacy.enhanced }
        var hidesDetails: Bool { isEnhanced && privacy.hideDetails }
        var hidesAccountNames: Bool { isEnhanced && privacy.hideAccountNames }
        var hidesCharts: Bool { isEnhanced && privacy.hideCharts }

        /// An amount as text, or the currency and dots in Privacy Mode; `revealed` is a form's deliberate Show
        func money(_ value: Decimal, revealed: Bool = false) -> String {
            hidesAmounts && !revealed ? "\(currency) \(Redesign.hiddenDigits)"
                : value.formatted(.currency(code: currency).presentation(.isoCode).locale(store.settings.locale)
                    .precision(.fractionLength(Currency.scale(of: currency))))
        }

        func money(_ value: Money, revealed: Bool = false) -> String { money(value.decimal, revealed: revealed) }

        /// An amount on its own, ready to style
        func amount(_ value: Decimal, revealed: Bool = false) -> Text { Text(private: money(value, revealed: revealed)) }

        /// A plain figure without the currency, as in "/ 1,000"
        func number(_ value: Decimal) -> String { hidesAmounts ? Redesign.hiddenDigits : value.formatted(.number.precision(.fractionLength(0...2))) }

        /// A share as a percentage; hidden with the charts, since it shows the shape of the person's spending
        func percent(_ share: Double) -> String { hidesCharts ? "••%" : "\(Int((share * 100).rounded()))%" }

        /// "Account 1", "Account 2"… in the order Accounts lists them, when account names are hidden
        func accountLabel(_ id: UUID?) -> String {
            guard let id else { return "No account" }
            let all = accounts + archivedAccounts
            guard let i = all.firstIndex(where: { $0.id == id }) else { return snapshot.account(id)?.name ?? "Account" }
            return hidesAccountNames ? "Account \(i + 1)" : all[i].name
        }

        func reference(of account: Account) -> String { hidesAccountNames ? Redesign.kindName(account.kind) : account.reference }

        func name(of t: Transaction) -> String { hidesDetails ? t.typeName : t.name }
        func category(of t: Transaction) -> String { hidesDetails ? "Hidden" : t.category }
        func note(of t: Transaction) -> String { hidesDetails ? "Hidden in Privacy Mode." : t.note.isEmpty ? "No note added." : t.note }

        /// The icon a transaction shows; in Enhanced privacy only its type, never the merchant or category
        func icon(of t: Transaction) -> (String, IconBox.Tone) {
            guard hidesDetails else { return (t.symbol, t.tone) }
            return (t.flow == .in ? "arrow.down.left" : t.flow == .move ? "arrow.up.arrow.down" : "ellipsis", .green)
        }

        func name(of bill: Bill) -> String {
            guard hidesDetails else { return bill.name }
            let list = bill.isIncome ? expectedIncome : bills
            let ids = Array(NSOrderedSet(array: list.map(\.itemId))) as? [UUID] ?? []
            return "\(bill.isIncome ? "Income" : "Bill") \((ids.firstIndex(of: bill.itemId) ?? 0) + 1)"
        }

        func day(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }
        func fullDay(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated).year()) }

        func greeting(at date: Date) -> String {
            let hour = calendar.component(.hour, from: date)
            return hour < 12 ? "Good morning," : hour < 18 ? "Good afternoon," : "Good evening,"
        }

        // MARK: - Navigation

        /// The + button's job on the screen in front; nil hides it (More, and pages with nothing to create)
        var createAction: CreateAction? {
            if let page = pages.last { return page == .activity ? .transaction : nil }
            switch tab {
            case .home: return .transaction
            case .accounts: return .account
            case .budget: return .category
            case .bills: return .bill
            case .more: return nil
            }
        }

        func open(_ sheet: Sheet) {
            if self.sheet == nil { path = []; self.sheet = sheet } else { path.append(sheet) }
        }

        /// Opens a Plus feature, or the paywall for it
        func open(_ sheet: Sheet, needs feature: PlusFeature) {
            open(isPlus ? sheet : .paywall(feature))
        }

        func show(_ page: Page, needs feature: PlusFeature) {
            if isPlus { show(page) } else { open(.paywall(feature)) }
        }

        /// Back one step inside a sheet, or closes it at its first screen
        func back() {
            if path.isEmpty { sheet = nil } else { path.removeLast() }
        }

        func close() {
            sheet = nil
            path = []
        }

        func go(_ tab: Tab) {
            sheet = nil
            path = []
            pages = []
            actionsOpen = false
            self.tab = tab
        }

        /// Pushes a full screen over the current tab, closing any sheet first, so Back returns where the person was
        func show(_ page: Page) {
            sheet = nil
            path = []
            actionsOpen = false
            pages.append(page)
        }

        // MARK: - Changes

        /// Runs a change; shows its problem in the toast and returns it, or nil when it worked
        @discardableResult
        func attempt(_ message: String? = nil, closing: Bool = true, undo: (() throws -> Void)? = nil,
                     _ change: () throws -> Void) -> String? {
            do {
                try change()
                if closing { close() }
                self.undo = undo
                if let message { toast = Toast(message: message, canUndo: undo != nil) }
                return nil
            } catch {
                return StoreError.from(error).errorDescription ?? error.localizedDescription
            }
        }

        func undoLast() {
            guard let undo else { return }
            self.undo = nil
            do {
                try undo()
                toast = Toast(message: "Undone.")
            } catch {
                toast = Toast(message: StoreError.from(error).errorDescription ?? "Couldn't undo that.", isError: true)
            }
        }

        func fail(_ error: Error) {
            toast = Toast(message: StoreError.from(error).errorDescription ?? error.localizedDescription, isError: true)
        }

        /// Saves an add or edit form; returns the problem to show beside it, or nil when saved
        func save(_ form: EntryForm, replacing original: UUID? = nil) -> String? {
            var id: UUID?
            let message: String = if original != nil { "Transaction updated." }
                else if form.kind == .transfer { "Transfer recorded. Your total cash is unchanged." }
                else if form.kind == .adjustment { "Balance corrected." }
                else if form.occurrenceId != nil { "Payment recorded. Your balances are up to date." }
                else { "Transaction saved." }
            let problem = attempt(message, undo: original == nil ? { [store] in if let id { try store.void(id) } } : nil) {
                id = try store.save(form, replacing: original)
                if let account = form.accountId, snapshot.account(account)?.kind != .lent {
                    try store.updateSettings { $0.lastUsedAccountId = account }
                }
            }
            return problem
        }

        /// Records a bill as paid by adding a payment
        func pay(_ bill: Bill, amount: Money, from accountId: UUID?, category: UUID?, on date: Date, key: UUID) -> String? {
            guard let accountId else { return "Choose the account it was paid from." }
            var id: UUID?
            return attempt(bill.isIncome ? "Income recorded." : "Payment recorded. Your balances are up to date.",
                           undo: { [store] in if let id { try store.void(id) } }) {
                id = try store.pay(occurrenceId: bill.id, amount: amount, accountId: accountId, categoryId: category,
                                   date: date, key: key)
            }
        }

        /// Links a payment already in Activity to the bill, so it isn't counted twice
        func link(_ bill: Bill, with t: Transaction) {
            attempt("Payment linked. No duplicate transaction created.", undo: { [store] in try store.unlink(entryId: t.id) }) {
                try store.match(occurrenceId: bill.id, entryId: t.id)
            }.map { toast = Toast(message: $0, isError: true) }
        }

        /// Unlinked entries of the bill's direction near its amount and date, closest first
        func matches(for bill: Bill) -> [Transaction] {
            let window: TimeInterval = 20 * 86_400
            return transactions
                .filter { $0.occurrenceId == nil && $0.flow == (bill.isIncome ? .in : .out)
                    && (bill.isIncome ? $0.kind == .income : $0.kind == .expense || $0.kind == .debtPayment)
                    && abs($0.date.timeIntervalSince(bill.due)) <= window }
                .sorted { abs($0.amount - bill.expected) < abs($1.amount - bill.expected) }
                .prefix(8).map { $0 }
        }

        func setBudget(_ id: UUID, to amount: Money) -> String? {
            attempt("Monthly budget updated.", closing: false) { try store.setAllocation(amount, categoryId: id, month: month) }
        }

        /// Adds a category with this month's budget
        func addCategory(_ name: String, group: String, budget: Money?, icon: String) -> String? {
            let name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return "Give the category a name." }
            guard !snapshot.expenseCategories.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                return "This category is already in your budget."
            }
            return attempt("Category added to your budget.") {
                let r = try store.saveCategory(nil, name: name, isIncome: false, group: group, policy: .rollover,
                                               reserve: false, icon: icon, colorHex: "#8E8E93")
                if let budget, budget.isPositive { try store.setAllocation(budget, categoryId: r.id, month: month) }
            }
        }

        /// Pinned categories shown on Home
        var pinned: [Category] {
            store.settings.pinnedCategoryIds.compactMap { category($0, month: snapshot.monthKey) }.filter { !$0.archived }
        }

        func togglePin(_ id: UUID) {
            attempt(closing: false) {
                try store.updateSettings { s in
                    if let i = s.pinnedCategoryIds.firstIndex(of: id) { s.pinnedCategoryIds.remove(at: i) } else { s.pinnedCategoryIds.append(id) }
                }
            }.map { toast = Toast(message: $0, isError: true) }
        }
    }
}
