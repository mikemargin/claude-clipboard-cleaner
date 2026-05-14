// MARK: - Test Runner

var passed = 0
var failed = 0

func check(_ condition: Bool, _ msg: String, line: Int = #line) {
    if condition {
        passed += 1
        print("  ✅ \(msg)")
    } else {
        failed += 1
        print("  ❌ \(msg)  (line \(line))")
    }
}

func group(_ name: String, _ block: () -> Void) {
    print("\n\(name)")
    block()
}

// MARK: - Helpers

/// Add trailing spaces to each line using display width (CJK-aware).
func pad(_ text: String, width: Int = 131) -> String {
    text.components(separatedBy: "\n").map { line in
        let dw = displayWidth(line)
        return dw < width ? line + String(repeating: " ", count: width - dw) : line
    }.joined(separator: "\n")
}

/// Add varied trailing spaces per line (simulates real terminal variance)
func addTrailing(_ lines: [String], counts: [Int]) -> String {
    zip(lines, counts).map { line, n in
        line + String(repeating: " ", count: n)
    }.joined(separator: "\n")
}

// MARK: - Path A: Trailing Padding

group("A1: Standard output — trailing + leading cleaned") {
    let input = pad("""
    ⏺ Project Status — Summary

      ■ Done
      1. Upload — file select
      2. Analysis — auto split
      3. Moderation — filtering
      4. Generation — output
      5. Progress — streaming
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(!r.contains("  ■"), "leading stripped")
        let hasTrailing = r.components(separatedBy: "\n").contains { $0.hasSuffix("   ") }
        check(!hasTrailing, "trailing stripped")
    }
}

group("A2: No ⏺, middle copy") {
    let input = pad("  3. Three\n  4. Four\n  5. Five\n  6. Six\n  7. Seven\n  8. Eight")
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected without ⏺")
    if let r = result { check(r.hasPrefix("3."), "leading stripped") }
}

group("A3: Minimum 3 padded lines") {
    let input = pad("  ■ Done\n  1. Upload\n  2. Analysis")
    check(cleanClaudeOutput(input) != nil, "3-line minimum")
}

group("A4: Non-uniform trailing widths (CJK real case)") {
    // Simulates real terminal: CJK lines have fewer trailing spaces than ASCII lines
    // but all lines HAVE trailing spaces
    let input = addTrailing([
        "⏺ 프로젝트 현황",
        "  ■ 완료 (13/18)",
        "  1. 업로드 — 파일 선택",
        "  2. 분석 — AI 자동 분할",
        "  3. 모더레이션 — 필터링",
        "  4. 생성 — 정리본",
    ], counts: [98, 115, 28, 84, 40, 80])
    let result = cleanClaudeOutput(input)
    check(result != nil, "CJK with varied trailing detected")
    if let r = result {
        check(!r.hasSuffix(" "), "trailing stripped")
    }
}

group("A5: All-space blank lines → empty") {
    let blank = String(repeating: " ", count: 80)
    let input = [
        "⏺ Title" + String(repeating: " ", count: 73),
        blank,
        "  ■ Section" + String(repeating: " ", count: 69),
        "  1. Item" + String(repeating: " ", count: 71),
        blank,
        "  2. Item" + String(repeating: " ", count: 71),
    ].joined(separator: "\n")
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.components(separatedBy: "\n").filter({ $0.isEmpty }).count >= 2, "blank lines cleaned")
    }
}

// MARK: - Path B: Leading 2-Space

group("B1: Claude response text — leading 2-space only") {
    let input = "⏺ Build complete.\n\n  ~/project/\n  - One\n  - Two\n  - Three\n  - Four\n  - Five"
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected via leading 2-space")
    if let r = result {
        check(!r.contains("  ~/"), "leading stripped")
        check(r.contains("⏺"), "⏺ preserved")
    }
}

group("B2: No ⏺, leading 2-space only") {
    let input = "  - First\n  - Second\n  - Third\n  - Fourth\n  - Fifth"
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected without ⏺")
    if let r = result { check(r.hasPrefix("- First"), "leading stripped") }
}

group("B3: Below 3-line threshold") {
    // Path B requires ≥3 exactly-2-space lines (lowered from 4 so that short
    // 3-or-4-line Claude paragraphs detect; see hasLeadingTwoSpacePattern).
    // 2 bullets fall under the short-input path which requires both signals.
    check(cleanClaudeOutput("  - One\n  - Two") == nil, "2 lines below threshold")
}

group("B3b: Three-line all-bullets fires (post-threshold-change)") {
    // Documents the deliberate behavior change: 3 bullet items with exactly
    // 2-space leading is Claude output and gets cleaned.
    let result = cleanClaudeOutput("  - One\n  - Two\n  - Three")
    check(result != nil, "3 bullets detected")
    if let r = result {
        check(r == "- One\n- Two\n- Three", "leading stripped")
    }
}

group("B4: Mixed-depth code rejected") {
    let input = "function hello() {\n  console.log(\"hi\");\n  if (true) {\n    return 42;\n  }\n}"
    check(cleanClaudeOutput(input) == nil, "code rejected")
}

group("B5: Below 60% ratio") {
    let input = "Title\nAnother\nThird\n  - One\n  - Two\n  - Three\n  - Four\nFooter\nMore\nEnd"
    check(cleanClaudeOutput(input) == nil, "40% rejected")
}

group("B6: Numbered list with 5-space continuations — relaxed ratio fires") {
    // Real failure mode: Claude formats numbered lists with hanging
    // continuations at 5 leading spaces. "Exactly 2" ratio dropped below
    // 60% when continuations dominated. The relaxed rule counts >=2
    // leading toward the ratio (continuations still vote) while keeping a
    // >=3 exactly-2 absolute floor (so an all-deeper-indent code block
    // still gets rejected per B4).
    let input =
        "  Three follow-ups uncovered while testing:\n" +
        "\n" +
        "  1. Dispatch to short-input by non-empty line count, not raw line\n" +
        "     count. A 2-content-line copy with a trailing newline has\n" +
        "     lines.count == 3 but only 2 non-empty lines.\n" +
        "\n" +
        "  2. Hanging-indent residue is relative to the baseline indent.\n" +
        "     Uniformly-indented content leaves every line at the same\n" +
        "     residue depth after Path A's strip.\n" +
        "\n" +
        "  3. Indent reset ends a hanging-indent block.\n"
    let result = cleanClaudeOutput(input)
    check(result != nil, "numbered-list content detected")
    if let r = result {
        check(r.contains("1. Dispatch"), "item 1 preserved")
        check(r.contains("not raw line count"), "item 1 continuation joined")
        check(r.contains("2. Hanging-indent"), "item 2 preserved")
        check(r.contains("3. Indent reset"), "item 3 preserved")
    }
}

// MARK: - Negatives

group("N1: Plain text") {
    check(cleanClaudeOutput("Hello world\nNormal text\nNo patterns\nJust content") == nil, "plain text")
}

group("N2: ⏺ alone") {
    check(cleanClaudeOutput("⏺ Title\nFirst line\nSecond line\nThird line") == nil, "⏺ alone not enough")
}

group("N3: Too short") {
    check(cleanClaudeOutput("") == nil, "empty")
    check(cleanClaudeOutput("one line") == nil, "1 line")
    check(cleanClaudeOutput("one\ntwo") == nil, "2 lines")
}

group("N4: Markdown") {
    check(cleanClaudeOutput("# Title\n\nParagraph.\n\n- One\n- Two\n- Three\n\n## Next") == nil, "markdown")
}

// MARK: - Paragraph Unwrapping

group("U1: Wrapped paragraph is joined") {
    let input = pad("""
      This is a paragraph of text that Claude has outputted and it wraps at the
      terminal width so each line is about the same length and when you copy it
      you get hard line breaks that you do not want in the pasted text.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let lines = r.components(separatedBy: "\n")
        check(lines.count == 1, "joined into single line, got \(lines.count)")
        check(r.contains("outputted and it wraps at the terminal"), "no extra spaces at join")
    }
}

group("U2: Paragraph breaks preserved") {
    let input = pad("""
      First paragraph that is long enough to be considered a wrapped line in the
      terminal output and should be joined into a single paragraph of text here.

      Second paragraph that is also long enough to be considered a wrapped line
      in the terminal and should remain separate from the first paragraph above.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let paragraphs = r.components(separatedBy: "\n\n")
        check(paragraphs.count == 2, "two paragraphs preserved, got \(paragraphs.count)")
    }
}

group("U3: List items not joined") {
    let input = pad("""
      Here is a long introduction paragraph that explains what the list below is
      going to contain and provides the necessary context for the reader to know.

      - First item in the list
      - Second item in the list
      - Third item in the list
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.contains("\n- First"), "list items stay separate")
        check(r.contains("\n- Second"), "list items stay separate")
    }
}

group("U4: Numbered list items not joined") {
    let input = pad("""
      Here is a long introduction paragraph that explains what the numbered list
      below is going to contain and provides the necessary context for reading.

      1. First numbered item
      2. Second numbered item
      3. Third numbered item
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.contains("\n1. First"), "numbered items stay separate")
        check(r.contains("\n2. Second"), "numbered items stay separate")
    }
}

group("U5: Code blocks not unwrapped") {
    let input = pad("""
      Here is a description of the code that follows and it is long enough to be
      considered a terminal-wrapped line that would normally be joined together.

      ```swift
      func hello() {
          print("world")
      }
      ```
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.contains("```swift\nfunc hello()"), "code block preserved")
        check(r.contains("\"world\")\n}"), "code indentation preserved")
    }
}

group("U6: Short lines not joined") {
    let input = pad("""
      ⏺ Build complete.

      Files changed:
      src/main.ts
      src/utils.ts
      README.md
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.contains("src/main.ts\nsrc/utils.ts"), "short lines stay separate")
    }
}

group("U7: Headings not joined") {
    let input = pad("""
      This is a long paragraph that explains the overall structure of the document
      and provides context that the reader needs to understand the sections below.

      ## Section Two

      Another long paragraph that goes into detail about section two and provides
      additional context and information that the reader needs to fully understand.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.contains("\n## Section Two\n"), "heading stays separate")
    }
}

group("U8: Mixed content — paragraphs unwrapped, structure preserved") {
    let input = pad("""
      ⏺ Here is a summary of the changes that were made to the project as part of
      this latest update to the codebase and the associated documentation files.

      Key changes:
      - Updated the build configuration
      - Fixed the deployment script
      - Added new tests

      The deployment should now work correctly and the tests should all pass when
      run against the staging environment with the updated configuration values.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        // ⏺ line is structural, should NOT be joined
        check(r.hasPrefix("⏺ Here is a summary"), "⏺ line preserved")
        // But the continuation after ⏺ should be joined since ⏺ is structural
        // Actually ⏺ line is structural so it won't join with next line
        check(r.contains("\n- Updated"), "list items separate")
        // Last paragraph should be joined
        check(r.contains("pass when run against"), "last paragraph joined")
    }
}

group("U9: CJK paragraph joined — Path A with terminal width") {
    // 한국어: 터미널에서 글자당 2칸, String.count는 1
    // Path A trailing space → 터미널 너비 추론 가능
    let w = 80
    let line1 = "  이것은 클로드 코드에서 출력된 긴 문단입니다. 터미널 너비에 맞춰서 자동으로"
    let line2 = "  줄바꿈이 되어 복사하면 하드 줄바꿈이 남아서 붙여넣기할 때 문단이 끊어집니다."
    let input = [line1, line2, "  세번째줄", "  네번째줄", "  다섯번째줄"].map {
        let pad = max(w - $0.count, 3)
        return $0 + String(repeating: " ", count: pad)
    }.joined(separator: "\n")
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let lines = r.components(separatedBy: "\n")
        check(lines.count < 5, "CJK joined, got \(lines.count) lines")
    }
}

group("U10: CJK paragraph joined — Path B without trailing space") {
    // Path B: trailing space 없이 leading 2-space만 있는 경우
    // displayWidth fallback (>=60) 사용
    let input = [
        "  이것은 클로드 코드에서 출력된 긴 문단입니다. 터미널 너비에 맞춰서 자동으로 줄바꿈이",
        "  되었기 때문에 복사하면 하드 줄바꿈이 그대로 남아서 붙여넣기할 때 문단이 끊어집니다.",
        "  이 줄도 충분히 길어서 합쳐져야 합니다.",
        "  네번째줄",
        "  다섯번째줄",
    ].joined(separator: "\n")
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        // 첫 두 줄은 displayWidth >= 60이므로 합쳐져야 함
        check(r.hasPrefix("이것은 클로드"), "leading stripped")
        check(r.contains("줄바꿈이 되었기"), "first two lines joined")
    }
}

group("U11: Korean + English mixed paragraph") {
    let input = pad("""
      Claude Code는 터미널 기반 AI 코딩 도구입니다. 이 도구는 사용자의 코드를 분석하고
      개선 사항을 제안하며, 실시간으로 코드를 작성하고 수정할 수 있습니다. 다양한 언어를
      지원하며 프로젝트 컨텍스트를 이해하고 적절한 변경을 제안합니다.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let lines = r.components(separatedBy: "\n")
        check(lines.count == 1, "mixed KR+EN joined into 1 line, got \(lines.count)")
    }
}

group("U12: Korean list after paragraph — not joined") {
    let input = pad("""
      이 프로젝트는 다음과 같은 기능을 제공합니다. 각 기능은 독립적으로 동작하며 사용자가
      원하는 대로 설정할 수 있습니다.

      - 클립보드 자동 모니터링
      - 터미널 출력 정리
      - 메뉴바 아이콘 피드백
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.contains("\n- 클립보드"), "KR list items separate")
        check(r.contains("\n- 터미널"), "KR list items separate")
        let firstParagraph = r.components(separatedBy: "\n\n")[0]
        check(!firstParagraph.contains("\n"), "KR paragraph joined")
    }
}

group("U13: Japanese text wrapping") {
    let input = pad("""
      これはClaudeのターミナル出力のテストです。日本語のテキストもターミナル幅に合わせて
      自動的に折り返されます。コピーするとハードな改行が残ってしまいます。長い文章を書くと
      このようにターミナルの幅で自動的に改行されてクリップボードにコピーされます。
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let lines = r.components(separatedBy: "\n")
        check(lines.count == 1, "JP joined into 1 line, got \(lines.count)")
    }
}

group("U14: Korean code block preserved") {
    let input = pad("""
      다음은 설정 파일의 예시입니다. 이 파일은 프로젝트 루트에 위치해야 하며 올바른 형식을
      따라야 합니다. 잘못된 형식은 빌드 오류를 유발할 수 있습니다.

      ```json
      {
        "name": "claude-clipboard-cleaner",
        "version": "1.0.0"
      }
      ```

      위 설정을 적용한 후 빌드를 다시 실행하면 정상적으로 동작합니다. 문제가 지속되면
      캐시를 삭제하고 다시 시도해 주세요.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.contains("```json\n{"), "code block preserved")
        check(r.contains("\"1.0.0\"\n}"), "code indentation preserved")
        // Paragraphs before and after code should be joined
        check(r.contains("형식을 따라야"), "KR paragraph before code joined")
        check(r.contains("지속되면 캐시를"), "KR paragraph after code joined")
    }
}

group("U15: Short Korean lines NOT joined") {
    let input = pad("""
      ⏺ 빌드 완료.

      변경된 파일:
      src/main.ts
      src/utils.ts
      README.md
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        check(r.contains("src/main.ts\nsrc/utils.ts"), "short KR lines stay separate")
    }
}

group("U16: English-only paragraph — baseline") {
    let input = pad("""
      The clipboard cleaner monitors your clipboard every 300 milliseconds and automatically
      detects when you have copied text from a Claude Code terminal session. It then strips the
      trailing whitespace padding and leading two-space indentation that the terminal adds.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let lines = r.components(separatedBy: "\n")
        check(lines.count == 1, "EN paragraph joined into 1 line, got \(lines.count)")
    }
}

group("U17: Emoji in paragraph text") {
    let input = pad("""
      🚀 이 프로젝트는 클립보드를 자동으로 정리하는 macOS 메뉴바 앱입니다. Claude Code에서
      복사한 텍스트의 불필요한 공백을 제거하고 깔끔한 텍스트로 변환해 줍니다. 설치 후에는
      별도의 설정 없이 바로 사용할 수 있습니다.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let lines = r.components(separatedBy: "\n")
        check(lines.count == 1, "emoji+KR joined into 1 line, got \(lines.count)")
        check(r.hasPrefix("🚀"), "emoji preserved")
    }
}

group("U18: Multiple emoji paragraphs") {
    let input = pad("""
      ✅ 빌드가 성공적으로 완료되었습니다. 모든 테스트가 통과했으며 배포 준비가 되었습니다.
      이제 다음 단계로 진행할 수 있습니다.

      ⚠️ 다만 몇 가지 경고가 있습니다. 사용하지 않는 변수가 발견되었으며 일부 타입 변환에서
      잠재적인 문제가 발견되었습니다. 가능하면 수정하는 것을 권장합니다.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let paragraphs = r.components(separatedBy: "\n\n")
        check(paragraphs.count == 2, "two emoji paragraphs, got \(paragraphs.count)")
        // ⏺/■ are structural but ✅/⚠️ are not — they should be joined
        check(r.contains("되었습니다. 이제"), "first emoji paragraph joined")
        check(r.contains("발견되었습니다. 가능하면"), "second emoji paragraph joined")
    }
}

// MARK: - Real Session Data (from Claude Code sessions on Mac mini)

group("R1: KR prose — project analysis (ai-space session)") {
    // Real: 한국어 산문, 프로젝트 분석. 터미널 120칸에서 줄바꿈된 형태.
    let input = pad("""
      Claude Code는 프로젝트 경로별로 세션을 모아놓습니다. /Users/lullu/mainpy에서 작업하면
      ~/.claude/projects/-Users-lullu-mainpy/ 안에 세션 JSONL이 쌓입니다. 그래서 이 프로젝트에서
      뭘 했더라는 찾기 쉽지만, 어제 뭘 했더라는 찾기 어렵습니다.

      Codex는 정반대로 날짜별로 정리합니다. sessions/2026/03/06/ 같은 식. 그래서 오늘 뭘 했더라는
      되지만, 이 프로젝트에서 뭘 했더라를 보려면 SQLite를 뒤져야 합니다.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let paragraphs = r.components(separatedBy: "\n\n")
        check(paragraphs.count == 2, "two paragraphs preserved, got \(paragraphs.count)")
        check(!paragraphs[0].contains("\n"), "first KR paragraph joined")
        check(!paragraphs[1].contains("\n"), "second KR paragraph joined")
    }
}

group("R2: KR+EN mixed — quant analysis (xd1-toss session)") {
    // Real: 한국어+영어 혼합, 퀀트 분석. 기술 용어와 숫자 포함.
    let input = pad("""
      솔직히 말하면 ELv3 core signal 자체가 약하다. spread + density 필터로 쓰레기를 걸러내면
      잠시 양수로 보이지만, 진짜 OOS에서 재현이 안 된다. Codex Reviewer A가 처음에 말했던 대로
      stripped core가 CSCV + OOS를 통과 못하면 kill 조건에 해당한다.

      SL 민감도는 events의 fwd_ret_min으로 근사할 수 있다. fwd_ret_min이 SL 이하이면 SL exit,
      아니면 timeout exit. 이 방식으로 전체 백테스트를 다시 돌려야 한다.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let paragraphs = r.components(separatedBy: "\n\n")
        check(paragraphs.count == 2, "two paragraphs, got \(paragraphs.count)")
        check(r.contains("약하다. spread"), "mixed KR+EN first paragraph joined")
        check(r.contains("있다. fwd_ret_min"), "mixed KR+EN second paragraph joined")
    }
}

group("R3: KR+EN mixed — API explanation (lullu session)") {
    // Real: Anthropic API 설명. backtick 인라인 코드와 한국어 혼합.
    let input = pad("""
      Anthropic API 자체가 서버사이드 툴로 web_search와 web_fetch를 제공합니다. 별도 API 키가
      필요한 게 아니라, 지금 쓰고 있는 Anthropic API 키에 tools 파라미터만 추가하면 됩니다.

      이게 Claude Code 내부에서 웹서치할 때 쓰는 바로 그 메커니즘입니다. 서버에서 실행되고 결과가
      server_tool_use + web_search_tool_result 블록으로 돌아옵니다.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let paragraphs = r.components(separatedBy: "\n\n")
        check(paragraphs.count == 2, "two paragraphs, got \(paragraphs.count)")
        check(r.contains("키가 필요한"), "API explanation first paragraph joined")
        check(r.contains("실행되고 결과가"), "API explanation second paragraph joined")
    }
}

group("R4: KR prose with numbers — investment insight (kakao-play session)") {
    // Real: 투자 인사이트, 숫자/퍼센트/인용구 포함.
    let input = pad("""
      SK하이닉스를 불장 고점에 사면 -20%, 전쟁 폭락에 사면 +18%. 같은 종목, 같은 AI/HBM
      스토리인데 결과가 정반대. 공포가 만든 할인이 최고의 안전마진이다.

      상한가 다음날, 리포트 상향일, 시간외 급등 후, 전쟁 테마 급등일 — 추격매수 5D 평균
      -10% 이상. 반면 조용히 축적한 테크윙 +55.9%, 삼성중공업 +16.1%가 최고 성과.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let paragraphs = r.components(separatedBy: "\n\n")
        check(paragraphs.count == 2, "two paragraphs, got \(paragraphs.count)")
        check(r.contains("AI/HBM 스토리인데"), "numbers+KR first paragraph joined")
        check(r.contains("평균 -10%"), "numbers+KR second paragraph joined")
    }
}

group("R5: KR prose — multi-machine workflow (ai-space session)") {
    // Real: 업무 머신 사용 패턴 분석. 매우 긴 한국어 산문.
    let input = pad("""
      macpro는 업무 머신입니다. gpai-monorepo를 1번부터 5번까지 복사본을 만들어놓고, 각 복사본에서
      Claude Code 세션을 열어서 서로 다른 피처 브랜치나 실험을 병렬로 진행합니다. 한 복사본이
      1~2주 동안 집중적으로 쓰이다가 다음 복사본으로 넘어가는 패턴이 있습니다.

      Mac Mini는 1월 28일에 셋업했고, 개인 프로젝트 전용입니다. xd1, diem-app, localslack,
      image-gen 같은 사이드 프로젝트들. 같은 프로젝트가 양쪽 머신에 다 있긴 한데, 같은 날
      같은 프로젝트를 두 머신에서 동시에 작업하는 경우는 거의 없습니다.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let paragraphs = r.components(separatedBy: "\n\n")
        check(paragraphs.count == 2, "two paragraphs, got \(paragraphs.count)")
        check(!paragraphs[0].contains("\n"), "long KR paragraph 1 fully joined")
        check(!paragraphs[1].contains("\n"), "long KR paragraph 2 fully joined")
    }
}

group("R6: KR+EN mixed with list — real Claude output pattern") {
    // Real: Claude Code 전형적 응답 — 설명 산문 + 리스트 + 마무리 산문
    let input = pad("""
      이 프로젝트는 macOS 메뉴바 앱으로, Claude Code 터미널 출력을 자동으로 정리합니다. 0.3초마다
      클립보드를 모니터링하고, 터미널에서 복사한 텍스트의 trailing space와 leading indent를
      자동으로 제거합니다.

      주요 변경사항:
      - displayWidth 함수 추가 (CJK 문자 2칸 처리)
      - Path A에서 터미널 너비 추론 로직 추가
      - unwrapParagraphLines threshold를 display width 기반으로 변경

      이 변경으로 한국어, 일본어 등 CJK 텍스트에서도 터미널 줄바꿈이 정상적으로 해제됩니다.
      기존 영어 텍스트 처리에는 영향이 없습니다.
    """)
    let result = cleanClaudeOutput(input)
    check(result != nil, "detected")
    if let r = result {
        let paragraphs = r.components(separatedBy: "\n\n")
        check(paragraphs.count == 3, "three sections, got \(paragraphs.count)")
        check(!paragraphs[0].contains("\n"), "intro paragraph joined")
        check(r.contains("\n- displayWidth"), "list items preserved")
        check(r.contains("\n- Path A"), "list items preserved")
        check(r.contains("해제됩니다. 기존"), "closing paragraph joined")
    }
}

// MARK: - Short Input (1-2 lines)

group("S1: Single line — leading 2-space + trailing pad → cleaned") {
    let input = "  Plan promise: Flip sandbox.enabled default to true.                                  "
    let result = cleanClaudeOutput(input)
    check(result != nil, "single line detected")
    if let r = result {
        check(r == "Plan promise: Flip sandbox.enabled default to true.", "leading and trailing stripped")
    }
}

group("S2: Single line — leading only (no trailing pad) → not cleaned") {
    // Looks like indented code; no terminal-padding signal.
    check(cleanClaudeOutput("  return foo()") == nil, "indented code rejected")
}

group("S3: Single line — trailing only (no leading) → not cleaned") {
    check(cleanClaudeOutput("Hello world.   ") == nil, "no leading 2-space rejected")
}

group("S4: Single line — neither signal → not cleaned") {
    check(cleanClaudeOutput("Hello world.") == nil, "plain single line rejected")
}

group("S5: Single line — deeper leading (4-space hanging) + pad → fully stripped") {
    // Hanging-indent continuation copied alone. Strip all leading + trailing.
    let input = "    that try to cat ~/.ssh/... under sandbox.                                "
    let result = cleanClaudeOutput(input)
    check(result != nil, "deeper leading detected")
    if let r = result {
        check(r == "that try to cat ~/.ssh/... under sandbox.", "all leading stripped")
    }
}

group("S6: Single line + trailing newline → still cleaned") {
    let input = "  Plan promise: Flip sandbox.                              \n"
    let result = cleanClaudeOutput(input)
    check(result != nil, "single line with trailing \\n detected")
    if let r = result {
        check(r == "Plan promise: Flip sandbox.", "stripped to clean text")
    }
}

group("S7: Two non-empty lines — both signals on both → cleaned and joined") {
    // Both lines carry the terminal-copy fingerprint and the second is a wrap
    // continuation of the first — unwrap should join them.
    let input = "  Plan: we should ship this feature                              \n  before the deadline.                              "
    let result = cleanClaudeOutput(input)
    check(result != nil, "2-line short input detected")
    if let r = result {
        check(r == "Plan: we should ship this feature before the deadline.", "wrap continuation joined")
    }
}

group("S8: Two lines, one missing trailing pad → rejected") {
    let input = "  Line one                              \n  Line two"
    check(cleanClaudeOutput(input) == nil, "missing trailing on one line rejects")
}

group("S9: Two lines, one missing leading 2-space → rejected") {
    let input = "  Line one                              \nLine two                              "
    check(cleanClaudeOutput(input) == nil, "missing leading on one line rejects")
}

group("S10: Two-line bullets → cleaned but not joined (structural)") {
    let input = "  - First bullet                              \n  - Second bullet                              "
    let result = cleanClaudeOutput(input)
    check(result != nil, "2-line bullets detected")
    if let r = result {
        check(r == "- First bullet\n- Second bullet", "bullets preserved as separate lines")
    }
}

group("S11: Two padded lines + trailing newline → cleaned (dispatch by non-empty count)") {
    // Real failure mode from user: copying 2 lines from a terminal often
    // includes a trailing newline, making lines.count == 3 but only 2 are
    // non-empty. Multi-line path can't vote on 2 lines; short path must
    // pick it up.
    let input = "  git checkout -b cleaner-improvements                              \n  next line here.                              \n"
    let result = cleanClaudeOutput(input)
    check(result != nil, "2-content-line + trailing newline detected")
    if let r = result {
        check(r == "git checkout -b cleaner-improvements next line here.", "lines joined per word-fit")
    }
}

group("S12: Two padded lines with interleaved blank → cleaned, paragraph preserved") {
    let input = "  First paragraph.                              \n\n  Second paragraph.                              "
    let result = cleanClaudeOutput(input)
    check(result != nil, "2-content-line + interleaved blank detected")
    if let r = result {
        check(r == "First paragraph.\n\nSecond paragraph.", "interleaved blank line preserved")
    }
}

// MARK: - Indent Baseline (Hanging-Indent Relativity)

group("I1: Uniform deep indent — trailing short line stays on its own line") {
    // Heredoc-style content: every line has 4-space leading. After Path A
    // strips 2 leading, every line has 2-space residue — that's the document
    // baseline, not a hanging-indent signal. The trailing "EOF" line is
    // short and the previous line didn't fill the wrap column, so the
    // terminal had no reason to wrap. EOF must stay on its own line.
    let input =
        "    Short Claude paragraphs (3-4 lines) with one hanging-indent               \n" +
        "    continuation miss detection: only 3 of 4 lines satisfy \"exactly 2         \n" +
        "    leading spaces\", failing the >=4 floor even when the 60% ratio gate       \n" +
        "    passes by a wide margin. Ratio gate still rejects code (test B4).         \n" +
        "                                                                              \n" +
        "    Test updates: B3 rephrased for the 2-line case, B3b added (3 bullets      \n" +
        "    fires), E1 input updated.                                                 \n" +
        "                                                                              \n" +
        "    All 125 tests pass.                                                       \n" +
        "    EOF                                                                       "
    let result = cleanClaudeOutput(input)
    check(result != nil, "deep-indent content detected")
    if let r = result {
        check(r.contains("\nEOF"), "EOF on its own line")
        check(!r.contains("pass. EOF"), "EOF not joined to previous line")
    }
}

group("I2: Mixed indent — deeper lines join, baseline reset breaks paragraph") {
    // Baseline = 0 (most lines flush left after Path A strips 2 leading).
    // A line deeper than baseline IS a real hanging-indent continuation
    // and should still join, even when word-fit math wouldn't fire.
    let input =
        "  Some prose ends with a colon:                                         \n" +
        "    nested hanging continuation here.                                   \n" +
        "  More flush-left prose follows.                                        "
    let result = cleanClaudeOutput(input)
    check(result != nil, "mixed-indent content detected")
    if let r = result {
        check(r.contains("colon: nested hanging continuation"), "deeper line joined as continuation")
        check(r.contains("\nMore flush-left prose"), "flush-left line stays separate")
    }
}

// MARK: - Edge Cases

group("E1: Below both thresholds") {
    // Trailing pads are <3 (Path A fails), and only 2 lines have exactly
    // 2-space leading (Path B's count of 3 fails).
    let input = "⏺ Title  \n  Line one \nplain text\n  Line two  "
    check(cleanClaudeOutput(input) == nil, "below both paths")
}

group("E2: Some lines unpadded, but enough ratio") {
    let w = 100
    let input = [
        "⏺ Title" + String(repeating: " ", count: w - 7),
        String(repeating: " ", count: w),
        "  Line one" + String(repeating: " ", count: w - 10),
        "  Short",
        "  Line three" + String(repeating: " ", count: w - 12),
        "  Line four" + String(repeating: " ", count: w - 11),
        "  Line five" + String(repeating: " ", count: w - 11),
    ].joined(separator: "\n")
    let result = cleanClaudeOutput(input)
    check(result != nil, "partial padding detected")
    if let r = result { check(r.contains("Short"), "unpadded line preserved") }
}

// MARK: - Results

print("\n" + String(repeating: "─", count: 40))
print("Results: \(passed) passed, \(failed) failed")
if failed > 0 {
    print("⚠️  SOME TESTS FAILED")
    exit(1)
} else {
    print("✅ ALL TESTS PASSED")
    exit(0)
}
