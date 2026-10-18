import Lens
import XCTest

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
struct Team {
    var title: String
    var lead: Person
}

@Lens
struct Pair<A, B> {
    var first: A
    var second: B
}

@Lens
struct Snapshot {
    let version: Int
    let title: String
    var isDraft: Bool
    var note: String?
}

struct Warehouse {
    @Lens
    struct Crate {
        var label: String
        var weight: Int
    }
}

final class LensTests: XCTestCase {
    let author = Person(
        name: "Maciej Konieczny",
        address: Address(street: "Sesame Street")
    )

    func testPlainLens() {
        let name = Person.Lenses.name

        XCTAssertEqual(name.get(author), "Maciej Konieczny")

        let author2 = name.set("narf", author)
        XCTAssertEqual(author2.name, "narf")
        XCTAssertEqual(author2.address.street, "Sesame Street")

        // The original value is untouched.
        XCTAssertEqual(author.name, "Maciej Konieczny")
    }

    func testComposition() {
        let street = Person.Lenses.address.compose(Address.Lenses.street)

        XCTAssertEqual(street.get(author), "Sesame Street")

        let author2 = street.set("Baker Street", author)
        XCTAssertEqual(author2.address.street, "Baker Street")
        XCTAssertEqual(author2.name, "Maciej Konieczny")
    }

    func testBoundLens() {
        XCTAssertEqual(author.throughLens.name.get(), "Maciej Konieczny")

        let author2 = author.throughLens.name.set("narf")
        XCTAssertEqual(author2.name, "narf")
        XCTAssertEqual(author2.address.street, "Sesame Street")

        let author3 = author.throughLens.address.street.set("Baker Street")
        XCTAssertEqual(author3.address.street, "Baker Street")
        XCTAssertEqual(author3.name, "Maciej Konieczny")

        XCTAssertEqual(author.throughLens.address.street.get(), "Sesame Street")
    }

    func testChainedBoundLens() {
        let team = Team(
            title: "Compilers",
            lead: author
        )

        XCTAssertEqual(team.throughLens.lead.name.get(), "Maciej Konieczny")
        XCTAssertEqual(team.throughLens.lead.address.street.get(), "Sesame Street")

        let team2 = team.throughLens.lead.address.street.set("Baker Street")
        XCTAssertEqual(team2.lead.address.street, "Baker Street")
        XCTAssertEqual(team2.title, "Compilers")
    }

    func testIdentityLens() {
        XCTAssertEqual(author.throughLens.get().name, "Maciej Konieczny")

        let other = Person(name: "narf", address: author.address)
        XCTAssertEqual(author.throughLens.set(other).name, "narf")

        XCTAssertEqual(Lens<Person, Person>.identity.get(author).name, "Maciej Konieczny")
    }

    func testKeyPathInitializer() {
        let name = Lens<Person, String>(\.name)

        XCTAssertEqual(name.get(author), "Maciej Konieczny")
        XCTAssertEqual(name.set("narf", author).name, "narf")
    }

    func testGenericStruct() {
        let pair = Pair(first: "one", second: 2)

        XCTAssertEqual(Pair<String, Int>.Lenses.first.get(pair), "one")
        XCTAssertEqual(Pair<String, Int>.Lenses.first.set("uno", pair).first, "uno")

        XCTAssertEqual(pair.throughLens.second.get(), 2)
        XCTAssertEqual(pair.throughLens.second.set(3).second, 3)
    }

    func testChanging() {
        let changed = author.throughLens.changing(name: "narf")
        XCTAssertEqual(changed.name, "narf")
        XCTAssertEqual(changed.address.street, "Sesame Street")

        // The original value is untouched.
        XCTAssertEqual(author.name, "Maciej Konieczny")

        let changed2 = author.throughLens.changing(
            name: "narf",
            address: Address(street: "Baker Street")
        )
        XCTAssertEqual(changed2.name, "narf")
        XCTAssertEqual(changed2.address.street, "Baker Street")
    }

    func testChangingWorksWithLetAndOptionalProperties() {
        let snapshot = Snapshot(version: 1, title: "hello", isDraft: false, note: nil)

        let changed = snapshot.throughLens.changing(version: 2, title: "goodbye", isDraft: true)
        XCTAssertEqual(changed.version, 2)
        XCTAssertEqual(changed.title, "goodbye")
        XCTAssertEqual(changed.isDraft, true)
        XCTAssertEqual(changed.note, nil)

        let changed2 = snapshot.throughLens.changing(note: "later")
        XCTAssertEqual(changed2.note, "later")
        XCTAssertEqual(changed2.version, 1)

        // Passing nil keeps the current value, so an optional property
        // cannot be reset to nil this way.
        XCTAssertEqual(changed2.throughLens.changing(note: nil).note, "later")
    }

    func testLetPropertiesGetRebuildBoundLenses() {
        let snapshot = Snapshot(version: 1, title: "hello", isDraft: false, note: nil)

        XCTAssertEqual(snapshot.throughLens.version.get(), 1)
        XCTAssertEqual(snapshot.throughLens.title.get(), "hello")

        let bumped = snapshot.throughLens.version.set(2)
        XCTAssertEqual(bumped.version, 2)
        XCTAssertEqual(bumped.title, "hello")
        XCTAssertEqual(bumped.isDraft, false)

        // The original value is untouched.
        XCTAssertEqual(snapshot.version, 1)

        let retitled = snapshot.throughLens.title.set("goodbye")
        XCTAssertEqual(retitled.title, "goodbye")
        XCTAssertEqual(retitled.version, 1)

        // Rebuild-based let lenses compose with the dynamic member chains.
        let combined = retitled.throughLens.isDraft.set(true)
        XCTAssertEqual(combined.title, "goodbye")
        XCTAssertEqual(combined.isDraft, true)
    }

    func testChangingKeepsThroughLensChainable() {
        let changed = author.throughLens
            .changing(name: "narf")
            .throughLens.address.street.set("Baker Street")
        XCTAssertEqual(changed.name, "narf")
        XCTAssertEqual(changed.address.street, "Baker Street")
    }

    func testChangingForGenericStruct() {
        let pair = Pair(first: "one", second: 2)

        let changed = pair.throughLens.changing(first: "uno")
        XCTAssertEqual(changed.first, "uno")
        XCTAssertEqual(changed.second, 2)

        XCTAssertEqual(Pair<String, Int>.Lenses.second.get(changed), 2)
    }

    func testChangingForNestedStruct() {
        let crate = Warehouse.Crate(label: "fragile", weight: 42)

        let changed = crate.throughLens.changing(label: "heavy", weight: 100)
        XCTAssertEqual(changed.label, "heavy")
        XCTAssertEqual(changed.weight, 100)

        XCTAssertEqual(crate.throughLens.weight.get(), 42)
    }
}
