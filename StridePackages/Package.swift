// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "StridePackages",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DomainKit", targets: ["DomainKit"]),
        .library(name: "DataKit", targets: ["DataKit"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "TestSupport", targets: ["TestSupport"]),
        .library(name: "FeatureBuilder", targets: ["FeatureBuilder"]),
        .library(name: "FeatureLibrary", targets: ["FeatureLibrary"]),
        .library(name: "FeatureHistory", targets: ["FeatureHistory"]),
        .library(name: "FeatureRecords", targets: ["FeatureRecords"]),
        .library(name: "FeatureSettings", targets: ["FeatureSettings"])
    ],
    targets: [
        // MARK: - Domain (pure Swift, zero Apple SDKs beyond Foundation)
        .target(
            name: "DomainKit",
            dependencies: []
        ),
        .testTarget(
            name: "DomainKitTests",
            dependencies: ["DomainKit"]
        ),

        // MARK: - Data (Apple-framework adapters; depends on DomainKit only)
        .target(
            name: "DataKit",
            dependencies: ["DomainKit"]
        ),
        .testTarget(
            name: "DataKitTests",
            dependencies: ["DataKit", "DomainKit", "TestSupport"]
        ),

        // MARK: - Design System (leaf UI module; no DomainKit dependency)
        .target(
            name: "DesignSystem",
            dependencies: []
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"]
        ),

        // MARK: - Test Support (in-memory fakes of DomainKit ports)
        .target(
            name: "TestSupport",
            dependencies: ["DomainKit"]
        ),
        .testTarget(
            name: "TestSupportTests",
            dependencies: ["TestSupport", "DomainKit"]
        ),

        // MARK: - Feature modules (DomainKit + DesignSystem only, never DataKit)
        .target(
            name: "FeatureBuilder",
            dependencies: ["DomainKit", "DesignSystem"]
        ),
        .target(
            name: "FeatureLibrary",
            dependencies: ["DomainKit", "DesignSystem"]
        ),
        .target(
            name: "FeatureHistory",
            dependencies: ["DomainKit", "DesignSystem"]
        ),
        .target(
            name: "FeatureRecords",
            dependencies: ["DomainKit", "DesignSystem"]
        ),
        .target(
            name: "FeatureSettings",
            dependencies: ["DomainKit", "DesignSystem"]
        )
    ]
)
