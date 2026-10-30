//
//  AppDuties.swift
//  Nokael Money
//
//  What the app keeps doing whatever is on screen: refreshing the widget and
//  the bill reminders after every change, and keeping bill schedules filled
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
                await BillReminders.sync(store.snapshot)
            }
            .onChange(of: plus.isPlus) { _, isPlus in WidgetSync.update(store.snapshot, isPlus: isPlus) }
            .onAppear {
                store.extendSchedules()
                #if DEBUG
                // Capture helper: -captureSMS "<message>" and -captureApplePay "card|merchant|amount"
                Task { await debugCaptures() }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.extendSchedules() }
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
}
