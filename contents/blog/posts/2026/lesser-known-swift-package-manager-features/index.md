---
type: post
title: "Lesser Known Swift Package Manager Features"
description: "Ffeature flags, Swift language mode configuration, and accessing environment values during builds."
publication: "2026-02-12 18:00:00"
tags: 
    - swift
authors:
    - tibor-bodecs
featured: true
---

In the last article I introduced Swift Package Traits, and I also realized some new package manager related stuff in some "next-gen" packages. In this post we're going to explore some lesser-known Swift Package Manager features.

Right now the Valkey library is state of the art, if you'd like to explore how to develop a proper library using modern structured concurerncy principles you should definitely have a look at Swift Valkey. Also Hummingbird is a great example, the project already includes some feature flags and it's based on modern Swift Concurrency. 

Lets begin with supporting modern Swift concurrency. In order to support Swift Concurrency you should enable swift langauge mode v6 or if you're already using Swift 6 language mode, you can still set language mode explicitly... but let me explain what's this all about first. 


## Swift language mode

The [Swift 6 language](https://www.swift.org/migration/documentation/migrationguide/) mode is opt-in Existing projects will not switch to this mode without configuration changes. 

it will enable strict concurrency checking, data race safety and a bunch of other Swift language features.

This means that, when you update your version or use a Swift toolchain that uses the Swift 6 compiler, unless you explicitly enable the Swift 6 language mode, your code will be compiled using the Swift 5 language mode.

The default language mode for // swift-tools-version: 6.0 in SwiftPM is also 6.0. If that causes issues, users can work around it by specifying a top level swiftLanguageVersion: [.v5] for their package or set it on a target-level:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "example",
    products: [
        .library(name: "Example", targets: ["Example"]),
    ],
    targets: [
        .target(
            name: "Example", 
            swiftSettings: [
                // set language mode for specific target
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "ExampleTests", 
            dependencies: [
                "Example",
            ]
        ),
    ],
    // set language mode for the whole package
    swiftLanguageModes: [.v5]
)
```

This way you can opt-out from langauge mode v6, but i highly recommend to follow along the migration guide and upgrade your soruce instead of using Swift language mode v5.

The package manager also allows users to enable upcoming and experimental features via flags. Let's dive in.

## Feature flags

There are two kinds of feature flags defined as static functions on SwiftSettings:

- `enableUpcomingFeature()` - Upcoming features
- `enableExperimentalFeature()` - Experimental features

Each function takes a string value, you can [print out](https://forums.swift.org/t/language-features-and-language-mode/81741/5) all of these by using the  `swift -print-supported-features` command. this will give you a complete list of names, also indicate which swift version is going to be enabled (or already enabled) that feature under the `enabled_in` key.

Lets explore some feature flags I'll show you what we enable nowadays. Since we are using swift-tools-version 6+ everything which is marked as enabled_in 6 is already there, we're opting in for some swift 7 features. This is how we define our package.swift files for our libraries:

```swift
// swift-tools-version: 6.1
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
    .enableUpcomingFeature("ExistentialAny"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
    .enableUpcomingFeature("MemberImportVisibility"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
    .enableUpcomingFeature("InternalImportsByDefault"),
    
    .enableExperimentalFeature("AvailabilityMacro=valkeySwift 1.0:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
    .enableUpcomingFeature("MemberImportVisibility"),

    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    
    // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
    // Require `any` for existential types.
    .enableUpcomingFeature("ExistentialAny")

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
    .enableUpcomingFeature("MemberImportVisibility")

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
    .enableUpcomingFeature("InternalImportsByDefault")

    .enableExperimentalFeature("AvailabilityMacro=Configuration 1.0:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0")
]

   { "name": "ExistentialAny", "migratable": true, "categories": ["ExistentialAny"], "enabled_in": "7" },
      { "name": "InternalImportsByDefault", "enabled_in": "7" },
      { "name": "MemberImportVisibility", "migratable": true, "categories": ["MemberImportVisibility"], "enabled_in": "7" },
      { "name": "InferIsolatedConformances", "migratable": true, "categories": ["IsolatedConformances"], "enabled_in": "7" },
      { "name": "NonisolatedNonsendingByDefault", "migratable": true, "categories": ["NonisolatedNonsendingByDefault"], "enabled_in": "7" },
      { "name": "ImmutableWeakCaptures", "enabled_in": "7" }
      

let package = Package(
    name: "example",
    products: [
        .library(name: "Example", targets: ["Example"]),
    ],
    targets: [
        .target(
            name: "Example", 
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ExampleTests", 
            dependencies: [
                "Example",
            ]
        ),
    ],
)
```


https://gist.github.com/ole/478874632fca61869928a0cc0a956972

https://github.com/kavon/swift-evolution/blob/suppressed-associated-types/proposals/NNNN-suppressed-associated-types.md


https://github.com/search?q=repo%3Aswiftlang%2Fswift-evolution+Upcoming+Feature+Flag&type=code


`@available(Configuration 1.0, *)`
public protocol ConfigSnapshotProtocol: Sendable {

`@available(valkeySwift 1.0, *)`

https://developer.apple.com/documentation/packagedescription/swiftsetting/interoperabilitymode(_:_:)

static func defaultIsolation(
    _ isolation: MainActor.Type?,
    _ condition: BuildSettingCondition? = nil
) -> SwiftSetting

static func strictMemorySafety(_ condition: BuildSettingCondition? = nil) -> SwiftSetting
static func interoperabilityMode(
    _ mode: SwiftSetting.InteroperabilityMode,
    _ condition: BuildSettingCondition? = nil
) -> SwiftSetting

## Environment

let spiGenerateDocs = ProcessInfo.processInfo.environment["SPI_GENERATE_DOCS"] != nil

if Context.environment["ENABLE_VALKEY_BENCHMARKS"] != nil {


https://github.com/tayloraswift/swift-unidoc/blob/master/Package.swift
https://github.com/toucansites/toucan/blob/main/Package.swift

var gitCommitHash: String {
    if let git = Context.gitInformation {
        let base = git.currentCommit
        return git.hasUncommittedChanges ? "\(base)-dev" : base
    }
    return "untracked"
}
