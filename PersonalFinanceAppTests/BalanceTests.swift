//
//  BalanceTests.swift
//  PersonalFinanceAppTests
//
//  v1.1 hotfix: balance always equals opening balance plus the sum of the
//  account's non-deleted transactions, after any add, edit or delete.
//

import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceApp

@MainActor
@Suite(.serialized)   
struct BalanceTests {
    let localDB = LocalDatabaseManager.shared
    let repository = TransactionRepository()

    private func makeAccount(_ opening: Decimal) throws -> Account {
        let account = Account(name: "Test \(UUID().uuidString.prefix(6))", type: .checking, openingBalance: opening)
        try localDB.insert(account)
        return account
    }

    private func cleanUp(_ accounts: [Account]) throws {
        for account in accounts {
            let id = account.id
            let optionalId: UUID? = id
            let rows = try localDB.context.fetch(FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.accountId == id || $0.transferAccountId == optionalId }))
            rows.forEach { localDB.context.delete($0) }
            localDB.context.delete(account)
        }
        try localDB.save()
    }

    @Test func addEditDeleteExpense() throws {
        let account = try makeAccount(1000)
        defer { try? cleanUp([account]) }

        let t = Transaction(accountId: account.id, amount: 100, type: .expense, transactionDescription: "Groceries")
        repository.addTransaction(t)
        #expect(account.balance == 900)

        t.amount = 60
        repository.updateTransaction(t, previousAccountId: account.id, previousTransferAccountId: nil)
        #expect(account.balance == 940)

        repository.deleteTransaction(t)
        #expect(account.balance == 1000)
        #expect(t.deletedAt != nil)
        #expect(try !localDB.fetchTransactions(for: account.id).contains { $0.id == t.id })
    }

    @Test func moveTransactionBetweenAccounts() throws {
        let a = try makeAccount(500)
        let b = try makeAccount(500)
        defer { try? cleanUp([a, b]) }

        let t = Transaction(accountId: a.id, amount: 50, type: .expense, transactionDescription: "Taxi")
        repository.addTransaction(t)
        #expect(a.balance == 450)

        t.accountId = b.id
        repository.updateTransaction(t, previousAccountId: a.id, previousTransferAccountId: nil)
        #expect(a.balance == 500)
        #expect(b.balance == 450)
    }

    @Test func editChangingAmountAccountAndTypeKeepsBalancesRight() throws {
        let a = try makeAccount(1000)
        let b = try makeAccount(200)
        defer { try? cleanUp([a, b]) }
        
        let t = Transaction(accountId: a.id, amount: 100, type: .expense, transactionDescription: "Dinner")
        repository.addTransaction(t)
        #expect(a.balance == 900)
        
        // Turn the expense into a 300 transfer from B to A, as the edit form would
        let previousAccountId = t.accountId
        let previousTransferAccountId = t.transferAccountId
        t.accountId = b.id
        t.transferAccountId = a.id
        t.type = .transfer
        t.amount = 300
        repository.updateTransaction(t, previousAccountId: previousAccountId,
                                     previousTransferAccountId: previousTransferAccountId)
        #expect(a.balance == 1300)
        #expect(b.balance == -100)
    }
    
    @Test func writesKeepAccountScopedListScoped() throws {
        let a = try makeAccount(0)
        let b = try makeAccount(0)
        defer { try? cleanUp([a, b]) }
        
        repository.addTransaction(Transaction(accountId: b.id, amount: 5, type: .expense, transactionDescription: "Other account"))
        repository.loadTransactions(for: a.id)
        let t = Transaction(accountId: a.id, amount: 10, type: .income, transactionDescription: "Mine")
        repository.addTransaction(t)
        #expect(repository.transactions.allSatisfy { $0.accountId == a.id || $0.transferAccountId == a.id })
        #expect(repository.transactions.contains { $0.id == t.id })
    }
    
    @Test func transferMovesMoneyBothWays() throws {
        let a = try makeAccount(1000)
        let b = try makeAccount(0)
        defer { try? cleanUp([a, b]) }

        let t = Transaction(accountId: a.id, transferAccountId: b.id, amount: 200, type: .transfer, transactionDescription: "Save")
        repository.addTransaction(t)
        #expect(a.balance == 800)
        #expect(b.balance == 200)

        repository.deleteTransaction(t)
        #expect(a.balance == 1000)
        #expect(b.balance == 0)
    }

    @Test func legacyTransferWithoutDestinationIsNeutral() throws {
        let a = try makeAccount(300)
        defer { try? cleanUp([a]) }

        repository.addTransaction(Transaction(accountId: a.id, amount: 100, type: .transfer, transactionDescription: "Old"))
        #expect(a.balance == 300)
    }

    @Test func decimalAmountsStayExact() throws {
        let a = try makeAccount(0)
        defer { try? cleanUp([a]) }

        repository.addTransaction(Transaction(accountId: a.id, amount: Decimal(string: "0.10")!, type: .income, transactionDescription: "a"))
        repository.addTransaction(Transaction(accountId: a.id, amount: Decimal(string: "0.20")!, type: .income, transactionDescription: "b"))
        #expect(a.balance == Decimal(string: "0.30")!)
    }
}
