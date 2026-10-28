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
        switch index {
        case 0:
            // A soft cursor silhouette, leaning forward with one small foot.
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 4, y: 21))
            p.curve(to: NSPoint(x: 6, y: 21), controlPoint1: NSPoint(x: 4, y: 22), controlPoint2: NSPoint(x: 5, y: 22))
            p.line(to: NSPoint(x: 21, y: 9))
            p.curve(to: NSPoint(x: 20, y: 7), controlPoint1: NSPoint(x: 22, y: 8), controlPoint2: NSPoint(x: 22, y: 7))
            p.line(to: NSPoint(x: 14, y: 7)); p.line(to: NSPoint(x: 16, y: 3))
            p.line(to: NSPoint(x: 12, y: 1)); p.line(to: NSPoint(x: 10, y: 6))
            p.line(to: NSPoint(x: 6, y: 2))
            p.curve(to: NSPoint(x: 4, y: 3), controlPoint1: NSPoint(x: 5, y: 1), controlPoint2: NSPoint(x: 4, y: 2))
            p.close(); stroke(p)
            for (x,y) in [(7.5,13.0),(12.0,11.5)] {
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2, height: 2.8)).fill()
            }
        case 1:
            // A folded window corner becomes a swept fringe.
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 7, y: 2)); p.line(to: NSPoint(x: 17, y: 2))
            p.curve(to: NSPoint(x: 21, y: 6), controlPoint1: NSPoint(x: 20, y: 2), controlPoint2: NSPoint(x: 21, y: 3))
            p.line(to: NSPoint(x: 21, y: 14)); p.line(to: NSPoint(x: 14, y: 21))
            p.line(to: NSPoint(x: 7, y: 21))
            p.curve(to: NSPoint(x: 3, y: 17), controlPoint1: NSPoint(x: 4, y: 21), controlPoint2: NSPoint(x: 3, y: 20))
            p.line(to: NSPoint(x: 3, y: 6))
            p.curve(to: NSPoint(x: 7, y: 2), controlPoint1: NSPoint(x: 3, y: 3), controlPoint2: NSPoint(x: 4, y: 2))
            p.close(); stroke(p)
            stroke(path([NSPoint(x: 14,y: 21),NSPoint(x: 14,y: 14),NSPoint(x: 21,y: 14)]))
            NSBezierPath(ovalIn: NSRect(x: 6.8,y: 8,width: 2.3,height: 3.3)).fill()
            // One wink gives the little window a mischievous personality.
            stroke(path([NSPoint(x: 13.5,y: 9.8),NSPoint(x: 16.8,y: 9.8)]),1.6)
            stroke(path([NSPoint(x: 9,y: 5.8),NSPoint(x: 13,y: 5.8)]),1.2)
        default:
            // Two pins double as expressive ears, a cable tail becomes a foot.
            stroke(path([NSPoint(x: 8,y: 17),NSPoint(x: 7,y: 22)]),2.2)
            stroke(path([NSPoint(x: 16,y: 17),NSPoint(x: 17,y: 22)]),2.2)
            stroke(NSBezierPath(roundedRect: NSRect(x: 3,y: 5,width: 18,height: 13), xRadius: 5,yRadius: 5))
            for x: CGFloat in [7,14.5] { NSBezierPath(ovalIn: NSRect(x: x,y: 10,width: 2.4,height: 3)).fill() }
            let cable=NSBezierPath(); cable.move(to: NSPoint(x: 12,y: 5)); cable.line(to: NSPoint(x: 12,y: 3)); cable.curve(to: NSPoint(x: 19,y: 2),controlPoint1: NSPoint(x: 12,y: 0),controlPoint2: NSPoint(x: 17,y: 0)); stroke(cable)
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
        text("工具，也可以有个性。",36,548,30,true)
        text("从 Mac 的交互语言里长出来的三个小角色",36,515,15,false,.darkGray)
        let titles=["01  游标仔","02  折角仔","03  插头仔"]
        let ideas=["指针 × 小脚丫","窗口 × 一撮折角刘海","插头 × 会竖耳朵的伙伴"]
        let personalities=["随叫随到，有点行动派。","把琐事收好，眨眼就搞定。","让工具连起来，给工作续点电。"]
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
