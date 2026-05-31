// swift-tools-version: 6.0
//
// Isle — IsleCore SwiftPM package
// Copyright (C) 2026 Isle Contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version. See LICENSE at the repository root.

import PackageDescription

let package = Package(
    name: "IsleCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "IsleCore", targets: ["IsleCore"]),
        .executable(name: "IsleHooks", targets: ["IsleHooks"]),
        .executable(name: "IsleSetup", targets: ["IsleSetup"]),
    ],
    targets: [
        .target(
            name: "IsleCore"
        ),
        .executableTarget(
            name: "IsleHooks",
            dependencies: ["IsleCore"]
        ),
        .executableTarget(
            name: "IsleSetup",
            dependencies: ["IsleCore"]
        ),
        .testTarget(
            name: "IsleCoreTests",
            dependencies: ["IsleCore"]
        ),
    ]
)
