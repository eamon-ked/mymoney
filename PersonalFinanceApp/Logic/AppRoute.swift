//
//  AppRoute.swift
//  Nokael Money
//
//  The places the app can be asked to open from outside a screen: a tapped
//  reminder today, and anything else later. Whatever the screens look like,
//  the root view handles every AppRoute and clears `AppRouter.shared.pending`.
//

import Foundation
import NokaelCore

enum AppTab: Hashable { case home, budget, activity, accounts, reports }

enum AppRoute: Equatable {
    case tab(AppTab)
    /// Bills and expected income, from a tapped bill reminder
    case bills
}

/// Holds a route until the screens are ready for it, so a reminder tapped
/// while the app was closed still opens the right place once it has launched
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var pending: AppRoute?

    func open(_ route: AppRoute) { pending = route }
}

/// "I received my salary": opens Payday, with the amount the person said if any
struct PaydayRequest: Identifiable {
    let id = UUID()
    let said: Money?
}
