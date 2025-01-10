//
//  MetalRendererRotationTest.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import MetalKit

class MetalRendererRotationTest: NSObject, MTKViewDelegate {
    let vertexBuffer: MTLBuffer
    let pipelineState: MTLRenderPipelineState
    let commandQueue: MTLCommandQueue
    let device: MTLDevice

    let vertices: [MetalRotationVertexStructureForTriangleTest] = [
        MetalRotationVertexStructureForTriangleTest(position3D: [0, 1, 0], colorRGB: [0, 0, 1]),
        MetalRotationVertexStructureForTriangleTest(position3D: [-1, -1, 0], colorRGB: [1, 1, 1]),
        MetalRotationVertexStructureForTriangleTest(position3D: [1, -1, 0], colorRGB: [1, 0, 0])
    ]

    private var rotationMatrix = matrix_identity_float4x4

    override init() {
        device = MetalRendererRotationTest.createMetalDevice()
        commandQueue = MetalRendererRotationTest.createCommandQueue(with: device)
        vertexBuffer = MetalRendererRotationTest.createVertexBuffer(for: device, containing: vertices)

        let descriptor = MetalRotationVertexStructureForTriangleTest.buildDefaultVertexDescriptor()
        let library = MetalRendererRotationTest.createDefaultMetalLibrary(with: device)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_rotation_test")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_rotation_test")
        pipelineDescriptor.vertexDescriptor = descriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipelineState = MetalRendererRotationTest.createPipelineState(with: device, from: pipelineDescriptor)

        super.init()
    }

    func updateRotation(angle: Float) {
        rotationMatrix = float4x4(rotationZ: angle)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        if let drawable = view.currentDrawable,
           let renderPassDescriptor = view.currentRenderPassDescriptor
        {
            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            else {
                fatalError("Could not set up objects for render encoding")
            }

            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&rotationMatrix, length: MemoryLayout<simd_float4x4>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            renderEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    private static func createMetalDevice() -> MTLDevice {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("No GPU")
        }

        return defaultDevice
    }

    private static func createCommandQueue(with device: MTLDevice) -> MTLCommandQueue {
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create the command queue")
        }

        return commandQueue
    }

    private static func createVertexBuffer(for device: MTLDevice, containing data: [MetalRotationVertexStructureForTriangleTest]) -> MTLBuffer {
        guard let buffer = device.makeBuffer(bytes: data,
                                             length: MemoryLayout<MetalRotationVertexStructureForTriangleTest>.stride * data.count,
                                             options: [])
        else {
            fatalError("Could not create the vertex buffer")
        }

        return buffer
    }

    private static func createDefaultMetalLibrary(with device: MTLDevice) -> MTLLibrary {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("No .metal files in the Xcode project")
        }

        return library
    }

    private static func createPipelineState(with device: MTLDevice, from descriptor: MTLRenderPipelineDescriptor) -> MTLRenderPipelineState {
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Could not create the pipeline state: \(error.localizedDescription)")
        }
    }
}
