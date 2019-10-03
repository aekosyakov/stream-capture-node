import Foundation
import AVFoundation

let output = FileHandle.standardOutput

func record() throws {
  let options: Options = try CLI.arguments.first!.jsonDecoded()
  let recorder = try ScreenCapture(
    framesPerSecond: options.framesPerSecond,
    cropRect: options.cropRect,
    showCursor: options.showCursor,
    highlightClicks: options.highlightClicks,
    screenId: options.screenId == 0 ? .main : options.screenId,
    audioDevice: options.audioDeviceId != nil ? AVCaptureDevice(uniqueID: options.audioDeviceId!) : nil,
    videoCodec: nil
  )
  recorder.onDataStream = {
    output.write($0)
  }
  recorder.onFinish = {
    exit(0)
  }
  recorder.onError = {
    recorder.stop()
    CLI.standardError.write($0.localizedDescription)
    exit(0)
  }

  CLI.onExit = {
    recorder.stop()
    exit(0)
  }
  recorder.start()

  setbuf(__stdoutp, nil)
  RunLoop.main.run()
}

struct Options: Decodable {
  let framesPerSecond: Int
  let cropRect: CGRect?
  let showCursor: Bool
  let highlightClicks: Bool
  let screenId: CGDirectDisplayID
  let audioDeviceId: String?
  let videoCodec: String?
}

func showUsage() {
  print(
    """
    Usage:
      capture <options>
      capture list-screens
      capture list-audio-devices
    """
  )
}

switch CLI.arguments.first {
case "list-screens":
  print(try toJson(Devices.screen()), to: .standardError)
  exit(0)
case "list-audio-devices":
  // Uses stderr because of unrelated stuff being outputted on stdout
  print(try toJson(Devices.audio()), to: .standardError)
  exit(0)
case .none:
  showUsage()
  exit(1)
default:
  try record()
}
