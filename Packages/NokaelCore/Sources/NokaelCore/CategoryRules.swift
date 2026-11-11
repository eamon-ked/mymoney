//
//  CategoryRules.swift
//  NokaelCore
//
//  Well-known shops and payees mapped to the kind of category they belong
//  in, so a statement or alert gets a sensible category on a phone with no
//  history and no Apple Intelligence. Matches the person's own category
//  names loosely ("Dining out", "Eating out" and "Restaurants" all fit).
//

import Foundation

public enum CategoryRules {
    /// (words in the description, words in a category name)
    static let spending: [([String], [String])] = [
        (["carrefour", "lulu", "spinneys", "choithrams", "waitrose", "union coop", "coop", "geant", "nesto", "viva",
          "supermarket", "hypermarket", "grocery", "groceries", "kibsons", "instashop", "baqala", "danube", "tamimi",
          "panda", "othaim", "almaya", "al maya"], ["grocer", "food shop", "supermarket"]),
        (["cafe", "coffee", "starbucks", "costa", "tim hortons", "tea", "karak", "restaurant", "rest", "mcdonald",
          "mcdonalds", "kfc", "burger", "pizza", "shawarma", "talabat", "deliveroo", "zomato", "careem food", "keeta",
          "bakery", "kitchen", "grill", "dunkin", "subway", "hardees", "popeyes", "eatery", "cafeteria"],
         ["dining", "eating", "restaurant", "food"]),
        (["adnoc", "enoc", "eppco", "emarat", "petrol", "fuel", "careem", "uber", "rta", "salik", "darb", "taxi",
          "parking", "mawaqif", "nol", "metro", "aldrees", "petromin", "car wash"], ["transport", "fuel", "car", "travel"]),
        (["dewa", "addc", "adwea", "taqa", "sewa", "fewa", "empower", "tabreed", "district cooling", "electricity", "water"],
         ["utilit", "electric", "bills"]),
        (["etisalat", "e&", "du", "virgin mobile", "stc", "mobily", "zain", "internet", "telecom"], ["phone", "internet", "mobile"]),
        (["netflix", "spotify", "shahid", "osn", "disney", "vox", "reel cinemas", "cinema", "playstation", "steam",
          "anghami", "youtube", "apple com bill", "itunes"], ["entertain", "subscri", "fun"]),
        (["amazon", "amzn", "noon", "namshi", "ikea", "centrepoint", "h&m", "zara", "sharaf", "jumbo", "ace hardware",
          "daiso", "aliexpress", "temu", "shein", "mall", "trading", "electronics", "home centre", "max fashion"],
         ["shopping", "clothes", "household"]),
        (["pharmacy", "aster", "boots", "hospital", "clinic", "medical", "dental", "nmc", "mediclinic", "cleveland",
          "burjeel", "seha", "lab", "optic", "optical"], ["health", "medical", "pharmacy"]),
        (["rent", "ejari", "real estate", "properties", "landlord", "mortgage"], ["rent", "housing", "mortgage", "home"]),
        // Before fees, so "LOANRECOVERY-EMI" isn't a bank charge
        (loanWords, ["loan", "repayment", "debt"]),
        (["fee", "fees", "charge", "charges", "interest", "commission", "vat on"], ["interest", "fee", "bank charge"]),
        (["school", "university", "tuition", "academy", "nursery", "course"], ["education", "school"]),
        (["gym", "fitness", "salon", "barber", "spa"], ["personal", "fitness", "health"]),
        // Last, so a transfer fee is still a fee: money sent to another person is spending on them
        (sentToPeopleWords, ["sent to people", "people", "family", "gift"])
    ]

    /// Words banks use for money sent to someone else, in many countries
    static let sentToPeopleWords = ["trf", "transfer", "transferred", "remittance", "remit", "ipp", "aani", "p2p", "zelle",
                                    "venmo", "interac", "upi", "imps", "neft", "paynow", "pix", "bizum", "blik", "swish",
                                    "sepa", "western union", "moneygram", "send money", "sent to", "fast payment",
                                    // Money apps people use to send to family and friends
                                    "botim", "ziina", "payit", "wise", "revolut", "remitly", "worldremit", "taptap",
                                    "sendwave", "mukuru", "skrill", "ria", "paypal", "cash app"]

    /// Words banks use for a loan instalment
    static let loanWords = ["emi", "loan", "loanrecovery", "instalment", "installment", "repayment"]

    /// Whether money out reads like a loan instalment
    public static func isLoanPayment(_ description: String) -> Bool {
        let words = tokens(description)
        return loanWords.contains { words.contains($0) }
    }

    static let salaryWords = ["salary", "payroll", "wps", "sal credit", "wages"]

    /// Whether money in says it's pay. Money from friends or a payment app isn't,
    /// so a guess of "Salary" for it is wrong.
    public static func saysSalary(_ description: String) -> Bool {
        let words = tokens(description)
        let joined = " " + words.joined(separator: " ") + " "
        return salaryWords.contains { $0.contains(" ") ? joined.contains(" \($0) ") : words.contains($0) }
    }

    /// Words that put money in from someone, not a business: "B/O Grace Achieng", "Transfer from J Smith"
    static let fromPersonWords = ["b o", "from", "received from", "inward", "ipp", "aani", "p2p", "zelle", "venmo", "interac",
                                  "upi", "imps", "paynow", "pix", "bizum", "blik", "swish", "fast payment", "remittance"]
    /// Words that mark the sender as a business. Long ones also count inside a run-together name
    /// ("NOKAELDASHLOGISTICSFORDELIVER")
    static let companyWords = ["llc", "ltd", "limited", "inc", "corp", "company", "co", "fze", "fzco", "fzc", "fzllc", "gmbh",
                               "plc", "pty", "est", "establishment", "logistics", "trading", "services", "solutions",
                               "holding", "holdings", "group", "bank", "insurance", "ministry", "government", "authority",
                               "university", "school", "hospital", "restaurant", "technologies", "delivery", "payroll"]

    /// Whether money in reads like it came from family or a friend: a money app, or a transfer
    /// naming a person rather than a business
    public static func isFromPeople(_ description: String) -> Bool {
        let words = tokens(description)
        let joined = " " + words.joined(separator: " ") + " "
        func has(_ list: [String]) -> Bool { list.contains { $0.contains(" ") ? joined.contains(" \($0) ") : words.contains($0) } }
        if saysSalary(description) { return false }
        if has(moneyApps) { return true }
        let business = companyWords.contains { key in
            words.contains(key) || (key.count >= 6 && words.contains { $0.count > key.count && $0.contains(key) })
        }
        return !business && has(fromPersonWords)
    }

    /// Apps people use to send money to each other
    static let moneyApps = ["botim", "ziina", "payit", "wise", "revolut", "remitly", "worldremit", "taptap", "sendwave",
                            "mukuru", "skrill", "venmo", "zelle", "cash app", "paypal"]

    /// Whether last time's category still fits: money from a person isn't pay just because it was filed so once
    public static func historyFits(categoryName: String, description: String, income: Bool) -> Bool {
        !(income && isSalaryCategory(categoryName) && !saysSalary(description) && isFromPeople(description))
    }

    /// Whether a category name is for pay
    public static func isSalaryCategory(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["salary", "wage", "payroll"].contains { n.contains($0) }
    }

    /// Whether a description reads like money sent to another person
    public static func isSentToPeople(_ description: String) -> Bool {
        let words = tokens(description)
        let joined = " " + words.joined(separator: " ") + " "
        return sentToPeopleWords.contains { $0.contains(" ") ? joined.contains(" \($0) ") : words.contains($0) }
    }

    static let income: [([String], [String])] = [
        (salaryWords, ["salary", "pay", "wage"]),
        (["refund", "reversal", "cashback", "cash back"], ["refund", "other income"]),
        (["interest", "profit", "dividend"], ["interest", "investment", "other income"])
    ]

    /// The person's category this description most likely belongs in, by name
    public static func guess(_ description: String, income isIncome: Bool, categories: [String]) -> String? {
        let words = tokens(description)
        let joined = " " + words.joined(separator: " ") + " "
        for (keys, wanted) in (isIncome ? income : spending) {
            let hit = keys.contains { key in
                key.contains(" ") ? joined.contains(" \(key) ") : words.contains(key)
            }
            guard hit else { continue }
            if let name = wanted.lazy.compactMap({ w in categories.first { $0.lowercased().contains(w) } }).first {
                return name
            }
        }
        return nil
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "&")).inverted)
            .filter { !$0.isEmpty }
    }
}
