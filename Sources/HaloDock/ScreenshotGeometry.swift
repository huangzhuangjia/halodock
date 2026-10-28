import CoreGraphics

/// Selection coordinates use a top-left origin, matching screenshot pixel coordinates.
enum ScreenshotGeometry {
    enum Handle: CaseIterable { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }

    static func selection(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        let a = clamped(start, to: bounds), b = clamped(end, to: bounds)
        return CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }

    static func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x,bounds.minX),bounds.maxX), y: min(max(point.y,bounds.minY),bounds.maxY))
    }

    static func moved(_ rect: CGRect, by delta: CGPoint, in bounds: CGRect) -> CGRect {
        CGRect(x: min(max(rect.minX+delta.x,bounds.minX),bounds.maxX-rect.width),
               y: min(max(rect.minY+delta.y,bounds.minY),bounds.maxY-rect.height), width: rect.width,height: rect.height)
    }

    static func point(for handle: Handle, in r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x:r.minX,y:r.minY)
        case .top: CGPoint(x:r.midX,y:r.minY)
        case .topRight: CGPoint(x:r.maxX,y:r.minY)
        case .right: CGPoint(x:r.maxX,y:r.midY)
        case .bottomRight: CGPoint(x:r.maxX,y:r.maxY)
        case .bottom: CGPoint(x:r.midX,y:r.maxY)
        case .bottomLeft: CGPoint(x:r.minX,y:r.maxY)
        case .left: CGPoint(x:r.minX,y:r.midY)
        }
    }

    static func resized(_ r: CGRect, handle: Handle, by delta: CGPoint, in bounds: CGRect) -> CGRect {
        let minimum: CGFloat = 8
        var x1=r.minX,y1=r.minY,x2=r.maxX,y2=r.maxY
        if [.topLeft,.left,.bottomLeft].contains(handle) { x1 = max(bounds.minX,min(x1+delta.x,x2-minimum)) }
        if [.topRight,.right,.bottomRight].contains(handle) { x2 = min(bounds.maxX,max(x2+delta.x,x1+minimum)) }
        if [.topLeft,.top,.topRight].contains(handle) { y1 = max(bounds.minY,min(y1+delta.y,y2-minimum)) }
        if [.bottomLeft,.bottom,.bottomRight].contains(handle) { y2 = min(bounds.maxY,max(y2+delta.y,y1+minimum)) }
        return CGRect(x:x1,y:y1,width:x2-x1,height:y2-y1)
    }

    static func rebased(_ points: [CGPoint], from previous: CGRect, to next: CGRect) -> [CGPoint] {
        points.map { CGPoint(x: $0.x + previous.minX - next.minX, y: $0.y + previous.minY - next.minY) }
    }

    static func pixels(for selection: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let x=imageSize.width/viewSize.width,y=imageSize.height/viewSize.height
        let rect=CGRect(x:floor(selection.minX*x),y:floor(selection.minY*y),width:ceil(selection.maxX*x)-floor(selection.minX*x),height:ceil(selection.maxY*y)-floor(selection.minY*y))
            .intersection(CGRect(origin:.zero,size:imageSize))
        return rect.isNull || rect.width < 1 || rect.height < 1 ? nil : rect
    }
}
