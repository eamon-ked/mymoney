//
//  JourneyUITests.swift
//  Nokael Money
//
//  The main journeys, driven through the real interface: setup on a fresh
//  in-memory store, then each money-changing flow on the demo household,
//  checking the numbers afterwards.
//  Demo: Emirates NBD Current 10,791 · Wio Savings 27,000 · car loan 36,500 at 4.99%, 1,850 a month ·
//  personal loan 11,165 · "Japan trip" goal 6,000 of 15,000 · Rent 6,500 due in 3 days
//

import XCTest

final class JourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name + "-end"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Currency follows the phone's region; these journeys check AED amounts
    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments + ["-AppleLocale", "en_AE"]
        app.launch()
    }

    /// Any element whose label contains the text. Currency formatting puts a non-breaking space after the code.
    private func element(_ text: String) -> XCUIElement {
        let nbsp = text.replacingOccurrences(of: "AED ", with: "AED\u{00A0}")
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", text, nbsp)).firstMatch
    }

    private func button(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func tapScrolling(_ el: XCUIElement, _ what: String) {
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeUp() }
        XCTAssertTrue(el.waitForExistence(timeout: 3), "No \(what)")
        el.tap()
    }

    private func expect(_ text: String, _ why: String) {
        let el = element(text)
        for _ in 0..<6 where !el.exists { app.swipeUp() }
        XCTAssertTrue(el.waitForExistence(timeout: 5), why)
    }

    private func tab(_ name: String) {
        app.buttons[name].firstMatch.tap()
        sleep(1)
    }

    /// Types into a field, then closes the keyboard with its Done key when it has one
    private func type(_ text: String, into id: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No field \(id)")
        field.tap()
        field.typeText(text)
        let done = app.toolbars.buttons["Done"]
        if done.waitForExistence(timeout: 1) { done.tap() }
    }

    /// Picks an option from a form's menu, labelled by the field's caption
    private func choose(_ option: String, in field: String) {
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", field)).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 3), "No \(field) menu")
        menu.tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3), "No \(option) in \(field)")
        item.tap()
    }

    private func waitUntilGone(_ el: XCUIElement) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: el)
        waitForExpectations(timeout: 10)
    }

    // MARK: - Setup

    /// Onboarding with one account and no optional steps
    private func completeSetup(balance: String = "12000") {
        app.buttons["getStarted"].tap()
        app.buttons["continue"].tap()
        app.buttons["newAccount"].tap()
        type("Current account", into: "accountName")
        type(balance, into: "openingBalance")
        app.buttons["addAccount"].tap()
        waitUntilGone(app.textFields["accountName"])
        app.buttons["continue"].tap()
        let skip = app.buttons["skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["continue"].tap()
        XCTAssertTrue(element("Plan the essentials").waitForExistence(timeout: 5))
        // The last step ends on what's actually free to spend, below the essentials
        let finish = app.buttons["finish"]
        for _ in 0..<4 where !finish.isHittable { app.swipeUp() }
        XCTAssertTrue(element("Safe to spend").exists)
        finish.tap()
    }

    @MainActor
    func testSetupThenFirstBudget() {
        launch(["-uiTesting"])
        completeSetup()
        XCTAssertTrue(app.descendants(matching: .any)["safeToSpend"].waitForExistence(timeout: 5))
        expect("AED 12,000", "Home shows the opening balance as cash")

        tab("Budget")
        tapScrolling(element("Groceries"), "Groceries")
        type("1500", into: "allocationField")
        expect("AED 1,500", "Groceries is planned at 1,500")
        // Allocating doesn't move money
        app.buttons["Close"].firstMatch.tap()
        tab("Accounts")
        expect("AED 12,000", "The account still holds 12,000")
    }

    @MainActor
    func testAddAnExpenseOnce() {
        launch(["-uiTesting"])
        completeSetup()
        app.buttons["globalAdd"].tap()
        app.buttons["Add Expense"].tap()
        type("85", into: "amountField")
        choose("Groceries", in: "Category")
        let save = app.buttons["saveEntry"]
        tapScrolling(save, "Save")
        if save.exists && save.isHittable { save.tap() }
        waitUntilGone(app.textFields["amountField"])
        tab("Accounts")
        expect("AED 11,915", "The account is down by 85, once")
    }

    // MARK: - Demo household

    @MainActor
    func testTransfer() {
        launch(["-demoData", "-plus"])
        app.buttons["globalAdd"].tap()
        app.buttons["Transfer Money"].tap()
        type("1000", into: "amountField")
        choose("Wio Savings", in: "To account")
        tapScrolling(app.buttons["saveEntry"], "Save")
        waitUntilGone(app.textFields["amountField"])
        tab("Accounts")
        expect("AED 9,791", "Current drops by 1,000")
        expect("AED 28,000", "Savings rises by 1,000")
    }

    @MainActor
    func testPayABill() {
        launch(["-demoData", "-plus", "-tab", "bills"])
        tapScrolling(button("Rent"), "Rent")
        tapScrolling(button("Record Payment"), "Record Payment")
        tapScrolling(button("Save payment"), "Save payment")
        sleep(1)
        tab("Accounts")
        expect("AED 4,291", "Current drops by the 6,500 rent")
    }

    @MainActor
    func testPayTheCarLoan() {
        launch(["-demoData", "-plus", "-tab", "accounts"])
        tapScrolling(button("Car loan"), "Car loan")
        app.buttons["payDebt"].tap()
        XCTAssertTrue(app.textFields["debtPaymentAmount"].waitForExistence(timeout: 5))
        // One month's interest at 4.99% on 36,500 is 151.78, so 1,698.22 comes off
        expect("AED 151.78", "The interest is split off")
        tapScrolling(app.buttons["recordDebtPayment"], "Save")
        expect("AED 34,801.78", "What's owed drops by the principal only")
    }

    @MainActor
    func testSavingTowardsAGoal() {
        launch(["-demoData", "-plus", "-tab", "budget"])
        tapScrolling(button("Japan trip"), "Japan trip")
        app.buttons["addToGoal"].tap()
        type("1000", into: "goalAmount")
        app.buttons["saveGoalMoney"].tap()
        expect("AED 7,000", "The goal has 7,000")
    }

    @MainActor
    func testPayday() {
        launch(["-demoData", "-plus", "-screen", "payday"])
        tapScrolling(app.buttons["paydayDoIt"], "Do it")
        expect("Safe to spend is now", "Payday says what's free afterwards")
    }

    @MainActor
    func testWhatHappenedOpensEachForm() {
        launch(["-demoData", "-plus"])
        app.buttons["globalAdd"].tap()
        app.buttons["More…"].tap()
        XCTAssertTrue(app.buttons["add-I paid a loan or credit card"].waitForExistence(timeout: 5))
        app.buttons["add-A balance is wrong"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMoreOpensEveryPage() {
        launch(["-demoData", "-plus", "-tab", "more"])
        for row in ["Activity", "Reports", "Money ahead", "Siri & automatic capture", "My Profile", "Settings",
                    "Privacy & Security", "Backup & your data", "Nokael Plus", "Help & Support"] {
            tapScrolling(button(row), row)
            XCTAssertTrue(app.navigationBars[row].waitForExistence(timeout: 5), "\(row) didn't open")
            app.navigationBars[row].buttons.firstMatch.tap()
            sleep(1)
        }
    }

    @MainActor
    func testPaywallWithoutPlus() {
        launch(["-demoData", "-noPlus", "-tab", "more"])
        tapScrolling(button("Money ahead"), "Money ahead")
        XCTAssertTrue(element("Nokael Plus").waitForExistence(timeout: 5), "Money ahead asks for Plus")
    }
}
