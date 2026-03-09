import Foundation

public struct RotatingFileSinkOptions: Sendable {
  public let fileURL: URL
  public let maxBytes: Int
  public let maxFiles: Int

  public init(fileURL: URL, maxBytes: Int, maxFiles: Int) {
    self.fileURL = fileURL
    self.maxBytes = maxBytes
    self.maxFiles = maxFiles
  }
}

public final class RotatingFileSink: @unchecked Sendable {
  private let fileManager: FileManager
  private let fileURL: URL
  private let maxBytes: Int
  private let maxFiles: Int
  private var currentSize: Int

  public init(
    options: RotatingFileSinkOptions,
    fileManager: FileManager = .default
  ) throws {
    precondition(options.maxBytes >= 1, "maxBytes must be >= 1")
    precondition(options.maxFiles >= 1, "maxFiles must be >= 1")

    self.fileManager = fileManager
    self.fileURL = options.fileURL
    self.maxBytes = options.maxBytes
    self.maxFiles = options.maxFiles
    self.currentSize = 0

    try fileManager.createDirectory(
      at: options.fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try pruneOverflowBackups()
    currentSize = readCurrentSize()
  }

  public func write(_ string: String) throws {
    try write(Data(string.utf8))
  }

  public func write(_ data: Data) throws {
    guard data.isEmpty == false else {
      return
    }

    if currentSize > 0 && currentSize + data.count > maxBytes {
      try rotate()
    }

    if fileManager.fileExists(atPath: fileURL.path) == false {
      _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
    }

    let handle = try FileHandle(forWritingTo: fileURL)
    defer { try? handle.close() }

    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    currentSize += data.count

    if currentSize > maxBytes {
      try rotate()
    }
  }

  private func rotate() throws {
    let oldestBackup = fileURL.appendingPathExtension(String(maxFiles))
    if fileManager.fileExists(atPath: oldestBackup.path) {
      try fileManager.removeItem(at: oldestBackup)
    }

    if maxFiles >= 2 {
      for index in stride(from: maxFiles - 1, through: 1, by: -1) {
        let source = fileURL.appendingPathExtension(String(index))
        let target = fileURL.appendingPathExtension(String(index + 1))
        if fileManager.fileExists(atPath: source.path) {
          if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
          }
          try fileManager.moveItem(at: source, to: target)
        }
      }
    }

    if fileManager.fileExists(atPath: fileURL.path) {
      let firstBackup = fileURL.appendingPathExtension("1")
      if fileManager.fileExists(atPath: firstBackup.path) {
        try fileManager.removeItem(at: firstBackup)
      }
      try fileManager.moveItem(at: fileURL, to: firstBackup)
    }

    currentSize = 0
  }

  private func pruneOverflowBackups() throws {
    let directoryURL = fileURL.deletingLastPathComponent()
    let entries = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
    let baseName = fileURL.lastPathComponent

    for entry in entries where entry.hasPrefix("\(baseName).") {
      let suffix = entry.dropFirst(baseName.count + 1)
      guard let number = Int(suffix), number > maxFiles else {
        continue
      }
      try fileManager.removeItem(at: directoryURL.appendingPathComponent(entry, isDirectory: false))
    }
  }

  private func readCurrentSize() -> Int {
    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
      let size = attributes[.size] as? NSNumber
    else {
      return 0
    }
    return size.intValue
  }
}
