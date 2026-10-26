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
    @State private var unlocked = false

    var body: some View {
        Group {
            if !store.settings.onboardingDone {
                OnboardingView()
            } else if store.settings.biometricLock && !unlocked {
                LockView(unlock: authenticate)
            } else {
                #if DEBUG
                // Screenshot helper: -screen forecast|reports|settings|add|import|paywall
                if UserDefaults.standard.string(forKey: "screen") == "forecast" {
                    NavigationStack { ForecastView() }
                } else if UserDefaults.standard.string(forKey: "screen") == "reports" {
                    NavigationStack { ReportsView() }
                } else if UserDefaults.standard.string(forKey: "screen") == "settings" {
                    SettingsView()
                } else if UserDefaults.standard.string(forKey: "screen") == "add" {
                    EntryEditor(kind: .expense)
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
        .environment(\.selectTab, SelectTabAction { tab = $0 })
        .sheet(item: $adding) { kind in
            EntryEditor(kind: kind)
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

struct SelectTabAction {
    let select: (AppTab) -> Void
    func callAsFunction(_ tab: AppTab) { select(tab) }
}

extension EnvironmentValues {
    @Entry var addEntry = AddEntryAction { _ in }
    @Entry var selectTab = SelectTabAction { _ in }
}

/// The + button in every tab's toolbar
struct GlobalAddButton: ToolbarContent {
    @Environment(\.addEntry) private var addEntry

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(AddKind.allCases) { kind in
                    Button { addEntry(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                }
            } label: {
                Image(systemName: "plus").font(.body.weight(.semibold))
            } primaryAction: {
                addEntry(.expense)
            }
            .accessibilityLabel("Add")
            .accessibilityHint("Tap to add an expense, hold for income, transfer or adjustment")
            .accessibilityIdentifier("globalAdd")
        }
    }
}
