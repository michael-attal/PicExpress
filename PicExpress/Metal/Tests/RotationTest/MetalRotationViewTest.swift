//
//  MetalRotationViewTest.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import SwiftUI

struct MetalRotationViewTest {
    @State private var renderer: MetalRendererRotationTest = .init()
    
    @Binding var rotation: Float
    
    private func makeMetalView() -> MTKView {
        let view = MTKView()
        
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        
        view.device = renderer.device
        view.delegate = renderer
        
        return view
    }
    
    private func updateMetalView() {
        renderer.updateRotation(angle: rotation)
    }
}

#if os(visionOS)
extension MetalViewTest: UIViewRepresentable {
    func makeUIView(context: Context) -> some UIView {
        makeMetalView()
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        updateMetalView()
    }
}

#elseif os(macOS)
extension MetalRotationViewTest: NSViewRepresentable {
    func makeNSView(context: Context) -> some NSView {
        makeMetalView()
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        updateMetalView()
    }
}
#endif
