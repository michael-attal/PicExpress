//
//  ToolsPanelView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftUI

/// Represents a tool in the panel
struct Tool: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let systemImage: String
}

/// Side panel: tool list
struct ToolsPanelView: View {
    let tools: [Tool]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outils")
                .font(.headline)

            ForEach(tools) { tool in
                Button(action: {
                    print("Do \(tool.name)")
                }) {
                    HStack {
                        Image(systemName: tool.systemImage)
                        Text(tool.name)
                        Spacer()
                    }.frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }
}
