//
//  CameraManager.swift
//  Yolo
//
//  Created by Abhishek Gupta on 15/11/25.
//

import AVFoundation
import Vision
import CoreML
import UIKit

class CameraManager: NSObject {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let overlay = CALayer()
    private let inferenceQueue = DispatchQueue(label: "inference")
    private var semaphore = DispatchSemaphore(value: 1)
    
    private var vnRequest: VNCoreMLRequest!
    
    
    func setup(with view: UIView) {
        setupModel()
        setupCamera(with: view)
    }
    
    private func setupCamera(with view: UIView) {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam) else { fatalError("No camera") }
        session.addInput(input)

        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.setSampleBufferDelegate(self, queue: inferenceQueue)
        session.addOutput(out)

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        overlay.frame = view.bounds
        view.layer.addSublayer(overlay)

        session.commitConfiguration()
        
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    private func setupModel() {
        // Load packaged model from bundle
        do {
            let vnModel = try loadVNModel(named: "yolov8n2")
            vnRequest = VNCoreMLRequest(model: vnModel, completionHandler: visionHandler)
            vnRequest.preferBackgroundProcessing = true
        } catch {
            fatalError("Failed to load model: \(error)")
        }
    }
    
    private func loadVNModel(named name: String) throws -> VNCoreMLModel {
        let bundle = Bundle.main

        // Prefer packaged model if present (compile it). Otherwise use compiled model directly.
        if let pkgURL = bundle.url(forResource: name, withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: pkgURL)
            let mlmodel = try MLModel(contentsOf: compiledURL)
            return try VNCoreMLModel(for: mlmodel)
        }

        if let compiledURL = bundle.url(forResource: name, withExtension: "mlmodelc") {
            // .mlmodelc is already compiled; load directly.
            let mlmodel = try MLModel(contentsOf: compiledURL)
            return try VNCoreMLModel(for: mlmodel)
        }

        // If Xcode generated a Swift wrapper class, consider using it instead:
        // let wrapper = try YOLOv8n(configuration: MLModelConfiguration())
        // return try VNCoreMLModel(for: wrapper.model)

        throw NSError(domain: "ModelLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name) not found in bundle"])
    }
    
    private func visionHandler(request: VNRequest, error: Error?) {
        defer { semaphore.signal() }
        guard error == nil, let results = request.results as? [VNRecognizedObjectObservation], !results.isEmpty else {
            DispatchQueue.main.async { self.clearOverlay() }
            return
        }
        // keep top detections (sorted by confidence)
        let detections = results.sorted { $0.confidence > $1.confidence }
        DispatchQueue.main.async { self.draw(detections) }
    }
    
    private func clearOverlay() {
        overlay.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func draw(_ observations: [VNRecognizedObjectObservation]) {
        clearOverlay()
        for obs in observations {
            guard let best = obs.labels.first else { continue }
            let rect = convertRect(obs.boundingBox)
            // Box
            let box = CAShapeLayer()
            box.frame = rect
            box.cornerRadius = 6
            box.borderWidth = 2
            box.borderColor = UIColor.red.cgColor
            overlay.addSublayer(box)

            // Label background
            let labelText = String(format: "%@ (%.0f%%)", best.identifier, best.confidence * 100)
            let textLayer = CATextLayer()
            textLayer.string = labelText
            textLayer.fontSize = 13
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.frame = CGRect(x: rect.minX, y: max(0, rect.minY - 22), width: 220, height: 20)
            // background for readability
            let bg = CALayer()
            bg.frame = textLayer.frame
            bg.backgroundColor = UIColor.black.withAlphaComponent(0.6).cgColor
            bg.cornerRadius = 4
            overlay.addSublayer(bg)
            overlay.addSublayer(textLayer)
        }
    }

    private func convertRect(_ normalized: CGRect) -> CGRect {
        // VN normalized coords origin is bottom-left; preview uses top-left.
        let w = previewLayer.bounds.width
        let h = previewLayer.bounds.height
        let x = normalized.minX * w
        let y = (1 - normalized.maxY) * h
        let width = normalized.width * w
        let height = normalized.height * h
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ out: AVCaptureOutput, didOutput sample: CMSampleBuffer, from conn: AVCaptureConnection) {
        guard semaphore.wait(timeout: .now()) == .success else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { semaphore.signal(); return }
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do { try handler.perform([vnRequest]) }
        catch { semaphore.signal(); print("Vision error:", error) }
    }
}
