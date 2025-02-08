// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "swift-consolidate-plugin",
    products: [
        .plugin(
            name: "SwiftConsolidatePlugin",
            targets: ["SwiftConsolidatePlugin"]
        ),
    ],
    targets: [
        .plugin(
            name: "SwiftConsolidatePlugin",
            capability: .command(
                intent: .custom(
                    verb: "consolidate",
                    description: "Consolidates multiple files that match a predicate into a single file."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Write consolidated output data to a single file.")
                ]
            )
        )
    ]
)
