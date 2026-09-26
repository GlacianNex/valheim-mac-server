import AppKit
import ServerCore

final class RestartScheduleEditor: NSObject {
    let view = NSView(frame: NSRect(x:0,y:0,width:560,height:420))
    private let enabled = NSButton(checkboxWithTitle: "Scheduled restart", target: nil, action: nil)
    private let frequency = NSPopUpButton()
    private let interval = NSTextField(string: "2")
    private let time = NSDatePicker()
    private let players = NSPopUpButton()
    private var days: [NSButton] = []
    private let next = NSTextField(wrappingLabelWithString: "")
    private let error = NSTextField(wrappingLabelWithString: "")
    private var value: RestartSchedule
    private let save: (RestartSchedule) throws -> Void
    init(schedule: RestartSchedule, save: @escaping (RestartSchedule) throws -> Void) {
        value = schedule; self.save = save
        super.init()
        func label(_ text: String, _ y: CGFloat) { let l = NSTextField(labelWithString:text); l.frame = NSRect(x:24,y:y,width:150,height:24); view.addSubview(l) }
        enabled.frame = NSRect(x:24,y:375,width:250,height:24); enabled.state = schedule.enabled ? .on : .off; view.addSubview(enabled)
        label("Frequency",330); frequency.frame = NSRect(x:180,y:325,width:240,height:30)
        frequency.addItems(withTitles:["Every day", "Every N days", "Selected weekdays"]); frequency.selectItem(at:RestartSchedule.Frequency.allCases.firstIndex(of:schedule.frequency)!)
        view.addSubview(frequency)
        label("Number of days",290); interval.frame = NSRect(x:180,y:290,width:60,height:24); interval.stringValue = String(schedule.everyDays); view.addSubview(interval)
        let names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        for i in 0..<7 { let b = NSButton(checkboxWithTitle:names[i],target:nil,action:nil); b.frame = NSRect(x:24+i*73,y:250,width:72,height:24); b.state = schedule.weekdays.contains(i+1) ? .on : .off; days.append(b); view.addSubview(b) }
        label("Local time",208); time.frame = NSRect(x:180,y:208,width:135,height:25); time.datePickerElements = [.hourMinute]; time.datePickerStyle = .textFieldAndStepper
        time.dateValue = Calendar.current.date(bySettingHour:schedule.hour,minute:schedule.minute,second:0,of:Date()) ?? Date(); view.addSubview(time)
        label("Players online",165); players.frame = NSRect(x:180,y:160,width:350,height:30)
        players.addItems(withTitles:["Warn at 15, 10, 5 and 1 minute", "Skip this restart", "Wait until the server is empty"])
        players.selectItem(at:RestartSchedule.Players.allCases.firstIndex(of:schedule.players)!); view.addSubview(players)
        next.frame = NSRect(x:24,y:90,width:512,height:65); view.addSubview(next)
        error.frame = NSRect(x:24,y:50,width:390,height:40); error.textColor = .systemRed; view.addSubview(error)
        let button = NSButton(title:"Save",target:self,action:#selector(saveClicked)); button.frame = NSRect(x:435,y:20,width:100,height:32); view.addSubview(button)
        for control: NSControl in [enabled,frequency,interval,time,players] + days { control.target = self; control.action = #selector(changed) }
        changed()
    }
    private func read() -> RestartSchedule {
        var s = value; s.enabled = enabled.state == .on; s.frequency = RestartSchedule.Frequency.allCases[frequency.indexOfSelectedItem]
        s.everyDays = Int(interval.stringValue) ?? 0; s.weekdays = Set(days.indices.filter { days[$0].state == .on }.map { $0+1 })
        s.hour = Calendar.current.component(.hour,from:time.dateValue); s.minute = Calendar.current.component(.minute,from:time.dateValue)
        s.players = RestartSchedule.Players.allCases[players.indexOfSelectedItem]; return s
    }
    @objc private func changed() {
        let s = read(); interval.isEnabled = s.frequency == .interval
        days.forEach { $0.isEnabled = s.frequency == .weekdays }
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        next.stringValue = (s.next(after:Date()).map { "Next: " + formatter.string(from:$0) + " (" + TimeZone.current.identifier + ")\n" } ?? "Schedule disabled.\n") + "Keep the manager open for scheduled restarts. Stopped servers stay stopped."
    }
    @objc private func saveClicked() {
        do { let s = read(); try s.validate(); try save(s); value = s; error.textColor = .secondaryLabelColor; error.stringValue = "Schedule saved."; changed() }
        catch { self.error.textColor = .systemRed; self.error.stringValue = error.localizedDescription }
    }
}

final class RestartScheduleWindow: NSObject {
    let window: NSWindow
    private let editor: RestartScheduleEditor
    init(name: String, schedule: RestartSchedule, save: @escaping (RestartSchedule) throws -> Void) {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:420), styleMask:[.titled,.closable],backing:.buffered,defer:false)
        self.window = window
        editor = RestartScheduleEditor(schedule:schedule) { value in try save(value); window.close() }
        super.init()
        window.title = name + " — Scheduled Restart"; window.isReleasedWhenClosed = false
        window.contentView = editor.view
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
}
