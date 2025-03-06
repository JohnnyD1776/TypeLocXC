# TypeLocXC - Type-Safe Localization for Swift

The TypeLocXC Swift package provides a convenient way to generate type-safe access to localized strings from an .xcstrings file in your Xcode project. This guide will walk you through the process of integrating the package into your project, setting up a build script and using it with or without a configuration file.

## Features
- Converts `.xcstrings` files into a type-safe `Llon` enum.
- Supports configuration via a `TypeLocXC.ypml` file.
- Auto-detects project root and `.xcstrings` files if no arguments are provided.
- Creates the `Resources` directory if it doesn't exist during auto-detection.
- Handles format specifiers like `%s`,  %d, %`@  etc., with appropriate Swift types.

## Prerequisites
- Swift 5.9 or later.
- An Xcode project with at least one `.xcstrings` file.

## Installation
1. In Xcode, go to **File > Add Packages**.
2. Enter `https://github.com/JohnnyD1776/TypeLocXC.git`
3. Select latest version.
4. Select a target for TypeLocXC

## Running as a Plugin in XCode
TypeLocXC includes a plugin to automatically build corresponding Type Safe references for each xcstrings file. To enable the plugin:
1. Select your Target Build Phase
2. Add TypeLocXCPlugin to `Run Build Tool Plugins`
3. When you initially build, the plugin will fail permissions
4. In Build Report Navigator, Select TypeLocXCPlugin and enable Run permissions

#### Note: You will need to run the Build atleast once before Type Safe entries are accessible. 

## Running from the command line
You can run TypeLocXC from the command line with parameters.

1. open the `TypeLocXC Package directory`.
2. run `swift build --configuration release`
3. from your  XCode Project directory, run `[TypeLocXC Package directory]/.build/release/TypeLocXC`

#### Note: Add the Generated File to your project target.

## Configuration (Optional)
Create a `TypeLocXC.yml` file in your project root to customize the script behavior:
``yaml
input: "path/to/strings.xcstrings"
output: "Resources/Strings+Generated.swift"
``

### Automatic Detection
If no arguments or config file are provided:
- The script auto-detects the project root (looking for `.xcodeproj or `.xcworkspace`).
- It then looks for a `TypeLocXC.ypml` file in the project root.
- If no config is found, it defaults to the first `.xcstrings` file it finds and outputs to `Resources/Strings+Generated.swift`.
- If the `Resources` folder doesn't exist, the script creates it.

## Usage of L10n Enum

#### Example Usage
For an `.xcstrings` entry:
``"json
{  "greeting": {
    "stringUnit": {
      "value": "Hello, %@!"
    }
  }
}
``

The generated `L10n` enum allows:
``swift
let message = L10n.greeting("World") // Returns "Hello, World!"
``

#### Supported Format Specifiers
- `%@
: `String`
- `%d`, `%i`
: `Int`
- `%f`
: `Double`
- `%s`
: `String` (C-style string)

## Notes
- Ensure the `.xcstrings` file is well-formed.
- The script overrrites the output file if it exists.
