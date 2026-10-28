//
//  Capture.swift
//  NokaelCore
//
//  Spending that arrives on its own: an Apple Pay tap passed in by a Shortcuts
//  automation, a bank SMS alert, or a sentence said to Siri. Reading the alert,
//  knowing which senders are banks, and spotting the same purchase twice all
//  live here so they can be tested without the app.
//

import Foundation

/// One purchase or deposit as it arrived, before it becomes an entry
public struct Capture: Equatable, Sendable {
    public enum Source: String, Sendable, Codable, CaseIterable {
        case applePay, sms, siri

        public var title: String {
            switch self {
            case .applePay: return "Apple Pay"
            case .sms: return "Bank message"
            case .siri: return "Siri"
            }
        }
    }

    public enum Direction: Sendable, Equatable { case spent, received }

    public var source: Source
    public var direction: Direction
    /// Always positive; `direction` says which way it went
    public var amount: Money
    public var merchant: String
    /// The Wallet card's name ("ENBD Visa") or the last four digits from an SMS
    public var cardHint: String?
    public var date: Date
    /// What came in, kept so a retried automation is recognised
    public var text: String

    public init(source: Source, direction: Direction, amount: Money, merchant: String,
                cardHint: String? = nil, date: Date, text: String = "") {
        self.source = source
        self.direction = direction
        self.amount = amount
        self.merchant = merchant
        self.cardHint = cardHint
        self.date = date
        self.text = text
    }
}

// MARK: - Reading a bank SMS

/// Reads bank alerts like "Purchase of AED 45.00 at CARREFOUR with card ending
/// 1234". Works without Apple Intelligence; returns nil for anything that
/// isn't money moving (codes, declines, balances, offers).
public enum AlertParser {
    /// ISO codes, written in capitals by banks. A few that are also English words ("ALL", "TOP")
    /// only count when they're the person's own currency.
    static let currencies: Set<String> = Set(Locale.commonISOCurrencyCodes)
        .subtracting(["ALL", "TOP", "CUP", "BOB", "PEN", "SOS", "BAM", "GEL", "MOP", "AMD"])
    /// Local ways of writing a currency. Where one sign is used by several ("$", "kr", "Rs"),
    /// the person's own currency wins, so "$45" is Canadian dollars in Canada.
    static let symbols: [String: [String]] = [
        "$": ["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN", "TWD", "ARS", "CLP", "COP"],
        "US$": ["USD"], "C$": ["CAD"], "CA$": ["CAD"], "A$": ["AUD"], "AU$": ["AUD"], "NZ$": ["NZD"],
        "S$": ["SGD"], "HK$": ["HKD"], "R$": ["BRL"], "MX$": ["MXN"], "NT$": ["TWD"],
        "£": ["GBP", "EGP"], "E£": ["EGP"], "€": ["EUR"], "¥": ["JPY", "CNY"], "￥": ["JPY", "CNY"], "円": ["JPY"],
        "元": ["CNY"], "₹": ["INR"], "Rs": ["INR", "PKR", "LKR", "NPR"], "Rs.": ["INR", "PKR", "LKR", "NPR"],
        "INR.": ["INR"], "₨": ["PKR", "LKR", "NPR", "INR"], "₩": ["KRW"], "₺": ["TRY"], "TL": ["TRY"], "₱": ["PHP"],
        "฿": ["THB"], "₦": ["NGN"], "₫": ["VND"], "₴": ["UAH"], "₽": ["RUB"], "₪": ["ILS"], "zł": ["PLN"],
        "kr": ["SEK", "NOK", "DKK", "ISK"], "kr.": ["DKK", "SEK", "NOK", "ISK"], "Kč": ["CZK"], "Ft": ["HUF"],
        "lei": ["RON"], "RM": ["MYR"], "Rp": ["IDR"], "R": ["ZAR"], "Ksh": ["KES"], "KSh": ["KES"], "৳": ["BDT"],
        "Tk": ["BDT"], "Dhs": ["AED", "MAD"], "DHS": ["AED", "MAD"], "Dh": ["AED", "MAD"], "DH": ["AED", "MAD"],
        "SR": ["SAR"], "QR": ["QAR"], "KD": ["KWD"], "BD": ["BHD"], "RO": ["OMR"], "LE": ["EGP"],
        "د.إ": ["AED"], "درهم": ["AED", "MAD"], "ر.س": ["SAR"], "ريال": ["SAR", "QAR", "OMR"], "ر.ق": ["QAR"],
        "د.ك": ["KWD"], "دينار": ["KWD", "BHD", "JOD"], "جنيه": ["EGP"],
    ]

    // Banks write in many languages; English first, then Arabic, French, Spanish, Portuguese and German.
    // Wording these lists miss is left to Apple Intelligence where it's available.
    static let rejectWords = ["one time password", "one-time password", "verification code", "do not share",
                              "declined", "unsuccessful", "was not successful", "failed", "insufficient", "rejected",
                              "will be debited", "is due", "due date", "minimum payment", "pre-approved", "apply now",
                              "رمز التحقق", "كلمة المرور لمرة واحدة", "مرفوض", "تم رفض", "غير ناجح", "رصيد غير كاف",
                              "code de vérification", "refusé", "rejeté", "fonds insuffisants",
                              "código de verificación", "rechazad", "denegad", "saldo insuficiente",
                              "código de verificação", "recusad", "negad",
                              "bestätigungscode", "abgelehnt", "nicht erfolgreich", "fehlgeschlagen"]
    /// Short codes are only turned away as whole words, so "laptop" isn't an OTP
    static let rejectTokens = ["otp", "tan", "pin code"]
    static let spentWords = ["purchase", "spent", "debited", "paid", "payment of", "withdrawn", "withdrawal", "charged",
                             "used for", "has been used", "was used", "debit of", "sent", "transfer of",
                             "شراء", "خصم", "سحب", "دفع", "تم استخدام",
                             "achat", "paiement", "débité", "retrait", "prélèvement",
                             "compra", "pago", "cargo", "retiro", "debitad", "pagamento", "saque", "débito de",
                             "zahlung", "belastet", "abbuchung", "kartenzahlung", "abhebung"]
    static let receivedWords = ["credited", "received", "deposited", "deposit of", "refund", "reversal", "reversed", "cashback",
                                "إيداع", "تم إضافة", "استرداد", "وارد",
                                "crédité", "virement reçu", "remboursement", "dépôt",
                                "abono", "abonad", "acreditad", "creditad", "depósito", "reembolso", "recibid", "recebid",
                                "gutgeschrieben", "gutschrift", "eingang", "erstattung"]
    /// An amount right after one of these is a balance or limit, not the purchase
    static let balanceWords = ["bal", "balance", "limit", "avl", "available", "outstanding",
                               "رصيد", "المتاح", "الحد", "solde", "disponible", "plafond", "saldo", "disponível", "límite",
                               "limite", "verfügbar", "guthaben", "kontostand"]

    /// Safety lines many banks add to every alert ("Never share your OTP"); they say nothing about the purchase
    static let warningWords = ["never share", "do not share", "don't share", "dont share", "never ask", "will never",
                               "beware", "fraud", "not done by you", "not initiated by you", "if you did not", "call us",
                               "لا تشارك", "لا تفصح", "احذر", "احتيال", "لم تقم",
                               "ne partagez", "ne communiquez", "jamais", "si vous n'êtes pas",
                               "no compart", "nunca compart", "nunca le", "si no reconoce",
                               "não compartilhe", "nunca compartilhe", "não reconhece",
                               "niemals", "geben sie", "nicht weiter", "betrug"]

    public static func read(_ original: String, homeCurrency: String, date: Date) -> Capture? {
        let text = westernDigits(original)
        let lower = text.lowercased()
        let checked = withoutWarnings(lower)
        guard !rejectWords.contains(where: checked.contains),
              !rejectTokens.contains(where: { checked.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) else { return nil }
        let amounts = self.amounts(in: text, homeCurrency: homeCurrency)
        // Prefer the amount in the person's own currency; a card used abroad
        // often shows both
        guard let amount = amounts.first(where: { $0.currency == homeCurrency }) ?? amounts.first else { return nil }

        let spentAt = spentWords.compactMap { lower.range(of: $0)?.lowerBound }.min()
        let receivedAt = receivedWords.compactMap { lower.range(of: $0)?.lowerBound }.min()
        let merchant = self.merchant(in: text)
        let direction: Capture.Direction
        switch (spentAt, receivedAt) {
        case let (s?, r?): direction = s < r ? .spent : .received
        case (_?, nil): direction = .spent
        case (nil, _?): direction = .received
        case (nil, nil):
            // "AED 45.00 at Carrefour, card 1234" with no verb is still a purchase
            guard merchant != nil else { return nil }
            direction = .spent
        }
        return Capture(source: .sms, direction: direction, amount: amount, merchant: merchant ?? "",
                       cardHint: cardDigits(in: text), date: date, text: original)
    }

    /// A sentence said to Siri: "45 at Carrefour", "spent 120 dirhams on DEWA",
    /// "got 500 from Sam". The first number is the amount.
    public static func spoken(_ text: String, homeCurrency: String, date: Date) -> Capture? {
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,3})?|[0-9]+(?:\.[0-9]{1,3})?"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text),
              let amount = StatementImport.amount(String(text[range]), currency: homeCurrency), amount.isPositive else { return nil }
        let lower = text.lowercased()
        let incoming = ["received", "got paid", "got ", "income", "salary", "refund", "earned"].contains(where: lower.contains)
        var merchant = self.merchant(in: text)
        if merchant == nil, let on = text.range(of: #"(?i)\b(?:on|for)\s+(.{2,40})$"#, options: .regularExpression) {
            merchant = String(text[on]).replacingOccurrences(of: #"(?i)^(?:on|for)\s+"#, with: "", options: .regularExpression)
        }
        let cleaned = merchant?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return Capture(source: .siri, direction: incoming ? .received : .spent, amount: amount,
                       merchant: cleaned.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "", date: date, text: text)
    }

    /// The message without its safety sentences, so a footer mentioning OTPs doesn't hide a real purchase.
    /// A real one-time code keeps its first sentence ("Your OTP … is 482913") and is still turned away.
    static func withoutWarnings(_ lower: String) -> String {
        lower.components(separatedBy: CharacterSet(charactersIn: "!\n"))
            .flatMap { $0.components(separatedBy: ". ") }
            .filter { sentence in !warningWords.contains(where: sentence.contains) }
            .joined(separator: ". ")
    }

    /// "٤٥٫٠٠" and "۴۵" → "45.00" and "45", so Arabic and Persian alerts read like any other
    public static func westernDigits(_ text: String) -> String {
        String(text.map { ch -> Character in
            if let v = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1 {
                if (0x0660...0x0669).contains(v) { return Character(String(v - 0x0660)) }
                if (0x06F0...0x06F9).contains(v) { return Character(String(v - 0x06F0)) }
                if v == 0x066B { return "." } // Arabic decimal mark
                if v == 0x066C { return "," } // Arabic thousands mark
            }
            return ch
        })
    }

    /// Every amount that has a currency next to it and isn't a balance or limit.
    /// Reads "1,234.56", "1.234,56", "1 234,56" and "1'234.56".
    static func amounts(in text: String, homeCurrency: String) -> [Money] {
        let home = homeCurrency.uppercased()
        let codes = currencies.union([home]).sorted { $0.count > $1.count }.joined(separator: "|")
        let signs = symbols.keys.sorted { $0.count > $1.count }.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let unit = "(?<![\\p{L}])(?:\(codes)|\(signs))(?![\\p{L}])"
        let number = #"([0-9]{1,3}(?:[,.'\u00A0\u202F ][0-9]{3})+(?:[.,][0-9]{1,3})?|[0-9]+(?:[.,][0-9]{1,3})?)(?![0-9])"#
        let pattern = "(?:(\(unit))\\s?\(number))|(?:\(number)\\s?(\(unit)))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            func group(_ i: Int) -> String? {
                let r = match.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let rawUnit = group(1) ?? group(4), var digits = group(2) ?? group(3) else { return nil }
            let before = ns.substring(to: match.range.location).lowercased().suffix(18)
            if balanceWords.contains(where: before.contains) { return nil }
            let code: String
            if currencies.contains(rawUnit) || rawUnit == home {
                code = rawUnit
            } else if let options = symbols[rawUnit] {
                code = options.contains(home) ? home : options[0]
            } else {
                return nil
            }
            // "1.234" is a thousand and more, except in currencies with three decimals (KWD 1.234)
            if Currency.scale(of: code) != 3, digits.range(of: #"^[0-9]{1,3}(\.[0-9]{3})+$"#, options: .regularExpression) != nil {
                digits = digits.replacingOccurrences(of: ".", with: "")
            }
            guard let money = StatementImport.amount(digits, currency: code), money.isPositive else { return nil }
            return money
        }
    }

    /// The shop after "at" or "@", or the payee after "to"/"from"
    static func merchant(in text: String) -> String? {
        let stops = #"(?=\s+(?:on|with|using|via|for|ref|dated|card|from|in|avl|avail|available|your|has|is|was|txn|by|le|el|am|au|del|con|avec|mit|com|par|por|pelo|bei|em|en|no|na|carte|tarjeta|cartão|karte|بتاريخ|في|بواسطة)(?![\p{L}])|\s+(?:ببطاق|بطاق)|[.,;:!\n]\s|[.,;:!]?$|\s+\d{1,2}[/-]\d{1,2})"#
        let patterns = [#"(?i)(?:\bat|@)\s+(.{2,60}?)"# + stops,
                        // chez, en, bei, em, لدى, عند: "at" in French, Spanish, German, Portuguese and Arabic
                        #"(?i)(?:(?<![\p{L}])(?:chez|en|bei|em)|لدى|عند)\s+(?!(?:ligne|línea|linha|cuenta|conta|compte|konto|eur|usd)(?![\p{L}]))(.{2,60}?)"# + stops,
                        #"(?i)\b(?:to|towards)\s+(?!your\b|you\b|a/c\b|acc\b|acct\b|account\b|card\b)(.{2,60}?)"# + stops,
                        #"(?i)\bfrom\s+(?!your\b|a/c\b|acc\b|acct\b|account\b|card\b)(.{2,60}?)"# + stops]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let name = text[range].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard name.count >= 2, name.contains(where: \.isLetter) else { continue }
            return tidy(name)
        }
        return nil
    }

    /// "CARREFOUR CITY" → "Carrefour City", "CARREFOUR,DUBAI-AE" → "Carrefour"; mixed case is left alone
    static func tidy(_ name: String) -> String {
        let shop = name.split(separator: ",").first.map(String.init) ?? name
        let squeezed = shop.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return squeezed == squeezed.uppercased() ? squeezed.capitalized : squeezed
    }

    /// "ending 1234", "ending with 1234", "XXXX1234", "**1234", "...1234", and the last four of "XXX123456"
    static func cardDigits(in text: String) -> String? {
        let pattern = #"(?i)(?:ending(?:\s+(?:with|in))?\s*(?:no\.?\s*)?|[x\*]{2,}\d*|\.{2,}\d*|#)\s*(\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: - Which senders are banks

/// Banks and the names their SMS alerts arrive from, by country. People can
/// add their own sender too, so this only has to be a good starting point.
public struct BankSender: Hashable, Sendable, Identifiable {
    public let name: String
    public let senders: [String]
    public var id: String { name }
}

public enum BankSenders {
    public static let catalog: [String: [BankSender]] = [
        "AE": [
            BankSender(name: "Emirates NBD", senders: ["EmiratesNBD", "ENBD"]),
            BankSender(name: "ADCB", senders: ["ADCBAlert", "ADCB"]),
            BankSender(name: "First Abu Dhabi Bank", senders: ["FAB", "FABAlert"]),
            BankSender(name: "Mashreq", senders: ["Mashreq", "MashreqBank", "MashreqNEO"]),
            BankSender(name: "Dubai Islamic Bank", senders: ["DIB"]),
            BankSender(name: "Abu Dhabi Islamic Bank", senders: ["ADIB"]),
            BankSender(name: "RAKBANK", senders: ["RAKBANK"]),
            BankSender(name: "Commercial Bank of Dubai", senders: ["CBD"]),
            BankSender(name: "Emirates Islamic", senders: ["EIB", "EmiratesIsl"]),
            BankSender(name: "Liv", senders: ["Liv", "LivBank"]),
            BankSender(name: "HSBC", senders: ["HSBC"]),
            BankSender(name: "Wio", senders: ["Wio", "WioBank"]),
            BankSender(name: "Citibank", senders: ["Citibank", "Citi"]),
        ],
        "SA": [
            BankSender(name: "Al Rajhi Bank", senders: ["AlRajhiBank", "AlRajhi"]),
            BankSender(name: "Saudi National Bank", senders: ["SNB", "SNB-AlAhli"]),
            BankSender(name: "Riyad Bank", senders: ["RiyadBank"]),
            BankSender(name: "SAB", senders: ["SAB"]),
            BankSender(name: "Alinma", senders: ["alinma", "AlinmaBank"]),
            BankSender(name: "STC Bank", senders: ["STCBank", "STCPAY"]),
        ],
        "IN": [
            BankSender(name: "HDFC Bank", senders: ["HDFCBK"]),
            BankSender(name: "ICICI Bank", senders: ["ICICIB", "ICICIT"]),
            BankSender(name: "State Bank of India", senders: ["SBIINB", "SBIPSG", "ATMSBI"]),
            BankSender(name: "Axis Bank", senders: ["AXISBK"]),
            BankSender(name: "Kotak", senders: ["KOTAKB"]),
        ],
        "QA": [
            BankSender(name: "QNB", senders: ["QNB"]),
            BankSender(name: "Commercial Bank", senders: ["CBQ"]),
            BankSender(name: "Doha Bank", senders: ["DohaBank"]),
        ],
    ]

    /// The word a Shortcuts "Message Contains" trigger should look for
    /// What the Shortcuts automation looks for in a message: the sign alerts there use, else the
    /// country's currency code ("EUR", "JPY"), and "Card" only when the country isn't known
    public static func keyword(region: String) -> String {
        if let sign = ["GB": "£", "US": "$", "IN": "INR"][region] { return sign }
        return Locale(identifier: "und_\(region)").currency?.identifier ?? "Card"
    }

    public static func banks(region: String) -> [BankSender] { catalog[region] ?? [] }

    /// Indian senders arrive as "AD-HDFCBK", others exactly as listed
    public static func matches(_ sender: String, any ids: [String]) -> Bool {
        let s = normalize(sender)
        guard !s.isEmpty else { return false }
        return ids.map(normalize).contains { !$0.isEmpty && (s == $0 || s.hasSuffix($0) || s.hasPrefix($0)) }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - The same purchase twice

/// An entry already in the ledger, as the matcher needs to see it
public struct CapturedEntry: Sendable {
    public let id: UUID
    public let date: Date
    public let amount: Money
    public let direction: Capture.Direction
    public let memo: String
    /// nil for entries the person typed in
    public let source: Capture.Source?

    public init(id: UUID, date: Date, amount: Money, direction: Capture.Direction, memo: String, source: Capture.Source?) {
        self.id = id
        self.date = date
        self.amount = amount
        self.direction = direction
        self.memo = memo
        self.source = source
    }
}

public enum CaptureMatcher {
    /// The entry this capture already is, if any. An Apple Pay tap and the
    /// bank's SMS for it arrive minutes apart with different shop names, so
    /// a different source only needs the same amount close in time; the same
    /// source or a typed entry also needs the shop to match.
    public static func duplicate(of capture: Capture, in entries: [CapturedEntry],
                                 window: TimeInterval = 30 * 60, calendar: Calendar = .current) -> UUID? {
        let words = Set(StatementImport.merchantWords(capture.merchant))
        func sameShop(_ memo: String) -> Bool {
            !words.isEmpty && !words.isDisjoint(with: StatementImport.merchantWords(memo))
        }
        return entries
            .filter { $0.amount == capture.amount && $0.direction == capture.direction }
            .filter { entry in
                let gap = abs(entry.date.timeIntervalSince(capture.date))
                switch entry.source {
                case nil:
                    return calendar.isDate(entry.date, inSameDayAs: capture.date) && sameShop(entry.memo)
                case let source? where source == capture.source:
                    return gap <= 5 * 60 && sameShop(entry.memo)
                case .some:
                    return gap <= window
                }
            }
            .min { abs($0.date.timeIntervalSince(capture.date)) < abs($1.date.timeIntervalSince(capture.date)) }?
            .id
    }
}
