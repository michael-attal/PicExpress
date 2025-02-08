//
//  AppState.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import Foundation
import SwiftUI

@Observable
@MainActor final class AppState: Sendable {
    static let isDevelopmentMode = false
    static let isDebugMode = false

    var mainRenderer: MainMetalRenderer?

    var isClickPolygonMode: Bool = false

    var selectedColor: Color = .yellow
    
    var isDocumentOpen: Bool = false
    var selectedDocument: PicExpressDocument?
}
