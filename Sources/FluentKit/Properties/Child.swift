extension Model {
    public typealias Child<To> = ChildProperty<Self, To>
        where To: FluentKit.Model
}

// MARK: Type

@propertyWrapper
public final class ChildProperty<From, To>
    where From: Model, To: Model
{
    public enum Key {
        case required(KeyPath<To, To.Parent<From>>)
        case optional(KeyPath<To, To.OptionalParent<From>>)
    }

    public let parentKey: Key
    var idValue: From.IDValue?

    public var value: To?

    public init(for parent: KeyPath<To, To.Parent<From>>) {
        self.parentKey = .required(parent)
    }

    public init(for optionalParent: KeyPath<To, To.OptionalParent<From>>) {
        self.parentKey = .optional(optionalParent)
    }

    public var wrappedValue: To {
        get {
            guard let value = self.value else {
                fatalError("Child relation not eager loaded, use $ prefix to access: \(name)")
            }
            return value
        }
        set {
            fatalError("Child relation is get-only.")
        }
    }

    public var projectedValue: ChildProperty<From, To> {
        return self
    }
    
    public var fromId: From.IDValue? {
        return self.idValue
    }

    public func query(on database: Database) -> QueryBuilder<To> {
        guard let id = self.idValue else {
            fatalError("Cannot query child relation from unsaved model.")
        }
        let builder = To.query(on: database)
        switch self.parentKey {
        case .optional(let optional):
            builder.filter(optional.appending(path: \.$id) == id)
        case .required(let required):
            builder.filter(required.appending(path: \.$id) == id)
        }
        return builder
    }

    public func create(_ to: To, on database: Database) -> EventLoopFuture<Void> {
        guard let id = self.idValue else {
            fatalError("Cannot save child to unsaved model.")
        }
        switch self.parentKey {
        case .required(let keyPath):
            to[keyPath: keyPath].id = id
        case .optional(let keyPath):
            to[keyPath: keyPath].id = id
        }
        return to.create(on: database)
    }
}

extension ChildProperty: CustomStringConvertible {
    public var description: String {
        self.name
    }
}

// MARK: Property

extension ChildProperty: AnyProperty { }

extension ChildProperty: Property {
    public typealias Model = From
    public typealias Value = To
}

// MARK: Database

extension ChildProperty: AnyDatabaseProperty {
    public var keys: [FieldKey] {
        []
    }

    public func input(to input: DatabaseInput) {
        // child never has input
    }

    public func output(from output: DatabaseOutput) throws {
        let key = From()._$id.field.key
        if output.contains(key) {
            self.idValue = try output.decode(key, as: From.IDValue.self)
        }
    }
}

// MARK: Codable

extension ChildProperty: AnyCodableProperty {
    public func encode(to encoder: Encoder) throws {
        if let rows = self.value {
            var container = encoder.singleValueContainer()
            try container.encode(rows)
        }
    }

    public func decode(from decoder: Decoder) throws {
        // don't decode
    }
}

// MARK: Relation

extension ChildProperty: Relation {
    public var name: String {
        "Child<\(From.self), \(To.self)>(for: \(self.parentKey))"
    }

    public func load(on database: Database) -> EventLoopFuture<Void> {
        self.query(on: database).first().map {
            self.value = $0
        }
    }
}

extension ChildProperty.Key: CustomStringConvertible {
    public var description: String {
        switch self {
        case .optional(let keyPath):
            return To.path(for: keyPath.appending(path: \.$id)).description
        case .required(let keyPath):
            return To.path(for: keyPath.appending(path: \.$id)).description
        }
    }
}

// MARK: Eager Loadable

extension ChildProperty: EagerLoadable {
    public static func eagerLoad<Builder>(
        _ relationKey: KeyPath<From, From.Child<To>>,
        to builder: Builder
    )
        where Builder: EagerLoadBuilder, Builder.Model == From
    {
        let loader = ChildEagerLoader(relationKey: relationKey)
        builder.add(loader: loader)
    }


    public static func eagerLoad<Loader, Builder>(
        _ loader: Loader,
        through: KeyPath<From, From.Child<To>>,
        to builder: Builder
    ) where
        Loader: EagerLoader,
        Loader.Model == To,
        Builder: EagerLoadBuilder,
        Builder.Model == From
    {
        let loader = ThroughChildEagerLoader(relationKey: through, loader: loader)
        builder.add(loader: loader)
    }
}

private struct ChildEagerLoader<From, To>: EagerLoader
    where From: Model, To: Model
{
    let relationKey: KeyPath<From, From.Child<To>>

    func run(models: [From], on database: Database) -> EventLoopFuture<Void> {
        let ids = models.map { $0.id! }

        let builder = To.query(on: database)
        let parentKey = From()[keyPath: self.relationKey].parentKey
        switch parentKey {
        case .optional(let optional):
            builder.filter(optional.appending(path: \.$id) ~~ Set(ids))
        case .required(let required):
            builder.filter(required.appending(path: \.$id) ~~ Set(ids))
        }
        return builder.all().map {
            for model in models {
                let id = model[keyPath: self.relationKey].idValue!
                let children = $0.filter { child in
                    switch parentKey {
                    case .optional(let optional):
                        return child[keyPath: optional].id == id
                    case .required(let required):
                        return child[keyPath: required].id == id
                    }
                }
                model[keyPath: self.relationKey].value = children.first
            }
        }
    }
}

private struct ThroughChildEagerLoader<From, Through, Loader>: EagerLoader
    where From: Model, Loader: EagerLoader, Loader.Model == Through
{
    let relationKey: KeyPath<From, From.Child<Through>>
    let loader: Loader

    func run(models: [From], on database: Database) -> EventLoopFuture<Void> {
        let throughs = models.map {
            $0[keyPath: self.relationKey].value!
        }
        return self.loader.run(models: throughs, on: database)
    }
}
