// Minimal CLI: reads stdin, prints the cleaner's output (or "[NOT DETECTED]"
// followed by the original on stderr). Useful for reproducing clipboard
// contents without going through the menubar app.
//
// Usage:
//   echo "  hello                              " | ./build/clean_string
//   pbpaste | ./build/clean_string
//
// Build:
//   cat CleanLogic.swift scripts/clean_string.swift > build/clean_string_main.swift
//   swiftc -O -target arm64-apple-macosx13.0 -o build/clean_string build/clean_string_main.swift

import Foundation

let raw = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
if let cleaned = cleanClaudeOutput(raw) {
    print(cleaned)
} else {
    FileHandle.standardError.write("[NOT DETECTED — pass-through]\n".data(using: .utf8)!)
    print(raw, terminator: "")
}
