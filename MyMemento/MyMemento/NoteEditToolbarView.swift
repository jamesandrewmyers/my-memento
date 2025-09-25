import SwiftUI

struct NoteEditToolbarView: View {
    var note: Note?
    var onCancel: () -> Void
    var onTogglePin: () -> Void
    var onExportHTML: () -> Void
    var onExportLocalKey: () -> Void
    var onExportEncrypted: () -> Void
    var onSave: () -> Void
    
    @State private var showSettings = false
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 44)
            .overlay(
                GeometryReader { geometry in
                    // Left group - Cancel button
                    Button(action: onCancel) {
                        Text("Cancel")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 60, height: 30)
                    .offset(x: 16, y: 7)
                    
                    // Center - Settings button
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 30, height: 30)
                    .offset(x: (geometry.size.width / 2) - 15, y: 7)
                    
                    // Right group - Pin, Export Menu, Save
                    Button(action: onTogglePin) {
                        Image(systemName: note?.isPinned == true ? "pin.slash" : "pin")
                            .foregroundColor(note?.isPinned == true ? .orange : .gray)
                    }
                    .frame(width: 30, height: 30)
                    .offset(x: geometry.size.width - 146, y: 7)
                    
                    Menu {
                        Button(action: onExportHTML) {
                            Label("Export as HTML", systemImage: "doc.text")
                        }
                        Button(action: onExportLocalKey) {
                            Label("Export (Local Key)", systemImage: "lock.app.dashed")
                        }
                        Button(action: onExportEncrypted) {
                            Label("Encrypted Export", systemImage: "lock.doc")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 30, height: 30)
                    .offset(x: geometry.size.width - 112, y: 7)
                    
                    Button(action: onSave) {
                        Text("Save")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 50, height: 30)
                    .offset(x: geometry.size.width - 66, y: 7)
                }
            )
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
    }
}