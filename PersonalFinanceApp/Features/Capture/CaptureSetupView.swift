//
//  CaptureSetupView.swift
//  Nokael Money
//
//  Settings › Siri & automatic capture. iOS doesn't let apps read Wallet or
//  messages, so the person sets up two Shortcuts automations once; this page
//  walks through them, lists the cards it has learned, picks which SMS
//  senders count as banks, and lets them try a message before relying on it.
//

import SwiftUI
import AppIntents
import NokaelCore

struct CaptureSetupView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(PlusStore.self) private var plus
    @Environment(\.openURL) private var openURL
    @State private var paywall: PlusFeature?
    @State private var newSender = ""
    @State private var testText = ""
    @State private var testResult: String?

    private var settings: SettingsRecord { store.settings }
    /// The person's choice, else the phone's country if we know its banks, else the country of their currency
    private var region: String {
        if let chosen = settings.bankRegion { return chosen }
        let phone = Locale.current.region?.identifier ?? ""
        if !BankSenders.banks(region: phone).isEmpty { return phone }
        let byCurrency = ["AED": "AE", "SAR": "SA", "INR": "IN", "QAR": "QA", "KWD": "KW", "OMR": "OM", "BHD": "BH"]
        return byCurrency[settings.currency] ?? phone
    }

    var body: some View {
        Form {
            if !plus.isPlus {
                Section {
                    Button { paywall = .autoCapture } label: {
                        HStack {
                            Label("Apple Pay and bank SMS capture", systemImage: "wallet.pass")
                            Spacer()
                            PlusBadge()
                        }
                    }
                } footer: {
                    Text("Adding by voice with Siri is free. Saving Apple Pay purchases and bank alerts automatically comes with Nokael Plus.")
                }
            }

            siriSection
            applePaySection
            smsSection
            testSection
        }
        .navigationTitle("Siri & automatic capture")
        .navigationBarTitleDisplayMode(.inline)
        .paywall($paywall)
    }

    // MARK: - Siri

    private var siriSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Ready to use, nothing to create", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                Text("Just say “Hey Siri” and one of these:").font(.subheadline).foregroundStyle(.secondary)
                ForEach(["“Log spending in Nokael Money”, then “45 at Carrefour”",
                         "“What's safe to spend in Nokael Money”",
                         "“Add income in Nokael Money”"], id: \.self) { phrase in
                    Label(phrase, systemImage: "waveform").font(.subheadline)
                }
            }
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("Want a button for it? Open Nokael Money in Shortcuts, then press and hold one to add it to your Home Screen or Action button.")
                    .font(.footnote).foregroundStyle(.secondary)
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Siri")
        } footer: {
            Text("Entries from Siri use your last account and the category you used before for that shop. Anything Nokael had to guess is marked for review.")
        }
    }

    // MARK: - Apple Pay

    private var applePaySection: some View {
        Section {
            SetupSteps(steps: [
                "Open Shortcuts, tap Automation, then +.",
                "Choose Transaction. Select all your cards and choose Run Immediately.",
                "Tap New Blank Automation and add “Log Apple Pay Purchase” from Nokael Money.",
                "Set Amount, Merchant and Card to the matching Shortcut Input values, then tap Done.",
            ])
            Button { openURL(URL(string: "shortcuts://")!) } label: {
                Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
            }
            let links = store.fetch(CardLinkRecord.self).sorted { $0.hint < $1.hint }
            ForEach(links, id: \.hint) { link in
                LabeledContent(cardTitle(link.hint), value: store.snapshot.account(link.accountId)?.name ?? "—")
                    .swipeActions {
                        Button("Forget", role: .destructive) { try? store.unlinkCard(link.hint) }
                    }
            }
        } header: {
            Text("Apple Pay")
        } footer: {
            Text("Each tap of your iPhone or Watch is saved for review. When a new card is used, check the account once and choose “Always use this account”.")
        }
    }

    // MARK: - Bank SMS

    @ViewBuilder private var smsSection: some View {
        let banks = BankSenders.banks(region: region)
        let chosen = Set(settings.bankSenders)
        let known = Set(banks.flatMap(\.senders))
        Section {
            Picker("Country", selection: Binding(get: { region }, set: { value in
                try? store.updateSettings { $0.bankRegion = value }
            })) {
                ForEach(Self.regions, id: \.code) { Text($0.name).tag($0.code) }
            }
            ForEach(banks) { bank in
                Toggle(isOn: Binding(get: { bank.senders.contains(where: chosen.contains) },
                                     set: { on in setSenders(bank.senders, on: on) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bank.name)
                        Text(bank.senders.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if banks.isEmpty {
                Text("No suggested banks for this country yet. Add the name your bank's alerts come from below.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(settings.bankSenders.filter { !known.contains($0) }, id: \.self) { sender in
                LabeledContent(sender, value: "Your sender")
                    .swipeActions {
                        Button("Remove", role: .destructive) { setSenders([sender], on: false) }
                    }
            }
            HStack {
                TextField("Sender name, e.g. ADCBAlert", text: $newSender)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") {
                    setSenders([newSender.trimmingCharacters(in: .whitespaces)], on: true)
                    newSender = ""
                }
                .disabled(newSender.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Your banks")
        } footer: {
            Text("Type the name your bank's alerts come from exactly as it appears in Messages. Messages from anyone else are ignored. With no banks chosen, any message that reads like a purchase is saved.")
        }

        Section {
            Button {
                openURL(Self.bankAlertShortcut)
            } label: {
                Label("Add the bank alerts automation", systemImage: "bolt.badge.automatic.fill")
            }
            .accessibilityIdentifier("addBankAutomation")
            Text("Opens Shortcuts with it ready: tap Add Shortcut, and turn on its automation if Shortcuts asks. It runs whenever a message mentions AED.")
                .font(.subheadline).foregroundStyle(.secondary)
            DisclosureGroup("Set it up by hand instead") {
                SetupSteps(steps: manualSteps)
            }
            if let last = store.lastBankMessage {
                LabeledContent("Last alert", value: last.date.formatted(.relative(presentation: .named)))
                Text(last.summary).font(.subheadline).foregroundStyle(.secondary)
            } else {
                Label("No alert has reached Nokael Money yet. If your bank has texted since you set this up, open the automation and check it's on and set to Run Immediately.",
                      systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("Bank SMS alerts")
        } footer: {
            Text("Messages are read on this iPhone and never leave it. Only the purchase is saved, not the message. One-time codes, declined payments and offers are ignored.")
        }
    }

    /// A shared shortcut carrying the Message trigger and the Read Bank Message action
    static let bankAlertShortcut = URL(string: "https://www.icloud.com/shortcuts/fed66c38583b44b5a58eb557cda7d879")!

    private var manualSteps: [String] {
        [
            "Open Shortcuts, tap Automation, then +, and choose Message (“When I receive a message”).",
            "Add the filter Message contains “\(BankSenders.keyword(region: region))”, with no sender, and choose Run Immediately if asked.",
            "Add “Read Bank Message” from Nokael Money.",
            "Set Message to Shortcut Input, and Sender to Shortcut Input › Sender, then go back to save.",
        ]
    }

    // MARK: - Try it

    private var testSection: some View {
        Section {
            TextField("Paste a bank message", text: $testText, axis: .vertical)
                .lineLimit(3...6)
            Button("Read it") { Task { await test() } }
                .disabled(testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let testResult {
                Text(testResult).font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("Try a message")
        } footer: {
            Text("Shows what would be saved. Nothing is added.")
        }
    }

    private func test() async {
        guard let capture = await CaptureService.read(message: testText, homeCurrency: store.currency, date: Date()) else {
            testResult = "No purchase or deposit found. This message would be ignored."
            return
        }
        var parts = [(capture.direction == .spent ? "Spent " : "Received ") + MoneyFormat.string(capture.amount)]
        if !capture.merchant.isEmpty { parts.append((capture.direction == .spent ? "at " : "from ") + capture.merchant) }
        if let card = capture.cardHint { parts.append(cardTitle(card)) }
        let account = card(capture.cardHint).flatMap { store.snapshot.account($0)?.name }
        if let account { parts.append("into \(account)") }
        testResult = parts.joined(separator: " · ")
    }

    private func card(_ hint: String?) -> UUID? { hint.flatMap(store.linkedAccount(forCard:)) }

    private func setSenders(_ senders: [String], on: Bool) {
        let cleaned = senders.filter { !$0.isEmpty }
        try? store.updateSettings { s in
            var list = s.bankSenders.filter { !cleaned.contains($0) }
            if on { list += cleaned }
            s.bankSenders = list
        }
    }

    private func cardTitle(_ hint: String) -> String {
        hint.count == 4 && hint.allSatisfy(\.isNumber) ? "Card ending \(hint)" : hint.capitalized
    }

    static let regions: [(code: String, name: String)] = {
        let codes = Array(BankSenders.catalog.keys) + ["GB", "US", "KW", "OM", "BH"]
        return Set(codes).map { ($0, Locale.current.localizedString(forRegionCode: $0) ?? $0) }
            .sorted { $0.1 < $1.1 }
    }()
}

/// Numbered how-to steps
struct SetupSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Palette.home.opacity(0.15)))
                        .foregroundStyle(Palette.home)
                    Text(step).font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Captured entries waiting for a look, for Home
struct ReviewSection: View {
    @Environment(LedgerStore.self) private var store
    @Binding var selected: EntryRecord?

    var body: some View {
        let snapshot = store.snapshot
        let waiting = snapshot.entries().filter(\.needsReview)
        if !waiting.isEmpty {
            Section {
                ForEach(waiting.prefix(4), id: \.id) { record in
                    Button { selected = record } label: { EntryRow(record: record, snapshot: snapshot) }
                        .buttonStyle(.plain)
                }
                Button("Everything looks right") { try? store.markAllReviewed() }
                    .font(.subheadline.weight(.semibold))
            } header: {
                Text(waiting.count == 1 ? "1 new entry to check" : "\(waiting.count) new entries to check")
            } footer: {
                Text("Saved automatically from Apple Pay, your bank's messages or Siri. Tap one to change its category or account.")
            }
        }
    }
}
