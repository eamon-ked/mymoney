//
//  Entities.swift
//  Nokael Money
//
//  Accounts and categories as Siri and Shortcuts see them, so "Groceries" or
//  "ENBD Visa" can be said or picked.
//

import AppIntents
import NokaelCore

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    @MainActor init(_ record: LedgerAccountRecord) {
        id = record.id
        name = record.name
    }
}

struct AccountQuery: EntityStringQuery {
    @MainActor private var all: [AccountEntity] {
        AppServices.shared.store.snapshot.accounts.filter { !$0.archived && $0.spendable }.map(AccountEntity.init)
    }

    @MainActor func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        all.filter { identifiers.contains($0.id) }
    }

    @MainActor func entities(matching string: String) async throws -> [AccountEntity] {
        all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor func suggestedEntities() async throws -> [AccountEntity] { all }
}

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryQuery()

    let id: UUID
    let name: String
    let isIncome: Bool

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    @MainActor init(_ record: LedgerAccountRecord) {
        id = record.id
        name = record.name
        isIncome = record.kind == .income
    }
}

struct CategoryQuery: EntityStringQuery {
    @MainActor private var all: [CategoryEntity] {
        let snapshot = AppServices.shared.store.snapshot
        return (snapshot.expenseCategories + snapshot.incomeCategories).filter { !$0.archived }.map(CategoryEntity.init)
    }

    @MainActor func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        all.filter { identifiers.contains($0.id) }
    }

    @MainActor func entities(matching string: String) async throws -> [CategoryEntity] {
        all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor func suggestedEntities() async throws -> [CategoryEntity] { all.filter { !$0.isIncome } }
}
