import XCTest
@testable import Learning

final class LoginModelsTests: XCTestCase {
    func testLoginSuccessDecoding() throws {
        let json = """
        {"token":"abc.def.ghi","status":"success"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)
        XCTAssertTrue(response.isSuccess)
        XCTAssertEqual(response.token, "abc.def.ghi")
    }

    func testLoginFailureDecoding() throws {
        let json = """
        {"status":"error","message":"Authentication failed"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)
        XCTAssertFalse(response.isSuccess)
        XCTAssertEqual(response.message, "Authentication failed")
    }

    func testCloudRecordingsEmptyDecoding() throws {
        let json = """
        {"success":true,"message":"RECORDINGS_FOR_SUB_HOST","data":[]}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CloudRecordingsResponse.self, from: json)
        XCTAssertEqual(response.data?.count, 0)
        XCTAssertEqual(response.message, "RECORDINGS_FOR_SUB_HOST")
    }
}
