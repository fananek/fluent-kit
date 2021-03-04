import FluentKit

public final class Governor: Model {
    public static let schema = "governors"

    @ID(key: .id)
    public var id: UUID?

    @Field(key: "name")
    public var name: String

    @Parent(key: "planet_id")
    public var planet: Planet

    public init() { }

    public init(id: IDValue? = nil, name: String) {
        self.id = id
        self.name = name
    }

    public init(id: IDValue? = nil, name: String, planetId: UUID) {
        self.id = id
        self.name = name
        self.$planet.id = planetId
    }
}

public struct GovernorMigration: Migration {
    public func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("governors")
            .field("id", .uuid, .identifier(auto: false))
            .field("name", .string, .required)
            .field("planet_id", .uuid, .required, .references("planets", "id"))
            .unique(on: "planet_id")
            .create()
    }

    public func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("governors").delete()
    }
}

public struct GovernorSeed: Migration {
    public init() { }

    public func prepare(on database: Database) -> EventLoopFuture<Void> {
        Planet.query(on: database).all().flatMap { planets in
            .andAllSucceed(planets.map { planet in
                let governor: Governor?
                switch planet.name {
                case "Mars":
                    governor = .init(name: "John Doe")
                case "Earth":
                    governor = .init(name: "Jane Doe")
                default:
                    governor = nil
                }
                guard let gov = governor else {
                    return database.eventLoop.makeSucceededFuture(())
                }
                return planet.$governor.create(gov, on: database)
            }, on: database.eventLoop)
        }
    }

    public func revert(on database: Database) -> EventLoopFuture<Void> {
        Governor.query(on: database).delete()
    }
}
