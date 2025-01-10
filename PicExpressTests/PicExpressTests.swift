//
//  PicExpressTests.swift
//  PicExpressTests
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import Foundation
@testable import PicExpress
import Testing

struct PicExpressTests {
    @Test func testDocumentName() async throws {
        let doc = PicExpressDocument(name: "TestDoc")
        #expect(doc.name == "TestDoc")
    }

    @Test func testDocumentTimestamp() async throws {
        let doc = PicExpressDocument(name: "TestDoc")
        // Dumb test: Check that the date is not too old
        let now = Date()
        #expect(doc.timestamp.timeIntervalSince1970 <= now.timeIntervalSince1970 + 1.0)
    }

    // TODO: Others tests
}
