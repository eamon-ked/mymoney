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
        // The crash in 2.1.3: the handler belonged to the main thread, but iOS ran it on a background queue and
        // Swift stopped the app. Now it's both asked for on the main queue and tied to no thread itself (@Sendable),
        // so wherever iOS runs it, it only hands the work to the main thread.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { @Sendable task in
            nonisolated(unsafe) let task = task
            // iOS may call the expiration handler from any thread too, so it only cancels
            task.expirationHandler = run { success in task.setTaskCompleted(success: success) }
        }
    }

    /// The wake-up's work, safe to start from any thread: it runs on the main thread, reports when it's done,
    /// and gives back a way to stop it early
    nonisolated static func run(completed: @escaping @Sendable (Bool) -> Void) -> @Sendable () -> Void {
        let work = Task { @MainActor in
            let services = AppServices.shared
            services.store.extendSchedules()
            WidgetSync.update(services.store.snapshot, isPlus: services.plus.isPlus)
            await Notifications.sync(services.store.snapshot)
            schedule()
            completed(!Task.isCancelled)
        }
        return { work.cancel() }
    }

    /// Asks for the next wake-up; iOS decides when, from how the phone is used
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
