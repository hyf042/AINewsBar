import XCTest
@testable import AINewsBar

final class AIErrorMappingTests: XCTestCase {
    func testHTTP401MapsToInvalidAPIKey() {
        XCTAssertEqual(
            GlobalAIError.from(BailianError.httpStatus(code: 401, bodySnippet: "")),
            .invalidAPIKey
        )
    }

    // H4: 403 不再一锅炖映射为 invalidAPIKey；403 常见是"key 有效但模型未授权"
    func testHTTP403MapsToForbidden() {
        XCTAssertEqual(
            GlobalAIError.from(BailianError.httpStatus(code: 403, bodySnippet: "")),
            .forbidden
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
