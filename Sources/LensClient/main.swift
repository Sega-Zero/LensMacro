import Lens

@Lens
struct Address {
    var street: String
}

@Lens
struct Person {
    var name: String
    var address: Address
}

@Lens
struct Snapshot {
    let version: Int
    var title: String?
}

let author = Person(name: "Maciej Konieczny", address: Address(street: "Sesame Street"))

// Plain lenses.
print(Person.Lenses.name.get(author))
print(Person.Lenses.name.set("narf", author))

// Composition.
let personStreetLens = Person.Lenses.address.compose(Address.Lenses.street)
print(personStreetLens.get(author))
print(personStreetLens.set("Wisteria Lane", author))

// Lenses for `let` properties rebuild the value through the memberwise
// initializer, so they compose like any other lens.
let snapshot = Snapshot(version: 1, title: nil)
print(Snapshot.Lenses.version.set(2, snapshot))
print(Snapshot.Lenses.title.get(snapshot))

// Bound lenses: dot notation without manual composition.
let author2 = author.throughLens.address.street.set("Baker Street")
print(author2)
print(author.throughLens.name.get())

// Bound lenses for `let` properties work the same way.
let snapshot2 = snapshot.throughLens.version.set(2).throughLens.title.set("hello")
print(snapshot2)
print(snapshot2.throughLens.title.set(nil))

// Changing several fields at once; omitted fields keep their values.
let author3 = author.changing(name: "narf", address: Address(street: "Baker Street"))
print(author3)
print(author.throughLens.changing(name: "narf"))
