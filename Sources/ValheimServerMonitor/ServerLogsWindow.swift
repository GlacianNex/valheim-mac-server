import AppKit
import SwiftUI
import ServerCore

private final class ServerLogsModel: ObservableObject {
    @Published var server = ""
    @Published var manager = ""
    @Published var loading = true
    var reading = false
    func refresh(paths:Paths) {
        guard !reading else { return }; reading = true
        DispatchQueue.global(qos:.utility).async {
            let server = LogViewer.read(paths:paths,manager:false)
            let manager = LogViewer.read(paths:paths,manager:true)
            DispatchQueue.main.async {
                if self.server != server { self.server = server }
                if self.manager != manager { self.manager = manager }
                self.loading = false; self.reading = false
            }
        }
    }
}
private struct ServerLogsView: View {
    @ObservedObject var model:ServerLogsModel
    let paths:Paths
    let close:() -> Void
    @State private var manager = false
    @State private var filter = ""
    @State private var autoScroll = true
    @State private var wrapText = true
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("Server Logs").font(.title2.bold()); Spacer(); Button("Done",action:close) }
            Picker("Log",selection:$manager) {
                Text("Server").tag(false)
                Text("Manager Activity").tag(true)
            }.pickerStyle(.segmented)
            TextField("Filter log lines",text:$filter)
            HStack(spacing:16) {
                Toggle("Auto-scroll",isOn:$autoScroll).toggleStyle(.checkbox)
                    .help("Follow new log lines at the bottom. Turn off to read earlier lines.")
                Toggle("Wrap Text",isOn:$wrapText).toggleStyle(.checkbox)
                    .help("Wrap long log lines to fit the window.")
                Spacer()
            }
            LogTextPane(text:displayed,wrap:wrapText,follow:autoScroll)
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            HStack {
                Text("Latest 256 KB per log view · refreshes every second").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open Log Folder") { NSWorkspace.shared.open(manager ? paths.root.appendingPathComponent("logs") : paths.logs) }
            }
        }.padding(20).frame(minWidth:720,minHeight:440)
    }
    private var displayed:String {
        if model.loading { return "Loading logs…" }
        let source = manager ? model.manager : model.server
        let text = LogViewer.readable(source,filter:filter)
        if !text.isEmpty { return text }
        return !filter.isEmpty ? "No matching log lines." : manager ? "No manager activity recorded yet." : "No server log yet. Start the server to create one."
    }
}
// The gutter is drawn separately; NSTextView selection/copy contains only log text.
private struct LogTextPane:NSViewRepresentable {
    let text:String
    let wrap:Bool
    let follow:Bool
    func makeNSView(context:Context) -> LogTextScrollView { LogTextScrollView() }
    func updateNSView(_ view:LogTextScrollView,context:Context) {
        view.update(text:text,wrap:wrap,follow:follow)
    }
}
final class LogTextScrollView:NSScrollView {
    let logText = NSTextView(frame:.zero)
    private var wrapping = true
    private var following = false
    override init(frame:NSRect) {
        super.init(frame:frame)
        hasVerticalScroller = true; borderType = .bezelBorder
        logText.isEditable = false; logText.isSelectable = true; logText.isRichText = false
        logText.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        logText.textColor = .textColor; logText.backgroundColor = .textBackgroundColor
        logText.textContainerInset = NSSize(width:8,height:8)
        logText.minSize = .zero
        logText.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        logText.isVerticallyResizable = true
        documentView = logText
        let gutter = LogLineRuler(scrollView:self,orientation:.verticalRuler)
        gutter.clientView = logText; gutter.ruleThickness = 56
        verticalRulerView = gutter; hasVerticalRuler = true; rulersVisible = true
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self,selector:#selector(scrolled),name:NSView.boundsDidChangeNotification,object:contentView)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func scrolled() { verticalRulerView?.needsDisplay = true }
    override func tile() {
        super.tile()
        if wrapping {
            logText.setFrameSize(NSSize(width:contentSize.width,height:logText.frame.height))
            logText.textContainer?.containerSize = NSSize(width:contentSize.width,height:CGFloat.greatestFiniteMagnitude)
        }
        verticalRulerView?.needsDisplay = true
    }
    func update(text:String,wrap:Bool,follow:Bool) {
        let changed = logText.string != text
        let shouldFollow = follow && (changed || !following || wrapping != wrap)
        let origin = contentView.bounds.origin
        let selection = logText.selectedRange()
        wrapping = wrap; following = follow
        hasHorizontalScroller = !wrap
        logText.isHorizontallyResizable = !wrap
        logText.autoresizingMask = wrap ? [.width] : []
        logText.textContainer?.widthTracksTextView = wrap
        logText.textContainer?.containerSize = NSSize(width:wrap ? contentSize.width : CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        if changed {
            logText.string = text
            let count = (text as NSString).length
            let start = min(selection.location,count)
            logText.setSelectedRange(NSRange(location:start,length:min(selection.length,count-start)))
        }
        tile()
        logText.layoutManager?.ensureLayout(for:logText.textContainer!)
        logText.sizeToFit()
        if shouldFollow && selection.length == 0 {
            logText.scrollRangeToVisible(NSRange(location:(text as NSString).length,length:0))
        } else if changed {
            contentView.scroll(to:origin); reflectScrolledClipView(contentView)
        }
        verticalRulerView?.needsDisplay = true
    }
}
private final class LogLineRuler:NSRulerView {
    override func drawHashMarksAndLabels(in rect:NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        guard let textView = clientView as? NSTextView,
              let layout = textView.layoutManager else { return }
        let source = textView.string as NSString
        let attributes:[NSAttributedString.Key:Any] = [
            .font:NSFont.monospacedSystemFont(ofSize:12,weight:.regular),
            .foregroundColor:NSColor.secondaryLabelColor
        ]
        var offset = 0, number = 1
        while offset < source.length {
            let glyph = layout.glyphIndexForCharacter(at:offset)
            let fragment = layout.lineFragmentRect(forGlyphAt:glyph,effectiveRange:nil)
            let point = convert(NSPoint(x:0,y:fragment.minY + textView.textContainerOrigin.y),from:textView)
            if point.y > bounds.maxY { break }
            if point.y + fragment.height >= bounds.minY {
                let label = String(number) as NSString
                label.draw(at:NSPoint(x:ruleThickness - label.size(withAttributes:attributes).width - 8,y:point.y),withAttributes:attributes)
            }
            offset = NSMaxRange(source.lineRange(for:NSRange(location:offset,length:0)))
            number += 1
        }
    }
}
final class ServerLogsWindow:NSObject, NSWindowDelegate {
    let window:NSWindow
    private let paths:Paths
    private let model = ServerLogsModel()
    private var timer:Timer?
    init(paths:Paths,name:String) {
        self.paths = paths
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:920,height:620),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        super.init()
        window.title = name + " — Server Logs"; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentView = NSHostingView(rootView:ServerLogsView(model:model,paths:paths,close:{ [weak self] in self?.window.close() }))
        window.center()
    }
    func show() {
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        model.refresh(paths:paths)
        guard timer == nil else { return }
        let poll = Timer(timeInterval:1,repeats:true) { [weak self] _ in
            guard let self else { return }; self.model.refresh(paths:self.paths)
        }
        timer = poll; RunLoop.main.add(poll,forMode:.common)
    }
    func windowWillClose(_ notification:Notification) { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
