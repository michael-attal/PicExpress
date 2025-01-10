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

    // Used to add a polygon directly from a view.
    var mainRenderer: MainMetalRenderer?
}
