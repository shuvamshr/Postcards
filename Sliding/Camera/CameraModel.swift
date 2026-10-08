//
//  CameraModel.swift
//  Sliding
//

@preconcurrency import AVFoundation
import SwiftUI

/// A minimal back-camera capture session. `isAvailable` stays false where there is
/// no camera (the Simulator) or access was denied.
@Observable
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    /// Created only once a camera is found, since SwiftUI may construct this model many times.
    private(set) var session: AVCaptureSession?
    var isAvailable: Bool { session != nil }
    private let output = AVCapturePhotoOutput()
    private var pendingCapture: CheckedContinuation<UIImage?, Never>?

    func start() async {
        if session == nil {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  await AVCaptureDevice.requestAccess(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            let newSession = AVCaptureSession()
            newSession.beginConfiguration()
            newSession.sessionPreset = .photo
            if newSession.canAddInput(input) { newSession.addInput(input) }
            if newSession.canAddOutput(output) { newSession.addOutput(output) }
            newSession.commitConfiguration()
            session = newSession
        }
        guard let session else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
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

/// Live camera preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
