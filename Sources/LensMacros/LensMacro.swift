import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Implementation of the `@Lens` macro, which adds a nested `Lenses` enum
/// with one `Lens` per stored `var` property of the annotated struct, and a
/// `throughLens` entry point that starts a chain of bound lenses and can
/// replace several fields at once with `changing`.
///
/// The API is based on <https://github.com/narfdotpl/lenso>.
public struct LensMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw LensMacroError(message: "@Lens can only be attached to a struct.")
        }

        let rootType = rootTypeName(of: structDecl)
        let access = accessPrefix(of: structDecl)

        var lenses: [String] = []

        for member in structDecl.memberBlock.members {
            guard let property = member.decl.as(VariableDeclSyntax.self),
                  property.bindingSpecifier.tokenKind == .keyword(.var),
                  !property.modifiers.contains(where: isStaticModifier)
            else {
                continue
            }

            let names = property.bindings.compactMap {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            }
            let displayName = names.first.map { "'\($0)'" } ?? "this property"

            guard property.attributes.isEmpty else {
                context.diagnose(
                    Diagnostic(
                        node: property,
                        message: LensMacroWarning(
                            message: "Lenses are not generated for \(displayName) because it has attributes or a property wrapper."
                        )
                    )
                )
                continue
            }

            for binding in property.bindings {
                // Computed and observed properties are not lenses.
                guard binding.accessorBlock == nil else { continue }

                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                else { continue }

                guard let typeAnnotation = binding.typeAnnotation else {
                    context.diagnose(
                        Diagnostic(
                            node: binding,
                            message: LensMacroWarning(
                                message: "Lenses require an explicit type annotation, so no lens was generated for '\(identifier)'."
                            )
                        )
                    )
                    continue
                }

                lenses.append(
                    lensDeclaration(
                        access: access,
                        rootType: rootType,
                        name: identifier,
                        type: typeAnnotation.type.trimmedDescription,
                        isGeneric: structDecl.genericParameterClause != nil
                    )
                )
            }
        }

        var members: [DeclSyntax] = []

        if !lenses.isEmpty {
            let enumDecl: DeclSyntax = """
            \(raw: access)enum Lenses {
            \(raw: lenses.joined(separator: "\n"))
            }
            """
            members.append(enumDecl)
        }

        if let wrapper = changingWrapperDeclaration(
            of: structDecl,
            rootType: rootType,
            access: access,
            in: context
        ) {
            let wrapperDecl: DeclSyntax = "\(raw: wrapper)"
            members.append(wrapperDecl)

            let throughLensDecl: DeclSyntax = "\(raw: throughLensWrapperDeclaration(access: access))"
            members.append(throughLensDecl)
        } else {
            let throughLensDecl: DeclSyntax = "\(raw: throughLensDeclaration(access: access, rootType: rootType))"
            members.append(throughLensDecl)
        }

        return members
    }

    // MARK: - changing

    private struct ChangingField {
        let name: String
        let type: String?
        let isOptional: Bool
        let hasAttributes: Bool
        let isMutable: Bool
    }

    /// Builds the `ThroughLens` wrapper that `throughLens` returns, whose
    /// `changing` method replaces several fields of the annotated struct in
    /// one call:
    ///
    /// ```swift
    /// author.throughLens.changing(name: "narf", address: newAddress)
    /// ```
    ///
    /// Rebuilding values goes through the memberwise initializer, so the
    /// wrapper is skipped for structs with custom initializers or with
    /// properties that have attributes.
    private static func changingWrapperDeclaration(
        of structDecl: StructDeclSyntax,
        rootType: String,
        access: String,
        in context: some MacroExpansionContext
    ) -> String? {
        let name = structDecl.name.text

        guard let fields = changingFields(of: structDecl) else {
            return nil
        }

        if structDecl.memberBlock.members.contains(where: { $0.decl.is(InitializerDeclSyntax.self) }) {
            context.diagnose(
                Diagnostic(
                    node: structDecl,
                    message: LensMacroWarning(
                        message: "changing is not generated for '\(name)' because a custom initializer suppresses the memberwise initializer it rebuilds values with."
                    )
                )
            )
            return nil
        }

        if let wrapped = fields.first(where: { $0.hasAttributes }) {
            context.diagnose(
                Diagnostic(
                    node: structDecl,
                    message: LensMacroWarning(
                        message: "changing is not generated for '\(name)' because '\(wrapped.name)' has attributes or a property wrapper."
                    )
                )
            )
            return nil
        }

        guard fields.contains(where: { $0.type != nil }) else {
            return nil
        }

        return changingWrapper(access: access, rootType: rootType, fields: fields)
    }

    /// Collects the stored properties a rebuilt value is assembled from.
    /// Returns `nil` when a member is something the generated initializer
    /// call cannot handle.
    private static func changingFields(of structDecl: StructDeclSyntax) -> [ChangingField]? {
        var fields: [ChangingField] = []
        for member in structDecl.memberBlock.members {
            guard let property = member.decl.as(VariableDeclSyntax.self),
                  !property.modifiers.contains(where: isStaticModifier),
                  !property.modifiers.contains(where: isLazyModifier)
            else {
                continue
            }
            let isMutable = property.bindingSpecifier.tokenKind == .keyword(.var)
            for binding in property.bindings {
                // Getter/setter accessor blocks describe computed properties,
                // while `willSet`/`didSet` observers keep a stored property.
                if let accessors = binding.accessorBlock, isComputed(accessors) {
                    continue
                }
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                else {
                    return nil
                }
                fields.append(
                    ChangingField(
                        name: identifier,
                        type: binding.typeAnnotation?.type.trimmedDescription,
                        isOptional: binding.typeAnnotation.map { isOptionalType($0.type) } ?? false,
                        hasAttributes: !property.attributes.isEmpty,
                        isMutable: isMutable
                    )
                )
            }
        }
        return fields
    }

    private static func changingWrapper(
        access: String,
        rootType: String,
        fields: [ChangingField]
    ) -> String {
        let parameters = fields.compactMap { field -> String? in
            guard let type = field.type else { return nil }
            return "\(field.name): \(type)\(field.isOptional ? "" : "?") = nil"
        }
        let arguments = fields.map { field -> String in
            guard field.type != nil else {
                return "\(field.name): self.get().\(field.name)"
            }
            return "\(field.name): \(field.name) ?? self.get().\(field.name)"
        }
        let letLenses = fields.compactMap { field -> String? in
            guard field.type != nil, !field.isMutable else { return nil }
            return letFieldLens(field: field, rootType: rootType, access: access)
        }
        let letLensesSection = letLenses.isEmpty
            ? ""
            : "\n\(letLenses.joined(separator: "\n\n"))\n"
        return """
        @dynamicMemberLookup
        \(access)struct ThroughLens {
            let instance: \(rootType)

            \(access)func get() -> \(rootType) {
                instance
            }

            \(access)func set(_ newValue: \(rootType)) -> \(rootType) {
                newValue
            }

            \(access)subscript<Subpart>(dynamicMember keyPath: WritableKeyPath<\(rootType), Subpart>) -> LensType.BoundLensValue<\(rootType), Subpart> {
                LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(keyPath))
            }
        \(letLensesSection)
            \(access)func changing(\(parameters.joined(separator: ", "))) -> \(rootType) {
                self.set(\(rootType)(
                    \(arguments.joined(separator: ",\n            "))
                ))
            }
        }
        """
    }

    /// A bound lens for a stored `let` property. Key paths are not writable
    /// for constants, so the lens rebuilds the value through `changing`
    /// instead of mutating a copy.
    private static func letFieldLens(
        field: ChangingField,
        rootType: String,
        access: String
    ) -> String {
        """
            \(access)var \(field.name): LensType.BoundLensValue<\(rootType), \(field.type ?? "")> {
                LensType.BoundLensValue(instance: instance, lens: LensType.LensValue(
                    get: {
                        $0.\(field.name)
                    },
                    set: { (newValue, whole) in
                        whole.throughLens.changing(\(field.name): newValue)
                    }
                ))
            }
        """
    }

    private static func throughLensWrapperDeclaration(access: String) -> String {
        """
        \(access)var throughLens: ThroughLens {
            ThroughLens(instance: self)
        }
        """
    }

    private static func lensDeclaration(
        access: String,
        rootType: String,
        name: String,
        type: String,
        isGeneric: Bool
    ) -> String {
        if isGeneric {
            // Swift does not support static stored properties in generic
            // types, so the lens is computed on demand instead.
            return """
            \(access)static var \(name): LensType.LensValue<\(rootType), \(type)> {
                LensType.LensValue(
                    get: { $0.\(name) },
                    set: { (newValue, whole) in
                        var copy = whole
                        copy.\(name) = newValue
                        return copy
                    }
                )
            }
            """
        }
        return """
        \(access)static let \(name): LensType.LensValue<\(rootType), \(type)> = LensType.LensValue(
            get: { $0.\(name) },
            set: { (newValue, whole) in
                var copy = whole
                copy.\(name) = newValue
                return copy
            }
        )
        """
    }

    private static func throughLensDeclaration(access: String, rootType: String) -> String {
        """
        \(access)var throughLens: LensType.BoundLensValue<\(rootType), \(rootType)> {
            LensType.BoundLensValue(instance: self, lens: .identity)
        }
        """
    }

    private static func rootTypeName(of structDecl: StructDeclSyntax) -> String {
        let name = structDecl.name.text
        guard let clause = structDecl.genericParameterClause else {
            return name
        }
        let parameters = clause.parameters.map { parameter -> String in
            if let specifier = parameter.specifier {
                return "\(specifier.text) \(parameter.name.text)"
            }
            return parameter.name.text
        }
        return "\(name)<\(parameters.joined(separator: ", "))>"
    }

    private static func accessPrefix(of structDecl: StructDeclSyntax) -> String {
        for modifier in structDecl.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.package), .keyword(.fileprivate), .keyword(.private):
                return "\(modifier.name.text) "
            default:
                continue
            }
        }
        return ""
    }

    private static func isStaticModifier(_ modifier: DeclModifierSyntax) -> Bool {
        switch modifier.name.tokenKind {
        case .keyword(.static), .keyword(.class):
            return true
        default:
            return false
        }
    }

    private static func isLazyModifier(_ modifier: DeclModifierSyntax) -> Bool {
        modifier.name.text == "lazy"
    }

    private static func isComputed(_ accessors: AccessorBlockSyntax) -> Bool {
        switch accessors.accessors {
        case .getter:
            return true
        case .accessors(let list):
            return list.contains { accessor in
                let specifier = accessor.accessorSpecifier.text
                return specifier == "get" || specifier == "set"
                    || specifier == "_read" || specifier == "_modify"
            }
        }
    }

    private static func isOptionalType(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return true
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return isOptionalType(attributed.baseType)
        }
        return false
    }
}

struct LensMacroError: Error, CustomStringConvertible {
    let description: String

    init(message: String) {
        self.description = message
    }
}

struct LensMacroWarning: DiagnosticMessage {
    let message: String

    var diagnosticID: MessageID {
        MessageID(domain: "LensMacros", id: "warning")
    }

    var severity: DiagnosticSeverity {
        .warning
    }
}

@main
struct LensPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LensMacro.self,
    ]
}
