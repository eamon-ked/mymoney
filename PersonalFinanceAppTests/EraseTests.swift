//  EraseTests.swift — "Delete all data" leaves nothing of the old database behind:
//  the file itself is replaced at the next launch, unless new data was saved since

import Foundation
import SwiftData
import Testing
import NokaelCore
@testable import PersonalFinanceApp

@MainActor
struct EraseTests {
    // Not in the temporary folder: erasing empties that too
    let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("erase-\(UUID().uuidString)")
    var database: URL { folder.appendingPathComponent("test.store") }
    var marker: URL { LedgerStore.erasePendingMarker(for: database) }

    private func open() throws -> (ModelContainer, LedgerStore) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(url: database))
        return (container, LedgerStore(context: container.mainContext))
    }

    private func addAccount(_ store: LedgerStore, _ name: String) throws {
        _ = try store.createAccount(name: name, kind: .bank, opening: Money(500, currency: "EUR"), openingDate: Date())
    }

    @Test("After an erase, the next launch starts a brand-new database file")
    func eraseReplacesTheFile() throws {
        do {
            let (container, store) = try open()
            for i in 1...5 { try addAccount(store, "Old \(i)") }
            try store.eraseAllData()
            #expect(FileManager.default.fileExists(atPath: marker.path))
            _ = container
        }
        LedgerStore.replaceErasedDatabase(at: database)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: database.path))

        let (container, store) = try open()
        try addAccount(store, "New")
        #expect(store.snapshot.accounts.map(\.name) == ["New"])
        _ = container
        try? FileManager.default.removeItem(at: folder)
    }

    @Test("Anything saved after an erase is kept: the file is not thrown away")
    func newDataAfterEraseSurvives() throws {
        do {
            let (container, store) = try open()
            try addAccount(store, "Old")
            try store.eraseAllData()
            #expect(FileManager.default.fileExists(atPath: marker.path))
            try addAccount(store, "Started again")
            #expect(!FileManager.default.fileExists(atPath: marker.path))
            _ = container
        }
        LedgerStore.replaceErasedDatabase(at: database)
        #expect(FileManager.default.fileExists(atPath: database.path))
        let (container, store) = try open()
        #expect(store.snapshot.accounts.map(\.name) == ["Started again"])
        _ = container
        try? FileManager.default.removeItem(at: folder)
    }
}
