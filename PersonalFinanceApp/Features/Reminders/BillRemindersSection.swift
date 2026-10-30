//
//  BillRemindersSection.swift
//  Nokael Money
//

import SwiftUI

/// Settings: switch reminders on and pick the time of day
struct BillRemindersSection: View {
    @Environment(LedgerStore.self) private var store
    @AppStorage(BillReminders.enabledKey) private var enabled = false
    @AppStorage(BillReminders.hourKey) private var hour = 9
    @State private var denied = false

    var body: some View {
        Section {
            Toggle("Remind me before bills are due", isOn: Binding(get: { enabled && !denied }, set: { turnOn($0) }))
                .accessibilityIdentifier("billReminders")
            if enabled && !denied {
                Picker("At", selection: $hour) {
                    ForEach(6..<22) { h in
                        Text(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
                            .formatted(date: .omitted, time: .shortened)).tag(h)
                    }
                }
            }
        } footer: {
            Text(denied
                 ? "Notifications are off for Nokael Money. Turn them on in the Settings app under Notifications."
                 : "Each bill reminds you 2 days before it's due unless you change it on the bill. Paid and skipped bills don't remind you.")
        }
        .task { denied = await BillReminders.permissionDenied() }
        .onChange(of: hour) { _, _ in Task { await BillReminders.sync(store.snapshot) } }
    }

    private func turnOn(_ on: Bool) {
        Task {
            if on {
                let granted = await BillReminders.requestPermission()
                denied = !granted
                enabled = granted
            } else {
                enabled = false
            }
            await BillReminders.sync(store.snapshot)
        }
    }
}
