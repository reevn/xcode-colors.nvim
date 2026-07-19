;; extends

(class_declaration
  name: (type_identifier) @type.definition)

(class_declaration
  "extension"
  name: (user_type) @type.definition)

(protocol_declaration
  name: (type_identifier) @type.definition)

(associatedtype_declaration
  name: (type_identifier) @type.definition)

(typealias_declaration
  name: (type_identifier) @type.definition)

(enum_entry
  name: (simple_identifier) @variable.member.definition)

; top-level variables
(source_file
  (property_declaration
    name: (pattern
      bound_identifier: (simple_identifier) @variable.member.definition)))

(parameter
  . (simple_identifier) @variable.member.definition)

(init_declaration
  "init" @keyword.function)
