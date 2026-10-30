//
//  RootView.swift
//  Nokael Money
//

import SwiftUI
import LocalAuthentication
import NokaelCore

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
    @State private var showingBills = false
    @State private var router = AppRouter.shared

    var body: some View {
        Group {
            if !store.settings.onboardingDone {
                OnboardingView().tint(Palette.brand)
            } else if store.settings.biometricLock && !unlocked {
                LockView(unlock: authenticate)
            } else {
                #if DEBUG
                // Screenshot helper: -screen forecast|reports|payday|tour|choose|guide [-ask <text>]|capture|settings|add|import|paywall|ask
                if UserDefaults.standard.string(forKey: "screen") == "forecast" {
                    NavigationStack { ForecastView() }
                } else if UserDefaults.standard.string(forKey: "screen") == "reports" {
                    ReportsView()
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
        .onAppear {
            #if DEBUG
            // Screenshot helper: -tab budget|activity|accounts|reports
            if let t = UserDefaults.standard.string(forKey: "tab") {
                tab = ["budget": .budget, "activity": .activity, "accounts": .accounts, "reports": .reports][t] ?? .home
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
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
            ReportsView().tag(AppTab.reports)
                .tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }
        }
        .tint(Palette.brand)
        .environment(\.addEntry, AddEntryAction { adding = $0 })
        .environment(\.chooseAdd, ChooseAddAction { choosing = ChooseRequest(focus: $0) })
        .environment(\.selectTab, SelectTabAction { tab = $0 })
        .sheet(item: $adding) { kind in
            EntryEditor(kind: kind)
        }
        .sheet(item: $choosing) { request in
            AddChooser(focus: request.focus)
        }
        .sheet(isPresented: $showingBills) { NavigationStack { BillsView() } }
        .sheet(isPresented: $showingTour, onDismiss: { seenTour = true }) { WelcomeTour() }
        .onChange(of: router.pending, initial: true) { _, route in
            guard let route else { return }
            switch route {
            case .tab(let t): tab = t
            case .bills: tab = .home; showingBills = true
            }
            router.pending = nil
        }
        .onAppear {
            let args = CommandLine.arguments
            let automated = args.contains("-uiTesting") || args.contains("-demoData") || args.contains("-screenshots")
            if !seenTour && !automated { showingTour = true }
        }
    }

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

/// One Add, floating above the tab bar on iOS 26; in the toolbar before that
/// Add, top right on every main screen: one place to put money in or out
struct GlobalAddButton: ToolbarContent {
    @Environment(\.chooseAdd) private var chooseAdd

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { chooseAdd() } label: { Image(systemName: "plus").font(.body.weight(.semibold)) }
                .accessibilityLabel("Add")
                .accessibilityHint("Add money spent, received, a loan payment and more")
                .accessibilityIdentifier("globalAdd")
        }
    }
}
