
import UIKit
import Combine
import AVFoundation


typealias Frame = CMSampleBuffer
typealias FramePublisher = AnyPublisher<Frame, Never>

protocol VideoCaptureDelegate: AnyObject {
    
    func videoCapture(_ videoCapture: VideoCapture,
                      didCreate framePublisher: FramePublisher)
}

class VideoCapture: NSObject {
    weak var delegate: VideoCaptureDelegate! {
        didSet { createVideoFramePublisher() }
    }

    var isEnabled = true {
        didSet { isEnabled ? enableCaptureSession() : disableCaptureSession() }
    }

    private var cameraPosition = AVCaptureDevice.Position.front {
        didSet { createVideoFramePublisher() }
    }

    private var orientation = AVCaptureVideoOrientation.portrait {
        didSet { createVideoFramePublisher() }
    }

    private let captureSession = AVCaptureSession()

    
    private var framePublisher: PassthroughSubject<Frame, Never>?

    private let videoCaptureQueue = DispatchQueue(label: "Video Capture Queue",
                                                  qos: .userInitiated)
    private var horizontalFlip: Bool {
        
        cameraPosition == .front
    }
    
    private var videoStabilizationEnabled = false

    func toggleCameraSelection() {
        cameraPosition = cameraPosition == .back ? .front : .back
    }

    func updateDeviceOrientation() {
        let currentPhysicalOrientation = UIDevice.current.orientation

        switch currentPhysicalOrientation {

        case .portrait, .faceUp, .faceDown, .unknown:
            orientation = .portrait
        case .portraitUpsideDown:
            orientation = .portraitUpsideDown
        case .landscapeLeft:
            orientation = .landscapeRight
        case .landscapeRight:
            orientation = .landscapeLeft

        @unknown default:
            orientation = .portrait
        }
    }

    private func enableCaptureSession() {
        if !captureSession.isRunning { captureSession.startRunning() }
    }

    private func disableCaptureSession() {
        if captureSession.isRunning { captureSession.stopRunning() }
    }
}
extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput frame: Frame,
                       from connection: AVCaptureConnection) {

        
        framePublisher?.send(frame)
    }
}

extension VideoCapture {
    
    private func createVideoFramePublisher() {
        
        guard let videoDataOutput = configureCaptureSession() else { return }

        
        let passthroughSubject = PassthroughSubject<Frame, Never>()

        
        framePublisher = passthroughSubject

        
        videoDataOutput.setSampleBufferDelegate(self, queue: videoCaptureQueue)

        
        let genericFramePublisher = passthroughSubject.eraseToAnyPublisher()

        delegate.videoCapture(self, didCreate: genericFramePublisher)
    }

    
    private func configureCaptureSession() -> AVCaptureVideoDataOutput? {
        disableCaptureSession()

        guard isEnabled else {
            
            return nil
        }

        
        defer { enableCaptureSession() }

        
        captureSession.beginConfiguration()

        
        defer { captureSession.commitConfiguration() }

        
        let modelFrameRate = ExerciseClassifier.frameRate

        let input = AVCaptureDeviceInput.createCameraInput(position: cameraPosition,
                                                           frameRate: modelFrameRate)

        let output = AVCaptureVideoDataOutput.withPixelFormatType(kCVPixelFormatType_32BGRA)

        let success = configureCaptureConnection(input, output)
        return success ? output : nil
    }

    
    private func configureCaptureConnection(_ input: AVCaptureDeviceInput?,
                                            _ output: AVCaptureVideoDataOutput?) -> Bool {

        guard let input = input else { return false }
        guard let output = output else { return false }

        
        captureSession.inputs.forEach(captureSession.removeInput)
        captureSession.outputs.forEach(captureSession.removeOutput)

        guard captureSession.canAddInput(input) else {
            print("The camera input isn't compatible with the capture session.")
            return false
        }

        guard captureSession.canAddOutput(output) else {
            print("The video output isn't compatible with the capture session.")
            return false
        }

        
        captureSession.addInput(input)
        captureSession.addOutput(output)

        
        guard captureSession.connections.count == 1 else {
            let count = captureSession.connections.count
            print("The capture session has \(count) connections instead of 1.")
            return false
        }

        
        guard let connection = captureSession.connections.first else {
            print("Getting the first/only capture-session connection shouldn't fail.")
            return false
        }

        if connection.isVideoOrientationSupported {
            
            connection.videoOrientation = orientation
        }

        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = horizontalFlip
        }

        if connection.isVideoStabilizationSupported {
            if videoStabilizationEnabled {
                connection.preferredVideoStabilizationMode = .standard
            } else {
                connection.preferredVideoStabilizationMode = .off
            }
        }

        
        output.alwaysDiscardsLateVideoFrames = true

        return true
    }
}
