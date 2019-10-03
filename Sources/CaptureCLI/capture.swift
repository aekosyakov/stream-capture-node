import Foundation
import AVFoundation
import Cocoa

public final
class ScreenCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    public let devices = Devices.self
    private let session: AVCaptureSession
    private var activity: NSObjectProtocol?
    private let videoOutput: AVCaptureVideoDataOutput

    public var onFinish: (() -> Void)?
    public var onError: ((Error) -> Void)?
    public var onPause: (() -> Void)?
    public var onResume: (() -> Void)?
    public var onDataStream: ((Data) -> Void)?
    public var onImageStream: ((NSImage) -> Void)?

    public
    init(
        framesPerSecond: Int = 60,
        cropRect: CGRect? = NSScreen.main?.frame,
        showCursor: Bool = true,
        highlightClicks: Bool = true,
        screenId: CGDirectDisplayID = .main,
        audioDevice: AVCaptureDevice? = .default(for: .audio),
        videoCodec: String? = "h264"
    ) throws {
        session = AVCaptureSession()
//        session.sessionPreset = .hd1280x720
        
        let input = try AVCaptureScreenInput(displayID: screenId).unwrapOrThrow(CaptureError.invalidScreen)
        
        input.minFrameDuration = CMTime(videoFramesPerSecond: framesPerSecond)
        
        if let cropRect = cropRect {
            input.cropRect = cropRect
        }
        
        input.capturesCursor = showCursor
        input.capturesMouseClicks = highlightClicks
        
        if let audioDevice = audioDevice {
            if !audioDevice.hasMediaType(.audio) {
                throw CaptureError.invalidAudioDevice
            }
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            } else {
                throw CaptureError.couldNotAddMic
            }
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            throw CaptureError.couldNotAddScreen
        }

        videoOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            throw CaptureError.couldNotAddOutput
        }
        super.init()

    }
    
    public
    func start() {
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample_buffer_queue"))
        session.startRunning()
    }

    public
    func stop() {
        session.stopRunning()
        onFinish?()
    }
    
    public
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let data = sampleBuffer.toByteData() {
            onDataStream?(data)
        }
    }

}

extension CMSampleBuffer {
    
    func toByteData() -> Data? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else {
            return nil
        }
        CVPixelBufferLockBaseAddress(imageBuffer,[])
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let cvBuff = CVPixelBufferGetBaseAddress(imageBuffer)
        print("height \(height), width \(width)")
        CVPixelBufferUnlockBaseAddress(imageBuffer, []);
        
        guard let cvBuffer = cvBuff else {
            return nil
        }
        return Data(bytes: cvBuffer, count: bytesPerRow * height)
    }
}

public
enum CaptureError: Error {
    case invalidScreen
    case invalidAudioDevice
    case couldNotAddScreen
    case couldNotAddMic
    case couldNotAddOutput
}
