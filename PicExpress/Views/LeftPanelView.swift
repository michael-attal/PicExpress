//
//  LeftPanelView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftUI

struct LeftPanelView: View {
    /// List of documents retrieved via SwiftData
    let documents: [PicExpressDocument]
    
    @Binding var selectedDocument: PicExpressDocument?
    
    let onAddDocument: () -> Void
    let onDeleteDocument: (PicExpressDocument) -> Void
    
    /// List of tools to display
    let tools: [Tool]
    
    // A closure that is called with new polygon points and color
    let onPolygonPoints: ([ECTPoint], Color) -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            // SECTION 1 : list of docs
            List(selection: $selectedDocument) {
                Section("Mes documents") {
                    ForEach(documents) { doc in
                        HStack {
                            Text(doc.name)
                            Spacer()
                            
                            Button {
                                withAnimation {
                                    onDeleteDocument(doc)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }
                        .tag(doc)
                    }
                }
            }
            
            Button {
                onAddDocument()
            } label: {
                Label("Nouveau document", systemImage: "plus")
            }
            .padding(.horizontal)
            .buttonStyle(.borderedProminent)
            
            Divider()
            
            // SECTION 2 : Tools panel
            ToolsPanelView(tools: tools, onPolygonPoints: onPolygonPoints)
                .padding(.top, 8)
            
            Spacer()
        }
    }
}
