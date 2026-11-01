import Foundation
import Testing
@testable import NokaelCore

struct CategoryRulesTests {
    let spending = ["Rent or mortgage", "Groceries", "Utilities", "Transport", "Phone & internet", "Dining out",
                    "Entertainment", "Shopping", "Health", "Interest & fees", "Other spending"]

    @Test func knownShops() {
        #expect(CategoryRules.guess("PUR 29/09 BEST TEA R Abu Dhabi 0785", income: false, categories: spending) == "Dining out")
        #expect(CategoryRules.guess("PUR 30/09 e& Digital Abu Dhabi 0785", income: false, categories: spending) == "Phone & internet")
        #expect(CategoryRules.guess("POS CARREFOUR CITY 1234 DUBAI", income: false, categories: spending) == "Groceries")
        #expect(CategoryRules.guess("ADNOC 512 ABU DHABI", income: false, categories: spending) == "Transport")
        #expect(CategoryRules.guess("DEWA BILL PAYMENT", income: false, categories: spending) == "Utilities")
        #expect(CategoryRules.guess("Life Pharmacy", income: false, categories: spending) == "Health")
    }

    @Test func noWordFragments() {
        // "du" only as a word, "rest" not inside "interest"
        #expect(CategoryRules.guess("DUBAI DUTY FREE", income: false, categories: spending) == nil)
        #expect(CategoryRules.guess("Some unknown shop", income: false, categories: spending) == nil)
    }

    @Test func income() {
        #expect(CategoryRules.guess("WPS SALARY OCT", income: true, categories: ["Salary", "Other income"]) == "Salary")
        #expect(CategoryRules.guess("REFUND AMAZON", income: true, categories: ["Salary", "Other income"]) == "Other income")
    }

    @Test func usesThePersonsOwnNames() {
        #expect(CategoryRules.guess("Talabat order", income: false, categories: ["Food & drink", "Bills"]) == "Food & drink")
        #expect(CategoryRules.guess("Talabat order", income: false, categories: ["Bills"]) == nil)
    }
}

@Test func loanInstalmentsFindTheirLoan() {
    let car = UUID(), home = UUID()
    #expect(StatementImport.loan(for: "LOANRECOVERY-EMI:11392149P022001", loans: [(home, "Construction loan")]) == home)
    #expect(StatementImport.loan(for: "CAR LOAN INSTALMENT", loans: [(home, "Construction loan"), (car, "Car loan")]) == car)
    #expect(StatementImport.loan(for: "LOAN EMI 0412", loans: [(home, "Construction loan"), (car, "Car loan")]) == nil)
    #expect(StatementImport.loan(for: "PUR 07/10 ADNOC RABD ABUDHABI", loans: [(home, "Construction loan")]) == nil)
    #expect(StatementImport.loan(for: "PUR LEMON TREE", loans: [(home, "Construction loan")]) == nil)
}

@Test func loanInstalmentsAreNotFees() {
    let spending = ["Interest & fees", "Loan payments", "Other spending"]
    #expect(CategoryRules.guess("LOANRECOVERY-EMI:11392149P022001", income: false, categories: spending) == "Loan payments")
    #expect(CategoryRules.guess("STANDING ORDER LOAN REPAYMENT", income: false, categories: spending) == "Loan payments")
    #expect(CategoryRules.isLoanPayment("LOANRECOVERY-EMI:11392149P022001"))
    #expect(!CategoryRules.isLoanPayment("AED TRF Within UAE Charges Incl VAT"))
    #expect(CategoryRules.guess("AED TRF Within UAE Charges Incl VAT", income: false, categories: spending) == "Interest & fees")
}

@Test func moneyAppsAreSentToPeople() {
    #expect(CategoryRules.isSentToPeople("PUR 26/10 BOTIM MONE Abu Dhabi 0785"))
    #expect(CategoryRules.isSentToPeople("WISE TRANSFER TO J SMITH"))
    #expect(!CategoryRules.isSentToPeople("PUR 28/10 GOOD BURGE ABU DHABI 0785"))
}

@Test func onlyPayIsSalary() {
    #expect(CategoryRules.saysSalary("SALARY"))
    #expect(CategoryRules.saysSalary("WPS SAL CREDIT OCT"))
    #expect(!CategoryRules.saysSalary("743378734 B/O Sheila Ankunda"))
    #expect(!CategoryRules.saysSalary("737073125 B/O ZIINA PAYMENT LLC - CLIENT MONEY"))
    #expect(CategoryRules.isSalaryCategory("Salary"))
    #expect(!CategoryRules.isSalaryCategory("Other income"))
}

@Test func movesToYourOwnAccounts() throws {
    let csv = """
    "Account Number: 11392149920001 AED",
    "Opening Balance: 2.23 AED",
    Posting Date,Value Date,Reference No,Description,Debit Amount,Credit Amount,Balance
    "29/10/2026 10:00:00","29/10/2026","1","41421369215MBTRFAED1000.00@11392149810001","1000","0.00","1.00",
    """
    let own = StatementImport.accountNumber(in: csv)
    #expect(own == "11392149920001")
    #expect(StatementImport.isOwnAccountTransfer("41421369215MBTRFAED1000.00@11392149810001", ownNumber: own))
    // Someone else's account, the statement's own number, and a loan reference aren't moves to your own account
    #expect(!StatementImport.isOwnAccountTransfer("41031133397 MBTRF AED350 TRF OUT TO owori alex bongomin", ownNumber: own))
    #expect(!StatementImport.isOwnAccountTransfer("PAYMENT FROM 11392149920001", ownNumber: own))
    #expect(!StatementImport.isOwnAccountTransfer("LOANRECOVERY-EMI:11392149P022001", ownNumber: own))
    #expect(!StatementImport.isOwnAccountTransfer("TRANSFER TO 55512349810001", ownNumber: own))
    #expect(!StatementImport.isOwnAccountTransfer("anything", ownNumber: nil))
    // A file with no account details
    #expect(StatementImport.accountNumber(in: "Date,Description,Amount\n2026-10-01,Coffee,-5") == nil)
    #expect(try StatementImport.read(csv, currency: "AED", calendar: .current).count == 1)
}
