// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "SwiftyEigen",
    products: [
        .library(
            name: "SwiftyEigen",
            targets: ["ObjCEigen"/*, "SwiftyEigen"*/]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ObjCEigen",
            path: "Sources/ObjC",
            resources: [
                .copy("data-zip/bundle_mock_smart_idreader.zip"),
                .copy("lib/libsmartid-universal.a")
            ],
            cxxSettings: [
                .headerSearchPath("../CPP/"),
//                .define("EIGEN_MPL2_ONLY")
            ]
        ),
//        .target(
//            name: "SwiftyEigen",
//            dependencies: ["ObjCEigen"],
//            path: "Sources/Swift"
//        )
    ]
)


//let package = Package(name: "Alamofire",
//
//  targets: [.target(name: "Alamofire",
//                    path: "Source",
//                    linkerSettings: [.linkedFramework("CFNetwork",
//                                                      .when(platforms: [.iOS,
//                                                                        .macOS,
//                                                                        .tvOS,
//                                                                        .watchOS]))]),
//  swiftLanguageVersions: [.v5])
