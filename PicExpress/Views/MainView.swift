//
//  MainView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftData
import SwiftUI

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    
    /// Retrieve all stored documents from SwiftData
    @Query private var documents: [PicExpressDocument]
    
    /// Document currently selected (from list)
    @State private var selectedDocument: PicExpressDocument?

    /// Basic startup tools (edit later from required tools of syllabus)
    private let tools: [Tool] = [
        Tool(name: "Pinceau", systemImage: "paintbrush"),
        Tool(name: "Gomme", systemImage: "eraser"),
        Tool(name: "Texte", systemImage: "textformat"),
        Tool(name: "Formes", systemImage: "square.on.circle"),
        Tool(name: "Recadrage", systemImage: "crop"),
    ]
    
    var body: some View {
        NavigationSplitView {
            LeftPanelView(
                documents: documents,
                selectedDocument: $selectedDocument,
                onAddDocument: addDocument,
                onDeleteDocument: deleteDocument,
                tools: tools
            )
            .navigationTitle("PicExpress")
            .navigationSplitViewColumnWidth(min: 10, ideal: 120, max: 200)
            
        } detail: {
            if let doc = selectedDocument {
                EditingContentView(document: doc)
            } else {
                Text("Sélectionnez un document ou créez-en un nouveau.")
                    .foregroundColor(.secondary)
                    .navigationTitle("Aucun document sélectionné")
            }
        }
    }
    
    // MARK: - Actions
    
    private func addDocument() {
        withAnimation {
            let newDoc = PicExpressDocument(name: "Nouveau Document")
            modelContext.insert(newDoc)
            selectedDocument = newDoc
        }
    }
    
    private func deleteDocument(_ doc: PicExpressDocument) {
        if doc == selectedDocument {
            selectedDocument = nil
        }
        
        withAnimation {
            modelContext.delete(doc)
        }
    }
}

struct LeftPanelView: View {
    /// List of documents retrieved via SwiftData
    let documents: [PicExpressDocument]
    
    @Binding var selectedDocument: PicExpressDocument?
    
    let onAddDocument: () -> Void
    
    let onDeleteDocument: (PicExpressDocument) -> Void
    
    /// List of tools to display
    let tools: [Tool]
    
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
                        .tag(doc) // Tells SwiftUI that this line represents the doc
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
            ToolsPanelView(tools: tools)
                .padding(.top, 8)
            
            Spacer()
        }
    }
}

#Preview {
    MainView()
        .modelContainer(for: PicExpressDocument.self, inMemory: true)
}
