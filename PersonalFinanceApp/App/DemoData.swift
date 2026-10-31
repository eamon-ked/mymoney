//
//  DemoData.swift
//  Nokael Money
//
//  DEBUG only. Fills a throwaway in-memory store (launch argument -demoData)
//  for screenshots and manual checks. Never touches real records.
//

#if DEBUG
import Foundation
import NokaelCore

@MainActor
enum DemoData {
    static func load(into store: LedgerStore) {
        let cal = store.calendar
        let today = store.now()
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: today))!.addingTimeInterval(12 * 3600) }
        func aed(_ v: Decimal) -> Money { Money(v, currency: "AED") }

        try? store.addStarterCategories()
        let s = store.snapshot
        func cat(_ name: String) -> AccountInfo { s.accountRecords.first { $0.name == name }!.info }

        guard let current = try? store.createAccount(name: "Emirates NBD Current", kind: .bank, opening: aed(14200), openingDate: day(-20), institution: "Emirates NBD", colorHex: "#3A7BD5"),
              let savings = try? store.createAccount(name: "Wio Savings", kind: .savings, opening: aed(25000), openingDate: day(-20), institution: "Wio", colorHex: "#0E9AA7"),
              let card = try? store.createAccount(name: "Mashreq Cashback", kind: .creditCard, opening: aed(-1850), openingDate: day(-20), institution: "Mashreq", colorHex: "#E4572E"),
              let loan = try? store.createAccount(name: "Car loan", kind: .loan, opening: aed(-36500), openingDate: day(-20), institution: "ADCB", colorHex: "#8E44AD"),
              let personal = try? store.createAccount(name: "Personal loan", kind: .loan, opening: aed(-12000), openingDate: day(-20), institution: "Mashreq", colorHex: "#5B6CFF")
        else { return }

        let entries: [Entry?] = [
            try? EntryFactory.expense(aed(342.5), from: card.info, category: cat("Groceries"), date: day(0), memo: "Carrefour"),
            try? EntryFactory.expense(aed(58), from: card.info, category: cat("Dining out"), date: day(0), memo: "Talabat"),
            try? EntryFactory.expense(aed(120), from: current.info, category: cat("Transport"), date: day(-1), memo: "Salik top-up"),
            try? EntryFactory.expense(aed(210), from: card.info, category: cat("Entertainment"), date: day(-2), memo: "VOX Cinemas"),
            try? EntryFactory.transfer(aed(2000), from: current.info, to: savings.info, date: day(-3), memo: "Move to savings"),
            try? EntryFactory.expense(aed(389), from: current.info, category: cat("Utilities"), date: day(-5), memo: "DEWA"),
            try? EntryFactory.expense(aed(96), from: card.info, category: cat("Groceries"), date: day(-6), memo: "Spinneys"),
            try? EntryFactory.expense(aed(185), from: card.info, category: cat("Groceries"), date: day(-4), memo: "Carrefour")
        ]
        for e in entries.compactMap({ $0 }) { _ = try? store.post(e) }

        let month = store.snapshot.monthKey
        for (name, amount) in [("Groceries", 1500), ("Transport", 500), ("Dining out", 400), ("Entertainment", 150),
                               ("Utilities", 450), ("Rent or mortgage", 6500)] {
            try? store.setAllocation(aed(Decimal(amount)), categoryId: cat(name).id, month: month)
        }

        try? store.savePlannedItem(PlannedItem(name: "Rent", direction: .outflow, amount: aed(6500),
                                               schedule: Schedule(start: day(3), frequency: .monthly(every: 1)),
                                               accountId: current.id, categoryId: cat("Rent or mortgage").id))
        let loanDay = store.calendar.component(.day, from: day(5))
        try? store.saveDebtTerms(DebtTerms(annualRateBps: 499, monthlyPayment: aed(1850), dueDay: loanDay),
                                 for: loan.id, paidFrom: current.id)
        try? store.saveDebtTerms(DebtTerms(annualRateBps: 3900, monthlyPayment: aed(500), dueDay: 20),
                                 for: card.id, paidFrom: nil)
        // A second loan in the same category as the car loan, already paid this month
        try? store.saveDebtTerms(DebtTerms(annualRateBps: 650, monthlyPayment: aed(900), dueDay: store.calendar.component(.day, from: day(-2))),
                                 for: personal.id, paidFrom: current.id)
        _ = try? store.payDebt(personal.id, from: current.id, amount: aed(900), interest: aed(65), fees: aed(0),
                               date: day(-2), key: UUID())
        try? store.savePlannedItem(PlannedItem(name: "Du mobile", direction: .outflow, amount: aed(280), isEstimate: true,
                                               schedule: Schedule(start: day(9), frequency: .monthly(every: 1)),
                                               accountId: current.id, categoryId: cat("Phone & internet").id))
        try? store.savePlannedItem(PlannedItem(name: "Salary", direction: .inflow, amount: aed(18000),
                                               schedule: Schedule(start: day(12), frequency: .monthly(every: 1)),
                                               accountId: current.id, categoryId: cat("Salary").id))
        try? store.saveReserve(Reserve(name: "Emergency fund", amount: aed(2000), accountId: current.id))
        try? store.saveReserve(Reserve(name: "Japan trip", amount: aed(6000), accountId: savings.id, target: aed(15000),
                                       targetDate: store.calendar.date(byAdding: .month, value: 7, to: day(0))))
        if CommandLine.arguments.contains("-screenshots") { screenshotExtras(store, current: current, card: card, cat: cat, day: day, aed: aed) }
        try? store.updateSettings { $0.bufferMinor = 50000; $0.onboardingDone = true; $0.onboardingStep = 4; $0.lastBackupAt = today }
    }

    /// For App Store screenshots: a little side income so safe to spend has room, and friends who owe money
    private static func screenshotExtras(_ store: LedgerStore, current: LedgerAccountRecord, card: LedgerAccountRecord,
                                         cat: (String) -> AccountInfo, day: (Int) -> Date, aed: (Decimal) -> Money) {
        if let e = try? EntryFactory.income(aed(3200), to: current.info, category: cat("Other income"), date: day(-1), memo: "Design project") {
            _ = try? store.post(e)
        }
        guard let sam = try? store.lentAccount(named: "Sam"), let maya = try? store.lentAccount(named: "Maya") else { return }
        if let dinner = try? EntryFactory.splitExpense(aed(450), from: card.info, category: cat("Dining out"),
                                                       shares: [(sam.info, aed(150)), (maya.info, aed(150))],
                                                       date: day(-1), memo: "Dinner at Zuma") {
            _ = try? store.post(dinner)
        }
        _ = try? store.lend(aed(500), to: maya.id, from: current.id, date: day(-8), memo: "Concert tickets")
    }
}
#endif
