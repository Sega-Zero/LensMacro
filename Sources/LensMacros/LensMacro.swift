import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Implementation of the `@Lens` macro, which adds a nested `Lenses` enum
/// with one `Lens` per stored property of the annotated struct, a `changing`
/// method that replaces several fields at once, and a `throughLens` entry
/// point that starts a chain of bound lenses.
///
/// Lenses for `var` properties replace the field in a copy of the value.
/// Lenses for `let` properties, `changing`, and the bound lenses for
/// constants rebuild the value through the memberwise initializer, so they
/// are only generated when a memberwise initializer is available.
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
        let isGeneric = structDecl.genericParameterClause != nil

        let fields = collectFields(of: structDecl, in: context)

        // Rebuilding goes through the memberwise initializer, which exists
        // only when the struct declares no initializers of its own and every
        // stored property can appear in the generated call.
        let rebuildFields = fields.filter { !$0.isLazy }
        let fieldsAreCollectable = rebuildFields.allSatisfy { $0.name != nil }
        let hasCustomInitializer = structDecl.memberBlock.members.contains {
            $0.decl.is(InitializerDeclSyntax.self)
        }
        let wrappedField = rebuildFields.first { $0.hasAttributes }

        if fieldsAreCollectable {
            if hasCustomInitializer {
                context.diagnose(
                    Diagnostic(
                        node: structDecl,
                        message: LensMacroWarning(
                            message: "changing is not generated for '\(structDecl.name.text)' because a custom initializer suppresses the memberwise initializer it rebuilds values with."
                        )
                    )
                )
            } else if let wrappedField {
                context.diagnose(
                    Diagnostic(
                        node: structDecl,
                        message: LensMacroWarning(
                            message: "changing is not generated for '\(structDecl.name.text)' because '\(wrappedField.name ?? "a property")' has attributes or a property wrapper."
                        )
                    )
                )
            }
        }

        let canRebuild = fieldsAreCollectable && !hasCustomInitializer && wrappedField == nil
        let canChange = rebuildFields.contains { $0.isMemberwiseParameter && $0.type != nil }
        let declaresChanging = structDecl.memberBlock.members.contains { member in
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                return function.name.text == "changing"
            }
            if let property = member.decl.as(VariableDeclSyntax.self) {
                return property.bindings.contains {
                    $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "changing"
                }
            }
            return false
        }

        var members: [DeclSyntax] = []

        var lensEntries: [String] = []
        for field in fields where !field.hasAttributes {
            guard let name = field.name, let type = field.type else { continue }

            if field.isMutable {
                lensEntries.append(
                    variableLensDeclaration(
                        access: access,
                        rootType: rootType,
                        isGeneric: isGeneric,
                        name: name,
                        type: type
                    )
                )
            } else if !field.hasInitializer, canRebuild {
                lensEntries.append(
                    rebuildLensDeclaration(
                        access: access,
                        rootType: rootType,
                        isGeneric: isGeneric,
                        name: name,
                        type: type,
                        arguments: rebuildArguments(of: rebuildFields, replacing: name)
                    )
                )
            }
        }

        if !lensEntries.isEmpty {
            let enumDecl: DeclSyntax = """
            \(raw: access)enum Lenses {
            \(raw: lensEntries.joined(separator: "\n"))
            }
            """
            members.append(enumDecl)
        }

        if canRebuild, canChange {
            if !declaresChanging {
                let changingDecl: DeclSyntax = "\(raw: changingDeclaration(access: access, rootType: rootType, fields: rebuildFields))"
                members.append(changingDecl)
            }

            let wrapperDecl: DeclSyntax = "\(raw: throughLensStructDeclaration(access: access, rootType: rootType, fields: rebuildFields))"
            members.append(wrapperDecl)

            let throughLensDecl: DeclSyntax = "\(raw: throughLensWrapperDeclaration(access: access))"
            members.append(throughLensDecl)
        } else {
            let throughLensDecl: DeclSyntax = "\(raw: throughLensDeclaration(access: access, rootType: rootType))"
            members.append(throughLensDecl)
        }

        return members
    }

    // MARK: - Collecting properties

    /// A stored property of the annotated struct, used to build both the
    /// `Lenses` entries and the memberwise initializer calls that rebuild
    /// values.
    private struct Field {
        let name: String?
        let type: String?
        let isOptional: Bool
        let isMutable: Bool
        let hasAttributes: Bool
        let isLazy: Bool
        let hasInitializer: Bool

        /// `true` when the property is a memberwise initializer parameter, so
        /// a rebuilt value can pass it through.
        var isMemberwiseParameter: Bool {
            !hasAttributes && (isMutable || !hasInitializer)
        }
    }

    private static func collectFields(
        of structDecl: StructDeclSyntax,
        in context: some MacroExpansionContext
    ) -> [Field] {
        var fields: [Field] = []

        for member in structDecl.memberBlock.members {
            guard let property = member.decl.as(VariableDeclSyntax.self),
                  !property.modifiers.contains(where: isStaticModifier)
            else {
                continue
            }

            let hasAttributes = !property.attributes.isEmpty
            let isLazy = property.modifiers.contains(where: isLazyModifier)
            let isMutable = property.bindingSpecifier.tokenKind == .keyword(.var)

            if hasAttributes {
                let names = property.bindings.compactMap {
                    $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                }
                let displayName = names.first.map { "'\($0)'" } ?? "this property"
                context.diagnose(
                    Diagnostic(
                        node: property,
                        message: LensMacroWarning(
                            message: "Lenses are not generated for \(displayName) because it has attributes or a property wrapper."
                        )
                    )
                )
            }

            for binding in property.bindings {
                // Getter/setter accessor blocks describe computed properties,
                // which are not stored, so there is nothing to focus on.
                if let accessors = binding.accessorBlock, isComputed(accessors) {
                    continue
                }

                let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                let hasInitializer = binding.initializer != nil

                if !hasAttributes {
                    if !isMutable, hasInitializer {
                        if let name {
                            context.diagnose(
                                Diagnostic(
                                    node: binding,
                                    message: LensMacroWarning(
                                        message: "Lenses are not generated for '\(name)' because constants with initial values are not part of the memberwise initializer."
                                    )
                                )
                            )
                        }
                    } else if binding.typeAnnotation == nil, let name {
                        context.diagnose(
                            Diagnostic(
                                node: binding,
                                message: LensMacroWarning(
                                    message: "Lenses require an explicit type annotation, so no lens was generated for '\(name)'."
                                )
                            )
                        )
                    }
                }

                fields.append(
                    Field(
                        name: name,
                        type: binding.typeAnnotation?.type.trimmedDescription,
                        isOptional: binding.typeAnnotation.map { isOptionalType($0.type) } ?? false,
                        isMutable: isMutable,
                        hasAttributes: hasAttributes,
                        isLazy: isLazy,
                        hasInitializer: hasInitializer
                    )
                )
            }
        }

        return fields
    }

    // MARK: - changing

    private static func changingParameters(of fields: [Field]) -> [String] {
        fields.compactMap { field in
            guard field.isMemberwiseParameter, let name = field.name, let type = field.type else {
                return nil
            }
            return "\(name): \(type)\(field.isOptional ? "" : "?") = nil"
        }
    }

    private static func changingArguments(of fields: [Field], whole: String) -> [String] {
        fields.compactMap { field in
            guard field.isMemberwiseParameter, let name = field.name else { return nil }
            guard field.type != nil else { return "\(name): \(whole).\(name)" }
            return "\(name): \(name) ?? \(whole).\(name)"
        }
    }

    /// Arguments that rebuild the whole value, replacing `replacement` with
    /// `newValue` and passing every other memberwise parameter through.
    private static func rebuildArguments(of fields: [Field], replacing replacement: String) -> [String] {
        fields.compactMap { field in
            guard field.isMemberwiseParameter, let name = field.name else { return nil }
            guard name != replacement else { return "\(name): newValue" }
            return "\(name): whole.\(name)"
        }
    }

    private static func changingDeclaration(
        access: String,
        rootType: String,
        fields: [Field]
    ) -> String {
        let parameters = changingParameters(of: fields).joined(separator: ", ")
        let arguments = changingArguments(of: fields, whole: "self").joined(separator: ",\n        ")
        return """
        \(access)func changing(\(parameters)) -> \(rootType) {
            \(rootType)(
                \(arguments)
            )
        }
        """
    }

    private static func throughLensStructDeclaration(
        access: String,
        rootType: String,
        fields: [Field]
    ) -> String {
        let parameters = changingParameters(of: fields).joined(separator: ", ")
        let arguments = changingArguments(of: fields, whole: "self.get()").joined(separator: ",\n            ")
        let constantLenses = fields.compactMap { field -> String? in
            guard !field.isMutable, !field.hasInitializer,
                  let name = field.name, let type = field.type
            else {
                return nil
            }
            return constantBoundLens(access: access, rootType: rootType, name: name, type: type)
        }
        let constantLensesSection = constantLenses.isEmpty
            ? ""
            : "\n\(constantLenses.joined(separator: "\n\n"))\n"
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
        \(constantLensesSection)
            \(access)func changing(\(parameters)) -> \(rootType) {
                self.set(\(rootType)(
                    \(arguments)
                ))
            }
        }
        """
    }

    /// A bound lens for a stored `let` property. It delegates to the rebuild
    /// lens of the nested `Lenses` enum.
    private static func constantBoundLens(
        access: String,
        rootType: String,
        name: String,
        type: String
    ) -> String {
        """
            \(access)var \(name): LensType.BoundLensValue<\(rootType), \(type)> {
                LensType.BoundLensValue(instance: instance, lens: Lenses.\(name))
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

    // MARK: - Lenses

    private static func variableLensDeclaration(
        access: String,
        rootType: String,
        isGeneric: Bool,
        name: String,
        type: String
    ) -> String {
        if isGeneric {
            // Swift does not support static stored properties in generic
            // types, so the lens is computed on demand instead.
            return """
            \(access)static var \(name): LensType.LensValue<\(rootType), \(type)> {
                LensType.LensValue(
                    get: {
                        $0.\(name)
                    },
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
            get: {
                $0.\(name)
            },
            set: { (newValue, whole) in
                var copy = whole
                copy.\(name) = newValue
                return copy
            }
        )
        """
    }

    /// A lens for a stored `let` property. Key paths are not writable for
    /// constants, so the setter rebuilds the value through the memberwise
    /// initializer.
    private static func rebuildLensDeclaration(
        access: String,
        rootType: String,
        isGeneric: Bool,
        name: String,
        type: String,
        arguments: [String]
    ) -> String {
        if isGeneric {
            return """
            \(access)static var \(name): LensType.LensValue<\(rootType), \(type)> {
                LensType.LensValue(
                    get: {
                        $0.\(name)
                    },
                    set: { (newValue, whole) in
                        \(rootType)(
                            \(arguments.joined(separator: ",\n                "))
                        )
                    }
                )
            }
            """
        }
        return """
        \(access)static let \(name): LensType.LensValue<\(rootType), \(type)> = LensType.LensValue(
            get: {
                $0.\(name)
            },
            set: { (newValue, whole) in
                \(rootType)(
                    \(arguments.joined(separator: ",\n            "))
                )
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

    // MARK: - Helpers

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
