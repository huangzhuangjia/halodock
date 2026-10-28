import AppKit
import Combine

/// One overlay owns selection and editing; the user never leaves the captured screen.
@MainActor
final class ScreenshotSelectionView: NSView, NSTextFieldDelegate {
    let image: CGImage
    var onCancel: (() -> Void)?
    var onPin: ((CGImage, CGPoint) -> Bool)?
    var onExtendedCapture: ((ExtendedCaptureSession.Mode, CGRect, CGImage) -> Void)?
    private var recognitionTask: Task<Void, Never>?
    private let recognitionPanel = NSVisualEffectView()
    private let recognizedText = NSTextView()
    private let recognizeButton = NSButton()
    private(set) var selection: CGRect?
    private var document: ScreenshotDocument?
    private var pixelRect: CGRect?
    private var observation: AnyCancellable?
    private var origin=CGPoint.zero
    private var originalSelection=CGRect.zero
    private enum Drag {case create,move,resize(ScreenshotGeometry.Handle)}
    private var dragging:Drag = .create
    private var adjusting=true
    private var draft:ScreenshotAnnotation?
    private var feedback:String?
    private var textField:NSTextField?
    private var textPoint:CGPoint?
    private let actionBar=NSVisualEffectView()
    private let stack=NSStackView()
    private var toolButtons:[NSButton]=[]
    private let undoButton=NSButton()
    private let redoButton=NSButton()
    private let stroke=NSSegmentedControl(labels:["细","中","粗"],trackingMode:.selectOne,target:nil,action:nil)
    private let palette:[NSColor]=[.systemRed,.systemYellow,.systemBlue,.white]
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}

    init(frame:CGRect,image:CGImage) {
        self.image=image
        super.init(frame:frame)
        configureToolbar()
        setAccessibilityLabel("截图选区与编辑画布；拖动选择范围，底部直接标注、复制或保存，Escape 取消。")
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}

    private func configureToolbar() {
        actionBar.material = .hudWindow
        actionBar.blendingMode = .withinWindow
        actionBar.state = .active
        actionBar.appearance=NSAppearance(named:.darkAqua)
        actionBar.wantsLayer=true
        actionBar.layer?.cornerRadius=13
        actionBar.isHidden=true
        stack.orientation = .vertical
        let tools = NSStackView()
        let actions = NSStackView()
        tools.orientation = .horizontal; tools.spacing = 6
        actions.orientation = .horizontal; actions.spacing = 8
        stack.addArrangedSubview(tools)
        stack.addArrangedSubview(actions)
        let cards = NSStackView()
        cards.spacing = 8
        for (title, action) in [("加入工作台…", #selector(collectScreenshot(_:))), ("滚动截图", #selector(startScrollCapture)), ("录制 GIF", #selector(startGIFCapture))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded; button.controlSize = .small
            button.toolTip = title == "加入工作台…" ? "保存当前截图及标注到本机工作台" : "捕获当前选区的原始画面，截图标注不会加入录制"
            cards.addArrangedSubview(button)
        }
        stack.addArrangedSubview(cards)
        stack.spacing=6
        stack.edgeInsets=NSEdgeInsets(top:8,left:10,bottom:8,right:10)
        let icons=["crop","pencil.tip","rectangle","arrow.up.right","textformat"]
        let names=["调整选区","画笔（1）","矩形（2）","箭头（3）","文字（4）"]
        for index in icons.indices {
            let button=iconButton(icons[index],label:names[index],action:#selector(chooseTool(_:)))
            button.tag=index
            button.setButtonType(.pushOnPushOff)
            toolButtons.append(button)
            tools.addArrangedSubview(button)
        }
        for index in palette.indices {
            let button=NSButton(title:"●",target:self,action:#selector(chooseColor(_:)))
            button.tag=index
            button.isBordered=false
            button.font = .systemFont(ofSize:23)
            button.contentTintColor=palette[index]
            button.toolTip=["红色","黄色","蓝色","白色"][index]
            button.setAccessibilityLabel(button.toolTip)
            button.widthAnchor.constraint(equalToConstant:25).isActive=true
            tools.addArrangedSubview(button)
        }
        stroke.target=self;stroke.action=#selector(changeStroke(_:));stroke.selectedSegment=1
        stroke.controlSize = .small
        stroke.toolTip="标注粗细"
        stroke.setAccessibilityLabel("标注粗细")
        tools.addArrangedSubview(stroke)
        configure(undoButton,icon:"arrow.uturn.backward",label:"撤销 ⌘Z",action:#selector(undoAnnotation))
        configure(redoButton,icon:"arrow.uturn.forward",label:"重做 ⇧⌘Z",action:#selector(redoAnnotation))
        actions.addArrangedSubview(undoButton);actions.addArrangedSubview(redoButton)
        configure(recognizeButton, icon: "text.viewfinder", label: "提取文字（本机识别）", action: #selector(recognizeText))
        actions.addArrangedSubview(recognizeButton)
        actions.addArrangedSubview(iconButton("pin", label: "贴到桌面置顶", action: #selector(pinScreenshot)))
        for (title,action) in [("复制",#selector(copyScreenshot)),("保存",#selector(saveScreenshot))] {
            let button=NSButton(title:title,target:self,action:action)
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.font = .systemFont(ofSize:12,weight:.semibold)
            actions.addArrangedSubview(button)
        }
        actions.addArrangedSubview(iconButton("xmark",label:"取消截图（Esc）",action:#selector(cancelCapture)))
        actionBar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:actionBar.leadingAnchor),stack.trailingAnchor.constraint(equalTo:actionBar.trailingAnchor),stack.topAnchor.constraint(equalTo:actionBar.topAnchor),stack.bottomAnchor.constraint(equalTo:actionBar.bottomAnchor)])
        addSubview(actionBar)
        configureRecognitionPanel()
        updateToolbar()
    }
    private func iconButton(_ icon:String,label:String,action:Selector) -> NSButton {
        let button=NSButton();configure(button,icon:icon,label:label,action:action);return button
    }
    private func configure(_ button:NSButton,icon:String,label:String,action:Selector) {
        button.image=NSImage(systemSymbolName:icon,accessibilityDescription:label)
        button.imagePosition = .imageOnly
        button.bezelStyle = .rounded
        button.target=self;button.action=action;button.toolTip=label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant:30).isActive=true
    }
    private func updateToolbar() {
        for (index,button) in toolButtons.enumerated() {
            let active=index==0 ? adjusting : !adjusting && document?.tool==ScreenshotAnnotation.Tool.allCases[index-1]
            button.contentTintColor=active ? .systemOrange:.white
            button.state=active ? .on:.off
        }
        undoButton.isEnabled=document?.annotations.isEmpty==false
        redoButton.isEnabled=document?.redoItems.isEmpty==false
    }
    override func resetCursorRects() {addCursorRect(bounds,cursor:.crosshair)}
    override func draw(_ dirtyRect:NSRect) {
        NSImage(cgImage:image,size:bounds.size).draw(in:bounds,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
        let shade=NSBezierPath(rect:bounds)
        if let selection {shade.appendRect(selection)}
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill();shade.fill()
        guard let selection else {
            drawBadge("拖动选取区域 · 松手即可编辑 · Esc 取消",at:CGPoint(x:max(16,bounds.midX-170),y:36))
            return
        }
        if !actionBar.isHidden,let document {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:selection).addClip()
            let transform=NSAffineTransform()
            transform.translateX(by:selection.minX,yBy:selection.minY)
            transform.scaleX(by:selection.width/document.size.width,yBy:selection.height/document.size.height)
            transform.concat()
            for annotation in document.annotations {ScreenshotDrawing.draw(annotation)}
            if let draft {ScreenshotDrawing.draw(draft)}
            NSGraphicsContext.restoreGraphicsState()
        }
        let border=NSBezierPath(rect:selection);border.lineWidth=1.5;NSColor.controlAccentColor.setStroke();border.stroke()
        if adjusting {
            for handle in ScreenshotGeometry.Handle.allCases {
                let point=ScreenshotGeometry.point(for:handle,in:selection)
                let knob=NSBezierPath(roundedRect:CGRect(x:point.x-4,y:point.y-4,width:8,height:8),xRadius:2,yRadius:2)
                NSColor.white.setFill();knob.fill();NSColor.controlAccentColor.setStroke();knob.lineWidth=1;knob.stroke()
            }
        }
        if let pixels=ScreenshotGeometry.pixels(for:selection,viewSize:bounds.size,imageSize:CGSize(width:image.width,height:image.height)) {
            drawBadge("\(Int(pixels.width)) × \(Int(pixels.height)) px",at:CGPoint(x:min(selection.minX,max(12,bounds.width-185)),y:selection.minY>42 ? selection.minY-34 : selection.minY+12))
        }
        if let feedback,!actionBar.isHidden {drawBadge(feedback,at:CGPoint(x:actionBar.frame.minX+10,y:max(12,actionBar.frame.minY-26)))}
    }
    private func drawBadge(_ text:String,at point:CGPoint) {
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedSystemFont(ofSize:12,weight:.medium),.foregroundColor:NSColor.white]
        let size=(text as NSString).size(withAttributes:attrs)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect:CGRect(x:point.x-8,y:point.y-5,width:size.width+16,height:size.height+10),xRadius:7,yRadius:7).fill()
        (text as NSString).draw(at:point,withAttributes:attrs)
    }
    override func mouseDown(with event:NSEvent) {
        hideRecognition()
        commitText()
        window?.makeFirstResponder(self)
        origin=convert(event.locationInWindow,from:nil)
        if !adjusting,let selection,selection.contains(origin),let document {
            let point=imagePoint(origin)
            if document.tool == .text {beginText(at:origin,imagePoint:point)}
            else {draft=ScreenshotAnnotation(tool:document.tool,points:[point],color:document.color,width:document.lineWidth)}
            return
        }
        guard adjusting else {return}
        actionBar.isHidden=true
        if let selection {
            originalSelection=selection
            if let handle=ScreenshotGeometry.Handle.allCases.first(where:{let p=ScreenshotGeometry.point(for:$0,in:selection);return hypot(p.x-origin.x,p.y-origin.y)<12}) {dragging = .resize(handle)}
            else if selection.contains(origin) {dragging = .move}
            else {dragging = .create;self.selection=nil}
        } else {dragging = .create}
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        let current=convert(event.locationInWindow,from:nil)
        if !adjusting {
            guard var annotation=draft else {return}
            if annotation.tool == .pencil {annotation.points.append(imagePoint(current))}
            else {annotation.points=Array(annotation.points.prefix(1))+[imagePoint(current)]}
            draft=annotation;needsDisplay=true;return
        }
        let delta=CGPoint(x:current.x-origin.x,y:current.y-origin.y)
        switch dragging {
        case .create: selection=ScreenshotGeometry.selection(from:origin,to:current,in:bounds)
        case .move: selection=ScreenshotGeometry.moved(originalSelection,by:delta,in:bounds)
        case .resize(let handle): selection=ScreenshotGeometry.resized(originalSelection,handle:handle,by:delta,in:bounds)
        }
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        if !adjusting {
            if let draft,let first=draft.points.first,let last=draft.points.last,hypot(last.x-first.x,last.y-first.y)>2 || draft.points.count>3 {document?.add(draft)}
            draft=nil;needsDisplay=true;updateToolbar();return
        }
        guard let selection,selection.width>=8,selection.height>=8 else {self.selection=nil;document=nil;needsDisplay=true;return}
        rebuildDocument();positionActionBar();needsDisplay=true
    }
    private func rebuildDocument() {
        guard let selection,let pixels=ScreenshotGeometry.pixels(for:selection,viewSize:bounds.size,imageSize:CGSize(width:image.width,height:image.height)),pixels != pixelRect,
              let cropped=image.cropping(to:pixels) else {return}
        let old=document,previous=pixelRect
        let next=ScreenshotDocument(image:cropped)
        if let old,let previous {
            next.tool=old.tool;next.color=old.color;next.lineWidth=old.lineWidth
            for var annotation in old.annotations {
                annotation.points=ScreenshotGeometry.rebased(annotation.points,from:previous,to:pixels)
                next.add(annotation)
            }
        }
        document=next;pixelRect=pixels
        observation=next.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.needsDisplay=true;self?.updateToolbar() }
        }
        updateToolbar()
    }
    private func imagePoint(_ point:CGPoint) -> CGPoint {
        guard let selection,let document else {return .zero}
        let p=ScreenshotGeometry.clamped(point,to:selection)
        return CGPoint(x:(p.x-selection.minX)/selection.width*document.size.width,y:(p.y-selection.minY)/selection.height*document.size.height)
    }
    private func positionActionBar() {
        guard let selection else {return}
        let size=stack.fittingSize,width=min(bounds.width-24,max(460,size.width)),height=max(46,size.height)
        let x=min(max(12,selection.midX-width/2),bounds.width-width-12)
        var y=selection.maxY+14
        if y+height>bounds.height-12 {y=max(12,selection.minY-height-14)}
        actionBar.frame=CGRect(x:x,y:y,width:width,height:height)
        actionBar.isHidden=false
    }
    private func beginText(at local:CGPoint,imagePoint:CGPoint) {
        guard let selection,let document else {return}
        let width=min(260,selection.width),height:CGFloat=36
        let field=NSTextField(frame:CGRect(x:min(local.x,selection.maxX-width),y:min(local.y,selection.maxY-height),width:width,height:height))
        field.placeholderString="输入文字，回车确认"
        field.font = .systemFont(ofSize:16,weight:.medium)
        field.textColor=document.color
        field.delegate=self;field.target=self;field.action=#selector(commitText)
        field.bezelStyle = .roundedBezel
        textPoint=imagePoint;textField=field
        addSubview(field);window?.makeFirstResponder(field)
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy commandSelector:Selector) -> Bool {
        if commandSelector==#selector(NSResponder.insertNewline(_:)) {commitText();return true}
        if commandSelector==#selector(NSResponder.cancelOperation(_:)) {textField?.removeFromSuperview();textField=nil;textPoint=nil;window?.makeFirstResponder(self);return true}
        return false
    }
    @objc private func commitText() {
        guard let field=textField,let point=textPoint,let document else {return}
        let value=field.currentEditor()?.string ?? field.stringValue
        textField=nil;textPoint=nil;field.removeFromSuperview()
        if !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {document.add(ScreenshotAnnotation(tool:.text,points:[point],color:document.color,width:document.lineWidth,text:value))}
        window?.makeFirstResponder(self);needsDisplay=true
    }
    @objc private func chooseTool(_ sender:NSButton) {
        commitText();adjusting=sender.tag==0
        if sender.tag>0 {document?.tool=ScreenshotAnnotation.Tool.allCases[sender.tag-1]}
        window?.makeFirstResponder(self);needsDisplay=true;updateToolbar()
    }
    @objc private func chooseColor(_ sender:NSButton) {document?.color=palette[sender.tag]}
    @objc private func changeStroke(_ sender:NSSegmentedControl) {document?.lineWidth=[CGFloat(3),6,10][sender.selectedSegment]}
    @objc private func undoAnnotation() {document?.undo();needsDisplay=true;updateToolbar()}
    @objc private func redoAnnotation() {document?.redo();needsDisplay=true;updateToolbar()}
    @objc private func copyScreenshot() {
        commitText()
        if document?.copy()==true {onCancel?()}
        else {feedback="复制失败，请重试或保存 PNG";needsDisplay=true}
    }
    @objc private func saveScreenshot() {
        commitText()
        let level=window?.level;window?.level = .normal
        let saved=document?.save()==true
        if let level {window?.level=level}
        if saved {onCancel?()} else {
            window?.makeKeyAndOrderFront(nil)
            if let status=document?.status,status.hasPrefix("保存失败") || status.hasPrefix("无法生成") {feedback=status;needsDisplay=true}
        }
    }
    private func configureRecognitionPanel() {
        recognitionPanel.material = .hudWindow
        recognitionPanel.state = .active
        recognitionPanel.appearance = NSAppearance(named: .darkAqua)
        recognitionPanel.wantsLayer = true
        recognitionPanel.layer?.cornerRadius = 12
        recognitionPanel.isHidden = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        recognizedText.isEditable = true
        recognizedText.isRichText = false
        recognizedText.font = .systemFont(ofSize: 14)
        recognizedText.textColor = .white
        recognizedText.backgroundColor = .clear
        recognizedText.drawsBackground = false
        recognizedText.isVerticallyResizable = true
        recognizedText.isHorizontallyResizable = false
        recognizedText.minSize = CGSize(width: 0, height: 140)
        recognizedText.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        recognizedText.textContainer?.containerSize = CGSize(width: 396, height: CGFloat.greatestFiniteMagnitude)
        recognizedText.autoresizingMask = [.width]
        recognizedText.textContainer?.widthTracksTextView = true
        recognizedText.setAccessibilityLabel("识别结果，可选择、修改和复制文字")
        scroll.documentView = recognizedText
        let layout = NSStackView()
        layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 8
        let header = NSTextField(labelWithString: "提取文字 · 本机识别")
        header.textColor = .white
        let buttons = NSStackView()
        buttons.addArrangedSubview(NSButton(title: "复制全部", target: self, action: #selector(copyRecognizedText)))
        buttons.addArrangedSubview(NSButton(title: "Markdown", target: self, action: #selector(copyMarkdown)))
        buttons.addArrangedSubview(NSButton(title: "收集文字", target: self, action: #selector(collectText(_:))))
        buttons.addArrangedSubview(NSButton(title: "链接…", target: self, action: #selector(openRecognizedLink)))
        buttons.addArrangedSubview(NSButton(title: "收起", target: self, action: #selector(hideRecognition)))
        layout.addArrangedSubview(header); layout.addArrangedSubview(scroll); layout.addArrangedSubview(buttons)
        recognitionPanel.addSubview(layout)
        layout.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: recognitionPanel.leadingAnchor, constant: 12),
            layout.trailingAnchor.constraint(equalTo: recognitionPanel.trailingAnchor, constant: -12),
            layout.topAnchor.constraint(equalTo: recognitionPanel.topAnchor, constant: 12),
            layout.bottomAnchor.constraint(equalTo: recognitionPanel.bottomAnchor, constant: -12),
            scroll.widthAnchor.constraint(equalTo: layout.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 140)
        ])
        addSubview(recognitionPanel)
    }
    @objc private func recognizeText() {
        commitText()
        guard let document else { return }
        recognitionTask?.cancel()
        recognizeButton.isEnabled = false
        feedback = "正在本机识别文字…"; needsDisplay = true
        // OCR uses the selected source pixels, so arrows and notes cannot obscure text.
        let selectedImage = document.image
        recognitionTask = Task { @MainActor [weak self] in
            do {
                let text = try await ScreenshotTextRecognizer.recognize(selectedImage)
                guard let self, !Task.isCancelled, self.document === document else { return }
                self.recognizeButton.isEnabled = true
                guard !text.isEmpty else { self.feedback = "未识别到文字，可调整选区后重试"; self.needsDisplay = true; return }
                self.recognizedText.string = text
                let width = min(420, self.bounds.width - 24)
                let x = min(max(12, self.actionBar.frame.midX - width / 2), self.bounds.width - width - 12)
                let y = self.actionBar.frame.minY > 250 ? self.actionBar.frame.minY - 246 : min(self.bounds.height - 244, self.actionBar.frame.maxY + 10)
                self.recognitionPanel.frame = CGRect(x: x, y: max(12, y), width: width, height: 234)
                self.recognitionPanel.isHidden = false
                self.recognitionPanel.layoutSubtreeIfNeeded()
                self.recognizedText.frame.size.width = width - 24
                self.recognizedText.sizeToFit()
                self.feedback = "识别完成，可直接选择或修改文字"; self.needsDisplay = true
                self.window?.makeFirstResponder(self.recognizedText)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.recognizeButton.isEnabled = true
                self.feedback = "识别失败：" + error.localizedDescription; self.needsDisplay = true
            }
        }
    }
    @objc private func collectScreenshot(_ sender: NSButton) {
        commitText()
        guard let image = document?.renderedImage() else { return }
        WorkbenchDestinationPicker.show(in: sender, at: CGPoint(x: 0, y: sender.bounds.maxY)) { [weak self] id in
            _ = WorkbenchStore.shared.add(image: image, to: id)
            self?.feedback = WorkbenchStore.shared.message; self?.needsDisplay = true
        }
    }
    @objc private func collectText(_ sender: NSButton) {
        let text = recognizedText.string
        WorkbenchDestinationPicker.show(in: sender, at: CGPoint(x: 0, y: sender.bounds.maxY)) { [weak self] id in
            _ = WorkbenchStore.shared.add(text: text, title: "截图文字", to: id)
            self?.feedback = WorkbenchStore.shared.message; self?.needsDisplay = true
        }
    }
    @objc private func copyMarkdown() {
        let board = NSPasteboard.general
        board.clearContents()
        feedback = board.setString(ScreenshotActions.markdown(recognizedText.string), forType: .string) ? "Markdown 已复制" : "复制失败"
        needsDisplay = true
    }
    @objc private func openRecognizedLink() {
        let links = ScreenshotActions.links(in: recognizedText.string)
        guard !links.isEmpty else { feedback = "未识别到网页链接"; needsDisplay = true; return }
        let menu = NSMenu()
        for url in links {
            let item = NSMenuItem(title: String(url.absoluteString.prefix(100)), action: #selector(openLink(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 12, y: 36), in: recognitionPanel)
    }
    @objc private func openLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, ["https", "http"].contains(url.scheme) else { return }
        hideRecognition(); onCancel?(); NSWorkspace.shared.open(url)
    }
    @objc private func startScrollCapture() { startExtendedCapture(.scroll) }
    @objc private func startGIFCapture() { startExtendedCapture(.gif) }
    private func startExtendedCapture(_ mode: ExtendedCaptureSession.Mode) {
        commitText()
        guard let document, let selection, selection.width >= 40, selection.height >= 40 else { feedback = "请先选择至少 40 × 40 点的范围"; needsDisplay = true; return }
        guard let onExtendedCapture else { return }
        hideRecognition()
        onExtendedCapture(mode, selection, document.image)
    }
    @objc private func copyRecognizedText() {
        let board = NSPasteboard.general
        board.clearContents()
        feedback = board.setString(recognizedText.string, forType: .string) ? "文字已复制" : "复制失败，请重试"
        needsDisplay = true
    }
    @objc func hideRecognition() {
        recognitionTask?.cancel(); recognitionTask = nil
        recognizeButton.isEnabled = true
        recognitionPanel.isHidden = true
    }
    @objc private func pinScreenshot() {
        commitText()
        guard let image = document?.renderedImage(), let selection, let window else { return }
        let point = window.convertPoint(toScreen: CGPoint(x: selection.minX, y: bounds.height - selection.minY))
        if onPin?(image, point) == true { hideRecognition(); onCancel?() }
        else { feedback = "最多同时打开 8 张贴图，请先关闭一张"; needsDisplay = true }
    }
    @objc private func cancelCapture() {hideRecognition();textField?.removeFromSuperview();onCancel?()}
    override func cancelOperation(_ sender: Any?) {
        if !recognitionPanel.isHidden { hideRecognition(); window?.makeFirstResponder(self) }
        else { cancelCapture() }
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode==53 { if !recognitionPanel.isHidden { hideRecognition() } else { cancelCapture() };return}
        if event.keyCode==36 {copyScreenshot();return}
        let key=event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command) {
            if key=="c" {copyScreenshot();return}
            if key=="s" {saveScreenshot();return}
            if key=="z" {if event.modifierFlags.contains(.shift){redoAnnotation()}else{undoAnnotation()};return}
        }
        if let key,let index=Int(key),(1...4).contains(index) {chooseTool(toolButtons[index]);return}
        if adjusting,let selection {
            let step:CGFloat=event.modifierFlags.contains(.shift) ? 10:1
            let delta:CGPoint
            switch event.keyCode {
            case 123:delta=CGPoint(x:-step,y:0)
            case 124:delta=CGPoint(x:step,y:0)
            case 125:delta=CGPoint(x:0,y:step)
            case 126:delta=CGPoint(x:0,y:-step)
            default:super.keyDown(with:event);return
            }
            self.selection=ScreenshotGeometry.moved(selection,by:delta,in:bounds)
            rebuildDocument();positionActionBar();needsDisplay=true
        }
    }
}
