import XCTest
@testable import AINewsBar

final class AIErrorMappingTests: XCTestCase {
    func testHTTP401And403MapToInvalidAPIKey() {
        XCTAssertEqual(
            GlobalAIError.from(BailianError.httpStatus(code: 401, bodySnippet: "")),
            .invalidAPIKey
        )
        XCTAssertEqual(
            GlobalAIError.from(BailianError.httpStatus(code: 403, bodySnippet: "")),
            .invalidAPIKey
        )
    }

    func testHTTP429MapsToQuotaExceeded() {
        XCTAssertEqual(
            GlobalAIError.from(BailianError.httpStatus(code: 429, bodySnippet: "")),
            .quotaExceeded
        )
    }

    func testNetworkErrorsMapToNetworkUnreachable() {
        XCTAssertEqual(GlobalAIError.from(URLError(.timedOut)), .networkUnreachable)
        XCTAssertEqual(GlobalAIError.from(URLError(.notConnectedToInternet)), .networkUnreachable)
    }

    func testMalformedResponseIsNotGlobal() {
        XCTAssertNil(GlobalAIError.from(BailianError.malformedResponse(reason: "bad json")))
    }
}
