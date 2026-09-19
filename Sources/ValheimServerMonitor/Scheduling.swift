import AppKit
import ServerCore

extension AppDelegate {
    @objc func scheduleSettings(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let store = try? Store(paths:engine.paths), let db = try? store.load(),
              let profile = db.profiles.first(where:{$0.id == id}) else { return }
        scheduleWindow?.window.close()
        scheduleWindow = RestartScheduleWindow(name:profile.label, schedule:db.restartSchedules?[id] ?? RestartSchedule()) { [weak self] schedule in
            try store.update { db in
                if db.restartSchedules == nil { db.restartSchedules = [:] }
                db.restartSchedules?[id] = schedule
                db.restartReceipts?.removeValue(forKey:id)
            }
            self?.lastScheduleCheck = .distantPast; self?.refresh()
        }
    }
    func checkSchedules() {
        guard !busy, busyProfiles.isEmpty, !scheduleChecking,
              Date().timeIntervalSince(lastScheduleCheck) >= 5 else { return }
        scheduleChecking = true; lastScheduleCheck = Date()
        DispatchQueue.global(qos:.utility).async {
            var selected: (String, Date, RestartReceipt, RestartSchedule)?
            do {
                let store = try Store(paths:self.engine.paths), db = try store.load(), now = Date()
                for profile in db.profiles {
                    guard let schedule = db.restartSchedules?[profile.id], schedule.enabled,
                          let due = ScheduledRestartPolicy.candidate(schedule:schedule,now:now) else { continue }
                    let key = schedule.key(for:due), receipt = db.restartReceipts?[profile.id]
                    if receipt?.occurrence == key && receipt?.state != "waiting" { continue }
                    let paths = store.servicePaths(profile.id,database:db), lifecycle = Lifecycle(paths:paths)
                    let status = try lifecycle.status()
                    let bridge = ManagedServer(paths:paths)
                    let canWarn = status.state == "Online" && bridge.enabled && (try? bridge.connection().send("health"))?.hasPrefix("OK ManagerRcon") == true
                    let decision = ScheduledRestartPolicy.decide(schedule:schedule,receipt:receipt,now:now,running:status.running,players:status.state == "Online" ? Int(status.players) : nil,canWarn:canWarn)
                    var state: String?
                    switch decision {
                    case .none: break
                    case .waiting: state = "waiting"
                    case .skip(let reason):
                        state = "skipped"
                        try MaintenanceLog.write(paths:self.engine.paths,server:profile.id,message:"reason=scheduled skipped: " + reason)
                    case .run(let deadline): selected = (profile.id,deadline,RestartReceipt(occurrence:key,due:due,state:"requested"),schedule)
                    }
                    if let state, receipt?.occurrence != key || receipt?.state != state {
                        try store.update { db in
                            if db.restartReceipts == nil { db.restartReceipts = [:] }
                            db.restartReceipts?[profile.id] = RestartReceipt(occurrence:key,due:due,state:state)
                        }
                    }
                    if selected != nil { break }
                }
            } catch {
                try? MaintenanceLog.write(paths:self.engine.paths,server:"scheduler",message:error.localizedDescription)
            }
            DispatchQueue.main.async {
                self.scheduleChecking = false
                guard !self.busy, self.busyProfiles.isEmpty, let (id,deadline,receipt,configuration) = selected else { return }
                do {
                    guard try Store(paths:self.engine.paths).claimScheduledRestart(id:id,configuration:configuration,receipt:receipt) else { return }
                    self.beginServerUpdate(scheduledID:id,scheduledDeadline:deadline > Date() ? deadline : nil)
                } catch { self.lastScheduleCheck = .distantPast }
            }
        }
    }
}
