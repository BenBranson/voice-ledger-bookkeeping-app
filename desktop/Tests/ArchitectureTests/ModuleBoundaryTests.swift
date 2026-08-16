import Testing
import Foundation

/// T0 structural test (docs/phase-0/12_TEST_STRATEGY.md §12.2, item 1):
/// "/core imports nothing from /integrations — source-level scan."
///
/// Runs the shell script rather than reimplementing the scan in Swift, so
/// there is exactly one place this rule lives and it's readable without
/// Swift tooling.
@Test("Core has zero dependencies on Integrations/Staging/Voice/DB")
func coreImportsNothingForbidden() throws {
    let scriptPath = try locateScript(named: "check-module-boundaries.sh")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["bash", scriptPath]

    let stderrPipe = Pipe()
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

    #expect(
        process.terminationStatus == 0,
        "Module boundary violation:\n\(stderrText)"
    )
}

/// Locates a script under desktop/Scripts relative to this test file's own
/// location (#filePath), rather than assuming a working directory — `swift
/// test` and Xcode's test runner don't agree on cwd.
func locateScript(named name: String) throws -> String {
    let thisFile = URL(fileURLWithPath: #filePath)
    // Tests/ArchitectureTests/ModuleBoundaryTests.swift -> desktop/
    let desktopRoot = thisFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = desktopRoot.appendingPathComponent("Scripts").appendingPathComponent(name)

    guard FileManager.default.fileExists(atPath: scriptURL.path) else {
        struct ScriptNotFound: Error, CustomStringConvertible {
            let path: String
            var description: String { "Script not found at \(path)" }
        }
        throw ScriptNotFound(path: scriptURL.path)
    }
    return scriptURL.path
}
