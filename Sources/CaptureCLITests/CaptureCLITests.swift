import XCTest
@testable import CaptureCLI

final class CaptureCLITests: XCTestCase {

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        let capture = CaptureCLI()
        capture.record()
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
