//
//  CodeGenerator.swift
//  TypeLocXC
//
//  Created by John Durcan on 06/03/2025.
//

import Foundation

// MARK: - Generation Function
//
//  CodeGenerator.swift
//  TypeLocXC
//
//  Created by John Durcan on 06/03/2025.
//
struct CodeGenerator {

  /// Create the Type Safe Swift File Output
  static func generateOutput(from xcstringsPath: String, to outputFilePath: String) {
    guard let checksum = FileHandler.computeSHA256(of: xcstringsPath) else {
      fatalError("Failed to compute checksum for \(xcstringsPath)")
    }

    guard let data = try? Data(contentsOf: URL(fileURLWithPath: xcstringsPath)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: Any] else {
      fatalError("Failed to read or parse .xcstrings file at \(xcstringsPath)")
    }

    var output = """
        // Checksum: \(checksum)
        // Generated from: \(xcstringsPath)
        // Auto-generated file for type-safe access to .xcstrings. Do not edit manually.
        import Foundation
        
        /// The `L10n` enum provides type-safe access to localized strings.
        /// - Nested enums reflect the key hierarchy (e.g., `L10n.ViewName.Section.title`).
        /// - Simple strings are accessed via `static let` properties (e.g., `L10n.ViewName.Section.title`).
        /// - Parameterized strings use `static func` with parameters (e.g., `L10n.ViewName.Section.string(p1: "something")`).
        /// - Plural strings include a `count` parameter (e.g., `L10n.ViewName.Section.itemsCount(count: 5)`).
        /// 
        /// Supported format specifiers:
        /// - `%@`: `String`
        /// - `%c`: `Character`
        /// - `%d`, `%i`: `Int`
        /// - `%lld`: `Int64`
        /// - `%o`, `%u`, `%x`, `%X`: `UInt`
        /// - `%f`, `%e`, `%g`, etc.: `Double`
        /// - `%s`: `String`
        /// - `%p`: `UnsafeRawPointer`
        /// - `%%`: No argument (literal percent sign)

        enum L10n {
        """

    let keys = strings.keys.sorted()
    var currentPath: [String] = []
    var indent = 4 // Starting inside enum L10n
    var usedNames: [String: Set<String>] = [:]

    for key in keys {
      let parts = splitKey(key)
      let commonLength = zip(currentPath, parts).prefix(while: { $0 == $1 }).count

      // Close enums no longer needed
      for _ in commonLength..<currentPath.count {
        indent -= 4
        output += String(repeating: " ", count: indent) + "}\n"
      }

      // Open new enums for new parts
      for i in commonLength..<parts.count - 1 {
        let enumPart = enumName(from: parts[i])
        let pathKey = (currentPath + parts[0...i]).joined(separator: ".")
        if usedNames[pathKey] == nil {
          usedNames[pathKey] = Set<String>()
        }
        var uniqueEnumName = enumPart
        var counter = 1
        while usedNames[pathKey]!.contains(uniqueEnumName) {
          uniqueEnumName = "\(enumPart)_\(counter)"
          counter += 1
        }
        usedNames[pathKey]!.insert(uniqueEnumName)
        output += String(repeating: " ", count: indent) + "enum \(uniqueEnumName) {\n"
        indent += 4
      }

      // Generate the leaf
      let baseName = propertyName(from: parts.last!)
      let pathKey = currentPath.joined(separator: ".")
      if usedNames[pathKey] == nil {
        usedNames[pathKey] = Set<String>()
      }
      var uniqueName = baseName
      var counter = 1
      while usedNames[pathKey]!.contains(uniqueName) {
        uniqueName = "\(baseName)_\(counter)"
        counter += 1
      }
      usedNames[pathKey]!.insert(uniqueName)

      if let valueDict = strings[key] as? [String: Any],
         let localizations = valueDict["localizations"] as? [String: Any],
         let enLocalization = localizations["en"] as? [String: Any] {
        if let variation = enLocalization["variation"] as? [String: Any],
           let plural = variation["plural"] as? [String: Any] {
          generatePluralFunction(for: uniqueName, pluralData: plural, output: &output, indent: indent, key: key)
        } else if let stringUnit = enLocalization["stringUnit"] as? [String: String],
                  let stringValue = stringUnit["value"] {
          let specifiers = extractSpecifiers(from: stringValue)
          if specifiers.isEmpty {
            output += String(repeating: " ", count: indent) + "static let \(uniqueName) = NSLocalizedString(\"\(key)\", tableName: \"Localizable\", comment: \"\")\n"
          } else {
            let parameters = generateParameters(for: specifiers)
            let arguments = generateArguments(for: specifiers)
            output += String(repeating: " ", count: indent) + "static func \(uniqueName)(\(parameters)) -> String {\n"
            output += String(repeating: " ", count: indent + 4) + "return String(format: NSLocalizedString(\"\(key)\", tableName: \"Localizable\", comment: \"\"), \(arguments))\n"
            output += String(repeating: " ", count: indent) + "}\n"
          }
        }
      }

      currentPath = Array(parts.dropLast())
    }

    // Close remaining enums
    for _ in currentPath {
      if indent > 0 {
        indent -= 4
        output += String(repeating: " ", count: indent) + "}\n"
      } else {
        print("Warning: Attempted to close more enums than were opened. Indent is already zero.")
        break
      }
    }

    output += "}\n"

    do {
      try output.write(toFile: outputFilePath, atomically: true, encoding: .utf8)
      print("✅ Generated \(outputFilePath) successfully!")
    } catch {
      fatalError("Failed to write to \(outputFilePath): \(error)")
    }
  }

  // MARK: - Helper Functions

  /// Split key into parts using dots and underscores as separators
  private static func splitKey(_ key: String) -> [String] {
    let separators = CharacterSet(charactersIn: "._")
    return key.components(separatedBy: separators).filter { !$0.isEmpty }
  }

  /// Sanitize identifier by removing invalid characters
  private static func sanitizeIdentifier(_ s: String, isEnum: Bool = false) -> String {
    let keywords: Set<String> = [
      "class", "deinit", "enum", "extension", "func", "import", "init", "let", "operator", "protocol",
      "static", "struct", "subscript", "typealias", "var", "break", "case", "continue", "default", "do",
      "else", "fallthrough", "for", "if", "in", "return", "switch", "where", "while", "as", "false", "is",
      "nil", "self", "Self", "super", "true", "_", "associativity", "convenience", "dynamic", "didSet",
      "final", "get", "infix", "inout", "lazy", "left", "mutating", "none", "nonmutating", "optional",
      "override", "postfix", "precedence", "prefix", "required", "right", "set", "Type", "unowned", "weak",
      "willSet"
    ]

    var sanitized = ""
    var lastWasUnderscore = false
    for char in s {
      if char.isLetter || char.isNumber {
        sanitized.append(char)
        lastWasUnderscore = false
      } else if !lastWasUnderscore {
        sanitized.append("_")
        lastWasUnderscore = true
      }
    }
    sanitized = sanitized.trimmingCharacters(in: .init(charactersIn: "_"))
    if sanitized.isEmpty {
      sanitized = "unknown"
    }
    if keywords.contains(sanitized.lowercased()) {
      sanitized += "_"
    }
    if sanitized.first?.isNumber == true {
      sanitized = "_\(sanitized)"
    }
    if isEnum {
      if let first = sanitized.first, first.isLowercase {
        sanitized = String(first.uppercased()) + sanitized.dropFirst()
      }
    } else {
      if let first = sanitized.first, first.isUppercase {
        sanitized = String(first.lowercased()) + sanitized.dropFirst()
      }
    }
    return sanitized
  }

  /// Format part as an enum name (first letter uppercase)
  private static func enumName(from part: String) -> String {
    return sanitizeIdentifier(part, isEnum: true)
  }

  /// Format part as a property/function name (first letter lowercase)
  private static func propertyName(from part: String) -> String {
    return sanitizeIdentifier(part, isEnum: false)
  }

  /// Extract format specifiers from a string
  private static func extractSpecifiers(from string: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: "%[^diouxXfFeEgGaAcCsSpn%]*[diouxXfFeEgGaAcCsSpn%]")
    let matches = regex.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
    return matches.map { String(string[Range($0.range, in: string)!]) }
  }

  /// Map format specifier to Swift type
  private static func mapSpecifierToType(_ specifier: String) -> String {
    let typePart = specifier.components(separatedBy: CharacterSet(charactersIn: "0123456789$")).last ?? specifier
    let typeChar = typePart.last
    switch typeChar {
    case "@": return "String"
    case "c": return "Character"
    case "d", "i": return "Int"
    case "u", "o", "x", "X": return "UInt"
    case "f", "F", "e", "E", "g", "G", "a", "A": return "Double"
    case "s": return "String"
    case "p": return "UnsafeRawPointer"
    case "%": return ""
    case "l":
      if typePart.hasSuffix("ld") || typePart.hasSuffix("lld") {
        return "Int64"
      } else if typePart.hasSuffix("lu") || typePart.hasSuffix("llu") {
        return "UInt64"
      } else {
        return "Any"
      }
    default:
      print("Warning: Unknown type character '\(typePart)' in specifier '\(specifier)', defaulting to Any")
      return "Any"
    }
  }

  /// Generate function parameters from specifiers
  private static func generateParameters(for specifiers: [String]) -> String {
    specifiers.enumerated().map { (index, specifier) in
      let type = mapSpecifierToType(specifier)
      if type.isEmpty { return "" }
      return "_ p\(index + 1): \(type)"
    }
    .filter { !$0.isEmpty }
    .joined(separator: ", ")
  }

  /// Generate arguments for String(format:)
  private static func generateArguments(for specifiers: [String]) -> String {
    specifiers.enumerated()
      .filter { mapSpecifierToType($1) != "" }
      .map { index, _ in "p\(index + 1)" }
      .joined(separator: ", ")
  }

  /// Generate plural function with count and optional additional parameters
  private static func generatePluralFunction(for name: String, pluralData: [String: Any], output: inout String, indent: Int, key: String) {
    let countParam = "_ count: Int"
    if let firstCategory = pluralData.keys.first,
       let categoryData = pluralData[firstCategory] as? [String: Any],
       let stringUnit = categoryData["stringUnit"] as? [String: String],
       let stringValue = stringUnit["value"] {
      let specifiers = extractSpecifiers(from: stringValue)
      let additionalParams = generateParameters(for: specifiers)
      let arguments = generateArguments(for: specifiers)
      let params = [countParam] + (additionalParams.isEmpty ? [] : [additionalParams])
      let paramString = params.joined(separator: ", ")
      let argList = ["count"] + (arguments.isEmpty ? [] : [arguments])

      output += String(repeating: " ", count: indent) + "static func \(name)(\(paramString)) -> String {\n"
      output += String(repeating: " ", count: indent + 4) + "let format = NSLocalizedString(\"\(key)\", tableName: \"Localizable\", comment: \"\")\n"
      output += String(repeating: " ", count: indent + 4) + "return String.localizedStringWithFormat(format, \(argList.joined(separator: ", ")))\n"
      output += String(repeating: " ", count: indent) + "}\n"
    } else {
      output += String(repeating: " ", count: indent) + "static func \(name)(\(countParam)) -> String {\n"
      output += String(repeating: " ", count: indent + 4) + "let format = NSLocalizedString(\"\(key)\", tableName: \"Localizable\", comment: \"\")\n"
      output += String(repeating: " ", count: indent + 4) + "return String.localizedStringWithFormat(format, count)\n"
      output += String(repeating: " ", count: indent) + "}\n"
    }
  }
}
