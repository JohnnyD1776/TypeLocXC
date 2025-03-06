//
//  FileHandler.swift
//  TypeLocXC
//
//  Created by John Durcan on 06/03/2025.
//

import Foundation
import CryptoKit

struct FileHandler {

  /// Checks if the current directory is the project root by looking for .xcodeproj.
  static func isProjectRoot(_ directory: String) -> Bool {
    let contents = try? FileManager.default.contentsOfDirectory(atPath: directory)
    return contents?.contains(where: { $0.hasSuffix(".xcodeproj") }) ?? false
  }

  /// Finds all .xcstrings files in the project root and subdirectories.
  static func findAllXCStringsFiles(in directory: String) -> [String] {
    var xcstringsFiles: [String] = []
    let enumerator = FileManager.default.enumerator(atPath: directory)
    while let file = enumerator?.nextObject() as? String {
      if file.hasSuffix(".xcstrings") {
        xcstringsFiles.append("\(directory)/\(file)")
      }
    }
    return xcstringsFiles
  }

  /// Finds all +generated.swift files in the project root and subdirectories.
  static func findAllGeneratedFiles(in directory: String) -> [String] {
    var generatedFiles: [String] = []
    let enumerator = FileManager.default.enumerator(atPath: directory)
    while let file = enumerator?.nextObject() as? String {
      if file.hasSuffix("+generated.swift") {
        generatedFiles.append("\(directory)/\(file)")
      }
    }
    return generatedFiles
  }

  /// Computes SHA256 checksum of a file.
  static func computeSHA256(of file: String) -> String? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
      return nil
    }
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }

  /// Extracts checksum from the generated file and returns it along with the source path.
  static func extractChecksumAndSource(from outputFile: String) -> (checksum: String?, sourcePath: String?) {
    guard let content = try? String(contentsOfFile: outputFile),
          let firstLine = content.components(separatedBy: .newlines).first,
          firstLine.hasPrefix("// Checksum: "),
          let secondLine = content.components(separatedBy: .newlines).dropFirst().first,
          secondLine.hasPrefix("// Generated from: ") else {
      return (nil, nil)
    }
    let checksum = firstLine.replacingOccurrences(of: "// Checksum: ", with: "").trimmingCharacters(in: .whitespaces)
    let sourcePath = secondLine.replacingOccurrences(of: "// Generated from: ", with: "").trimmingCharacters(in: .whitespaces)
    return (checksum, sourcePath)
  }

  /// Determines if the output file should be regenerated based on checksum and source path.
  static func shouldGenerate(xcstringsFile: String, existingGeneratedFiles: [String]) -> (needsGeneration: Bool, outputFile: String) {
    let expectedFilename = (((xcstringsFile as NSString).lastPathComponent as NSString).deletingPathExtension) + "+generated.swift"
    for generatedFile in existingGeneratedFiles {
      let filename = (generatedFile as NSString).lastPathComponent
      if filename == expectedFilename {
        let checksumAndSource = extractChecksumAndSource(from: generatedFile)
        if let storedSourcePath = checksumAndSource.sourcePath, storedSourcePath == xcstringsFile {
          guard let storedChecksum = checksumAndSource.checksum,
                let currentChecksum = computeSHA256(of: xcstringsFile) else {
            return (true, generatedFile)
          }
          if storedChecksum != currentChecksum {
            return (true, generatedFile)
          } else {
            return (false, generatedFile)
          }
        }
      }
    }
    let directory = (xcstringsFile as NSString).deletingLastPathComponent
    let outputFile = "\(directory)/\(expectedFilename)"
    return (true, outputFile)
  }

  /// Validates and sets the source path.
  static func validateSource(_ path: String?) -> String {
    if let source = path {
      let absoluteSource = (source as NSString).isAbsolutePath ? source : "\(FileManager.default.currentDirectoryPath)/\(source)"
      guard FileManager.default.fileExists(atPath: absoluteSource) else {
        fatalError("Specified source file does not exist: \(absoluteSource)")
      }
      return absoluteSource
    } else {
      guard let defaultSource = findAllXCStringsFiles(in: FileManager.default.currentDirectoryPath).first else {
        fatalError("No .xcstrings file found in project root and no source provided.")
      }
      return defaultSource
    }
  }

  /// Validates and sets the destination path.
  static func validateDestination(_ path: String?, projectRoot: String, pluginMode: Bool) -> String {
    let destination = path ?? "\(projectRoot)/Resources/Strings+Generated.swift"
    let absoluteDestination = (destination as NSString).isAbsolutePath ? destination : "\(projectRoot)/\(destination)"
    let outputDirectory = (absoluteDestination as NSString).deletingLastPathComponent

    if !pluginMode {
      let projectRootURL = URL(fileURLWithPath: projectRoot).standardized
      let outputDirURL = URL(fileURLWithPath: outputDirectory).standardized
      guard outputDirURL.path.hasPrefix(projectRootURL.path) else {
        fatalError("Destination directory '\(outputDirectory)' is outside project root '\(projectRoot)'.")
      }
    }

    if !FileManager.default.fileExists(atPath: outputDirectory) {
      do {
        try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        print("Created output directory: \(outputDirectory)")
      } catch {
        fatalError("Error creating output directory '\(outputDirectory)': \(error)")
      }
    }
    return absoluteDestination
  }
}
