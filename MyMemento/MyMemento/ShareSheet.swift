
//
//  ShareSheet.swift
//  MyMemento
//
//  Created by James Andrew Myers on 9/11/25.
//

import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var itemsToShare: [Any] = []
        
        for item in activityItems {
            if let fileURL = item as? URL {
                let provider = NSItemProvider(contentsOf: fileURL)!
                provider.registerFileRepresentation(forTypeIdentifier: "app.jam.ios.memento",
                                                  fileOptions: [],
                                                  visibility: .all) { completion in
                    completion(fileURL, true, nil)
                    return nil
                }
                itemsToShare.append(provider)
            } else {
                itemsToShare.append(item)
            }
        }
        
        let controller = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
