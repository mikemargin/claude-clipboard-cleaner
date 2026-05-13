import Foundation

// MARK: - Detection & Cleaning

/// Detect Claude Code output and clean it.
/// Three independent detection paths:
///   Short:  1-2 line input — requires BOTH leading 2-space AND ≥3 trailing
///           spaces (the multi-line ratio detectors can't vote here).
///   Path A: Many lines have trailing space padding → strip trailing + leading 2-space
///   Path B: Consistent leading 2-space pattern → strip leading 2-space only
func cleanClaudeOutput(_ text: String) -> String? {
    let lines = text.components(separatedBy: "\n")
    guard !lines.isEmpty else { return nil }

    // Dispatch by non-empty count, not raw line count: a 2-content-line copy
    // with a trailing newline has lines.count == 3 but only 2 non-empty lines,
    // which the multi-line ratio detectors (count >= 3 floor) can't vote on.
    let nonEmptyCount = lines.lazy.filter { !$0.isEmpty }.count
    if nonEmptyCount < 3 {
        return cleanShortInput(text, lines: lines)
    }

    let hasPadding = hasTrailingSpacePadding(lines)
    let hasLeading = hasLeadingTwoSpacePattern(lines)

    guard hasPadding || hasLeading else { return nil }

    let cleaned = lines.map { line -> String in
        var s = line

        // Path A: strip trailing spaces
        if hasPadding {
            if let last = s.lastIndex(where: { $0 != " " }) {
                s = String(s[...last])
            } else if !s.isEmpty {
                s = ""
            }
        }

        // Both paths: strip leading 2 spaces
        if s.hasPrefix("  ") {
            s = String(s.dropFirst(2))
        }

        return s
    }.joined(separator: "\n")

    let unwrapped = unwrapParagraphLines(cleaned)

    return unwrapped != text ? unwrapped : nil
}

// MARK: - Short Input (1-2 lines)

/// Clean a 1-2 line input. The multi-line ratio detectors need ≥3 lines to
/// vote, so for short fragments we require BOTH signals on EACH content line:
/// leading 2-space indent AND ≥3 trailing spaces. Either alone matches
/// indented code or generic trailing whitespace — together they're the
/// terminal-copy fingerprint.
func cleanShortInput(_ text: String, lines: [String]) -> String? {
    let nonEmpty = lines.filter { !$0.isEmpty }
    guard !nonEmpty.isEmpty, nonEmpty.count <= 2 else { return nil }

    for line in nonEmpty {
        guard line.hasPrefix("  ") else { return nil }
        let trailing: Int
        if let last = line.lastIndex(where: { $0 != " " }) {
            trailing = line.distance(from: last, to: line.endIndex) - 1
        } else {
            return nil
        }
        guard trailing >= 3 else { return nil }
    }

    // Strip all leading + trailing whitespace from each non-empty line. With so
    // few content lines there's no indent context to preserve, so we're more
    // aggressive than the multi-line path (which only takes 2 leading spaces).
    // Interleaved empty lines pass through (paragraph breaks survive); trailing
    // empties are dropped so a trailing "\n" doesn't leak into the output.
    var cleanedLines = lines.map { line -> String in
        var s = line
        if let last = s.lastIndex(where: { $0 != " " }) {
            s = String(s[...last])
        } else if !s.isEmpty {
            s = ""
        }
        return String(s.drop(while: { $0 == " " || $0 == "\t" }))
    }
    while let last = cleanedLines.last, last.isEmpty {
        cleanedLines.removeLast()
    }
    let cleaned = cleanedLines.joined(separator: "\n")

    // For 2-line short input, hand off to the unwrap so terminal-wrapped
    // paragraphs get joined and structural lines (bullets etc.) stay split.
    // Single-line input is a no-op (unwrap requires >=2 lines).
    let unwrapped = unwrapParagraphLines(cleaned)
    return unwrapped == text ? nil : unwrapped
}

// MARK: - Path A: Trailing Space Padding

/// 50%+ of non-empty lines have ≥3 trailing spaces.
/// Normal text never has this — unique to terminal copy.
func hasTrailingSpacePadding(_ lines: [String]) -> Bool {
    var paddedCount = 0
    var nonEmptyCount = 0

    for line in lines {
        guard !line.isEmpty else { continue }
        nonEmptyCount += 1

        if let lastNonSpace = line.lastIndex(where: { $0 != " " }) {
            let trailingSpaces = line.distance(from: lastNonSpace, to: line.endIndex) - 1
            if trailingSpaces >= 3 {
                paddedCount += 1
            }
        } else {
            // All-space line
            paddedCount += 1
        }
    }

    guard paddedCount >= 3 else { return false }
    return Double(paddedCount) / Double(max(nonEmptyCount, 1)) >= 0.5
}

// MARK: - Post-Processing: Paragraph Unwrapping

/// Terminal display width of a string, counting CJK characters as 2 columns.
func displayWidth(_ s: String) -> Int {
    var w = 0
    for scalar in s.unicodeScalars {
        let v = scalar.value
        // CJK Unified Ideographs, Hangul Syllables, CJK Compatibility,
        // Fullwidth Forms, CJK Ext-A/B, Katakana/Hiragana, CJK Symbols
        if (0x1100...0x115F).contains(v)   // Hangul Jamo
            || (0x2E80...0x303E).contains(v)  // CJK Radicals, Kangxi, CJK Symbols
            || (0x3041...0x33BF).contains(v)  // Hiragana, Katakana, CJK Compat
            || (0x3400...0x4DBF).contains(v)  // CJK Ext-A
            || (0x4E00...0x9FFF).contains(v)  // CJK Unified Ideographs
            || (0xA960...0xA97F).contains(v)  // Hangul Jamo Ext-A
            || (0xAC00...0xD7AF).contains(v)  // Hangul Syllables
            || (0xF900...0xFAFF).contains(v)  // CJK Compat Ideographs
            || (0xFE30...0xFE4F).contains(v)  // CJK Compat Forms
            || (0xFF01...0xFF60).contains(v)  // Fullwidth Forms
            || (0xFFE0...0xFFE6).contains(v)  // Fullwidth Signs
            || (0x20000...0x2FA1F).contains(v) // CJK Ext-B + Compat Supplement
        {
            w += 2
        } else {
            w += 1
        }
    }
    return w
}

/// Join terminal-wrapped lines back into paragraphs.
///
/// A line is a wrap continuation of the previous one when either:
///   - Word-fit: `prev_width + first_word_width` overflows the estimated wrap
///     column (the terminal had no choice but to break).
///   - Hanging-indent residue: ≥2 leading spaces remain after the caller's
///     2-space strip (originally a 4+ space hanging indent). Covers cases
///     where the wrap break lands on a short word so word-fit doesn't fire.
func unwrapParagraphLines(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    guard lines.count >= 2 else { return text }

    // Wrap column = longest non-fenced line. Path A's terminalWidth from the
    // padded-line count is intentionally not used: padded lines can exceed the
    // original wrap point and would falsely suppress detection.
    var maxWidth = 0
    var inFenceForMax = false
    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("```") { inFenceForMax.toggle(); continue }
        if inFenceForMax { continue }
        let w = displayWidth(line)
        if w > maxWidth { maxWidth = w }
    }
    let wrapColumn = max(maxWidth, 40)

    var result: [String] = []
    var prevWidth = 0
    var inCodeBlock = false

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            inCodeBlock = !inCodeBlock
            result.append(line)
            prevWidth = 0
            continue
        }

        if inCodeBlock {
            result.append(line)
            prevWidth = 0
            continue
        }

        let isStructural = isStructuralLine(line)

        // 10-column slack: terminal wraps can land short of the column when the
        // next word doesn't fit at the boundary.
        let firstWord = displayWidthOfFirstWord(line)
        let wouldNotFit = prevWidth > 0
            && firstWord > 0
            && (prevWidth + 1 + firstWord) > wrapColumn - 10

        let isHangingContinuation = line.hasPrefix("  ")
            && !result.isEmpty
            && !result.last!.isEmpty
            && !isStructural

        let shouldJoin = !line.isEmpty
            && !isStructural
            && !result.isEmpty
            && !result.last!.isEmpty
            && (wouldNotFit || isHangingContinuation)

        // Strip residual leading whitespace (hanging-indent residue from a wrap).
        // Joins consume it via the separator; appends would otherwise leak it
        // into the final output.
        let stripped = String(line.drop(while: { $0 == " " || $0 == "\t" }))
        if shouldJoin {
            result[result.count - 1] += " " + stripped
        } else {
            result.append(stripped)
        }

        // Track *original* width for the next pair's wrap-fit. Empty and box-
        // drawing lines reset (real paragraph breaks); other structural lines
        // keep their width so their own wrapped continuations can join.
        prevWidth = (line.isEmpty || isBoxDrawingLine(line)) ? 0 : displayWidth(line)
    }

    return result.joined(separator: "\n")
}

/// First non-space char is in the Unicode Box Drawing block — table rows or
/// separators, which are paragraph boundaries prose can't wrap across.
func isBoxDrawingLine(_ line: String) -> Bool {
    let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
    guard let first = trimmed.unicodeScalars.first else { return false }
    return (0x2500...0x257F).contains(first.value)
}

/// Display width of the first whitespace-delimited token on a line — the
/// smallest unit the terminal could have considered before breaking.
func displayWidthOfFirstWord(_ line: String) -> Int {
    let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
    var endIdx = trimmed.startIndex
    while endIdx < trimmed.endIndex, trimmed[endIdx] != " ", trimmed[endIdx] != "\t" {
        endIdx = trimmed.index(after: endIdx)
    }
    return displayWidth(String(trimmed[..<endIdx]))
}

/// Lines that represent structural elements and should never be joined.
func isStructuralLine(_ line: String) -> Bool {
    let t = line.trimmingCharacters(in: .whitespaces)
    if t.isEmpty { return false }
    if t.hasPrefix("#") { return true }
    if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
    if t.hasPrefix("> ") { return true }
    if t.hasPrefix("⏺") || t.hasPrefix("■") { return true }
    if t.hasPrefix("|") { return true }
    // Box-drawing rows/separators: without this, table rows and ─── lines
    // get joined as if they were prose.
    if isBoxDrawingLine(line) { return true }
    if t.hasPrefix("```") { return true }
    // Numbered list: "1. " or "1) "
    if let dot = t.firstIndex(of: "."), dot > t.startIndex,
       t[t.startIndex..<dot].allSatisfy({ $0.isNumber }),
       t.index(after: dot) < t.endIndex, t[t.index(after: dot)] == " " {
        return true
    }
    if let paren = t.firstIndex(of: ")"), paren > t.startIndex,
       t[t.startIndex..<paren].allSatisfy({ $0.isNumber }),
       t.index(after: paren) < t.endIndex, t[t.index(after: paren)] == " " {
        return true
    }
    return false
}

// MARK: - Path B: Leading 2-Space Pattern

/// 60%+ of non-empty lines have exactly 2 leading spaces (not 3+).
/// "Exactly 2" (not "≥2") is what separates Claude prose from indented code:
/// code samples have mixed depths (2/4/6), so few lines hit exactly-2.
func hasLeadingTwoSpacePattern(_ lines: [String]) -> Bool {
    var twoSpaceCount = 0
    var nonEmptyCount = 0

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        nonEmptyCount += 1

        if line.hasPrefix("  ") && !line.hasPrefix("   ") {
            twoSpaceCount += 1
        }
    }

    // Floor of 3 (was 4): short Claude paragraphs with one hanging-indent
    // continuation otherwise miss detection. Ratio gate still rejects code
    // (covered by test B4).
    guard twoSpaceCount >= 3 else { return false }
    return Double(twoSpaceCount) / Double(max(nonEmptyCount, 1)) >= 0.6
}
