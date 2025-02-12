//
//  NewDocumentSheet.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 09/02/2025.
//

import SwiftUI

/// This view is shown in a sheet when the user clicks "Nouveau document".
/// It allows entering the document name, width, and height in pixels.
struct NewDocumentSheet: View {
    @Environment(\.dismiss) var dismiss

    @State private var docName: String = "Nouveau Document"
    @State private var width: Int = 512
    @State private var height: Int = 512

    /// Called when user confirms creation. We'll pass (name, w, h).
    let onCreate: (String, Int, Int) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Nouveau document")
                .font(.title2)

            TextField("Nom du document", text: $docName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Largeur:")
                TextField("512", value: $width, format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Hauteur:")
                TextField("512", value: $height, format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Annuler") {
                    dismiss()
                }
                Button("Créer") {
                    onCreate(docName, width, height)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
