//
//  RedesignRoot.swift
//  Nokael Money
//
//  The app's shell: onboarding and the lock, Home's header, each tab's title,
//  the floating glass tab bar, the pushed pages, the sheets and the
//  confirmation with Undo.
//

import SwiftUI
import LocalAuthentication
import NokaelCore

extension Redesign {
    /// The app: onboarding until it's set up, the lock while Face ID is on, then the tabs
    struct AppRoot: View {
        @State private var app: AppModel
        @State private var router = AppRouter.shared
        @State private var unlocked = false
        @State private var showingTour = false
        @AppStorage("seenTour") private var seenTour = false
        @Environment(\.scenePhase) private var phase

        init(store: LedgerStore, plus: PlusStore) {
            _app = State(initialValue: AppModel(store: store, plus: plus))
        }

        var body: some View {
            Group {
                if !app.store.settings.onboardingDone {
                    Onboarding()
                } else if app.store.settings.biometricLock && !unlocked {
                    LockScreen(unlock: authenticate)
                } else {
                    shell
                }
            }
            .foregroundStyle(Theme.foreground)
            .tint(Theme.primary)
            .environment(app)
            .preferredColorScheme(app.dark.map { $0 ? .dark : .light })
            .onChange(of: phase) { _, now in if now == .background { unlocked = false } }
        }

        private var shell: some View {
            @Bindable var app = app
            return NavigationStack(path: $app.pages) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if app.tab == .home { HomeHeader() } else { TabHeader() }
                        Group {
                            switch app.tab {
                            case .home: HomeTab()
                            case .accounts: AccountsTab()
                            case .budget: BudgetTab()
                            case .bills: BillsTab()
                            case .more: MoreTab()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                        .id(app.tab)
                    }
                }
                .safeAreaPadding(.bottom, app.barHeight)
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Page.self) { PageScreen(page: $0) }
            }
            .overlay {
                if app.actionsOpen {
                    Rectangle().fill(.black.opacity(0.25)).ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { app.actionsOpen = false } }
                        .transition(.opacity)
                        .accessibilityLabel("Close quick actions")
                        .accessibilityAddTraits(.isButton)
                }
            }
            // The bar floats over the page rather than insetting it: an inset doesn't always reach the scroll
            // views inside the navigation stack, which left the last rows stuck under the bar on some phones
            .overlay(alignment: .bottom) {
                VStack(alignment: .trailing, spacing: 12) {
                    if app.createAction != nil { CreateButton().transition(.scale(scale: 0.6).combined(with: .opacity)) }
                    GlassTabBar()
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: app.createAction)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { app.barHeight = $0 + 12 }
            }
            .overlay(alignment: .top) { ToastView() }
            .modifier(PrivacyCover())
            .sheet(item: $app.sheet) { first in
                SheetStack(first: first)
                    .environment(app)
                    .environment(app.store)
                    .environment(app.plus)
                    .preferredColorScheme(app.dark.map { $0 ? .dark : .light })
            }
            .sheet(isPresented: $showingTour, onDismiss: { seenTour = true }) {
                WelcomeTour().environment(app)
            }
            .onChange(of: router.pending, initial: true) { _, route in
                guard let route else { return }
                switch route {
                case .bills: app.go(.bills)
                case .entry(let id): app.open(.transaction(id))
                case .addExpense(let memo):
                    var draft = DraftEntry()
                    draft.memo = memo
                    app.draft = draft
                    app.open(.entry(.expense))
                case .payday: app.go(.home); app.open(.payday)
                case .forecast: app.go(.home); app.show(.forecast)
                case .backup: app.go(.more); app.show(.data)
                case .importStatement: app.go(.accounts); app.open(.importStatement(nil))
                case .person(let id): app.open(.account(id))
                case .tab(let t):
                    switch t {
                    case .home: app.go(.home)
                    case .budget: app.go(.budget)
                    case .accounts: app.go(.accounts)
                    case .activity: app.go(.home); app.show(.activity)
                    case .reports: app.go(.home); app.show(.reports)
                    }
                }
                router.pending = nil
            }
            .onAppear {
                let args = CommandLine.arguments
                let automated = args.contains("-uiTesting") || args.contains("-demoData") || args.contains("-screenshots")
                if !seenTour && !automated { showingTour = true }
                #if DEBUG
                DebugScreens.open(in: app)
                #endif
            }
        }

        private func authenticate() {
            // The async form: iOS answers on a background thread, which a reply closure here would crash on
            Task { @MainActor in
                let context = LAContext()
                let success = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Nokael Money")) ?? false
                unlocked = success
            }
        }
    }

    /// Home's one-row header: the greeting and name on the left, Intelligence and Help on the right, the date beneath
    struct HomeHeader: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            // Redrawn each minute so the greeting and date turn over on their own
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            let name = app.holder.trimmingCharacters(in: .whitespaces)
                            let greeting = app.greeting(at: context.date)
                            Text(name.isEmpty ? String(greeting.dropLast()) : greeting)
                                .rdText(.body).foregroundStyle(Theme.muted)
                            if !name.isEmpty {
                                Text(name).rdText(.title)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        HStack(spacing: 8) {
                            Button { app.open(.intelligence) } label: {
                                HStack(spacing: 6) {
                                    IntelligenceMark(size: 22)
                                    Text("Intelligence").rdText(.detailStrong).lineLimit(1)
                                }
                                .padding(.leading, 8).padding(.trailing, 12)
                                .frame(minHeight: 44)
                                .background(Theme.card, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border.opacity(0.7)))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Apple Intelligence financial insights")
                            Button { app.open(.help) } label: {
                                Image(systemName: "questionmark").font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.card, in: Circle())
                                    .overlay(Circle().stroke(Theme.border.opacity(0.7)))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Help")
                        }
                        .fixedSize()
                    }
                    HStack(spacing: 8) {
                        Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .rdText(.caption).foregroundStyle(Theme.muted)
                        PrivacyBadge()
                    }
                    .animation(.easeInOut(duration: 0.2), value: app.isEnhanced)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
    }

    struct TabHeader: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    if app.tab == .budget {
                        Button { withAnimation { app.tab = .home } } label: {
                            Image(systemName: "chevron.left").font(.title3.weight(.light)).frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Home")
                    }
                    Text(app.tab.rawValue)
                        .rdText(.title)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                PrivacyBadge().frame(minHeight: 44)
                // Adding lives on the floating +, so only Budget keeps a button here
                if app.tab == .budget {
                    Button {
                        if let top = app.categories().max(by: { $0.spent < $1.spent }) { app.open(.category(top.id)) } else { app.open(.newCategory) }
                    } label: {
                        Image(systemName: "chart.bar").font(.title3.weight(.light)).frame(width: 44, height: 44)
                    }
                    .foregroundStyle(Theme.primary)
                    .accessibilityLabel("Edit category budgets")
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }

    struct Avatar: View {
        let name: String
        var size: CGFloat = 40
        var body: some View {
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(LinearGradient(colors: [Color(hex: 0x8C9B7E), Color(hex: 0x354E3C)], startPoint: .top, endPoint: .bottom),
                            in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: Color(hex: 0xE6E3DA), radius: 0.5)
        }
    }

    /// The floating capsule at the bottom, with the chosen tab lifted out in glass
    struct GlassTabBar: View {
        @Environment(AppModel.self) private var app
        @Environment(\.colorScheme) private var scheme
        @Namespace private var glass

        private var dark: Bool { scheme == .dark }

        var body: some View {
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    let selected = app.tab == tab
                    Button {
                        // Any tab, including the current one, comes back to its top screen
                        app.pages = []
                        app.actionsOpen = false
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { app.tab = tab }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: selected && tab == .home ? "house.fill" : tab.symbol)
                                .font(.system(size: 19, weight: selected ? .semibold : .regular))
                            Text(tab.rawValue).rdText(.nav).fontWeight(selected ? .semibold : .medium)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(selected ? Theme.primary : Theme.foreground.opacity(0.6))
                        .background {
                            if selected {
                                Capsule().fill(.white.opacity(dark ? 0.1 : 0.55))
                                    .overlay(Capsule().stroke(.white.opacity(dark ? 0.1 : 0.6)))
                                    .matchedGeometryEffect(id: "selection", in: glass)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(6)
            .background(.ultraThinMaterial, in: Capsule())
            .background(dark ? Color(hex: 0x252D24, opacity: 0.6) : .white.opacity(0.3), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(dark ? 0.15 : 0.7), lineWidth: 1))
            .shadow(color: dark ? .black.opacity(0.25) : Color(hex: 0x26342A, opacity: 0.1), radius: 16, y: 8)
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
        }
    }

    /// The one floating + above the tab bar. It fans out the screen's own thing to add (an account, a category,
    /// a bill) above an expense, income and transfer, and turns into a close button while open.
    struct CreateButton: View {
        @Environment(AppModel.self) private var app

        private struct Item: Identifiable {
            let label: String
            let symbol: String
            var warm = false
            let sheet: Sheet
            var id: String { label }
        }

        private static let transactions = [
            Item(label: "Add Expense", symbol: "basket", warm: true, sheet: .entry(.expense)),
            Item(label: "Add Income", symbol: "arrow.down.left", sheet: .entry(.income)),
            Item(label: "Transfer Money", symbol: "arrow.up.arrow.down", sheet: .entry(.transfer)),
        ]

        /// The screen's own job on top, then the three transactions, so those are always in the same place
        private var items: [Item] {
            let own: [Item] = switch app.createAction {
            case .account: [Item(label: "Lend Money", symbol: "person.2", sheet: .lend(nil, .lend)),
                            Item(label: "Add Cash", symbol: "banknote", sheet: .newCash),
                            Item(label: "Add Account", symbol: "creditcard", sheet: .newAccount(loan: false))]
            case .category: [Item(label: "Add Category", symbol: "square.grid.2x2", sheet: .newCategory)]
            case .bill: [Item(label: "Add Expected Income", symbol: "arrow.down.circle", sheet: .entry(.expectedIncome)),
                         Item(label: "Add Bill", symbol: "doc.text", sheet: .entry(.bill))]
            case .transaction, nil: [Item(label: "More…", symbol: "ellipsis", sheet: .whatHappened)]
            }
            return own + Self.transactions
        }

        var body: some View {
            let action = app.createAction
            Button(action: tapped) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .rotationEffect(.degrees(app.actionsOpen ? 45 : 0))
                    .frame(width: 58, height: 58)
                    .foregroundStyle(Theme.onPrimary)
                    .background(Theme.primary, in: Circle())
                    .shadow(color: Color(hex: 0x24432E, opacity: 0.3), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.actionsOpen ? "Close" : action?.label ?? "Add")
            .accessibilityIdentifier("globalAdd")
            // The options float above the button, so opening them never moves the page
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 10) {
                    if app.actionsOpen {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            option(item)
                                // The nearest option arrives first, the furthest last
                                .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.8).delay(Double(items.count - 1 - index) * 0.03)))
                        }
                    }
                }
                .fixedSize()
                .offset(y: -70)
            }
            .padding(.trailing, 20)
            .sensoryFeedback(.impact(weight: .light), trigger: app.actionsOpen)
            // A new tab or page means a new job; never carry an open menu across
            .onChange(of: action) { app.actionsOpen = false }
        }

        private func option(_ item: Item) -> some View {
            Button {
                toggle()
                app.open(item.sheet)
            } label: {
                HStack(spacing: 10) {
                    Text(item.label).rdText(.label)
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(item.warm ? Theme.warm : Theme.primary)
                        .background(item.warm ? Theme.warmFill : Theme.primary.opacity(0.1), in: Circle())
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.border.opacity(0.6)))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
        }

        private func tapped() {
            if app.createAction != nil { toggle() }
        }

        private func toggle() {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { app.actionsOpen.toggle() }
        }
    }

    /// One sheet with its own back stack: links inside it push, the X closes it
    struct SheetStack: View {
        let first: Sheet
        @Environment(AppModel.self) private var app

        var body: some View {
            @Bindable var app = app
            NavigationStack(path: $app.path) {
                SheetScreen(sheet: first)
                    .navigationDestination(for: Sheet.self) { SheetScreen(sheet: $0) }
            }
            .tint(Theme.primary)
            .overlay(alignment: .top) { ToastView() }
            .modifier(PrivacyCover())
        }
    }

    /// The confirmation that drops in from the top, with Undo where it applies
    struct ToastView: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            Group {
                if let toast = app.toast {
                    HStack(spacing: 10) {
                        Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(toast.isError ? Theme.destructive : Theme.primary)
                        Text(private: toast.message).rdText(.detail).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        if toast.canUndo {
                            Button("Undo") { app.undoLast() }.rdText(.detailStrong).foregroundStyle(Theme.primary)
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        // A closing sheet cancels its copy; only a full wait clears the message
                        guard (try? await Task.sleep(for: .seconds(6))) != nil else { return }
                        withAnimation { if app.toast?.id == toast.id { app.toast = nil } }
                    }
                }
            }
            .animation(.snappy, value: app.toast)
        }
    }
}
