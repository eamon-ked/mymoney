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
    /// The digits the bank shows of the person's own account the money left or reached ("730001" from "XXX730001")
    public var accountHint: String?
    /// For a transfer, the digits shown of the account on the other side, when the bank names one
    public var otherAccountHint: String?
    /// The bank's reference for this movement; two alerts with different references are different movements
    public var reference: String?
    /// Money moved to or from an account (a person's, or another of your own), not a purchase
    public var isTransfer: Bool
    /// The bank gave back an earlier charge
    public var isReversal: Bool
    /// `date` was read from the message itself rather than when it arrived
    public var dateFromMessage: Bool
    /// The message's wording without its numbers, dates and name: two alerts with the same shape are
    /// the same kind of alert (two coffees), different shapes may tell of one movement twice
    public var shape: String?
    /// The balance the bank says the account has after this movement
    public var balance: Money?

    public init(source: Source, direction: Direction, amount: Money, merchant: String,
                cardHint: String? = nil, date: Date, text: String = "", accountHint: String? = nil,
                otherAccountHint: String? = nil, reference: String? = nil, isTransfer: Bool = false,
                isReversal: Bool = false, dateFromMessage: Bool = false, shape: String? = nil, balance: Money? = nil) {
        self.source = source
        self.direction = direction
        self.amount = amount
        self.merchant = merchant
        self.cardHint = cardHint
        self.date = date
        self.text = text
        self.accountHint = accountHint
        self.otherAccountHint = otherAccountHint
        self.reference = reference
        self.isTransfer = isTransfer
        self.isReversal = isReversal
        self.dateFromMessage = dateFromMessage
        self.shape = shape
        self.balance = balance
    }
}

/// Why a message wasn't saved, in words the person can act on
public enum IgnoredReason: String, Equatable, Sendable {
    case oneTimeCode, declined, notice, promotion, noAmount, unclear, personal

    public var sentence: String {
        switch self {
        case .oneTimeCode: return "It's a one-time code, not a payment."
        case .declined: return "It's a declined or failed payment, so no money moved."
        case .notice: return "It's a reminder or a balance notice, not a payment."
        case .promotion: return "It's an offer or advert, not a payment."
        case .noAmount: return "No amount with a currency was found in it."
        case .unclear: return "It wasn't clear whether money went out or came in."
        case .personal: return "It reads like a personal message, not a bank alert."
        }
    }
}

/// What reading a bank message found
public enum AlertReading: Equatable, Sendable {
    case capture(Capture)
    case ignored(IgnoredReason)

    public var capture: Capture? { if case .capture(let c) = self { return c } else { return nil } }
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
    static let codeWords = ["one time password", "one-time password", "verification code", "do not share",
                            "رمز التحقق", "كلمة المرور لمرة واحدة", "code de vérification", "código de verificación",
                            "código de verificação", "bestätigungscode"]
    static let declinedWords = ["declined", "unsuccessful", "was not successful", "failed", "insufficient", "rejected",
                                "could not be processed", "not processed",
                                "مرفوض", "تم رفض", "غير ناجح", "رصيد غير كاف", "refusé", "rejeté", "fonds insuffisants",
                                "rechazad", "denegad", "saldo insuficiente", "recusad", "negad",
                                "abgelehnt", "nicht erfolgreich", "fehlgeschlagen"]
    static let noticeWords = ["will be debited", "will be deducted", "is due", "due date", "minimum payment", "payment due",
                              "statement is ready", "statement has been generated", "is scheduled", "standing instruction will"]
    /// Adverts banks send from the same sender as alerts. Only counted when the message doesn't also
    /// say money moved on one of the person's cards or accounts.
    static let promotionWords = ["pre-approved", "preapproved", "apply now", "offer", "win ", "chance to", "enjoy", "exclusive",
                                 "limited time", "% off", "discount", "t&c", "terms apply", "http", "www.", "click",
                                 "download", "eligible", "upgrade to", "get up to", "earn up to", "earn ", "cashback of up to",
                                 "instant loan", "personal loan at", "reply yes", "sms yes", "رابح", "عرض", "اربح",
                                 "offre", "gagnez", "oferta", "gana ", "angebot", "gewinnen"]
    static var rejectWords: [String] { codeWords + declinedWords + noticeWords }
    /// Words for money given back
    static let reversalWords = ["reversal", "reversed", "refund", "chargeback", "credited back", "returned to your",
                                "استرداد", "remboursement", "reembolso", "estorno", "erstattung", "rückbuchung"]
    /// Words for money moved between accounts rather than spent at a shop
    static let transferWords = ["transferred", "transfer", "trf", "remittance", "remitted", "funds sent", "sent to",
                                "تحويل", "virement", "transferencia", "transferência", "überweisung"]
    /// Short codes are only turned away as whole words, so "laptop" isn't an OTP
    static let rejectTokens = ["otp", "tan", "pin code"]
    static let spentWords = ["purchase", "spent", "debited", "paid", "payment of", "withdrawn", "withdrawal", "charged",
                             "used for", "has been used", "was used", "debit of", "sent",
                             "dr. transaction", "dr transaction", "dr. txn", "debit transaction", "transfer of", "transferred", "trf out",
                             "شراء", "خصم", "سحب", "دفع", "تم استخدام",
                             "achat", "paiement", "débité", "retrait", "prélèvement",
                             "compra", "pago", "cargo", "retiro", "debitad", "pagamento", "saque", "débito de",
                             "zahlung", "belastet", "abbuchung", "kartenzahlung", "abhebung"]
    static let receivedWords = ["credited", "received", "deposited", "b/o", "trf in", "inward", "deposit of", "refund", "reversal", "reversed", "cashback",
                                // "A Cr. transaction of AED 150.00 on your account": banks abbreviate credit
                                "cr. transaction", "cr transaction", "cr. txn", "credit transaction", "credit of",
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

    public static func read(_ original: String, homeCurrency: String, date: Date,
                            calendar: Calendar = .current, monthFirst: Bool = false) -> Capture? {
        examine(original, homeCurrency: homeCurrency, date: date, calendar: calendar, monthFirst: monthFirst).capture
    }

    /// Reads a bank alert, or says why it isn't one. `date` is when it arrived; the date the bank
    /// printed is used instead when there is one and it's believable. `monthFirst` reads 03/11 as
    /// 11 March, for countries that write the month first.
    public static func examine(_ original: String, homeCurrency: String, date: Date,
                               calendar: Calendar = .current, monthFirst: Bool = false) -> AlertReading {
        let text = westernDigits(original)
        let lower = text.lowercased()
        let checked = withoutWarnings(lower)
        func says(_ words: [String]) -> Bool { words.contains(where: checked.contains) }
        if says(codeWords) || rejectTokens.contains(where: { checked.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) {
            return .ignored(.oneTimeCode)
        }
        if says(declinedWords) { return .ignored(.declined) }
        if says(noticeWords) { return .ignored(.notice) }

        let card = cardDigits(in: text)
        let accounts = accountDigits(in: text)
        let reference = self.reference(in: text)
        let moved = completedWords.contains(where: lower.contains)
        if says(promotionWords) && !(moved && (card != nil || !accounts.isEmpty || reference != nil)) {
            return .ignored(.promotion)
        }

        let amounts = self.amounts(in: text, homeCurrency: homeCurrency)
        // Prefer the amount in the person's own currency; a card used abroad often shows both
        guard let amount = amounts.first(where: { $0.currency == homeCurrency }) ?? amounts.first else { return .ignored(.noAmount) }

        let isTransfer = transferWords.contains { word in
            lower.range(of: "(?<![\\p{L}])\(NSRegularExpression.escapedPattern(for: word))(?![\\p{L}])", options: .regularExpression) != nil
        }
        let isReversal = reversalWords.contains(where: lower.contains)
        let merchant = self.merchant(in: text)
        let direction: Capture.Direction
        if isReversal {
            direction = .received
        } else if let own = ownSide(lower) {
            direction = own
        } else {
            let spentAt = spentWords.compactMap { lower.range(of: $0)?.lowerBound }.min()
            let receivedAt = receivedWords.compactMap { lower.range(of: $0)?.lowerBound }.min()
            switch (spentAt, receivedAt) {
            case let (s?, r?): direction = s < r ? .spent : .received
            case (_?, nil): direction = .spent
            case (nil, _?): direction = .received
            case (nil, nil):
                // "AED 45.00 at Carrefour, card 1234" with no verb is still a purchase
                guard merchant != nil else { return .ignored(.unclear) }
                direction = .spent
            }
        }
        let printed = transactionDate(in: text, arrived: date, calendar: calendar, monthFirst: monthFirst)
        return .capture(Capture(source: .sms, direction: direction, amount: amount, merchant: merchant ?? "",
                                cardHint: card, date: printed ?? date, text: original,
                                accountHint: accounts.first, otherAccountHint: accounts.dropFirst().first,
                                reference: reference, isTransfer: isTransfer, isReversal: isReversal,
                                dateFromMessage: printed != nil, shape: shape(text, merchant: merchant),
                                balance: balanceAfter(in: text, homeCurrency: homeCurrency)))
    }

    /// The wording of an alert with what changes from one to the next taken out: the name, numbers,
    /// masked digits, amounts and month names. "AED 12.00 at COSTA on 03 Nov, card XX4417" and
    /// "AED 4.50 at Pret on 05 Dec, card XX4417" have the same shape.
    public static func shape(_ text: String, merchant: String?) -> String {
        var lower = westernDigits(text).lowercased()
        if let merchant, !merchant.isEmpty {
            lower = lower.replacingOccurrences(of: merchant.lowercased(), with: " @ ")
        }
        let months = #"\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b"#
        for (pattern, with) in [(#"[x\*#]{2,}\d*"#, "#"), (#"\d+"#, "#"), (months, "#"),
                                (#"[^\p{L}#@]+"#, " ")] {
            lower = lower.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        return lower.split(separator: " ").joined(separator: " ")
    }

    /// Whether a message carries something a bank's alert has and a friend's text doesn't: card or
    /// account digits, a reference, a balance, the date or time of the payment, or an amount written
    /// to the cent ("45.00"). It reads no words, so it works in any language. "I sent you AED 100"
    /// has none of these. Currencies with no cents can't be told this way, so they always pass.
    public static func readsLikeBankAlert(_ original: String, homeCurrency: String, arrived: Date,
                                          calendar: Calendar = .current) -> Bool {
        let text = westernDigits(original)
        if Money.exact(Decimal(string: "0.01")!, currency: homeCurrency) == nil { return true }
        if cardDigits(in: text) != nil || !accountDigits(in: text).isEmpty || reference(in: text) != nil { return true }
        if balanceAfter(in: text, homeCurrency: homeCurrency) != nil { return true }
        if transactionDate(in: text, arrived: arrived, calendar: calendar) != nil { return true }
        if text.range(of: #"[xX*•]{2,}\s?\d{2,}"#, options: .regularExpression) != nil { return true }
        return text.range(of: #"\d[.,]\d{2}(?!\d)"#, options: .regularExpression) != nil
    }

    /// "Available balance is AED 453.39", "Avl. bal. AED 2.89", "Bal: 1,200.00 AED"
    public static func balanceAfter(in text: String, homeCurrency: String) -> Money? {
        let western = westernDigits(text)
        let lead = #"(?i)(?:available\s+balance|avail(?:able)?\.?\s*bal(?:ance)?|avl\.?\s*bal(?:ance)?\.?|current\s+balance|a/c\s+bal(?:ance)?|\bbal(?:ance)?)\s*(?:is|of|:|-)?\s*"#
        guard let found = western.range(of: lead, options: .regularExpression) else { return nil }
        let rest = String(western[found.upperBound...].prefix(30))
        return amounts(in: rest, homeCurrency: homeCurrency, skippingBalances: false).first
    }

    /// Words that say money already moved, as opposed to an offer to move it
    static let completedWords = ["was used", "has been used", "used for", "debited", "credited", "transferred", "withdrawn",
                                 "purchase of", "spent", "paid", "received", "deposited", "trf", "b/o", "refund", "reversal",
                                 "cr. transaction", "dr. transaction", "was successful"]

    /// "…to your account" means money came in, "…from your account" that it went out, whatever verb the bank used
    static func ownSide(_ lower: String) -> Capture.Direction? {
        let into = ["to your account", "to your a/c", "to your acc", "into your account", "into your a/c",
                    "credited to your", "credited in your", "credited into your", "in your account"]
        let outOf = ["from your account", "from your a/c", "from your acc", "debited from your"]
        let gotIn = into.contains(where: lower.contains), wentOut = outOf.contains(where: lower.contains)
        if gotIn && !wentOut { return .received }
        if wentOut && !gotIn { return .spent }
        return nil
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

    /// Whether the amount's digits appear in the message, at the currency's
    /// own decimals and without trailing zeros, so a guessed amount can be
    /// checked against what the bank wrote (KWD 12.345, AED 45, JPY 1500).
    public static func mentions(_ money: Money, in text: String) -> Bool {
        // Each number in the text is read whole, so 12.34 is never found inside a code like 123456
        let target = abs(money.decimal)
        let ns = westernDigits(text) as NSString
        guard let regex = try? NSRegularExpression(pattern: #"[0-9](?:[0-9]|[,.'\u00A0\u202F ](?=[0-9]))*"#) else { return false }
        for match in regex.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            let digits = token.filter(\.isNumber)
            var readings: [Decimal] = []
            if let whole = Decimal(string: digits) { readings.append(whole) }
            // The last separator may be the decimal mark: "45,50", "12.300"
            if let last = token.lastIndex(where: { !$0.isNumber }) {
                let fraction = token[token.index(after: last)...]
                let before = token[..<last].filter(\.isNumber)
                if (1...3).contains(fraction.count), let value = Decimal(string: "\(before).\(fraction)") { readings.append(value) }
            }
            if readings.contains(target) { return true }
        }
        return false
    }

    /// Every amount that has a currency next to it and isn't a balance or limit.
    /// Reads "1,234.56", "1.234,56", "1 234,56" and "1'234.56".
    static func amounts(in text: String, homeCurrency: String, skippingBalances: Bool = true) -> [Money] {
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
            if skippingBalances, balanceWords.contains(where: before.contains) { return nil }
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

    /// The card's last four: "card ending 1234", "Card XXX1234", "card no. ****1234". A masked number with no
    /// word for card or account in front of it counts as a card, as most alerts are about cards.
    static func cardDigits(in text: String) -> String? {
        let card = #"(?i)(?:card|carte|tarjeta|cartão|karte|بطاقة)\s*(?:no\.?|number|ending(?:\s+(?:with|in))?)?\s*(?:no\.?)?\s*[:#]?\s*[x\*\.#]*\d*?(\d{4})(?!\d)"#
        if let found = lastDigits(card, in: text) { return found }
        guard accountDigits(in: text).isEmpty else { return nil }
        let masked = #"(?i)(?:ending(?:\s+(?:with|in))?\s*(?:no\.?\s*)?|[x\*]{2,}\d*?|\.{2,}\d*?|#)\s*(\d{4})(?!\d)"#
        return lastDigits(masked, in: text)
    }

    /// The digits the bank shows of each account the message names, in order: "730001" from "acc. XXX730001",
    /// "1234" from "a/c XX1234", "account ending 4321". All of them, not just four: one bank's accounts often
    /// share their last four ("…730001" and "…240001"). The first is the person's own account.
    static func accountDigits(in text: String) -> [String] {
        let pattern = #"(?i)(?:a/c|acct?\.?|account|compte|cuenta|conta|konto|حساب)\s*(?:no\.?\s*|number\s*)?(?:ending(?:\s+(?:with|in))?\s*)?[:#]?\s*[x\*\.]+(\d{3,8})(?!\d)|(?i)(?:a/c|acct?\.?|account)\s*(?:no\.?\s*|number\s*)?ending(?:\s+(?:with|in))?\s*(\d{3,8})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var found: [String] = [], own: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            // "from account XXX240001 to your account XXX730001": the one after "your" is the person's,
            // wherever the bank put it in the sentence
            let lead = ns.substring(with: NSRange(location: max(0, match.range.location - 8),
                                                  length: min(8, match.range.location))).lowercased()
            let mine = ["your ", "your", "votre ", "ihr ", "ihrem ", "su ", "sua ", "seu ", "tu "].contains { lead.hasSuffix($0) }
            for i in 1...2 where match.range(at: i).location != NSNotFound {
                let digits = ns.substring(with: match.range(at: i))
                if !found.contains(digits) && !own.contains(digits) {
                    if mine { own.append(digits) } else { found.append(digits) }
                }
            }
        }
        return own + found
    }

    private static func lastDigits(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// The bank's reference: "Ref 43361448434", "Ref. No: TXN12345678", "reference number 123456",
    /// or the long number some banks start an alert with ("43361448434 MBTRF …")
    static func reference(in text: String) -> String? {
        let labelled = #"(?i)\b(?:ref(?:erence)?|txn(?:\s*id)?|transaction\s*(?:id|no\.?|number)|rrn|utr)\b\.?\s*(?:no\.?|number|id|#)?\s*[:#.\-]?\s*([A-Z0-9]*\d(?:[A-Z0-9]|-(?=\d)){5,})"#
        if let found = lastDigits(labelled, in: text) { return found.uppercased() }
        let leading = #"^\s*(\d{8,})(?=\s|[A-Z])"#
        return lastDigits(leading, in: text)
    }

    // MARK: Dates

    static let monthNames: [String: Int] = {
        var names: [String: Int] = [:]
        let english = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        for (i, n) in english.enumerated() { names[n] = i + 1 }
        names["sept"] = 9
        return names
    }()

    /// The date (and time, when given) the bank printed: "03/11/2026 12:22:05", "3-Nov-2026", "Nov 3 2026 12:22PM",
    /// "2026-11-03", or "03/11" with the year worked out. Only believed when it's from the last 45 days and not
    /// tomorrow or later, so a due date or an expiry is never taken for the purchase date.
    public static func transactionDate(in text: String, arrived: Date, calendar: Calendar = .current, monthFirst: Bool = false) -> Date? {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        var day: Int?, month: Int?, year: Int?, rest: String = ""
        let numeric = #"(?<!\d)(\d{1,2})[/\-.](\d{1,2})(?:[/\-.](\d{4}|\d{2}))?(?![\d/])"#
        let iso = #"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)"#
        let dayName = #"(?i)(?<!\d)(\d{1,2})[\s\-]?(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*[\s\-,]*(\d{4}|\d{2})?(?![\d])"#
        let nameDay = #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sept?|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s*(\d{4})?(?!\d)"#
        if let m = try? NSRegularExpression(pattern: iso).firstMatch(in: text, range: all) {
            year = Int(group(m, 1)!); month = Int(group(m, 2)!); day = Int(group(m, 3)!)
            rest = ns.substring(from: m.range.upperBound)
        } else if let m = try? NSRegularExpression(pattern: dayName).firstMatch(in: text, range: all) {
            day = Int(group(m, 1)!); month = monthNames[group(m, 2)!.lowercased()]; year = group(m, 3).flatMap { Int($0) }.map { $0 < 100 ? 2000 + $0 : $0 }
            rest = ns.substring(from: m.range.upperBound)
        } else if let m = try? NSRegularExpression(pattern: nameDay).firstMatch(in: text, range: all) {
            month = monthNames[group(m, 1)!.lowercased()]; day = Int(group(m, 2)!); year = group(m, 3).flatMap { Int($0) }
            rest = ns.substring(from: m.range.upperBound)
        } else {
            // Skip numbers that are amounts ("45.00"): a date's parts are both at most 31
            guard let regex = try? NSRegularExpression(pattern: numeric) else { return nil }
            for m in regex.matches(in: text, range: all) {
                guard let a = Int(group(m, 1)!), let b = Int(group(m, 2)!) else { continue }
                let separator = ns.substring(with: NSRange(location: m.range(at: 1).upperBound, length: 1))
                // "45.00" or "12.50" without a year is an amount, not a date
                if separator == ".", group(m, 3) == nil { continue }
                var (d, mo) = monthFirst ? (b, a) : (a, b)
                if mo > 12 && d <= 12 { swap(&d, &mo) }
                guard (1...12).contains(mo), (1...31).contains(d) else { continue }
                day = d; month = mo
                if let y = group(m, 3).flatMap({ Int($0) }) { year = y < 100 ? 2000 + y : y }
                rest = ns.substring(from: m.range.upperBound)
                break
            }
        }
        guard let day, let month else { return nil }
        var parts = calendar.dateComponents([.year, .hour, .minute, .second], from: arrived)
        let arrivedYear = parts.year ?? 2000
        parts.day = day
        parts.month = month
        parts.year = year ?? arrivedYear
        // A time right after the date: "12:22", "12:22:05", "12:22PM", "09:05 am"
        var hasTime = false
        if let m = try? NSRegularExpression(pattern: #"(?i)^[\s,]*(?:at\s+)?(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?"#)
            .firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) {
            let r = rest as NSString
            func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : r.substring(with: m.range(at: i)) }
            if var h = Int(g(1)!), let mi = Int(g(2)!), h < 24, mi < 60 {
                if let half = g(4)?.lowercased() { if half == "pm" && h < 12 { h += 12 } else if half == "am" && h == 12 { h = 0 } }
                parts.hour = h; parts.minute = mi; parts.second = g(3).flatMap { Int($0) } ?? 0
                hasTime = true
            }
        }
        guard var found = calendar.date(from: parts), calendar.component(.day, from: found) == day else { return nil }
        // "30/12" arriving on 2 January is last year's
        if year == nil, found > arrived.addingTimeInterval(86_400), let earlier = calendar.date(byAdding: .year, value: -1, to: found) {
            found = earlier
        }
        guard found <= arrived.addingTimeInterval(hasTime ? 600 : 86_400),
              found >= arrived.addingTimeInterval(-45 * 86_400) else { return nil }
        if !hasTime {
            // Only a day: the arrival time when it's today, else midday so it can't slip into the next or previous day
            if calendar.isDate(found, inSameDayAs: arrived) { return arrived }
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: found)
        }
        return Swift.min(found, arrived)
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
    /// The bank's reference, when an alert gave one
    public let reference: String?
    /// A second source already matched to this entry (the bank's SMS for an Apple Pay tap)
    public let alsoFrom: Capture.Source?
    /// The person's account it came out of or went into
    public let accountId: UUID?
    /// The bank messages that made or joined this entry, as far as they were noted
    public let messages: [MessageMark]
    /// Money sent to or from someone, or between your own accounts, rather than a purchase
    public let isTransfer: Bool

    /// What's kept of a bank message to tell whether another one is about the same movement
    public struct MessageMark: Sendable, Equatable, Codable {
        public var shape: String?
        public var accountHint: String?
        public var balance: Money?
        public init(shape: String?, accountHint: String?, balance: Money?) {
            self.shape = shape
            self.accountHint = accountHint
            self.balance = balance
        }
    }

    public init(id: UUID, date: Date, amount: Money, direction: Capture.Direction, memo: String, source: Capture.Source?,
                reference: String? = nil, alsoFrom: Capture.Source? = nil, accountId: UUID? = nil,
                messages: [MessageMark] = [], isTransfer: Bool = false) {
        self.id = id
        self.date = date
        self.amount = amount
        self.direction = direction
        self.memo = memo
        self.source = source
        self.reference = reference
        self.alsoFrom = alsoFrom
        self.accountId = accountId
        self.messages = messages
        self.isTransfer = isTransfer
    }
}

public enum CaptureMatcher {
    /// The entry this capture already is, if any.
    ///
    /// - Bank references decide when both sides have one: the same reference is the same movement,
    ///   different references are different ones, however alike they look.
    /// - An Apple Pay tap and the bank's SMS for it arrive minutes apart with different shop names, so a
    ///   different source needs the same amount close in time, and only one capture of each kind can join an entry.
    /// - Two different alerts from the same bank are two purchases (the same alert twice never gets here:
    ///   it has the same key). Wallet taps repeat only when an automation retries, within a couple of minutes.
    /// - An entry the person typed needs the same day and shop.
    /// - `accountId` is where the capture is known to belong; an entry in another account is never it.
    public static func duplicate(of capture: Capture, in entries: [CapturedEntry], accountId: UUID? = nil,
                                 window: TimeInterval = 30 * 60, calendar: Calendar = .current) -> UUID? {
        duplicates(of: capture, in: entries, accountId: accountId, window: window, calendar: calendar).first
    }

    /// Bank messages arrive within minutes of each other when they tell of one movement
    public static let messageWindow: TimeInterval = 15 * 60

    /// Words in a "name" that are really the bank's channel, not a person or shop
    static let channelWords: Set<String> = ["bank", "banking", "app", "mobile", "online", "internet", "transfer", "domestic",
                                            "international", "atm", "branch", "personal", "digital", "ipp", "aani", "instant",
                                            "upi", "neft", "imps", "rtgs", "sepa", "fps", "wire", "swift", "pjsc", "cr", "dr"]

    /// Whether a name says who or where, rather than how ("ADCB Mobile App", "Domestic Transfer")
    public static func saysWho(_ name: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 2 }
        // "Example Bank Mobile App": a bank's own name with a channel word is still the channel
        if words.contains(where: channelOnly.contains) { return false }
        return words.contains { !channelWords.contains($0) && !$0.allSatisfy { $0 == "x" } }
    }
    static let channelOnly: Set<String> = ["banking", "app", "mobile", "online", "internet", "atm", "branch", "transfer", "pjsc"]

    /// A second bank message about a movement already saved from another one: the bank's own alert and
    /// the confirmation, or "transferred via the app" and "credited to Sam". Two alerts worded alike are
    /// two purchases; the balance afterwards, when both give it for the same account, decides outright.
    static func sameMovement(_ capture: Capture, _ entry: CapturedEntry) -> Bool {
        guard !entry.messages.isEmpty else { return false }
        for mark in entry.messages {
            if let a = capture.accountHint, let b = mark.accountHint, a != b { continue }
            if let a = capture.balance, let b = mark.balance, capture.accountHint != nil, capture.accountHint == mark.accountHint {
                if a == b { return true } else { continue }
            }
            if let a = capture.shape, let b = mark.shape, a == b { continue }
            guard capture.shape != nil, mark.shape != nil else { continue }
            if namesDiffer(capture.merchant, entry.memo, transfer: capture.isTransfer || entry.isTransfer) { continue }
            return true
        }
        return false
    }

    /// Two names that can't be the same payee: for purchases two shops with no word in common, for
    /// transfers two that both say who and share nothing
    static func namesDiffer(_ a: String, _ b: String, transfer: Bool) -> Bool {
        let x = Set(StatementImport.merchantWords(a)), y = Set(StatementImport.merchantWords(b))
        guard !x.isEmpty, !y.isEmpty, x.isDisjoint(with: y) else { return false }
        return transfer ? saysWho(a) && saysWho(b) : true
    }

    /// Every entry this capture could be, closest in time first
    public static func duplicates(of capture: Capture, in entries: [CapturedEntry], accountId: UUID? = nil,
                                  window: TimeInterval = 30 * 60, calendar: Calendar = .current) -> [UUID] {
        let words = Set(StatementImport.merchantWords(capture.merchant))
        func sameShop(_ memo: String) -> Bool {
            !words.isEmpty && !words.isDisjoint(with: StatementImport.merchantWords(memo))
        }
        return entries
            .filter { $0.amount == capture.amount && $0.direction == capture.direction }
            .filter { entry in
                if let accountId, let other = entry.accountId, other != accountId { return false }
                if let mine = capture.reference, let theirs = entry.reference { return mine == theirs }
                let gap = abs(entry.date.timeIntervalSince(capture.date))
                switch entry.source {
                case nil:
                    return entry.alsoFrom == nil && calendar.isDate(entry.date, inSameDayAs: capture.date) && sameShop(entry.memo)
                case .sms? where capture.source == .sms:
                    return gap <= messageWindow && sameMovement(capture, entry)
                case let source? where source == capture.source:
                    return source == .applePay && gap <= 2 * 60 && sameShop(entry.memo)
                case .some:
                    // Names the two sources give a shop differ ("Carrefour", "MAF CARREFOUR CITY") but share a word;
                    // two names with nothing in common are two purchases that happen to cost the same
                    let named = !words.isEmpty && !StatementImport.merchantWords(entry.memo).isEmpty
                    return entry.alsoFrom == nil && gap <= window && (!named || sameShop(entry.memo))
                }
            }
            .sorted { abs($0.date.timeIntervalSince(capture.date)) < abs($1.date.timeIntervalSince(capture.date)) }
            .map(\.id)
    }
}
