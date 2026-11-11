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

    /// Onboarding with one bank account and a typed balance; pay, bills and budget are left for Home
    private func completeSetup(balance: String = "12000") {
        app.buttons["getStarted"].tap()
        app.buttons["continue"].tap()
        let enter = app.buttons["enterBalance"]
        XCTAssertTrue(enter.waitForExistence(timeout: 5))
        enter.tap()
        type(balance, into: "openingBalance")
        app.buttons["saveAccount"].tap()
        // Setup ends on the accounts added, then Home
        let home = app.buttons["finish"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
    }

    /// A bank account started from a statement: its balance, a check against the bank app,
    /// then Home offering the pay and loan the statement showed
    @MainActor
    func testSetupFromAStatement() {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/statement.csv")
        launch(["-uiTesting", "-importSample", file.path])
        app.buttons["getStarted"].tap()
        type("Sam", into: "firstName")
        app.buttons["continue"].tap()
        let importButton = app.buttons["importStatement"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()
        let add = app.buttons["addImported"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "The statement's rows are listed")
        XCTAssertTrue(NSPredicate(format: "isEnabled == true").evaluate(with: add) || waitEnabled(add), "Every row has a category")
        // The loan instalment asks which loan, and starts one in a tap
        let whichLoan = app.buttons["Which loan?"]
        for _ in 0..<12 where !whichLoan.isHittable { app.swipeUp() }
        whichLoan.tap()
        let newLoan = app.buttons["addLoanFromRow"]
        XCTAssertTrue(newLoan.waitForExistence(timeout: 5))
        newLoan.tap()
        expect("Pays Loan …2001", "The instalment goes to the new loan")
        add.tap()
        expect("Matches your statement", "The account starts from the statement and ends on its balance")
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["balanceRight"].waitForExistence(timeout: 5))
        expect("AED 176.19", "Asks about the statement's closing balance")
        app.buttons["balanceDifferent"].tap()
        type("121.19", into: "bankBalance")
        app.buttons["useBalance"].tap()

        let home = app.buttons["finish"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        expect("AED 121.19", "The account now holds what the bank app shows")
        home.tap()
        XCTAssertTrue(app.descendants(matching: .any)["safeToSpend"].waitForExistence(timeout: 5), "Setup ends on Home")
        expect("Sam", "Home greets them by name")
        expect("your monthly pay", "Home offers the pay the statement showed")
        expect("How much is left on Loan …2001?", "Home asks what's owed on the loan")
        element("How much is left on Loan …2001?").tap()
        type("Construction", into: "loanName")
        type("244561.31", into: "loanOwed")
        app.buttons["finishLoan"].tap()
        XCTAssertTrue(element("How much is left").waitForNonExistence(timeout: 5), "Home stops asking once it's finished")
    }

    /// A statement whose column names the app doesn't know: the person picks which is which, then adds
    @MainActor
    func testChoosingAStatementsColumns() {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/odd-columns.csv")
        launch(["-demoData", "-screen", "import", "-importSample", file.path])
        // Two money columns, no balance, names that say nothing: the app asks, and says why
        expect("Which column is which?", "Columns nothing in the file tells apart ask instead of failing")
        expect("Side 1 and Side 2 both hold money, and nothing in the file says which is money out. Pick them below.", "The reason is given")
        func pick(_ role: String, _ column: String) {
            let menu = app.buttons["column.\(role)"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.tap()
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", column)).firstMatch
            if !item.waitForExistence(timeout: 2) { menu.tap() }
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(column) is offered for \(role)")
            item.tap()
        }
        // The dates and descriptions were worked out already; only the money is left
        app.buttons["Money out and in"].tap()
        pick("Money out", "Side 1")
        pick("Money in", "Side 2")
        let use = app.buttons["useColumns"]
        XCTAssertTrue(waitEnabled(use), "Every role has a column")
        use.tap()
        XCTAssertTrue(app.buttons["addImported"].waitForExistence(timeout: 5), "The rows are listed")
        expect("CARREFOUR", "The description comes from the chosen column")
        XCTAssertTrue(app.buttons["statementColumns"].exists, "The columns can be changed again")
    }

    /// Two bank messages about one payment: one entry, opened from its record, split back into two,
    /// one deleted, then restored from its record
    func testBankMessagesJoinedThenSeparatedAndRestored() {
        let viaApp = "AED210.00 transferred via Example Personal Internet Banking / Mobile App from acc. no. XXX450002. Avl. bal. AED 31.70."
        let confirmation = "Confirmation recd. from SECOND NATIONAL BANK PJSC: AED 210.00 transferred to SAMIRA OKELLO has been credited."
        launch(["-demoData", "-captureMessages", viaApp + "|||" + confirmation, "-screen", "capture"])
        // The newest record is the confirmation, which joined the first
        let newest = app.buttons["captureTrace.0"]
        XCTAssertTrue(newest.waitForExistence(timeout: 10), "The records are listed")
        newest.tap()
        let open = app.buttons["openTraceEntry"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertEqual(open.label, "Open the entry it joined")
        open.tap()
        expect("From 2 bank messages", "The entry lists both messages")
        expect("Samira Okello", "The person's name replaced the bank's channel")
        let separate = app.buttons["separatePayment"]
        XCTAssertTrue(separate.waitForExistence(timeout: 5))
        separate.tap()
        expect("Saved as its own payment. It's on To check.", "The joined message is its own payment again")
        // Delete the entry, then bring it back from its record
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        // Wait for the undo message to go, then touch the button itself:
        // the page's layers report themselves as on top of it to the test
        let undo = app.buttons["Undo"].firstMatch
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: undo)], timeout: 15)
        for _ in 0..<2 where !delete.isHittable { app.swipeUp() }
        delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Delete this transaction?"].waitForExistence(timeout: 5), "Asks before deleting")
        let inDialog = app.popovers.buttons["Delete"]
        (inDialog.exists ? inDialog : app.sheets.buttons["Delete"]).tap()
        expect("Transaction deleted.", "Deleted")
        let older = app.buttons["captureTrace.1"]
        XCTAssertTrue(older.waitForExistence(timeout: 5))
        older.tap()
        let deleted = app.buttons["openTraceEntry"].firstMatch
        XCTAssertTrue(deleted.waitForExistence(timeout: 5))
        XCTAssertEqual(deleted.label, "Open the deleted entry")
        deleted.tap()
        let restore = app.buttons["restoreEntry"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        expect("Restored.", "The deleted entry is back")
    }

    /// "Add another account" tapped by mistake: Back returns to the list, Cancel goes to Home,
    /// and an account started for a statement that never came isn't left behind
    @MainActor
    func testAddAnotherAccountCanBeLeft() {
        launch(["-uiTesting"])
        app.buttons["getStarted"].tap()
        app.buttons["continue"].tap()
        let enter = app.buttons["enterBalance"]
        XCTAssertTrue(enter.waitForExistence(timeout: 5))
        enter.tap()
        type("500", into: "openingBalance")
        app.buttons["saveAccount"].tap()

        let another = app.buttons["addAnother"]
        XCTAssertTrue(another.waitForExistence(timeout: 5))
        another.tap()
        let back = app.buttons["back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "There's a way back from Add another account")
        back.tap()
        XCTAssertTrue(another.waitForExistence(timeout: 5), "Back on the list of accounts")

        another.tap()
        app.buttons["importStatement"].tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let cancel = app.buttons["cancelAddAccount"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.descendants(matching: .any)["safeToSpend"].waitForExistence(timeout: 5), "Cancel goes to Home")
        XCTAssertFalse(element("Account 2").exists, "The account started for the statement isn't left behind")
    }

    private func waitEnabled(_ el: XCUIElement) -> Bool {
        let done = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: el)
        return XCTWaiter.wait(for: [done], timeout: 20) == .completed
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

    /// Lending starts from What happened?, and a new name becomes a person under People
    @MainActor
    func testLendToSomeoneNew() {
        launch(["-uiTesting"])
        completeSetup()
        app.buttons["globalAdd"].tap()
        app.buttons["More…"].tap()
        tapScrolling(app.buttons["add-I lent someone money"], "I lent someone money")
        type("Sam", into: "personName")
        type("200", into: "lentAmount")
        tapScrolling(app.buttons["saveLent"], "Save")
        waitUntilGone(app.textFields["lentAmount"])
        tab("Accounts")
        expect("PEOPLE", "People have their own group")
        expect("Owes you", "Sam owes the money back")
        expect("AED 11,800", "The account is down by 200")
    }

    /// A 300 dinner split evenly three ways: the account pays 300, each friend owes 100
    @MainActor
    func testSplitABill() {
        launch(["-uiTesting"])
        completeSetup()
        app.buttons["globalAdd"].tap()
        app.buttons["Add Expense"].tap()
        type("300", into: "amountField")
        choose("Groceries", in: "Category")
        let toggle = app.switches["splitToggle"].firstMatch
        tapScrolling(toggle.exists ? toggle : app.descendants(matching: .any)["splitToggle"].firstMatch, "Split")
        let names = app.textFields.matching(identifier: "shareName")
        XCTAssertTrue(names.firstMatch.waitForExistence(timeout: 3), "A share row appears")
        names.element(boundBy: 0).tap(); names.element(boundBy: 0).typeText("Sam")
        tapScrolling(app.buttons["addShare"], "Add person")
        names.element(boundBy: 1).tap(); names.element(boundBy: 1).typeText("Alex")
        tapScrolling(app.buttons["splitEvenly"], "Split evenly")
        expect("Your share AED 100", "Each pays a third")
        tapScrolling(app.buttons["saveEntry"], "Save")
        waitUntilGone(app.textFields["amountField"])
        tab("Accounts")
        expect("AED 11,700", "The account paid the whole bill")
        expect("PEOPLE", "Sam and Alex are under People")
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
    func testPlusOffersATransactionOnEveryTab() {
        launch(["-demoData", "-plus", "-tab", "budget"])
        for (tabName, own) in [("Accounts", "Add Account"), ("Accounts", "Add Cash"), ("Budget", "Add Category"), ("Bills", "Add Bill")] {
            tab(tabName)
            app.buttons["globalAdd"].tap()
            XCTAssertTrue(app.buttons[own].waitForExistence(timeout: 3), "\(tabName) offers its own add")
            XCTAssertTrue(app.buttons["Add Expense"].exists, "\(tabName) offers an expense")
            app.buttons["globalAdd"].tap()
            sleep(1)
        }
        app.buttons["globalAdd"].tap()
        // The menu opens with an animation; tapping before it's there taps nothing
        XCTAssertTrue(app.buttons["Add Expense"].waitForExistence(timeout: 3), "Bills offers an expense")
        app.buttons["Add Expense"].tap()
        XCTAssertTrue(app.textFields["amountField"].waitForExistence(timeout: 5), "The expense form opens from Bills")
    }

    /// The last rows of a long tab scroll clear of the floating + and tab bar
    @MainActor
    func testLastRowClearsTheTabBar() {
        launch(["-demoData", "-plus", "-tab", "budget"])
        let last = element("Emergency fund")
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertTrue(last.waitForExistence(timeout: 3))
        let plus = app.buttons["globalAdd"]
        XCTAssertLessThanOrEqual(last.frame.maxY, plus.frame.minY, "The last row ends above the +")
    }

    /// The period picked on the breakdown is the one Home shows
    @MainActor
    func testSafeToSpendPeriodCarriesToHome() {
        launch(["-demoData", "-plus"])
        app.descendants(matching: .any)["safeToSpend"].tap()
        let week = app.buttons["7 days"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        app.buttons["Close"].firstMatch.tap()
        expect("for the next 7 days", "Home shows the chosen period")
        // Leave the next run on the usual period
        app.descendants(matching: .any)["safeToSpend"].tap()
        XCTAssertTrue(app.buttons["Until payday"].waitForExistence(timeout: 5))
        app.buttons["Until payday"].tap()
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
        XCTAssertTrue(app.buttons["add-I have cash"].exists, "Cash can be added from What happened?")
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

    /// Free keeps an accurate picture: the first statement import and export need no Plus
    @MainActor
    func testFreeImportAndExport() {
        launch(["-demoData", "-noPlus", "-tab", "more"])
        tapScrolling(button("Import a statement"), "Import a statement")
        XCTAssertTrue(element("Which account is the statement for?").waitForExistence(timeout: 5), "The first import is free")
        app.buttons["Close"].firstMatch.tap()
        sleep(1)
        tapScrolling(button("Backup & your data"), "Backup & your data")
        let export = button("Export all entries")
        tapScrolling(export, "Export")
        XCTAssertFalse(element("Your money, tracked automatically").waitForExistence(timeout: 2), "Export doesn't ask for Plus")
    }

    @MainActor
    func testPaywallWithoutPlus() {
        launch(["-demoData", "-noPlus", "-tab", "more"])
        tapScrolling(button("Money ahead"), "Money ahead")
        XCTAssertTrue(element("Nokael Plus").waitForExistence(timeout: 5), "Money ahead asks for Plus")
    }

    /// Standard Privacy Mode hides amounts written into saved text too, not only figures
    @MainActor
    func testStandardPrivacyHidesAmountsInHistory() {
        launch(["-demoData", "-plus"])
        let hide = app.buttons["Hide amounts"]
        if hide.waitForExistence(timeout: 5) { hide.tap() }
        XCTAssertTrue(app.buttons["Show amounts"].exists, "Privacy must be on")
        tab("More")
        tapScrolling(button("Privacy & Security"), "Privacy & Security")
        tapScrolling(button("Privacy Mode"), "Privacy Mode")
        app.buttons["Standard"].tap()
        tab("More")
        tapScrolling(button("Backup & your data"), "Backup & your data")
        tapScrolling(button("Change history"), "Change history")
        let exposed = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*AED.*[0-9].*")).firstMatch
        XCTAssertFalse(exposed.exists, "Standard Privacy Mode must hide amount-bearing history text")
        // Privacy Mode is remembered between launches: leave it off for the journeys after this one
        tab("Home")
        let show = app.buttons["Show amounts"]
        if show.waitForExistence(timeout: 5) { show.tap() }
        XCTAssertTrue(app.buttons["Hide amounts"].waitForExistence(timeout: 5), "Privacy is off again")
    }
}
