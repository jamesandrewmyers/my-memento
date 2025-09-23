import SwiftUI

struct CustomToolbarView: View {
    @Binding var showTagList: Bool
    @Binding var showLocationManagement: Bool
    @Binding var showImportPicker: Bool
    @Binding var showExportDialog: Bool
    
    var isImporting: Bool
    var isExporting: Bool
    
    var onAddNote: () -> Void
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 44)
            .overlay(
                GeometryReader { geometry in
                    // Left group - exact positioning
                    Button(action: { showTagList = true }) {
                        Image(systemName: "tag")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 30, height: 30)
                    .offset(x: 16, y: 7)
                    
                    Button(action: { showLocationManagement = true }) {
                        Image(systemName: "location")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 30, height: 30)
                    .offset(x: 50, y: 7)
                    
                    // Center - positioned at exact screen center
                    SettingsButton()
                        .offset(x: (geometry.size.width / 2) - 15, y: 7)
                    
                    // Right group - exact positioning from right edge
                    Button(action: { showImportPicker = true }) {
                        if isImporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .disabled(isExporting || isImporting)
                    .offset(x: geometry.size.width - 114, y: 7)
                    
                    Button(action: { showExportDialog = true }) {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.primary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .disabled(isExporting || isImporting)
                    .offset(x: geometry.size.width - 80, y: 7)
                    
                    Button(action: onAddNote) {
                        Image(systemName: "plus")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 30, height: 30)
                    .disabled(isExporting || isImporting)
                    .offset(x: geometry.size.width - 46, y: 7)
                }
            )
    }
}