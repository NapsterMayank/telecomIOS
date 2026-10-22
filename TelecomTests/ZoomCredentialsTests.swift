import XCTest
@testable import Learning

final class ZoomCredentialsTests: XCTestCase {
    func testCredentialsMappingFromBase64PlatformResponse() throws {
        let json = """
        {
          "iOS": {
            "StartMeetingParamsWithoutLogin": {
              "meetingNo": "2892047781",
              "zoomAccessToken": "zoom-access-token",
              "displayName": "HOST"
            },
            "ZoomSDKInitParams": {
              "jwtToken": "sdk-jwt-token"
            },
            "userMap": {
              "expiryDate": "2026-08-17",
              "daysLeft": 27,
              "username": "kussu10"
            }
          }
        }
        """
        let encodedResponse = Data(json.utf8).base64EncodedString()

        let response = try ZoomTokenResponse(rawToken: encodedResponse)
        let credentials = try ZoomMeetingCredentials.from(response: response, fallbackUsername: "fallback")

        XCTAssertEqual(credentials.role, .host)
        XCTAssertTrue(credentials.isHost)
        XCTAssertEqual(credentials.jwtOrSDKToken, "sdk-jwt-token")
        XCTAssertEqual(credentials.meetingNumber, "2892047781")
        XCTAssertEqual(credentials.zak, "zoom-access-token")
        XCTAssertEqual(credentials.displayName, "HOST")
        XCTAssertEqual(credentials.expiryDisplay, "2026-08-17")
        XCTAssertEqual(credentials.expiresInDays, 27)
    }

    func testCredentialsMappingFromParticipantJoinResponse() throws {
        let json = """
        {
          "iOS": {
            "JoinMeetingParams": {
              "meetingNo": "2892047781",
              "password": "join-pass",
              "displayName": "honey"
            },
            "ZoomSDKInitParams": {
              "jwtToken": "sdk-jwt-token"
            },
            "userMap": {
              "expiryDate": "2026-08-17",
              "daysLeft": 11,
              "username": "kussu1111"
            }
          }
        }
        """
        let encodedResponse = Data(json.utf8).base64EncodedString()

        let response = try ZoomTokenResponse(rawToken: encodedResponse)
        let credentials = try ZoomMeetingCredentials.from(response: response, fallbackUsername: "fallback")

        XCTAssertEqual(credentials.role, .participant)
        XCTAssertFalse(credentials.isHost)
        XCTAssertEqual(credentials.jwtOrSDKToken, "sdk-jwt-token")
        XCTAssertEqual(credentials.meetingNumber, "2892047781")
        XCTAssertEqual(credentials.password, "join-pass")
        XCTAssertEqual(credentials.displayName, "honey")
        XCTAssertEqual(credentials.bookOwnerName, "kussu1111")
        XCTAssertNil(credentials.zak)
        XCTAssertEqual(credentials.expiresInDays, 11)
        XCTAssertTrue(credentials.hostJoinAvailable)
    }

    func testParticipantBlockedWhenNumberSwitchOffInPayload() throws {
        let json = """
        {
          "iOS": {
            "JoinMeetingParams": {
              "meetingNo": "2892047781",
              "password": "join-pass",
              "displayName": "honey"
            },
            "ZoomSDKInitParams": {
              "jwtToken": "sdk-jwt-token"
            },
            "userMap": {
              "expiryDate": "2026-08-17",
              "daysLeft": 11,
              "username": "kussu1111",
              "switchOff": true
            }
          }
        }
        """
        let encodedResponse = Data(json.utf8).base64EncodedString()

        let response = try ZoomTokenResponse(rawToken: encodedResponse)
        let credentials = try ZoomMeetingCredentials.from(response: response, fallbackUsername: "fallback")

        XCTAssertFalse(credentials.hostJoinAvailable)
    }

    func testProfileImageURLParsedFromUserMap() throws {
        let json = """
        {
          "iOS": {
            "JoinMeetingParams": {
              "meetingNo": "2892047781",
              "displayName": "honey"
            },
            "ZoomSDKInitParams": {
              "jwtToken": "sdk-jwt-token"
            },
            "userMap": {
              "username": "kussu1111",
              "profile": "https://telecom.ac/api/files/65977ead-d09c-45ab.jpg"
            }
          }
        }
        """
        let encodedResponse = Data(json.utf8).base64EncodedString()

        let response = try ZoomTokenResponse(rawToken: encodedResponse)
        let credentials = try ZoomMeetingCredentials.from(response: response, fallbackUsername: "fallback")

        XCTAssertEqual(
            credentials.profileImageURL?.absoluteString,
            "https://telecom.ac/api/files/65977ead-d09c-45ab.jpg"
        )
    }

    func testCredentialsMappingFromNestedData() throws {
        let json = """
        {
          "success": true,
          "data": {
            "token": "sdk-jwt-token",
            "meetingNumber": "123456789",
            "password": "abcd",
            "userName": "shost",
            "expiry": "2026-08-17",
            "expiresInDays": 28
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ZoomTokenResponse.self, from: json)
        let credentials = try ZoomMeetingCredentials.from(response: response, fallbackUsername: "fallback")

        XCTAssertEqual(credentials.jwtOrSDKToken, "sdk-jwt-token")
        XCTAssertEqual(credentials.meetingNumber, "123456789")
        XCTAssertEqual(credentials.password, "abcd")
        XCTAssertEqual(credentials.displayName, "shost")
        XCTAssertEqual(credentials.expiresInDays, 28)
        XCTAssertEqual(credentials.expiryDisplay, "2026-08-17")
    }
}
