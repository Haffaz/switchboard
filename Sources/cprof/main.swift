import Foundation

do {
    try await CLI().run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("cprof: \(error.localizedDescription)\n".utf8))
    exit(1)
}
