// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FolioReaderKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "FolioReaderKit",
            targets: ["FolioReaderKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ZipArchive/ZipArchive.git", exact: "2.4.3"),
        .package(url: "https://github.com/cxa/MenuItemKit.git", from: "3.0.0"),
        .package(path: "Vendor/ZFDragableModalTransition"),
        .package(url: "https://github.com/tadija/AEXML.git", from: "4.2.0"),
        .package(url: "https://github.com/ArtSabintsev/FontBlaster.git", from: "5.0.0"),
        .package(path: "Vendor/JSQWebViewController"),
        .package(url: "https://github.com/realm/realm-cocoa.git", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "FolioReaderKit",
            dependencies: [
                .product(name: "ZipArchive", package: "ZipArchive"),
                "MenuItemKit",
                "ZFDragableModalTransition",
                "AEXML",
                "FontBlaster",
                "JSQWebViewController",
                .product(name: "RealmSwift", package: "realm-cocoa")
            ],
            path: ".",
            exclude: [
                "Source/Resources",
                "Source/FolioReaderKit.h",
                "Example",
                "Vendor/ZFDragableModalTransition",
                "Vendor/JSQWebViewController",
                "demo-nativescript",
                "docs",
                "FolioReaderKitTests"
            ],
            sources: [
                "Source",
                "Vendor/HAControls",
                "Vendor/SMSegmentView"
            ],
            resources: [
                .process("Source/Resources")
            ],
            publicHeadersPath: "Source"
        ),
        .testTarget(
            name: "FolioReaderKitTests",
            dependencies: ["FolioReaderKit"],
            path: "FolioReaderKitTests"
        )
    ]
)
