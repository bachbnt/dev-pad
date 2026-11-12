// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  PortKillerManager.swift
//  DevPad
//
//  Shared state for Port Killer: the last scan, whether one is running, and
//  the last error. The main-window tab and the menu-bar popover tab both
//  observe this one instance, so a kill or a refresh in either shows up in
//  both. Scanning runs off the main thread (`PortScanner` does the libproc
//  work); the manager only publishes results. In demo mode it serves made-up
//  rows and never touches a real process.
//

import Foundation
import Darwin

@MainActor
final class PortKillerManager: ObservableObject {
    static let shared = PortKillerManager()

    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var isScanning = false
    /// False until the first scan has finished, so views can tell "not looked yet" from "nothing listening".
    @Published private(set) var hasScanned = false
    @Published var errorMessage: String?

    /// DevPad's own PID — never offered for killing.
    let ownPID = getpid()

    private init() {}

    // MARK: - Scanning

    func refresh() {
        if DemoMode.isOn {
            if !hasScanned {
                ports = DemoMode.samplePorts
                hasScanned = true
            }
            return
        }
        guard !isScanning else { return }
        isScanning = true
        // Singleton, so capturing `self` strongly can't outlive anything.
        Task.detached { [self] in
            var found: [ListeningPort] = []
            var failure: String?
            do {
                found = try PortScanner.listeningPorts()
            } catch {
                failure = error.localizedDescription
            }
            // Freeze before crossing the actor boundary (Swift 6 strictness).
            let finalPorts = found
            let finalFailure = failure
            await self.finishScan(ports: finalPorts, failure: finalFailure)
        }
    }

    private func finishScan(ports found: [ListeningPort], failure: String?) {
        if failure == nil { ports = found }
        errorMessage = failure
        hasScanned = true
        isScanning = false
    }

    // MARK: - Stopping

    /// SIGTERM, or SIGKILL when `force`. A failure is kept in `errorMessage`.
    func terminate(_ item: ListeningPort, force: Bool) {
        guard item.pid != ownPID else { return }
        if DemoMode.isOn {
            ports.removeAll { $0.pid == item.pid }
            return
        }
        do {
            try PortScanner.terminate(pid: item.pid, force: force)
        } catch {
            // No auto-refresh here: a scan would clear this message a
            // moment after the user could read it.
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil
        // SIGTERM is a request: give the process a moment to exit before
        // looking again, or the row would linger and look like a failed kill.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }
}
