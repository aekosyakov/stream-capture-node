import Foundation
import CoreMediaIO
import AppKit
import AVFoundation
import VideoToolbox


public
extension CVPixelBuffer {

    enum LockFlag {
        case readwrite
        case readonly
        
        func flag() -> CVPixelBufferLockFlags {
            switch self {
            case .readonly:
                return .readOnly
            default:
                return CVPixelBufferLockFlags.init(rawValue: 0)
            }
        }
    }

    func lock(_ flag: LockFlag, closure: (() -> Void)?) {
        if CVPixelBufferLockBaseAddress(self, flag.flag()) == kCVReturnSuccess {
            closure?()
        }
        CVPixelBufferUnlockBaseAddress(self, flag.flag())
    }
}

// MARK: - SignalHandler

struct SignalHandler {
  struct Signal: Hashable {
    static let hangup = Signal(rawValue: SIGHUP)
    static let interrupt = Signal(rawValue: SIGINT)
    static let quit = Signal(rawValue: SIGQUIT)
    static let abort = Signal(rawValue: SIGABRT)
    static let kill = Signal(rawValue: SIGKILL)
    static let alarm = Signal(rawValue: SIGALRM)
    static let termination = Signal(rawValue: SIGTERM)
    static let userDefined1 = Signal(rawValue: SIGUSR1)
    static let userDefined2 = Signal(rawValue: SIGUSR2)
    static let exitSignals = [
      hangup,
      interrupt,
      quit,
      abort,
      alarm,
      termination
    ]

    let rawValue: Int32
    init(rawValue: Int32) {
      self.rawValue = rawValue
    }
  }

  typealias CSignalHandler = @convention(c) (Int32) -> Void
  typealias SignalHandler = (Signal) -> Void

  private static var handlers = [Signal: [SignalHandler]]()

  private static var cHandler: CSignalHandler = { rawSignal in
    let signal = Signal(rawValue: rawSignal)

    guard let signalHandlers = handlers[signal] else {
      return
    }

    for handler in signalHandlers {
      handler(signal)
    }
  }

  static func handle(signals: [Signal], handler: @escaping SignalHandler) {
    for signal in signals {
      // Since Swift has no way of running code on "struct creation", we need to initialize here…
      if handlers[signal] == nil {
        handlers[signal] = []
      }
      handlers[signal]?.append(handler)

      var signalAction = sigaction(
        __sigaction_u: unsafeBitCast(cHandler, to: __sigaction_u.self),
        sa_mask: 0,
        sa_flags: 0
      )

      _ = withUnsafePointer(to: &signalAction) { pointer in
        sigaction(signal.rawValue, pointer, nil)
      }
    }
  }

  /// Raise a signal
  static func raise(signal: Signal) {
    _ = Darwin.raise(signal.rawValue)
  }

  /// Ignore a signal
  static func ignore(signal: Signal) {
    _ = Darwin.signal(signal.rawValue, SIG_IGN)
  }

  /// Restore default signal handling
  static func restore(signal: Signal) {
    _ = Darwin.signal(signal.rawValue, SIG_DFL)
  }
}

extension Array where Element == SignalHandler.Signal {
  static let exitSignals = SignalHandler.Signal.exitSignals
}

// MARK: - CLI utils

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    write(string.data(using: .utf8)!)
  }
}

struct CLI {
  static var standardInput = FileHandle.standardOutput
  static var standardOutput = FileHandle.standardOutput
  static var standardError = FileHandle.standardError

  static let arguments = Array(CommandLine.arguments.dropFirst(1))
}

extension CLI {
  private static let once = Once()

  /// Called when the process exits, either normally or forced (through signals)
  /// When this is set, it's up to you to exit the process
  static var onExit: (() -> Void)? {
    didSet {
      guard let exitHandler = onExit else {
        return
      }

      let handler = {
        once.run(exitHandler)
      }

      atexit_b {
        handler()
      }

      SignalHandler.handle(signals: .exitSignals) { _ in
        handler()
      }
    }
  }

  /// Called when the process is being forced (through signals) to exit
  /// When this is set, it's up to you to exit the process
  static var onForcedExit: ((SignalHandler.Signal) -> Void)? {
    didSet {
      guard let exitHandler = onForcedExit else {
        return
      }

      SignalHandler.handle(signals: .exitSignals, handler: exitHandler)
    }
  }
}

enum PrintOutputTarget {
  case standardOutput
  case standardError
}

/// Make `print()` accept an array of items
/// Since Swift doesn't support spreading...

private func print<Target>(
  _ items: [Any],
  separator: String = " ",
  terminator: String = "\n",
  to output: inout Target
) where Target: TextOutputStream {
  let item = items.map { "\($0)" }.joined(separator: separator)
  Swift.print(item, terminator: terminator, to: &output)
}

func print(
  _ items: Any...,
  separator: String = " ",
  terminator: String = "\n",
  to output: PrintOutputTarget = .standardOutput
) {
  switch output {
  case .standardOutput:
    print(items, separator: separator, terminator: terminator)
  case .standardError:
    print(items, separator: separator, terminator: terminator, to: &CLI.standardError)
  }
}

// MARK: - Misc

func synchronized<T>(lock: AnyObject, closure: () throws -> T) rethrows -> T {
	objc_sync_enter(lock)
	defer {
		objc_sync_exit(lock)
	}

	return try closure()
}

final class Once {
  private var hasRun = false

  /**
  Executes the given closure only once (thread-safe)

  ```
  final class Foo {
    private let once = Once()

    func bar() {
      once.run {
        print("Called only once")
      }
    }
  }

  let foo = Foo()
  foo.bar()
  foo.bar()
  ```
  */
  func run(_ closure: () -> Void) {
    synchronized(lock: self) {
      guard !hasRun else {
        return
      }

      hasRun = true
      closure()
    }
  }
}

extension Data {
  func jsonDecoded<T: Decodable>() throws -> T {
    return try JSONDecoder().decode(T.self, from: self)
  }
}

extension String {
  func jsonDecoded<T: Decodable>() throws -> T {
    return try data(using: .utf8)!.jsonDecoded()
  }
}

func toJson<T>(_ data: T) throws -> String {
  let json = try JSONSerialization.data(withJSONObject: data)
  return String(data: json, encoding: .utf8)!
}

// MARK: -

extension CMTimeScale {
  static var video: CMTimeScale = 600 // This is what Apple recommends
}

extension CMTime {
  init(videoFramesPerSecond: Int) {
    self.init(seconds: 1 / Double(videoFramesPerSecond), preferredTimescale: .video)
  }
}

extension CGDirectDisplayID {
  public static let main = CGMainDisplayID()
}

extension NSScreen {
  private func infoForCGDisplay(_ displayID: CGDirectDisplayID, options: Int) -> [AnyHashable: Any]? {
    var iterator: io_iterator_t = 0

    let result = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
    guard result == kIOReturnSuccess else {
      print("Could not find services for IODisplayConnect: \(result)")
      return nil
    }

    var service = IOIteratorNext(iterator)
    while service != 0 {
      let info = IODisplayCreateInfoDictionary(service, IOOptionBits(options)).takeRetainedValue() as! [AnyHashable: Any]

      guard
        let vendorID = info[kDisplayVendorID] as! UInt32?,
        let productID = info[kDisplayProductID] as! UInt32?
      else {
          continue
      }

      if vendorID == CGDisplayVendorNumber(displayID) && productID == CGDisplayModelNumber(displayID) {
        return info
      }

      service = IOIteratorNext(iterator)
    }

    return nil
  }

  var id: CGDirectDisplayID {
    return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
  }

  var name: String {
    guard let info = infoForCGDisplay(id, options: kIODisplayOnlyPreferredName) else {
      return "Unknown screen"
    }

    guard
      let localizedNames = info[kDisplayProductName] as? [String: Any],
      let name = localizedNames.values.first as? String
    else {
        return "Unnamed screen"
    }

    return name
  }
}

extension Optional {
  func unwrapOrThrow(_ errorExpression: @autoclosure () -> Error) throws -> Wrapped {
    guard let value = self else {
      throw errorExpression()
    }

    return value
  }
}

private func enableDalDevices() {
  var property = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster)
  )
  var allow: UInt32 = 1
  let sizeOfAllow = MemoryLayout<UInt32>.size
  CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, UInt32(sizeOfAllow), &allow)
}

public struct Devices {
  public static func screen() -> [[String: Any]] {
    return NSScreen.screens.map {
      [
        // TODO: Use `NSScreen#localizedName` when targeting macOS 10.15
        "name": $0.name,
        "id": $0.id
      ]
    }
  }

  public static func audio() -> [[String: String]] {
    return AVCaptureDevice.devices(for: .audio).map {
      [
        "name": $0.localizedName,
        "id": $0.uniqueID
      ]
    }
  }

  public static func ios() -> [[String: String]] {
    enableDalDevices()
    return AVCaptureDevice.devices(for: .muxed)
      .filter { $0.localizedName == "iPhone" || $0.localizedName == "iPad" }
      .map {
        [
          "name": $0.localizedName,
          "id": $0.uniqueID
        ]
      }
  }
}


