import XCTest
@testable import Odysseus

final class MultipartFormTests: XCTestCase {

    func testFieldAppearsInBody() {
        let form = MultipartForm(fields: ["name": "hello"])
        let body = String(data: form.finalizedData, encoding: .utf8)!
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"name\""))
        XCTAssertTrue(body.contains("hello"))
    }

    func testFinalizedBodyEndsWithClosingBoundary() {
        let form = MultipartForm(fields: ["a": "b"])
        let body = String(data: form.finalizedData, encoding: .utf8)!
        XCTAssertTrue(body.hasSuffix("--\(form.boundary)--\r\n"))
    }

    func testContentTypeCarriesBoundary() {
        let form = MultipartForm()
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=\(form.boundary)")
    }

    /// CR/LF/quotes in a name or filename must never reach the part headers
    /// (header smuggling / extra-part injection).
    func testHeaderSmugglingIsStripped() {
        var form = MultipartForm()
        form.append(field: "evil\r\nContent-Disposition: form-data; name=\"x\"", value: "v")
        form.append(file: "f", filename: "a\"; filename=\"b\r\n.png", mime: "image/png\r\nX-Bad: 1", fileData: Data([0x1]))
        let body = String(data: form.finalizedData, encoding: .utf8)!
        // Injected CRLFs die, so nothing can start a new header line. The letters
        // may survive inline (harmless without CRLF).
        XCTAssertFalse(body.contains("evil\r\nContent-Disposition"))
        XCTAssertFalse(body.contains("\r\nX-Bad"))
        XCTAssertFalse(body.contains("filename=\"b"))
    }

    func testFileDataRoundTrips() {
        var form = MultipartForm()
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        form.append(file: "files", filename: "x.bin", mime: "application/octet-stream", fileData: payload)
        XCTAssertNotNil(form.finalizedData.range(of: payload))
    }
}
