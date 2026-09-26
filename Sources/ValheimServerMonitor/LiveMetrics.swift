import AppKit

struct OnlinePlayer: Decodable {
    let name: String
    let id: String
}
struct ManagementReading: Decodable {
    let version: String
    let players: Int
    let fps: Double
    let managedMemoryBytes: Double
    let uptimeSeconds: Double
    let onlinePlayers: [OnlinePlayer]?
    let banned: [String]?
}
struct LiveMetricSample {
    let time: Date
    let fps: Double?
    let memory: Double?
}
final class LiveMetricChart: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var unit = ""
    var points: [(Date,Double?)] = [] { didSet { needsDisplay = true } }
    var emptyMessage = "Waiting for live readings"
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect:bounds,xRadius:6,yRadius:6).fill()
        let labelStyle: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor.secondaryLabelColor]
        func text(_ value:String, at origin:NSPoint, style:[NSAttributedString.Key:Any]? = nil) {
            (value as NSString).draw(at:origin,withAttributes:style ?? labelStyle)
        }
        text(title,at:NSPoint(x:10,y:bounds.height-20),style:[.font:NSFont.systemFont(ofSize:11,weight:.semibold),.foregroundColor:NSColor.labelColor])
        let valid = points.compactMap { $0.1 }.filter { $0.isFinite && $0 >= 0 }
        let current = points.last.flatMap { sample -> Double? in
            guard Date().timeIntervalSince(sample.0) <= 3, let value = sample.1, value.isFinite, value >= 0 else { return nil }; return value
        }
        text(current.map { String(format:"%.1f",$0) + " " + unit + " · last hour · 1-second samples" } ?? "Unavailable · waiting for live readings",at:NSPoint(x:10,y:bounds.height-36))
        let end = Date()
        // A fixed one-hour window makes histories comparable across servers.
        let duration: Double = 3600
        let start = end.addingTimeInterval(-duration)
        let rawStep = max((valid.max() ?? 1)*1.1,1)/4
        let magnitude = pow(10,floor(log10(rawStep)))
        let normalized = rawStep/magnitude
        let step = ([1.0,2,2.5,5,10].first { $0 >= normalized } ?? 10)*magnitude
        let maximum = step*4
        func number(_ value:Double) -> String {
            String(format:step < 1 ? "%.2f" : step.rounded() != step ? "%.1f" : "%.0f",value)
        }
        let widest = (number(maximum) as NSString).size(withAttributes:labelStyle).width
        let rect = NSRect(x:max(42,widest+16),y:25,width:bounds.width-max(42,widest+16)-28,height:bounds.height-72)
        for index in 0...4 {
            let y = rect.minY+CGFloat(index)*rect.height/4
            NSColor.separatorColor.setStroke()
            let grid = NSBezierPath(); grid.lineWidth = 0.5
            grid.move(to:NSPoint(x:rect.minX,y:y)); grid.line(to:NSPoint(x:rect.maxX,y:y)); grid.stroke()
            let value = number(Double(index)*step)
            let width = (value as NSString).size(withAttributes:labelStyle).width
            text(value,at:NSPoint(x:rect.minX-width-8,y:y-6))
        }
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        for index in 0...3 {
            let x = rect.minX+CGFloat(index)*rect.width/3
            NSColor.separatorColor.setStroke()
            let grid = NSBezierPath(); grid.lineWidth = 0.5
            grid.move(to:NSPoint(x:x,y:rect.minY)); grid.line(to:NSPoint(x:x,y:rect.maxY)); grid.stroke()
            let label = formatter.string(from:start.addingTimeInterval(duration*Double(index)/3))
            let width = (label as NSString).size(withAttributes:labelStyle).width
            text(label,at:NSPoint(x:min(bounds.width-width-5,max(5,x-width/2)),y:5))
        }
        guard !valid.isEmpty else {
            text(emptyMessage,at:NSPoint(x:rect.minX+8,y:rect.midY)); return
        }
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:rect).addClip()
        let line = NSBezierPath(); line.lineWidth = 2; line.lineJoinStyle = .round
        var previous: Date?
        for (time,value) in points {
            guard time >= start, let value, value.isFinite, value >= 0 else { previous = nil; continue }
            let point = NSPoint(x:rect.minX+time.timeIntervalSince(start)/duration*rect.width,y:rect.minY+value/maximum*rect.height)
            if let last = previous, time.timeIntervalSince(last) <= 3 { line.line(to:point) }
            else { line.move(to:point) }
            previous = time
        }
        NSColor.systemBlue.setStroke(); line.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class ManagementPlayerList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSScrollView()
    let table = NSTableView()
    var rows: [(id:String,name:String)] = []
    var changed: (() -> Void)?
    var selectedID: String? { rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id : nil }
    init(banned: Bool = false) {
        super.init()
        for (id,title,width) in banned ? [("id","Banned player / platform ID",490.0)] : [("name","Player",200.0),("id","Platform ID",305.0)] {
            let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width; table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.allowsMultipleSelection = false; table.usesAlternatingRowBackgroundColors = true
        view.documentView = table; view.hasVerticalScroller = true; view.borderType = .bezelBorder
    }
    func update(_ rows: [(id:String,name:String)]) {
        let selected = selectedID; self.rows = rows; table.reloadData()
        if let selected, let i = rows.firstIndex(where:{$0.id == selected}) { table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false) }
        else { table.deselectAll(nil) }
        changed?()
    }
    func numberOfRows(in tableView:NSTableView) -> Int { rows.count }
    func tableView(_ tableView:NSTableView, viewFor column:NSTableColumn?, row:Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let v = rows[row]
        let field = NSTextField(labelWithString:column?.identifier.rawValue == "name" ? v.name : v.id)
        field.lineBreakMode = .byTruncatingMiddle; field.toolTip = field.stringValue; return field
    }
    func tableViewSelectionDidChange(_ notification:Notification) { changed?() }
}

enum ManagementHelp {
    static let automaticUpdates = "Installs the latest stable version of the official Valheim dedicated server from Valve. This updates the game server, not the Server Manager app or third-party mods.\n\nChecks every 10 minutes while the manager is open. All servers share this installation, so this setting applies to every server.\n\nPlayers receive warnings at 15, 10, 5 and 1 minute. The manager saves, stops, updates and restarts the servers that were running. Without working management tools, updates wait until all running servers are confirmed empty."
}
