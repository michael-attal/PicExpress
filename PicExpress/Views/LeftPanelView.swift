//
//  LeftPanelView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftUI

struct LeftPanelView: View {
    @Environment(AppState.self) private var appState

    /// List of documents retrieved via SwiftData
    let documents: [PicExpressDocument]
    
    @Binding var selectedDocument: PicExpressDocument?
    
    /// Called when user wants to create a new doc
    /// We pass (docName, width, height)
    let onAddDocument: (String, Int, Int) -> Void
    let onDeleteDocument: (PicExpressDocument) -> Void
    
    /// Tools
    let tools: [AvailableTool]
    
    /// When the user manually enters polygon points
    let onPolygonPoints: ([ECTPoint], Color) -> Void
    
    @State private var showNewDocSheet = false
    
    var body: some View {
        VStack(alignment: .leading) {
            // SECTION 1 : list of docs
            List(selection: $selectedDocument) {
                Section("Mes documents") {
                    ForEach(documents.sorted(by: { $0.createdAt > $1.createdAt })) { doc in
                        HStack {
                            Text(doc.name)
                            Spacer()
                            
                            Button {
                                withAnimation {
                                    if appState.selectedDocument == doc {
                                        appState.isDocumentOpen = false
                                        appState.selectedDocument = nil
                                    }
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
            .onChange(of: selectedDocument) {
                if let doc = selectedDocument {
                    appState.selectedDocument = doc
                    appState.isDocumentOpen = true
                    print("New document selected: \(doc.name)")
                }
            }
            
            Button {
                showNewDocSheet = true
            } label: {
                Label("Nouveau document", systemImage: "plus")
            }
            .padding(.horizontal)
            .buttonStyle(.borderedProminent)
            .sheet(isPresented: $showNewDocSheet) {
                // The sheet for new doc creation
                NewDocumentSheet { docName, w, h in
                    onAddDocument(docName, w, h)
                }
            }
            
            // SECTION 2 : Tools if doc is open
            if appState.isDocumentOpen {
                Divider()
                ToolsPanelView(onPolygonPoints: onPolygonPoints, tools: tools)
                    .padding(.top, 8)
            }
            
            Spacer()
        }
    }
}
