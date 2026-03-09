import Foundation

public struct DesktopUpdateManifestFile: Equatable, Sendable {
  public let url: String
  public let sha512: String
  public let size: Int

  public init(url: String, sha512: String, size: Int) {
    self.url = url
    self.sha512 = sha512
    self.size = size
  }
}

public struct DesktopUpdateManifest: Equatable, Sendable {
  public let version: String
  public let releaseDate: String
  public let files: [DesktopUpdateManifestFile]
  public let extras: [String: String]

  public init(
    version: String,
    releaseDate: String,
    files: [DesktopUpdateManifestFile],
    extras: [String: String]
  ) {
    self.version = version
    self.releaseDate = releaseDate
    self.files = files
    self.extras = extras
  }
}

public enum DesktopUpdateManifestParserError: Error, Equatable {
  case invalidLine(String)
  case incompleteFileEntry
  case missingVersion
  case missingReleaseDate
  case missingFiles
}

public enum DesktopUpdateManifestParser {
  public static func parse(_ raw: String) throws -> DesktopUpdateManifest {
    let lines = raw.split(whereSeparator: \.isNewline).map(String.init)
    var version: String?
    var releaseDate: String?
    var files: [DesktopUpdateManifestFile] = []
    var extras: [String: String] = [:]
    var currentFile: [String: String] = [:]
    var inFiles = false

    func finalizeCurrentFile() throws {
      guard currentFile.isEmpty == false else {
        return
      }
      guard let url = currentFile["url"],
        let sha512 = currentFile["sha512"],
        let sizeString = currentFile["size"],
        let size = Int(sizeString)
      else {
        throw DesktopUpdateManifestParserError.incompleteFileEntry
      }
      files.append(DesktopUpdateManifestFile(url: stripQuotes(url), sha512: stripQuotes(sha512), size: size))
      currentFile.removeAll()
    }

    for rawLine in lines {
      let line = rawLine.trimmingCharacters(in: .newlines)
      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        continue
      }

      if let match = line.firstMatch(of: /^  - url:\s*(.+)$/) {
        try finalizeCurrentFile()
        currentFile["url"] = String(match.1)
        inFiles = true
        continue
      }

      if let match = line.firstMatch(of: /^    sha512:\s*(.+)$/) {
        currentFile["sha512"] = String(match.1)
        continue
      }

      if let match = line.firstMatch(of: /^    size:\s*(\d+)$/) {
        currentFile["size"] = String(match.1)
        continue
      }

      if line == "files:" {
        inFiles = true
        continue
      }

      if inFiles {
        try finalizeCurrentFile()
        inFiles = false
      }

      guard let separatorIndex = line.firstIndex(of: ":") else {
        throw DesktopUpdateManifestParserError.invalidLine(line)
      }
      let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
      let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)

      switch key {
      case "version":
        version = stripQuotes(value)
      case "releaseDate":
        releaseDate = stripQuotes(value)
      case "path", "sha512":
        break
      default:
        extras[key] = stripQuotes(value)
      }
    }

    try finalizeCurrentFile()

    guard let version else {
      throw DesktopUpdateManifestParserError.missingVersion
    }
    guard let releaseDate else {
      throw DesktopUpdateManifestParserError.missingReleaseDate
    }
    guard files.isEmpty == false else {
      throw DesktopUpdateManifestParserError.missingFiles
    }

    return DesktopUpdateManifest(
      version: version,
      releaseDate: releaseDate,
      files: files,
      extras: extras
    )
  }

  private static func stripQuotes(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("'"), trimmed.hasSuffix("'"), trimmed.count >= 2 else {
      return trimmed
    }
    return String(trimmed.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
  }
}

public enum DesktopVersionComparator {
  public static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
    candidate.compare(current, options: [.numeric]) == .orderedDescending
  }
}
