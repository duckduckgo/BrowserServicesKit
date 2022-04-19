import Foundation

import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DDGSyncAuthTests.allTests)
    ]
}
#endif
