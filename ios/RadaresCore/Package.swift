// swift-tools-version:5.7
// Núcleo de la app: modelos, geometría y motor de avisos. Sin interfaz ni GPS,
// para poder comprobarlo en el iMac (sin Xcode) con `swift run RadaresChecks`.
import PackageDescription

let package = Package(
    name: "RadaresCore",
    platforms: [.iOS(.v16), .macOS(.v12)],
    products: [
        .library(name: "RadaresCore", targets: ["RadaresCore"]),
    ],
    targets: [
        .target(name: "RadaresCore"),
        .executableTarget(name: "RadaresChecks", dependencies: ["RadaresCore"]),
    ]
)
