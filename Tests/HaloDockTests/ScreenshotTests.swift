import AppKit
import Testing
@testable import HaloDock

@Test func selectionCanBeAdjustedWithinScreen() throws {
    let bounds=CGRect(x:0,y:0,width:800,height:600)
    let selected=ScreenshotGeometry.selection(from:CGPoint(x:500,y:400),to:CGPoint(x:-20,y:30),in:bounds)
    #expect(selected==CGRect(x:0,y:30,width:500,height:370))
    let moved=ScreenshotGeometry.moved(selected,by:CGPoint(x:1000,y:1000),in:bounds)
    #expect(moved==CGRect(x:300,y:230,width:500,height:370))
    for handle in ScreenshotGeometry.Handle.allCases {
        let r=ScreenshotGeometry.resized(CGRect(x:100,y:100,width:200,height:160),handle:handle,by:CGPoint(x:1000,y:-1000),in:bounds)
        #expect(bounds.contains(r))
        #expect(r.width>=8 && r.height>=8)
    }
}

@Test func retinaCropUsesPixelDimensions() {
    let rect=ScreenshotGeometry.pixels(for:CGRect(x:10.25,y:20.5,width:100.5,height:50.25),viewSize:CGSize(width:800,height:600),imageSize:CGSize(width:1600,height:1200))
    #expect(rect==CGRect(x:20,y:41,width:202,height:101))
    #expect(ScreenshotGeometry.pixels(for:.zero,viewSize:.zero,imageSize:CGSize(width:100,height:100))==nil)
}

private func fixture(width:Int=100,height:Int=80) throws -> CGImage {
    var bytes=[UInt8](repeating:255,count:width*height*4)
    for y in 0..<height { for x in 0..<width {
        let i=(y*width+x)*4
        if y<height/2 {bytes[i]=255;bytes[i+1]=255;bytes[i+2]=255}
        else {bytes[i]=0;bytes[i+1]=0;bytes[i+2]=255}
    }}
    let provider=try #require(CGDataProvider(data:Data(bytes) as CFData))
    return try #require(CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
}

private func pixel(_ image:CGImage,x:Int,y:Int) throws -> [UInt8] {
    let bytes=try #require(image.dataProvider?.data) as Data
    let index=y*image.bytesPerRow+x*4
    return Array(bytes[index..<index+4])
}

@Test @MainActor func editingPreservesOrientationAndSupportsUndo() throws {
    let source=try fixture()
    let document=ScreenshotDocument(image:source)
    let original=try #require(document.renderedImage())
    #expect(original.width==100 && original.height==80)
    #expect(try pixel(original,x:25,y:10).prefix(3)==[255,255,255])
    #expect(try pixel(original,x:25,y:70).prefix(3)==[0,0,255])
    document.add(ScreenshotAnnotation(tool:.rectangle,points:[CGPoint(x:10,y:10),CGPoint(x:30,y:25)],color:.red,width:4))
    let annotated=try #require(document.renderedImage())
    #expect(try pixel(annotated,x:10,y:15).prefix(3)==[255,0,0])
    #expect(try pixel(annotated,x:10,y:65).prefix(3)==[0,0,255])
    document.undo();#expect(document.annotations.isEmpty && document.redoItems.count==1)
    document.redo();#expect(document.annotations.count==1 && document.redoItems.isEmpty)
    let data=try #require(document.pngData())
    let decoded=try #require(NSBitmapImageRep(data:data))
    #expect(decoded.pixelsWide==100 && decoded.pixelsHigh==80)
}

@Test func adjustingCropPreservesAnnotationScreenPosition() {
    let points = [CGPoint(x:5,y:5), CGPoint(x:20,y:30)]
    let old = CGRect(x:100,y:100,width:50,height:50)
    let next = CGRect(x:80,y:90,width:100,height:100)
    #expect(ScreenshotGeometry.rebased(points,from:old,to:next)==[CGPoint(x:25,y:15),CGPoint(x:40,y:40)])
}

@Test @MainActor func wakeIconUsesFixedColorInsteadOfTemplateTint() {
    let normal=HaloDockBrand.image()
    let awake=HaloDockBrand.image(color:NSColor(calibratedRed:0.95,green:0.33,blue:0.20,alpha:1))
    #expect(normal.isTemplate)
    #expect(!awake.isTemplate)
    #expect(normal.size==awake.size)
}
