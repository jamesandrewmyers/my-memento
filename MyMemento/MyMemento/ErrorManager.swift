//
//  ErrorManager.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/22/25.
//

import Foundation
import SwiftUI
import CoreData
import OSLog

class ErrorManager: ObservableObject {
    static let shared = ErrorManager()
    
    @Published var showError = false
    @Published var errorMessage = ""
    
    private let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "ErrorManager")
    
    private init() {}
    
    func handleError(_ error: Error, context: String = "") {
        let errorDescription = "\(context.isEmpty ? "" : "\(context): ")\(error.localizedDescription)"
        
        // Log the error
        logger.error("\(errorDescription)")
        
        // Update UI state
        DispatchQueue.main.async {
            self.errorMessage = errorDescription
            self.showError = true
        }
    }
    
    func handleCoreDataError(_ error: NSError, context: String = "") {
        let errorDescription = "\(context.isEmpty ? "" : "\(context): ")Core Data error: \(error.localizedDescription)"
        
        // Log detailed Core Data error
        logger.error("\(errorDescription) - Code: \(error.code), UserInfo: \(String(describing: error.userInfo))")
        
        // Provide user-friendly message
        let userMessage = getUserFriendlyMessage(for: error, context: context)
        
        DispatchQueue.main.async {
            self.errorMessage = userMessage
            self.showError = true
        }
    }
    
    private func getUserFriendlyMessage(for error: NSError, context: String) -> String {
        switch error.code {
        case NSValidationMultipleErrorsError:
            return "There was a problem validating your note. Please check the content and try again."
        case NSValidationMissingMandatoryPropertyError:
            return "Required information is missing. Please fill in all required fields."
        case NSManagedObjectValidationError:
            return "There was a problem with the note data. Please try again."
        case NSPersistentStoreSaveError:
            return "Failed to save your note. Please try again."
        default:
            return context.isEmpty ? "An unexpected error occurred. Please try again." : "\(context): An unexpected error occurred. Please try again."
        }
    }
}