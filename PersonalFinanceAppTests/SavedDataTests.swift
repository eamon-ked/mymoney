//  SavedDataTests.swift — a database saved by a released version must still open in today's code.
//  A change to the stored records that breaks this would lose people's data on update, so it fails here first.
//
//  Fixtures/saved-2.1.4.store holds made-up demo data, written by version 2.1.4. For each release that changes
//  the stored records, save a new fixture and keep the old ones:
//    TEST_RUNNER_SAVE_FIXTURE=/some/folder xcodebuild test ... -only-testing:PersonalFinanceAppTests/SavedDataTests
//    sqlite3 /some/folder/saved.store "PRAGMA wal_checkpoint(TRUNCATE);"   (then copy saved.store into Fixtures)

import Foundation
import SwiftData
import Testing
@testable import PersonalFinanceApp

private final class BundleToken {}

@MainActor
struct SavedDataTests {
    static let saveTo = ProcessInfo.processInfo.environment["SAVE_FIXTURE"]

    private func counts(_ context: ModelContext) throws -> [Int] {
        [try context.fetchCount(FetchDescriptor<LedgerAccountRecord>()),
         try context.fetchCount(FetchDescriptor<EntryRecord>()),
         try context.fetchCount(FetchDescriptor<LineRecord>()),
         try context.fetchCount(FetchDescriptor<PlannedItemRecord>()),
         try context.fetchCount(FetchDescriptor<SettingsRecord>())]
    }

    @Test("Data saved by version 2.1.4 opens with every record in place",
          arguments: [("saved-2.1.4", [22, 14, 29, 5, 1])])
    func savedDataStillOpens(name: String, expected: [Int]) throws {
        let fixture = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "store"))
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saved-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appendingPathComponent("opened.store")
        try FileManager.default.copyItem(at: fixture, to: database)

        let container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(url: database))
        #expect(try counts(container.mainContext) == expected)
        // The app's own reading of it works too, not only the raw records
        let store = LedgerStore(context: container.mainContext)
        #expect(!store.snapshot.accounts.isEmpty)
    }

    @Test("Save a fixture for this version", .enabled(if: saveTo != nil))
    func saveFixture() throws {
        let database = URL(fileURLWithPath: Self.saveTo!).appendingPathComponent("saved.store")
        let container = try ModelContainer(for: Schema(Schema1.models), configurations: ModelConfiguration(url: database))
        DemoData.load(into: LedgerStore(context: container.mainContext))
        try container.mainContext.save()
        print("FIXTURE COUNTS \(try counts(container.mainContext))")
    }
}
