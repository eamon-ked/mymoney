//
//  StatementPDFDrawn.swift
//  Nokael Money
//
//  The text of a PDF page read from the page's own drawing instructions: each piece of
//  text and where the page puts it. PDFKit's reading mixes up the letters of some
//  statements (numbers that reach the edge of their table cell); the instructions don't.
//  Only plainly encoded text is read. Anything else is left out, so the caller checks
//  the result (a statement's rows against its running balance) before trusting it.
//

import Foundation
import PDFKit
import CoreText

enum StatementPDFDrawn {
    /// Every piece of text the page draws upright in a plainly encoded font, pieces that touch joined.
    /// nil when the page can't be read this way.
    static func textLines(on page: PDFPage) -> [StatementPDF.TextLine]? {
        guard page.rotation == 0, let ref = page.pageRef, let table = CGPDFOperatorTableCreate() else { return nil }
        let stream = CGPDFContentStreamCreateWithPage(ref)
        defer { CGPDFContentStreamRelease(stream); CGPDFOperatorTableRelease(table) }
        let reader = Reader(stream: stream)

        CGPDFOperatorTableSetCallback(table, "q") { _, info in Reader.from(info).saved.append(Reader.from(info).ctm) }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let r = Reader.from(info)
            if let last = r.saved.popLast() { r.ctm = last }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let r = Reader.from(info)
            if let m = Reader.matrix(scanner) { r.ctm = m.concatenating(r.ctm) }
        }
        CGPDFOperatorTableSetCallback(table, "BT") { _, info in
            let r = Reader.from(info)
            r.text = .identity; r.line = .identity
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let r = Reader.from(info)
            var size: CGPDFReal = 0
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopNumber(scanner, &size), CGPDFScannerPopName(scanner, &name), let name else { return }
            r.size = size
            r.font = r.font(named: String(cString: name))
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            var v: CGPDFReal = 0
            if CGPDFScannerPopNumber(scanner, &v) { Reader.from(info).leading = v }
        }
        CGPDFOperatorTableSetCallback(table, "Tr") { scanner, info in
            var v: CGPDFInteger = 0
            if CGPDFScannerPopInteger(scanner, &v) { Reader.from(info).invisible = v == 3 }
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            var x: CGPDFReal = 0, y: CGPDFReal = 0
            if CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) { Reader.from(info).move(x, y) }
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            var x: CGPDFReal = 0, y: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x) else { return }
            Reader.from(info).leading = -y
            Reader.from(info).move(x, y)
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            let r = Reader.from(info)
            if let m = Reader.matrix(scanner) { r.text = m; r.line = m }
        }
        CGPDFOperatorTableSetCallback(table, "T*") { _, info in Reader.from(info).newLine() }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            var s: CGPDFStringRef?
            if CGPDFScannerPopString(scanner, &s), let s { Reader.from(info).show([.text(s)]) }
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            var s: CGPDFStringRef?
            guard CGPDFScannerPopString(scanner, &s), let s else { return }
            Reader.from(info).newLine()
            Reader.from(info).show([.text(s)])
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            var s: CGPDFStringRef?
            var skip: CGPDFReal = 0
            guard CGPDFScannerPopString(scanner, &s), let s, CGPDFScannerPopNumber(scanner, &skip), CGPDFScannerPopNumber(scanner, &skip) else { return }
            Reader.from(info).newLine()
            Reader.from(info).show([.text(s)])
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            var parts: [Reader.Part] = []
            for i in 0..<CGPDFArrayGetCount(array) {
                var s: CGPDFStringRef?
                var n: CGPDFReal = 0
                if CGPDFArrayGetString(array, i, &s), let s { parts.append(.text(s)) }
                else if CGPDFArrayGetNumber(array, i, &n) { parts.append(.shift(n)) }
            }
            Reader.from(info).show(parts)
        }

        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(reader).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        guard CGPDFScannerScan(scanner) else { return nil }
        return joined(reader.pieces)
    }

    /// Pieces drawn one after another on a line (a word at a time, or a line in two halves) made one
    static func joined(_ pieces: [StatementPDF.TextLine]) -> [StatementPDF.TextLine] {
        var out: [StatementPDF.TextLine] = []
        for piece in pieces {
            if let last = out.last, abs(last.rect.minY - piece.rect.minY) < 0.5, abs(last.rect.height - piece.rect.height) < 0.5 {
                let gap = piece.rect.minX - last.rect.maxX
                if gap > -1, gap < last.rect.height * 0.35 {
                    let space = gap > last.rect.height * 0.15 && !last.text.hasSuffix(" ") && !piece.text.hasPrefix(" ")
                    out[out.count - 1] = StatementPDF.TextLine(text: last.text + (space ? " " : "") + piece.text, rect: last.rect.union(piece.rect))
                    continue
                }
            }
            out.append(piece)
        }
        return out.compactMap { piece in
            let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : StatementPDF.TextLine(text: text, rect: piece.rect)
        }
    }

    /// A font whose text is plain letters: how its bytes read and how wide each is, in thousandths of the size
    struct Font {
        var encoding: String.Encoding
        var widths: [Int: CGFloat]
        var measure: CTFont

        func width(of byte: UInt8, _ character: Character) -> CGFloat {
            if let known = widths[Int(byte)] { return known }
            var glyphs = [CGGlyph](repeating: 0, count: 2)
            let units = Array(String(character).utf16)
            guard units.count == 1, CTFontGetGlyphsForCharacters(measure, units, &glyphs, 1) else { return 500 }
            return CGFloat(CTFontGetAdvancesForGlyphs(measure, .horizontal, glyphs, nil, 1))
        }
    }

    final class Reader {
        enum Part { case text(CGPDFStringRef), shift(CGFloat) }

        let stream: CGPDFContentStreamRef
        var ctm = CGAffineTransform.identity
        var saved: [CGAffineTransform] = []
        var text = CGAffineTransform.identity
        var line = CGAffineTransform.identity
        var leading: CGFloat = 0
        var size: CGFloat = 0
        var font: Font?
        var invisible = false
        var fonts: [String: Font?] = [:]
        var pieces: [StatementPDF.TextLine] = []

        init(stream: CGPDFContentStreamRef) { self.stream = stream }

        static func from(_ info: UnsafeMutableRawPointer?) -> Reader { Unmanaged<Reader>.fromOpaque(info!).takeUnretainedValue() }

        static func matrix(_ scanner: CGPDFScannerRef) -> CGAffineTransform? {
            var v = [CGPDFReal](repeating: 0, count: 6)
            for i in (0..<6).reversed() { guard CGPDFScannerPopNumber(scanner, &v[i]) else { return nil } }
            return CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        }

        func move(_ x: CGFloat, _ y: CGFloat) {
            line = CGAffineTransform(translationX: x, y: y).concatenating(line)
            text = line
        }

        func newLine() { move(0, -leading) }

        /// The font's bytes are plain letters when it's a simple font in one of the standard encodings
        func font(named name: String) -> Font? {
            if let known = fonts[name] { return known }
            var found: Font? = nil
            defer { fonts[name] = found }
            var dictionary: CGPDFDictionaryRef?
            guard let object = CGPDFContentStreamGetResource(stream, "Font", name),
                  CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else { return nil }
            func value(_ key: String) -> String? {
                var p: UnsafePointer<CChar>?
                return CGPDFDictionaryGetName(dictionary, key, &p) ? p.map { String(cString: $0) } : nil
            }
            guard let kind = value("Subtype"), ["Type1", "TrueType", "MMType1"].contains(kind) else { return nil }
            var custom: CGPDFDictionaryRef?
            guard !CGPDFDictionaryGetDictionary(dictionary, "Encoding", &custom) else { return nil }
            let encoding: String.Encoding
            switch value("Encoding") {
            case "WinAnsiEncoding", nil: encoding = .windowsCP1252
            case "MacRomanEncoding": encoding = .macOSRoman
            default: return nil
            }
            var widths: [Int: CGFloat] = [:]
            var first: CGPDFInteger = 0
            var array: CGPDFArrayRef?
            if CGPDFDictionaryGetInteger(dictionary, "FirstChar", &first), CGPDFDictionaryGetArray(dictionary, "Widths", &array), let array {
                for i in 0..<CGPDFArrayGetCount(array) {
                    var w: CGPDFReal = 0
                    if CGPDFArrayGetNumber(array, i, &w), w > 0 { widths[first + i] = w }
                }
            }
            // "ABCDEE+Arial,Bold" → "Arial-Bold"; a name the phone doesn't have measures as its nearest match
            let base = (value("BaseFont") ?? "Helvetica").split(separator: "+").last.map(String.init) ?? "Helvetica"
            found = Font(encoding: encoding, widths: widths,
                         measure: CTFontCreateWithName(base.replacingOccurrences(of: ",", with: "-") as CFString, 1000, nil))
            return found
        }

        func show(_ parts: [Part]) {
            var shown = ""
            var width: CGFloat = 0     // in text space
            for part in parts {
                switch part {
                case .shift(let n):
                    width -= n / 1000 * size
                    if n < -250, !shown.isEmpty, !shown.hasSuffix(" ") { shown += " " }
                case .text(let s):
                    guard let font, let bytes = CGPDFStringGetBytePtr(s) else { continue }
                    let data = Data(bytes: bytes, count: CGPDFStringGetLength(s))
                    guard let string = String(data: data, encoding: font.encoding) ?? String(data: data, encoding: .isoLatin1),
                          string.count == data.count else { continue }
                    shown += string
                    for (byte, character) in zip(data, string) { width += font.width(of: byte, character) / 1000 * size }
                }
            }
            let placed = text.concatenating(ctm)
            defer { text = CGAffineTransform(translationX: width, y: 0).concatenating(text) }
            // Upright text only: a watermark set at an angle isn't part of a table
            guard !shown.isEmpty, !invisible, abs(placed.b) < 0.01, abs(placed.c) < 0.01, placed.a > 0 else { return }
            let height = abs(size * placed.d)
            pieces.append(StatementPDF.TextLine(text: shown, rect: CGRect(x: placed.tx, y: placed.ty - height * 0.2,
                                                                         width: max(1, width * placed.a), height: max(1, height))))
        }
    }
}
