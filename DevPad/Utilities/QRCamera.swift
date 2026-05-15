//
//  QRCamera.swift
//  DevPad
//
//  AVFoundation wrapper that owns an `AVCaptureSession` and reads QR
//  codes from the user's webcam. Each frame is forwarded to Vision's
//  `VNDetectBarcodesRequest` filtered to `.qr` — the same engine the
//  file-based scan uses, so detection quality is identical.
//
//  We use `AVCaptureVideoDataOutput` + Vision instead of
//  `AVCaptureMetadataOutput` because the latter rejects `.qr` on some
//  Mac webcam configurations with "Unsupported type found - use
//  -availableMetadataObjectTypes" even after the canonical filter pattern.
//

import Foundation
@preconcurrency import AVFoundation
import Vision
import AppKit

@MainActor
final class QRCamera: NSObject, ObservableObject {

    /// What the user / system says about camera access right now.
    enum Permission {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    /// Whether the AVCaptureSession is actively running. Drives the
    /// Start / Stop button label.
    @Published private(set) var isRunning = false

    /// Last QR string we successfully decoded. UI clears this when the
    /// user presses Clear or stops the camera.
    @Published var decoded: String?

    /// Latest non-fatal error to surface as a banner in the UI.
    @Published var errorMessage: String?

    /// Current authorization status — refreshed at init and after a
    /// `requestAccess()` round-trip.
    @Published private(set) var permission: Permission = .notDetermined

    /// Underlying session. Exposed so the SwiftUI preview layer can
    /// attach to it directly.
    let session = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "DevPad.QRCamera.queue")

    /// Time of the last decode that produced a new value. Used to ignore
    /// the same QR being reported many times per second.
    private var lastDecodedValue: String?

    override init() {
        super.init()
        refreshPermission()
    }

    deinit {
        // Cut AVFoundation's link to our delegate before ARC tears us
        // down so no in-flight frame callback can land on freed memory.
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - Permission

    func refreshPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: permission = .notDetermined
        case .authorized:    permission = .authorized
        case .denied:        permission = .denied
        case .restricted:    permission = .restricted
        @unknown default:    permission = .denied
        }
    }

    /// Trigger the system camera-permission prompt. Only meaningful when
    /// `permission == .notDetermined`; for `.denied` the user has to go
    /// to System Settings.
    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            // The completion handler arrives on an arbitrary thread.
            // Hop to main with GCD — simpler and more predictable on
            // macOS 13 than `Task { @MainActor … }`.
            DispatchQueue.main.async {
                self?.refreshPermission()
                if self?.permission == .authorized {
                    self?.start()
                }
            }
        }
    }

    /// Open the macOS Privacy & Security pane so the user can flip the
    /// camera toggle on for DevPad after a previous denial.
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Session lifecycle

    func start() {
        guard permission == .authorized else {
            if permission == .notDetermined { requestAccess() }
            return
        }
        if session.isRunning { return }

        if session.inputs.isEmpty {
            do {
                try configureSession()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } else {
            // Restart path: stop() cleared the sample-buffer delegate.
            // Re-attach so frame callbacks resume.
            videoOutput.setSampleBufferDelegate(self, queue: queue)
        }

        queue.async { [session] in
            session.startRunning()
            let running = session.isRunning
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = running
            }
        }
    }

    func stop() {
        // Cut the delegate first so no callback can hit a tearing-down
        // self. Apple's AVCam sample uses this exact teardown order.
        videoOutput.setSampleBufferDelegate(nil, queue: nil)

        guard session.isRunning else {
            isRunning = false
            return
        }
        queue.async { [session] in
            session.stopRunning()
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
            }
        }
    }

    func clearDecoded() {
        decoded = nil
        lastDecodedValue = nil
    }

    // MARK: - Setup

    private func configureSession() throws {
        session.beginConfiguration()

        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            throw CameraError.noDevice
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw error
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraError.cannotAddOutput
        }
        session.addOutput(videoOutput)

        // Discard frames that arrive while Vision is still chewing on
        // the previous one — keeps memory bounded and avoids back-pressure
        // on slower Macs. Format BGRA is what Vision is happiest with.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
        ]

        session.commitConfiguration()

        // Set the delegate AFTER the session is committed — analogous to
        // why we do this for metadata outputs. Keeps everything tidy.
        videoOutput.setSampleBufferDelegate(self, queue: queue)
    }

    enum CameraError: LocalizedError {
        case noDevice
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .noDevice:        return "No camera was found on this Mac."
            case .cannotAddInput:  return "Couldn't attach the camera as an input source."
            case .cannotAddOutput: return "Couldn't attach the video output to the session."
            }
        }
    }
}

// MARK: - Frame → Vision → QR

extension QRCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        // Vision wants a CVPixelBuffer. CMSampleBufferGetImageBuffer is
        // O(1) on a CMSampleBuffer whose backing is a CVPixelBuffer (which
        // is what AVCaptureVideoDataOutput produces).
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // A Vision failure on a single frame isn't actionable —
            // the next frame will retry. Swallow silently.
            return
        }

        guard let observation = request.results?.first as? VNBarcodeObservation,
              let value = observation.payloadStringValue,
              !value.isEmpty
        else { return }

        // De-duplicate: the camera produces 30 frames/s; once we've
        // locked onto a QR we keep reading the same string. Only update
        // the UI when the value actually changes.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.lastDecodedValue != value {
                self.lastDecodedValue = value
                self.decoded = value
            }
        }
    }
}
