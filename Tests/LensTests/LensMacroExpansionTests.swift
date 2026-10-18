import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(LensMacros)
import LensMacros

let testMacros: [String: Macro.Type] = [
    "Lens": LensMacro.self,
]

final class LensMacroExpansionTests: XCTestCase {
    func testGeneratesLensForEveryStoredVarProperty() throws {
        assertMacroExpansion(
            """
            @Lens
            struct User {
                var name: String
                var age: Int
            }
            """,
            expandedSource: """
            struct User {
                var name: String
                var age: Int

                enum Lenses {
                    static let name: LensType.LensValue<User, String> = LensType.LensValue(
                        get: {
                            $0.name
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.name = newValue
                            return copy
                        }
                    )
                    static let age: LensType.LensValue<User, Int> = LensType.LensValue(
                        get: {
                            $0.age
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.age = newValue
                            return copy
                        }
                    )
                }

                func changing(name: String? = nil, age: Int? = nil) -> User {
                    User(
                        name: name ?? self.name,
                        age: age ?? self.age
                    )
                }

                @dynamicMemberLookup
                struct ThroughLens {
                    let instance: User

                    func get() -> User {
                        instance
                    }

                    func set(_ newValue: User) -> User {
                        newValue
                    }

                    subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<User, Subpart>) -> LensType.BoundLensValue<User, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    func changing(name: String? = nil, age: Int? = nil) -> User {
                        self.set(User(
                            name: name ?? self.get().name,
                            age: age ?? self.get().age
                        ))
                    }
                }

                var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testSkipsComputedAndStaticProperties() throws {
        assertMacroExpansion(
            """
            @Lens
            struct User {
                let id: Int
                var name: String
                var displayName: String { name }
                static var count: Int = 0
            }
            """,
            expandedSource: """
            struct User {
                let id: Int
                var name: String
                var displayName: String { name }
                static var count: Int = 0

                enum Lenses {
                    static let id: LensType.LensValue<User, Int> = LensType.LensValue(
                        get: {
                            $0.id
                        },
                        set: { (newValue, whole) in
                            User(
                                id: newValue,
                                name: whole.name
                            )
                        }
                    )
                    static let name: LensType.LensValue<User, String> = LensType.LensValue(
                        get: {
                            $0.name
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.name = newValue
                            return copy
                        }
                    )
                }

                func changing(id: Int? = nil, name: String? = nil) -> User {
                    User(
                        id: id ?? self.id,
                        name: name ?? self.name
                    )
                }

                @dynamicMemberLookup
                struct ThroughLens {
                    let instance: User

                    func get() -> User {
                        instance
                    }

                    func set(_ newValue: User) -> User {
                        newValue
                    }

                    subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<User, Subpart>) -> LensType.BoundLensValue<User, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    var id: LensType.BoundLensValue<User, Int> {
                        LensType.BoundLensValue(instance: instance, lens: Lenses.id)
                    }

                    func changing(id: Int? = nil, name: String? = nil) -> User {
                        self.set(User(
                            id: id ?? self.get().id,
                            name: name ?? self.get().name
                        ))
                    }
                }

                var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testLetPropertiesGetRebuildBoundLenses() throws {
        assertMacroExpansion(
            """
            @Lens
            public struct Snapshot {
                public let version: Int
                public let title: String?
                public var isDraft: Bool
            }
            """,
            expandedSource: """
            public struct Snapshot {
                public let version: Int
                public let title: String?
                public var isDraft: Bool

                public enum Lenses {
                    public static let version: LensType.LensValue<Snapshot, Int> = LensType.LensValue(
                        get: {
                            $0.version
                        },
                        set: { (newValue, whole) in
                            Snapshot(
                                version: newValue,
                                title: whole.title,
                                isDraft: whole.isDraft
                            )
                        }
                    )
                    public static let title: LensType.LensValue<Snapshot, String?> = LensType.LensValue(
                        get: {
                            $0.title
                        },
                        set: { (newValue, whole) in
                            Snapshot(
                                version: whole.version,
                                title: newValue,
                                isDraft: whole.isDraft
                            )
                        }
                    )
                    public static let isDraft: LensType.LensValue<Snapshot, Bool> = LensType.LensValue(
                        get: {
                            $0.isDraft
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.isDraft = newValue
                            return copy
                        }
                    )
                }

                public func changing(version: Int? = nil, title: String? = nil, isDraft: Bool? = nil) -> Snapshot {
                    Snapshot(
                        version: version ?? self.version,
                        title: title ?? self.title,
                        isDraft: isDraft ?? self.isDraft
                    )
                }

                @dynamicMemberLookup
                public struct ThroughLens {
                    let instance: Snapshot

                    public func get() -> Snapshot {
                        instance
                    }

                    public func set(_ newValue: Snapshot) -> Snapshot {
                        newValue
                    }

                    public subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<Snapshot, Subpart>) -> LensType.BoundLensValue<Snapshot, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    public var version: LensType.BoundLensValue<Snapshot, Int> {
                        LensType.BoundLensValue(instance: instance, lens: Lenses.version)
                    }

                    public var title: LensType.BoundLensValue<Snapshot, String?> {
                        LensType.BoundLensValue(instance: instance, lens: Lenses.title)
                    }

                    public func changing(version: Int? = nil, title: String? = nil, isDraft: Bool? = nil) -> Snapshot {
                        self.set(Snapshot(
                            version: version ?? self.get().version,
                            title: title ?? self.get().title,
                            isDraft: isDraft ?? self.get().isDraft
                        ))
                    }
                }

                public var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testGenericStruct() throws {
        assertMacroExpansion(
            """
            @Lens
            struct Pair<A, B> {
                var first: A
                var second: B
            }
            """,
            expandedSource: """
            struct Pair<A, B> {
                var first: A
                var second: B

                enum Lenses {
                    static var first: LensType.LensValue<Pair<A, B>, A> {
                        LensType.LensValue(
                            get: {
                                $0.first
                            },
                            set: { (newValue, whole) in
                                var copy = whole
                                copy.first = newValue
                                return copy
                            }
                        )
                    }
                    static var second: LensType.LensValue<Pair<A, B>, B> {
                        LensType.LensValue(
                            get: {
                                $0.second
                            },
                            set: { (newValue, whole) in
                                var copy = whole
                                copy.second = newValue
                                return copy
                            }
                        )
                    }
                }

                func changing(first: A? = nil, second: B? = nil) -> Pair<A, B> {
                    Pair<A, B>(
                        first: first ?? self.first,
                        second: second ?? self.second
                    )
                }

                @dynamicMemberLookup
                struct ThroughLens {
                    let instance: Pair<A, B>

                    func get() -> Pair<A, B> {
                        instance
                    }

                    func set(_ newValue: Pair<A, B>) -> Pair<A, B> {
                        newValue
                    }

                    subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<Pair<A, B>, Subpart>) -> LensType.BoundLensValue<Pair<A, B>, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    func changing(first: A? = nil, second: B? = nil) -> Pair<A, B> {
                        self.set(Pair<A, B>(
                            first: first ?? self.get().first,
                            second: second ?? self.get().second
                        ))
                    }
                }

                var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testMirrorsAccessLevel() throws {
        assertMacroExpansion(
            """
            @Lens
            public struct User {
                public var name: String
            }
            """,
            expandedSource: """
            public struct User {
                public var name: String

                public enum Lenses {
                    public static let name: LensType.LensValue<User, String> = LensType.LensValue(
                        get: {
                            $0.name
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.name = newValue
                            return copy
                        }
                    )
                }

                public func changing(name: String? = nil) -> User {
                    User(
                        name: name ?? self.name
                    )
                }

                @dynamicMemberLookup
                public struct ThroughLens {
                    let instance: User

                    public func get() -> User {
                        instance
                    }

                    public func set(_ newValue: User) -> User {
                        newValue
                    }

                    public subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<User, Subpart>) -> LensType.BoundLensValue<User, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    public func changing(name: String? = nil) -> User {
                        self.set(User(
                            name: name ?? self.get().name
                        ))
                    }
                }

                public var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testSkipsPropertyWithoutTypeAnnotationWithWarning() throws {
        assertMacroExpansion(
            """
            @Lens
            struct Counter {
                var count = 0
            }
            """,
            expandedSource: """
            struct Counter {
                var count = 0

                var throughLens: LensType.BoundLensValue<Counter, Counter> {
                    LensType.BoundLensValue(instance: self, lens: .identity)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Lenses require an explicit type annotation, so no lens was generated for 'count'.",
                    line: 3,
                    column: 9,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    func testSkipsPropertyWrappersWithWarning() throws {
        assertMacroExpansion(
            """
            @Lens
            struct Settings {
                @Clamped var volume: Int
            }
            """,
            expandedSource: """
            struct Settings {
                @Clamped var volume: Int

                var throughLens: LensType.BoundLensValue<Settings, Settings> {
                    LensType.BoundLensValue(instance: self, lens: .identity)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Lenses are not generated for 'volume' because it has attributes or a property wrapper.",
                    line: 3,
                    column: 5,
                    severity: .warning
                ),
                DiagnosticSpec(
                    message: "changing is not generated for 'Settings' because 'volume' has attributes or a property wrapper.",
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    func testChangingPassesUnannotatedPropertiesThrough() throws {
        assertMacroExpansion(
            """
            @Lens
            struct Mixed {
                var count = 0
                var label: String
            }
            """,
            expandedSource: """
            struct Mixed {
                var count = 0
                var label: String

                enum Lenses {
                    static let label: LensType.LensValue<Mixed, String> = LensType.LensValue(
                        get: {
                            $0.label
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.label = newValue
                            return copy
                        }
                    )
                }

                func changing(label: String? = nil) -> Mixed {
                    Mixed(
                        count: self.count,
                        label: label ?? self.label
                    )
                }

                @dynamicMemberLookup
                struct ThroughLens {
                    let instance: Mixed

                    func get() -> Mixed {
                        instance
                    }

                    func set(_ newValue: Mixed) -> Mixed {
                        newValue
                    }

                    subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<Mixed, Subpart>) -> LensType.BoundLensValue<Mixed, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    func changing(label: String? = nil) -> Mixed {
                        self.set(Mixed(
                            count: self.get().count,
                            label: label ?? self.get().label
                        ))
                    }
                }

                var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Lenses require an explicit type annotation, so no lens was generated for 'count'.",
                    line: 3,
                    column: 9,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    func testChangingUsesOptionalFieldTypesDirectly() throws {
        assertMacroExpansion(
            """
            @Lens
            struct Account {
                var email: String?
                var name: String
            }
            """,
            expandedSource: """
            struct Account {
                var email: String?
                var name: String

                enum Lenses {
                    static let email: LensType.LensValue<Account, String?> = LensType.LensValue(
                        get: {
                            $0.email
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.email = newValue
                            return copy
                        }
                    )
                    static let name: LensType.LensValue<Account, String> = LensType.LensValue(
                        get: {
                            $0.name
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.name = newValue
                            return copy
                        }
                    )
                }

                func changing(email: String? = nil, name: String? = nil) -> Account {
                    Account(
                        email: email ?? self.email,
                        name: name ?? self.name
                    )
                }

                @dynamicMemberLookup
                struct ThroughLens {
                    let instance: Account

                    func get() -> Account {
                        instance
                    }

                    func set(_ newValue: Account) -> Account {
                        newValue
                    }

                    subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<Account, Subpart>) -> LensType.BoundLensValue<Account, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    func changing(email: String? = nil, name: String? = nil) -> Account {
                        self.set(Account(
                            email: email ?? self.get().email,
                            name: name ?? self.get().name
                        ))
                    }
                }

                var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testChangingSkipsCustomInitializersWithWarning() throws {
        assertMacroExpansion(
            """
            @Lens
            struct Transient {
                var value: Int

                init(value: Int) {
                    self.value = value * 2
                }
            }
            """,
            expandedSource: """
            struct Transient {
                var value: Int

                init(value: Int) {
                    self.value = value * 2
                }

                enum Lenses {
                    static let value: LensType.LensValue<Transient, Int> = LensType.LensValue(
                        get: {
                            $0.value
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.value = newValue
                            return copy
                        }
                    )
                }

                var throughLens: LensType.BoundLensValue<Transient, Transient> {
                    LensType.BoundLensValue(instance: self, lens: .identity)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "changing is not generated for 'Transient' because a custom initializer suppresses the memberwise initializer it rebuilds values with.",
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    func testChangingSupportsNestedStructs() throws {
        assertMacroExpansion(
            """
            struct Outer {
                @Lens
                struct Inner {
                    var value: Int
                }
            }
            """,
            expandedSource: """
            struct Outer {
                struct Inner {
                    var value: Int

                    enum Lenses {
                        static let value: LensType.LensValue<Inner, Int> = LensType.LensValue(
                            get: {
                                $0.value
                            },
                            set: { (newValue, whole) in
                                var copy = whole
                                copy.value = newValue
                                return copy
                            }
                        )
                    }

                    func changing(value: Int? = nil) -> Inner {
                        Inner(
                            value: value ?? self.value
                        )
                    }

                    @dynamicMemberLookup
                    struct ThroughLens {
                        let instance: Inner

                        func get() -> Inner {
                            instance
                        }

                        func set(_ newValue: Inner) -> Inner {
                            newValue
                        }

                        subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<Inner, Subpart>) -> LensType.BoundLensValue<Inner, Subpart> {
                            LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                        }

                        func changing(value: Int? = nil) -> Inner {
                            self.set(Inner(
                                value: value ?? self.get().value
                            ))
                        }
                    }

                    var throughLens: ThroughLens {
                        ThroughLens(instance: self)
                    }
                }
            }
            """,
            macros: testMacros
        )
    }

    func testOnlyStructsAreSupported() throws {
        assertMacroExpansion(
            """
            @Lens
            enum Direction {
                case north
            }
            """,
            expandedSource: """
            enum Direction {
                case north
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Lens can only be attached to a struct.",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }
    func testConstantWithInitialValueGetsNoLensWithWarning() throws {
        assertMacroExpansion(
            """
            @Lens
            struct Config {
                let id: Int = 1
                var name: String
            }
            """,
            expandedSource: """
            struct Config {
                let id: Int = 1
                var name: String

                enum Lenses {
                    static let name: LensType.LensValue<Config, String> = LensType.LensValue(
                        get: {
                            $0.name
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.name = newValue
                            return copy
                        }
                    )
                }

                func changing(name: String? = nil) -> Config {
                    Config(
                        name: name ?? self.name
                    )
                }

                @dynamicMemberLookup
                struct ThroughLens {
                    let instance: Config

                    func get() -> Config {
                        instance
                    }

                    func set(_ newValue: Config) -> Config {
                        newValue
                    }

                    subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<Config, Subpart>) -> LensType.BoundLensValue<Config, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    func changing(name: String? = nil) -> Config {
                        self.set(Config(
                            name: name ?? self.get().name
                        ))
                    }
                }

                var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Lenses are not generated for 'id' because constants with initial values are not part of the memberwise initializer.",
                    line: 3,
                    column: 9,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    func testKeepsCustomChangingMethod() throws {
        assertMacroExpansion(
            """
            @Lens
            struct Point {
                var x: Int
                var y: Int

                func changing(x: Int? = nil, y: Int? = nil) -> Point {
                    Point(x: x ?? self.x, y: y ?? self.y)
                }
            }
            """,
            expandedSource: """
            struct Point {
                var x: Int
                var y: Int

                func changing(x: Int? = nil, y: Int? = nil) -> Point {
                    Point(x: x ?? self.x, y: y ?? self.y)
                }

                enum Lenses {
                    static let x: LensType.LensValue<Point, Int> = LensType.LensValue(
                        get: {
                            $0.x
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.x = newValue
                            return copy
                        }
                    )
                    static let y: LensType.LensValue<Point, Int> = LensType.LensValue(
                        get: {
                            $0.y
                        },
                        set: { (newValue, whole) in
                            var copy = whole
                            copy.y = newValue
                            return copy
                        }
                    )
                }

                @dynamicMemberLookup
                struct ThroughLens {
                    let instance: Point

                    func get() -> Point {
                        instance
                    }

                    func set(_ newValue: Point) -> Point {
                        newValue
                    }

                    subscript <Subpart>(dynamicMember keyPath: WritableKeyPath<Point, Subpart>) -> LensType.BoundLensValue<Point, Subpart> {
                        LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
                    }

                    func changing(x: Int? = nil, y: Int? = nil) -> Point {
                        self.set(Point(
                            x: x ?? self.get().x,
                            y: y ?? self.get().y
                        ))
                    }
                }

                var throughLens: ThroughLens {
                    ThroughLens(instance: self)
                }
            }
            """,
            macros: testMacros
        )
    }
}
#endif
