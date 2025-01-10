//
//  EditingContentView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftData
import SwiftUI

struct EditingContentView: View {
    /// The document being edited
    @Bindable var document: PicExpressDocument
    
    @State private var isEditingDocumentName = false
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Metal canvas zone --
            // RotationMetalCanvasTestView(contentMode: .fit)
            MetalCanvasView()
        }
        .navigationTitle(document.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Édition du document : \(document.name)")
                                .font(.title3)
                            if !isEditingDocumentName {
                                Text("Date : \(document.timestamp, style: .date) - \(document.timestamp, style: .time)")
                                    .foregroundColor(.secondary)
                            }
                        }
                            
                        Spacer()
                            
                        Button {
                            isEditingDocumentName.toggle()
                        } label: {
                            Text(isEditingDocumentName ? "Done" : "Edit")
                        }
                        .padding(.leading, 8)
                    }
                        
                    if isEditingDocumentName {
                        TextField("Nom du document", text: $document.name)
                            .padding(0)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }
        }
    }
}
