//
//  MyMementoApp.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/21/25.
//

import SwiftUI

@main
struct MyMementoApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
