//
//  Renderer.swift
//  HelloMetal001
//
//  Created by Yoshiki Izumi on 2019/12/28.
//  Copyright © 2019 Yoshiki Izumi. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: [MTLBuffer] = []
    var pipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
    var uniformBufferOffset = 0
    
    var uniformBufferIndex = 0
    
    var uniforms: [UnsafeMutablePointer<Uniforms>] = []

    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    
    var rotation: Float = 0
        
    var plane1: [Plane] = []

    var vertex1Buffer :[MTLBuffer] = []
    var texCoord1Buffer: [MTLBuffer] = []

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        
        var j = 0
        for _ in 0...32 {
            let s: Float = 2.0
            plane1.append(Plane(r:1.0,g:0.0,b:0.0,a:1.0,sx:s, sy:s, sz:s) )
            
            vertex1Buffer.append(self.device.makeBuffer(bytes: plane1[j].vertexData, length: 82 * plane1[j].vertexData.count, options:[])!)
            texCoord1Buffer.append(self.device.makeBuffer(bytes: plane1[j].texCood, length: 82 * plane1[j].texCood.count, options:[])!)
            j += 1
        }
        var i = 0
        for _ in plane1 {
            guard let buffer = self.device.makeBuffer(length:uniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
            buffer.label = "UniformBuffer"
            dynamicUniformBuffer.append(buffer)
            uniforms.append( UnsafeMutableRawPointer(dynamicUniformBuffer[i].contents()).bindMemory(to:Uniforms.self, capacity:1) )
            i += 1
        }


        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        let mtlVertexDescriptor = MTLVertexDescriptor() //Renderer.buildMetalVertexDescriptor()
        
        do {
            pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
                                                                       metalKitView: metalKitView,
                                                                       mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }
        
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDesciptor.isDepthWriteEnabled = false
        guard let state = device.makeDepthStencilState(descriptor:depthStateDesciptor) else { return nil }
        depthState = state
        
        
        
        super.init()
    }

    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.sampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        
        var i = 0
        for _ in plane1 {

            uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
            
            uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
            
            uniforms.append( UnsafeMutableRawPointer(dynamicUniformBuffer[i].contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1) )
            i += 1
        }
    }
    
    private func updateGameState() {
        /// Update any game state before rendering
        var i = 0
        for p in plane1 {
            uniforms[i][0].projectionMatrix = projectionMatrix
            let modelMatrix = matrix4x4_translation(p.x, p.y, 0.0)
            let viewMatrix = matrix_lookAt(eye: SIMD3<Float>(0,0,8.0), target: SIMD3<Float>(0,0,0), up:SIMD3<Float>(0,1,0))//matrix4x4_translation(8.0, 8.0, -8.0)
            uniforms[i][0].modelViewMatrix = simd_mul(viewMatrix, modelMatrix)
            uniforms[i][0].lightPosition = SIMD3<Float>(1,0,0)
            p.x += p.speedX
            p.y += p.speedY
            
            if p.x < -3.0 || p.x > 3.0 {
                p.speedX *= -1
            }
            if p.y < -3.0 || p.y > 3.0 {
                p.speedY *= -1
            }
            i += 1
        }
    }
    
    func draw(in view: MTKView) {
        /// Per frame updates hare
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            self.updateDynamicBufferState()
            
            self.updateGameState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            if let renderPassDescriptor = renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
                /// Final pass rendering code here
                
//                renderEncoder.setCullMode(.back)
//                renderEncoder.setFrontFacing(.counterClockwise)
                
                renderEncoder.setRenderPipelineState(pipelineState)
                renderEncoder.setDepthStencilState(depthState)
                
                var i = 0
                for p in plane1 {

                    renderEncoder.setVertexBuffer(dynamicUniformBuffer[i], offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setFragmentBuffer(dynamicUniformBuffer[i], offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)

                    vertex1Buffer[i] = device.makeBuffer(bytes: p.vertexData, length: 82 * p.vertexData.count, options:[])!
                    texCoord1Buffer[i] = device.makeBuffer(bytes: p.texCood, length: 82 * p.texCood.count, options:[])!

                    renderEncoder.setVertexBuffer(vertex1Buffer[i], offset: 0, index: 0)
                    renderEncoder.setVertexBuffer(texCoord1Buffer[i], offset: 0, index: 2)
                    renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                    
                    i += 1
                }


                renderEncoder.popDebugGroup()
                
                renderEncoder.endEncoding()
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
            
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
    }
}

// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func matrix_lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    var m = [
        Float(1.0), Float(0.0), Float(0.0), Float(0.0),
        Float(0.0), Float(1.0), Float(0.0), Float(0.0),
        Float(0.0), Float(0.0), Float(1.0), Float(0.0),
        Float(0.0), Float(0.0), Float(0.0), Float(1.0),
    ]
    var l = Float(0.0)
    var t = [Float(0.0), Float(0.0), Float(0.0)]
    t[0] = eye[0] - target[0]
    t[1] = eye[1] - target[1]
    t[2] = eye[2] - target[2]
    var tt = t[0]*t[0]+t[1]*t[1]+t[2]*t[2]
    l = sqrt(tt)
    m[ 2] = t[0] / l
    m[ 6] = t[1] / l;
    m[10] = t[2] / l;
    
    
    t[0] = up[1] * m[10] - up[2] * m[ 6];
    t[1] = up[2] * m[ 2] - up[0] * m[10];
    t[2] = up[0] * m[ 6] - up[1] * m[ 2];
    tt = t[0]*t[0]+t[1]*t[1]+t[2]*t[2]
    l = sqrt(tt);
    m[0] = t[0] / l;
    m[4] = t[1] / l;
    m[8] = t[2] / l;
    
    
    m[1] = m[ 6] * m[8] - m[10] * m[4];
    m[5] = m[10] * m[0] - m[ 2] * m[8];
    m[9] = m[ 2] * m[4] - m[ 6] * m[0];
    
    m[12] = -(eye[0] * m[0] + eye[1] * m[4] + eye[2] * m[ 8]);
    m[13] = -(eye[0] * m[1] + eye[1] * m[5] + eye[2] * m[ 9]);
    m[14] = -(eye[0] * m[2] + eye[1] * m[6] + eye[2] * m[10]);
    
    return matrix_float4x4.init(columns:(vector_float4(m[0], m[1], m[2], m[3]),
                                         vector_float4(m[4], m[5], m[6], m[7]),
                                         vector_float4(m[8], m[9], m[10], m[11]),
                                         vector_float4(m[12], m[13], m[14], m[15])))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
