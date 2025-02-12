//
//  PolygonToolView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import simd
import SwiftUI

/// Some x, y polygon coordinate point samples that work fine:
/// Triangle: 0.0,0.5;-0.5,-0.2;0.5,-0.2
/// Another right triangle: 0.8,0.2;  0.5,-0.2;  1.0,-0.2
/// Square: -0.2,0.2; 0.2,0.2; 0.2,-0.2; -0.2,-0.2
/// Bigger square: -0.5,0.5; 0.5,0.5; 0.5,-0.5; -0.5,-0.5
/// Star: 0.0,0.3;  -0.1,0.0; -0.3,0.0;  -0.15,-0.15; -0.2,-0.4; 0.0,-0.25; 0.2,-0.4; 0.15,-0.15; 0.3,0.0; 0.1,0.0
struct PolygonToolView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var rawPoints: String = ""
    @State private var selectedColor: Color = .green

    let onApplyPoints: ([ECTPoint], Color) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Création de Polygone")
                .font(.headline)
            
            Text("Saisissez des points sous forme de paires x,y séparées par des points-virgules :")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextField("ex: 0.0,0.5;-0.5,-0.2;0.5,-0.2", text: $rawPoints)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            VStack {
                Text("Couleur du polygone :")
                ColorPicker("", selection: $selectedColor, supportsOpacity: true)
                    .frame(width: 50, height: 25)
                    .labelsHidden()
            }
            .padding(.horizontal)

            HStack {
                Spacer()
                Button("Annuler") {
                    dismiss()
                }
                .padding(.trailing)
                
                Button("Appliquer") {
                    print("Apply Création de Polygone with points: \(rawPoints)")
                    let points = parsePoints(from: rawPoints)
                    onApplyPoints(points, selectedColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .padding(.top, 20)
    }
    
    private func parsePoints(from text: String) -> [ECTPoint] {
        let pairs = text.split(separator: ";")
        var result: [ECTPoint] = []
        for pair in pairs {
            let xy = pair.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if xy.count == 2,
               let xVal = Double(xy[0]),
               let yVal = Double(xy[1])
            {
                result.append(ECTPoint(x: xVal, y: yVal))
            }
        }
        return result
    }
}

#Preview {
    PolygonToolView { points, color in
        print("Preview got \(points.count) points with color \(color)")
    }
}
