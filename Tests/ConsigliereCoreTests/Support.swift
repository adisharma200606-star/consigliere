import Foundation
import XCTest
@testable import ConsigliereCore

/// Hands the code an explicit list of "random" numbers, so Swift consumes exactly the values the
/// JavaScript reference consumed when it wrote the golden fixtures.
final class ScriptedRandom {
    private let values: [Double]
    private(set) var used = 0

    init(_ values: [Double]) {
        self.values = values
    }

    func next() -> Double {
        precondition(used < values.count, "scripted random ran out of values")
        let value = values[used]
        used += 1
        return value
    }
}

enum Fixtures {
    /// <repo>/fixtures, found relative to this source file so it works from Xcode and from `swift test`.
    static var directory: URL {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ConsigliereCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("fixtures", isDirectory: true)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let url = directory.appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("consigliere-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
