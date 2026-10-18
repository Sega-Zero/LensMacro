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

let author = Person(name: "Maciej Konieczny", address: Address(street: "Sesame Street"))

// Plain lenses.
print(Person.Lenses.name.get(author))
print(Person.Lenses.name.set("narf", author))

// Composition.
let personStreetLens = Person.Lenses.address.compose(Address.Lenses.street)
print(personStreetLens.get(author))
print(personStreetLens.set("Wisteria Lane", author))

// Bound lenses: dot notation without manual composition.
let author2 = author.throughLens.address.street.set("Baker Street")
print(author2)
print(author.throughLens.name.get())

// Changing several fields at once; omitted fields keep their values.
let author3 = author.throughLens.changing(name: "narf", address: Address(street: "Baker Street"))
print(author3)
print(author.throughLens.changing(name: "narf"))
