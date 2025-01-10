//
//  RotationTestView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftUI

struct RotationMetalCanvasTestView: View {
    @State private var rotation: Float = 0.0
    var contentMode: ContentMode = .fit
    
    var body: some View {
        VStack {
            Spacer()
            MetalRotationViewTest(rotation: $rotation).aspectRatio(1, contentMode: contentMode)
            Spacer()

            Text("Rotation")
            HStack {
                Text("-π")
                Slider(value: $rotation, in: -(.pi) ... .pi)
                Text("π")
            }
            Spacer()

            Button("Reset") {
                rotation = 0.0
            }
        }
    }
}
