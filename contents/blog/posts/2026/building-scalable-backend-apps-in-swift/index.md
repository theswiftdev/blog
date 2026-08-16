---
type: post
title: "Building scalable backend apps in Swift"
description: "Build scalable Swift backends with onion, hexagonal, and clean architecture using use cases, repositories, transactions, and database abstractions."
publication: "2026-08-16 14:00:00"
tags: 
    - swift
authors:
    - tibor-bodecs
featured: true
---

Microservices, monoliths, clean architecture, MVC, MVP, MVVM, VIPER, SOLID, DRY... we have so many ways to build apps. Wouldn't it be simpler to have massive view controllers everywhere? You could do that, and it might give you a false sense of simplicity, but putting everything into views, controllers, or models does not create a scalable architecture. On the other hand, we could talk about VIPER, which requires much more boilerplate and ceremony. However, every feature follows the same structure, so no matter what you're building, you follow the same rules. Complex? Sure. Scalable? Yes. I've worked on many apps and seen many architectures, so let's point one thing out directly: there's no silver bullet, only a preferred way of doing things.

In this post, I'll show you what I've learned over the last few years and how I'm approaching backend development with server-side Swift. Let's get started. 😊

## Hexagonal / onion / clean architecture for Swift backends

The **onion architecture** is a software design pattern created by [Jeffrey Palermo](https://jeffreypalermo.com/2008/07/the-onion-architecture-part-1/) in 2008. It separates an application into three main layers: domain, application, and infrastructure.

**Hexagonal architecture**, also known as the ports and adapters pattern, was proposed by [Alistair Cockburn](https://en.wikipedia.org/wiki/Hexagonal_architecture_(software)). It divides a system into loosely coupled components connected through ports, which define abstract APIs implemented by concrete adapters; in Swift, we call these protocols and their implementations.

[Robert C. Martin](https://www.amazon.com/Clean-Architecture-Craftsmans-Software-Structure/dp/0134494164)’s **clean architecture** combines ideas from onion architecture, hexagonal architecture, and other patterns. The business domain stays at the center, with dependencies always pointing inward. The core should not depend on databases, user interfaces, or external frameworks.

I've adapted these architectures and made a few minor changes, but based on my understanding, this is how I separate concerns into layers using Swift.

## Domain

The domain contains domain models. These are not database table rows, transfer objects, or API representations. They encapsulate business rules and enforce invariants. What does this sentence actually mean?

Business rules are the core domain rules and decisions that define how an application behaves. 😇

Let's look at the following example, where we'll model an imaginary blog engine.

### Domain models

When publishing a blog post, we should always have associated tag identifiers. These identifiers are stored in a cross-reference database table (`post_id`, `tag_id`). Since we want to create a post together with its associated tags, this looks like a good business rule to model in the domain layer:

```swift
public struct Post {
    public let id: String
    public private(set) var title: String
    public private(set) var content: String
    public private(set) var tagIds: [String]
}
```

Notice that `id` is the only immutable property. The other properties can be changed internally, but not by external consumers. We'll get back to this in a minute. 🕥

Another business rule could enforce a blog post title that is at least 3 and at most 255 characters long. This validation logic belongs in the domain layer, and a domain error can be thrown when validation fails. The domain layer should not use external dependencies, apart from Foundation or a very small shared domain library. Framework dependencies should be kept to a minimum. It is also useful to define typed throws and custom errors for the issues that end users and framework consumers can encounter when calling this layer:

```swift
extension Post {

    public enum Error: Swift.Error {
        case titleTooShort
        case titleTooLong
    }

    private static func validate(
        title: String
    ) throws(Self.Error) {
        guard !title.isEmpty else {
            throw .titleTooShort
        }
        guard title.count < 255 else {
            throw .titleTooLong
        }
    }
}
```

So how should we handle insertion? Should we make the post ID optional? I don't think so. Vapor 4 did this with Fluent models, but a Fluent model is not a true domain model, and the terminology around repositories is mixed there as well. Fluent's models and repositories are database access layer components. Anyway, back to the topic.

Instead of making identifiers optional, we could introduce a `New` nested struct containing the same fields without an ID. Alternatively, we could create a base object to avoid duplicating properties. For the sake of simplicity, let's duplicate them here. AI can generate boilerplate extremely well, so why not? 🤖

We'll also introduce a public static builder because we don't want consumers to create these objects without enforcing the validation rules. This lets us create a validated `New` post value.

```swift
public struct Post {

    public struct New {
        public let title: String
        public let content: String
        public let tagIds: [String]
    }

    public static func create(
        title: String,
        content: String,
        tagIds: [String]
    ) throws -> Self.New {
        try validate(title: title)

        return .init(
            title: title,
            content: content,
            tagIds: tagIds
        )
    }
}
```

Since `New` does not have a public initializer, this is the only way to create a validated value. Similarly, we can add an update function that validates changed properties before updating the domain model:

```swift

extension Post {

    public mutating func update(
        title: String? = nil,
        content: String? = nil,
        tagIds: [String]? = nil
    ) throws(Self.Error) {
        let newTitle = title ?? self.title
        let newContent = content ?? self.content
        let newTagIds = tagIds ?? self.tagIds

        try Self.validate(title: newTitle)

        self.title = newTitle
        self.content = newContent
        self.tagIds = newTagIds
    }
}
```

As you can see, property access control and basic validation rules already enforce several business rules. These are simple examples, and the code is somewhat verbose because we duplicated several properties, but that is acceptable here. Notice that we have not discussed a UI or database at all. These models exist to represent business rules and abstractions. Using identifiers is natural, and they may eventually be persisted in a database, but the domain layer should still be treated as an abstraction rather than an implementation detail. 🏗️


### Repositories (interfaces)

In onion architecture, a repository is an abstraction that defines how domain models are accessed and persisted without exposing infrastructure or database details to the application core.

In Swift, protocols are a natural way to model repositories. Here is an example for blog post management:

```swift
public protocol PostRepository {

    func insert(
        _ model: Post.New
    ) async throws -> Post

    func update(
        _ model: Post
    ) async throws -> Post

    func delete(
        id: String
    ) async throws -> Bool
}
```

This protocol already gives us an important boundary. It lives in the domain layer, so consumers can save, update, or delete a blog post without knowing which storage system is used. This pattern is common in Swift, so let's move on to the next layer. 🧅


## Application

The application layer coordinates use cases and workflows by applying domain rules through defined interfaces, without depending on infrastructure details such as databases or external services.

Let's break this down.

### Use-cases

A use case represents a specific action, coordinating the required domain rules and dependencies to achieve a particular outcome. `AddPost`, for example, is a good use-case candidate. How is this different from `insert`? The repository's `insert` method is a CRUD-like operation that persists valid and consistent data. The `AddPost` use case, on the other hand, can orchestrate the entire workflow: it can enforce access control, check ownership rules, and encapsulate a unit of work. It is a higher-level abstraction. But how do we implement it? 🤔

Every use case should have an input and an output. Domain models should not be used as the input or output objects of this layer; in particular, they should never leak out of it. This is why we introduce Data Transfer Objects (DTOs).

For example, if a user domain model contains a password, that field should not be returned by a use case. The domain model should be mapped to another type that does not include the password. Domain models can contain sensitive or non-user-facing data, while DTOs should contain only the data required by the use case's consumers.

This introduces some duplication again, but that separation helps the system scale by keeping each boundary explicit. 🙄

```swift
public struct AddPostUseCase {
    
    public struct Input {
        public let title: String
        public let content: String
        public let tagIds: [String]

        public init(
            title: String,
            content: String,
            tagIds: [String]
        ) {
            self.title = title
            self.content = content
            self.tagIds = tagIds
        }
    }
}
```

Now that we have an input, let's define an output as well. Since multiple use cases may return the same output, it does not need to be nested inside a single use case. We can define a top-level object called `PostDetailDTO`. The suffix is optional and mostly a matter of coding style:

```swift    
public struct PostDetailDTO {
    public let id: String
    public let title: String
    public let content: String
    public let tagIds: [String]

    package init(
        id: String,
        title: String,
        content: String,
        tagIds: [String]
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.tagIds = tagIds
    }
}
```

So far, so good. Notice the difference between the two objects. Now let's write the use-case function. We'll keep it simple and iterate on it later. It will transform the input into a domain model, call the repository, and map the result to the output DTO:


```swift
import PostDomain

public struct AddPostUseCase {

    let repository: PostRepository
    
    public init(
        repository: PostRepository
    ) {
        self.repository = repository
    }
    
    public func execute(
        input: Input
    ) async throws -> PostDetailDTO {
        let model = try await repository.insert(
            Post.create(
                title: input.title,
                content: input.content,
                tagIds: input.tagIds
            )
        )
        return .init(
            id: model.id,
            title: model.title,
            content: model.content,
            tagIds: model.tagIds,
        )
    }
}
```

This looks fine, except that domain errors still escape from the use case. A `do`/`catch` block and a typed throwing `execute` function could translate them, but we'll leave that aside for now. The `.create` function enforces the domain rules, and the use case knows nothing about the repository implementation. The repository protocol is an abstract dependency. The boundaries are clear, but there is still a problem: if we keep this implementation, every user can create blog posts. In this example, guest posts are not allowed. 😢

### Actions

Role-based access control (RBAC) manages access by assigning permissions to roles and then assigning those roles to users. Access control lists (ACLs), by contrast, define permissions directly for individual users or resources.

**Users** are the identities or accounts that can log in to your system.

**Roles** are groups that organize users and permissions. In some systems, permissions can also be attached directly to users without introducing roles.

**Permissions** define which actions a user or role can perform on specific resources. For example, `post:write` could represent the ability to create a blog post. Some systems use a namespace, resource, and action format such as `blog:post:create`. Permissions are usually predefined based on the application's business rules and available functionality.

As mentioned earlier, use cases should handle permission checks. For this purpose, I'll introduce a simple abstraction for defining actions and authorization. 🔑

```swift
public struct Subject: Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}
```

**Subject** contains an identifier, usually a user ID, so we can query user data when needed and check relationships with other objects.

```swift
public protocol Action: Sendable {
    
    func authorize(
        subject: Subject,
        permissions: Set<String>
    ) async throws -> Bool
}
```

**Action** represents an operation that the subject wants to perform. Its `authorize` function receives the subject and that user's permissions, represented here as a simple set of strings. The function returns a Boolean indicating whether the subject is allowed to perform the action.

```swift
public protocol Authorizer: Sendable {
    
    func can(
        subject: Subject,
        perform action: any Action
    ) async throws -> Bool
}
```

**Authorizer** checks whether a subject can perform an action and returns a Boolean.

```swift
public struct AuthError: Error {
    public enum Kind: Sendable {
        case unauthorized
        case forbidden
    }

    public let kind: Kind
    public let message: String

    public init(
        kind: Kind,
        message: String
    ) {
        self.kind = kind
        self.message = message
    }
}
```

**AuthError** is a simple error type that models both unauthorized access, such as an invalid user, and forbidden access, where the user has no permission.

Imagine that the server receives a token and can use it to look up the user ID. It can then retrieve the user's associated permissions. The route handler can pass the resulting subject and input to the use case. 🔎

First, we define an action that checks whether the user's permission set contains the `post:write` key:

```swift
struct AddPostAction: Action {

    let key = "post:write"

    public func authorize(
        subject: Subject,
        permissions: Set<String>
    ) async throws -> Bool {
        permissions.contains(key) 
    }
}
```

Of course, we could create a more generic permission-based action that only requires a key and can be reused across the system. That would avoid implementing the `authorize` function repeatedly for permission-related actions, but the specialized version is easy to understand for this example. 🔒

Next, we update the use case to handle authorization:

```swift
import PostDomain

public struct AddPostUseCase {
    
    let authorizer: any Authorizer
    let repository: PostRepository
    
    public init(
        authorizer: any Authorizer,
        repository: PostRepository
    ) {
        self.authorizer = authorizer
        self.repository = repository
    }
    
    public func execute(
        subject: Subject,
        input: Input
    ) async throws -> PostDetailDTO {
        let action = AddPostAction()

        guard try await authorizer.can(subject: subject, perform: action) else {
            throw AuthError(kind: .forbidden, message: "No write access.")
        }

        let model = try await repository.insert(
                Post.create(
                    title: input.title,
                    content: input.content,
                    tagIds: input.tagIds
                )
            )
        }
        return .init(
            id: model.id,
            title: model.title,
            content: model.content,
            tagIds: model.tagIds,
        )
    }
}
```

Calling `execute` from the route handler or another part of the application now requires a subject. The use case also receives an authorizer as a dependency. A simple authorizer could look like this. `Database` is an application-specific abstraction in this example. 😛

```swift
public struct ExampleAuthorizer: Authorizer {

    let database: Database
    
    public func can(
        subject: Subject,
        perform action: any Action
    ) async throws -> Bool {

        let permissions = try await database.getUserPermissions(
            for: subject.id
        )
        return try await action.authorize(
            subject: subject,
            permissions: permissions
        )
    }
}
```

The call site now looks like this:

```swift
let database = //... a database pointer from a framework
let userId = try await request.getUserIDFromToken() // or similar
let subject = Subject(id: userId)

let authorizer = ExampleAuthorizer(database: database) // use a real one...
let repository = PostDatabaseRepository(database: database) // or similar

let useCase = AddPostUseCase(
    authorizer: authorizer,
    repository: repository,
)

let input = try await request.transformDataIntoAddPostInput()
let result = try await useCase.execute(subject: subject, input: input)

return try await result.transformIntoHTTPResponse()
```

The flow is:

1. The client calls an HTTP endpoint with a bearer token.
2. Server authentication middleware resolves the user ID and permissions from the token.
3. The route handler constructs a subject and calls the use case.

The snippet above simplifies the authentication mechanics. A real-world application will be more complex, but the same separation makes the flow easier to understand and implement. 😉

The more difficult part is managing units of work, transactions, and atomic database operations. 😱


### Unit of work

Transaction control is very important. You do not want to create a blog post if creating its associated tags fails. Without transactions and foreign keys, it is easy to leave the database in an inconsistent state.

It took some effort (it was literally a fucking nightmare) to come up with a proper abstraction for this, but the solution works well and is definitely worth explaining since it’s a crucial part of the system. 🤯

We'll start with an executor. Its only purpose is to execute work using a generic scope and return a generic result. The idea is simple:

```swift
public protocol Executor<S>: Sendable {
    associatedtype S: Scope

    func run<T: Sendable>(
        _ body: @Sendable (S) async throws -> T
    ) async throws -> T
}
```

Now let's define a transaction & query executor:

```swift
public protocol QueryExecutor<S>: Executor {}
public protocol TransactionExecutor<S>: Executor {}
```

These protocols have the same shape but different meanings. One executes work using a simple database query; the other uses a transaction with begin, commit, and rollback behavior.

We'll also need three context protocols: a shared execution context, a query context, and a transaction context:

```swift
public protocol ExecutionContext: Sendable {}
public protocol QueryContext: ExecutionContext {}
public protocol TransactionContext: ExecutionContext {}
```

These contexts will later hold the database connection and the ID generator.

Now let's extend the base executor with contextual execution and generic scope and context support:

```swift
public protocol ContextualExecutor<S, C>: Executor where S: Scope {
    associatedtype C

    func run<T: Sendable>(
        _ body: @Sendable (S, C) async throws -> T
    ) async throws -> T
}
```

From this point, we can define two pathways based on the SQL execution type. These protocols build on the contextual executor and associate the correct context with either a query or a transaction:

```swift
public protocol ContextualQueryExecutor<S>:
    QueryExecutor,
    ContextualExecutor
where C == any QueryContext {}
```

The first is for queries, and this one is for transactions:

```swift
public protocol ContextualTransactionExecutor<S>:
    TransactionExecutor,
    ContextualExecutor
where C == any TransactionContext {}
```

The only difference is the `C` constraint, which identifies the execution context.

These protocols can live in the application layer because they do not contain infrastructure-specific details. I have these protocols in my core CMS framework, and everything demonstrated in this article already exists there. This article explains the ideas behind what I have built. 🙄

Instead of passing the repository directly to the use-case initializer, we use a scope and a transaction executor. Scopes are a useful way to group the repositories that participate in a use case. This lets us mock only the required dependencies and test the system thoroughly. I prefer many smaller parts over one large "collector" containing every repository and function. This makes the system easier to test, scale, and compose.

We can now move the repository dependency to the newly created scope object. You can name scopes however you want; I currently prefer a `Read` or `Write` prefix:

```swift
public struct WritePostScope: Scope {
    public let post: any PostRepository
    
    public init(
        post: any PostRepository
    ) {
        self.post = post
    }
}
```

Scope definition is simple: add as many repositories or queries as the use case requires. Some people also distinguish read and write access at the repository level. Read-only operations can live on a `PostQueries` object, which retrieves data from a database or another source. Queries can also be part of the scope and are independent of the execution context, so they can run either inside a transaction or as a standalone query. Repositories that modify multiple tables, on the other hand, should run through a transaction executor so the changes remain atomic.

The `AddPostUseCase` use case now looks something like this:


```swift
public struct AddPostUseCase: UseCase {

    let authorizer: any Authorizer
    let transaction: any TransactionExecutor<WritePostScope>

    public init(
        authorizer: any Authorizer,
        transaction: any TransactionExecutor<WritePostScope>
    ) {
        self.authorizer = authorizer
        self.transaction = transaction
    }

    public struct Input: DTO { /*...*/}

    public func execute(
        subject: Subject,
        input: Input
    ) async throws -> PostDetail {
        let action = AddPostAction()

        guard try await authorizer.can(subject: subject, perform: action) else {
            throw AuthError(kind: .forbidden, message: action.key)
        }

        let model = try await transaction.run { scope in
            return try await scope.post.insert(
                Post.create(
                    title: input.title,
                    content: input.content,
                    tagIds: input.tagIds
                )
            )
        }
        return model.toDTO()
    }
}
```

The call site still needs a concrete transaction executor. The executor is currently only an abstraction; its implementation belongs in the infrastructure layer.

## Infrastructure

The infrastructure layer contains concrete implementations for external concerns, such as the database executor for our executor interface.

### Database executors

Imagine that we have a `DatabaseClient`, such as the one provided by [Feather Framework](https://feather-framework.com/docs/database/) or [Fluent](https://docs.vapor.codes/fluent/overview/). We can use that client to build a database executor.

```swift
public struct DatabaseExecutor<S: Scope, C: ExecutionContext>: Sendable {

    public let database: any DatabaseClient
    public let scope: @Sendable (C) -> S

    public init(
        database: any DatabaseClient,
        scope: @Sendable @escaping (C) -> S
    ) {
        self.database = database
        self.scope = scope
    }
}
```

We can now use this executor to implement database query and transaction execution. The code is a little longer, but the idea is simple:

```swift
public struct DatabaseQueryExecutor<S: Scope>:
    ContextualQueryExecutor
{

    public let executor: DatabaseExecutor<S, DatabaseQueryContext>

    public init(executor: DatabaseExecutor<S, DatabaseQueryContext>) {
        self.executor = executor
    }

    public init(
        database: any DatabaseClient,
        scope: @Sendable @escaping (DatabaseQueryContext) -> S
    ) {
        self.executor = .init(
            database: database,
            scope: scope
        )
    }

    public func run<T: Sendable>(
        _ body: @Sendable (S) async throws -> T
    ) async throws -> T {
        try await executor.database.withConnection { connection in
            let context = DatabaseQueryContext(connection: connection)
            return try await body(executor.scope(context))
        }
    }

    public func run<T: Sendable>(
        _ body: @Sendable (S, any QueryContext) async throws -> T
    ) async throws -> T {
        try await executor.database.withConnection { connection in
            let context = DatabaseQueryContext(connection: connection)
            return try await body(
                executor.scope(context),
                context
            )
        }
    }
}
```

The important part lives inside the `run` functions. When necessary, callers can extract the database connection from the context and use it directly. I use this for event-based hooks and repositories. You could also do this in a use case, but I generally recommend using the scope-only version. The context is useful when working with the event system. 

This is what the call site looks like for extraction::

```swift
try await query.run { scope, context in
    let dbConnection = context.connection
    let idGenerator = context.idGenerator
}
```

The scope contains the repositories and queries, so normally this version of `run` is not needed and the context can be ignored.

```swift
let posts = try await query.run { scope in
    try await scope.analyticsRepository.writeSomethingUseful()
    return try await scope.postQueries.listAll()
}
```

Anyway, the same logic applies to transaction executors:

```swift
public struct DatabaseTransactionExecutor<S: Scope>:
    ContextualTransactionExecutor
{

    public let executor: DatabaseExecutor<S, DatabaseTransactionContext>
    public let idGenerator: any IDGenerator

    public init(
        executor: DatabaseExecutor<S, DatabaseTransactionContext>,
        idGenerator: any IDGenerator
    ) {
        self.executor = executor
        self.idGenerator = idGenerator
    }

    public init(
        database: any DatabaseClient,
        idGenerator: any IDGenerator,
        scope: @Sendable @escaping (DatabaseTransactionContext) -> S
    ) {
        self.executor = .init(
            database: database,
            scope: scope
        )
        self.idGenerator = idGenerator
    }

    public func run<T: Sendable>(
        _ body: @Sendable (S) async throws -> T
    ) async throws -> T {
        try await executor.database.withTransaction { connection in
            let context = context(for: connection)
            return try await body(executor.scope(context))
        }
    }

    public func run<T: Sendable>(
        _ body: @Sendable (S, any TransactionContext) async throws -> T
    ) async throws -> T {
        try await executor.database.withTransaction { connection in
            let context = DatabaseTransactionContext(
                connection: connection,
                idGenerator: idGenerator
            )
            return try await body(executor.scope(context), context)
        }
    }

    private func context(
        for connection: any DatabaseConnection
    ) -> DatabaseTransactionContext {
        .init(connection: connection, idGenerator: idGenerator)
    }
}
```

The only difference between the two executors is that one calls `withTransaction` and the other calls `withConnection`. The former starts a real database transaction and rolls it back if something goes wrong; the latter runs the query without a transaction.

At this point, we can initialize a database executor and pass it as a dependency to the use case. Before doing that, there is one more abstraction to introduce: the Database ~~Abstraction~~ Access Layer (DBAL). 🤣

### Database Abstraction or Access Layer (DBAL)

The Database Abstraction Layer or Database Access Layer, I use both terms interchangeably, (DBAL) hides the details of a specific database system behind a consistent interface, allowing the application to access and persist data without depending on a particular database technology.

In other words, SQL code is hidden behind Swift code. SQL should be limited to this layer. Nothing will break if SQL appears elsewhere, but keeping it here makes the architectural boundary clear. 💡

Let's model a simple post table using Feather Database:

```swift
import FeatherDatabase
import struct Foundation.Date

struct PostTableError: Error {
    let message: String
}

struct PostTable {
    struct Row {
        struct Create {
            let id: String
            let title: String
            let content: String
        }

        let id: String
        let title: String
        let content: String
        let createdAt: Date
        let updatedAt: Date
    }

    let connection: any DatabaseConnection

    init(connection: any DatabaseConnection) {
        self.connection = connection
    }
}
```

The same pattern appears again: we have a `Row` representation and a `Create` struct. The table type receives an `any DatabaseConnection`, which keeps it independent of the concrete database driver. `Row` describes the database row returned by the table, and each row type should know how to decode itself from a `DatabaseRow`:

```swift
extension PostTable.Row {
    init(from row: DatabaseRow) throws {
        self.id = try row.decode(column: "id", as: String.self)
        self.title = try row.decode(column: "title", as: String.self)
        self.content = try row.decode(column: "content", as: String.self)
        self.createdAt = try row.decode(column: "created_at", as: Date.self)
        self.updatedAt = try row.decode(column: "updated_at", as: Date.self)
    }
}
```

This keeps decoding consistent across queries. Any query that returns a post row must return the columns required by this initializer.

We can add a `create` method to the table struct that inserts a row and returns the inserted database row:


```swift
extension PostTable {

    func create(
        row: Row.Create
    ) async throws -> Row {
        try await connection.run(
            query: #"""
                INSERT INTO post (
                    id,
                    title,
                    content
                )
                VALUES (
                    \#(row.id),
                    \#(row.title),
                    \#(row.content)
                )
                RETURNING
                    id,
                    title,
                    content,
                    created_at,
                    updated_at;
                """#
        ) { sequence in
            guard let row = try await sequence.collect().first else {
                throw PostTableError(
                    message: "Could not return inserted post row"
                )
            }
            return try Row(from: row)
        }
    }
}
```

Similarly, we could add more functions, but I won't show them all here. We have a detailed page describing the [database access layer](https://feather-framework.com/docs/database/access-layer/), including database migration tips and other row operations using the Feather framework.

The last pieces are the database query and transaction contexts. I'll show the transaction context implementation; the query context follows the same pattern:

```swift
public struct DatabaseTransactionContext: TransactionContext, DatabaseContext {

    public let connection: any DatabaseConnection
    public let idGenerator: any IDGenerator

    public init(
        connection: any DatabaseConnection,
        idGenerator: any IDGenerator
    ) {
        self.connection = connection
        self.idGenerator = idGenerator
    }
}
```

As mentioned earlier, this contains the execution context. The ID generator is a small abstraction with one function that returns a unique string: `func generate() -> String`. It is intentionally simple and can be implemented as needed.

Now let's focus on the final building block: the repository implementation.

### Repositories (implementation)

Database repositories contain database-related logic and implement the functions defined by the abstract protocol. The implementation could use in-memory storage or an API instead; the protocol hides those details from the application layer, so only the infrastructure code changes. This also makes it possible to build mock repositories for testing or replace the entire storage mechanism when needed.

For the database repository, we can use the DBAL objects to implement the required functions. Here is the `insert` implementation:

```swift
public struct PostDatabaseRepository: PostRepository {

    public let context: DatabaseTransactionContext
    public init(context: DatabaseTransactionContext) {
        self.context = context
    }

    public func insert(
        _ model: Post.New
    ) async throws -> Post {
        let table = PostTable(connection: context.connection)
        let row = try await table.create(
            row: .init(
                id: context.idGenerator.generate(),
                title: model.title,
                content: model.content
            )
        )
        // TODO: associate tag relations here...
        // Use model.tagIds & a DBAL table to update tags
        return row.asDomainModel()
    }
}
```

The repository is initialized with the database transaction context, which is its dependency. We provide this context when composing the system. In `insert`, we create a DBAL table representation using the connection from the context, call the insert operation, and generate a unique identifier with the ID generator. The database could generate the identifier with an auto-increment or similar field, but generating it here provides more control. Finally, we create a domain model from the table row and return it. If needed, we could use other tables to load relations or insert additional records in the same transaction.

## Composition

The final topic is composition. The system has to be assembled somewhere. This can happen in a separate layer of the server application for production infrastructure, in tests for testing purposes, or in a dedicated shared composition layer that can simplify both.

Here is one possible composition using the Feather Database framework. This code is illustrative and will not work as-is, but it demonstrates the steps needed to assemble the system. 😳

```swift
// from postgres-nio
let client = PostgresClient(
    configuration: .init(
        host: "localhost",
        port: 5432,
        username: "postgres",
        password: "postgres",
        database: "feather",
        tls: .require(tlsConfig)
    ),
    backgroundLogger: Logger.current
)

// from feather database
let database = DatabaseClientPostgres(client: client)
let authorizer = ExampleAuthorizer(database: database)
let idGenerator = NanoIDGenerator()

let transaction = DatabaseTransactionExecutor(
    database: database,
    idGenerator: idGenerator,
    scope: { context in
        WritePostScope(
            post: PostDatabaseRepository(context: context)
        )
    }
)
let useCase = AddPostUseCase(
    authorizer: authorizer, 
    transaction: transaction
)

// from Hummingbird or Vapor
router.post("post/new") { request, response in 
    let userId = try await request.getUserIDFromToken() // or similar
    let subject = Subject(id: userId)

    let input = try await request.transformDataIntoAddPostInput()
    let result = try await useCase.execute(subject: subject, input: input)

    return try await result.transformIntoHTTPResponse()
}
```

First, we create a Postgres database client using postgres-nio. Then we create the Feather database client, an abstraction that simplifies query management. We also initialize the authorizer and ID generator described earlier in the article.

Next, we create the transaction executor, which encapsulates unit-of-work operations. If a transaction is not needed, a query executor can be created in the same way. The transaction executor requires the database connection, the ID generator, and a scope-construction closure. The closure is called later so the scope can receive the active database context. Finally, we build the use case from these dependencies.

In a Vapor or Hummingbird route handler, we can transform the HTTP input into a DTO and retrieve the user information required by the authorizer. We call the use case's `execute` method and transform the result into the appropriate HTTP response schema.

## Conclusion

As you can see, we have not discussed OpenAPI or request and response handling beyond the small demonstration above. This article is about structuring application logic rather than building servers with Swift. There are already plenty of tutorials covering that topic. Designing a scalable application is difficult, but not impossible. This approach gives me the flexibility and maintainability I need.

This is a lot to digest, but the complete approach is publicly available in the upcoming Feather CMS project. Next time, we'll continue with the admin and frontend architecture. 🪶

This article was written by a human and corrected with the help of an AI agent.
