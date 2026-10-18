// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenshotShelf",
    platforms: [.macOS(.v13)],
    targets: [
        // The protocol both sides of the XPC connection agree on.
        .target(
            name: "OCRShared",
            path: "Sources/OCRShared"
        ),
        // The menu bar app.
        .executableTarget(
            name: "ScreenshotShelf",
            dependencies: ["OCRShared"],
            path: "Sources/ScreenshotShelf"
        ),
        // The text-reading helper, bundled into the app as an XPC service.
        .executableTarget(
            name: "OCRService",
            dependencies: ["OCRShared"],
            path: "Sources/OCRService"
        )
    ]
)
