# RAML to ISA

A macOS application that converts ServiceNow REST API RAML documentation into Internal Standards Architecture (ISA) documents.

## Requirements

- macOS 13.0+
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (installed automatically by `build.sh` if missing)

## Dependencies (via Swift Package Manager)

- [Yams](https://github.com/jpsim/Yams) — YAML parsing
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — ZIP file handling

## Build

```bash
chmod +x build.sh
./build.sh
```

This will:
1. Generate the Xcode project from `project.yml`
2. Resolve SPM dependencies
3. Build the app

Alternatively, open `RAMLtoISA.xcodeproj` in Xcode and build directly.
