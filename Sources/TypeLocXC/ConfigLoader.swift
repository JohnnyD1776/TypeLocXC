//
//  ConfigLoader.swift
//  TypeLocXC
//
//  Created by John Durcan on 06/03/2025.
//

import Foundation
import Yams

struct ConfigLoader {
  static func loadConfig(from path: String, isArg: Bool? = nil) -> (source: String, destination: String)? {
    let configPath = (path as NSString).isAbsolutePath ? path : "\(FileManager.default.currentDirectoryPath)/\(path)"
    guard FileManager.default.fileExists(atPath: configPath) else {
      if isArg == true {
        fatalError("Config file not found at: \(configPath)")
      } else {
        print("Config file not found at: \(configPath)")
        return nil
      }
    }
    print("Config file found at: \(configPath)")
    do {
      let configData = try String(contentsOfFile: configPath)
      guard let config = try Yams.load(yaml: configData) as? [String: String],
            let source = config["source"],
            let destination = config["destination"] else {
        print("Invalid format in '\(configPath)'. Expected 'source' and 'destination' keys.")
        return nil
      }
      return (source, destination)
    } catch {
      print("Error reading config file '\(configPath)': \(error)")
      return nil
    }
  }
}
