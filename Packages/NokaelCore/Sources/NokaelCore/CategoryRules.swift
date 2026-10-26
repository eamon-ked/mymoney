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
        (["fee", "fees", "charge", "charges", "interest", "commission", "vat on"], ["interest", "fee", "bank charge"]),
        (["school", "university", "tuition", "academy", "nursery", "course"], ["education", "school"]),
        (["gym", "fitness", "salon", "barber", "spa"], ["personal", "fitness", "health"])
    ]

    static let income: [([String], [String])] = [
        (["salary", "payroll", "wps", "sal credit", "wages"], ["salary", "pay", "wage"]),
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
