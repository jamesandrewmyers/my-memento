
//
//  SortOptionsView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 9/11/25.
//

import SwiftUI

struct SortOptionsView: View {
    @Binding var sortOption: SortOption

    var body: some View {
        HStack {
            Text("Sort by:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(SortOption.allCases, id: \.self) { option in
                Button(action: { sortOption = option }) {
                    Text(option.rawValue.lowercased())
                        .font(.subheadline)
                        .foregroundColor(sortOption == option ? .blue : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
