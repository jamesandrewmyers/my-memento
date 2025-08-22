//
//  DebugConfig.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/22/25.
//

import Foundation

/// Global debug configuration for the application
struct DebugConfig {
    /// Global debug mode flag - set to true to enable debugging features throughout the app
    /// This can be used to conditionally execute debug-only code, logging, or UI elements
    /// 
    /// Usage example:
    /// ```swift
    /// if DEBUG_MODE {
    ///     print("Debug: performing additional logging")
    /// }
    /// ```
    static let DEBUG_MODE: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}

/// Global convenience constant for easy access to debug mode
/// This allows using `DEBUG_MODE` directly without prefixing with `DebugConfig.`
let DEBUG_MODE = DebugConfig.DEBUG_MODE