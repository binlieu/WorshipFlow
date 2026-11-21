// R16: Metal shader compilation is the slowest thing an output does when it starts. The library and the pipeline
// states are immutable and thread-safe, so they are built once per device and shared by every compositor.
import Foundation
import Metal

// @unchecked Sendable: `library` is immutable; `pipelines` is guarded by `lock`.
final class SharedGPUState: @unchecked Sendable {
    let library: MTLLibrary
    private let device: MTLDevice
    private let lock = NSLock()
    private var pipelines: [MTLPixelFormat: MTLRenderPipelineState] = [:]

    init(device: MTLDevice, library: MTLLibrary) {
        self.device = device
        self.library = library
    }

    func pipeline(for format: MTLPixelFormat) throws -> MTLRenderPipelineState {
        lock.lock(); defer { lock.unlock() }       // held while building: a second caller waits instead of building twice
        if let p = pipelines[format] { return p }
        guard let vf = library.makeFunction(name: "quad_vertex"), let ff = library.makeFunction(name: "quad_fragment") else {
            throw RenderError.shaderCompilation("missing shader function")
        }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vf
        d.fragmentFunction = ff
        let a = d.colorAttachments[0]!
        a.pixelFormat = format
        a.isBlendingEnabled = true
        a.rgbBlendOperation = .add
        a.alphaBlendOperation = .add
        a.sourceRGBBlendFactor = .one
        a.sourceAlphaBlendFactor = .one
        a.destinationRGBBlendFactor = .oneMinusSourceAlpha
        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            let p = try device.makeRenderPipelineState(descriptor: d)
            pipelines[format] = p
            return p
        } catch {
            throw RenderError.pipeline("\(error)")
        }
    }
}

enum SharedGPU {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var states: [UInt64: SharedGPUState] = [:]
    nonisolated(unsafe) private static var compiles = 0

    /// Shader compilations performed in this process (tests and diagnostics).
    static var compileCount: Int { lock.lock(); defer { lock.unlock() }; return compiles }

    /// The shared state for `device`, compiling the shaders the first time. A second caller arriving during the
    /// compile waits for it rather than compiling again.
    static func state(for device: MTLDevice) throws -> SharedGPUState {
        lock.lock(); defer { lock.unlock() }
        if let s = states[device.registryID] { return s }
        compiles += 1
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Compositor.shaderSource, options: nil)
        } catch {
            throw RenderError.shaderCompilation("\(error)")
        }
        let s = SharedGPUState(device: device, library: library)
        states[device.registryID] = s
        return s
    }
}
