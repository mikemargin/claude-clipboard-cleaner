# Claude Clipboard Cleaner

macOS MenuBar app that automatically cleans Claude Code terminal output when you copy it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/demo-dark.png">
  <img src="docs/demo-light.png" alt="Demo">
</picture>

When you copy text from Claude Code's terminal, it comes with trailing space padding and leading 2-space indentation. This app detects that pattern and strips it automatically — so your paste is always clean.

## Install

```bash
brew install --cask esc5221/tap/claude-clipboard-cleaner
```

Or download the DMG from [Releases](https://github.com/esc5221/claude-clipboard-cleaner/releases).

## Usage

Launch the app — it sits in your menu bar as **⌘C**. That's it.

- Clipboard is monitored automatically (0.3s polling)
- Icon flashes **✓** when a clean happens
- Click the menu bar icon for Enable/Disable, Launch at Login, and clean count

## How it works

**Three independent detection paths:**
- **Trailing space padding** — terminal copy pads lines to fixed width with spaces. If 50%+ of lines have ≥3 trailing spaces, it strips them.
- **Leading 2-space pattern** — Claude response text uses consistent 2-space indent. If 60%+ of lines match, it strips the indent.
- **Short input (1-2 lines)** — when there aren't enough lines for the ratio detectors to vote, each non-empty content line must carry BOTH leading 2-space AND ≥3 trailing spaces to be treated as a terminal-copy fragment. For two-line input, the unwrap step decides whether the second line is a wrap continuation of the first (joined) or an intentional break (kept separate).

After stripping, terminal-wrapped paragraphs are stitched back together: a line is joined to the previous one when word-fit math says the terminal had no choice but to break, or when the line's leading whitespace is deeper than the document's indent baseline (a hanging-indent continuation). An indent reset back to baseline forces a paragraph break.

## Build from source

```bash
git clone https://github.com/esc5221/claude-clipboard-cleaner.git
cd claude-clipboard-cleaner
./build.sh
open "build/Claude Clipboard Cleaner.app"
```

## Test

```bash
./test.sh
```

## Requirements

- macOS 13.0+ (Ventura)
- Apple Silicon (arm64)

## License

MIT
