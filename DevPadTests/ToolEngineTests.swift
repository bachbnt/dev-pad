// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  ToolEngineTests.swift
//  DevPadTests
//
//  Known-answer tests for the small utility engines: Base64 / URL encoding,
//  UUID / ULID generation and the Unix timestamp converter. Reference values
//  were computed independently (Python, RFC 9562 and ULID spec examples).
//

import XCTest

// MARK: - Encode

final class EncodeEngineTests: XCTestCase {

    func testBase64RoundTrip() throws {
        XCTAssertEqual(EncodeEngine.encode("Hello, World!", mode: .base64), "SGVsbG8sIFdvcmxkIQ==")
        XCTAssertEqual(try EncodeEngine.decode("SGVsbG8sIFdvcmxkIQ==", mode: .base64), "Hello, World!")
    }

    func testBase64URLUsesSafeAlphabetAndDropsPadding() throws {
        // ">>>" is "Pj4+" and "???" is "Pz8/" in standard Base64.
        XCTAssertEqual(EncodeEngine.encode(">>>", mode: .base64url), "Pj4-")
        XCTAssertEqual(EncodeEngine.encode("???", mode: .base64url), "Pz8_")
        XCTAssertEqual(EncodeEngine.encode("a", mode: .base64url), "YQ")
        XCTAssertEqual(try EncodeEngine.decode("Pj4-", mode: .base64url), ">>>")
        XCTAssertEqual(try EncodeEngine.decode("Pz8_", mode: .base64url), "???")
    }

    func testBase64DecodeToleratesMissingPaddingAndWhitespace() throws {
        XCTAssertEqual(try EncodeEngine.decode("SGVsbG8", mode: .base64), "Hello")
        XCTAssertEqual(try EncodeEngine.decode(" SGVs\nbG8=\n", mode: .base64), "Hello")
    }

    func testBase64RejectsGarbage() {
        XCTAssertThrowsError(try EncodeEngine.decode("SGVsbG8$", mode: .base64))
        // A single leftover character can never come from an encoder.
        XCTAssertThrowsError(try EncodeEngine.decode("A", mode: .base64))
        // URL-safe characters are not valid in plain Base64 mode.
        XCTAssertThrowsError(try EncodeEngine.decode("Pj4-", mode: .base64))
    }

    func testBase64DecodeReportsNonUTF8Payload() {
        // 0xFF 0xFE is not UTF-8.
        XCTAssertThrowsError(try EncodeEngine.decode("//4=", mode: .base64)) { error in
            guard case EncodeError.notUTF8 = error else {
                return XCTFail("expected notUTF8, got \(error)")
            }
        }
    }

    func testPercentEncodingEscapesEverythingButUnreserved() throws {
        XCTAssertEqual(EncodeEngine.encode("a b&c=d/é", mode: .url), "a%20b%26c%3Dd%2F%C3%A9")
        XCTAssertEqual(EncodeEngine.encode("A-z_0.9~", mode: .url), "A-z_0.9~")
        XCTAssertEqual(try EncodeEngine.decode("a%20b%26c%3Dd%2F%C3%A9", mode: .url), "a b&c=d/é")
    }

    func testPercentDecodeKeepsPlusAndRejectsBadEscapes() throws {
        XCTAssertEqual(try EncodeEngine.decode("a+b", mode: .url), "a+b")
        XCTAssertThrowsError(try EncodeEngine.decode("100%zz", mode: .url))
    }
}

// MARK: - IDs

final class IDGeneratorTests: XCTestCase {

    func testUUIDv4SetsVersionAndVariant() {
        let bytes: [UInt8] = [0x91, 0x91, 0x08, 0xF7, 0x52, 0xD1, 0x03, 0x20,
                              0x1B, 0xAC, 0xF8, 0x47, 0xDB, 0x41, 0x48, 0xA8]
        XCTAssertEqual(IDGenerator.uuidV4(randomBytes: bytes),
                       "919108f7-52d1-4320-9bac-f847db4148a8")
        XCTAssertEqual(IDGenerator.uuidV4(randomBytes: bytes, hyphens: false),
                       "919108f752d143209bacf847db4148a8")
    }

    /// RFC 9562 appendix A.6.
    func testUUIDv7MatchesRFCExample() {
        let id = IDGenerator.uuidV7(
            timestampMs: 0x017F_22E2_79B0,
            randomBytes: [0x0C, 0xC3, 0x18, 0xC4, 0xDC, 0x0C, 0x0C, 0x07, 0x39, 0x8F])
        XCTAssertEqual(id, "017f22e2-79b0-7cc3-98c4-dc0c0c07398f")
    }

    /// The spec's canonical example, decoded with an independent algorithm.
    func testULIDMatchesSpecExample() {
        let id = IDGenerator.ulid(
            timestampMs: 1_469_922_850_259,
            randomBytes: [0xD6, 0x76, 0x4C, 0x61, 0xEF, 0xB9, 0x93, 0x02, 0xBD, 0x5B])
        XCTAssertEqual(id, "01ARZ3NDEKTSV4RRFFQ69G5FAV")
    }

    func testULIDTimestampPrefixAndZeroValue() {
        let zeros = [UInt8](repeating: 0, count: 10)
        XCTAssertEqual(IDGenerator.ulid(timestampMs: 0, randomBytes: zeros),
                       String(repeating: "0", count: 26))
        XCTAssertEqual(IDGenerator.ulid(timestampMs: 1_469_918_176_385, randomBytes: zeros),
                       "01ARYZ6S41" + String(repeating: "0", count: 16))
        // Largest 48-bit timestamp must not overflow the first character.
        let max = IDGenerator.ulid(timestampMs: 0xFFFF_FFFF_FFFF,
                                   randomBytes: [UInt8](repeating: 0xFF, count: 10))
        XCTAssertEqual(max, "7ZZZZZZZZZZZZZZZZZZZZZZZZZ")
    }

    func testGenerateHonoursCountCaseAndHyphens() {
        XCTAssertEqual(IDGenerator.generate(kind: .uuidV4, count: 5, uppercase: false, hyphens: true).count, 5)
        XCTAssertEqual(IDGenerator.generate(kind: .uuidV4, count: 0, uppercase: false, hyphens: true).count, 1)
        XCTAssertEqual(IDGenerator.generate(kind: .ulid, count: 10_000, uppercase: false, hyphens: true).count,
                       IDGenerator.maxCount)

        let upper = IDGenerator.generate(kind: .uuidV7, count: 3, uppercase: true, hyphens: false)
        for id in upper {
            XCTAssertEqual(id.count, 32)
            XCTAssertEqual(id, id.uppercased())
        }
        let ulids = IDGenerator.generate(kind: .ulid, count: 20, uppercase: false, hyphens: true)
        for id in ulids {
            XCTAssertEqual(id.count, 26)
            XCTAssertEqual(id, id.lowercased())
        }
    }

    func testGeneratedIDsAreUnique() {
        let ids = IDGenerator.generate(kind: .uuidV4, count: 100, uppercase: false, hyphens: true)
        XCTAssertEqual(Set(ids).count, 100)
        for id in ids {
            XCTAssertEqual(id.count, 36)
            XCTAssertNotNil(UUID(uuidString: id))
        }
    }
}

// MARK: - Timestamp

final class TimestampEngineTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let hcm = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    func testUnitDetectionByMagnitude() {
        XCTAssertEqual(TimestampEngine.detectUnit(1_700_000_000), .seconds)
        XCTAssertEqual(TimestampEngine.detectUnit(1_700_000_000_123), .milliseconds)
        XCTAssertEqual(TimestampEngine.detectUnit(1_700_000_000_123_456), .microseconds)
        XCTAssertEqual(TimestampEngine.detectUnit(1_700_000_000_123_456_789), .nanoseconds)
        XCTAssertEqual(TimestampEngine.detectUnit(-1_700_000_000), .seconds)
    }

    func testParseSecondsAndMilliseconds() throws {
        let s = try TimestampEngine.parse("1700000000")
        XCTAssertEqual(s.unit, .seconds)
        XCTAssertEqual(TimestampEngine.epochSeconds(s.date), 1_700_000_000)
        XCTAssertEqual(TimestampEngine.iso8601(s.date, timeZone: utc), "2023-11-14T22:13:20Z")

        let ms = try TimestampEngine.parse(" 1700000000123 ")
        XCTAssertEqual(ms.unit, .milliseconds)
        XCTAssertEqual(TimestampEngine.epochMilliseconds(ms.date), 1_700_000_000_123)
        XCTAssertEqual(TimestampEngine.iso8601(ms.date, timeZone: utc), "2023-11-14T22:13:20.123Z")
    }

    func testPinnedUnitOverridesDetection() throws {
        // Auto-detect reads this as seconds (1972); pinned to ms it is 1970-01-02.
        let r = try TimestampEngine.parse("86400000", unit: .milliseconds)
        XCTAssertEqual(TimestampEngine.iso8601(r.date, timeZone: utc), "1970-01-02T00:00:00Z")
        XCTAssertEqual(try TimestampEngine.parse("86400000").unit, .seconds)
    }

    func testFractionalAndNegativeSeconds() throws {
        let f = try TimestampEngine.parse("1700000000.5")
        XCTAssertEqual(TimestampEngine.epochSeconds(f.date), 1_700_000_000)
        XCTAssertEqual(TimestampEngine.epochMilliseconds(f.date), 1_700_000_000_500)

        let n = try TimestampEngine.parse("-1")
        XCTAssertEqual(TimestampEngine.iso8601(n.date, timeZone: utc), "1969-12-31T23:59:59Z")
        // Floor, not truncation: half a second before the epoch is second -1.
        XCTAssertEqual(TimestampEngine.epochSeconds(Date(timeIntervalSince1970: -0.5)), -1)
    }

    func testISOStringWithOffsetCarriesItsOwnZone() throws {
        let r = try TimestampEngine.parse("2023-11-15T05:13:20+07:00", zoneLessTimeZone: utc)
        XCTAssertNil(r.unit)
        XCTAssertEqual(TimestampEngine.epochSeconds(r.date), 1_700_000_000)
        let z = try TimestampEngine.parse("2023-11-14T22:13:20Z", zoneLessTimeZone: hcm)
        XCTAssertEqual(TimestampEngine.epochSeconds(z.date), 1_700_000_000)
    }

    func testZoneLessStringUsesTheChosenZone() throws {
        let asUTC = try TimestampEngine.parse("2023-11-14 22:13:20", zoneLessTimeZone: utc)
        XCTAssertEqual(TimestampEngine.epochSeconds(asUTC.date), 1_700_000_000)
        let asHCM = try TimestampEngine.parse("2023-11-14 22:13:20", zoneLessTimeZone: hcm)
        XCTAssertEqual(TimestampEngine.epochSeconds(asHCM.date), 1_700_000_000 - 7 * 3600)
        let dateOnly = try TimestampEngine.parse("1970-01-02", zoneLessTimeZone: utc)
        XCTAssertEqual(TimestampEngine.epochSeconds(dateOnly.date), 86_400)
    }

    func testLocalISOFormattingUsesOffset() throws {
        let r = try TimestampEngine.parse("1700000000")
        XCTAssertEqual(TimestampEngine.iso8601(r.date, timeZone: hcm), "2023-11-15T05:13:20+07:00")
    }

    func testRejectsInvalidInput() {
        XCTAssertThrowsError(try TimestampEngine.parse("")) { error in
            guard case TimestampError.empty = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try TimestampEngine.parse("hello")) { error in
            guard case TimestampError.unrecognized = error else { return XCTFail("\(error)") }
        }
        // Trailing junk must not be swallowed by a prefix match.
        XCTAssertThrowsError(try TimestampEngine.parse("2023-11-14 22:13:20 abc"))
        XCTAssertThrowsError(try TimestampEngine.parse("1.2.3"))
        XCTAssertThrowsError(try TimestampEngine.parse("9999999999999999999999")) { error in
            guard case TimestampError.outOfRange = error else { return XCTFail("\(error)") }
        }
    }

    func testRelativeIsLocaleAware() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = now.addingTimeInterval(-3 * 86_400)
        XCTAssertEqual(TimestampEngine.relative(past, to: now, locale: Locale(identifier: "en")),
                       "3 days ago")
    }
}

// MARK: - Port scanner

/// These run in the unsandboxed xctest process, so they exercise the libproc
/// parsing and the signalling for real. They cannot say anything about the
/// App Sandbox exception in DevPad.entitlements — that was verified
/// separately with a sandboxed binary.
final class PortScannerTests: XCTestCase {

    /// Binds a listening TCP socket on an ephemeral port. Returns the fd and port.
    private func listener(ipv6: Bool) throws -> (fd: Int32, port: UInt16) {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        try XCTSkipIf(fd < 0, "socket() failed")
        var ok: Int32
        if ipv6 {
            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_addr = in6addr_any
            ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        } else {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        try XCTSkipIf(ok != 0 || listen(fd, 1) != 0, "bind/listen failed (IPv6 unavailable?)")

        var bound = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        let port: UInt16 = withUnsafePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt16(bigEndian: $0.pointee.sin_port) }
        }
        return (fd, port)
    }

    func testFindsLoopbackListener() throws {
        let (fd, port) = try listener(ipv6: false)
        defer { close(fd) }
        let hit = try XCTUnwrap(try PortScanner.listeningPorts().first { $0.port == port })
        XCTAssertEqual(hit.pid, getpid())
        XCTAssertEqual(hit.addresses, ["127.0.0.1"])
        XCTAssertFalse(hit.isExposed)
        XCTAssertFalse(hit.processName.isEmpty)
    }

    func testWildcardListenerIsMarkedExposed() throws {
        let (fd, port) = try listener(ipv6: true)
        defer { close(fd) }
        let hit = try XCTUnwrap(try PortScanner.listeningPorts().first { $0.port == port })
        XCTAssertEqual(hit.addresses, ["::"])
        XCTAssertTrue(hit.isExposed)
    }

    func testClosedListenerDisappears() throws {
        let (fd, port) = try listener(ipv6: false)
        XCTAssertTrue(try PortScanner.listeningPorts().contains { $0.port == port })
        close(fd)
        XCTAssertFalse(try PortScanner.listeningPorts().contains { $0.port == port })
    }

    func testTerminateRefusesGroupAndSystemPIDs() {
        for pid: Int32 in [0, 1, -1, -500] {
            XCTAssertThrowsError(try PortScanner.terminate(pid: pid)) { error in
                guard case PortScannerError.invalidPID = error else { return XCTFail("\(error)") }
            }
        }
    }

    private func spawnSleeper() throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["60"]
        try p.run()
        return p
    }

    func testTerminateSendsSIGTERM() throws {
        let child = try spawnSleeper()
        try PortScanner.terminate(pid: child.processIdentifier)
        child.waitUntilExit()
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGTERM)
    }

    func testForceTerminateSendsSIGKILL() throws {
        let child = try spawnSleeper()
        try PortScanner.terminate(pid: child.processIdentifier, force: true)
        child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus, SIGKILL)
    }

    func testTerminateReportsAMissingProcess() throws {
        let child = try spawnSleeper()
        child.terminate()
        child.waitUntilExit()   // reaped, so the PID no longer exists
        XCTAssertThrowsError(try PortScanner.terminate(pid: child.processIdentifier)) { error in
            guard case PortScannerError.signalFailed = error else { return XCTFail("\(error)") }
        }
    }
}

// MARK: - QR payloads

final class VietQRTests: XCTestCase {

    /// The first four strings were produced by VietQR's own image service
    /// (img.vietqr.io) for the same inputs, then decoded back from the QR.
    func testMatchesVietQRServiceOutput() throws {
        XCTAssertEqual(
            try VietQR.build(bin: "970436", account: "0123456789", amount: 50000, message: "ck tien"),
            "00020101021238540010A00000072701240006970436011001234567890208QRIBFTTA53037045405500005802VN62110807ck tien630496A3")
        XCTAssertEqual(
            try VietQR.build(bin: "970436", account: "0123456789"),
            "00020101021138540010A00000072701240006970436011001234567890208QRIBFTTA53037045802VN63046A15")
        XCTAssertEqual(
            try VietQR.build(bin: "970407", account: "19036556677017", amount: 1_250_000),
            "00020101021238580010A000000727012800069704070114190365566770170208QRIBFTTA5303704540712500005802VN6304BA55")
        XCTAssertEqual(
            try VietQR.build(bin: "970422", account: "5555666677", message: "Thanh toan don 123"),
            "00020101021138540010A00000072701240006970422011055556666770208QRIBFTTA53037045802VN62220818Thanh toan don 1236304E2D8")
    }

    func testCRC16KnownVector() {
        XCTAssertEqual(VietQR.crc16("123456789"), "29B1")
    }

    func testParseRoundTrip() throws {
        let payload = try VietQR.build(bin: "970436", account: "0123456789", amount: 50000, message: "ck tien")
        XCTAssertEqual(VietQR.parse(payload),
                       VietQRInfo(bin: "970436", account: "0123456789", amount: 50000, message: "ck tien"))
        let bare = try VietQR.build(bin: "970436", account: "0123456789")
        XCTAssertEqual(VietQR.parse(bare), VietQRInfo(bin: "970436", account: "0123456789", amount: nil, message: nil))
    }

    func testParseRejectsBadChecksumAndForeignQR() throws {
        let good = try VietQR.build(bin: "970436", account: "0123456789", amount: 50000)
        var corrupted = good
        corrupted.removeLast()
        corrupted.append(good.last == "0" ? "1" : "0")
        XCTAssertNil(VietQR.parse(corrupted))
        XCTAssertNil(VietQR.parse("https://example.com"))
        XCTAssertNil(VietQR.parse(""))
    }

    func testMessageIsFoldedToASCII() {
        XCTAssertEqual(VietQR.sanitizeMessage("Chuyển khoản đơn Đặt hàng"), "Chuyen khoan don Dat hang")
        XCTAssertEqual(VietQR.sanitizeMessage("  ok 😀 tab\t"), "ok  tab")
    }

    func testAmountParsing() throws {
        XCTAssertEqual(try VietQR.parseAmount("50.000"), 50_000)
        XCTAssertEqual(try VietQR.parseAmount("1,250,000"), 1_250_000)
        XCTAssertEqual(try VietQR.parseAmount(" 1 250 000 "), 1_250_000)
        XCTAssertNil(try VietQR.parseAmount(""))
        XCTAssertThrowsError(try VietQR.parseAmount("0"))
        XCTAssertThrowsError(try VietQR.parseAmount("12abc"))
        XCTAssertThrowsError(try VietQR.parseAmount("-5"))
    }

    func testValidation() {
        XCTAssertThrowsError(try VietQR.build(bin: "12345", account: "1"))
        XCTAssertThrowsError(try VietQR.build(bin: "97043A", account: "1"))
        XCTAssertThrowsError(try VietQR.build(bin: "970436", account: ""))
        XCTAssertThrowsError(try VietQR.build(bin: "970436", account: "12AB"))
        XCTAssertThrowsError(try VietQR.build(bin: "970436", account: String(repeating: "1", count: 20)))
        XCTAssertThrowsError(try VietQR.build(bin: "970436", account: "1", amount: 0))
        XCTAssertThrowsError(try VietQR.build(bin: "970436", account: "1", amount: -1))
        XCTAssertThrowsError(try VietQR.build(bin: "970436", account: "1",
                                              message: String(repeating: "a", count: VietQR.maxMessageLength + 1)))
        // Spaces inside an account number (copied from a statement) are ignored.
        XCTAssertNoThrow(try VietQR.build(bin: "970436", account: "0123 4567 89"))
        XCTAssertNoThrow(try VietQR.build(bin: "970436", account: "1",
                                          message: String(repeating: "a", count: VietQR.maxMessageLength)))
    }

    func testBankTable() {
        XCTAssertEqual(VietQR.bankName(forBIN: "970436"), "Vietcombank")
        XCTAssertNil(VietQR.bankName(forBIN: "000000"))
        XCTAssertEqual(Set(VietQR.banks.map(\.bin)).count, VietQR.banks.count, "duplicate BIN")
        XCTAssertTrue(VietQR.banks.allSatisfy { $0.bin.count == 6 && $0.bin.allSatisfy(\.isNumber) })
    }
}

final class WiFiQRTests: XCTestCase {

    func testBuild() throws {
        XCTAssertEqual(try WiFiQR.build(ssid: "MyNet", password: "pass1234", security: .wpa, hidden: false),
                       "WIFI:T:WPA;S:MyNet;P:pass1234;;")
        XCTAssertEqual(try WiFiQR.build(ssid: "MyNet", password: "pass1234", security: .wpa, hidden: true),
                       "WIFI:T:WPA;S:MyNet;P:pass1234;H:true;;")
        XCTAssertEqual(try WiFiQR.build(ssid: "Cafe", password: "ignored", security: .none, hidden: false),
                       "WIFI:T:nopass;S:Cafe;;")
        XCTAssertEqual(try WiFiQR.build(ssid: "Old", password: "abcde", security: .wep, hidden: false),
                       "WIFI:T:WEP;S:Old;P:abcde;;")
    }

    func testReservedCharactersAreEscapedAndRoundTrip() throws {
        let ssid = #"a;b:c"d\e"#
        let password = "p,w;d:12345"
        let payload = try WiFiQR.build(ssid: ssid, password: password, security: .wpa, hidden: false)
        XCTAssertEqual(payload, #"WIFI:T:WPA;S:a\;b\:c\"d\\e;P:p\,w\;d\:12345;;"#)
        XCTAssertEqual(WiFiQR.parse(payload),
                       WiFiInfo(ssid: ssid, password: password, security: .wpa, hidden: false))
    }

    func testParseOtherLayouts() {
        // Field order is free, and a missing T means an open network.
        XCTAssertEqual(WiFiQR.parse("WIFI:S:Cafe;H:true;;"),
                       WiFiInfo(ssid: "Cafe", password: "", security: .none, hidden: true))
        XCTAssertEqual(WiFiQR.parse("WIFI:P:secret99;T:WPA2;S:Home;;")?.security, .wpa)
        XCTAssertNil(WiFiQR.parse("WIFI:T:WPA;P:nossid;;"))
        XCTAssertNil(WiFiQR.parse("https://example.com"))
    }

    func testValidation() {
        XCTAssertThrowsError(try WiFiQR.build(ssid: "", password: "pass1234", security: .wpa, hidden: false))
        XCTAssertThrowsError(try WiFiQR.build(ssid: String(repeating: "é", count: 17), password: "pass1234",
                                              security: .wpa, hidden: false))   // 34 bytes
        XCTAssertThrowsError(try WiFiQR.build(ssid: "x", password: "short", security: .wpa, hidden: false))
        XCTAssertThrowsError(try WiFiQR.build(ssid: "x", password: String(repeating: "z", count: 64),
                                              security: .wpa, hidden: false), "64 chars must be hex")
        XCTAssertNoThrow(try WiFiQR.build(ssid: "x", password: String(repeating: "a", count: 64),
                                          security: .wpa, hidden: false), "64 hex digits are a raw PSK")
        XCTAssertThrowsError(try WiFiQR.build(ssid: "x", password: "", security: .wep, hidden: false))
    }
}

final class VCardQRTests: XCTestCase {

    func testBuildExactLayout() throws {
        let card = ContactCard(firstName: "Bách", lastName: "Bùi", organization: "FPT Software",
                               title: "Team Lead", mobile: "+84 901 234 567",
                               email: "a@b.com", website: "https://x.dev")
        XCTAssertEqual(try VCardQR.build(card), [
            "BEGIN:VCARD", "VERSION:3.0", "N:Bùi;Bách;;;", "FN:Bách Bùi", "ORG:FPT Software",
            "TITLE:Team Lead", "TEL;TYPE=CELL:+84 901 234 567", "EMAIL:a@b.com",
            "URL:https://x.dev", "END:VCARD"
        ].joined(separator: "\r\n"))
    }

    func testOptionalFieldsAreOmittedAndSpecialsEscaped() throws {
        let card = ContactCard(firstName: "Ann", organization: #"A, B; C\D"#)
        let out = try VCardQR.build(card)
        XCTAssertTrue(out.contains(#"ORG:A\, B\; C\\D"#))
        XCTAssertFalse(out.contains("TEL"))
        XCTAssertFalse(out.contains("EMAIL"))
        XCTAssertTrue(out.contains("N:;Ann;;;"))
        XCTAssertTrue(out.contains("FN:Ann"))
    }

    func testParseRoundTrip() throws {
        let card = ContactCard(firstName: "Bách", lastName: "Bùi", organization: "FPT, Software",
                               title: "Lead", mobile: "+84 901", email: "a@b.com", website: "https://x.dev")
        let info = try XCTUnwrap(VCardQR.parse(try VCardQR.build(card)))
        XCTAssertEqual(info, VCardInfo(name: "Bách Bùi", organization: "FPT, Software", title: "Lead",
                                       phones: ["+84 901"], emails: ["a@b.com"], urls: ["https://x.dev"]))
    }

    func testParseHandlesFoldedLinesAndLFEndings() throws {
        let raw = "BEGIN:VCARD\nVERSION:3.0\nFN:Long\n  Name\nTEL;TYPE=WORK,VOICE:123\nEMAIL;TYPE=INTERNET:x@y.org\nEND:VCARD"
        let info = try XCTUnwrap(VCardQR.parse(raw))
        XCTAssertEqual(info.name, "Long Name")
        XCTAssertEqual(info.phones, ["123"])
        XCTAssertEqual(info.emails, ["x@y.org"])
        XCTAssertNil(VCardQR.parse("hello"))
    }

    func testValidation() {
        XCTAssertThrowsError(try VCardQR.build(ContactCard()))
        XCTAssertThrowsError(try VCardQR.build(ContactCard(firstName: "A", email: "abc")))
        XCTAssertThrowsError(try VCardQR.build(ContactCard(firstName: "A", email: "a@b")))
        XCTAssertThrowsError(try VCardQR.build(ContactCard(firstName: "A", email: "a b@c.com")))
        XCTAssertNoThrow(try VCardQR.build(ContactCard(lastName: "OnlyLast")))
    }
}

final class QRPayloadClassifyTests: XCTestCase {

    func testClassify() throws {
        let vietqr = try VietQR.build(bin: "970436", account: "0123456789")
        guard case .vietQR = QRPayload.classify(vietqr) else { return XCTFail("vietqr") }
        let wifi = try WiFiQR.build(ssid: "Net", password: "pass1234", security: .wpa, hidden: false)
        guard case .wifi = QRPayload.classify(wifi) else { return XCTFail("wifi") }
        let vcard = try VCardQR.build(ContactCard(firstName: "A"))
        guard case .vcard = QRPayload.classify(vcard) else { return XCTFail("vcard") }
        XCTAssertEqual(QRPayload.classify("https://example.com"), .text)
        XCTAssertEqual(QRPayload.classify("just some words"), .text)
    }
}
