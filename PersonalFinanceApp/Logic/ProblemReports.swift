//  ProblemReports.swift — crash reports from iOS (MetricKit), kept on this iPhone.
//  Nothing is sent anywhere: a report leaves the phone only when the person shares it from Settings › Data.
//  A report holds where the app stopped, the iOS version and the app version; no accounts, entries or amounts.

import Foundation
import MetricKit

final class ProblemReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = ProblemReports()
    static let kept = 5

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProblemReports", isDirectory: true)
    }

    /// iOS delivers a crash report the next time the app runs, usually within a day
    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads where !(payload.crashDiagnostics ?? []).isEmpty {
            Self.save(payload.jsonRepresentation(), at: payload.timeStampEnd, in: Self.folder)
        }
    }

    /// Saves one report and keeps only the newest few
    static func save(_ report: Data, at date: Date, in folder: URL) {
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        // Sorts by name, oldest first; the stamp is not shown to anyone
        let name = "report-\(Int(date.timeIntervalSince1970)).json"
        try? report.write(to: folder.appendingPathComponent(name), options: .atomic)
        let all = reports(in: folder)
        for old in all.dropLast(kept) { try? files.removeItem(at: old) }
    }

    static func reports(in folder: URL) -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return found.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The newest report, to share
    static var latest: URL? { reports(in: folder).last }
}
