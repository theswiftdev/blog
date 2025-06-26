---
type: post
title: "Type-safe and user-friendly error handling in Swift 6"
description: "Learn how to implement user-friendly, type-safe error handling in Swift 6 with structured diagnostics and a hierarchical error model."
publication: "2025-06-26 13:00:00"
tags: 
    - swift
authors:
    - tibor-bodecs
featured: true
---

Swift 6 brings an exciting new feature to the language: [typed throws](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md). This change makes error handling in Swift much more type-safe, allowing us to define exactly what kinds of errors a function can throw. It’s a small change on the surface, but it opens the door to writing cleaner, more reliable code.

Now, you might be wondering — how do we actually use this in practice? The idea I’m going to share with you came up during a conversation with my wife. She came up with this user-friendly layered error message model, and I turned it into a technique we even ended up using in [Toucan](https://toucansites.com/), our Swift-based static site generator at [Binary Birds](https://binarybirds.com/).

In this post, I’ll show you how this approach works and how you can use it to improve your own Swift projects.


## A custom error protocol

First of all, I was never satisfied with the built-in [LocalizedError](https://developer.apple.com/documentation/foundation/localizederror) protocol. Sure, its `errorDescription` property could be used as a user-facing error message, but sometimes it's more like a riddle, alongside [NSError](https://developer.apple.com/documentation/foundation/nserror)'s domains and codes. Additionally, if we stick to the base `Error` protocol, it can cause naming convention issues, or you have to write `Swift.Error`, which is very inconvenient.

That's the reason why I started to define my own protocol, using [Error](https://developer.apple.com/documentation/swift/error) as a base protocol, but with some additional functionalities:


```swift
public protocol SystemError: Error {
    // 1.
    var logMessage: String { get }
    // 2.
    var userFriendlyMessage: String { get }
    // 3.
    var underlyingErrors: [Error] { get }
    // 4.
    func logMessageStack() -> String
    // 5.
    func lookup<T: Error>(_ errorType: T.Type) -> T?
    // 6.
    func lookup<T: Error, V>(_ t: (T) -> V?) -> V?
}
```
Let me explain each point:

1. The log message used by developers to display the error.
2. The user-facing error message for your end users.
3. An array of underlying errors for structured error diagnostics.
4. The backtrace for developers to easily access the error hierarchy.
5. A lookup function to detect an error type in the stack.
6. A helper to simplify the lookup process, mainly for enum cases.

Now that we’ve covered the base idea, it’s time to dive into the more interesting part — the default implementations:

```swift
extension SystemError {
    
    // 1.
    public var underlyingErrors: [Error] { [] }

    // 2.
    public func lookup<T: Error>(
        _ errorType: T.Type
    ) -> T? {
        for error in underlyingErrors {
            if let match = error as? T {
                return match
            }
            if let match = (error as SystemError).lookup(errorType) {
                return match
            }
        }
        return nil
    }

    // 3.
    public func lookup<T: Error, V>(
        _ t: (T) -> V?
    ) -> V? {
        lookup(T.self).flatMap(t)
    }
    
    // 4.
    public func logMessageStack() -> String {
        format(error: self)
    }

    // MARK: -
    
    // 5.
    private func format(
        error: Error,
        prefix: String = "",
        isLast: Bool = true
    ) -> String {
        let type = type(of: error)
        
        var message: String
        var underlyingErrors: [Error]
        switch error {
        case let e as SystemError:
            message = e.logMessage
            underlyingErrors = e.underlyingErrors
        default:
            message = "\(error)"
            underlyingErrors = []
        }
        
        let branch = prefix.isEmpty ? "" : (isLast ? "└─ " : "├─ ")
        var output = "\(prefix)\(branch)\(type): \"\(message)\"\n"
        let childPrefix = prefix + (isLast ? "    " : "│   ")
        
        let childCount = underlyingErrors.count
        for (idx, error) in underlyingErrors.enumerated() {
            let lastChild = (idx == childCount - 1)
            output += format(
                error: error,
                prefix: childPrefix,
                isLast: lastChild
            )
        }
        
        return output
    }
}
```

This extension adds the default functionalities to the `SystemError` protocol to help with structured error handling and diagnostics:

1. Provides an empty array by default, meaning there are no nested errors unless explicitly overridden.

2. Recursively searches the error stack for a specific error type. If a match is found, it returns it. Otherwise, it keeps searching through the underlying errors.

3. A convenience method for transforming the result of a lookup. It finds the error and applies a closure to extract a specific value.

4. Generates a string representation of the error hierarchy, making it easier for developers to trace what went wrong.

5. A private helper function used by `logMessageStack()` to recursively format the full error tree into a readable string with branch indicators.

By using this extension, creating a custom error object becomes trivial — let me show how this works in the next section.

## Defining error objects

As far as I noticed, sometimes developers tend to forget that we can use both `struct` and `enum` as an error type. Let me show you how to use both — that's going to be a good starting point to come up with an example use-case scenario.

First, we create a custom error `struct` by satisfying the `SystemError` protocol requirements using standard variables:

```swift
struct MyCustomErrorStruct: SystemError {
    var logMessage: String
    var userFriendlyMessage: String
    var underlyingErrors: [any Error]
}
```

That's pretty simple, we don't need to implement a custom lookup nor the logStack function, since that will come from the SystemError extension.

We can also build an `enum` as an error representation. For the sake of simplicity, I'm going to showcase only one demo case (`.ouch`) this time — but of course, you can have multiple enum cases, even with associated types to pass around additional context for your error messages:


```swift
enum MyCustomErrorEnum: SystemError {
    
    case ouch
    
    var logMessage: String {
        switch self {
        case .ouch:
            "Ouch this is not good, provide more info..."
        }
    }
    
    var userFriendlyMessage: String {
        switch self {
        case .ouch:
            "Ouch something went wrong."
        }
    }
}
```
Before the usage example, let's focus a bit on the `Foundation` framework for a second.

## Foundation errors

Funny thing is that `NSError` follows a similar approach regarding error hierarchy. We can actually conform `NSError` to our new `SystemError` protocol without providing an `underlyingErrors` array, since that type has a built-in property for this purpose:

```swift
import Foundation

extension NSError: SystemError {

    public var logMessage: String {
        "\(domain):\(code) - \(localizedDescription)"
    }

    public var userFriendlyMessage: String {
        "\(localizedDescription)"
    }
}
```

One common use case is to detect decoding errors. For this purpose, I always include a similar snippet in my projects — it allows me to get the exact reason why a decoding issue occurred in the first place:

```swift
import Foundation

extension DecodingError.Context {

    // 1.
    var logMessage: String {
        if codingPath.isEmpty {
            return debugDescription
        }
        return codingPath.map(\.description).joined(separator: ".")
    }
}

extension DecodingError: SystemError {

    public var logMessage: String {
        switch self {
        // 2.
        case let .dataCorrupted(context):
            "Data corrupted: \(context.logMessage)"
        // 3.
        case let .keyNotFound(key, context):
            "Key not found: \(key) - \(context.logMessage)"
        // 4.
        case let .typeMismatch(type, context):
            "Type mismatch: \(type) - \(context.logMessage)"
        // 5.
        case let .valueNotFound(type, context):
            "Value not found: \(type) - \(context.logMessage)"
        default:
            "\(self)"
        }
    }

    public var userFriendlyMessage: String {
        localizedDescription
    }
}
```

This extension helps convert `DecodingError` values into clear, structured messages by conforming them to the `SystemError` protocol:

1. Generates a readable message from the coding path. If the path is empty, it falls back to the debug description. Otherwise, it joins the path components with dots for clarity.

2. Handles corrupted data errors and includes the context's log message for pinpointing the issue.

3. Indicates that a required key was missing during decoding. The message includes the key and a detailed context path.

4. Occurs when the decoded value has a different type than expected. The message names the type and adds the context for debugging.

5. Similar to `keyNotFound`, but triggered when a value is absent. Again, it includes the type and context path for accuracy.

## Using typed throws

By having these protocols and extensions in our codebase, we can now focus on the real deal — using the new typed-throws feature in Swift 6. Let me create two separate throwing function use-cases:

```swift
enum UseCases {

    // 1.
    static func testHierarchy(

    ) throws(MyCustomErrorStruct) {
        throw .init(
            logMessage: "This is a custom error struct",
            userFriendlyMessage: "Something went wrong.",
            underlyingErrors: [
                MyCustomErrorEnum.ouch
            ]
        )
    }

    // 2.
    static func testDecodingError(

    ) throws(MyCustomErrorStruct) {
        do {
             let invalidJSON = """
                 not-a-valid-json
                 """
             
             struct Foo: Decodable {
                 var bar: String
             }

             let decoder = JSONDecoder()
             let _ = try decoder.decode(
                Foo.self,
                from: invalidJSON.data(using: .utf8)!
             )
        }
         catch {
            let message = "Sorry, our server is not working well."
            throw .init(
                logMessage: "Could not decode Foo type.",
                userFriendlyMessage: message,
                underlyingErrors: [error]
            )
        }
    }
}
```

The new syntax for typed-throws is `throws(MyErrorType)`, which declares that a function can only throw errors of the specified type. We use this for our test functions to throw custom error structures in both cases:

1. Demonstrates how to manually throw a `MyCustomErrorStruct` instance with a clear log message, a user-facing error message, and an array of underlying errors — in this case, a single enum case `.ouch` from `MyCustomErrorEnum`.

2. Attempts to decode invalid JSON, which will trigger a decoding error. It catches the thrown error, then wraps it in a `MyCustomErrorStruct` with a custom log message and user-friendly message, including the original decoding error in the `underlyingErrors` array.

Let's have a look at the call side from a developer / end user perspective:

```swift
do {
    try UseCases.testHierarchy()
}
catch let error as SystemError {
    // 1.
    print(error.userFriendlyMessage)
    // 2.
    print("=== Error Stack ===")
    print(error.logMessageStack())
}
catch {
    // 3.
    print("\(error.localizedDescription)")
}
```
As you can see, we can catch `SystemError`s from now on and:

1. The user-friendly error message can be displayed for end users.  
2. The entire error stack can be used for debugging purposes (as a log message).
3. Handle all other error types as usual.

In this case, the output is something similar:

```sh
Something went wrong.
=== Error Stack ===
MyCustomErrorStruct: "This is a custom error struct"
    └─ MyCustomErrorEnum: "Ouch this is not good, provide more info..."
```

When dealing with more complex errors, we can dig a bit deeper and use a lookup function to handle a specific scenario using a simple switch:

```swift
do {
    try UseCases.testDecodingError()
}
catch let error as SystemError {
    // 1.
    if let decodingError = error.lookup(DecodingError.self) {
        // 2.
        switch decodingError {
        // 3.
        case .dataCorrupted(let context):
            print(context.debugDescription)
        // 4.
        default:
            print("Not a data corrupted error.")
        }
    }
    // 5.
    else {
        print("Not a decoding error.")
    }
    // 6.
    print("=== Error Stack ===")
    print(error.logMessageStack())
}
catch {
    print("\(error.localizedDescription)")
}
```

Here's how the snippet from above works:

1. We catch `SystemError`s and use `lookup` to check for any underlying `DecodingError`.

2. If found, we examine the decoding error and switch between its possible cases.

3. For this example, we only care about the `.dataCorrupted` case.

4. If it's not a data corruption error, we print a default message.

5. If no decoding error is found at all, we print a fallback message.

6. Finally, we print the full error stack to help with debugging.

This is the expected output for the snippet above:

```sh
The given data was not valid JSON.
=== Error Stack ===
MyCustomErrorStruct: "Could not decode Foo type."
    └─ DecodingError: "Data corrupted: The given data was not valid JSON."
```



Our last example is a simplified version of the previous snippet. It eliminates the need for a switch-case by using the convenience `lookup` function:

```swift
do {
    try UseCases.testDecodingError()
}
catch let error as SystemError {
    // 1.
    if let context = error.lookup({
        // 2.
        if case DecodingError.dataCorrupted(let ctx) = $0 {
            return ctx
        }
        return nil
    }) {
        // 3.
        print(context.debugDescription)
    }
    else {
        // 4.
        print("Not a DecodingError.dataCorrupted case.")
    }
    print("=== Error Stack ===")
    print(error.logMessageStack())
}
catch {
    print("\(error.localizedDescription)")
}
```

Here's a brief explanation:

1. We use a custom closure inside `lookup` to search for a specific decoding error case.

2. If the error matches `.dataCorrupted`, we extract and return its context.

3. When found, we print the context's `debugDescription` for debugging.

4. If not found, we print a fallback message indicating it wasn't the expected case.

As you can see, it’s essentially the same approach as before — just a bit more concise. It’s mostly about the cosmetics, offering syntactic sugar and added convenience.

I truly believe these kinds of structured error stacks are incredibly useful. They've helped us a lot when debugging Toucan issues, and the best part is how simple it is to implement something similar. 

I hope you enjoyed this article — let me know what you think about this approach and how you handle typed throws and Swift error messages in your own codebase.


