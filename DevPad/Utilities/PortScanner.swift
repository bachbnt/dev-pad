// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  PortScanner.swift
//  DevPad
//
//  Lists the TCP ports that processes are listening on and sends signals to
//  those processes. It reads the kernel's process table through libproc
//  (`proc_listpids` / `proc_pidinfo` / `proc_pidfdinfo`) instead of shelling
//  out to `lsof`, so no child process is spawned and the output can't change
//  format under us.
//
//  Under the App Sandbox both halves are blocked for processes other than
//  our own; DevPad.entitlements carries a narrow sandbox exception that
//  re-allows exactly these two operations. If that exception ever goes
//  missing, `listeningPorts()` throws `.accessDenied` rather than reporting
//  an empty (and misleading) list. Processes owned by other users are
//  invisible to us even without a sandbox and are skipped silently.
//

import Foundation
import Darwin

struct ListeningPort: Identifiable, Hashable, Sendable {
    let pid: Int32
    let processName: String
    let port: UInt16
    /// Local addresses the process listens on for this port, sorted.
    let addresses: [String]

    var id: String { "\(pid):\(port)" }

    /// True when the listener accepts connections on every interface
    /// (`0.0.0.0` / `::`) instead of only on loopback.
    var isExposed: Bool { addresses.contains { PortScanner.isWildcard($0) } }
}

enum PortScannerError: LocalizedError {
    case accessDenied
    case invalidPID(Int32)
    case signalFailed(pid: Int32, reason: String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "macOS denied access to other processes (is the sandbox exception missing?)"
        case .invalidPID(let pid):
            return "Refusing to signal PID \(pid)"
        case .signalFailed(let pid, let reason):
            return "Could not signal PID \(pid): \(reason)"
        }
    }
}

enum PortScanner {

    // MARK: - Scanning

    /// One entry per (process, port), sorted by port then PID.
    static func listeningPorts() throws -> [ListeningPort] {
        let me = getpid()
        var readableOthers = 0
        var found: [String: (pid: Int32, name: String, port: UInt16, addresses: Set<String>)] = [:]

        for pid in allPIDs() {
            guard let fds = fileDescriptors(of: pid) else { continue }
            if pid != me { readableOthers += 1 }

            for fd in fds where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                guard let (port, address) = listeningEndpoint(pid: pid, fd: fd.proc_fd) else { continue }
                let key = "\(pid):\(port)"
                if found[key] == nil {
                    found[key] = (pid, processName(pid), port, [])
                }
                found[key]?.addresses.insert(address)
            }
        }

        // Our own descriptors are always readable, other processes' are not
        // when the sandbox exception is gone: telling the two apart is the
        // only way to avoid presenting "nothing is listening" as a fact.
        if readableOthers == 0 { throw PortScannerError.accessDenied }

        return found.values
            .map { ListeningPort(pid: $0.pid, processName: $0.name, port: $0.port,
                                 addresses: $0.addresses.sorted()) }
            .sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    static func isWildcard(_ address: String) -> Bool {
        address == "0.0.0.0" || address == "::"
    }

    // MARK: - Signalling

    /// SIGTERM by default (lets the process clean up); SIGKILL when `force`.
    static func terminate(pid: Int32, force: Bool = false) throws {
        // 0 and negative values address whole process groups / every process;
        // 1 is launchd. None of those are ever what a click on a row means.
        guard pid > 1 else { throw PortScannerError.invalidPID(pid) }
        if Darwin.kill(pid, force ? SIGKILL : SIGTERM) != 0 {
            throw PortScannerError.signalFailed(pid: pid, reason: String(cString: strerror(errno)))
        }
    }

    // MARK: - libproc helpers

    private static func allPIDs() -> [Int32] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        // Headroom: processes can appear between the two calls.
        var pids = [Int32](repeating: 0, count: Int(needed) / MemoryLayout<Int32>.size + 64)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids,
                                  Int32(pids.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    /// `nil` when the process can't be inspected (gone, other user, sandbox).
    private static func fileDescriptors(of pid: Int32) -> [proc_fdinfo]? {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return nil }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard bytes > 0 else { return nil }
        return Array(fds.prefix(Int(bytes) / stride))
    }

    /// Local port and address if `fd` is a TCP socket in LISTEN state.
    private static func listeningEndpoint(pid: Int32, fd: Int32) -> (UInt16, String)? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, size) == size else { return nil }
        guard info.psi.soi_kind == Int32(SOCKINFO_TCP) else { return nil }

        let tcp = info.psi.soi_proto.pri_tcp
        guard tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { return nil }

        let ini = tcp.tcpsi_ini
        // The kernel stores the port in network byte order inside an Int32.
        let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport))
        guard port != 0 else { return nil }
        return (port, address(of: ini))
    }

    private static func address(of ini: in_sockinfo) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        // A dual-stack socket (bound to `::`) carries BOTH flags; its real
        // local address is the IPv6 one, so test IPv6 first.
        if ini.insi_vflag & UInt8(INI_IPV6) != 0 {
            var addr = ini.insi_laddr.ina_6
            inet_ntop(AF_INET6, &addr, &buffer, socklen_t(buffer.count))
        } else {
            var addr = ini.insi_laddr.ina_46.i46a_addr4
            inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count))
        }
        return String(cString: buffer)
    }

    private static func processName(_ pid: Int32) -> String {
        // proc_name truncates to 32 characters; the executable path doesn't.
        // Swift can't import PROC_PIDPATHINFO_MAXSIZE; it is defined as 4 * MAXPATHLEN.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let name = (String(cString: path) as NSString).lastPathComponent
            if !name.isEmpty { return name }
        }
        var short = [CChar](repeating: 0, count: 64)
        if proc_name(pid, &short, UInt32(short.count)) > 0 {
            return String(cString: short)
        }
        return "PID \(pid)"
    }
}
