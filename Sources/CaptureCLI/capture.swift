import Foundation
import AVFoundation
import Cocoa

public final
class ScreenCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    public let devices = Devices.self
    private var destination: URL?
    private let session: AVCaptureSession
    private var activity: NSObjectProtocol?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var movieFileOutput: AVCaptureMovieFileOutput?

    public var onFinish: (() -> Void)?
    public var onError: ((Error) -> Void)?
    public var onPause: (() -> Void)?
    public var onResume: (() -> Void)?
    public var onDataStream: ((Data) -> Void)?
    public var onImageStream: ((NSImage) -> Void)?

    public
    init(
        destination: URL?,
        framesPerSecond: Int = 60,
        cropRect: CGRect? = NSScreen.main?.frame,
        showCursor: Bool = true,
        highlightClicks: Bool = true,
        screenId: CGDirectDisplayID = .main,
        audioDevice: AVCaptureDevice? = .default(for: .audio),
        videoCodec: String? = "HEVC"
    ) throws {
        self.destination = destination
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

        if destination != nil {
            let movieOutput = AVCaptureMovieFileOutput()
            movieOutput.movieFragmentInterval = .invalid
            if let videoCodec = videoCodec {
              movieOutput.setOutputSettings([AVVideoCodecKey: videoCodec], for: movieOutput.connection(with: .video)!)
            }
            self.movieFileOutput = movieOutput
            if session.canAddOutput(movieOutput) {
              session.addOutput(movieOutput)
            } else {
              throw CaptureError.couldNotAddOutput
            }
        } else {
            let captureOutput = AVCaptureVideoDataOutput()
            self.videoOutput = captureOutput
            if session.canAddOutput(captureOutput) {
                session.addOutput(captureOutput)
            } else {
                throw CaptureError.couldNotAddOutput
            }
        }

        super.init()

    }
    
    public
    func start() {
        session.startRunning()
        if let destination = destination {
            movieFileOutput?.startRecording(to: destination, recordingDelegate: self)
        } else {
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample_buffer_queue"))
        }
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


extension ScreenCapture: AVCaptureFileOutputRecordingDelegate {

    private
    var shouldPreventSleep: Bool {
        get { activity != nil }
        set {
          if newValue {
                activity = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: "Recording screen")
          } else if let activity = activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
          }
        }
  }

    public
    func fileOutput(_ captureOutput: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        shouldPreventSleep = true
//        onStart?()
    }

    public
    func fileOutput(_ captureOutput: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        shouldPreventSleep = false

        let FINISHED_RECORDING_ERROR_CODE = -11_806

        if let error = error, error._code != FINISHED_RECORDING_ERROR_CODE {
          onError?(error)
        } else {
          onFinish?()
        }
    }

    public
    func fileOutput(_ output: AVCaptureFileOutput, didPauseRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        shouldPreventSleep = false
        onPause?()
    }

    public
    func fileOutput(_ output: AVCaptureFileOutput, didResumeRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        shouldPreventSleep = true
        onResume?()
    }

    public
    func fileOutputShouldProvideSampleAccurateRecordingStart(_ output: AVCaptureFileOutput) -> Bool { true }

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
