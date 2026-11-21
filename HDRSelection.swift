import AppKit
import Metal
import QuartzCore

enum HDRSelectionMaterial: Float {
    case celadon = 0, pearl = 1, marker = 2, porcelainLite = 3
}

/// Shared, on-demand half-float renderer. No timer, display link or capture API.
final class HDRSelectionRenderer {
    static let shared = try? HDRSelectionRenderer()
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    private var contourTextures: [String: MTLTexture] = [:]
    struct Parameters { var size: SIMD2<Float>; var headroom: Float; var dark: Float; var material: Float = 0 }
    static func usableHeadroom(_ current: CGFloat, material: HDRSelectionMaterial = .celadon) -> Float {
        let cap: CGFloat = (material == .celadon || material == .porcelainLite) ? 1.6 : 1.3
        return Float(min(cap, max(1, current.isFinite ? current : 1)))
    }
    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "MeetSee.EDR", code: 1)
        }
        self.device = device; self.queue = queue
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 position [[position]]; float2 uv; };
        struct P { float2 size; float headroom; float dark; float material; };
        vertex V vertexMain(uint id [[vertex_id]]) {
            float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
            V v; v.position=float4(p[id],0,1); v.uv=float2(p[id].x*.5+.5,.5-p[id].y*.5); return v;
        }
        fragment float4 fragmentMain(V v [[stage_in]], constant P &p [[buffer(0)]], texture2d<float, access::read> contour [[texture(0)]]) {
            float2 uv=v.uv;
            uint2 pixel=min(uint2(uv*float2(contour.get_width(),contour.get_height())),
                            uint2(contour.get_width()-1,contour.get_height()-1));
            float distance=contour.read(pixel).r;
            float aa=.6*p.size.x/float(contour.get_width());
            float coverage=1.-smoothstep(-aa,aa,distance);
            if(p.material>2.5) {
                // Porcelain lite: lift the glaze body with the full EDR headroom
                // so ink text keeps contrast on the selected row. SDR screens
                // get a brighter, more saturated fallback glaze instead.
                float3 green=pow(float3(158./255.,184./255.,153./255.),float3(2.2));
                float3 sdrBright=pow(float3(178./255.,214./255.,166./255.),float3(2.2));
                float3 base=p.headroom>1.001 ? green*p.headroom : sdrBright;
                // 1pt ink outline just inside the continuous edge.
                float depth=max(0.,-distance);
                float outline=1.-smoothstep(1.2,2.2,depth);
                float3 ink=pow(float3(46./255.,74./255.,53./255.),float3(2.2));
                float3 color=mix(base,ink,outline);
                return float4(color*coverage,coverage);
            }
            if(p.material>1.5) {
                // Opaque Klein-blue-inspired #002FA7. Lift the blue spectrum
                // proportionally, never add neutral white or desaturate the body.
                float3 base=pow(float3(0.,47./255.,167./255.),float3(2.2));
                float strength=clamp((p.headroom-1.)/.3,0.,1.);
                float blue=mix(base.b,1.3,strength);
                return float4(base*(blue/base.b)*coverage,coverage);
            }
            if(p.material>.5) {
                // Top dim -> bottom bright, before illumination. Keep
                // translucency separate from a restrained, neutral EDR lift.
                float3 tint=mix(float3(1.,253./255.,250./255.),float3(1.,254./255.,252./255.),uv.y);
                float alpha=mix(mix(.6445,.6955,uv.y),mix(.09125,.09875,uv.y),p.dark);
                float3 linear=pow(tint,float3(2.2));
                float3 light=linear*alpha*(1.+(min(p.headroom,1.3)-1.)*mix(1.,.10,p.dark));
                // Retain the original fine white outline without a separate
                // offscreen effect around the HDR surface.
                float rim=(1.-smoothstep(.25,.75,-distance))*mix(.65,.13,p.dark);
                light=mix(light,float3(alpha),rim);
                return float4(light*coverage,alpha*coverage);
            }
            float thickness=.66+.13*sin(uv.y*M_PI_F);
            float3 normal=normalize(float3(.025*(.5-uv.x),.07*(.5-uv.y),1.));
            float irradiance=0.;
            for(int i=0;i<4;i++) {
                float3 delta=float3(-.5+float(i)*.65,-1.2,1.6)-float3(uv.x,uv.y*.38,0.);
                irradiance+=max(dot(normal,normalize(delta)),0.)/(1.+dot(delta,delta)*.12);
            }
            irradiance*=.25;
            float3 reference=mix(float3(.953,.962,.950),float3(.18,.23,.25),p.dark);
            float3 transmitted=pow(reference,float3(2.2))*exp(-float3(.90,.66,.62)*thickness);
            float3 scattered=float3(.075,.16,.18)*.90*(1.-exp(-thickness*1.7))*irradiance*1.6;
            float3 energy=transmitted+scattered*mix(1.,.28,p.dark);
            float3 sdr=energy/(1.+max(energy-.83,0.)*.7);
            // Ru-ware-inspired blue-green body, with restrained chroma. The EDR
            // illuminant is more balanced than the former electric cyan: lift
            // all channels, retaining a small green/blue bias rather than neon.
            // EDR surplus is broad face illumination, not a rim or a white spot.
            // Cyan channels can exceed reference white in the float drawable.
            float field=clamp(irradiance/.57,.55,1.);
            // SDR panels receive no EDR surplus, so the plain tone-mapped body
            // reads gray. Give them a dedicated, more saturated and brighter
            // celadon; the EDR path keeps its existing parameters untouched.
            float sdrScreen=step(p.headroom,1.001);
            float3 body=sdr;
            if(sdrScreen>.5) {
                float luma=dot(body,float3(.2126,.7152,.0722));
                body=max(luma+(body-luma)*1.35,0.)*1.40;
            }
            float3 surplus=float3(.95,1.17,1.22)*(p.headroom-1.)*field*mix(1.,.35,p.dark);
            // A thinner, less cloudy body exposes more native glass. Keep the
            // independent EDR illuminant and its previous energy ceiling intact.
            float alpha=mix(.50,.57,p.dark);
            float3 premultiplied=max(body-(1.-alpha)*pow(reference,float3(2.2)),0.)+surplus;
            // Float premultiplied RGB may exceed alpha; this is intentional EDR.
            premultiplied=min(premultiplied,float3(p.headroom*mix(.58,.65,p.dark)));
            return float4(premultiplied*coverage,alpha*coverage);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    private func contourTexture(width: Int, height: Int, size: SIMD2<Float>) -> MTLTexture? {
        let key = "\(width):\(height):\(size.x):\(size.y)"
        if let cached = contourTextures[key] { return cached }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let field = ContinuousCorners.Field(size: CGSize(width: CGFloat(size.x), height: CGFloat(size.y)), radius: 13)
        var distances = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                distances[y * width + x] = Float(field.sample(x: (Double(x)+0.5)*Double(size.x)/Double(width),
                    y: (Double(y)+0.5)*Double(size.y)/Double(height)).distance)
            }
        }
        distances.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: width * MemoryLayout<Float>.stride)
        }
        if contourTextures.count >= 16, let oldest = contourTextures.keys.first { contourTextures.removeValue(forKey: oldest) }
        contourTextures[key] = texture
        return texture
    }
    func encode(texture: MTLTexture, parameters: Parameters, buffer: MTLCommandBuffer) {
        guard let contour = contourTexture(width: texture.width, height: texture.height, size: parameters.size) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var parameters = parameters
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(contour, index: 0)
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

/// This view sits below text/icons, above the native glass. It never takes focus.
final class HDRSelectionView: NSView {
    var material: HDRSelectionMaterial = .celadon {
        didSet {
            guard oldValue != material else { return }
            generation += 1; lastRenderKey = nil
            if hasPresentedFrame { hasPresentedFrame = false; onPresentationChange?() }
            refresh()
        }
    }
    var active = false {
        didSet {
            if oldValue != active {
                generation += 1; lastRenderKey = nil
                if hasPresentedFrame { hasPresentedFrame = false; onPresentationChange?() }
            }
            refresh()
        }
    }
    private(set) var hasPresentedFrame = false
    private(set) var presentedFrameCount = 0
    var onPresentationChange: (() -> Void)?
    private var renderScheduled = false
    private var generation = 0
    private var lastRenderKey: [Double]?
    var available: Bool { HDRSelectionRenderer.shared != nil }
    private var observers: [NSObjectProtocol] = []
    // A separate SDR halo avoids offscreen-flattening the float Metal surface.
    // Its hollow mask keeps all added light outside the material itself.
    let glowLayer = CAShapeLayer()
    private let glowMask = CAShapeLayer()
    let metalLayer = CAMetalLayer()
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        if #available(macOS 14.0, *) { clipsToBounds = false }
        layer?.masksToBounds = false
        // An inverse AA mask can leave fractional source coverage at the seam.
        // Use a faint, matching tint instead of an opaque black silhouette.
        glowLayer.fillColor = NSColor(srgbRed: 0.48, green: 0.76, blue: 0.80, alpha: 0.12).cgColor
        glowLayer.shadowColor = NSColor(srgbRed: 0.48, green: 0.76, blue: 0.80, alpha: 1).cgColor
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = 3
        glowMask.fillRule = .evenOdd
        glowLayer.mask = glowMask
        layer?.addSublayer(glowLayer)
        // AppKit owns only the host layer. The drawable belongs to a dedicated
        // sublayer, so sibling/status redraws cannot replace its contents.
        metalLayer.device = HDRSelectionRenderer.shared?.device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.wantsExtendedDynamicRangeContent = false
        layer?.addSublayer(metalLayer)
        for name in [NSApplication.didChangeScreenParametersNotification,
                     NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refresh() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        metalLayer.frame = bounds
        glowLayer.frame = bounds.insetBy(dx: -10, dy: -10)
        let body = ContinuousCorners.path(in: glowLayer.bounds.insetBy(dx: 10, dy: 10), radius: 13)
        glowLayer.path = body
        glowLayer.shadowPath = body
        let outside = CGMutablePath()
        outside.addRect(glowLayer.bounds)
        outside.addPath(body)
        glowMask.frame = glowLayer.bounds
        glowMask.path = outside
        CATransaction.commit()
        refresh()
    }
    private func refresh() {
        isHidden = !active || !available
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // Custom sublayers/masks do not inherit the window's Retina scale.
        // Keep both at native resolution, including after display changes.
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        glowLayer.contentsScale = scale
        glowMask.contentsScale = scale
        let pearl = material == .pearl
        glowLayer.isHidden = material == .marker
        glowLayer.shadowColor = (pearl ? NSColor.black : NSColor(srgbRed: 0.48, green: 0.76, blue: 0.80, alpha: 1)).cgColor
        glowLayer.fillColor = (pearl ? NSColor.black.withAlphaComponent(0.06) : NSColor(srgbRed: 0.48, green: 0.76, blue: 0.80, alpha: 0.12)).cgColor
        glowLayer.shadowRadius = pearl ? 4 : 3
        glowLayer.shadowOffset = pearl ? CGSize(width: 0, height: 1) : .zero
        glowLayer.shadowOpacity = pearl ? 0.06 : (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.18 : 0.23)
        CATransaction.commit()
        let visible = active && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        metalLayer.wantsExtendedDynamicRangeContent = visible
        if !visible && hasPresentedFrame {
            hasPresentedFrame = false
            generation += 1
            lastRenderKey = nil
            onPresentationChange?()
        }
        if visible { scheduleRender() }
    }
    // A layer-backed descendant of NSGlassEffectView/NSTableRowView does not
    // reliably receive updateLayer. Schedule Metal submission ourselves rather
    // than treating needsDisplay as proof that any drawable was presented.
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false
            self.renderFrame()
        }
    }
    override func updateLayer() { scheduleRender() }
    private func renderFrame() {
        guard active, let window, window.isVisible, window.occlusionState.contains(.visible),
              bounds.width > 0, bounds.height > 0,
              let renderer = HDRSelectionRenderer.shared else { return }
        let metal = metalLayer
        let scale = window.backingScaleFactor
        metal.contentsScale = scale
        let size = CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
        if metal.drawableSize != size { metal.drawableSize = size }
        let parameters = HDRSelectionRenderer.Parameters(size: SIMD2(Float(bounds.width), Float(bounds.height)),
            headroom: HDRSelectionRenderer.usableHeadroom(window.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1, material: material),
            dark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 1 : 0, material: material.rawValue)
        // Presenting a Metal drawable may itself provoke an AppKit layer update.
        // Only changed inputs may submit another frame; otherwise that becomes
        // an accidental display-rate rendering loop despite having no timer.
        let key = [Double(size.width), Double(size.height), Double(scale),
                   Double(parameters.headroom), Double(parameters.dark), Double(parameters.material)]
        guard key != lastRenderKey else { return }
        guard let drawable = metal.nextDrawable(), let buffer = renderer.queue.makeCommandBuffer() else { return }
        lastRenderKey = key
        let token = generation
        drawable.addPresentedHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.active, self.window?.isVisible == true else { return }
                self.presentedFrameCount += 1
                if !self.hasPresentedFrame {
                    self.hasPresentedFrame = true
                    self.onPresentationChange?()
                }
            }
        }
        renderer.encode(texture: drawable.texture, parameters: parameters, buffer: buffer)
        buffer.present(drawable); buffer.commit()
    }
}
