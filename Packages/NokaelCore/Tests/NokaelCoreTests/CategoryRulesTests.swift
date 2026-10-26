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
