//
//  RootView.swift
//  Nokael Money
//

import SwiftUI
import LocalAuthentication
import NokaelCore

/// What the global Add button can create
enum AddKind: String, Identifiable, CaseIterable {
    case expense, income, transfer, adjustment
    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        case .adjustment: return "Balance adjustment"
        }
    }

    var symbol: String {
        switch self {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .adjustment: return "slider.horizontal.3"
        }
    }
}

enum AppTab: Hashable { case home, budget, activity, accounts, plan }

struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .home
    @State private var adding: AddKind?
    @State private var choosing: ChooseRequest?
    @AppStorage("seenTour") private var seenTour = false
    @State private var showingTour = false
    @State private var unlocked = false

    var body: some View {
        Group {
            if !store.settings.onboardingDone {
                OnboardingView()
            } else if store.settings.biometricLock && !unlocked {
                LockView(unlock: authenticate)
            } else {
                #if DEBUG
                // Screenshot helper: -screen forecast|reports|payday|tour|choose|guide [-ask <text>]|capture|settings|add|import|paywall|ask
                if UserDefaults.standard.string(forKey: "screen") == "forecast" {
                    NavigationStack { ForecastView() }
                } else if UserDefaults.standard.string(forKey: "screen") == "reports" {
                    NavigationStack { ReportsView() }
                } else if UserDefaults.standard.string(forKey: "screen") == "payday" {
                    PaydaySheet()
                } else if UserDefaults.standard.string(forKey: "screen") == "tour" {
                    WelcomeTour()
                } else if UserDefaults.standard.string(forKey: "screen") == "choose" {
                    AddChooser()
                } else if UserDefaults.standard.string(forKey: "screen") == "guide" {
                    GuideView(initialQuestion: UserDefaults.standard.string(forKey: "ask") ?? "")
                } else if UserDefaults.standard.string(forKey: "screen") == "capture" {
                    NavigationStack { CaptureSetupView() }
                } else if UserDefaults.standard.string(forKey: "screen") == "settings" {
                    SettingsView()
                } else if UserDefaults.standard.string(forKey: "screen") == "add" {
                    EntryEditor(kind: UserDefaults.standard.string(forKey: "addKind") == "income" ? .income : .expense)
                } else if UserDefaults.standard.string(forKey: "screen") == "ask" {
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, *) { AskMoneyView() }
                    #endif
                } else if UserDefaults.standard.string(forKey: "screen") == "debtpay",
                          let paid = store.snapshot.entryRecords.first(where: { $0.kind == .debtPayment && $0.status == .posted }) {
                    EntryDetailView(record: paid)
                } else if UserDefaults.standard.string(forKey: "screen") == "loan" {
                    NewLoanSheet()
                } else if UserDefaults.standard.string(forKey: "screen") == "paywall" {
                    PaywallView(feature: .statementImport)
                } else if UserDefaults.standard.string(forKey: "screen") == "import",
                          let account = store.snapshot.accounts.first(where: \.spendable) {
                    ImportStatementView(accountId: account.id)
                } else {
                    tabs
                }
                #else
                tabs
                #endif
            }
        }
        .task(id: store.revision) {
            WidgetSync.update(store.snapshot, isPlus: plus.isPlus)
            await BillReminders.sync(store.snapshot)
        }
        .onChange(of: plus.isPlus) { _, isPlus in WidgetSync.update(store.snapshot, isPlus: isPlus) }
        .onAppear {
            NotificationRouter.openPlan = { tab = .plan }
            store.extendSchedules()
            #if DEBUG
            // Screenshot helper: -tab budget|activity|accounts|plan
            if let t = UserDefaults.standard.string(forKey: "tab") {
                tab = ["budget": .budget, "activity": .activity, "accounts": .accounts, "plan": .plan][t] ?? .home
            }
            // Capture helper: -captureSMS "<message>" and -captureApplePay "card|merchant|amount"
            Task { await debugCaptures() }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.extendSchedules() }
            if phase == .background { unlocked = false }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeView().tag(AppTab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }
            BudgetView().tag(AppTab.budget)
                .tabItem { Label("Budget", systemImage: "chart.pie.fill") }
            ActivityView().tag(AppTab.activity)
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle.fill") }
            AccountsView().tag(AppTab.accounts)
                .tabItem { Label("Accounts", systemImage: "building.columns.fill") }
            PlanView().tag(AppTab.plan)
                .tabItem { Label("Plan", systemImage: "calendar") }
        }
        .environment(\.addEntry, AddEntryAction { adding = $0 })
        .environment(\.chooseAdd, ChooseAddAction { choosing = ChooseRequest(focus: $0) })
        .environment(\.selectTab, SelectTabAction { tab = $0 })
        .sheet(item: $adding) { kind in
            EntryEditor(kind: kind)
        }
        .sheet(item: $choosing) { request in
            AddChooser(focus: request.focus)
        }
        .sheet(isPresented: $showingTour, onDismiss: { seenTour = true }) { WelcomeTour() }
        .onAppear {
            let args = CommandLine.arguments
            let automated = args.contains("-uiTesting") || args.contains("-demoData") || args.contains("-screenshots")
            if !seenTour && !automated { showingTour = true }
        }
    }

    #if DEBUG
    private func debugCaptures() async {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "screen") == "debtpay",
           !store.snapshot.entryRecords.contains(where: { $0.kind == .debtPayment }),
           let loan = store.snapshot.debts.first(where: { $0.kind == .loan }) ?? store.snapshot.debts.first,
           let bank = store.snapshot.accounts.first(where: \.spendable) {
            let owed = store.snapshot.owed(loan.id)
            let interest = DebtCalculator.monthlyInterest(owed: owed, annualRateBps: loan.debtRateBps ?? 500)
            _ = try? store.payDebt(loan.id, from: bank.id, amount: Money(1500, currency: store.currency), interest: interest,
                                   fees: .zero(store.currency), date: store.now(), key: UUID())
        }
        if let pay = defaults.string(forKey: "captureApplePay") {
            let parts = pay.split(separator: "|").map(String.init)
            if parts.count == 3, let amount = Decimal(string: parts[2]) {
                let capture = Capture(source: .applePay, direction: .spent, amount: Money(amount, currency: store.currency),
                                      merchant: parts[1], cardHint: parts[0], date: store.now().addingTimeInterval(-120), text: pay)
                let outcome = try? await CaptureService.record(capture, in: store, isPlus: plus.isPlus)
                print("captureApplePay:", outcome.map { "\($0)" } ?? "error")
            }
        }
        if let text = defaults.string(forKey: "captureSMS") {
            if let capture = await CaptureService.read(message: text, homeCurrency: store.currency, date: store.now()) {
                let outcome = try? await CaptureService.record(capture, in: store, isPlus: plus.isPlus)
                print("captureSMS:", outcome.map { "\($0)" } ?? "error")
            } else {
                print("captureSMS: not a transaction")
            }
        }
    }
    #endif

    private func authenticate() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Nokael Money") { success, _ in
            Task { @MainActor in unlocked = success }
        }
    }
}

struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Nokael Money is locked").font(.title3.bold())
            Button("Unlock", action: unlock).buttonStyle(.borderedProminent)
        }
        .onAppear(perform: unlock)
    }
}

// MARK: - Environment actions

struct AddEntryAction {
    let open: (AddKind) -> Void
    func callAsFunction(_ kind: AddKind) { open(kind) }
}

struct ChooseRequest: Identifiable {
    let id = UUID()
    let focus: AddChooser.Focus?
}

/// Opens "What happened?", optionally straight at paying a loan
struct ChooseAddAction {
    let open: (AddChooser.Focus?) -> Void
    func callAsFunction(_ focus: AddChooser.Focus? = nil) { open(focus) }
}

struct SelectTabAction {
    let select: (AppTab) -> Void
    func callAsFunction(_ tab: AppTab) { select(tab) }
}

extension EnvironmentValues {
    @Entry var addEntry = AddEntryAction { _ in }
    @Entry var selectTab = SelectTabAction { _ in }
    @Entry var chooseAdd = ChooseAddAction { _ in }
}

/// The Add button in every tab's toolbar: asks what happened
struct GlobalAddButton: ToolbarContent {
    @Environment(\.chooseAdd) private var chooseAdd

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { chooseAdd() } label: {
                Text("\(Image(systemName: "plus")) Add").font(.body.weight(.semibold))
            }
            .accessibilityLabel("Add")
            .accessibilityHint("Add money spent, received, a loan payment and more")
            .accessibilityIdentifier("globalAdd")
        }
    }
}
