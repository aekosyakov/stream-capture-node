import Foundation
import AVFoundation
import Cocoa
import VideoToolbox

public final
class ScreenCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    public let devices = Devices.self
    private let session: AVCaptureSession
    private let output = AVCaptureVideoDataOutput()
    private var activity: NSObjectProtocol?

    public var onFinish: (() -> Void)?
    public var onError: ((Error) -> Void)?
    public var onPause: (() -> Void)?
    public var onResume: (() -> Void)?
    public var onDataStream: ((Data) -> Void)?
    public var fileHandler: FileHandle?
    public var onImageStream: ((NSImage) -> Void)?
    let captureQueue = DispatchQueue(label: "videotoolbox.compression.capture")
    let compressionQueue = DispatchQueue(label: "videotoolbox.compression.queue")
    
    var compressionSession: VTCompressionSession?
    var isCapturing: Bool = false

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
        session.beginConfiguration()
        session.sessionPreset = .high
        
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
            try? audioDevice.lockForConfiguration()
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
        output.alwaysDiscardsLateVideoFrames = true
        if let videoCodec = videoCodec {
            output.videoSettings = [AVVideoCodecKey: videoCodec]
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            throw CaptureError.couldNotAddOutput
        }
        session.commitConfiguration()
        super.init()
    }
    
    public
    func start() {
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample_buffer_queue"))
        session.startRunning()
        isCapturing = true
    }
    
    public
    func stop() {
        session.stopRunning()
        onFinish?()
        isCapturing = false
        guard let compressionSession = compressionSession else {
            return
        }
        
        VTCompressionSessionCompleteFrames(compressionSession, untilPresentationTimeStamp: CMTime.invalid)
        VTCompressionSessionInvalidate(compressionSession)
        self.compressionSession = nil
    }
    
    public
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelbuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let ciImage = CIImage(cvImageBuffer: pixelbuffer)
        let context = CIContext()
        let size = CGSize(width: CVPixelBufferGetWidth(pixelbuffer), height: CVPixelBufferGetHeight(pixelbuffer))
        guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: size.width, height: size.height)) else {
            return
        }
        let image = NSImage(cgImage: cgImage, size: size)
        onImageStream?(image)

        if compressionSession == nil {
            let width = CVPixelBufferGetWidth(pixelbuffer)
            let height = CVPixelBufferGetHeight(pixelbuffer)
            print("width: \(width), height: \(height)")
            
            let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                width: Int32(width),
                                                height: Int32(height),
                                                codecType: H265 ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
                                                encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
                                                outputCallback: compressionOutputCallback,
                                                refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                                compressionSessionOut: &compressionSession)
              
            guard let c = compressionSession else {
                print("Error creating compression session: \(status)")
                return
            }
            VTSessionSetProperty(c, key: kVTCompressionPropertyKey_ProfileLevel,
                                 value: kVTProfileLevel_HEVC_Main_AutoLevel)
            VTSessionSetProperty(c, key: kVTCompressionPropertyKey_RealTime, value: true as CFTypeRef)
            VTSessionSetProperty(c, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 10 as CFTypeRef)
            VTSessionSetProperty(c, key: kVTCompressionPropertyKey_AverageBitRate, value: width * height * 2 * 32 as CFTypeRef)
            VTSessionSetProperty(c, key: kVTCompressionPropertyKey_DataRateLimits, value: [width * height * 2 * 4, 1] as CFArray)
            VTCompressionSessionPrepareToEncodeFrames(c)
        }
          
        guard let c = compressionSession else {
            return
        }
          
        guard isCapturing else {
            return
        }
          
        compressionQueue.sync {
            pixelbuffer.lock(.readwrite) {
                let presentationTimestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                let duration = CMSampleBufferGetOutputDuration(sampleBuffer)
                VTCompressionSessionEncodeFrame(c, imageBuffer: pixelbuffer, presentationTimeStamp: presentationTimestamp, duration: duration, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
            }
        }
    }
    
    func handle(sps: NSData, pps: NSData, vps: NSData? = nil) {
        guard let fh = fileHandler else {
            return
        }
        
        let headerData: NSData = NSData(bytes: NALUHeader, length: NALUHeader.count)
        if let v = vps {
            print("Got VPS data: \(v.length) bytes")
            fh.write(headerData as Data)
            fh.write(v as Data)
        }
        
        fh.write(headerData as Data)
        fh.write(sps as Data)
        fh.write(headerData as Data)
        fh.write(pps as Data)
    }
    
    func encode(data: NSData, isKeyFrame: Bool) {
//        guard let fh = fileHandler else {
//            return
//        }
//        let headerData: NSData = NSData(bytes: NALUHeader, length: NALUHeader.count)
        let data = Data(bytes: NALUHeader, count: NALUHeader.count)
        onDataStream?(data)

//        fh.write(headerData as Data)
//        fh.write(data as Data)
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

fileprivate var NALUHeader: [UInt8] = [0, 0, 0, 1]

let H265 = true

func compressionOutputCallback(outputCallbackRefCon: UnsafeMutableRawPointer?,
                               sourceFrameRefCon: UnsafeMutableRawPointer?,
                               status: OSStatus,
                               infoFlags: VTEncodeInfoFlags,
                               sampleBuffer: CMSampleBuffer?) -> Swift.Void {
    guard status == noErr else {
        print("error: \(status)")
        return
    }
    
    if infoFlags == .frameDropped {
        print("frame dropped")
        return
    }
    
    guard let sampleBuffer = sampleBuffer else {
        print("sampleBuffer is nil")
        return
    }
    
    if CMSampleBufferDataIsReady(sampleBuffer) != true {
        print("sampleBuffer data is not ready")
        return
    }

    // 调试信息
//    let desc = CMSampleBufferGetFormatDescription(sampleBuffer)
//    let extensions = CMFormatDescriptionGetExtensions(desc!)
//    print("extensions: \(extensions!)")
//
//    let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
//    print("sample count: \(sampleCount)")
//
//    let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)!
//    var length: Int = 0
//    var dataPointer: UnsafeMutablePointer<Int8>?
//    CMBlockBufferGetDataPointer(dataBuffer, 0, nil, &length, &dataPointer)
//    print("length: \(length), dataPointer: \(dataPointer!)")
    // 调试信息结束
    
    let vc: ScreenCapture = Unmanaged.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
    
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
        print("attachments: \(attachments)")
        
        let rawDic: UnsafeRawPointer = CFArrayGetValueAtIndex(attachments, 0)
        let dic: CFDictionary = Unmanaged.fromOpaque(rawDic).takeUnretainedValue()
        
        // if not contains means it's an IDR frame
        let keyFrame = !CFDictionaryContainsKey(dic, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
        if keyFrame {
            print("IDR frame")
            
            // sps
            let format = CMSampleBufferGetFormatDescription(sampleBuffer)
            var spsSize: Int = 0
            var spsCount: Int = 0
            var nalHeaderLength: Int32 = 0
            var sps: UnsafePointer<UInt8>?
            var status: OSStatus
            if H265 {
                // HEVC
                
                // HEVC比H264多一个VPS
                var vpsSize: Int = 0
                var vpsCount: Int = 0
                var vps: UnsafePointer<UInt8>?
                var ppsSize: Int = 0
                var ppsCount: Int = 0
                var pps: UnsafePointer<UInt8>?

                status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format!, parameterSetIndex: 0, parameterSetPointerOut: &vps, parameterSetSizeOut: &vpsSize, parameterSetCountOut: &vpsCount, nalUnitHeaderLengthOut: &nalHeaderLength)
                if status == noErr {
                    print("HEVC vps: \(String(describing: vps)), vpsSize: \(vpsSize), vpsCount: \(vpsCount), NAL header length: \(nalHeaderLength)")
                    status =           CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format!, parameterSetIndex: 1, parameterSetPointerOut: &sps, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: &nalHeaderLength)
                    if status == noErr {
                        print("HEVC sps: \(String(describing: sps)), spsSize: \(spsSize), spsCount: \(spsCount), NAL header length: \(nalHeaderLength)")
                        status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format!, parameterSetIndex: 2, parameterSetPointerOut: &pps, parameterSetSizeOut: &ppsSize, parameterSetCountOut: &ppsCount, nalUnitHeaderLengthOut: &nalHeaderLength)
                        if status == noErr {
                            print("HEVC pps: \(String(describing: pps)), ppsSize: \(ppsSize), ppsCount: \(ppsCount), NAL header length: \(nalHeaderLength)")

                            let vpsData: NSData = NSData(bytes: vps, length: vpsSize)
                            let spsData: NSData = NSData(bytes: sps, length: spsSize)
                            let ppsData: NSData = NSData(bytes: pps, length: ppsSize)
                            
                            vc.handle(sps: spsData, pps: ppsData, vps: vpsData)

                        }
                    }

                }
                
            } else {
                // H.264
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format!,
                                                                      parameterSetIndex: 0,
                                                                      parameterSetPointerOut: &sps,
                                                                      parameterSetSizeOut: &spsSize,
                                                                      parameterSetCountOut: &spsCount,
                                                                      nalUnitHeaderLengthOut: &nalHeaderLength) == noErr {
                    print("sps: \(String(describing: sps)), spsSize: \(spsSize), spsCount: \(spsCount), NAL header length: \(nalHeaderLength)")
                    
                    // pps
                    var ppsSize: Int = 0
                    var ppsCount: Int = 0
                    var pps: UnsafePointer<UInt8>?
                    
                    if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format!,
                                                                          parameterSetIndex: 1,
                                                                          parameterSetPointerOut: &pps,
                                                                          parameterSetSizeOut: &ppsSize,
                                                                          parameterSetCountOut: &ppsCount,
                                                                          nalUnitHeaderLengthOut: &nalHeaderLength) == noErr {
                        print("sps: \(String(describing: pps)), spsSize: \(ppsSize), spsCount: \(ppsCount), NAL header length: \(nalHeaderLength)")
                        
                        let spsData: NSData = NSData(bytes: sps, length: spsSize)
                        let ppsData: NSData = NSData(bytes: pps, length: ppsSize)
                        
                        // save sps/pps to file
                        // NOTE: 事实上，大多数情况下 sps/pps 不变/变化不大 或者 变化对视频数据产生的影响很小，
                        // 因此，多数情况下你都可以只在文件头写入或视频流开头传输 sps/pps 数据
                        vc.handle(sps: spsData, pps: ppsData)
                    }
                }
            }
        } // end of handle sps/pps
        
        // handle frame data
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        if CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == noErr {
            var bufferOffset: Int = 0
            let AVCCHeaderLength = 4
            
            while bufferOffset < (totalLength - AVCCHeaderLength) {
                var NALUnitLength: UInt32 = 0
                // first four character is NALUnit length
                memcpy(&NALUnitLength, dataPointer?.advanced(by: bufferOffset), AVCCHeaderLength)
                
                // big endian to host endian. in iOS it's little endian
                NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
                
                let data: NSData = NSData(bytes: dataPointer?.advanced(by: bufferOffset + AVCCHeaderLength), length: Int(NALUnitLength))
                vc.encode(data: data, isKeyFrame: keyFrame)
                
                // move forward to the next NAL Unit
                bufferOffset += Int(AVCCHeaderLength)
                bufferOffset += Int(NALUnitLength)
            }
        }
    }
}
