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
    @StateObject private var noteIndexViewModel = NoteIndexViewModel()

    init() {
        AttributedStringTransformer.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(noteIndexViewModel)
                .onAppear {
                    noteIndexViewModel.loadIndex(from: persistenceController.container.viewContext)
                }
        }
    }
}
