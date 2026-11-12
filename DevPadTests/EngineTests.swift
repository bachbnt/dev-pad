// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  EngineTests.swift
//  DevPadTests
//
//  Known-answer tests for the pure-logic engines: JSON, SQL, XML, hashing,
//  JWT and regex. These guard behavior other code relies on; they are not
//  exhaustive.
//

import XCTest

final class JSONFormatterTests: XCTestCase {

    private func compact(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    }

    func testFormatIndentsNestedStructures() throws {
        let out = try JSONFormatter.format(#"{"a":[1,2],"b":{"c":null}}"#, indent: 2)
        XCTAssertEqual(out, """
        {
          "a": [
            1,
            2
          ],
          "b": {
            "c": null
          }
        }
        """)
    }

    /// Regression: key order used to change from run to run because the
    /// formatter went through an unordered dictionary.
    func testKeyOrderIsPreservedUnlessSortRequested() throws {
        let input = #"{"zebra":1,"apple":2,"mango":{"y":1,"x":2}}"#
        for _ in 0..<20 {
            XCTAssertEqual(compact(try JSONFormatter.format(input)),
                           #"{"zebra":1,"apple":2,"mango":{"y":1,"x":2}}"#)
        }
        XCTAssertEqual(compact(try JSONFormatter.format(input, sortKeys: true)),
                       #"{"apple":2,"mango":{"x":2,"y":1},"zebra":1}"#)
        XCTAssertEqual(try JSONFormatter.minify(input), input)
    }

    /// Regression: `as? Bool` bridged NSNumber 0 / 1 to booleans, so `[1,0]`
    /// came out as `[true, false]`.
    func testNumbersZeroAndOneAreNotTurnedIntoBooleans() throws {
        XCTAssertEqual(compact(try JSONFormatter.format("[1, 0, true, false, 2, 1.5]")), "[1,0,true,false,2,1.5]")
        XCTAssertEqual(try JSONFormatter.minify("[1, 0, true, false]"), "[1,0,true,false]")
    }

    func testNumbersKeepTheirExactSourceText() throws {
        let input = "[12345678901234567890, 1.0, 1e3, -0, 0.10, 3.14159265358979323846]"
        XCTAssertEqual(try JSONFormatter.minify(input),
                       "[12345678901234567890,1.0,1e3,-0,0.10,3.14159265358979323846]")
    }

    func testDuplicateKeysAreKept() throws {
        XCTAssertEqual(try JSONFormatter.minify(#"{"a":1,"a":2}"#), #"{"a":1,"a":2}"#)
    }

    func testTabIndentDoesNotTouchSpacesInsideStrings() throws {
        let out = try JSONFormatter.format(#"{"k":"a  b"}"#, useTabs: true)
        XCTAssertEqual(out, "{\n\t\"k\": \"a  b\"\n}")
    }

    func testStringEscapesRoundTrip() throws {
        let input = #"{"s":"quote\" slash\\ nl\n tab\t \u00e9 \ud83d\ude00 \u0001"}"#
        let out = try JSONFormatter.minify(input)
        // é and the emoji come out as characters, the control char stays escaped.
        XCTAssertEqual(out, "{\"s\":\"quote\\\" slash\\\\ nl\\n tab\\t é 😀 \\u0001\"}")
        XCTAssertEqual(try JSONFormatter.minify(out), out)
    }

    func testFragmentsAndEmptyContainers() throws {
        XCTAssertEqual(try JSONFormatter.format("5"), "5")
        XCTAssertEqual(try JSONFormatter.format(#""x""#), #""x""#)
        XCTAssertEqual(try JSONFormatter.format("null"), "null")
        XCTAssertEqual(try JSONFormatter.format("{}"), "{}")
        XCTAssertEqual(try JSONFormatter.format("[]"), "[]")
        XCTAssertEqual(try JSONFormatter.format("{\"a\":[],\"b\":{}}", indent: 4), "{\n    \"a\": [],\n    \"b\": {}\n}")
    }

    func testInvalidInputIsRejectedWithPosition() {
        let bad = [
            "{oops", "{\"a\":1,}", "[1,]", "[1 2]", "{'a':1}", "{\"a\" 1}", "[01]", "[1.]", "[.5]", "[+1]",
            "[NaN]", "[1e]", "{\"a\":1} extra", "\"unterminated", "\"bad \\x escape\"", "\"\\ud800\"",
            "[1, // c\n2]", "tru", "", "   "
        ]
        for input in bad {
            XCTAssertThrowsError(try JSONFormatter.format(input), "should reject: \(input)")
        }
        XCTAssertThrowsError(try JSONFormatter.format("{\n  \"a\": ?\n}")) { error in
            XCTAssertTrue(error.localizedDescription.contains("line 2, column 8"), error.localizedDescription)
        }
    }

    func testAcceptsWhatJSONSerializationAcceptsOnValidDocuments() throws {
        let docs = [#"{"a":[1,2,{"b":null}],"c":"d"}"#, "[true,false,null,-1.5e-3]", #""just a string""#,
                    "  \n[1]\n ", #"{"emoji":"😀","nested":{"deep":[[],[{}]]}}"#]
        for doc in docs {
            let ours = try JSONFormatter.minify(doc)
            let a = try JSONSerialization.jsonObject(with: Data(doc.utf8), options: .fragmentsAllowed)
            let b = try JSONSerialization.jsonObject(with: Data(ours.utf8), options: .fragmentsAllowed)
            XCTAssertTrue((a as AnyObject).isEqual(b), doc)
        }
    }

    func testLargeDocumentParsesInReasonableTime() throws {
        let rows = (0..<60_000).map { #"{"id":\#($0),"name":"user \#($0)","tags":["a","b"],"ok":true,"score":1.5}"# }
        let input = "[" + rows.joined(separator: ",") + "]"   // ~4 MB
        let start = Date()
        let out = try JSONFormatter.format(input)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "Debug build; Release is far faster")
        XCTAssertTrue(out.hasPrefix("[\n  {\n    \"id\": 0,"))
    }

    func testVeryDeepNestingFailsInsteadOfCrashing() {
        let deep = String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)
        XCTAssertThrowsError(try JSONFormatter.format(deep))
    }

    func testInvalidAndEmptyInputThrow() {
        XCTAssertThrowsError(try JSONFormatter.format("{oops"))
        XCTAssertThrowsError(try JSONFormatter.format("   "))
    }
}

final class SQLFormatterTests: XCTestCase {

    func testKeywordsUppercasedAndClausesOnOwnLines() throws {
        let out = try SQLFormatter.format("select id, name from users where id = 1 and active = 1")
        XCTAssertTrue(out.contains("SELECT"), out)
        XCTAssertTrue(out.contains("\nFROM"), out)
        XCTAssertTrue(out.contains("\nWHERE"), out)
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try SQLFormatter.format("  "))
    }
}

final class XMLFormatterTests: XCTestCase {

    func testIndentsChildren() throws {
        let out = try XMLFormatter.format("<a><b>x</b></a>", indent: 2)
        XCTAssertTrue(out.contains("\n  <b>"), out)
    }

    func testUnclosedTagThrows() {
        XCTAssertThrowsError(try XMLFormatter.format("<a><b"))
        XCTAssertThrowsError(try XMLFormatter.format("   "))
    }
}

final class HashingTests: XCTestCase {

    private func hex(_ s: String, _ algo: HashAlgorithm) -> String {
        Hashing.hex(Hashing.hash(Data(s.utf8), algorithm: algo))
    }

    func testKnownDigestsOfABC() {
        XCTAssertEqual(hex("abc", .md5), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(hex("abc", .sha1), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(hex("abc", .sha256), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testMD2AndMD4StillWorkThroughSilgenNameAliases() {
        XCTAssertEqual(hex("abc", .md2), "da853b0d3f88d99b30283a69e6ded6bb")
        XCTAssertEqual(hex("abc", .md4), "a448017aaf21d8525fc10ae87aa6729d")
    }

    func testHMACSHA256KnownAnswer() throws {
        // RFC 4231 test case 2.
        let mac = try XCTUnwrap(Hashing.hmac(Data("what do ya want for nothing?".utf8),
                                             key: Data("Jefe".utf8), algorithm: .sha256))
        XCTAssertEqual(Hashing.hex(mac), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    func testHashFileMatchesInMemoryHash() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("devpad-\(UUID().uuidString).bin")
        let bytes = Data((0..<3_000_000).map { UInt8($0 % 253) })   // > 1 MB chunk
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Hashing.hashFile(at: url, algorithm: .sha256),
                       Hashing.hash(bytes, algorithm: .sha256))
    }

    func testLooselyEqualIgnoresCaseAndSeparators() {
        XCTAssertTrue(Hashing.looselyEqual("AB CD", "abcd"))
        XCTAssertFalse(Hashing.looselyEqual("abcd", "abce"))
    }
}

final class JWTTests: XCTestCase {

    func testSignThenDecodeAndVerifyHS256() throws {
        let token = try JWTCoder.sign(headerJSON: #"{"alg":"HS256","typ":"JWT"}"#,
                                      payloadJSON: #"{"sub":"42"}"#,
                                      secret: "s3cret")
        let jwt = try JWTCoder.decode(token)
        XCTAssertEqual(jwt.payloadJSON["sub"] as? String, "42")
        XCTAssertTrue(try JWTCoder.verify(jwt, key: "s3cret"))
        XCTAssertFalse(try JWTCoder.verify(jwt, key: "wrong"))
    }

    func testMalformedTokensThrow() {
        XCTAssertThrowsError(try JWTCoder.decode(""))
        XCTAssertThrowsError(try JWTCoder.decode("a.b"))
        XCTAssertThrowsError(try JWTCoder.decode("!!!.???.sig"))
    }

    func testUnsupportedSigningAlgorithmThrows() {
        XCTAssertThrowsError(try JWTCoder.sign(headerJSON: #"{"alg":"RS256"}"#, payloadJSON: "{}", secret: "x"))
    }
}

final class RegexEngineTests: XCTestCase {

    func testNamedGroupsAndMatchCount() throws {
        let regex = try RegexEngine.compile(#"(?<key>\w+)=(?<val>\d+)"#, flags: [])
        let matches = RegexEngine.matches(regex: regex, in: "a=1 b=22")
        XCTAssertEqual(matches.map(\.text), ["a=1", "b=22"])
        XCTAssertEqual(matches[1].groups.map(\.name), ["key", "val"])
        XCTAssertEqual(matches[1].groups.map(\.text), ["b", "22"])
    }

    func testCaseInsensitiveFlag() throws {
        let sensitive = try RegexEngine.compile("abc", flags: [])
        let insensitive = try RegexEngine.compile("abc", flags: [.caseInsensitive])
        XCTAssertTrue(RegexEngine.matches(regex: sensitive, in: "ABC").isEmpty)
        XCTAssertEqual(RegexEngine.matches(regex: insensitive, in: "ABC").count, 1)
    }

    func testInvalidPatternThrows() {
        XCTAssertThrowsError(try RegexEngine.compile("(", flags: []))
    }
}
