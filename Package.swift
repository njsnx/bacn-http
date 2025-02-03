// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "bacn-http",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "BacnHttp", targets: ["BacnHttp"]),
    
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", branch: "main"),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", branch: "main")
        
    ],
    targets: [
        .target(
            name: "BacnHttp",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                ]
        ),
    ]
)
