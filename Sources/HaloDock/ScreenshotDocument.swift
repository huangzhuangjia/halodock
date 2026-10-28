import AppKit
import Combine
import UniformTypeIdentifiers

struct ScreenshotAnnotation {
    enum Tool: String, CaseIterable { case pencil="画笔", rectangle="矩形", arrow="箭头", text="文字" }
    let tool: Tool
    var points: [CGPoint]
    let color: NSColor
    let width: CGFloat
    var text = ""
}

@MainActor
final class ScreenshotDocument: ObservableObject {
    let image: CGImage
    @Published var tool: ScreenshotAnnotation.Tool = .arrow
    @Published var color = NSColor.systemRed
    @Published var lineWidth: CGFloat = 6
    @Published private(set) var annotations: [ScreenshotAnnotation] = []
    @Published private(set) var redoItems: [ScreenshotAnnotation] = []
    @Published var textAnchor: CGPoint?
    @Published var status = "标注后可以复制或保存 PNG"
    var size: CGSize { CGSize(width:image.width,height:image.height) }

    init(image: CGImage) { self.image=image }

    func add(_ annotation: ScreenshotAnnotation) {
        annotations.append(annotation)
        redoItems.removeAll()
        status="已添加\(annotation.tool.rawValue)标注"
    }
    func addText(_ text: String) {
        guard let anchor=textAnchor,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        add(ScreenshotAnnotation(tool:.text,points:[anchor],color:color,width:lineWidth,text:text))
        textAnchor=nil
    }
    func undo() { if let last=annotations.popLast() { redoItems.append(last) } }
    func redo() { if let last=redoItems.popLast() { annotations.append(last) } }

    func renderedImage() -> CGImage? {
        guard let space=CGColorSpace(name:CGColorSpace.sRGB),
              let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image,in:CGRect(origin:.zero,size:size))
        context.translateBy(x:0,y:size.height)
        context.scaleBy(x:1,y:-1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:true)
        for annotation in annotations { ScreenshotDrawing.draw(annotation) }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    func pngData() -> Data? {
        guard let image=renderedImage() else { return nil }
        return NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])
    }
    @discardableResult
    func copy() -> Bool {
        guard let data=pngData() else { status="无法生成截图"; return false }
        let board=NSPasteboard.general
        board.clearContents()
        if board.setData(data,forType:.png) { status="截图已复制到剪贴板";return true }
        status="复制失败，请尝试保存 PNG";return false
    }
    @discardableResult
    func save() -> Bool {
        let panel=NSSavePanel()
        panel.allowedContentTypes=[.png]
        panel.nameFieldStringValue="HaloDock-\(Int(Date().timeIntervalSince1970)).png"
        panel.directoryURL=FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first
        guard panel.runModal() == .OK,let url=panel.url else { return false }
        guard let data=pngData() else { status="无法生成截图";return false }
        do { try data.write(to:url,options:.atomic);status="已保存：\(url.lastPathComponent)";return true }
        catch { status="保存失败：\(error.localizedDescription)";return false }
    }
}

@MainActor
enum ScreenshotDrawing {
    static func draw(_ annotation: ScreenshotAnnotation) {
        guard let first=annotation.points.first else { return }
        annotation.color.setStroke()
        annotation.color.setFill()
        let path=NSBezierPath()
        path.lineWidth=annotation.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch annotation.tool {
        case .pencil:
            path.move(to:first)
            for point in annotation.points.dropFirst() { path.line(to:point) }
            path.stroke()
        case .rectangle:
            guard let last=annotation.points.last else { return }
            path.appendRect(CGRect(x:min(first.x,last.x),y:min(first.y,last.y),width:abs(last.x-first.x),height:abs(last.y-first.y)))
            path.stroke()
        case .arrow:
            guard let last=annotation.points.last else { return }
            path.move(to:first);path.line(to:last)
            let angle=atan2(last.y-first.y,last.x-first.x),length=max(12,annotation.width*3.8)
            for offset in [-CGFloat.pi/6,CGFloat.pi/6] {
                path.move(to:last)
                path.line(to:CGPoint(x:last.x-length*cos(angle+offset),y:last.y-length*sin(angle+offset)))
            }
            path.stroke()
        case .text:
            (annotation.text as NSString).draw(at:first,withAttributes:[.font:NSFont.systemFont(ofSize:max(22,annotation.width*6),weight:.semibold),.foregroundColor:annotation.color])
        }
    }
}
