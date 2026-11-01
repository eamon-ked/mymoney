//
//  RedesignTabs.swift
//  Nokael Money
//
//  The five tabs, and the rows they share with the sheets.
//

import SwiftUI
import NokaelCore

// MARK: - Rows

extension Redesign {
    struct TransactionRow: View {
        @Environment(AppModel.self) private var app
        let t: Transaction
        /// Shows the account in the caption in place of the category, as inside an account
        var showsAccount = false

        var body: some View {
            Button { app.open(.transaction(t.id)) } label: {
                HStack(spacing: 12) {
                    IconBox(app.icon(of: t), small: true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(app.name(of: t)).rdText(.cardTitle).lineLimit(1)
                            .strikethrough(t.voided)
                        HStack(spacing: 6) {
                            Text(caption).lineLimit(1)
                            if t.voided { tag("Deleted", Theme.muted) } else if t.needsReview { tag("New", Theme.amber) }
                        }
                        .rdText(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Text(private: sign + " " + app.money(t.amount))
                        .rdText(.amount)
                        .strikethrough(t.voided)
                        .foregroundStyle(t.voided ? Theme.muted : t.flow == .in ? Theme.primary : t.flow == .out ? Theme.destructive : Theme.muted)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var caption: String {
            if app.hidesDetails { return app.day(t.date) }
            let middle = showsAccount ? app.accountLabel(t.accountId) : t.category
            return "\(middle)  ·  \(app.day(t.date))"
        }

        private func tag(_ text: String, _ color: Color) -> some View {
            Text(text).rdText(.captionStrong).foregroundStyle(color)
        }

        private var sign: String { t.flow == .in ? "+" : t.flow == .out ? "−" : "↔" }
    }

    struct BillRow: View {
        @Environment(AppModel.self) private var app
        let bill: Bill
        var compact = false

        var body: some View {
            Button { app.open(.bill(bill.id)) } label: {
                HStack(spacing: 12) {
                    IconBox(symbol: bill.isIncome ? "arrow.down.left" : bill.debtId != nil ? "creditcard" : "doc.text",
                            tone: bill.status == .overdue ? .alert : .green, small: true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(app.name(of: bill)).rdText(.cardTitle).lineLimit(1)
                        Text("\(bill.isIncome ? "Expected" : "Due") \(app.fullDay(bill.due))" + (!compact && bill.recurring != "One time" ? " · \(bill.recurring)" : ""))
                            .rdText(.caption).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 5) {
                        app.amount(bill.amount).rdText(.amount)
                        StatusPill(bill: bill, today: app.today)
                    }
                }
                .padding(.vertical, compact ? 12 : 0)
                .contentShape(Rectangle())
                .modifier(Card(on: !compact))
            }
            .buttonStyle(.plain)
        }
    }

    struct AccountRow: View {
        @Environment(AppModel.self) private var app
        @Environment(\.dynamicTypeSize) private var typeSize
        let account: Account
        var compact = false

        var body: some View {
            Button { app.open(.account(account.id)) } label: {
                HStack(alignment: compact ? .center : .top, spacing: 12) {
                    if compact { IconBox(symbol: Redesign.kindSymbol(account.kind), small: true) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.accountLabel(account.id)).rdText(.cardTitle).lineLimit(1)
                        Text(app.reference(of: account) + (compact && account.isLiability ? " · Owed" : ""))
                            .rdText(.caption).tracking(0.7).foregroundStyle(muted)
                        if !compact {
                            app.amount(account.shown).rdText(.figure)
                                .padding(.top, 6)
                            Text(account.isLiability ? "Outstanding balance" : account.caption)
                                .rdText(.caption).foregroundStyle(muted)
                        }
                    }
                    Spacer(minLength: 8)
                    if compact {
                        app.amount(account.shown).rdText(.amount)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                    } else if !typeSize.isAccessibilitySize {
                        Image(Redesign.kindArtwork(account.kind))
                            .resizable().scaledToFit()
                            .frame(width: 92, height: 92)
                            .padding(.vertical, -6)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, compact ? 13 : 0)
                .contentShape(Rectangle())
                .modifier(Face(kind: account.kind, on: !compact))
            }
            .buttonStyle(.plain)
        }

        private var muted: Color { compact ? Theme.muted : .white.opacity(0.65) }

        /// The account on a coloured card of its own, like the credit card on the card's page
        struct Face: ViewModifier {
            let kind: AccountKind
            let on: Bool

            func body(content: Content) -> some View {
                if on {
                    let colors = Redesign.kindColors(kind)
                    content
                        .foregroundStyle(.white)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [Color(hex: colors.0), Color(hex: colors.1)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1)))
                        .shadow(color: Color(hex: colors.1, opacity: 0.08), radius: 10, y: 8)
                } else {
                    content
                }
            }
        }
    }

    /// A row on its own card, or plain inside a card of rows
    struct Card: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View { if on { content.rdPanel() } else { content } }
    }

    /// Rows inside one card, with hairlines between them
    struct Divided<Item: Identifiable, Row: View>: View {
        let items: [Item]
        @ViewBuilder let row: (Item) -> Row

        var body: some View {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1) }
                }
            }
        }
    }

    /// A plain tappable row with a symbol, a title and a line under it, for lists of choices and links
    struct LinkRow: View {
        let symbol: String
        let title: String
        var detail: String?
        var value: String?
        var badge: String?
        var tone: IconBox.Tone = .green
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 14) {
                    IconBox(symbol: symbol, tone: tone, small: true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(title).rdText(.cardTitle).multilineTextAlignment(.leading)
                            if let badge { PlusTag(text: badge) }
                        }
                        if let detail {
                            Text(private: detail).rdText(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if let value { Text(private: value).rdText(.detail).foregroundStyle(Theme.muted) }
                    Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(Theme.muted.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 62)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The small "PLUS" mark on a feature that needs Nokael Plus
    struct PlusTag: View {
        var text = "PLUS"
        var body: some View {
            Text(text).rdText(.captionStrong).tracking(0.6)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .foregroundStyle(Theme.amber)
                .background(Theme.amberFill, in: Capsule())
        }
    }

    @MainActor static func footnote(_ text: String) -> some View {
        Text(private: text).rdText(.caption).foregroundStyle(Theme.muted).lineSpacing(3)
    }

    @MainActor static func overline(_ title: String) -> some View {
        Text(title.uppercased()).rdText(.overline).foregroundStyle(Theme.muted)
            .padding(.horizontal, 4).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @MainActor static var hairline: some View { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1) }
}

// MARK: - Home

extension Redesign {
    struct HomeTab: View {
        @Environment(AppModel.self) private var app
        @State private var allTasks = false

        var body: some View {
            let tasks = HomeTask.all(app.snapshot)
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { app.open(.breakdown) } label: { hero }.buttonStyle(.plain)
                        .accessibilityIdentifier("safeToSpend")
                        .overlay(alignment: .topTrailing) { PrivacyToggle().padding(.top, 6).padding(.trailing, 6) }
                    HStack(spacing: 8) {
                        mini("Current cash", "wallet.bifold", app.cash)
                        mini("Reserved", "doc.text", app.reserved)
                    }
                    if app.shortfall > 0 {
                        Button { app.go(.bills) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle")
                                Text(private: "\(app.money(app.shortfall)) still to cover. Review your upcoming bills.")
                                    // Two lines either way, so hiding the amount doesn't pull the page up
                                    .lineLimit(2, reservesSpace: true)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .rdText(.caption).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeading(title: "Needs you", action: tasks.count > 3 ? (allTasks ? "Show fewer" : "Show \(tasks.count - 3) more") : nil) {
                            withAnimation(.snappy) { allTasks.toggle() }
                        }
                        Divided(items: Array(tasks.prefix(allTasks ? tasks.count : 3))) { TaskRow(task: $0) }
                            .rdPanel(padding: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "Upcoming Bills", action: "See all") { app.go(.bills) }
                        .accessibilityIdentifier("seeAllBills")
                    Group {
                        if app.unpaidBills.isEmpty {
                            EmptyNote(text: app.bills.isEmpty ? "No bills yet. Add rent, phone or any regular payment on the Bills tab."
                                      : "All taken care of. No bills due in the next 30 days.")
                        } else {
                            Divided(items: Array(app.unpaidBills.prefix(3))) { BillRow(bill: $0, compact: true) }
                        }
                    }
                    .rdPanel(padding: 14)
                }

                if !app.pinned.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeading(title: "Watching", action: "Budget") { app.go(.budget) }
                        Divided(items: app.pinned) { CategoryRow(category: $0) }
                            .rdPanel(padding: 14)
                    }
                }

                if let card = app.cards.first {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeading(title: app.cards.count > 1 ? "Your Credit Cards" : "Your Credit Card", action: "View card") {
                            app.open(.account(card.id))
                        }
                        CardFaceButton(card: card)
                        Redesign.footnote("Credit is borrowed money, not part of your available cash.").padding(.horizontal, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "Your Accounts", action: "See all") { app.go(.accounts) }
                    Group {
                        if app.accounts.isEmpty {
                            Button { app.open(.newAccount(loan: false)) } label: {
                                EmptyNote(text: "No accounts yet. Add the bank account or cash you spend from.")
                            }
                            .buttonStyle(.plain)
                        } else {
                            Divided(items: Array(app.accounts.prefix(3))) { AccountRow(account: $0, compact: true) }
                        }
                    }
                    .rdPanel(padding: 14)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "Recent Activity", action: "See all") { app.show(.activity) }
                    if app.transactions.isEmpty {
                        EmptyNote(text: "Nothing recorded yet. Tap + to add what you spent or received.")
                    } else {
                        Divided(items: Array(app.transactions.prefix(3))) { TransactionRow(t: $0) }
                    }
                }
            }
        }

        private var hero: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Safe to spend \(app.safePeriodLabel)").rdText(.detailStrong)
                    // Room for the eye, which sits over the card's corner
                    .frame(minHeight: 18)
                HStack(spacing: 10) {
                    if app.setupComplete {
                        app.amount(app.safe).rdText(.display).minimumScaleFactor(0.6).lineLimit(1)
                    } else {
                        Text("—").rdText(.display)
                    }
                    Image(systemName: "info.circle").font(.footnote)
                }
                .padding(.top, 10)
                Text(!app.setupComplete ? "Add an account you spend from to see this."
                     : app.shortfall > 0 ? "Your cash is reserved for upcoming commitments."
                     : app.snapshot.nextIncomeDate == nil ? "Until the end of the month. Add your payday for a truer number."
                     : "Your commitments are covered. This is yours to spend.")
                    .rdText(.caption).lineSpacing(3).frame(maxWidth: 250, alignment: .leading).padding(.top, 10)
                HStack(spacing: 3) { Text("View breakdown"); Image(systemName: "chevron.right") }
                    .rdText(.captionStrong).padding(.top, 12)
            }
            .foregroundStyle(Color(hex: 0x26372B))
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(Hills())
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color(hex: 0xB6BBA8, opacity: 0.3)))
        }

        private func mini(_ label: String, _ symbol: String, _ amount: Decimal) -> some View {
            Button { app.open(.breakdown) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(label, systemImage: symbol).rdText(.caption).foregroundStyle(Theme.muted).labelStyle(TightLabel())
                    app.amount(amount).rdText(.stat).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.secondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// One thing on Home's "Needs you" list, with the one place that settles it
    struct TaskRow: View {
        @Environment(AppModel.self) private var app
        let task: HomeTask

        var body: some View {
            if case .finding(let finding) = task {
                findingRow(finding)
            } else if case .setUp = task {
                // No regular pay or no bills: say so once and it stops asking
                row.contextMenu {
                    Button("Not for me") { try? app.store.updateSettings { $0.dismissedFindings.append(task.id) } }
                }
            } else {
                row
            }
        }

        /// A statement's suggestion: set it up, or say it isn't right
        private func findingRow(_ f: StatementFinding) -> some View {
            let (symbol, tone, title, detail) = look
            return HStack(alignment: .top, spacing: 12) {
                IconBox(symbol: symbol, tone: tone, small: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(private: title).rdText(.cardTitle)
                    Text(private: detail).rdText(.caption).foregroundStyle(Theme.muted)
                    HStack(spacing: 16) {
                        Button("Yes, add it") {
                            do { try app.store.acceptFinding(f, accountId: app.snapshot.accounts.first { $0.spendable }?.id) }
                            catch { app.toast = Toast(message: StoreError.from(error).errorDescription ?? "Couldn't add it.", isError: true) }
                        }
                        .rdText(.label).foregroundStyle(Theme.primary)
                        .accessibilityIdentifier("acceptFinding")
                        Button("Not this") { try? app.store.dismissFinding(f) }
                            .rdText(.label).foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
        }

        private var row: some View {
            let (symbol, tone, title, detail) = look
            return Button(action: run) {
                HStack(spacing: 12) {
                    IconBox(symbol: symbol, tone: tone, small: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(private: title).rdText(.cardTitle).multilineTextAlignment(.leading)
                        Text(private: detail).rdText(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var look: (String, IconBox.Tone, String, String) {
            let s = app.snapshot
            switch task {
            case .bill(let occ):
                let bill = app.bill(occ.id)
                let name = bill.map { app.name(of: $0) } ?? "A bill"
                let state = s.state(of: occ)
                return ("doc.text", state == .overdue ? .alert : .green,
                        state == .overdue ? "\(name) is overdue" : state == .partiallyPaid ? "\(name) is part paid" : "\(name) is due today",
                        "\(app.money(occ.remaining)) to pay. Record the payment once it's made.")
            case .billLink(let suggestion):
                let name = app.hidesDetails ? "a bill" : suggestion.item.name
                return ("link", .green, "Is this your \(name) payment?",
                        "\(app.money(suggestion.payment.amount)) on \(app.day(suggestion.entry.date)). Link it so it isn't counted twice.")
            case .payday(let item, _):
                return ("arrow.down.left", .green, "Payday? Got your \(app.hidesDetails ? "salary" : item.name.lowercased())",
                        "Record it, plan this month's budget and top up your goals in one go.")
            case .overspent(let c, let by):
                return ("exclamationmark.circle", .alert, "\(app.hidesDetails ? "A category" : c.name) is over budget",
                        "\(app.money(by)) more than planned. Move money from another category to cover it.")
            case .noBudget(let cats, let total):
                return ("leaf", .green, "\(app.money(total)) spent with no budget",
                        app.hidesDetails ? "Give those categories a budget." : "In \(cats.prefix(2).map(\.name).joined(separator: " and "))\(cats.count > 2 ? " and more" : ""). Set a budget for them.")
            case .review(let count):
                return ("sparkles", .green, count == 1 ? "1 automatic entry to check" : "\(count) automatic entries to check",
                        "Saved from Apple Pay, a bank message or Siri. Make sure each looks right.")
            case .unplanned(let m):
                return m.isNegative
                    ? ("exclamationmark.circle", .alert, "You've planned \(app.money(m.magnitude)) more than you have", "Lower a budget so the plan fits your money.")
                    : ("leaf", .green, "\(app.money(m)) not planned yet", "Give it a job in your budget, or keep it as spare.")
            case .person(let p, let balance, let due):
                let name = app.accountLabel(p.id)
                let amount = app.money(balance.magnitude)
                if balance.isNegative {
                    return ("person.2", .alert, "Pay \(name) back \(amount)",
                            "You planned to by \(due.map { $0.formatted(.dateTime.day().month()) } ?? "now"). Record it once you have, or pick a new date.")
                }
                if let due {
                    return ("person.2", .alert, "\(name) owes you \(amount)",
                            "They were due to pay it back by \(due.formatted(.dateTime.day().month())). A reminder might help.")
                }
                let since = app.snapshot.lastConfirmed[p.id].map { $0.formatted(.relative(presentation: .named)) } ?? "a while"
                return ("person.2", .green, "\(name) owes you \(amount)", "Nothing has been paid back since \(since).")
            case .stale(let a):
                return ("checkmark.seal", .green, "Check \(app.accountLabel(a.id))'s balance",
                        "It hasn't been checked for a while. Compare it with your bank so safe to spend stays right.")
            case .backup(let never):
                return ("externaldrive", .green, never ? "Save your first backup" : "Time for a fresh backup",
                        "Your money is only on this iPhone. A backup file keeps it safe.")
            case .finding(let f):
                let when = "next on \(app.day(f.nextDate))"
                switch f.kind {
                case .pay:
                    return ("arrow.down.left", .green, "Is \(app.money(f.amount)) your monthly pay?",
                            "Seen in your statement, \(when). Safe to spend will last until payday.")
                case .loan:
                    return ("building.columns", .green, "A loan payment of \(app.money(f.amount))?",
                            "Seen in your statement, \(when). Add it as a monthly bill so it's set aside.")
                case .bill:
                    return ("doc.text", .green, "\(app.hidesDetails ? "A bill" : f.name) every month?",
                            "\(app.money(f.amount)) in each month of your statement, \(when). Add it as a bill.")
                }
            case .setUp(.payday):
                return ("calendar", .green, "Add your payday",
                        "Safe to spend runs to the end of the month until it knows when you're paid.")
            case .setUp(.bills):
                return ("doc.text", .green, "Add your regular bills",
                        "Rent, phone, a loan: they're set aside before you see what's safe to spend.")
            }
        }

        private func run() {
            switch task {
            case .bill(let occ): app.open(.bill(occ.id))
            case .billLink(let s): app.open(.billLink(s.occurrence.id))
            case .payday: app.open(.payday)
            case .overspent(let c, _): app.open(.category(c.id))
            case .noBudget, .unplanned: app.go(.budget)
            case .review: app.open(.review)
            case .person(let p, _, _): app.open(.account(p.id))
            case .stale(let a): app.open(.reconcile(a.id))
            case .backup: app.show(.data)
            case .finding: break
            case .setUp(.payday): app.open(.payday)
            case .setUp(.bills): app.go(.bills)
            }
        }
    }

    /// The eye on Home's safe-to-spend card: the one quick switch for Privacy Mode across the whole app
    struct PrivacyToggle: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { app.privacy.on.toggle() }
            } label: {
                Image(systemName: app.hidesAmounts ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .regular))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Color(hex: 0x26372B))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.hidesAmounts ? "Show amounts" : "Hide amounts")
            .accessibilityHint("Privacy Mode, across the whole app")
            .sensoryFeedback(.selection, trigger: app.privacy.on)
        }
    }

    struct TightLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) { configuration.icon.font(.caption2); configuration.title }
        }
    }

    /// A card drawn as the green card face, opening its page
    struct CardFaceButton: View {
        @Environment(AppModel.self) private var app
        let card: Account

        var body: some View {
            Button { app.open(.account(card.id)) } label: {
                CreditCardFace(balance: app.amount(card.balance), holder: app.isEnhanced ? "" : app.holder,
                               number: app.hidesAccountNames || card.number.isEmpty ? nil : card.number)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.hidesAccountNames ? "Open credit card" : "Open \(card.name)")
        }
    }
}

// MARK: - Accounts

extension Redesign {
    struct AccountsTab: View {
        @Environment(AppModel.self) private var app
        @State private var filter = "All"
        @State private var showArchived = false

        var body: some View {
            let money = app.accounts.filter { $0.kind.holdsMoney }
            let current = money.filter { $0.kind == .bank || $0.kind == .cash }
            let savings = money.filter { $0.kind != .bank && $0.kind != .cash }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Total Cash").rdText(.detail).foregroundStyle(Theme.muted)
                    app.amount(money.reduce(0) { $0 + $1.balance }).rdText(.balance).padding(.top, 8)
                    Button { app.open(.breakdown) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text(private: "\(app.money(app.safe)) safe to spend")
                            Image(systemName: "chevron.right")
                        }
                        .rdText(.caption).foregroundStyle(Theme.primary)
                    }
                    .padding(.top, 12)
                    Text(private: "Net worth \(app.money(app.snapshot.netWorth.total))")
                        .rdText(.caption).foregroundStyle(Theme.muted).padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(light: 0xE8E8E0, dark: 0x30382C), Color(light: 0xEEEDE5, dark: 0x30352C),
                                                    Color(light: 0xF1ECDF, dark: 0x39382F)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if app.accounts.isEmpty {
                    EmptyNote(text: "No accounts yet. Tap + to add the bank account or cash you spend from, or a card or loan.")
                } else {
                    Pills(options: ["All", "Current", "Savings", "Loans", "Cards"], selection: $filter).padding(.vertical, 16)

                    let shown = filter == "Current" ? current : filter == "Savings" ? savings : filter == "All" ? money : []
                    if !shown.isEmpty {
                        if filter == "All" { Redesign.overline("Your money") }
                        VStack(spacing: 8) { ForEach(shown) { AccountRow(account: $0) } }
                    }
                    if ["All", "Loans", "Cards"].contains(filter) {
                        let owed = (filter != "Cards" ? app.loans : []) + (filter != "Loans" ? app.cards : [])
                        if filter == "All" && !owed.isEmpty { Redesign.overline("What you owe").padding(.top, 16) }
                        VStack(spacing: 12) {
                            if filter != "Cards" { ForEach(app.loans) { AccountRow(account: $0) } }
                            if filter != "Loans" { ForEach(app.cards) { CardFaceButton(card: $0) } }
                            if owed.isEmpty && filter != "All" {
                                Button { app.open(.newAccount(loan: true)) } label: {
                                    EmptyNote(text: filter == "Cards" ? "No credit cards. Tap to add one." : "No loans. Tap to add one.")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if filter == "All" && !app.lent.isEmpty {
                        Redesign.overline("People").padding(.top, 16)
                        VStack(spacing: 8) { ForEach(app.lent) { AccountRow(account: $0) } }
                    }
                    if filter == "All" && !app.archivedAccounts.isEmpty {
                        Button { withAnimation(.snappy) { showArchived.toggle() } } label: {
                            HStack {
                                Text("Archived (\(app.archivedAccounts.count))")
                                Spacer()
                                Image(systemName: "chevron.down").rotationEffect(.degrees(showArchived ? 180 : 0))
                            }
                            .rdText(.detail).foregroundStyle(Theme.muted).padding(.horizontal, 4).frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                        if showArchived {
                            Divided(items: app.archivedAccounts) { AccountRow(account: $0, compact: true) }.rdPanel(padding: 14)
                        }
                    }
                }

                Button { app.open(.help) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "leaf").font(.system(size: 26, weight: .light)).foregroundStyle(Theme.primary).frame(width: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("A clearer financial picture").rdText(.cardTitle)
                            Text("Your money and what you owe.\nAlways kept separate.").rdText(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.primary)
                    }
                    .padding(16)
                    .background(Theme.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
        }
    }
}

// MARK: - Budget

extension Redesign {
    struct CategoryRow: View {
        @Environment(AppModel.self) private var app
        let category: Category

        var body: some View {
            Button { app.open(.category(category.id)) } label: {
                HStack(spacing: 12) {
                    IconBox(symbol: category.symbol, tone: category.tone, small: true)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(app.hidesDetails ? "Category" : category.name).rdText(.detailStrong).lineLimit(1)
                            Spacer()
                            (app.amount(category.spent) + Text(private: " / \(app.number(category.budget))").foregroundColor(Theme.muted))
                                .rdText(.caption).monospacedDigit()
                        }
                        ProgressBar(value: category.budget > 0 ? (category.spent / category.budget as NSDecimalNumber).doubleValue : 0)
                        Text(private: status).rdText(.caption).foregroundStyle(category.remaining < 0 ? Theme.destructive : Theme.muted)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var status: String {
            if category.budget <= 0 { return category.spent > 0 ? "No budget set" : "Set a budget" }
            if category.remaining < 0 { return "\(app.money(-category.remaining)) over" }
            return "\(app.money(category.remaining)) remaining"
        }
    }

    struct BudgetTab: View {
        @Environment(AppModel.self) private var app
        @State private var filter = "All"

        var body: some View {
            @Bindable var app = app
            let all = app.categories()
            let total = all.reduce(Decimal(0)) { $0 + max(0, $1.budget) }
            let spent = all.reduce(Decimal(0)) { $0 + $1.spent }
            let share = total > 0 ? min(1, (spent / total as NSDecimalNumber).doubleValue) : 0
            let previous = BudgetMonth.adding(-1, to: app.month, calendar: app.calendar)
            let planned = all.contains { $0.allocated > 0 }
            let previousPlanned = app.categories(in: previous).contains { $0.allocated > 0 }

            VStack(alignment: .leading, spacing: 0) {
                Menu {
                    Picker("Month", selection: $app.month) {
                        ForEach(months, id: \.self) { key in Text(label(key)).tag(key) }
                    }
                } label: {
                    HStack {
                        Text(app.monthStart.formatted(.dateTime.month(.wide).year())).rdText(.body)
                        Spacer()
                        HStack(spacing: 4) { Text(app.isThisMonth ? "This month" : "Change month"); Image(systemName: "chevron.down") }
                            .rdText(.caption).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.foreground)
                    .rdPanel(padding: 14)
                }
                .accessibilityLabel("Month, \(label(app.month))")

                if all.isEmpty {
                    VStack(spacing: 12) {
                        EmptyNote(text: "No categories yet. Start with common ones like groceries and rent, then rename or add your own.")
                        Button("Use starter categories") { app.attempt(closing: false) { try app.store.addStarterCategories() } }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.top, 16)
                } else {
                    HStack(spacing: 22) {
                        ZStack {
                            Circle().stroke(Theme.border, lineWidth: 10)
                            Circle().trim(from: 0, to: app.hidesCharts ? 0 : share)
                                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 2) {
                                Text(app.percent(share)).rdText(.balance)
                                Text("Spent").rdText(.detail).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(width: 150, height: 150)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(app.hidesCharts ? "Budget progress hidden" : "\(Int((share * 100).rounded())) percent of budget spent")

                        VStack(alignment: .leading, spacing: 16) {
                            stat("Total Budget", total)
                            stat("Spent", spent)
                            stat("Remaining", total - spent)
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 4)

                    if !planned && previousPlanned {
                        Button("Copy last month's plan") {
                            app.attempt("Last month's budget copied.", closing: false) { try app.store.copyPlan(from: previous, to: app.month) }
                        }
                        .buttonStyle(QuietButtonStyle())
                        .padding(.bottom, 16)
                    }
                    attention(all)

                    Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 1).padding(.bottom, 16)
                    SectionHeading(title: "Spending by Category", action: "New category") { app.open(.newCategory) }
                    Pills(options: BudgetFilter.allCases.map(\.title), selection: $filter).padding(.bottom, 8)
                    let filtered = shown(all)
                    let groups = Dictionary(grouping: filtered, by: \.group)
                    let order = app.snapshot.expenseCategoryGroups.map(\.name)
                    ForEach(order.filter { groups[$0] != nil }, id: \.self) { group in
                        if groups.count > 1 { Redesign.overline(group).padding(.top, 12) }
                        Divided(items: groups[group] ?? []) { CategoryRow(category: $0) }
                    }
                    if filtered.isEmpty { EmptyNote(text: "No categories match. Choose All to see every one.") }
                    Redesign.footnote("Your budget is a plan, not available cash. Bills are included in their categories, never counted twice. Not planned yet: \(app.money(app.unallocated)).")
                        .padding(.top, 20)
                }

                SavingsSection().padding(.top, 28)
            }
        }

        private var months: [String] {
            (-12...1).map { BudgetMonth.adding($0, to: app.snapshot.monthKey, calendar: app.calendar) }.reversed()
        }

        private func label(_ key: String) -> String {
            (BudgetMonth.start(of: key, calendar: app.calendar) ?? app.today).formatted(.dateTime.month(.wide).year())
        }

        private func shown(_ all: [Category]) -> [Category] {
            let chosen = BudgetFilter.allCases.first { $0.title == filter } ?? .all
            return all.filter { chosen.matches(app.snapshot.budget.line($0.id, month: app.month)) }
        }

        /// One line for what most needs fixing: overspending first, then spending with no budget
        @ViewBuilder private func attention(_ all: [Category]) -> some View {
            let over = all.filter { $0.budget > 0 && $0.remaining < 0 }
            let unbudgeted = all.filter { $0.budget <= 0 && $0.spent > 0 }
            let firstJob = all.allSatisfy { $0.budget <= 0 }
            if let first = over.first ?? unbudgeted.first ?? (firstJob ? all.first : nil) {
                Button { app.open(.category(first.id)) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: over.isEmpty && unbudgeted.isEmpty ? "leaf" : "exclamationmark.circle")
                            .foregroundStyle(over.isEmpty ? Theme.primary : Theme.destructive)
                        Text(private: !over.isEmpty ? "\(over.count == 1 ? (app.hidesDetails ? "A category" : first.name) + " is" : "\(over.count) categories are") over budget. Fix it."
                             : !unbudgeted.isEmpty ? "\(app.money(unbudgeted.reduce(0) { $0 + $1.spent })) spent with no budget. Set one."
                             : "Set budgets for your main costs first. Start with \(app.hidesDetails ? "your first category" : first.name).")
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .rdText(.caption).foregroundStyle(Theme.foreground)
                    .padding(14)
                    .background(Theme.secondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
            }
        }

        private func stat(_ label: String, _ value: Decimal) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).rdText(.caption).foregroundStyle(Theme.muted)
                app.amount(value).rdText(.stat).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    /// Goals and money set aside, at the end of Budget
    struct SavingsSection: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            let s = app.snapshot
            let setAside = s.reserves.filter { !$0.isGoal }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Savings").rdText(.section)
                    Spacer()
                    Menu {
                        Button("Savings goal") { newGoal() }
                        Button("Money set aside") { app.open(.reserve(nil, goal: false)) }
                    } label: {
                        Text("Add").rdText(.detail).foregroundStyle(Theme.primary).frame(minHeight: 32)
                    }
                    .accessibilityLabel("Add savings")
                }
                .padding(.bottom, 4)
                if s.goals.isEmpty && setAside.isEmpty {
                    Button(action: newGoal) {
                        HStack(spacing: 14) {
                            Image(systemName: "flag").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.primary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start a savings goal").rdText(.cardTitle)
                                Text("Save towards something, and see what to put aside each month.").rdText(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote)
                        }
                        .padding(16)
                        .background(Theme.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("startGoal")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(s.goals.enumerated()), id: \.element.id) { i, goal in
                            GoalRow(goal: goal)
                            if i < s.goals.count - 1 || !setAside.isEmpty { Redesign.hairline }
                        }
                        ForEach(Array(setAside.enumerated()), id: \.element.id) { i, reserve in
                            Button { app.open(.reserve(reserve.id, goal: false)) } label: {
                                HStack(spacing: 12) {
                                    IconBox(symbol: "lock", small: true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.hidesDetails ? "Set aside" : reserve.name).rdText(.cardTitle)
                                        Text("Kept in \(app.accountLabel(reserve.accountId)) · not safe to spend").rdText(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    app.amount(reserve.amount.decimal).rdText(.amount)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if i < setAside.count - 1 { Redesign.hairline }
                        }
                    }
                    .rdPanel(padding: 14)
                }
            }
        }

        private func newGoal() {
            // A few goals are free; more come with Plus
            if app.isPlus || app.snapshot.goals.count < FreePlan.goals { app.open(.reserve(nil, goal: true)) } else { app.open(.paywall(.goals)) }
        }
    }

    struct GoalRow: View {
        @Environment(AppModel.self) private var app
        let goal: Reserve

        var body: some View {
            let progress = app.snapshot.progress(of: goal)
            Button { app.open(.goal(goal.id)) } label: {
                HStack(spacing: 12) {
                    IconBox(symbol: "flag", small: true)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(app.hidesDetails ? "Goal" : goal.name).rdText(.detailStrong)
                            Spacer()
                            (app.amount(goal.amount.decimal) + Text(private: " / \(app.number(goal.target?.decimal ?? 0))").foregroundColor(Theme.muted))
                                .rdText(.caption)
                        }
                        ProgressBar(value: progress?.fraction ?? 0)
                        Text(private: progress.map { GoalRow.advice($0, app: app) } ?? "").rdText(.caption).foregroundStyle(Theme.muted)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        @MainActor static func advice(_ p: GoalProgress, app: AppModel) -> String {
            switch p.status {
            case .reached: "Goal reached"
            case .needsPerMonth(let m, let months): "Save \(app.money(m)) a month · \(months) month\(months == 1 ? "" : "s") left"
            case .noDate: "\(app.money(p.remaining)) to go"
            case .pastDue: "The date has passed · \(app.money(p.remaining)) to go"
            }
        }
    }
}

// MARK: - Bills

extension Redesign {
    struct BillsTab: View {
        @Environment(AppModel.self) private var app
        @State private var filter = "Upcoming"

        var body: some View {
            let horizon = app.calendar.date(byAdding: .day, value: 45, to: app.today) ?? app.today
            let monthsAgo = app.calendar.date(byAdding: .month, value: -2, to: app.today) ?? app.today
            let shown = app.bills.filter {
                switch filter {
                case "Upcoming": return $0.isOpen && $0.due <= horizon
                case "Paid": return ($0.status == .paid || $0.status == .skipped) && $0.due >= monthsAgo
                case "Overdue": return $0.status == .overdue
                default: return $0.due <= horizon && ($0.isOpen || $0.due >= monthsAgo)
                }
            }
            let income = app.expectedIncome.filter { $0.isOpen && $0.due <= horizon }
            VStack(alignment: .leading, spacing: 0) {
                Pills(options: ["Upcoming", "Paid", "All", "Overdue"], selection: $filter)
                Text(private: "\(app.money(app.safeToSpend.obligationsTotal)) reserved for unpaid commitments")
                    .rdText(.caption).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.vertical, 16)
                VStack(spacing: 8) {
                    ForEach(filter == "Paid" ? shown.reversed() : shown) { BillRow(bill: $0) }
                    if shown.isEmpty {
                        EmptyNote(text: app.bills.isEmpty ? "No bills yet. Tap + to add rent, a phone plan or anything you pay regularly."
                                  : filter == "Paid" ? "No paid bills yet. Record or link a payment to get started."
                                  : filter == "Overdue" ? "Nothing overdue. A little peace of mind."
                                  : "All caught up. No bills need your attention.")
                    }
                }
                if !income.isEmpty {
                    SectionHeading(title: "Expected income").padding(.top, 24)
                    VStack(spacing: 8) { ForEach(Array(income.prefix(4))) { BillRow(bill: $0) } }
                }
                Button { app.open(.schedules) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "calendar.badge.checkmark").font(.system(size: 26, weight: .light)).foregroundStyle(Theme.primary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your regular bills and income").rdText(.cardTitle)
                            Text("Change amounts and dates, or stop one.").rdText(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote)
                    }
                    .padding(20)
                    .background(Theme.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
                Redesign.footnote("Record payments you've made, or link an existing transaction.\nNo bank payment is initiated.")
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 16)
            }
        }
    }
}

// MARK: - Activity

extension Redesign {
    struct ActivityTab: View {
        @Environment(AppModel.self) private var app
        @State private var query = ""
        @State private var type = "All"
        @State private var dateFilter = "All dates"
        @State private var accountFilter: UUID?
        @State private var show = "Everything"
        @State private var limit = 100

        var body: some View {
            let monthName = app.today.formatted(.dateTime.month(.wide).year())
            let toReview = app.transactions.filter(\.needsReview)
            let base = show == "Deleted" ? app.allTransactions.filter(\.voided) : show == "To review" ? toReview : app.transactions
            let shown = base.filter { t in
                // Searches only what's on screen, so hidden names can't be found by typing them
                (query.isEmpty || "\(app.name(of: t)) \(app.category(of: t)) \(app.hidesDetails ? "" : t.note) \(app.accountLabel(t.accountId))"
                    .localizedCaseInsensitiveContains(query))
                    && (type == "All" || (type == "Income" && t.flow == .in && t.kind != .transfer)
                        || (type == "Expenses" && t.flow == .out) || (type == "Transfers" && t.kind == .transfer))
                    && (accountFilter == nil || t.accountId == accountFilter || t.destinationId == accountFilter)
                    && (dateFilter == "All dates"
                        || (dateFilter == "Today" ? app.calendar.isDate(t.date, inSameDayAs: app.today)
                            : app.calendar.isDate(t.date, equalTo: app.today, toGranularity: .month)))
            }
            let scheduled = Array(app.allBills.filter(\.isOpen).prefix(30))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search transactions...", text: $query).rdText(.body).submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark").font(.caption) }.accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
                .background(Theme.secondary.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Pills(options: ["All", "Income", "Expenses", "Transfers"], selection: $type)

                if !toReview.isEmpty && show != "To review" {
                    Button { show = "To review" } label: {
                        Label("\(toReview.count) automatic \(toReview.count == 1 ? "entry" : "entries") to check", systemImage: "sparkles")
                            .rdText(.captionStrong).foregroundStyle(Theme.primary).frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }

                if app.showFilters || show != "Everything" {
                    HStack(spacing: 8) {
                        menu($dateFilter, ["All dates", "Today", monthName]) { $0 }
                        menu($accountFilter, [nil] + (app.accounts + app.archivedAccounts).map { Optional($0.id) }) {
                            $0 == nil ? "All accounts" : app.accountLabel($0)
                        }
                        menu($show, ["Everything", "To review", "Scheduled", "Deleted"]) { $0 }
                    }
                }

                if show == "Scheduled" {
                    VStack(spacing: 8) { ForEach(scheduled) { BillRow(bill: $0) } }
                    if scheduled.isEmpty { EmptyNote(text: "Nothing scheduled. Add bills and expected income on the Bills tab.") }
                } else {
                    VStack(spacing: 0) {
                        Divided(items: Array(shown.prefix(limit))) { TransactionRow(t: $0) }
                        if shown.count > limit {
                            Button("Show more") { limit += 200 }.buttonStyle(QuietButtonStyle()).padding(.top, 12)
                        }
                        if shown.isEmpty {
                            EmptyNote(text: app.transactions.isEmpty ? "Nothing recorded yet. Tap + to add what you spent or received."
                                      : "No matching transactions. Try another search or filter.")
                        }
                    }
                }

                Redesign.footnote("Transfers between your accounts aren't income or spending.")
                    .frame(maxWidth: .infinity).padding(.top, 12)
            }
        }

        private func menu<Value: Hashable>(_ value: Binding<Value>, _ options: [Value], shown: @escaping (Value) -> String) -> some View {
            Menu {
                Picker("", selection: value) { ForEach(options, id: \.self) { Text(shown($0)).tag($0) } }
            } label: {
                HStack {
                    Text(shown(value.wrappedValue)).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .rdText(.caption)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
            }
            .foregroundStyle(Theme.foreground)
        }
    }
}
