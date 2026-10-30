//
//  JourneyUITests.swift
//  Nokael Money
//
//  The spec's end-to-end journeys, driven through the real interface on a
//  fresh in-memory store.
//

import XCTest

final class JourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Currency follows the phone's region; these journeys check AED amounts
        app.launchArguments = ["-uiTesting", "-AppleLocale", "en_AE"]
        app.launch()
    }

    /// Any element whose accessibility label contains the text. Rows combine
    /// their texts into one label, the way VoiceOver reads them. Currency
    /// formatting puts a non-breaking space after the code, so "AED " matches it.
    private func element(containing text: String) -> XCUIElement {
        let formatted = text.replacingOccurrences(of: "AED ", with: "AED\u{00A0}")
        let predicate = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", text, formatted)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Switches tab, tapping again if the first tap lands mid-transition
    private func open(tab: String, title: String) {
        for _ in 0..<3 {
            app.tabBars.buttons[tab].tap()
            if app.navigationBars[title].waitForExistence(timeout: 3) { return }
        }
        XCTFail("Couldn't open the \(tab) tab")
    }

    /// Waits for the entry editor to close after saving
    private func waitForEditorToClose() {
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.textFields["amountField"])
        waitForExpectations(timeout: 10)
    }

    /// Onboarding with one account and no optional steps
    private func completeSetup(balance: String = "12000") {
        app.buttons["getStarted"].tap()
        app.buttons["continue"].tap()

        let name = app.textFields["accountName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Current account")
        let opening = app.textFields["openingBalance"]
        opening.tap()
        opening.typeText(balance)
        app.buttons["addAccount"].tap()

        let skip = app.buttons["skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        let bills = app.buttons["continue"]
        XCTAssertTrue(bills.waitForExistence(timeout: 5))
        bills.tap()
        XCTAssertTrue(element(containing: "Plan the essentials").waitForExistence(timeout: 5))
        // The last step ends on what's actually free to spend, below the essentials
        let finish = app.buttons["finish"]
        for _ in 0..<4 where !finish.isHittable { app.swipeUp() }
        XCTAssertTrue(element(containing: "Safe to spend").exists)
        XCTAssertTrue(finish.isHittable)
        finish.tap()
    }

    @MainActor
    func testJourneyA_FirstAccountAndFirstBudget() throws {
        completeSetup()

        // Home shows a real safe-to-spend from the opening balance
        XCTAssertTrue(app.descendants(matching: .any)["safeToSpend"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "AED 12,000").waitForExistence(timeout: 5))

        // Plan groceries for the month
        open(tab: "Budget", title: "Budget")
        let groceries = element(containing: "Groceries")
        XCTAssertTrue(groceries.waitForExistence(timeout: 5))
        groceries.tap()
        let allocation = app.textFields["allocationField"]
        XCTAssertTrue(allocation.waitForExistence(timeout: 5))
        allocation.tap()
        allocation.typeText("1500")
        app.buttons["Done"].tap()

        XCTAssertTrue(element(containing: "AED 1,500 left").waitForExistence(timeout: 5))
        // Allocating doesn't move money: the account still holds 12,000
        open(tab: "Accounts", title: "Accounts")
        XCTAssertTrue(element(containing: "AED 12,000").waitForExistence(timeout: 5))
    }

    @MainActor
    func testJourneyB_BuyGroceries() throws {
        completeSetup()

        // Add → "I spent money" → amount first
        app.buttons["globalAdd"].tap()
        app.buttons["add-I spent money"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("85")
        app.buttons["category-Groceries"].tap()
        app.buttons["saveEntry"].tap()
        waitForEditorToClose()

        // Account down by 85, once
        open(tab: "Accounts", title: "Accounts")
        XCTAssertTrue(element(containing: "AED 11,915").waitForExistence(timeout: 5))

        // It appears in Activity
        open(tab: "Activity", title: "Activity")
        XCTAssertTrue(element(containing: "Groceries").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containing: "−AED 85").waitForExistence(timeout: 5))
    }

    @MainActor
    func testDoubleTapSaveCreatesOneEntry() throws {
        completeSetup()
        app.buttons["globalAdd"].tap()
        app.buttons["add-I spent money"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.typeText("40")
        app.buttons["category-Groceries"].tap()
        let save = app.buttons["saveEntry"]
        save.tap()
        if save.isHittable { save.tap() }
        waitForEditorToClose()

        open(tab: "Accounts", title: "Accounts")
        XCTAssertTrue(element(containing: "AED 11,960").waitForExistence(timeout: 5))
    }

    @MainActor
    func testJourneyC_PayTheCarLoan() throws {
        // Demo household: car loan of 36,500 at 4.99%, 1,850 a month
        app.terminate()
        app.launchArguments = ["-demoData", "-tab", "accounts"]
        app.launch()

        let loanRow = element(containing: "Car loan, AED 1,850 a month")
        for _ in 0..<6 where !loanRow.isHittable { app.swipeUp() }
        loanRow.tap()
        XCTAssertTrue(element(containing: "Debt-free").waitForExistence(timeout: 5))

        app.buttons["payDebt"].tap()
        XCTAssertTrue(app.textFields["debtPaymentAmount"].waitForExistence(timeout: 5))
        // One month's interest at 4.99% on 36,500 is 151.78, so 1,698.22 comes off
        XCTAssertTrue(element(containing: "AED 151.78").exists)
        app.buttons["recordDebtPayment"].tap()

        XCTAssertTrue(element(containing: "AED 34,801.78").waitForExistence(timeout: 5))
    }

    @MainActor
    func testFixingALoanEnteredWrong() throws {
        // Demo household: personal loan added at 12,000, one payment of 900 with 65 interest, so 11,165 owed
        app.terminate()
        app.launchArguments = ["-demoData", "-tab", "accounts"]
        app.launch()

        let loanRow = element(containing: "Personal loan")
        for _ in 0..<6 where !loanRow.isHittable { app.swipeUp() }
        loanRow.tap()
        XCTAssertTrue(element(containing: "AED 11,165").waitForExistence(timeout: 5))

        // It was really 21,000. Tapping the amount selects it, so typing replaces it
        let edit = app.buttons["editDebt"]
        for _ in 0..<4 where !edit.isHittable { app.swipeUp() }
        edit.tap()
        let field = app.textFields["owedWhenAdded"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("21000")
        XCTAssertTrue(element(containing: "AED 20,165").waitForExistence(timeout: 3))
        app.buttons["saveTerms"].tap()
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(element(containing: "AED 20,165").waitForExistence(timeout: 5))

        // And the payment was 1,000, not 900; the 65 interest from the statement stays
        let payment = element(containing: "Personal loan payment")
        for _ in 0..<6 where !payment.isHittable { app.swipeUp() }
        payment.tap()
        app.buttons["Edit"].tap()
        let amount = app.textFields["debtPaymentAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("1000")
        app.buttons["recordDebtPayment"].tap()
        for _ in 0..<6 { app.swipeDown() }
        XCTAssertTrue(element(containing: "AED 20,065").waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavingTowardsAGoal() throws {
        // Demo household: "Japan trip", 6,000 of 15,000 saved in Wio Savings
        app.terminate()
        app.launchArguments = ["-demoData", "-tab", "budget"]
        app.launch()

        let goal = element(containing: "Japan trip, AED 6,000 of AED 15,000")
        for _ in 0..<8 where !goal.isHittable { app.swipeUp() }
        goal.tap()
        XCTAssertTrue(element(containing: "Each month").waitForExistence(timeout: 5))

        app.buttons["addToGoal"].tap()
        let amount = app.textFields["goalAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("1000")
        app.buttons["saveGoalMoney"].tap()

        XCTAssertTrue(element(containing: "AED 7,000").waitForExistence(timeout: 5))
    }
}
