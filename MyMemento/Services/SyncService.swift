//
//  SyncService.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/22/25.
//

import Foundation
import CoreData

final class SyncService {
    static let shared = SyncService()

    private init() {}

    // Placeholder: upload notes to server
    func upload(notes: [Note]) {
        // TODO: implement sync later
        print("Pretend uploading \(notes.count) notes")
    }

    // Placeholder: download notes from server
    func download() -> [Note] {
        // TODO: implement sync later
        print("Pretend downloading notes")
        return []
    }

    // Placeholder: trigger full sync
    func syncAll(context: NSManagedObjectContext) {
        print("Pretend syncing all notes with server")
    }
}
