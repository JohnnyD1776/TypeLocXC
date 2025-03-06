//
//  ArgumentParser.swift
//  TypeLocXC
//
//  Created by John Durcan on 06/03/2025.
//
import Foundation

struct CommandLineArguments {
  let pluginMode: Bool
  let sourceArg: String?
  let destinationArg: String?
  let configArg: String?
  let positionalArgs: [String]

  init(arguments: [String]) {
    var pluginMode = false
    var sourceArg: String?
    var destinationArg: String?
    var configArg: String?
    var positionalArgs: [String] = []

    var i = 0
    while i < arguments.count {
      let arg = arguments[i]
      switch arg {
      case "--help", "-?":
        print("HELP OUTPUT:")
        print(Self.helpMessage())
        fflush(stdout)
        exit(0)
      case "--plugin-mode":
        pluginMode = true
        i += 1
      case "--source" where i + 1 < arguments.count:
        sourceArg = arguments[i + 1]
        i += 2
      case "--destination" where i + 1 < arguments.count:
        destinationArg = arguments[i + 1]
        i += 2
      case "--config" where i + 1 < arguments.count:
        configArg = arguments[i + 1]
        i += 2
      default:
        if arg.hasPrefix("--") {
          print("Unknown flag: \(arg)")
          exit(1)
        } else {
          positionalArgs.append(arg)
          i += 1
        }
      }
    }

    self.pluginMode = pluginMode
    self.sourceArg = sourceArg
    self.destinationArg = destinationArg
    self.configArg = configArg
    self.positionalArgs = positionalArgs
  }

  static func helpMessage() -> String {
        """
        Usage: TypeLocXC [OPTIONS] [SOURCE DESTINATION]
        
        Generate type-safe Swift code from .xcstrings files.
        
        Options:
          --source <file>        Specify the input .xcstrings file
          --destination <file>   Specify the output Swift file
          --config <file>        Use a custom YAML config file (e.g., config.yml)
          --plugin-mode          Run in plugin mode (used by SPM/Xcode build tool)
          --help, -?             Display this help message
        
        Positional Arguments:
          SOURCE                 Input .xcstrings file (optional if --source is used)
          DESTINATION            Output Swift file (optional if --destination is used)
        
        Behavior:
          - If run with --plugin-mode, processes files as specified by the plugin.
          - If run without parameters, enters auto mode: finds all .xcstrings files in the project
            and generates <name>+generated.swift files in the same directory.
          - Otherwise, uses config, positional arguments, or defaults to generate a single file.
        
        Examples:
          TypeLocXC --source Custom.xcstrings --destination Generated.swift
          TypeLocXC --config myconfig.yml
          TypeLocXC (runs in auto mode)
        """
  }
}
