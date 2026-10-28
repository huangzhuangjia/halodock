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
            let strap=NSBezierPath();strap.move(to:NSPoint(x:5,y:13));strap.curve(to:NSPoint(x:20,y:13),controlPoint1:NSPoint(x:5,y:25),controlPoint2:NSPoint(x:20,y:25));stroke(strap)
            stroke(NSBezierPath(roundedRect:NSRect(x:2,y:3,width:20,height:12),xRadius:4,yRadius:4),1.8)
            stroke(path([NSPoint(x:3,y:13),NSPoint(x:10,y:9),NSPoint(x:14,y:9),NSPoint(x:21,y:13)]),1.3)
            eye(7,5.8,2.6);eye(15,5.8,2.6)
            NSBezierPath(roundedRect:NSRect(x:10.5,y:10,width:3,height:3),xRadius:0.8,yRadius:0.8).fill()
        case 1:
            stroke(NSBezierPath(roundedRect:NSRect(x:2,y:4,width:17,height:16),xRadius:7,yRadius:7),1.8)
            eye(6,11,3);eye(12,11,3)
            let mouth=NSBezierPath();mouth.move(to:NSPoint(x:7,y:8));mouth.curve(to:NSPoint(x:13,y:8),controlPoint1:NSPoint(x:9,y:6),controlPoint2:NSPoint(x:11,y:6));stroke(mouth,1.2)
            stroke(path([NSPoint(x:18,y:7),NSPoint(x:22,y:7),NSPoint(x:22,y:3)]),2)
            stroke(path([NSPoint(x:19,y:7),NSPoint(x:19,y:9)]),1)
            stroke(path([NSPoint(x:21,y:7),NSPoint(x:21,y:9)]),1)
        case 2:
            let p=NSBezierPath();p.move(to:NSPoint(x:3,y:21));p.line(to:NSPoint(x:3,y:10));p.curve(to:NSPoint(x:21,y:10),controlPoint1:NSPoint(x:3,y:-1),controlPoint2:NSPoint(x:21,y:-1));p.line(to:NSPoint(x:21,y:21));p.line(to:NSPoint(x:15,y:21));p.line(to:NSPoint(x:15,y:10));p.curve(to:NSPoint(x:9,y:10),controlPoint1:NSPoint(x:15,y:6),controlPoint2:NSPoint(x:9,y:6));p.line(to:NSPoint(x:9,y:21));p.close();stroke(p,1.6)
            stroke(path([NSPoint(x:3,y:16),NSPoint(x:9,y:16)]),1.3);stroke(path([NSPoint(x:15,y:16),NSPoint(x:21,y:16)]),1.3)
            eye(5,10,2);eye(17,10,2)
        case 3:
            let tool=NSBezierPath(roundedRect:NSRect(x:3,y:2.5,width:18,height:11),xRadius:5,yRadius:5);stroke(tool,1.8)
            stroke(path([NSPoint(x:7,y:14),NSPoint(x:5,y:20),NSPoint(x:7,y:22),NSPoint(x:10,y:14)]),1.6)
            stroke(path([NSPoint(x:13,y:14),NSPoint(x:17,y:21),NSPoint(x:20,y:20),NSPoint(x:18,y:14)]),1.6)
            eye(7,7,2.7);eye(14.5,7,2.7)
        case 4:
            let p=NSBezierPath();p.move(to:NSPoint(x:3,y:18));p.line(to:NSPoint(x:21,y:18));p.line(to:NSPoint(x:21,y:9));p.curve(to:NSPoint(x:12,y:2),controlPoint1:NSPoint(x:21,y:5),controlPoint2:NSPoint(x:16,y:2));p.curve(to:NSPoint(x:3,y:9),controlPoint1:NSPoint(x:8,y:2),controlPoint2:NSPoint(x:3,y:5));p.close();stroke(p,1.8)
            stroke(path([NSPoint(x:3,y:15),NSPoint(x:21,y:15)]),1.3)
            eye(7,9,2.7);eye(14.5,9,2.7)
            let tag=NSBezierPath();tag.move(to:NSPoint(x:15,y:18));tag.line(to:NSPoint(x:15,y:22));tag.line(to:NSPoint(x:19,y:22));tag.line(to:NSPoint(x:19,y:18));stroke(tag,1.5)
        default:
            let p=NSBezierPath();p.move(to:NSPoint(x:5,y:5));p.line(to:NSPoint(x:5,y:15));p.curve(to:NSPoint(x:19,y:15),controlPoint1:NSPoint(x:5,y:24),controlPoint2:NSPoint(x:19,y:24));p.line(to:NSPoint(x:19,y:5));p.curve(to:NSPoint(x:9,y:5),controlPoint1:NSPoint(x:19,y:-1),controlPoint2:NSPoint(x:9,y:-1));p.line(to:NSPoint(x:9,y:14));p.curve(to:NSPoint(x:15,y:14),controlPoint1:NSPoint(x:9,y:19),controlPoint2:NSPoint(x:15,y:19));p.line(to:NSPoint(x:15,y:7));stroke(p,1.8)
            eye(6.2,8.5,2.4);eye(16,8.5,2.4)
        }
        return true
    }
}

@main struct Sheet {
    @MainActor static func main() throws {
        let image=NSImage(size:NSSize(width:1140,height:1060));image.lockFocus()
        NSColor(calibratedRed:0.96,green:0.95,blue:0.92,alpha:1).setFill();NSRect(x:0,y:0,width:1140,height:1060).fill()
        func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ bold:Bool=false,_ color:NSColor = .black){(s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:bold ? .semibold : .regular),.foregroundColor:color])}
        text("不止是一个小方盒。",36,994,30,true)
        text("六个新的工具角色 · 看轮廓，也看状态栏里的辨识度",36,960,15,false,.darkGray)
        let names=["04  挎包仔","05  卷尺仔","06  磁铁搭子","07  折叠小工","08  口袋精灵","09  夹子助手"]
        let subs=["随身工具包 × 搭扣鼻子","卷尺机身 × 一截小尾巴","马蹄磁铁 × 双脸结构","折叠工具 × 伸展的耳朵","收纳口袋 × 翘出的标签","回形针 × 灵活细长轮廓"]
        let traits=["带上常用工具，随时出发。","一小只，也有伸手的本领。","把分散的事情吸到一起。","需要哪一招，就展开哪一招。","把零碎收好，轻装上阵。","夹住灵感，接住下一件事。"]
        for i in 0..<6 {
            let x=CGFloat(36+(i%3)*368), y=CGFloat(i<3 ? 506 : 50)
            NSColor.white.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:y,width:332,height:420),xRadius:22,yRadius:22).fill()
            text(names[i],x+24,y+373,21,true);text(subs[i],x+24,y+346,13,false,.darkGray)
            character(i,126).draw(in:NSRect(x:x+103,y:y+188,width:126,height:126))
            text(traits[i],x+24,y+157,13,false,.darkGray)
            NSColor(calibratedWhite:0.9,alpha:1).setFill();NSRect(x:x+24,y:y+132,width:284,height:1).fill()
            character(i,32).draw(in:NSRect(x:x+26,y:y+63,width:32,height:32));text("设置页",x+70,y+71,12,false,.darkGray)
            NSColor(calibratedWhite:0.91,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:x+218,y:y+59,width:90,height:36),xRadius:9,yRadius:9).fill()
            character(i,18).draw(in:NSRect(x:x+254,y:y+68,width:18,height:18));text("状态栏 18pt",x+229,y+32,11,false,.darkGray)
        }
        image.unlockFocus()
        let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
