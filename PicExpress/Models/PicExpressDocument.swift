//
//  PicExpressDocument.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import Foundation
import SwiftData

@Model
final class PicExpressDocument {
    /// Document or project name
    var name: String

    /// Date created or last modified
    var timestamp: Date

    /// Prepare storage for future data :
    /// For example, a Data file containing an array of vertices in JSON,
    /// or any other format. We're using an optional type for now.
    var verticesData: Data?

    // MARK: - Init

    init(name: String, timestamp: Date = Date(), verticesData: Data? = nil) {
        self.name = name
        self.timestamp = timestamp
        self.verticesData = verticesData
    }
}
