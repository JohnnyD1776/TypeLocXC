//
//  CodeGenerator.swift
//  TypeLocXC
//
//  Created by John Durcan on 06/03/2025.
//

import Foundation

// MARK: - Generation Function
struct CodeGenerator {

  /// Create the Type Safe swift File Output
  /// Create the Type Safe swift File Output
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
        
        /// The `L10n` enum provides functions for each string key in `Localizable.xcstrings`.
        /// - Keys with special characters (e.g., "%", "$") are sanitized and converted to underscores.
        /// - For simple strings without format specifiers, the function takes no parameters.
        /// - For strings with format specifiers (`%d`, `%@`, `%f`), the function includes labeled parameters (`p1`, `p2`, etc.) with appropriate types.
        /// - For plural strings, pass the count as the first parameter (`count: Int`), followed by additional parameters if needed.
        ///
        /// Example usage:
        /// ```swift
        /// let mainMenu = L10n.GameOver_backToMain()  // "Main Menu"
        /// let score = L10n.HUD_Label_score_Int(p1: 42)   // "Score: 42"
        /// let pages = L10n.Page_lld_of_lld_Int64_Int64(p1: 1, p2: 5)  // "Page 1 of 5"
        /// let oneApple = L10n.apple_count_Int(count: 1)     // "1 apple"
        /// ```
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

    for (key, value) in strings {
      guard let valueDict = value as? [String: Any],
            let localizations = valueDict["localizations"] as? [String: Any],
            let enLocalization = localizations["en"] as? [String: Any] else {
        continue
      }

      if let variation = enLocalization["variation"] as? [String: Any],
         let plural = variation["plural"] as? [String: Any] {
        if let firstCategory = plural.keys.first,
           let categoryData = plural[firstCategory] as? [String: Any],
           let stringUnit = categoryData["stringUnit"] as? [String: String],
           let stringValue = stringUnit["value"] {
          let specifiers = extractSpecifiers(from: stringValue)
          let safeKey = sanitizeKey(key, specifiers: specifiers)
          generatePluralFunction(for: safeKey, pluralData: plural, output: &output)
        } else {
          let safeKey = sanitizeKey(key, specifiers: [])
          generatePluralFunction(for: safeKey, pluralData: plural, output: &output)
        }
      } else if let stringUnit = enLocalization["stringUnit"] as? [String: String],
                let stringValue = stringUnit["value"] {
        let specifiers = extractSpecifiers(from: stringValue)
        let safeKey = sanitizeKey(key, specifiers: specifiers)
        let parameters = generateParameters(for: specifiers)
        let arguments = generateArguments(for: specifiers)

        if specifiers.isEmpty {
          output += """
                            
                            static func \(safeKey)() -> String {
                                return NSLocalizedString("\(key)", tableName: "Localizable", comment: "")
                            }
                            """
        } else {
          output += """
                            
                            static func \(safeKey)(\(parameters)) -> String {
                                return String(format: NSLocalizedString("\(key)", tableName: "Localizable", comment: ""), \(arguments))
                            }
                            """
        }
      }
    }

    output += "\n}\n"

    do {
      try output.write(toFile: outputFilePath, atomically: true, encoding: .utf8)
      print("✅ Generated \(outputFilePath) successfully!")
    } catch {
      fatalError("Failed to write to \(outputFilePath): \(error)")
    }
  }

  private static func extractSpecifiers(from string: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: "%[^diouxXfFeEgGaAcCsSpn%]*[diouxXfFeEgGaAcCsSpn%]")
    let matches = regex.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
    return matches.map { String(string[Range($0.range, in: string)!]) }
  }


  private static func mapSpecifierToType(_ specifier: String) -> String {
    // Handle positional specifiers (e.g., %1$lld) by focusing on the type part
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
    case "%": return "" // For %%
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

  private static func sanitizeKey(_ key: String, specifiers: [String]) -> String {
    var safeKey = key
    for specifier in specifiers {
      safeKey = safeKey.replacingOccurrences(of: specifier, with: "")
    }
    safeKey = safeKey.replacingOccurrences(of: ".", with: "_")
    let specialChars = CharacterSet.punctuationCharacters.union(.symbols).subtracting(CharacterSet(charactersIn: "_"))
    safeKey = safeKey.components(separatedBy: specialChars).joined(separator: "_")
    safeKey = safeKey.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    while safeKey.contains("__") {
      safeKey = safeKey.replacingOccurrences(of: "__", with: "_")
    }
    if !specifiers.isEmpty {
      let types = specifiers.map { mapSpecifierToType($0) }.filter { !$0.isEmpty }
      if !types.isEmpty {
        safeKey += "_\(types.joined(separator: "_"))"
      }
    }
    if let firstChar = safeKey.first, firstChar.isNumber {
      safeKey = "_\(safeKey)"
    }
    return String(safeKey.unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).union(.init(charactersIn: "_")).contains($0) })
  }

  private static func generateParameters(for specifiers: [String]) -> String {
    specifiers.enumerated().map { (index, specifier) in
      let type = mapSpecifierToType(specifier)
      if type.isEmpty { return "" }
      return "p\(index + 1): \(type)"
    }
    .filter { !$0.isEmpty }
    .joined(separator: ", ")
  }

  private static func generateArguments(for specifiers: [String]) -> String {
    specifiers.enumerated()
      .filter { mapSpecifierToType($1) != "" }
      .map { index, _ in "p\(index + 1)" }
      .joined(separator: ", ")
  }

  private static func generatePluralFunction(for key: String, pluralData: [String: Any], output: inout String) {
    let countParam = "count: Int"
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

      output += """
                    
                    static func \(key)(\(paramString)) -> String {
                        let format = NSLocalizedString("\(key)", tableName: "Localizable", comment: "")
                        return String.localizedStringWithFormat(format, \(argList.joined(separator: ", ")))
                    }
                    """
    } else {
      output += """
                    
                    static func \(key)(\(countParam)) -> String {
                        let format = NSLocalizedString("\(key)", tableName: "Localizable", comment: "")
                        return String.localizedStringWithFormat(format, count)
                    }
                    """
    }
  }
}
