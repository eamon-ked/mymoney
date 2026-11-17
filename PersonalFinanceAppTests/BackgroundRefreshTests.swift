//
//  BackgroundRefreshTests.swift
//  Nokael Money
//
//  iOS starts the wake-up on a background thread. In 2.1.3 that stopped the app; it must just do the work.
//

import Foundation
import Testing
@testable import PersonalFinanceApp

struct BackgroundRefreshTests {
    @Test func aWakeUpStartedOffTheMainThreadFinishes() async {
        let success = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .background).async {
                #expect(!Thread.isMainThread)
                _ = BackgroundRefresh.run { done.resume(returning: $0) }
            }
        }
        #expect(success)
    }
}
