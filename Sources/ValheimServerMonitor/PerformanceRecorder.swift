import Foundation
import ServerCore

/// Owned by the menu-bar app, not by a management window. All state is main-thread confined.
final class PerformanceRecorder {
    private struct Series {
        var samples: [LiveMetricSample] = []
        var reading: ManagementReading?
        var updated = Date.distantPast
        var uptime: Double?
    }
    private var series: [String:Series] = [:]
    private var inFlight: Set<String> = []
    private var discovering = false
    private var timer: Timer?
    private let read: (Paths) throws -> ManagementReading

    init(read: @escaping (Paths) throws -> ManagementReading = { paths in
        try JSONDecoder().decode(ManagementReading.self,from:Data(ManagedServer(paths:paths).connection().send("serverInfo").utf8))
    }) { self.read = read }
    deinit { timer?.invalidate() }

    func start(paths: Paths) {
        guard timer == nil else { return }
        let timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.poll(paths:paths) }
        RunLoop.main.add(timer,forMode:.common); self.timer = timer
        poll(paths:paths)
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func poll(paths: Paths) {
        guard !discovering else { return }; discovering = true
        DispatchQueue.global(qos:.utility).async {
            let store = try? Store(paths:paths)
            let db = try? store?.load()
            DispatchQueue.main.async {
                self.discovering = false
                guard let db, let store else { return }
                let ids = Set(db.profiles.map(\.id))
                self.series = self.series.filter { ids.contains($0.key) }
                for profile in db.profiles {
                    let id = profile.id
                    guard !self.inFlight.contains(id) else { continue }
                    guard db.managedServers?[id] == true else { self.record(nil,for:id); continue }
                    self.inFlight.insert(id)
                    let scoped = store.servicePaths(id,database:db)
                    DispatchQueue.global(qos:.utility).async {
                        let reading = try? self.read(scoped)
                        DispatchQueue.main.async {
                            self.inFlight.remove(id)
                            // Ignore completions for deleted servers.
                            guard (try? store.load().profiles.contains { $0.id == id }) == true else { return }
                            self.record(reading,for:id)
                        }
                    }
                }
            }
        }
    }
    func record(_ reading: ManagementReading?, for id: String, now: Date = Date()) {
        var state = series[id] ?? Series()
        if let uptime = reading?.uptimeSeconds {
            if let previous = state.uptime, uptime < previous {
                // Keep history across restarts, but break the line between separate runs.
                state.samples.append(LiveMetricSample(time:now.addingTimeInterval(-0.001),fps:nil,memory:nil))
            }
            state.uptime = uptime
        }
        state.samples.append(LiveMetricSample(time:now,fps:reading?.fps,memory:reading.map { $0.managedMemoryBytes/1048576 }))
        state.samples.removeAll { now.timeIntervalSince($0.time) > 3600 }
        if state.samples.count > 7202 { state.samples.removeFirst(state.samples.count-7202) }
        state.reading = reading; state.updated = now; series[id] = state
    }
    func latest(for id: String, now: Date = Date()) -> ManagementReading? {
        guard let state = series[id], now.timeIntervalSince(state.updated) <= 3 else { return nil }
        return state.reading
    }
    func history(for id: String, now: Date = Date()) -> [LiveMetricSample] {
        (series[id]?.samples ?? []).filter { now.timeIntervalSince($0.time) <= 3600 }
    }
}
