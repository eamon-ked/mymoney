//
//  AppDuties.swift
//  Nokael Money
//
//  What the app keeps doing whatever is on screen: refreshing the widget and
//  the notifications after every change, and keeping bill schedules filled
//  ahead. Attached once, around the root view in NokaelMoneyApp, so redesigned
//  screens can't drop it by accident.
//

import SwiftUI
import NokaelCore

struct AppDuties: ViewModifier {
    let store: LedgerStore
    let plus: PlusStore
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: store.revision) {
                WidgetSync.update(store.snapshot, isPlus: plus.isPlus)
                if store.settings.onboardingDone { await Notifications.startQuietly() }
                await Notifications.sync(store.snapshot)
            }
            .onChange(of: plus.isPlus) { _, isPlus in WidgetSync.update(store.snapshot, isPlus: isPlus) }
            .onAppear {
                store.extendSchedules()
                store.pairOwnTransfers()
                #if DEBUG
                // Capture helper: -captureSMS "<message>" and -captureApplePay "card|merchant|amount"
                Task { await debugCaptures() }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.extendSchedules() }
                if phase == .background { BackgroundRefresh.schedule() }
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
        // Notification helper: -notifyIn <seconds> sends the next planned notices that soon, to see how they look
        if case let seconds = defaults.integer(forKey: "notifyIn"), seconds > 0 {
            await Notifications.sendSoon(store.snapshot, in: seconds)
        }
        if let pay = defaults.string(forKey: "captureApplePay") {
            let parts = pay.split(separator: "|").map(String.init)
            if parts.count == 3, let amount = Decimal(string: parts[2]) {
                let capture = Capture(source: .applePay, direction: .spent, amount: Money(amount, currency: store.currency),
                                      merchant: parts[1], cardHint: parts[0], date: store.now().addingTimeInterval(-120), text: pay)
                let run = await CaptureService.runCardPurchase(capture, store: store, isPlus: plus.isPlus)
                print("captureApplePay:", run.outcome.map { "\($0)" } ?? run.trace.headline)
                if let outcome = run.outcome { await Notifications.captured(outcome, capture, in: store) }
            }
        }
        if let text = defaults.string(forKey: "captureSMS") {
            let run = await CaptureService.runBankMessage(text, sender: defaults.string(forKey: "captureSender"), store: store,
                                                          isPlus: plus.isPlus, useAI: !defaults.bool(forKey: "noAI"))
            print("captureSMS:", run.trace.steps.map { "\($0.title) \($0.mark.rawValue): \($0.detail)" }.joined(separator: " | "))
            if let outcome = run.outcome, let capture = run.capture { await Notifications.captured(outcome, capture, in: store) }
        }
    }
    #endif
}
