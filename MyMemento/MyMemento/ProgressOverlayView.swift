
//
//  ProgressOverlayView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 9/11/25.
//

import SwiftUI

struct ProgressOverlayView: View {
    @Binding var isExporting: Bool
    @Binding var isImporting: Bool
    @Binding var exportProgress: Double
    @Binding var importProgress: Double
    @Binding var exportStatusMessage: String
    @Binding var importStatusMessage: String

    var body: some View {
        if isExporting || isImporting {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView(value: isExporting ? exportProgress : importProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 200)
                    
                    Text(isExporting ? exportStatusMessage : importStatusMessage)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("\(Int((isExporting ? exportProgress : importProgress) * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(30)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 10)
            }
        }
    }
}
