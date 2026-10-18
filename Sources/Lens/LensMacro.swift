/// Generates a `Lenses` namespace, a `throughLens` chain of bound lenses, and
/// a `changing` convenience that replaces several fields at once. The API is
/// based on [lenso](https://github.com/narfdotpl/lenso) by Maciej Konieczny.
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
/// Person.Lenses.name.get(author)                 // "Maciej Konieczny"
/// Person.Lenses.name.set("narf", author)         // Person with name "narf"
/// author.throughLens.address.street.set("Baker Street")  // Person
/// author.throughLens.changing(name: "narf", address: Address(street: "Baker Street"))
/// ```
///
/// expands to:
///
/// ```swift
/// struct Person {
///     var name: String
///     var address: Address
///
///     enum Lenses {
///         static let name: LensType.LensValue<Person, String> = LensType.LensValue(
///             get: { $0.name },
///             set: { (newValue, whole) in
///                 var copy = whole
///                 copy.name = newValue
///                 return copy
///             }
///         )
///         // ... one entry per stored property: `let` entries rebuild the
///         // value through the memberwise initializer instead of copying it
///     }
///
///     func changing(name: String? = nil, address: Address? = nil) -> Person {
///         Person(
///             name: name ?? self.name,
///             address: address ?? self.address
///         )
///     }
///
///     @dynamicMemberLookup
///     struct ThroughLens {
///         let instance: Person
///
///         func get() -> Person {
///             instance
///         }
///
///         func set(_ newValue: Person) -> Person {
///             newValue
///         }
///
///         subscript<Subpart>(dynamicMember keyPath: WritableKeyPath<Person, Subpart>) -> LensType.BoundLensValue<Person, Subpart> {
///             LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
///         }
///
///         func changing(name: String? = nil, address: Address? = nil) -> Person {
///             self.set(Person(
///                 name: name ?? self.get().name,
///                 address: address ?? self.get().address
///             ))
///         }
///     }
///
///     var throughLens: ThroughLens {
///         ThroughLens(instance: self)
///     }
/// }
/// ```
///
/// Every stored property with an explicit type annotation gets an entry in
/// `Lenses`: `var` entries replace the field in a copy of the value, while
/// `let` entries rebuild the value through the memberwise initializer.
/// Computed properties, static members, and properties with property
/// wrappers are skipped for lenses.
///
/// Dot-notation chains only go through `var` properties (key paths are not
/// writable for constants), so stored `let` properties also get dedicated
/// rebuild-based bound lenses on the generated `ThroughLens` wrapper —
/// `snapshot.throughLens.version.set(2)` works like any other chain — and
/// their `Lenses` entries compose like any other lens.
///
/// `changing` is generated both on the value itself and on `throughLens`.
/// It rebuilds through the memberwise initializer, so it can replace every
/// stored property — including `let` ones — in one call. Passing `nil` (or
/// omitting a parameter) keeps the current value; an optional property
/// cannot be set back to `nil` this way (a rebuild-based `let` lens can).
///
/// `changing` and the rebuild-based `let` lenses are not generated for
/// structs with custom initializers or structs whose properties have
/// property wrappers, because the memberwise initializer they build on is
/// not available in those cases. Such structs keep a plain `throughLens`
/// property and `let` properties cannot be chained.
///
/// Generic structs get computed lenses (`static var`) instead of stored
/// ones, because Swift does not allow static stored properties in generic
/// types.
@attached(member, names: named(Lenses), named(throughLens), named(ThroughLens), named(changing))
public macro Lens() = #externalMacro(module: "LensMacros", type: "LensMacro")
