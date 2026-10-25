//
//  BackupViews.swift
//  Nokael Money
//
//  Saving a backup file wherever the person chooses (iCloud Drive, Files, a
//  computer), and restoring from one after checking it and confirming.
//

import SwiftUI
import UniformTypeIdentifiers
import NokaelCore

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// The Backup section in Settings
struct BackupSection: View {
    @Environment(LedgerStore.self) private var store
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var restoring = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        Section {
            Button { save() } label: { Label("Save a backup", systemImage: "externaldrive.badge.plus") }
                .accessibilityIdentifier("saveBackup")
            Button { restoring = true } label: { Label("Restore from a backup", systemImage: "clock.arrow.circlepath") }
            if let message { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.footnote) }
            FieldError(message: error)
        } header: {
            Text("Backup")
        } footer: {
            Text(footer)
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "Nokael Money backup \(LedgerStore.fileStamp(Date()))") { result in
            switch result {
            case .success:
                store.markBackedUp()
                message = "Backup saved."
            case .failure(let failure):
                if (failure as NSError).code != NSUserCancelledError { error = "Couldn't save the backup." }
            }
        }
        .restoreFromBackup(isPresented: $restoring) { safetyCopy in
            message = safetyCopy == nil ? "Backup restored." : "Backup restored. Your previous data was saved in Files → Nokael Money → Backups."
        }
    }

    private var footer: String {
        let status = store.settings.lastBackupAt.map { "Last backup " + $0.formatted(.relative(presentation: .named)) + "." }
            ?? "No backup yet."
        return status + " Your data is only on this iPhone. Save a backup to iCloud Drive or another place you trust, so you can restore it if the phone is lost or replaced."
    }

    private func save() {
        error = nil
        message = nil
        do {
            document = BackupDocument(data: try store.backupData())
            exporting = true
        } catch { self.error = "Couldn't create the backup." }
    }
}

extension View {
    /// Picks a backup file, checks it, asks to confirm, then restores it
    func restoreFromBackup(isPresented: Binding<Bool>, onRestored: @escaping (URL?) -> Void = { _ in }) -> some View {
        modifier(RestoreFlow(isPresented: isPresented, onRestored: onRestored))
    }
}

private struct RestoreFlow: ViewModifier {
    @Environment(LedgerStore.self) private var store
    @Binding var isPresented: Bool
    let onRestored: (URL?) -> Void
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
                        let copy = try store.restore(backup)
                        onRestored(copy)
                    } catch { self.error = "The restore didn't finish, so please try again. \(StoreError.from(error).errorDescription ?? "")" }
                    pending = nil
                }
            } message: { backup in
                Text("Backup from \(backup.createdAt.formatted(date: .long, time: .shortened)): \(backup.summary). What's on this iPhone now is saved to Files → Nokael Money → Backups first.")
            }
            .alert("Couldn't restore", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }
}
