//
//  StatementPDF.swift
//  Nokael Money
//
//  A PDF statement turned into rows and cells, so it goes through the same
//  column choice and review as a CSV. Everything runs on this iPhone: the
//  page's tables are read by Vision (iOS 26+), else its text lines by PDFKit.
//

import Foundation
import PDFKit
import UIKit
import NokaelCore
#if canImport(Vision)
import Vision
#endif

enum StatementPDF {
    enum Problem: Error, Equatable, LocalizedError {
        case unreadable
        case locked
        case nothingFound
        case tooLong(pages: Int)

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Couldn't open that PDF. Download it again from your bank."
            case .locked: return "This PDF needs its password."
            case .nothingFound: return "Couldn't find any transactions in this PDF. If your bank offers a CSV file, use that instead."
            case .tooLong(let pages): return "This PDF has \(pages) pages. Choose a statement of \(maxPages) pages or fewer, such as one month."
            }
        }
    }

    static let maxPages = 50

    static func isPDF(_ data: Data) -> Bool { data.prefix(5) == Data("%PDF-".utf8) }

    /// Rows and cells from every page, the column names once at the top.
    /// `progress` is told the page being read and how many there are.
    @MainActor
    static func grid(from data: Data, password: String?, progress: (Int, Int) -> Void = { _, _ in }) async throws -> [[String]] {
        guard let document = PDFDocument(data: data) else { throw Problem.unreadable }
        if document.isLocked {
            guard let password, document.unlock(withPassword: password) else { throw Problem.locked }
        }
        guard document.pageCount > 0 else { throw Problem.unreadable }
        guard document.pageCount <= maxPages else { throw Problem.tooLong(pages: document.pageCount) }

        // A statement made by the bank's system carries its own text: read its table exactly
        var columns: [Column]? = nil
        var fromText: [[String]] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            progress(index + 1, document.pageCount)
            await Task.yield()
            let (rows, found) = textTable(textLines(on: page), columns: columns)
            columns = found ?? columns
            if fromText.isEmpty, let header = columns, !rows.isEmpty { fromText.append(header.map(\.name)) }
            fromText += rows
        }
        if fromText.count > 1 { return fromText }

        // A scanned statement: Vision reads the picture of each page
        var tables: [[String]] = []
        var lines: [[String]] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            progress(index + 1, document.pageCount)
            let found = await tableRows(on: page)
            if found.isEmpty {
                lines += textRows(page.string ?? "")
            } else {
                tables += found
            }
        }
        let grid = tables.isEmpty ? withHeader(lines) : dropRepeatedHeaders(tables)
        guard grid.count > 1 else { throw Problem.nothingFound }
        return grid
    }

    // MARK: - The PDF's own text

    /// A piece of text on the page and where it sits (PDF coordinates: y grows upwards)
    struct TextLine: Equatable {
        var text: String
        var rect: CGRect
    }

    /// A column of the statement's table: its name and where the name sits across the page
    struct Column: Equatable {
        var name: String
        var minX: CGFloat
        var maxX: CGFloat
    }

    /// Every line of text on the page, each table cell's lines separately
    static func textLines(on page: PDFPage) -> [TextLine] {
        guard let all = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        return all.selectionsByLine().flatMap { line -> [TextLine] in
            let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rect = line.bounds(for: page)
            guard !text.isEmpty, !rect.isEmpty else { return [] }
            return split(TextLine(text: text, rect: rect), words: words(along: rect, on: page))
        }
    }

    /// The words along a line and where each sits, as PDFKit finds them one by one
    private static func words(along rect: CGRect, on page: PDFPage) -> [TextLine] {
        var found: [TextLine] = []
        var x = rect.minX + 0.5
        while x < rect.maxX {
            if let word = page.selectionForWord(at: CGPoint(x: x, y: rect.midY)),
               let s = word.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                let b = word.bounds(for: page)
                // A word has no spaces in it, apart from a date written out (PDFKit sometimes offers several
                // words as one), and one further along
                // is taken only when there's nothing but space before it (PDFKit sometimes skips words)
                func clear(to end: CGFloat) -> Bool {
                    end <= x + 1 || (page.selection(for: CGRect(x: x, y: rect.minY, width: end - x - 0.5, height: rect.height))?.string ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let oneWord = !s.contains(where: \.isWhitespace) || s.range(of: leadingDate + "$", options: .regularExpression) != nil
                if b.maxX > x, abs(b.midY - rect.midY) < rect.height / 2, oneWord, clear(to: b.minX) {
                    found.append(TextLine(text: s, rect: b))
                    x = b.maxX + 0.5
                    continue
                }
            }
            x += 1
        }
        return found
    }

    /// A line the PDF keeps together across columns ("150 0.00 1728.8"), cut where the gap
    /// between words is wider than a space. The pieces keep the line's own text.
    static func split(_ line: TextLine, words: [TextLine]) -> [TextLine] {
        guard words.count > 1 else { return [line] }
        let text = line.text as NSString
        // Where each word sits in the line's text
        var at = 0
        var spans: [(range: NSRange, rect: CGRect)] = []
        for word in words {
            let r = text.range(of: word.text, range: NSRange(location: at, length: text.length - at))
            // Right-to-left text keeps its words in the opposite order to where they sit: build the pieces from the words
            guard r.location != NSNotFound else { return byGaps(words, height: line.rect.height) }
            spans.append((r, word.rect))
            at = NSMaxRange(r)
        }
        // Cut only at the wide gaps, so text PDFKit didn't find as a word stays with its neighbours
        var cuts: [(at: Int, x: CGFloat)] = [(0, line.rect.minX)]
        for (a, b) in zip(spans, spans.dropFirst()) where b.rect.minX - a.rect.maxX > line.rect.height * 0.6 {
            cuts.append((b.range.location, b.rect.minX))
        }
        guard cuts.count > 1 else { return [line] }
        var pieces: [TextLine] = []
        for (k, cut) in cuts.enumerated() {
            let end = k + 1 < cuts.count ? cuts[k + 1].at : text.length
            let piece = text.substring(with: NSRange(location: cut.at, length: end - cut.at)).trimmingCharacters(in: .whitespaces)
            // Where the piece ends: its last found word, or the line's end for the last piece
            let maxX = k + 1 < cuts.count ? (spans.last { $0.range.location < end }?.rect.maxX ?? cut.x) : line.rect.maxX
            if !piece.isEmpty {
                pieces.append(TextLine(text: piece, rect: CGRect(x: cut.x, y: line.rect.minY, width: max(1, maxX - cut.x), height: line.rect.height)))
            }
        }
        return pieces
    }

    /// Words grouped where the gap between them is wider than a space, each group one piece
    private static func byGaps(_ words: [TextLine], height: CGFloat) -> [TextLine] {
        var groups: [[TextLine]] = []
        for word in words.sorted(by: { $0.rect.minX < $1.rect.minX }) {
            if let last = groups.last?.last, word.rect.minX - last.rect.maxX <= height * 0.6 {
                groups[groups.count - 1].append(word)
            } else {
                groups.append([word])
            }
        }
        return groups.map { g in
            let text = zip(g, [nil] + g.map(Optional.some)).map { word, before in
                (before.map { word.rect.minX - $0.rect.maxX > height * 0.15 } ?? false ? " " : "") + word.text
            }.joined()
            return TextLine(text: text, rect: g.dropFirst().reduce(g[0].rect) { $0.union($1.rect) })
        }
    }

    /// A date at the start of a piece of text: 11/11/2026, 2026-11-11, 11 Nov 2026, 11-Nov-26, Nov 11, 2026
    static let leadingDate = #"^(\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}|\d{4}[/.\-]\d{1,2}[/.\-]\d{1,2}|\d{1,2}[ \-][A-Za-z]{3,9}\.?[ \-]\d{2,4}|[A-Za-z]{3,9}\.? \d{1,2},? \d{4})"#

    /// A piece that's a value (a date, an amount, a reference) rather than a column's name
    private static func isValue(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber).count
        return text.range(of: leadingDate, options: .regularExpression) != nil
            || (digits > 0 && digits * 2 >= text.filter { !$0.isWhitespace }.count)
    }

    /// The table on one page, read from where its text sits, in any language: the date column is
    /// where dates line up down the page, a new row starts at each of them, the column names are
    /// the lines just above the first one (on one line or two), and lines wrapped in a cell are joined.
    /// Later pages without the column names use the ones found before.
    static func textTable(_ lines: [TextLine], columns known: [Column]?) -> (rows: [[String]], columns: [Column]?) {
        func isDate(_ t: String) -> Bool { t.range(of: leadingDate, options: .regularExpression) != nil }
        // Dates that line up: the largest group sharing a left edge; of groups nearly as large, the leftmost
        var groups: [[TextLine]] = []
        for line in lines.filter({ isDate($0.text) }).sorted(by: { $0.rect.minX < $1.rect.minX }) {
            if let g = groups.indices.first(where: { abs(groups[$0][0].rect.minX - line.rect.minX) < 4 }) {
                groups[g].append(line)
            } else {
                groups.append([line])
            }
        }
        let most = groups.map(\.count).max() ?? 0
        guard let dates = groups.first(where: { $0.count >= max(known == nil ? 2 : 1, (most + 1) / 2) }) else { return ([], known) }
        let firstTop = dates.map(\.rect.maxY).max()!
        let height = dates.map(\.rect.height).sorted()[dates.count / 2]

        // Lines that share a baseline, top of the page first
        var bands: [[TextLine]] = []
        for line in lines.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let last = bands.last?.first, abs(last.rect.midY - line.rect.midY) < 2 {
                bands[bands.count - 1].append(line)
            } else {
                bands.append([line])
            }
        }
        // The column names: the closest line above the first date with several pieces and no values,
        // and the line above that when it continues the names ("Transaction" over "Date")
        var columns = known
        var headerBottom = firstTop + 2.5
        let above = bands.filter { band in band.allSatisfy { $0.rect.minY > firstTop - 1 } }.reversed()
        if let nameBand = above.prefix(3).first(where: { $0.count >= 3 && !$0.contains { isValue($0.text) } }),
           let bottom = nameBand.map(\.rect.minY).min(), bottom - firstTop < height * 8 {
            var names = nameBand.sorted { $0.rect.minX < $1.rect.minX }
            let top = nameBand.map(\.rect.maxY).max()!
            if let upper = bands.first(where: { band in
                   let y = band[0].rect.midY
                   return y > top && y - top < height * 1.2 && !band.contains { isValue($0.text) }
               }), upper.allSatisfy({ u in names.contains { min($0.rect.maxX, u.rect.maxX) > max($0.rect.minX, u.rect.minX) } }) {
                for u in upper {
                    guard let i = names.indices.max(by: { a, b in
                        min(names[a].rect.maxX, u.rect.maxX) - max(names[a].rect.minX, u.rect.minX)
                            < min(names[b].rect.maxX, u.rect.maxX) - max(names[b].rect.minX, u.rect.minX)
                    }) else { continue }
                    names[i] = TextLine(text: u.text + " " + names[i].text, rect: names[i].rect.union(u.rect))
                }
            }
            columns = names.map { Column(name: $0.text, minX: $0.rect.minX, maxX: $0.rect.maxX) }
            headerBottom = bottom
        }
        if columns == nil { columns = alignedColumns(lines.filter { $0.rect.maxY <= firstTop + 1.5 }, dates: dates) }
        guard let columns, columns.count >= 3 else { return ([], nil) }

        let centers = columns.map { ($0.minX + $0.maxX) / 2 }
        func overlaps(_ r: CGRect) -> [CGFloat] { columns.map { min($0.maxX, r.maxX) - max($0.minX, r.minX) } }
        func isAmount(_ t: String) -> Bool { StatementImport.amount(t, currency: "USD") != nil }

        // Pieces of text under the column names. A run of amounts the PDF keeps as one piece
        // across two columns ("5 0.00") is split, each amount's place estimated from its letters.
        var pieces: [(line: TextLine, estimated: Bool)] = []
        for line in lines where line.rect.maxY < headerBottom - 1 {
            let words = line.text.split(separator: " ").map(String.init)
            guard words.count > 1, words.allSatisfy(isAmount), overlaps(line.rect).filter({ $0 > 0 }).count > 1 else {
                pieces.append((line, false)); continue
            }
            let length = CGFloat(line.text.count), width = line.rect.width
            var offset = 0
            for word in words {
                let from = line.rect.minX + width * CGFloat(offset) / length
                let to = line.rect.minX + width * CGFloat(offset + word.count) / length
                pieces.append((TextLine(text: word, rect: CGRect(x: from, y: line.rect.minY, width: to - from, height: line.rect.height)), true))
                offset += word.count + 1
            }
        }
        // First the pieces that sit under a column name, then the rest by how they line up with those:
        // text left-aligned with a column's text (a wrapped description), amounts by their right edge
        var placed: [Int?] = pieces.map { p in
            guard !p.estimated else { return nil }
            let o = overlaps(p.line.rect)
            guard let best = o.indices.max(by: { o[$0] < o[$1] }), o[best] > 0 else { return nil }
            return best
        }
        var lefts = Array(repeating: [CGFloat](), count: columns.count)
        var rights = Array(repeating: [CGFloat](), count: columns.count)
        for (i, c) in placed.enumerated() {
            guard let c else { continue }
            lefts[c].append(pieces[i].line.rect.minX)
            if isAmount(pieces[i].line.text) { rights[c].append(pieces[i].line.rect.maxX) }
        }
        func nearest(_ x: CGFloat, in edges: [[CGFloat]]) -> (column: Int, distance: CGFloat)? {
            edges.indices.compactMap { c in edges[c].map { abs($0 - x) }.min().map { (c, $0) } }.min { $0.1 < $1.1 }
        }
        for i in pieces.indices where placed[i] == nil {
            let r = pieces[i].line.rect
            if isAmount(pieces[i].line.text), let n = nearest(r.maxX, in: rights), n.distance < 12 {
                placed[i] = n.column
            } else if let n = nearest(r.minX, in: lefts), n.distance < 1.5 {
                placed[i] = n.column
            } else {
                placed[i] = centers.indices.min { abs(centers[$0] - r.midX) < abs(centers[$1] - r.midX) }
            }
        }
        let body = pieces.indices.map { (line: pieces[$0].line, column: placed[$0]!) }

        // Each row starts with a date in the date column
        let placedDates = body.filter { p in dates.contains { $0.rect == p.line.rect } }.map(\.column)
        let dateColumn = Dictionary(grouping: placedDates, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? 0
        let starts = body.filter { $0.column == dateColumn && isDate($0.line.text) }
            .map(\.line.rect.maxY).sorted(by: >)
        guard !starts.isEmpty else { return ([], columns) }
        let gaps = zip(starts, starts.dropFirst()).map { $0 - $1 }.sorted()
        let usual = gaps.isEmpty ? 40 : gaps[gaps.count / 2]
        var rows: [[String]] = []
        for (k, top) in starts.enumerated() {
            let bottom = k + 1 < starts.count ? starts[k + 1] : top - usual * 1.5
            var cells = Array(repeating: [TextLine](), count: columns.count)
            for piece in body where piece.line.rect.maxY <= top + 1.5 && piece.line.rect.maxY > bottom + 1.5 {
                cells[piece.column].append(piece.line)
            }
            rows.append(cells.map { pieces in
                pieces.sorted { abs($0.rect.midY - $1.rect.midY) < 2 ? $0.rect.minX < $1.rect.minX : $0.rect.midY > $1.rect.midY }
                    .map(\.text).joined(separator: " ")
            })
        }
        return (rows, columns)
    }

    /// Columns where the page has no names for them, from how the rows' text lines up:
    /// dates and words by their left edge, amounts by their right edge
    static func alignedColumns(_ lines: [TextLine], dates: [TextLine]) -> [Column]? {
        func isAmount(_ t: String) -> Bool { StatementImport.amount(t, currency: "USD") != nil && t.contains { $0 == "." || $0 == "," } }
        func cluster(_ items: [TextLine], edge: (CGRect) -> CGFloat, within: CGFloat) -> [[TextLine]] {
            var out: [[TextLine]] = []
            for item in items.sorted(by: { edge($0.rect) < edge($1.rect) }) {
                if let last = out.last?.last, edge(item.rect) - edge(last.rect) < within { out[out.count - 1].append(item) } else { out.append([item]) }
            }
            return out.filter { $0.count >= 2 }
        }
        let rest = lines.filter { l in !dates.contains { $0.rect == l.rect } }
        let money = cluster(rest.filter { isAmount($0.text) }, edge: \.maxX, within: 4)
        let words = cluster(rest.filter { !isAmount($0.text) }, edge: \.minX, within: 2)
        var spans = [dates] + money
        for w in words {
            let span = (w.map(\.rect.minX).min()!, w.map(\.rect.maxX).max()!)
            // Text under a date or an amount (a time, a note) belongs to that column
            if !spans.contains(where: { s in min(s.map(\.rect.maxX).max()!, span.1) > max(s.map(\.rect.minX).min()!, span.0) }) {
                spans.append(w)
            }
        }
        let columns = spans.map { s in Column(name: "", minX: s.map(\.rect.minX).min()!, maxX: s.map(\.rect.maxX).max()!) }
            .sorted { $0.minX < $1.minX }
        guard columns.count >= 3 else { return nil }
        return columns.enumerated().map { Column(name: "Column \($0.offset + 1)", minX: $0.element.minX, maxX: $0.element.maxX) }
    }

    // MARK: - Tables (iOS 26+)

    /// The page's tables, row by row, when Vision finds any
    @MainActor
    private static func tableRows(on page: PDFPage) async -> [[String]] {
        #if canImport(Vision)
        if #available(iOS 26.0, *) {
            guard let image = render(page) else { return [] }
            guard let observations = try? await RecognizeDocumentsRequest().perform(on: image) else { return [] }
            var out: [[String]] = []
            for observation in observations {
                for table in observation.document.tables {
                    for row in table.rows {
                        let width = (row.map(\.columnRange.upperBound).max() ?? -1) + 1
                        guard width > 1 else { continue }
                        var cells = Array(repeating: "", count: width)
                        for cell in row {
                            cells[cell.columnRange.lowerBound] = cell.content.text.transcript
                                .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                        }
                        if cells.contains(where: { !$0.isEmpty }) { out.append(cells) }
                    }
                }
            }
            return out
        }
        #endif
        return []
    }

    /// The page as a picture, about twice its size, for Vision to read
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(2, 3000 / max(bounds.width, bounds.height, 1))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox).cgImage
    }

    /// Later pages repeat the column names: keep only the first
    static func dropRepeatedHeaders(_ rows: [[String]]) -> [[String]] {
        guard let layout = StatementImport.layout(in: StatementImport.csvText(rows)) else { return rows }
        let header = rows[layout.headerIndex].map { $0.lowercased() }
        return rows.enumerated().filter { index, row in
            index <= layout.headerIndex || row.map { $0.lowercased() } != header
        }.map(\.element)
    }

    // MARK: - Text lines

    private static let datePattern = #"^(\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}|\d{4}-\d{2}-\d{2}|\d{1,2}[ \-][A-Za-z]{3,9}[ \-]\d{2,4})"#
    private static let amountPattern = #"(\(?-?[\d][\d,.' ]*[.,]\d{2}\)?(?:\s?(?:CR|DR|Cr|Dr))?-?)$"#

    /// Lines that start with a date and end with one or more amounts, split into
    /// date, description and amounts. Other lines (headings, totals) are left out.
    static func textRows(_ text: String) -> [[String]] {
        text.components(separatedBy: .newlines).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard let date = line.range(of: datePattern, options: .regularExpression) else { return nil }
            let day = String(line[date])
            line = String(line[date.upperBound...]).trimmingCharacters(in: .whitespaces)
            // A second date straight after the first (a value date) isn't part of the description
            if let value = line.range(of: datePattern, options: .regularExpression) {
                line = String(line[value.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            var amounts: [String] = []
            while amounts.count < 3, let found = line.range(of: amountPattern, options: .regularExpression) {
                let token = String(line[found]).trimmingCharacters(in: .whitespaces)
                // A run like "45.00 1,234.56" is two amounts: split at the last space before the last one
                let parts = token.split(separator: " ").map(String.init)
                let last = parts.count > 1 && parts.last.map({ $0.contains(".") || $0.contains(",") }) == true ? parts.last! : token
                amounts.insert(last, at: 0)
                line = String(line.dropLast(last.count)).trimmingCharacters(in: .whitespaces)
            }
            guard !amounts.isEmpty, !line.isEmpty else { return nil }
            return [day, line] + amounts
        }
    }

    /// Names for the columns of text lines: with two amounts, the second is the balance after the row,
    /// and the amount's sign comes from how the balance moved
    static func withHeader(_ rows: [[String]]) -> [[String]] {
        guard !rows.isEmpty else { return [] }
        let width = rows.map(\.count).max() ?? 3
        if width == 4, rows.allSatisfy({ $0.count == 4 }) {
            return [["Date", "Description", "Amount", "Balance"]] + signedByBalance(rows)
        }
        let names = ["Date", "Description"] + (2..<width).map { width == 3 ? "Amount" : "Amount \($0 - 1)" }
        return [names] + rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    /// Statements often print money out without a minus sign: the running balance says which way it went.
    /// Works for files oldest first or newest first; the first row of the file keeps its own sign.
    static func signedByBalance(_ rows: [[String]]) -> [[String]] {
        let values: [(amount: Int64, balance: Int64)?] = rows.map { row in
            guard let a = StatementImport.amount(row[2], currency: "USD"),
                  let b = StatementImport.amount(row[3], currency: "USD") else { return nil }
            return (a.minorUnits, b.minorUnits)
        }
        /// How the balance moved at row i, given the row whose balance came before it
        func moved(_ i: Int, before j: Int) -> Bool? {
            guard values.indices.contains(j), let now = values[i], let then = values[j] else { return nil }
            let size = abs(now.amount)
            if now.balance == then.balance - size { return true }
            if now.balance == then.balance + size { return false }
            return nil
        }
        let oldestFirst = rows.indices.filter { moved($0, before: $0 - 1) != nil }.count
        let newestFirst = rows.indices.filter { moved($0, before: $0 + 1) != nil }.count
        let step = oldestFirst >= newestFirst ? -1 : 1
        var out = rows
        for i in rows.indices {
            guard let down = moved(i, before: i + step), let v = values[i] else { continue }
            if down, v.amount > 0 { out[i][2] = "-" + rows[i][2] }
            if !down, v.amount < 0 { out[i][2] = rows[i][2].replacingOccurrences(of: "-", with: "") }
        }
        return out
    }
}
