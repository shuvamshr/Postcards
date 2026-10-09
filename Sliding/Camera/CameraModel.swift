//
//  CameraModel.swift
//  Sliding
//

@preconcurrency import AVFoundation
import SwiftUI

/// A minimal back-camera capture session. `isAvailable` stays false where there is
/// no camera (the Simulator) or access was denied; `isDenied` tells the two apart.
@Observable
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    /// Created only once a camera is found, since SwiftUI may construct this model many times.
    private(set) var session: AVCaptureSession?
    var isAvailable: Bool { session != nil }
    /// The person said no to camera access (or it's restricted), so only Settings can turn it back on.
    private(set) var isDenied = false
    /// True until the first start finishes, whether or not a camera turned up.
    private(set) var isStarting = true
    private var device: AVCaptureDevice?
    private var subjectChangeObserver: NSObjectProtocol?
    private let output = AVCapturePhotoOutput()
    private var pendingCapture: CheckedContinuation<UIImage?, Never>?

    func start() async {
        defer { isStarting = false }
        if isStarting { await FakeLatency.wait(1.2) }
        if session == nil {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            else { return }
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                isDenied = true
                return
            }
            isDenied = false
            guard let input = try? AVCaptureDeviceInput(device: device) else { return }
            let newSession = AVCaptureSession()
            newSession.beginConfiguration()
            newSession.sessionPreset = .photo
            if newSession.canAddInput(input) { newSession.addInput(input) }
            if newSession.canAddOutput(output) { newSession.addOutput(output) }
            newSession.commitConfiguration()
            session = newSession
            self.device = device
        }
        guard let session else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    /// Focus and expose on a point, in the camera's 0–1 coordinates (from the preview layer).
    /// When the scene changes a lot afterwards, the camera goes back to continuous autofocus.
    func focus(at point: CGPoint) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = point
            device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposurePointOfInterest = point
            device.exposureMode = .continuousAutoExposure
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
        device.unlockForConfiguration()

        if subjectChangeObserver == nil {
            subjectChangeObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetFocus() }
            }
        }
    }

    private func resetFocus() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        let center = CGPoint(x: 0.5, y: 0.5)
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusPointOfInterest = center
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = center
        }
        device.isSubjectAreaChangeMonitoringEnabled = false
        device.unlockForConfiguration()
    }

    func stop() {
        guard let session else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    func capture() async -> UIImage? {
        guard isAvailable, pendingCapture == nil else { return nil }
        return await withCheckedContinuation { continuation in
            pendingCapture = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            pendingCapture?.resume(returning: image)
            pendingCapture = nil
        }
    }
}

/// Live camera preview. Taps report where they landed, both on screen and in camera coordinates.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (_ viewPoint: CGPoint, _ devicePoint: CGPoint) -> Void = { _, _ in }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject {
        var onTap: (CGPoint, CGPoint) -> Void = { _, _ in }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PreviewView else { return }
            let point = recognizer.location(in: view)
            onTap(point, view.previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator,
                                                         action: #selector(Coordinator.tapped)))
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onTap = onTap
    }
}
