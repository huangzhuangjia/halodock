import AppKit

@MainActor
func character(_ index: Int, _ size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let t = NSAffineTransform(); t.scale(by: rect.width / 24); t.concat()
        NSColor.black.setFill(); NSColor.black.setStroke()
        func stroke(_ p: NSBezierPath, _ w: CGFloat = 1.7) {
            p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        }
        func path(_ points: [NSPoint], close: Bool = false) -> NSBezierPath {
            let p = NSBezierPath(); p.move(to: points[0]); for v in points.dropFirst() { p.line(to: v) }; if close { p.close() }; return p
        }
        func eye(_ x: CGFloat, _ y: CGFloat, _ height: CGFloat = 3) {
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 2.2, height: height), xRadius: 1.1, yRadius: 1.1).fill()
        }
        switch index {
        case 0:
            // A lopsided handle is the signature silhouette.
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 7, y: 17))
            handle.line(to: NSPoint(x: 8.2, y: 21))
            handle.curve(to: NSPoint(x: 16.5, y: 19), controlPoint1: NSPoint(x: 9, y: 24), controlPoint2: NSPoint(x: 18.5, y: 23))
            handle.line(to: NSPoint(x: 16, y: 17))
            stroke(handle, 1.9)
            stroke(NSBezierPath(roundedRect: NSRect(x: 2.5,y: 3,width: 19,height: 14),xRadius: 4,yRadius: 4),1.8)
            eye(7, 9, 3.4); eye(14.5, 9.6, 3.4)
            let smile = NSBezierPath(); smile.move(to: NSPoint(x: 10,y: 6.6));smile.curve(to:NSPoint(x:14,y:7.1),controlPoint1:NSPoint(x:11,y:5.6),controlPoint2:NSPoint(x:13,y:5.8));stroke(smile,1.2)
            stroke(path([NSPoint(x: 2.5,y: 13.5),NSPoint(x: 5,y: 13.5)]),1.3)
            stroke(path([NSPoint(x: 19,y: 13.5),NSPoint(x: 21.5,y: 13.5)]),1.3)
        case 1:
            // A lower drawer doubles as a tiny open mouth.
            stroke(NSBezierPath(roundedRect: NSRect(x:3,y:2,width:18,height:18),xRadius:4,yRadius:4),1.8)
            stroke(path([NSPoint(x:8,y:20),NSPoint(x:8,y:22),NSPoint(x:16,y:22),NSPoint(x:16,y:20)]),1.6)
            eye(7.3,12,3);eye(14.5,12,3)
            let drawer = NSBezierPath(roundedRect:NSRect(x:6,y:4.6,width:12,height:4),xRadius:1.5,yRadius:1.5)
            stroke(drawer,1.3)
            stroke(path([NSPoint(x:10,y:6.6),NSPoint(x:14,y:6.6)]),1.3)
        default:
            // Side switches create a recognisable little control-console character.
            stroke(NSBezierPath(roundedRect:NSRect(x:4,y:3,width:16,height:16),xRadius:5,yRadius:5),1.8)
            stroke(path([NSPoint(x:9,y:19),NSPoint(x:9,y:22),NSPoint(x:15,y:22),NSPoint(x:15,y:19)]),1.7)
            stroke(path([NSPoint(x:1,y:13),NSPoint(x:4,y:13)]),2.5)
            stroke(path([NSPoint(x:20,y:9),NSPoint(x:23,y:9)]),2.5)
            eye(7.2,10,3.6);eye(14.6,10,3.6)
            stroke(path([NSPoint(x:10.5,y:6.3),NSPoint(x:13.5,y:6.3)]),1.3)
        }
        return true
    }
}

@main struct Sheet {
    @MainActor static func main() throws {
        let image=NSImage(size: NSSize(width: 1140,height: 610))
        image.lockFocus()
        NSColor(calibratedRed: 0.96,green: 0.95,blue: 0.92,alpha: 1).setFill();NSRect(x: 0,y: 0,width: 1140,height: 610).fill()
        func text(_ s: String,_ x: CGFloat,_ y: CGFloat,_ size: CGFloat,_ bold: Bool=false,_ color: NSColor = .black) {
            (s as NSString).draw(at: NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:bold ? .semibold : .regular),.foregroundColor:color])
        }
        text("三个工具箱，三种性格。",36,548,30,true)
        text("参考 Pastebot 的物件人格化方法，重新设计 HaloDock 的小助手",36,515,15,false,.darkGray)
        let titles=["01  翘翘箱","02  抽屉仔","03  拨片盒"]
        let ideas=["歪提手 × 不对称表情","收纳柜 × 小抽屉嘴巴","控制盒 × 高低拨片耳朵"]
        let personalities=["有点机灵，拎起来就能帮忙。","认真收好每一件小事。","常用控制，伸手就够得到。"]
        for i in 0..<3 {
            let x=CGFloat(36+i*368)
            NSColor.white.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:42,width:332,height:440),xRadius:22,yRadius:22).fill()
            text(titles[i],x+24,435,21,true)
            text(ideas[i],x+24,407,13,false,.darkGray)
            character(i,128).draw(in:NSRect(x:x+102,y:241,width:128,height:128))
            text(personalities[i],x+24,208,13,false,.darkGray)
            NSColor(calibratedWhite:0.9,alpha:1).setFill();NSRect(x:x+24,y:183,width:284,height:1).fill()
            character(i,32).draw(in:NSRect(x:x+26,y:115,width:32,height:32))
            text("设置页",x+70,123,12,false,.darkGray)
            NSColor(calibratedWhite:0.91,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:x+218,y:111,width:90,height:36),xRadius:9,yRadius:9).fill()
            character(i,18).draw(in:NSRect(x:x+254,y:120,width:18,height:18))
            text("状态栏 18pt",x+229,84,11,false,.darkGray)
        }
        image.unlockFocus()
        let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
