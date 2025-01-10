//
//  MetalCanvasView.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit
import SwiftUI

struct MetalCanvasView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        // 1. Instantiates the Metal view
        let mtkView = MTKView(frame: .zero)
        
        // 2. Initializes default device
        mtkView.device = MTLCreateSystemDefaultDevice()
        
        // 3. Background color (black)
        mtkView.clearColor = MTLClearColorMake(0, 0, 0, 1)
        
        // 4. Create the renderer and assign it as a delegate
        let renderer = MetalRenderer(mtkView: mtkView)
        mtkView.delegate = renderer
        
        // 5. Stores the renderer in the Coordinator
        context.coordinator.renderer = renderer
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // Handle update later here
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        // We keep a strong reference here, otherwise the renderer will be freed.
        var renderer: MetalRenderer?
    }
}
