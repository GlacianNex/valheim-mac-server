import AppKit

/// AppKit has no enabled property on NSTabViewItem; pair disabled drawing with the selection delegate.
final class PingTabItem: NSTabViewItem {
    var available = false
    override func drawLabel(_ shouldTruncateLabel: Bool, in tabRect: NSRect) {
        guard !available else { super.drawLabel(shouldTruncateLabel, in: tabRect); return }
        let style: [NSAttributedString.Key:Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.disabledControlTextColor]
        let size = (label as NSString).size(withAttributes: style)
        (label as NSString).draw(at: NSPoint(x:tabRect.midX-size.width/2,y:tabRect.midY-size.height/2),withAttributes:style)
    }
}
final class PlayerPingGraphs: NSView {
    private let help = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let document = NSView()
    private(set) var charts: [String:LiveMetricChart] = [:]
    private var order: [String] = []
    override init(frame: NSRect) {
        super.init(frame:frame)
        help.font = .systemFont(ofSize:11); addSubview(help)
        scroll.hasVerticalScroller = true; scroll.documentView = document; addSubview(scroll)
    }
    convenience init() { self.init(frame:NSRect(x:0,y:0,width:560,height:525)) }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        help.frame = NSRect(x:20,y:bounds.height-67,width:bounds.width-40,height:55)
        scroll.frame = NSRect(x:20,y:15,width:bounds.width-40,height:max(0,bounds.height-90))
        let width = scroll.contentSize.width
        let height = max(scroll.contentSize.height,CGFloat(order.count)*170)
        document.frame = NSRect(x:0,y:0,width:width,height:height)
        for (i,id) in order.enumerated() { charts[id]?.frame = NSRect(x:0,y:height-CGFloat(i+1)*170+10,width:width,height:160) }
    }
    func update(reading: ManagementReading?, samples: [LiveMetricSample]) {
        let players = reading?.onlinePlayers ?? []
        help.stringValue = reading == nil ? "Server offline or management tools unavailable." : reading?.pingSupported != true ? "Ping readings unavailable. Restart with updated management tools; crossplay must be disabled." : players.isEmpty ? "No players connected. Graphs appear when Steam players join." : "Steam connection ping in milliseconds, sampled once per second. Last hour of history is collected while this window is closed. Missing readings and disconnects leave gaps."
        let visible = reading?.pingSupported == true ? players : []
        let ids = Set(visible.map(\.id))
        for id in Array(charts.keys) where !ids.contains(id) { charts.removeValue(forKey:id)?.removeFromSuperview() }
        order = visible.sorted { ($0.name,$0.id) < ($1.name,$1.id) }.map(\.id)
        for player in visible {
            let chart = charts[player.id] ?? LiveMetricChart()
            if charts[player.id] == nil { charts[player.id] = chart; document.addSubview(chart) }
            chart.title = player.name + " · " + player.id; chart.unit = "ms"
            chart.toolTip = "Steam connection ping to \(player.name) (\(player.id)). Missing values are not treated as zero."
            chart.emptyMessage = "Waiting for Steam ping measurements"
            chart.points = samples.map { ($0.time,$0.pings[player.id]) }
        }
        needsLayout = true
    }
}
