import XCTest

// Temporary: every money-changing flow on demo data, checking the numbers afterwards.
// Demo: Emirates NBD Current 10,791 · Wio Savings 27,000 · card owes 2,741.50 · car loan 36,500 · personal loan 11,165
final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demoData", "-plus", "-AppleLocale", "en_AE"]
        app.launch()
    }

    override func tearDownWithError() throws {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name + "-end"
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-end-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func element(_ text: String) -> XCUIElement {
        let nbsp = text.replacingOccurrences(of: "AED ", with: "AED\u{00A0}")
        return app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", text, nbsp)).firstMatch
    }

    private func button(_ text: String) -> XCUIElement {
        let nbsp = text.replacingOccurrences(of: "AED ", with: "AED\u{00A0}")
        return app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", text, nbsp)).firstMatch
    }

    private func tapScrolling(_ el: XCUIElement, _ what: String) {
        for _ in 0..<6 where !(el.exists && el.isHittable) { app.swipeUp() }
        XCTAssertTrue(el.waitForExistence(timeout: 3), "No \(what)")
        el.tap()
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].tap()
        sleep(1)
        for _ in 0..<3 { app.swipeDown() }
    }

    private func expect(_ text: String, _ why: String) {
        let el = element(text)
        for _ in 0..<5 where !el.exists { app.swipeUp() }
        XCTAssertTrue(el.waitForExistence(timeout: 5), why)
    }

    private func add(_ choice: String) {
        app.buttons["globalAdd"].firstMatch.tap()
        let b = app.buttons["add-\(choice)"]
        XCTAssertTrue(b.waitForExistence(timeout: 5), "No add choice \(choice)")
        b.tap()
    }

    private func typeAmount(_ text: String) {
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText(text)
    }

    private func save() {
        app.buttons["saveEntry"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.textFields["amountField"])
        waitForExpectations(timeout: 10)
    }

    func testIncome() {
        add("I received money")
        typeAmount("500")
        app.buttons["category-Other income"].tap()
        save()
        tab("Accounts")
        expect("Emirates NBD Current, Bank account, AED 11,291", "Income should raise the current account by 500")
    }

    func testTransfer() {
        add("I moved money between my accounts")
        typeAmount("1000")
        button("To, Choose").tap()
        let savings = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Wio Savings'")).firstMatch
        XCTAssertTrue(savings.waitForExistence(timeout: 3)); savings.tap()
        save()
        tab("Accounts")
        expect("AED 9,791", "Current should drop by 1,000")
        expect("AED 28,000", "Savings should rise by 1,000")
    }

    func testBalanceIsWrong() {
        add("A balance is wrong")
        let record = XCTAttachment(string: app.debugDescription); record.lifetime = .keepAlways; record.name = "adjust-tree"; add(record)
        typeAmount("10700")
        let reason = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'reason' OR placeholderValue CONTAINS[c] 'why'")).firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 3), "No reason field")
        reason.tap(); reason.typeText("Bank fee I missed")
        save()
        tab("Accounts")
        expect("AED 10,700", "Current should be set to 10,700")
    }

    func testEditAnExpense() {
        tab("Activity")
        tapScrolling(button("Talabat"), "Talabat")
        app.buttons["Edit"].tap()
        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("60")
        save()
        sleep(1)
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        expect("−AED 60", "Talabat should now be 60")
        tab("Budget")
        expect("Dining out, AED 340 left", "Dining out should have 340 left")
    }

    func testDeleteAnEntry() {
        tab("Activity")
        tapScrolling(button("Salik top-up"), "Salik")
        app.buttons["Delete"].tap()
        sleep(1)
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }
        XCTAssertNotNil(confirm); confirm?.tap()
        sleep(1)
        XCTAssertFalse(button("Salik top-up").exists, "Salik should be gone")
        tab("Accounts")
        expect("Emirates NBD Current, Bank account, AED 10,911", "Current should be back up by 120")
        tab("Budget")
        expect("Transport, AED 500 left", "Transport should have its 500 back")
    }

    func testPayday() {
        add("I got my salary")
        let doIt = app.buttons["Do it"]
        XCTAssertTrue(doIt.waitForExistence(timeout: 5))
        doIt.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        sleep(1)
        tab("Accounts")
        // 18,000 in, then 1,125 of it moved to the Japan trip goal in savings
        expect("Emirates NBD Current, Bank account, AED 27,666", "Salary of 18,000 should land in Current")
        expect("Wio Savings, Savings account, AED 28,125", "1,125 should go to the goal's account")
    }

    func testPayABill() {
        add("I paid a bill")
        let rent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rent, AED'")).firstMatch
        XCTAssertTrue(rent.waitForExistence(timeout: 3), "Bills didn't expand"); rent.tap()
        let tree = XCTAttachment(string: app.debugDescription); tree.lifetime = .keepAlways; tree.name = "paybill-tree"; add(tree)
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pay' OR label BEGINSWITH 'Record' OR label == 'Paid' OR label == 'Save'")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()
        sleep(2)
        tab("Accounts")
        expect("Emirates NBD Current, Bank account, AED 4,291", "Rent of 6,500 should come out of Current")
    }

    func testPayTheCard() {
        add("I paid a loan or credit card")
        tapScrolling(button("Mashreq Cashback"), "card")
        let amount = app.textFields["debtPaymentAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("1000")
        app.buttons["recordDebtPayment"].tap()
        sleep(2)
        tab("Accounts")
        expect("Emirates NBD Current, Bank account, AED 9,791", "Current should drop by 1,000")
    }

    func testNewBill() {
        app.buttons["seeAllBills"].firstMatch.tap()
        let new = app.buttons["newBill"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        app.buttons["Bill"].firstMatch.tap()
        let name = app.textFields["billName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Gym")
        let amount = app.textFields["billAmount"]
        amount.tap(); amount.typeText("250")
        app.buttons["saveBill"].tap()
        sleep(1)
        expect("Gym", "The new bill should be listed")
    }

    func testAddALoan() {
        add("I have a loan or credit card")
        let name = app.textFields["loanName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Mortgage")
        let tree = XCTAttachment(string: app.debugDescription); tree.lifetime = .keepAlways; tree.name = "newloan-tree"; add(tree)
        let owed = app.textFields.matching(NSPredicate(format: "placeholderValue == '0'")).firstMatch
        owed.tap(); owed.typeText("500000")
        app.buttons["saveLoan"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        sleep(1)
        tab("Accounts")
        expect("Mortgage", "The loan should be listed")
        expect("AED 500,000", "It should owe 500,000")
    }

    /// Saving without a category must say why, where it can be seen
    func testSavingWithoutACategorySaysWhy() {
        add("I received money")
        typeAmount("500")
        app.buttons["saveEntry"].tap()
        sleep(1)
        XCTAssertTrue(app.textFields["amountField"].exists, "It shouldn't save without a category")
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Choose the kind of income'")).firstMatch
        XCTAssertTrue(message.exists && message.isHittable, "The reason it didn't save should be visible")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The keyboard shouldn't cover it")
    }

    // MARK: - Batch 3

    private func relaunch(_ args: [String]) {
        app.terminate()
        app.launchArguments = ["-demoData", "-AppleLocale", "en_AE"] + args
        app.launch()
    }

    private func snapshotTree(_ name: String) {
        let t = XCTAttachment(string: app.debugDescription); t.name = name + "-tree"; t.lifetime = .keepAlways; add(t)
        let i = XCTAttachment(screenshot: app.screenshot()); i.name = name; i.lifetime = .keepAlways; add(i)
    }

    func testMoveMoneyFixesOverspending() {
        tab("Budget")
        tapScrolling(button("Entertainment, AED 60 over"), "Entertainment")
        tapScrolling(button("Move money from another category"), "Move money")
        button("From, Choose").tap()
        let dining = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Dining out'")).firstMatch
        XCTAssertTrue(dining.waitForExistence(timeout: 3)); dining.tap()
        button("Cover the overspending").tap()
        snapshotTree("move-filled")
        app.buttons["Move"].tap()
        sleep(1)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(element("Entertainment went AED 60 over").exists, "Overspending should be gone")
        expect("Dining out, AED 282 left", "Dining out should have given up 60")
    }

    func testNewCategoryAndPlanIt() {
        tab("Budget")
        app.buttons["Filter and new category"].tap()
        app.buttons["New category"].tap()
        let name = app.textFields["categoryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Kids")
        app.buttons["Save"].tap()
        sleep(1)
        tapScrolling(button("Kids"), "Kids")
        let allocation = app.textFields["allocationField"]
        XCTAssertTrue(allocation.waitForExistence(timeout: 5)); allocation.tap(); allocation.typeText("300")
        app.buttons["Done"].tap()
        expect("Kids, AED 300 left", "The new category should have 300 planned")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        expect("Not planned yet, AED 16,740", "Planning 300 should leave 16,740 unplanned")
    }

    func testBudgetMonthsAndFilter() {
        tab("Budget")
        app.buttons["Previous month"].tap()
        expect("September 2026", "Should show September")
        app.buttons["Next month"].tap(); app.buttons["Next month"].tap()
        expect("November 2026", "Should show November")
        snapshotTree("budget-november")
        app.buttons["Previous month"].tap()
        app.buttons["Filter and new category"].tap()
        app.buttons["Over budget"].tap()
        sleep(1)
        XCTAssertTrue(button("Entertainment").exists, "Entertainment is over budget")
        XCTAssertFalse(button("Groceries, AED").exists, "Groceries isn't over budget")
    }

    func testNewGoalAndMoneyInAndOut() {
        tab("Budget")
        tapScrolling(app.buttons.matching(NSPredicate(format: "label == 'Add'")).element(boundBy: 1), "Savings Add")
        snapshotTree("savings-add")
        if app.buttons["New goal"].exists { app.buttons["New goal"].tap() }
        else if button("goal").exists { button("goal").tap() }
        let name = app.textFields["goalName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("New car")
        let target = app.textFields["goalTarget"]
        if target.exists { target.tap(); target.typeText("20000") }
        let saved = app.textFields["goalSaved"]
        if saved.exists { saved.tap(); saved.typeText("1000") }
        snapshotTree("goal-filled")
        app.buttons["saveGoal"].tap()
        sleep(1)
        expect("New car", "The goal should be listed")
        tapScrolling(button("New car"), "goal row")
        button("Take money out").tap()
        let amount = app.textFields["goalAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); amount.tap(); amount.typeText("400")
        app.buttons["saveGoalMoney"].tap()
        expect("AED 600", "Goal should hold 600 after taking 400 out")
    }

    func testNewAccount() {
        tab("Accounts")
        app.buttons["addAccountMenu"].tap()
        button("Bank account, cash or savings").tap()
        let name = app.textFields["accountName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Cash wallet")
        let opening = app.textFields["openingBalance"]
        opening.tap(); opening.typeText("750")
        app.buttons["Add"].tap()
        sleep(1)
        expect("Cash wallet", "The account should be listed")
        expect("Net worth, −AED 11,866", "Net worth should rise by 750")
    }

    func testCheckAgainstAStatement() {
        tab("Accounts")
        tapScrolling(button("Emirates NBD Current"), "Current")
        tapScrolling(button("Check against a statement"), "check")
        snapshotTree("reconcile-open")
        let balance = app.textFields.firstMatch
        balance.tap(); balance.typeText("10791")
        app.buttons["Confirm"].tap()
        sleep(1)
        snapshotTree("reconcile-after")
        expect("Checked against a statement", "The account should say it was checked")
    }

    func testActivityFilters() {
        tab("Activity")
        app.buttons["Transfers"].tap(); sleep(1)
        XCTAssertTrue(button("Move to savings").exists, "Transfers should show the move to savings")
        XCTAssertFalse(button("Talabat").exists, "Transfers shouldn't show expenses")
        app.buttons["Income"].tap(); sleep(1)
        XCTAssertFalse(button("Talabat").exists, "Income shouldn't show expenses")
        snapshotTree("activity-income")
        app.buttons["Expenses"].tap(); sleep(1)
        XCTAssertTrue(button("Talabat").exists)
        XCTAssertFalse(button("Move to savings").exists)
        let search = app.searchFields.firstMatch
        if search.exists {
            app.buttons["All"].tap()
            search.tap(); search.typeText("carrefour")
            sleep(1)
            XCTAssertFalse(button("Talabat").exists, "Search should narrow to Carrefour")
            XCTAssertTrue(button("Carrefour").exists)
        }
    }

    func testReports() {
        tab("Reports")
        expect("Loan payments", "Loan payments should be in Where it went")
        button("See all").tap()
        snapshotTree("reports-see-all")
        app.navigationBars.buttons.firstMatch.tap()
        app.swipeDown(); app.swipeDown()
        tapScrolling(button("Previous"), "previous month")
        sleep(1)
        snapshotTree("reports-september")
    }

    func testSettingsScreens() {
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
        snapshotTree("settings")
        for row in ["Siri & automatic capture", "Bill reminders", "Apple Intelligence", "Currency & categories", "Your data"] {
            let b = button(row)
            if b.waitForExistence(timeout: 3) {
                b.tap(); sleep(1)
                snapshotTree("settings-" + row)
                app.navigationBars.buttons.firstMatch.tap(); sleep(1)
            } else { XCTFail("No \(row)") }
        }
        button("Your data").tap()
        tapScrolling(button("Change history"), "history"); sleep(1)
        snapshotTree("settings-history")
        app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        button("Currency & categories").tap()
        tapScrolling(button("Categories"), "categories"); sleep(1)
        snapshotTree("settings-categories")
    }

    func testBackupAndCSV() {
        app.navigationBars.buttons.firstMatch.tap()
        let backup = app.buttons["saveBackup"]
        for _ in 0..<4 where !backup.isHittable { app.swipeUp() }
        XCTAssertTrue(backup.waitForExistence(timeout: 5)); backup.tap()
        sleep(2)
        snapshotTree("backup-share")
    }

    func testPaywallWithoutPlus() {
        relaunch([])
        tab("Reports")
        snapshotTree("reports-no-plus")
        tab("Home")
        tapScrolling(button("Money ahead"), "Money ahead")
        sleep(1)
        snapshotTree("money-ahead-no-plus")
    }

    func testCaptureBankSMS() {
        relaunch(["-plus", "-captureSMS", "Purchase of AED 45.00 at MAF CARREFOUR CITY with card ending 1234"])
        sleep(3)
        tab("Activity")
        snapshotTree("after-sms")
        expect("AED 45", "The SMS purchase should be recorded")
    }

    func testCaptureApplePay() {
        relaunch(["-plus", "-captureApplePay", "Mashreq Cashback|Starbucks|23.5"])
        sleep(3)
        tab("Activity")
        snapshotTree("after-applepay")
        expect("Starbucks", "The Apple Pay purchase should be recorded")
    }

    func testGuideAnswers() {
        relaunch(["-screen", "guide", "-ask", "How do I pay my car loan?"])
        sleep(4)
        snapshotTree("guide-answer")
    }

    // MARK: - Batch 4

    func testSkipAndStopABill() {
        app.buttons["seeAllBills"].firstMatch.tap()
        tapScrolling(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Du mobile, Sun'")).firstMatch, "Du mobile")
        snapshotTree("bill-occurrence")
        tapScrolling(button("Skip this one"), "skip")
        sleep(1)
        snapshotTree("bill-skipped")
        expect("Skipped", "It should say skipped")
        app.buttons["Done"].firstMatch.tap(); sleep(1)
        tapScrolling(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Du mobile, Monthly'")).firstMatch, "Du mobile bill")
        tapScrolling(button("Stop this bill"), "stop")
        app.buttons.matching(NSPredicate(format: "label == 'Stop'")).firstMatch.tap()
        sleep(1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Du mobile'")).firstMatch.exists, "Du mobile should be gone")
    }

    func testRepeatingExpenseGoesIntoPlan() {
        add("I spent money")
        typeAmount("99")
        app.swipeDown()
        tapScrolling(button("All categories"), "All categories")
        let shopping = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Shopping'")).firstMatch
        XCTAssertTrue(shopping.waitForExistence(timeout: 3)); shopping.tap()
        sleep(1)
        tapScrolling(button("More options"), "More options")
        let repeats = app.switches["Repeats"]
        tapScrolling(repeats, "Repeats")
        if (repeats.value as? String) == "0" { repeats.switches.firstMatch.tap() }
        snapshotTree("repeat-on")
        save()
        app.buttons["seeAllBills"].firstMatch.tap()
        expect("Shopping", "The repeat should be in bills")
    }

    func testEditAndReleaseSetAsideMoney() {
        tab("Budget")
        tapScrolling(button("Emergency fund"), "Emergency fund")
        tapScrolling(button("Release this money"), "release")
        sleep(1)
        XCTAssertFalse(button("Emergency fund").exists, "It should be gone")
        tab("Home")
        expect("Safe to spend", "Home")
        snapshotTree("home-after-release")
    }

    func testRenameAndArchiveAccount() {
        tab("Accounts")
        tapScrolling(button("Wio Savings"), "savings")
        snapshotTree("savings-detail")
        tapScrolling(button("Archive account"), "archive")
        app.buttons.matching(NSPredicate(format: "label == 'Archive'")).firstMatch.tap()
        sleep(1)
        if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        snapshotTree("accounts-after-archive")
    }

    func testArchiveCategory() {
        tab("Budget")
        tapScrolling(button("Health"), "Health")
        tapScrolling(button("Rename, group or settings"), "settings")
        tapScrolling(button("More options"), "more")
        tapScrolling(button("Archive category"), "archive")
        sleep(1)
        let confirm = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Archive'")).allElementsBoundByIndex.last
        if let c = confirm, c.exists, c.isHittable { c.tap() }
        sleep(1)
        snapshotTree("after-archive-category")
        if app.buttons["Done"].exists { app.buttons["Done"].firstMatch.tap() }
        sleep(1)
        XCTAssertFalse(button("Health, No budget").exists, "Health should be hidden")
    }

    func testPlusForecastAndExtraPayment() {
        tapScrolling(button("Money ahead"), "Money ahead")
        sleep(1)
        snapshotTree("forecast")
        if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        tab("Accounts")
        tapScrolling(button("Car loan"), "car loan")
        let extra = app.textFields["extraPayment"]
        tapScrolling(extra, "extra payment")
        extra.typeText("500")
        sleep(1)
        snapshotTree("extra-payment")
        expect("sooner", "Paying extra should show how much sooner")
    }

    func testCSVExport() {
        app.navigationBars.buttons.firstMatch.tap()
        button("Your data").tap()
        button("Export all entries (CSV)").tap()
        sleep(2)
        snapshotTree("csv-export")
        expect("Share export", "A share link should appear")
    }

    func testDeleteEverything() {
        app.navigationBars.buttons.firstMatch.tap()
        button("Your data").tap()
        tapScrolling(button("Delete all data on this iPhone"), "erase")
        sleep(1)
        snapshotTree("erase-confirm")
        app.buttons.matching(NSPredicate(format: "label == 'Delete everything'")).firstMatch.tap()
        sleep(2)
        snapshotTree("after-erase")
        XCTAssertTrue(app.buttons["getStarted"].waitForExistence(timeout: 5), "It should start over at setup")
    }

    func testAskOnSimulator() {
        relaunch(["-plus"])
        let ask = app.buttons["askButton"]
        if ask.waitForExistence(timeout: 3) {
            ask.tap(); sleep(2)
            snapshotTree("ask-sim")
        } else { snapshotTree("ask-hidden") }
    }

    func testWelcomeTourAndDarkMode() {
        relaunch(["-screen", "tour"])
        snapshotTree("tour-1")
        for i in 2...6 {
            let next = app.buttons.matching(NSPredicate(format: "label == 'Next' OR label == 'Continue' OR label == 'Get started' OR label == 'Done'")).firstMatch
            guard next.exists else { break }
            next.tap(); sleep(1); snapshotTree("tour-\(i)")
        }
        relaunch(["-plus", "-appearance", "dark"])
        snapshotTree("dark-home")
        for t in ["Budget", "Activity", "Accounts", "Reports"] { app.tabBars.buttons[t].tap(); sleep(1); snapshotTree("dark-" + t) }
    }
}
