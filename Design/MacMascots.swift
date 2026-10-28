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
        func face(_ y: CGFloat, _ left: CGFloat = 8, _ right: CGFloat = 14) {
            eye(left, y, 2.6); eye(right, y, 2.6)
            let smile = NSBezierPath();smile.move(to:NSPoint(x:10,y:y-2));smile.curve(to:NSPoint(x:14,y:y-2),controlPoint1:NSPoint(x:11,y:y-3.5),controlPoint2:NSPoint(x:13,y:y-3.5));stroke(smile,1.15)
        }
        switch index {
        case 0:
            stroke(NSBezierPath(roundedRect:NSRect(x:4,y:1.5,width:16,height:21),xRadius:3,yRadius:3),1.65)
            stroke(NSBezierPath(roundedRect:NSRect(x:6.5,y:9,width:11,height:10.5),xRadius:2,yRadius:2),1.2)
            face(14,8,13.5)
            stroke(path([NSPoint(x:12,y:5.2),NSPoint(x:17,y:5.2)]),1.4)
            NSBezierPath(ovalIn:NSRect(x:7,y:4.5,width:1.5,height:1.5)).fill()
        case 1:
            stroke(NSBezierPath(roundedRect:NSRect(x:2,y:6.5,width:20,height:15),xRadius:3.5,yRadius:3.5),1.8)
            face(14.5)
            stroke(path([NSPoint(x:3,y:10),NSPoint(x:21,y:10)]),1.15)
            stroke(path([NSPoint(x:10,y:6.5),NSPoint(x:9,y:2.5),NSPoint(x:15,y:2.5),NSPoint(x:14,y:6.5)]),1.4)
        case 2:
            stroke(NSBezierPath(roundedRect:NSRect(x:4,y:6,width:16,height:15),xRadius:2.5,yRadius:2.5),1.65)
            face(13.7)
            let base=path([NSPoint(x:4,y:6),NSPoint(x:1.5,y:2.5),NSPoint(x:22.5,y:2.5),NSPoint(x:20,y:6)],close:true);stroke(base,1.6)
            stroke(path([NSPoint(x:10,y:4),NSPoint(x:14,y:4)]),1.1)
        default:
            // Tilted, expressive display with a jaunty stand.
            let body=NSBezierPath()
            body.move(to:NSPoint(x:3,y:8));body.line(to:NSPoint(x:3,y:19));body.curve(to:NSPoint(x:6,y:22),controlPoint1:NSPoint(x:3,y:21),controlPoint2:NSPoint(x:4,y:22));body.line(to:NSPoint(x:20,y:20));body.curve(to:NSPoint(x:22,y:17),controlPoint1:NSPoint(x:22,y:20),controlPoint2:NSPoint(x:22,y:19));body.line(to:NSPoint(x:22,y:7));body.curve(to:NSPoint(x:19,y:5),controlPoint1:NSPoint(x:22,y:5),controlPoint2:NSPoint(x:21,y:5));body.line(to:NSPoint(x:5,y:6));body.curve(to:NSPoint(x:3,y:8),controlPoint1:NSPoint(x:3,y:6),controlPoint2:NSPoint(x:3,y:7));body.close();stroke(body,1.8)
            eye(7.5,13,3.5)
            stroke(path([NSPoint(x:14,y:14),NSPoint(x:17,y:14.8)]),1.6)
            let grin=NSBezierPath();grin.move(to:NSPoint(x:10,y:10));grin.curve(to:NSPoint(x:15,y:10.5),controlPoint1:NSPoint(x:11,y:8.5),controlPoint2:NSPoint(x:14,y:8.5));stroke(grin,1.3)
            stroke(path([NSPoint(x:11,y:5.5),NSPoint(x:10,y:2),NSPoint(x:16,y:2)]),1.7)
        }
        return true
    }
}

@main struct Sheet {
    @MainActor static func main() throws {
        let image=NSImage(size:NSSize(width:1280,height:650));image.lockFocus()
        NSColor(calibratedRed:0.96,green:0.95,blue:0.92,alpha:1).setFill();NSRect(x:0,y:0,width:1280,height:650).fill()
        func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ bold:Bool=false,_ color:NSColor = .black){(s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:bold ? .semibold : .regular),.foregroundColor:color])}
        text("让你的 Mac，成为小伙伴。",36,581,30,true)
        text("四款电脑角色 · 屏幕是表情，机身是性格 · 同一轮廓适配设置页与状态栏",36,545,14,false,.darkGray)
        let names=["10  经典麦仔","11  小桌面","12  本本仔","13  歪头屏"]
        let subs=["经典 Macintosh 的复古比例","iMac 轮廓，稳稳陪在桌上","MacBook 翻开，就开始工作","轻轻歪头，眨一下眼"]
        let notes=["怀旧、踏实，像老朋友。","清爽、圆润，一眼认出电脑。","轻巧、随身，有行动感。","有点调皮，角色感最强。"]
        for i in 0..<4 {
            let x=CGFloat(36+i*310)
            NSColor.white.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:52,width:282,height:450),xRadius:22,yRadius:22).fill()
            text(names[i],x+22,457,21,true);text(subs[i],x+22,429,12,false,.darkGray)
            character(i,138).draw(in:NSRect(x:x+72,y:257,width:138,height:138))
            text(notes[i],x+22,219,12,false,.darkGray)
            NSColor(calibratedWhite:0.9,alpha:1).setFill();NSRect(x:x+22,y:192,width:238,height:1).fill()
            character(i,32).draw(in:NSRect(x:x+24,y:122,width:32,height:32));text("设置页",x+66,130,11,false,.darkGray)
            NSColor(calibratedWhite:0.91,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:x+172,y:118,width:86,height:36),xRadius:9,yRadius:9).fill()
            character(i,18).draw(in:NSRect(x:x+206,y:127,width:18,height:18));text("状态栏 18pt",x+183,91,10,false,.darkGray)
        }
        image.unlockFocus()
        let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
