import XCTest
@testable import NuvioTV

final class URLValidatorTests: XCTestCase {
    func testValidatesHTTPSURL() throws {
        let url = try URLValidator.validatedURL(from: " https://example.com/master.m3u8 ")

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host(), "example.com")
    }

    func testRejectsEmptyURL() {
        XCTAssertThrowsError(try URLValidator.validatedURL(from: "  ")) { error in
            XCTAssertEqual(error as? URLValidationError, .empty)
        }
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try URLValidator.validatedURL(from: "ftp://example.com/file.mp4")) { error in
            XCTAssertEqual(error as? URLValidationError, .unsupportedScheme)
        }
    }

    func testHostedBackendConfigIsUsable() {
        XCTAssertTrue(NuvioBackendConfig.hosted.normalizedSupabaseURL.hasPrefix("https://"))
        XCTAssertEqual(NuvioBackendConfig.hosted.anonKey, "")
        XCTAssertEqual(NuvioBackendConfig.hostedEnvironmentURL.host(), "web.nuvioapp.space")
        XCTAssertTrue(NuvioBackendConfig.hosted.tvLoginRedirectBaseURL.hasPrefix("https://"))
    }
}
