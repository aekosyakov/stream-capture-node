import Foundation
import AVFoundation
import Cocoa

public
enum CaptureError: Error {
    case invalidScreen
    case invalidAudioDevice
    case couldNotAddScreen
    case couldNotAddMic
    case couldNotAddOutput
}

public final
class CaptureCLI: NSObject {

    private let session: AVCaptureSession
    private let output: AVCaptureVideoDataOutput
    private var activity: NSObjectProtocol?
    
    public var onStart: (() -> Void)?
    public var onFinish: (() -> Void)?
    public var onError: ((Error) -> Void)?
    public var onPause: (() -> Void)?
    public var onResume: (() -> Void)?
    public var imageStream: ((NSImage?) -> Void)?
    public var onDataStream: ((CVImageBuffer) -> Void)?

    
    public let devices = Devices.self
    
    public lazy
    var outputStream = OutputStream()

    public
    init(
        framesPerSecond: Int = 60,
        cropRect: CGRect?,
        showCursor: Bool,
        highlightClicks: Bool,
        screenId: CGDirectDisplayID = .main,
        audioDevice: AVCaptureDevice? = .default(for: .audio),
        videoCodec: AVVideoCodecType?
    ) throws {
        session = AVCaptureSession()
        
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
        
        output = AVCaptureVideoDataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            throw CaptureError.couldNotAddOutput
        }
        super.init()
    }
    
    public
    func start() {
        outputStream.schedule(in: .main, forMode: .default)
        outputStream.open()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer"))
        session.startRunning()
    }
    
    public
    func stop() {
        session.stopRunning()
    }

}


extension CaptureCLI : AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        onDataStream?(imageBuffer)
//        let ciImage = CIImage(cvImageBuffer: imageBuffer)
//        let context = CIContext()
//        let size = CGSize(width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))
//        guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: size.width, height: size.height)) else {
//            return
//        }
//        let image = NSImage(cgImage: cgImage, size: size)
////        print("captureOutput sample buffer \(sampleBuffer) image size \(image.size)")
//        imageStream?(image)
//
//        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
//        let height = CVPixelBufferGetHeight(imageBuffer)
//        let src_buff = CVPixelBufferGetBaseAddress(imageBuffer)
//
//        CVPixelBufferUnlockBaseAddress(imageBuffer, []);
//
//        let data = NSData(bytes: src_buff, length: bytesPerRow * height)
//        socket.write(data: data as Data)
//        _ = outputStream.write(data: data as Data)
//        print("image data \(data.description)")
    }
    
}

private
extension OutputStream {
    
    func write(data: Data) -> Int {
        return data.withUnsafeBytes { write($0, maxLength: data.count) }
    }

}
