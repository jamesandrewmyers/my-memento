import SwiftUI

struct LocationDetailToolbarView: View {
    var onCancel: () -> Void
    var onSelect: () -> Void
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 44)
            .overlay(
                GeometryReader { geometry in
                    // Left - Cancel button
                    Button(action: onCancel) {
                        Text("Cancel")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 60, height: 30)
                    .offset(x: 16, y: 7)
                    
                    // Center - Settings button
                    SettingsButton()
                        .offset(x: (geometry.size.width / 2) - 15, y: 7)
                    
                    // Right - Select button
                    Button(action: onSelect) {
                        Text("Select")
                            .foregroundColor(.primary)
                    }
                    .frame(width: 60, height: 30)
                    .offset(x: geometry.size.width - 76, y: 7)
                }
            )
    }
}

#Preview {
    LocationDetailToolbarView(
        onCancel: {},
        onSelect: {}
    )
}