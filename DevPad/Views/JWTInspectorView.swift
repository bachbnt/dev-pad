// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  JWTInspectorView.swift
//  DevPad
//
//  Two-mode JWT tool:
//    • Decode — paste a token, see header/payload/signature, parse standard
//               claims with a status badge, optionally verify the signature.
//    • Sign   — type a header + payload + HMAC secret, get a signed JWT
//               string back.
//

import SwiftUI
import AppKit

private enum JWTMode: String, CaseIterable, Identifiable {
    case decode, sign
    var id: String { rawValue }
}

private enum SignAlgorithm: String, CaseIterable, Identifiable {
    case hs256 = "HS256"
    case hs384 = "HS384"
    case hs512 = "HS512"
    var id: String { rawValue }
}

struct JWTInspectorView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var mode: JWTMode = .decode

    // Decode state
    @State private var input: String = ""
    @State private var decoded: JWT?
    @State private var decodeError: String?
    @State private var verifyKey: String = ""
    @State private var verifyResult: VerifyResult?

    // Sign state
    @State private var signHeader: String = #"{"alg":"HS256","typ":"JWT"}"#
    @State private var signPayload: String = #"{"sub":"1234567890","name":"bachbnt","iat":1747059700}"#
    @State private var signAlg: SignAlgorithm = .hs256
    @State private var signSecret: String = "your-256-bit-secret"
    @State private var signOutput: String = ""
    @State private var signError: String?

    private enum VerifyResult: Equatable {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 12) {
            modePicker
            switch mode {
            case .decode: decodeView
            case .sign:   signView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .onAppear {
            if DemoMode.isOn, input.isEmpty {
                input = DemoMode.sampleJWT
                runDecode()
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text(settings.t("jwt.mode.decode")).tag(JWTMode.decode)
            Text(settings.t("jwt.mode.sign")).tag(JWTMode.sign)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
    }

    // MARK: - Decode

    private var decodeView: some View {
        VStack(spacing: 12) {
            inputEditor
            decodeActionBar
            if let decodeError {
                errorBanner(decodeError)
            }
            if let decoded {
                decodedResults(decoded)
            } else if decodeError == nil {
                emptyDecode
            }
        }
    }

    private var inputEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
            if input.isEmpty {
                Text(settings.t("jwt.placeholder"))
                    .foregroundStyle(.tertiary)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 13)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 90, maxHeight: 140)
    }

    private var decodeActionBar: some View {
        HStack(spacing: 8) {
            Button {
                if let s = NSPasteboard.general.string(forType: .string) {
                    input = s
                }
            } label: {
                Label(settings.t("common.paste"), systemImage: "doc.on.clipboard")
            }
            Button(role: .destructive) {
                input = ""
                decoded = nil
                decodeError = nil
                verifyResult = nil
            } label: {
                Label(settings.t("common.clear"), systemImage: "trash")
            }
            Spacer()
            Button {
                runDecode()
            } label: {
                Label(settings.t("jwt.decode"), systemImage: "lock.open")
                    .frame(minWidth: 100)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyDecode: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("jwt.empty.title"))
                .font(.headline)
            Text(settings.t("jwt.empty.hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func decodedResults(_ jwt: JWT) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusBadge(for: jwt)
                section(title: settings.t("jwt.header"),
                        json: prettyJSON(jwt.headerJSON))
                section(title: settings.t("jwt.payload"),
                        json: prettyJSON(jwt.payloadJSON))
                section(title: settings.t("jwt.signature"),
                        json: jwt.rawSignature,
                        monospaced: true,
                        wrappable: true)
                claims(for: jwt)
                verifySection(for: jwt)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
        .frame(maxHeight: .infinity)
    }

    private func statusBadge(for jwt: JWT) -> some View {
        let (label, icon, color): (String, String, Color) = {
            switch jwt.status {
            case .valid:
                return (settings.t("jwt.status.valid"), "checkmark.seal.fill", .green)
            case .expired(let at):
                return (settings.t("jwt.status.expired", relativeString(at)),
                        "xmark.seal.fill", .red)
            case .notYetActive(let until):
                return (settings.t("jwt.status.notYet", relativeString(until)),
                        "clock.badge.exclamationmark.fill", .orange)
            case .noExpiration:
                return (settings.t("jwt.status.noExp"), "infinity.circle.fill", .gray)
            }
        }()
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(label)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if let alg = jwt.algorithm {
                Text(alg)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    private func section(title: String,
                         json: String,
                         monospaced: Bool = true,
                         wrappable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    copy(json)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(settings.t("common.copy"))
            }
            Text(json)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(wrappable ? nil : nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
        }
    }

    private func claims(for jwt: JWT) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t("jwt.claims"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            claimRow(settings.t("jwt.claim.iss"), value: jwt.issuer)
            claimRow(settings.t("jwt.claim.sub"), value: jwt.subject)
            claimRow(settings.t("jwt.claim.aud"),
                     value: jwt.audience.isEmpty ? nil : jwt.audience.joined(separator: ", "))
            claimRow(settings.t("jwt.claim.exp"),
                     value: jwt.expiresAt.map { dateString($0) })
            claimRow(settings.t("jwt.claim.iat"),
                     value: jwt.issuedAt.map { dateString($0) })
            claimRow(settings.t("jwt.claim.nbf"),
                     value: jwt.notBefore.map { dateString($0) })
            claimRow(settings.t("jwt.claim.jti"), value: jwt.jwtID)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.04))
        )
    }

    private func claimRow(_ label: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .trailing)
            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(settings.t("common.copy"))
            } else {
                Text(settings.t("url.absent"))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func verifySection(for jwt: JWT) -> some View {
        let isAsym = (jwt.algorithm ?? "").hasPrefix("RS")
            || (jwt.algorithm ?? "").hasPrefix("ES")
        let labelKey = isAsym ? "jwt.verify.publicKey" : "jwt.verify.secret"
        let placeholderKey = isAsym
            ? "jwt.verify.publicKey.placeholder"
            : "jwt.verify.secret.placeholder"

        VStack(alignment: .leading, spacing: 8) {
            Text(settings.t("jwt.verify.title"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 8) {
                Text(settings.t(labelKey))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .trailing)

                if isAsym {
                    TextEditor(text: $verifyKey)
                        .font(.system(.footnote, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.25))
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                        )
                        .frame(minHeight: 90, maxHeight: 140)
                } else {
                    SecureField(settings.t(placeholderKey), text: $verifyKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Text(settings.t(isAsym ? "jwt.verify.hint.asym" : "jwt.verify.hint.hmac"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    runVerify(for: jwt)
                } label: {
                    Label(settings.t("jwt.verify.run"), systemImage: "checkmark.shield")
                }
                .disabled(verifyKey.isEmpty)
            }

            if let verifyResult {
                verifyResultRow(verifyResult)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func verifyResultRow(_ result: VerifyResult) -> some View {
        let (icon, label, color): (String, String, Color)
        switch result {
        case .success:
            icon = "checkmark.seal.fill"
            label = settings.t("jwt.verify.success")
            color = .green
        case .failure(let msg):
            icon = "xmark.seal.fill"
            label = msg.isEmpty ? settings.t("jwt.verify.failure") : msg
            color = .red
        }
        return HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(label).foregroundStyle(.primary).font(.callout)
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    // MARK: - Sign

    private var signView: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                signEditor(title: settings.t("jwt.sign.header"), text: $signHeader)
                signEditor(title: settings.t("jwt.sign.payload"), text: $signPayload)
            }
            .frame(minHeight: 160, maxHeight: 240)

            HStack(spacing: 12) {
                Text(settings.t("jwt.sign.algorithm"))
                    .foregroundStyle(.secondary)
                Picker(settings.t("jwt.sign.algorithm"), selection: $signAlg) {
                    ForEach(SignAlgorithm.allCases) { a in
                        Text(a.rawValue).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .onChange(of: signAlg) { newValue in
                    signHeader = adjustAlg(in: signHeader, to: newValue.rawValue)
                }

                Text(settings.t("jwt.sign.secret"))
                    .foregroundStyle(.secondary)
                SecureField("", text: $signSecret)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)

                Spacer()

                Button {
                    runSign()
                } label: {
                    Label(settings.t("jwt.sign.run"), systemImage: "signature")
                        .frame(minWidth: 120)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }

            if let signError {
                errorBanner(signError)
            }

            Text(settings.t("jwt.sign.hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !signOutput.isEmpty {
                signOutputView
            }
        }
    }

    private func signEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                )
        }
    }

    private var signOutputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(settings.t("jwt.sign.output"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    copy(signOutput)
                } label: {
                    Label(settings.t("common.copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            Text(signOutput)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
        }
    }

    // MARK: - Banners + helpers

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("\(settings.t("jwt.error.prefix")): \(message)")
                .font(.callout)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    private func prettyJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ),
            let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = settings.language.locale
        f.dateStyle = .medium
        f.timeStyle = .medium
        return "\(f.string(from: date))  (\(relativeString(date)))"
    }

    private func relativeString(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = settings.language.locale
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    /// Replace (or insert) `"alg":"<value>"` in a JSON header string.
    private func adjustAlg(in header: String, to alg: String) -> String {
        guard let data = header.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any] else {
            return header
        }
        dict["alg"] = alg
        if dict["typ"] == nil { dict["typ"] = "JWT" }
        guard let newData = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ),
              let s = String(data: newData, encoding: .utf8) else {
            return header
        }
        return s
    }

    // MARK: - Actions

    private func runDecode() {
        verifyResult = nil
        do {
            decoded = try JWTCoder.decode(input)
            decodeError = nil
        } catch {
            decoded = nil
            decodeError = error.localizedDescription
        }
    }

    private func runVerify(for jwt: JWT) {
        do {
            let ok = try JWTCoder.verify(jwt, key: verifyKey)
            verifyResult = ok ? .success : .failure(settings.t("jwt.verify.failure"))
        } catch {
            verifyResult = .failure(error.localizedDescription)
        }
    }

    private func runSign() {
        do {
            // Make sure the header's alg matches the picker.
            let header = adjustAlg(in: signHeader, to: signAlg.rawValue)
            signHeader = header
            signOutput = try JWTCoder.sign(
                headerJSON: header,
                payloadJSON: signPayload,
                secret: signSecret
            )
            signError = nil
        } catch {
            signOutput = ""
            signError = error.localizedDescription
        }
    }
}

#Preview {
    JWTInspectorView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 800)
}
