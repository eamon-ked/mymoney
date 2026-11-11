//
//  BackgroundRefresh.swift
//  Nokael Money
//
//  A few times a day iOS may wake the app briefly. It fills bill schedules
//  ahead and replans notifications and the widget, so what they say stays
//  current even when the app isn't opened for a while.
//

import BackgroundTasks
import NokaelCore

@MainActor
enum BackgroundRefresh {
    static let identifier = "nokael.refresh"

    static func register() {
        // iOS runs the handler on the queue given here. This type belongs to the main thread, so it must be
        // the main queue: with none, iOS uses a background one and Swift stops the app (the crash in 2.1.3).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            nonisolated(unsafe) let task = task
            let work = Task { @MainActor in
                let services = AppServices.shared
                services.store.extendSchedules()
                WidgetSync.update(services.store.snapshot, isPlus: services.plus.isPlus)
                await Notifications.sync(services.store.snapshot)
                schedule()
                task.setTaskCompleted(success: !Task.isCancelled)
            }
            // iOS may call this from any thread, so it must not be tied to the main one
            task.expirationHandler = { @Sendable in work.cancel() }
        }
    }

    /// Asks for the next wake-up; iOS decides when, from how the phone is used
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
