//
//  RedesignMore.swift
//  Nokael Money
//
//  The More tab and the pages it pushes: profile, settings, privacy and
//  Privacy Mode, backup and your data, categories, change history, Apple
//  Intelligence, and Nokael Plus with its paywall.
//

import SwiftUI
import UserNotifications
import StoreKit
import UniformTypeIdentifiers
import NokaelCore

extension Redesign {
    /// The fifth tab: finance pages, automation, then the person's own pages
    struct MoreTab: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            group("Finance") {
                row("arrow.up.arrow.down", "Activity", "Transactions and history") { app.show(.activity) }
                line
                row("chart.xyaxis.line", "Reports", "Where your money went, month by month") { app.show(.reports) }
                line
                row("calendar", "Money ahead", "Your balance over the next weeks", plus: true) { app.show(.forecast, needs: .moneyAhead) }
                line
                row("square.and.arrow.down", "Import a statement", "Add a bank's CSV or PDF in one go") {
                    app.open(.importStatement(nil))
                }
            }
            .padding(.bottom, 24)
            group("Automation") {
                row("wave.3.right", "Siri & automatic capture", "Apple Pay, bank messages and Siri") { app.show(.capture) }
            }
            .padding(.bottom, 24)
            group("Personal") {
                row("person", "My Profile", app.holder.isEmpty ? "Add your name" : app.holder) { app.show(.profile) }
                line
                row("gearshape", "Settings", "Appearance, notifications and categories") { app.show(.settings) }
                line
                row("lock.shield", "Privacy & Security", "Privacy Mode and Face ID") { app.show(.privacy) }
                line
                row("externaldrive", "Backup & your data", backupLine) { app.show(.data) }
                line
                row("star", "Nokael Plus", app.plus.currentPlan.map { "\($0) plan" } ?? "What Plus adds") { app.show(.plus) }
                line
                row("questionmark", "Help & Support", "Answers and how things work") { app.show(.help) }
            }
        }

        private var backupLine: String {
            app.store.settings.lastBackupAt.map { "Last backup \($0.formatted(.relative(presentation: .named)))" } ?? "No backup yet"
        }

        private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased()).rdText(.overline).foregroundStyle(Theme.muted)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0, content: rows).rdPanel(padding: 0)
            }
        }

        private var line: some View { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 68) }

        private func row(_ symbol: String, _ title: String, _ subtitle: String, plus: Bool = false, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 38, height: 38)
                        .background(Theme.primary.opacity(0.075), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(title).rdText(.cardTitle)
                            if plus && !app.isPlus { PlusTag() }
                        }
                        Text(subtitle).rdText(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(Theme.muted.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// A full screen pushed from More or Home, with the system back button
    struct PageScreen: View {
        let page: Page
        @Environment(AppModel.self) private var app

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch page {
                    case .activity: ActivityTab()
                    case .reports: ReportsPage()
                    case .forecast: ForecastPage()
                    case .profile: ProfilePage()
                    case .settings: SettingsPage()
                    case .privacy: PrivacyPage()
                    case .privacyMode: PrivacyModePage()
                    case .help: HelpPage()
                    case .capture: CapturePage()
                    case .data: DataPage()
                    case .plus: PlusPage()
                    case .categories: CategoriesPage()
                    case .history: HistoryPage()
                    case .reminders: NotificationsPage()
                    case .intelligenceSettings: IntelligenceSettingsPage()
                    case .netWorth: NetWorthPage()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .safeAreaPadding(.bottom, app.barHeight)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.foreground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if page == .activity {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { withAnimation { app.showFilters.toggle() } } label: { Image(systemName: "slider.horizontal.3") }
                            .accessibilityLabel("Filters")
                    }
                }
                if page == .categories {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { app.open(.newCategory) } label: { Image(systemName: "plus") }.accessibilityLabel("New category")
                    }
                }
            }
        }

        private var title: String {
            switch page {
            case .activity: "Activity"
            case .reports: "Reports"
            case .forecast: "Money ahead"
            case .profile: "My Profile"
            case .settings: "Settings"
            case .privacy: "Privacy & Security"
            case .privacyMode: "Privacy Mode"
            case .help: "Help & Support"
            case .capture: "Siri & automatic capture"
            case .data: "Backup & your data"
            case .plus: "Nokael Plus"
            case .categories: "Categories"
            case .history: "Change history"
            case .reminders: "Notifications"
            case .intelligenceSettings: "Apple Intelligence"
            case .netWorth: "Net worth"
            }
        }
    }

    struct ProfilePage: View {
        @Environment(AppModel.self) private var app
        @State private var name = ""

        var body: some View {
            VStack(spacing: 12) {
                Avatar(name: name.isEmpty ? "?" : name, size: 72)
                Text("Personal Account").rdText(.caption).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("Your name").rdText(.caption).foregroundStyle(Theme.muted)
                TextField("Name", text: $name)
                    .rdText(.body)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .frame(minHeight: 44)
                    .onSubmit { app.holder = name.trimmingCharacters(in: .whitespaces) }
            }
            .rdPanel()
            Redesign.footnote("Shown in the greeting on Home and on your card. It stays on this iPhone and in your backups.")
                .padding(.top, 8).padding(.leading, 4)
            .onAppear { name = app.holder }
            .onDisappear { app.holder = name.trimmingCharacters(in: .whitespaces) }
        }
    }

    struct SettingsPage: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            @Bindable var app = app
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "circle.lefthalf.filled").frame(width: 22)
                    Text("Appearance").rdText(.body)
                    Spacer()
                    Choice(value: $app.dark, options: [nil, false, true]) { $0 == nil ? "Like the iPhone" : $0! ? "Dark" : "Light" }
                        .fixedSize()
                        .rdText(.detail)
                }
                .padding(.horizontal, 16).frame(minHeight: 54)
                line
                link("bell", "Notifications", Notifications.Group.allCases.contains(where: Notifications.isOn) ? "On" : "Off") { app.show(.reminders) }
                line
                HStack(spacing: 12) {
                    Image(systemName: "banknote").frame(width: 22)
                    Text("Currency").rdText(.body)
                    Spacer()
                    Text(app.currency).rdText(.detail).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16).frame(minHeight: 54)
                line
                HStack(spacing: 12) {
                    Image(systemName: "calendar").frame(width: 22)
                    Text("Week starts on").rdText(.body)
                    Spacer()
                    Choice(value: Binding(get: { app.store.settings.firstWeekday },
                                          set: { day in try? app.store.updateSettings { $0.firstWeekday = day } }),
                           options: [1, 2, 7]) { [1: "Sunday", 2: "Monday", 7: "Saturday"][$0] ?? "" }
                        .fixedSize()
                        .rdText(.detail)
                }
                .padding(.horizontal, 16).frame(minHeight: 54)
                line
                link("tag", "Categories", "\(app.snapshot.expenseCategories.count + app.snapshot.incomeCategories.count)") { app.show(.categories) }
                line
                link("sparkles", "Apple Intelligence", AppleIntelligence.isReady ? "On" : "Off") { app.show(.intelligenceSettings) }
            }
            .rdPanel(padding: 0)
            Redesign.footnote("The currency is set when you start and can't be changed, so your history stays in one currency.")
                .padding(.top, 8).padding(.horizontal, 4)

            Text("Your finances, simplified.\nNokael Money \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .rdText(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(4)
                .frame(maxWidth: .infinity).padding(.top, 32)
        }

        private var line: some View { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 50) }

        private func link(_ symbol: String, _ title: String, _ value: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: symbol).frame(width: 22)
                    Text(title).rdText(.body)
                    Spacer()
                    Text(value).rdText(.detail).foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// One switch per kind of notification, quiet by default; everything is planned on this phone
    struct NotificationsPage: View {
        @Environment(AppModel.self) private var app
        @Environment(\.openURL) private var openURL
        @AppStorage(Notifications.hourKey) private var hour = 9
        @AppStorage(Notifications.hideAmountsKey) private var hideAmounts = false
        @State private var status: UNAuthorizationStatus = .notDetermined
        /// Bumped after a switch changes, so the rows read UserDefaults again
        @State private var changes = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                permissionNote
                VStack(spacing: 14) {
                    ForEach(Notifications.Group.allCases) { group in
                        ToggleRow(title: group.title, detail: group.detail, isOn: binding(group.key, default: true))
                            .accessibilityIdentifier("notify-\(group.rawValue)")
                    }
                }
                Text("ALSO").rdText(.overline).foregroundStyle(Theme.muted).padding(.top, 24).padding(.bottom, 8)
                VStack(spacing: 14) {
                    ForEach(Notifications.Extra.allCases) { extra in
                        ToggleRow(title: extra.title, isOn: binding(extra.key, default: false))
                    }
                }
                Field(label: "Reminders come at") {
                    Choice(value: $hour, options: Array(6..<22)) { h in
                        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!.formatted(date: .omitted, time: .shortened)
                    }
                }
                .padding(.top, 24)
                ToggleRow(title: "Hide amounts", detail: "Notifications say what happened without saying how much, so a glance at the Lock Screen gives nothing away.",
                          isOn: $hideAmounts)
                    .padding(.top, 16)
                if Notifications.isOn(.spending) && !hasCaptures {
                    Redesign.footnote("Spending is announced as it happens once the Wallet or bank message automation is set up.")
                        .padding(.top, 16).padding(.horizontal, 4)
                    Button("Set up automatic capture") { app.show(.capture) }
                        .buttonStyle(QuietButtonStyle())
                }
                Redesign.footnote("Each bill reminds you 2 days before it's due unless you change it on the bill. Everything is worked out on this iPhone; nothing is sent anywhere.")
                    .padding(.top, 16).padding(.horizontal, 4)
            }
            .id(changes)
            .task { status = await Notifications.permission() }
            .onChange(of: hour) { resync() }
            .onChange(of: hideAmounts) { resync() }
        }

        @ViewBuilder private var permissionNote: some View {
            switch status {
            case .denied:
                note("Notifications are off for Nokael Money in the iPhone's Settings.", button: "Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            case .provisional, .notDetermined:
                note("They arrive quietly in Notification Centre, with no banner or sound.", button: "Show banners and sounds") {
                    Task { _ = await Notifications.requestPermission(); status = await Notifications.permission(); resync() }
                }
            default:
                EmptyView()
            }
        }

        private func note(_ text: String, button: String, action: @escaping () -> Void) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(text).rdText(.detail).fixedSize(horizontal: false, vertical: true)
                Button(button, action: action).buttonStyle(QuietButtonStyle())
            }
            .rdPanel()
            .padding(.bottom, 20)
        }

        private var hasCaptures: Bool { app.snapshot.entryRecords.contains { $0.source == .applePay || $0.source == .sms } }

        private func binding(_ key: String, default on: Bool) -> Binding<Bool> {
            Binding(get: { _ = changes; return UserDefaults.standard.object(forKey: key) as? Bool ?? on },
                    set: { value in
                        UserDefaults.standard.set(value, forKey: key)
                        changes += 1
                        // Turning one on is the moment to ask for banners and sounds
                        if value && status != .authorized {
                            Task { _ = await Notifications.requestPermission(); status = await Notifications.permission() }
                        }
                        resync()
                    })
        }

        private func resync() { Task { await Notifications.sync(app.snapshot) } }
    }

    struct IntelligenceSettingsPage: View {
        @Environment(AppModel.self) private var app
        @AppStorage(AppleIntelligence.enabledKey) private var enabled = true
        @AppStorage(AppleIntelligence.cloudKey) private var cloudOn = true

        var body: some View {
            let system = AppleIntelligence.systemStatus
            let cloud = AppleIntelligence.cloudStatus
            if system == .ready {
                ToggleRow(title: "Use Apple Intelligence", isOn: $enabled)
                if enabled, app.isPlus, cloud.offered {
                    ToggleRow(title: "Use Apple's cloud model when online", isOn: $cloudOn)
                        .accessibilityIdentifier("cloudModelToggle")
                        .padding(.top, 12)
                    if cloudOn, cloud == .limitReached {
                        Label("Today's limit is used up. Answers come from this iPhone until it resets.", systemImage: "hourglass")
                            .rdText(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
                    }
                }
            } else {
                DetailCard { DetailRow(label: "Apple Intelligence", value: "Unavailable") }
            }
            Redesign.footnote(system != .ready ? system.explanation
                : app.isPlus && cloud.offered && cloudOn && enabled
                    ? "A summary of your month and answers to your questions use Apple's larger model on Private Cloud Compute when you're online. Apple uses your data only to answer and doesn't keep it. Offline, everything runs on this iPhone. Always check before saving."
                    : "Quick add from a sentence, category suggestions, a summary of your month and answers to your questions. Runs privately on this iPhone, free and offline. Always check before saving.")
                .padding(.top, 12).padding(.horizontal, 4)
        }
    }

    struct PrivacyPage: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            Button { app.show(.privacyMode) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "eye.slash").frame(width: 22)
                    Text("Privacy Mode").rdText(.body)
                    Spacer()
                    Text(!app.privacy.on ? "Off" : app.privacy.enhanced ? "Enhanced" : "Standard")
                        .rdText(.detail).foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rdPanel(padding: 0)
            Redesign.footnote("Hides your amounts so you can check Nokael Money in public.")
                .padding(.top, 8).padding(.horizontal, 4).padding(.bottom, 24)

            Toggle(isOn: Binding(get: { app.store.settings.biometricLock }, set: { on in
                try? app.store.updateSettings { $0.biometricLock = on }
            })) {
                Label { Text("Lock with Face ID").rdText(.body) } icon: { Image(systemName: "faceid") }
            }
            .tint(Theme.primary)
            .padding(.horizontal, 16).frame(minHeight: 54)
            .rdPanel(padding: 0)
            Redesign.footnote("Asks for Face ID or your passcode each time you open Nokael Money.")
                .padding(.top, 8).padding(.horizontal, 4).padding(.bottom, 24)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "iphone").foregroundStyle(Theme.primary).frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your data stays on this iPhone").rdText(.detailStrong)
                    Text("Your accounts and transactions are stored on this device, not on a server. Save a backup to keep a copy.")
                        .rdText(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .rdPanel()
        }
    }

    /// More › Privacy & Security › Privacy Mode: the switch the eye on Home also flips, its level and when it applies
    struct PrivacyModePage: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            @Bindable var app = app
            let level = Binding(get: { app.privacy.enhanced ? "Enhanced" : "Standard" },
                                set: { app.privacy.enhanced = $0 == "Enhanced" })

            VStack(spacing: 0) {
                toggle("Privacy Mode", "Hide sensitive financial information", "eye.slash", $app.privacy.on)
            }
            .rdPanel(padding: 0)
            Redesign.footnote("You can also tap the eye on Home's safe-to-spend card. It switches Privacy Mode everywhere at once.")
                .padding(.top, 8).padding(.horizontal, 4).padding(.bottom, 24)

            Redesign.overline("Level")
            Pills(options: ["Standard", "Enhanced"], selection: level)
            Redesign.footnote(app.privacy.enhanced
                ? "Hides amounts, and the details you choose below. Each one is replaced with a neutral label."
                : "Hides every amount. Account names, transactions and the rest of the app stay as they are.")
                .padding(.top, 8).padding(.horizontal, 4).padding(.bottom, 16)

            if app.privacy.enhanced {
                VStack(spacing: 0) {
                    toggle("Hide Transaction Details", "Names, merchants, notes and categories", "list.bullet", $app.privacy.hideDetails)
                    line
                    toggle("Hide Account Names", "Shown as Account 1, Account 2", "wallet.bifold", $app.privacy.hideAccountNames)
                    line
                    toggle("Hide Financial Charts", "Charts, progress and percentages", "chart.bar", $app.privacy.hideCharts)
                }
                .rdPanel(padding: 0)
                .padding(.bottom, 24)
                .transition(.opacity)
            }

            Redesign.overline("Opening and leaving")
            VStack(spacing: 0) {
                toggle("Remember Privacy Mode", "Reopen the way you left it. When off, amounts show each time you open the app.",
                       "arrow.clockwise", $app.privacy.remember)
                line
                toggle("Hide When You Leave", "Cover the screen in the app switcher", "rectangle.on.rectangle", $app.privacy.coverInBackground)
            }
            .rdPanel(padding: 0)

            Redesign.footnote("Privacy Mode changes only what's on screen. Your figures aren't changed, and it doesn't stop screenshots or lock the app. For that, use Lock with Face ID.")
                .padding(.top, 16).padding(.horizontal, 4)
        }

        private var line: some View { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1).padding(.leading, 50) }

        private func toggle(_ title: String, _ detail: String, _ symbol: String, _ value: Binding<Bool>) -> some View {
            Toggle(isOn: Binding(get: { value.wrappedValue },
                                 set: { new in withAnimation(.easeInOut(duration: 0.2)) { value.wrappedValue = new } })) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol).foregroundStyle(Theme.primary).frame(width: 22).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).rdText(.body)
                        Text(detail).rdText(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Theme.primary)
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 54)
        }
    }

    // MARK: - Backup and your data

    struct BackupDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.json] }
        let data: Data

        init(data: Data) { self.data = data }
        init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
    }

    struct DataPage: View {
        @Environment(AppModel.self) private var app
        @State private var document: BackupDocument?
        @State private var exporting = false
        @State private var restoring = false
        @State private var exportURL: URL?
        @State private var confirmErase = false

        var body: some View {
            Redesign.overline("Backup")
            VStack(spacing: 0) {
                LinkRow(symbol: "externaldrive.badge.plus", title: "Save a backup", detail: "A file you can keep in iCloud Drive or elsewhere") { save() }
                    .accessibilityIdentifier("saveBackup")
                Redesign.hairline.padding(.leading, 68)
                LinkRow(symbol: "clock.arrow.circlepath", title: "Restore from a backup", detail: "Replaces what's on this iPhone") { restoring = true }
            }
            .rdPanel(padding: 0)
            Redesign.footnote(app.store.settings.lastBackupAt.map { "Last backup \($0.formatted(.relative(presentation: .named)))." }
                              ?? "No backup yet. Your data is only on this iPhone. Save one to iCloud Drive or another place you trust.")
                .padding(.top, 8).padding(.horizontal, 4).padding(.bottom, 24)

            Redesign.overline("Your data")
            VStack(spacing: 0) {
                // Free for everyone: people's records are theirs to take
                LinkRow(symbol: "square.and.arrow.up", title: "Export all entries (CSV)", detail: "A spreadsheet for your own records") { export() }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share export", systemImage: "doc.text").rdText(.label).foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                Redesign.hairline.padding(.leading, 68)
                LinkRow(symbol: "clock", title: "Change history", detail: "Every change, newest first") { app.show(.history) }
            }
            .rdPanel(padding: 0)
            .padding(.bottom, 24)

            Button(role: .destructive) { confirmErase = true } label: { Text("Delete all data on this iPhone").foregroundStyle(Theme.destructive) }
                .buttonStyle(QuietButtonStyle())
            Redesign.footnote("Removes every account, entry, budget and bill from this device. Without a backup, this can't be undone.")
                .padding(.top, 8).padding(.horizontal, 4)
                .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                              defaultFilename: "Nokael Money backup \(LedgerStore.fileStamp(Date()))") { result in
                    switch result {
                    case .success:
                        app.store.markBackedUp()
                        app.toast = Toast(message: "Backup saved.")
                    case .failure(let failure):
                        if (failure as NSError).code != NSUserCancelledError { app.toast = Toast(message: "Couldn't save the backup.", isError: true) }
                    }
                }
                .modifier(RestoreFlow(isPresented: $restoring))
                .confirmationDialog("Delete all data?", isPresented: $confirmErase, titleVisibility: .visible) {
                    Button("Delete everything", role: .destructive) {
                        app.attempt("Everything was deleted.") { try app.store.eraseAllData() }
                            .map { app.toast = Toast(message: $0, isError: true) }
                        app.go(.home)
                    }
                } message: { Text("This can't be undone.") }
        }

        private func save() {
            do {
                document = BackupDocument(data: try app.store.backupData())
                exporting = true
            } catch { app.toast = Toast(message: "Couldn't create the backup.", isError: true) }
        }

        private func export() {
            let s = app.snapshot
            var rows = ["Date,Type,Description,Account,Category,Amount,Currency,Status,Notes"]
            for record in s.entries(includeVoided: true).reversed() {
                let category = record.lines.compactMap { s.account($0.accountId) }.first { $0.kind.isCategory }?.name ?? ""
                for line in record.lines where s.account(line.accountId)?.kind.isBalanceSheet == true {
                    rows.append([
                        ISO8601DateFormatter.string(from: record.date, timeZone: s.calendar.timeZone, formatOptions: [.withFullDate]),
                        record.kindRaw, record.memo, s.account(line.accountId)?.name ?? "", category,
                        "\(Money(minorUnits: line.minorUnits, currency: line.currency).decimal)", line.currency,
                        record.statusRaw, record.notes
                    ].map(csv).joined(separator: ","))
                }
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("nokael-money-entries.csv")
            do {
                try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
                exportURL = url
            } catch { app.toast = Toast(message: "Couldn't create the export.", isError: true) }
        }

        private func csv(_ field: String) -> String {
            field.contains(where: { ",\"\n".contains($0) }) ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
        }
    }

    /// Picks a backup file, checks it, asks to confirm, then restores it
    struct RestoreFlow: ViewModifier {
        @Environment(AppModel.self) private var app
        @Binding var isPresented: Bool
        @State private var pending: Backup?
        @State private var error: String?

        func body(content: Content) -> some View {
            content
                .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                    guard case .success(let url) = result else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        pending = try LedgerStore.readBackup(try Data(contentsOf: url))
                    } catch let e as BackupError {
                        error = e.errorDescription
                    } catch {
                        self.error = "Couldn't open that file."
                    }
                }
                .confirmationDialog("Replace everything on this iPhone?",
                                    isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                    titleVisibility: .visible, presenting: pending) { backup in
                    Button("Restore", role: .destructive) {
                        do {
                            let copy = try app.store.restore(backup)
                            app.toast = Toast(message: copy == nil ? "Backup restored."
                                              : "Backup restored. Your previous data was saved in Files › Nokael Money › Backups.")
                        } catch { self.error = "The restore didn't finish, so please try again. \(StoreError.from(error).errorDescription ?? "")" }
                        pending = nil
                    }
                } message: { backup in
                    Text("Backup from \(backup.createdAt.formatted(date: .long, time: .shortened)): \(backup.summary). What's on this iPhone now is saved to Files › Nokael Money › Backups first.")
                }
                .alert("Couldn't restore", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(error ?? "") }
        }
    }

    struct HistoryPage: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            let trail = Array(app.store.auditTrail.prefix(300))
            if trail.isEmpty { EmptyNote(text: "No changes yet.") }
            VStack(spacing: 0) {
                ForEach(Array(trail.enumerated()), id: \.offset) { i, a in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(private: app.hidesDetails ? a.action : app.concealingAmounts(a.summary)).rdText(.detail)
                        if let reason = a.reason, !reason.isEmpty, !app.hidesDetails {
                            Text(private: app.concealingAmounts(reason)).rdText(.caption).foregroundStyle(Theme.muted)
                        }
                        Text(a.date.formatted(date: .abbreviated, time: .shortened)).rdText(.caption).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    if i < trail.count - 1 { Redesign.hairline }
                }
            }
            .rdPanel(padding: 14)
        }
    }

    /// Every spending and income category, archived ones too
    struct CategoriesPage: View {
        @Environment(AppModel.self) private var app

        var body: some View {
            let s = app.snapshot
            let all = s.accountRecords.filter { $0.kind.isCategory && !$0.isSystem }
            section("Spending", all.filter { $0.kind == .expense && !$0.archived })
            section("Income", all.filter { $0.kind == .income && !$0.archived })
            let archived = all.filter(\.archived)
            if !archived.isEmpty { section("Archived", archived) }
            Button("New category") { app.open(.newCategory) }.buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
        }

        @ViewBuilder private func section(_ title: String, _ items: [LedgerAccountRecord]) -> some View {
            Redesign.overline(title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                    Button { app.open(.editCategory(c.id)) } label: {
                        HStack(spacing: 12) {
                            IconBox(AppModel.look(c), small: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name).rdText(.cardTitle)
                                if c.kind == .expense { Text(c.group.isEmpty ? "Other" : c.group).rdText(.caption).foregroundStyle(Theme.muted) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < items.count - 1 { Redesign.hairline }
                }
                if items.isEmpty { Redesign.footnote("None yet.").padding(.vertical, 12) }
            }
            .rdPanel(padding: 14)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Nokael Plus

    struct PlusPage: View {
        @Environment(AppModel.self) private var app
        @State private var managing = false

        var body: some View {
            if let plan = app.plus.currentPlan {
                VStack(alignment: .leading, spacing: 8) {
                    Label("You have Nokael Plus", systemImage: "star.fill").rdText(.section).foregroundStyle(Theme.primary)
                    Text("\(plan) plan. Thank you.").rdText(.caption).foregroundStyle(Theme.muted)
                }
                .rdPanel()
                if plan == "Monthly" || plan == "Yearly" {
                    Button("Manage subscription") { managing = true }.buttonStyle(QuietButtonStyle()).padding(.top, 16)
                        .manageSubscriptionsSheet(isPresented: $managing)
                }
                features.padding(.top, 24)
            } else {
                PaywallPage(feature: nil)
            }
        }

        private var features: some View {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(PlusFeature.allCases) { f in
                    HStack(alignment: .top, spacing: 12) {
                        IconBox(symbol: f.symbol, small: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.title).rdText(.detailStrong)
                            Text(f.detail).rdText(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    /// What Nokael Plus adds and the three ways to get it. Prices come from the App Store, in the person's own currency.
    struct PaywallPage: View {
        let feature: PlusFeature?
        @Environment(AppModel.self) private var app
        @Environment(\.openURL) private var openURL
        @State private var selected = PlusStore.yearly
        @State private var trialEligible = false
        @State private var working = false
        @State private var problem: String?

        static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        static let privacyURL = URL(string: "https://mymoney-legal-docs.pages.dev/privacy-policy.html")!

        private var plus: PlusStore { app.plus }
        private var features: [PlusFeature] {
            guard let feature else { return PlusFeature.allCases }
            return [feature] + PlusFeature.allCases.filter { $0 != feature }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your money, tracked automatically").rdText(.heading)
                    Text("Nokael Plus: less work, more clarity. Everything in the free app, plus:")
                        .rdText(.body).foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features) { f in
                        HStack(alignment: .top, spacing: 12) {
                            IconBox(symbol: f.symbol, small: true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.title).rdText(.detailStrong)
                                Text(f.detail).rdText(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                // Say plainly what never needs Plus, so nobody feels their picture is incomplete without it
                Redesign.footnote("Free always includes unlimited accounts and transactions, budgets, bills, debts, safe to spend, Siri, export, backup and Privacy Mode.")
                plans
                Problem(text: problem)
                Button { Task { await buy() } } label: {
                    if working { ProgressView().tint(Theme.onPrimary) } else { Text(buyTitle) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(plus.products.first { $0.id == selected } == nil || working)
                .accessibilityIdentifier("buyPlus")
                Text(selected == PlusStore.lifetime ? "One payment. No subscription." : "Cancel anytime in Settings › Apple Account › Subscriptions.")
                    .rdText(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                Button("Restore purchases") { Task { await restore() } }
                    .rdText(.label).foregroundStyle(Theme.primary).frame(maxWidth: .infinity, minHeight: 44).disabled(working)
                Redesign.footnote("Subscriptions renew automatically at the price shown unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple Account. Any unused part of a free trial ends when you subscribe.")
                HStack(spacing: 16) {
                    Button("Terms of Use") { openURL(Self.termsURL) }
                    Button("Privacy Policy") { openURL(Self.privacyURL) }
                }
                .rdText(.caption).foregroundStyle(Theme.primary)
            }
            .task {
                if plus.products.isEmpty { await plus.loadProducts() }
                trialEligible = await plus.products.first { $0.id == PlusStore.yearly }?.subscription?.isEligibleForIntroOffer ?? false
            }
            .onChange(of: plus.isPlus) { _, isPlus in if isPlus && feature != nil { app.back() } }
        }

        @ViewBuilder private var plans: some View {
            if plus.products.isEmpty {
                HStack(spacing: 8) {
                    if plus.loadFailed {
                        Text("Couldn't reach the App Store. Check your connection and try again.").rdText(.detail).foregroundStyle(Theme.muted)
                        Button("Retry") { Task { await plus.loadProducts() } }
                    } else {
                        ProgressView()
                        Text("Loading prices…").rdText(.detail).foregroundStyle(Theme.muted)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(plus.products, id: \.id) { product in
                        Button { selected = product.id } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected == product.id ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(selected == product.id ? Theme.primary : Theme.muted)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(product.displayName).rdText(.cardTitle)
                                        if product.id == PlusStore.yearly { PlusTag(text: "Best value") }
                                    }
                                    Text(caption(for: product)).rdText(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected == product.id ? Theme.primary : Theme.border, lineWidth: selected == product.id ? 2 : 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == product.id ? .isSelected : [])
                    }
                }
            }
        }

        private func caption(for product: Product) -> String {
            switch product.id {
            case PlusStore.yearly:
                let perMonth = (product.price / 12).formatted(product.priceFormatStyle)
                return trialEligible ? "1 week free, then \(product.displayPrice) a year (\(perMonth) a month)"
                                     : "\(product.displayPrice) a year, \(perMonth) a month"
            case PlusStore.monthly: return "\(product.displayPrice) a month"
            default: return "\(product.displayPrice) once, yours to keep"
            }
        }

        private var buyTitle: String {
            if selected == PlusStore.yearly && trialEligible { return "Try free for 1 week" }
            if selected == PlusStore.lifetime { return "Buy lifetime" }
            return "Subscribe"
        }

        private func buy() async {
            guard let product = plus.products.first(where: { $0.id == selected }) else { return }
            working = true
            problem = nil
            defer { working = false }
            do {
                if try await plus.purchase(product) { app.toast = Toast(message: "Welcome to Nokael Plus.") }
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? "The purchase didn't go through. You haven't been charged."
            }
        }

        private func restore() async {
            working = true
            problem = nil
            defer { working = false }
            do {
                try await plus.restore()
                if !plus.isPlus { problem = "No Nokael Plus purchase was found for this Apple Account." }
            } catch {
                problem = "Couldn't restore right now. Try again."
            }
        }
    }
}
