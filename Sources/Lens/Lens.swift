// Lens
//
// API based on lenso by Maciej Konieczny:
// https://github.com/narfdotpl/lenso

// MARK: - Lens

/// A composable pair of a getter and a setter focused on a single `Part` of
/// a `Whole` — "functional getters and setters" for immutable values.
///
/// ```swift
/// @Lens
/// struct Person {
///     var name: String
///     var address: Address
/// }
///
/// let author = Person(name: "Maciej Konieczny", address: Address(street: "Sesame Street"))
///
/// Person.Lenses.name.get(author)                // "Maciej Konieczny"
/// Person.Lenses.name.set("narf", author)        // Person with name "narf"
/// ```
public struct Lens<Whole, Part>: Sendable {

    /// Reads the part out of a whole.
    public let get: @Sendable (Whole) -> Part

    /// Replaces the part in a whole and returns the updated whole.
    /// Note the lenso argument order: the new part comes first.
    public let set: @Sendable (Part, Whole) -> Whole

    /// Creates a lens from a getter and a setter.
    public init(
        get: @escaping @Sendable (Whole) -> Part,
        set: @escaping @Sendable (Part, Whole) -> Whole
    ) {
        self.get = get
        self.set = set
    }

    /// Creates a writable lens from a key path.
    ///
    /// ```swift
    /// let name = Lens<Person, String>(\.name)
    /// ```
    ///
    /// - Note: The key path is boxed as `@unchecked Sendable` so the lens can
    ///   remain `Sendable`. This is safe for key paths over stored
    ///   properties; key paths that capture mutable state through bound
    ///   subscript arguments should not be shared across isolation domains.
    public init(_ keyPath: WritableKeyPath<Whole, Part>) {
        let storage = KeyPathStorage(keyPath: keyPath)
        self.init(
            get: { whole in whole[keyPath: storage.keyPath] },
            set: { (newPart, whole) in
                var copy = whole
                copy[keyPath: storage.keyPath] = newPart
                return copy
            }
        )
    }

    /// The lens that focuses on the whole value itself.
    public static var identity: Lens<Whole, Whole> {
        Lens<Whole, Whole>(
            get: { $0 },
            set: { (newWhole, _) in newWhole }
        )
    }

    /// Composes this lens with a lens that focuses deeper into the part.
    ///
    /// ```swift
    /// let street = Person.Lenses.address.compose(Address.Lenses.street)
    /// street.get(author)                  // "Sesame Street"
    /// street.set("Baker Street", author)  // Person with a new street
    /// ```
    public func compose<Subpart>(_ other: Lens<Part, Subpart>) -> Lens<Whole, Subpart> {
        Lens<Whole, Subpart>(
            get: { whole in other.get(self.get(whole)) },
            set: { (newSubpart, whole) in
                let part = self.get(whole)
                let newPart = other.set(newSubpart, part)
                return self.set(newPart, whole)
            }
        )
    }
}

// MARK: - Bound lenses

/// A whole instance together with the lens that focuses on its part.
public struct BoundLensStorage<Whole, Part> {
    public let instance: Whole
    public let lens: Lens<Whole, Part>

    public init(instance: Whole, lens: Lens<Whole, Part>) {
        self.instance = instance
        self.lens = lens
    }
}

/// A lens that is already "used half way": it has a `Whole` instance
/// associated with it, which allows dot-notation access:
/// `author.throughLens.address.street.set("Baker Street")`.
public protocol BoundLensType {
    associatedtype Whole
    associatedtype Part

    init(boundLensStorage: BoundLensStorage<Whole, Part>)

    var boundLensStorage: BoundLensStorage<Whole, Part> { get }

    /// Returns the focused part of the bound instance.
    func get() -> Part

    /// Returns a copy of the bound whole with the part replaced.
    func set(_ newPart: Part) -> Whole
}

public extension BoundLensType {
    /// Binds a lens to an instance.
    init(instance: Whole, lens: Lens<Whole, Part>) {
        self.init(boundLensStorage: BoundLensStorage(instance: instance, lens: lens))
    }

    /// Binds a lens that focuses deeper into the currently focused part.
    init<Parent: BoundLensType>(parent: Parent, sublens: Lens<Parent.Part, Part>) where Parent.Whole == Whole {
        let storage = parent.boundLensStorage
        self.init(instance: storage.instance, lens: storage.lens.compose(sublens))
    }

    /// Returns the focused part of the bound instance.
    func get() -> Part {
        boundLensStorage.lens.get(boundLensStorage.instance)
    }

    /// Returns a copy of the bound whole with the part replaced.
    func set(_ newPart: Part) -> Whole {
        boundLensStorage.lens.set(newPart, boundLensStorage.instance)
    }
}

/// A bound lens that can chain through writable properties of the focused
/// part using dot notation:
///
/// ```swift
/// author.throughLens.name.get()                          // "Maciej Konieczny"
/// author.throughLens.address.street.set("Baker Street")  // Person
/// ```
@dynamicMemberLookup
public struct BoundLens<Whole, Part>: BoundLensType {
    public let boundLensStorage: BoundLensStorage<Whole, Part>

    public init(boundLensStorage: BoundLensStorage<Whole, Part>) {
        self.boundLensStorage = boundLensStorage
    }

    /// Chains through a `var` property of the focused part.
    public subscript<Subpart>(dynamicMember keyPath: WritableKeyPath<Part, Subpart>) -> BoundLens<Whole, Subpart> {
        BoundLens<Whole, Subpart>(parent: self, sublens: Lens(keyPath))
    }
}

// MARK: - Macro support

/// Names used by `@Lens`'s generated code to reference the runtime types.
///
/// Routing generated code through this namespace keeps it compiling even
/// when the surrounding module declares its own types named `Lens` or
/// `BoundLens`, which would otherwise shadow the imported ones.
///
/// This is an implementation detail of the macro — do not use it directly.
public enum LensType {
    public typealias LensValue<Whole, Part> = Lens<Whole, Part>
    public typealias BoundLensValue<Whole, Part> = BoundLens<Whole, Part>
}

// MARK: - Private

/// A `Sendable` box for a writable key path.
///
/// Key paths are immutable and safe to share for key paths over stored
/// properties. This box keeps the `@Sendable` closures of ``Lens``
/// compilable while documenting that assumption.
private struct KeyPathStorage<Whole, Part>: @unchecked Sendable {
    let keyPath: WritableKeyPath<Whole, Part>
}
