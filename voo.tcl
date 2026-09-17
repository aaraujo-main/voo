# Vanilla Tcl Object Orientation (voo) package
namespace eval voo {
    # package version
    variable version 1.1.0
    # Jim Tcl lacks namespace exists; detect once during package loading so hot
    # accessor calls never branch on interpreter type.
    variable useQualifiedStaticVars [catch {namespace exists ::voo}]

    ##\brief Check if a namespace is a valid voo class
    # \param[in] namespaceName the namespace to check
    # \return 1 if valid voo class, 0 otherwise
    proc isVooClass {namespaceName} {
        return [uplevel [list info exists ${namespaceName}::__defaultObj]]
    }

    ##\brief Declare a new voo class namespace and process its class body
    # \param[in] args Arguments for class declaration: <className> <body> and optional -extends parent, -virtual, -overwrite
    # \note Creates the class namespace, imports parent fields/methods when using -extends,
    #       and registers constructors and exports
    proc class {args} {
        set optDict {}
        set defaultArgs {}
        set layout list
        set numArgs [llength $args]
        for {set i 0} {$i < $numArgs} {incr i} {
            set arg [lindex $args $i]
            if {$arg eq "-extends"} {
                if {$i + 1 >= $numArgs} {
                    error "Constructor option '$arg' requires an argument"
                }
                dict set optDict $arg [lindex $args [incr i]]
            } elseif {$arg eq "-layout"} {
                if {[dict exists $optDict $arg]} {
                    error "Class option '$arg' may not be specified more than once"
                }
                if {$i + 1 >= $numArgs} {
                    error "Class option '$arg' requires an argument"
                }
                set layout [lindex $args [incr i]]
                if {$layout ne "list" && $layout ne "fieldpack"} {
                    error "Class option '$arg' expected list or fieldpack, got '$layout'"
                }
                dict set optDict $arg $layout
            } elseif {$arg eq "-virtual" || $arg eq "-v"} {
                dict set optDict "-virtual" {}
            } elseif {$arg eq "-overwrite"} {
                dict set optDict "-overwrite" {}
            } else {
                lappend defaultArgs $arg
            }
        }
        lassign $defaultArgs className body

        if {$layout eq "fieldpack"} {
            if {[catch {package require fieldpack 1.0} error]} {
                error "voo::class: -layout fieldpack requires FieldPack 1.0: $error"
            }
        }

        if {[dict exists $optDict -extends]} {
            set parentClassName [dict get $optDict -extends]
            if {![uplevel [list info exists ${parentClassName}::__defaultObj]]} {
                error "Parent class '$parentClassName' does not exist."
            }
            if {[${parentClassName}::class.layout] ne $layout} {
                error "voo::class: parent uses layout [${parentClassName}::class.layout], child uses layout $layout"
            }
        }

        set classExists [uplevel [list info exists ${className}::__defaultObj]]
        if {$classExists} {
            if {![dict exists $optDict -overwrite]} {
                error "Class/Namespace '$className' already exists. Use -overwrite to replace it."
            }
            uplevel [list namespace delete $className]
        }

        set vooNs [namespace current]
        # create the namespace for the class
        uplevel [list namespace eval $className [subst -nocommands {
            namespace import ${vooNs}::*
            variable __defaultObj {}
            variable __fields {}
            variable __voo_field_types {}
            variable __voo_field_defaults {}
            variable __voo_own_field_types {}
            variable __voo_own_field_defaults {}
            variable __voo_fieldTypeMap {}
            variable __voo_layout $layout
            variable __voo_isPublicEnabled 1
        }]]

        uplevel [list namespace eval $className {
            ##\brief Access default object for this class
            # \return Default class instance (list)
            # \note Used for inheritance and constructor defaults
            proc class.defaultObj {} {
                variable __defaultObj
                return $__defaultObj
            }
            
            ##\brief Get list of field names for this class
            # \return List of field names in declaration order
            # \note Useful for introspection and constructor -name new.args
            proc class.fields {} {
                variable __fields
                return $__fields
            }

            ##\brief Get storage layout for this class
            # \return list or fieldpack
            proc class.layout {} {
                variable __voo_layout
                return $__voo_layout
            }

            proc class.my.ownFieldTypes {} {
                variable __voo_own_field_types
                return $__voo_own_field_types
            }

            proc class.my.ownFieldDefaults {} {
                variable __voo_own_field_defaults
                return $__voo_own_field_defaults
            }

            proc class.my.fieldTypeMap {} {
                variable __voo_fieldTypeMap
                return $__voo_fieldTypeMap
            }

            proc class.fieldType {fieldName} {
                variable __voo_fieldTypeMap
                if {![dict exists $__voo_fieldTypeMap $fieldName]} {
                    error "Unknown field '$fieldName'"
                }
                return [dict get $__voo_fieldTypeMap $fieldName]
            }

            proc class.my.schemaId {} {
                variable __voo_schema_id
                return $__voo_schema_id
            }
        }]

        if {[dict exists $optDict -virtual] && [dict exists $optDict -extends]} {
            error "voo::class: cannot use -virtual with -extends; child classes inherit virtual automatically from a -virtual parent"
        }

        if {[dict exists $optDict -virtual] || $layout eq "fieldpack"} {
            set normalizedClassName [uplevel [list namespace eval $className {namespace current}]]
            uplevel [list namespace eval $className [list variable __voo_is_virtual_class 1]]
            uplevel [list namespace eval $className [list variable __voo_class_namespace $normalizedClassName]]
            if {$layout eq "list"} {
                # Pre-populate __defaultObj with namespace tag at index 0 BEFORE field declarations
                # so that _getClassCurrNumFields returns 1 for the first field declared
                uplevel [list set ${normalizedClassName}::__defaultObj [list $normalizedClassName]]
            }
        }

        # variable __parentClassNamespace {}
        if {[dict exists $optDict -extends]} {
            set parentClassName [dict get $optDict -extends]

            if {![uplevel [list info exists ${parentClassName}::__defaultObj]]} {
                error "Parent class '$parentClassName' does not exist."
            }

            # normalize namespace name of parent class
            set parentClassName [uplevel [list namespace eval $parentClassName {
                namespace current
            }]]

            uplevel [list namespace eval $className [subst -nocommands {
                variable __parentClassNamespace $parentClassName
            }]]

            # import parent's default object values
            set parentDefaultObj [${parentClassName}::class.defaultObj]
            set normalizedChildName [uplevel [list namespace eval $className {namespace current}]]
            if {$layout eq "list"} {
                uplevel [list set ${normalizedChildName}::__defaultObj $parentDefaultObj]
            }

            if {$layout eq "fieldpack"} {
                uplevel [list set ${normalizedChildName}::__voo_field_types [set ${parentClassName}::__voo_field_types]]
                uplevel [list set ${normalizedChildName}::__voo_field_defaults [set ${parentClassName}::__voo_field_defaults]]
            }

            uplevel [list set ${normalizedChildName}::__voo_fieldTypeMap [${parentClassName}::class.my.fieldTypeMap]]

            # if parent is virtual, update namespace tag at index 0 to child's namespace
            set parentIsVirtual [uplevel [list info exists ${parentClassName}::__voo_is_virtual_class]]
            if {$parentIsVirtual && $layout eq "list"} {
                uplevel [list set ${normalizedChildName}::__defaultObj [lreplace $parentDefaultObj 0 0 $normalizedChildName]]
                uplevel [list namespace eval $className [list variable __voo_is_virtual_class 1]]
                uplevel [list namespace eval $className [list variable __voo_class_namespace $normalizedChildName]]
            } elseif {$parentIsVirtual} {
                uplevel [list namespace eval $className [list variable __voo_is_virtual_class 1]]
                uplevel [list namespace eval $className [list variable __voo_class_namespace $normalizedChildName]]
            }

            # import parent's field index variables by copying actual index values from parent
            set parentFields [${parentClassName}::class.fields]
            foreach field $parentFields {
                set fieldIdx [set ${parentClassName}::$field]
                uplevel [list namespace eval $className [list variable $field $fieldIdx]]
                uplevel [list lappend ${className}::__fields $field]
            }

            # import parent's acessors in child class with namespace import
            uplevel [list namespace eval $className [subst -nocommands {
                namespace import ${parentClassName}::get.*
                namespace import ${parentClassName}::set.*
                namespace import ${parentClassName}::update.*
            }]]
        }

        uplevel [list namespace eval $className $body]

        if {$layout eq "fieldpack"} {
            set normalizedClassName [uplevel [list namespace eval $className {namespace current}]]
            set fieldpackTypes [uplevel [list set ${normalizedClassName}::__voo_field_types]]
            if {[dict exists $optDict -extends]} {
                set parentSchemaId [${parentClassName}::class.my.schemaId]
                set ownTypes [uplevel [list set ${normalizedClassName}::__voo_own_field_types]]
                set schemaId [fieldpack::schema::derive \
                    $normalizedClassName $parentSchemaId $ownTypes 1 reuse-equivalent]
            } else {
                set schemaId [fieldpack::schema::register \
                    $normalizedClassName $fieldpackTypes 1 reuse-equivalent]
            }
            set object [fieldpack::new $schemaId]
            set fieldDefaults [uplevel [list set ${normalizedClassName}::__voo_field_defaults]]
            for {set fieldIdx 0} {$fieldIdx < [llength $fieldDefaults]} {incr fieldIdx} {
                set fieldDefault [lindex $fieldDefaults $fieldIdx]
                fieldpack::set object $fieldIdx $fieldDefault
            }
            uplevel [list set ${normalizedClassName}::__defaultObj $object]
            uplevel [list variable ${normalizedClassName}::__voo_schema_id $schemaId]
        }

        uplevel [list namespace eval $className {
            if {[info commands new] eq ""} {
                constructor
            }
            if {[info commands new()] eq ""} {
                constructor -noargs [_buildConstructorNoArgsBody]
            }
            if {[info commands new.args] eq ""} {
                constructor -name new.args {args} [_buildConstructorArgsBody]
            }
        }]

        uplevel [list namespace eval $className {
            # export class methods
            namespace export *
        }]

        uplevel [list namespace eval $className {
            # clean temporary variable
            unset [namespace current]::__voo_isPublicEnabled
        }]
        return
    }

    ##\brief Return the default value for a given field type
    # \param[in] type the field type token (double,int,bool,...)
    # \return The default value appropriate for the type
    proc _getDefaultValueByType {type} {
        switch -- $type {
            double { return 0.0 }
            int    { return 0 }
            bool   { return 0 }
            default { return {} }
        }
    }

    ##\brief Get the current number of fields declared in the current class
    # \return Number of fields (integer)
    proc _getClassCurrNumFields {defaultObj} {
        return [llength $defaultObj]
    }

    ##\brief Check whether public mode is enabled during class body parsing
    # \return 1 if public mode is enabled, 0 otherwise
    proc _getClassIsPublicEnabled {isPublicEnabled} {
        return $isPublicEnabled
    }

    ##\brief Declare getter/setter/updater accessors for a class field
    # \param[in] fieldName name of the field
    # \param[in] isPublic boolean whether accessors are public
    # \param[in] isStatic boolean whether field is static (class-level)
    proc _declareFieldAcessors {fieldName isPublic isStatic classNs fieldIdx} {
        set prefix {}

        if {$isStatic} {
            append prefix class.
        }
        if {!$isPublic} {
            append prefix my.
        }

        set getterName "${prefix}get.$fieldName"
        set setterName "${prefix}set.$fieldName"
        set updaterName "${prefix}update.$fieldName"

        if {$isStatic} {
            variable useQualifiedStaticVars
            if {$useQualifiedStaticVars} {
                # Jim Tcl needs qualified namespace-variable access in generated code.
                proc ${classNs}::$getterName {} [subst -nocommands {
                    return [set ${classNs}::$fieldName]
                }]

                proc ${classNs}::$setterName {value} [subst -nocommands {
                    set ${classNs}::$fieldName "\$value"
                }]

                proc ${classNs}::$updaterName {tempVar body} [subst -nocommands {
                    upvar "\$tempVar" temp
                    set temp [set ${classNs}::$fieldName]
                    set ${classNs}::$fieldName {}
                    try {
                        uplevel \$body
                    } finally {
                        set ${classNs}::$fieldName "\$temp"
                        set temp {}
                    }
                }]
            } else {
                # Tcl variable links avoid repeated qualified lookups for static fields.
                proc ${classNs}::$getterName {} [subst -nocommands {
                    variable $fieldName
                    return $$fieldName
                }]

                proc ${classNs}::$setterName {value} [subst -nocommands {
                    variable $fieldName
                    set $fieldName "\$value"
                }]

                proc ${classNs}::$updaterName {tempVar body} [subst -nocommands {
                    variable $fieldName
                    upvar "\$tempVar" temp
                    set temp $$fieldName
                    set $fieldName {}
                    try {
                        uplevel \$body
                    } finally {
                        set $fieldName "\$temp"
                        set temp {}
                    }
                }]
            }
        } else {
            getter $getterName $fieldName $classNs $fieldIdx
            setter $setterName $fieldName $classNs $fieldIdx
            updater $updaterName $fieldName $classNs $fieldIdx
        }
        return
    }
    
    ##\brief Validate a field name for illegal characters
    # \param[in] fieldName the field name to validate
    # \return Raises an error if invalid
    proc _validateFieldName {fieldName} {
        if {[string first "." $fieldName] != -1 || [string first "::" $fieldName] != -1} {
            error "Field name '$fieldName' cannot contain '.' or '::' substrings."
        }
    }

    ##\brief Ensure a field name does not already exist in the class
    # \param[in] fieldName the field name to check
    # \param[in] fields the list of instance fields in the class
    # \param[in] classNs the namespace of the class for static field checks
    # \return Raises an error if the field already exists
    # \note Uses __fields for instance fields and fully-qualified namespace lookup for static
    #       fields to avoid false positives from global variables with the same name
    proc _validateFieldDoesNotExist {fieldName fields classNs} {
        # Check instance fields tracked in __fields (class-scoped, no global bleed)
        if {$fieldName in $fields} {
            error "Field name '$fieldName' already exists in the class."
        }
        # Check static fields via fully-qualified namespace variable; info exists ::Ns::var
        # only matches that exact namespace variable, never a same-named global
        if {[info exists ${classNs}::$fieldName]} {
            error "Field name '$fieldName' already exists in the class."
        }
    }

    ##\brief Validate a variable initial value according to its declared type
    # \param[in] type the declared type (double,int,bool,list,dict)
    # \param[in] value the value to validate
    # \return Raises an error if the value does not match the type
    proc _validateVarValueByType {type value} {
        switch -- $type {
            double {
                if {[string is double -strict $value] == 0} {
                    error "Value for t_double must be a double, got '$value'"
                }
            }
            int {
                if {[string is integer -strict $value] == 0} {
                    error "Value for t_int must be an integer, got '$value'"
                }
            }
            bool {
                if {[string is boolean -strict $value] == 0} {
                    error "Value for t_bool must be a boolean, got '$value'"
                }
            }
            list {
                if {[catch {llength $value}]} {
                    error "Value for t_list must be a list, got '$value'"
                }
            }
            dict {
                if {[catch {dict size $value}]} {
                    error "Value for t_dict must be a dict, got '$value'"
                }
            }
        }
    }

    ##\brief Declare a field variable inside the class body
    # \param[in] type the field type token (double,int,string,bool,list,dict,obj)
    # \param[in] argList arguments: ?-static? <name> ?<initialValue>?
    proc _var {type argList} {
        set defaultArgs {}
        set optDict {}
        set numArgs [llength $argList]
        for {set i 0} {$i < $numArgs} {incr i} {
            set arg [lindex $argList $i]
            if {$arg eq "-static"} {
                dict set optDict $arg {}
            } else {
                lappend defaultArgs $arg
            }
        }

        if {[llength $defaultArgs] == 0} {
            error "Variable definition requires: ?<option>? <name> ?<initialValue>?"
        }

        if {$type eq "class"} {
            set nestedKind slice
            if {[lindex $defaultArgs 0] eq "-slice" || [lindex $defaultArgs 0] eq "-pack"} {
                set nestedKind [string range [lindex $defaultArgs 0] 1 end]
                set defaultArgs [lrange $defaultArgs 1 end]
            }
            if {[llength $defaultArgs] < 2 || [llength $defaultArgs] > 3} {
                error "class_t requires: ?-slice|-pack? <class> <name> ?<initialValue>?"
            }
            set nestedClass [lindex $defaultArgs 0]
            set name [lindex $defaultArgs 1]
            if {![string match ::* $nestedClass]} {
                error "class_t requires global class name starting with ::, got '$nestedClass'"
            }
            if {![uplevel [list info exists ${nestedClass}::__defaultObj]]} {
                error "Nested class '$nestedClass' does not exist"
            }
            if {[llength $defaultArgs] == 3} {
                set initVal [lindex $defaultArgs 2]
            } else {
                set initVal [${nestedClass}::new()]
            }
        } elseif {[llength $defaultArgs] == 2} {
            lassign $defaultArgs name initVal
        } else {
            lassign $defaultArgs name
            set initVal [_getDefaultValueByType $type]
        }

        if {$type eq "slice" || $type eq "pack"} {
            if {[llength $defaultArgs] < 2 || [llength $defaultArgs] > 3} {
                error "Nested FieldPack variable definition requires: <name> <schema> ?<initialValue>?"
            }
            lassign $defaultArgs name nestedSchema
            if {[llength $defaultArgs] == 3} {
                set initVal [lindex $defaultArgs 2]
            } else {
                set initVal {}
            }
        }


        set classNs [uplevel {namespace current}]
        set fields [uplevel [list set ${classNs}::__fields]]
        set defaultObj [uplevel [list set ${classNs}::__defaultObj]]

        _validateFieldName $name
        _validateFieldDoesNotExist $name $fields $classNs
        if {$type ne "slice" && $type ne "pack" && $type ne "class"} {
            _validateVarValueByType $type $initVal
        }

        set layout [uplevel [list set ${classNs}::__voo_layout]]
        set fieldIdx {}
        if {[dict exists $optDict -static]} {
            # static field
            uplevel [list variable $name $initVal]
        } else {
            if {$layout eq "fieldpack"} {
                set currNumFields [llength $fields]
            } else {
                set currNumFields [_getClassCurrNumFields $defaultObj]
            }
            set fieldIdx $currNumFields
            uplevel [list variable $name $currNumFields]
            if {$layout ne "fieldpack"} {
                uplevel [list lappend ${classNs}::__defaultObj $initVal]
            }
            uplevel [list lappend ${classNs}::__fields $name]
            set fieldTypeMapValue $type
            if {$layout eq "fieldpack"} {
                switch -- $type {
                    int - double - bool - string { set fieldpackType $type }
                    list - dict - object { set fieldpackType obj }
                    class {
                        if {[${nestedClass}::class.layout] ne "fieldpack"} {
                            error "FieldPack class_t requires nested class '$nestedClass' to use fieldpack layout"
                        }
                        set fieldpackType [list $nestedKind $nestedClass]
                        set fieldTypeMapValue [list class $nestedClass]
                    }
                    default { error "Unsupported FieldPack field type '$type'" }
                }
                uplevel [list lappend ${classNs}::__voo_field_types $fieldpackType]
                uplevel [list lappend ${classNs}::__voo_field_defaults $initVal]
                uplevel [list lappend ${classNs}::__voo_own_field_types $fieldpackType]
                uplevel [list lappend ${classNs}::__voo_own_field_defaults $initVal]
            }
            if {$type eq "class"} {
                set fieldTypeMapValue [list class $nestedClass]
            }
            uplevel [list dict set ${classNs}::__voo_fieldTypeMap $name $fieldTypeMapValue]
        }

        set isPublicEnabled [_getClassIsPublicEnabled [uplevel [list set ${classNs}::__voo_isPublicEnabled]]]
        _declareFieldAcessors $name $isPublicEnabled [dict exists $optDict -static] $classNs $fieldIdx
        return
    }

    ##\brief Declare a double-typed field
    # \param[in] args same arguments accepted by _var (name and optional initial value)
    proc double_t {args} {
        uplevel [list _var "double" $args]
    }

    ##\brief Declare an integer-typed field
    # \param[in] args same arguments accepted by _var (name and optional initial value)
    proc int_t {args} {
        uplevel [list _var "int" $args]
    }

    ##\brief Declare a string-typed field
    # \param[in] args same arguments accepted by _var (name and optional initial value)
    proc string_t {args} {
        uplevel [list _var "string" $args]
    }

    ##\brief Declare a boolean-typed field
    # \param[in] args same arguments accepted by _var (name and optional initial value)
    proc bool_t {args} {
        uplevel [list _var "bool" $args]
    }
    
    ##\brief Declare a list-typed field
    # \param[in] args same arguments accepted by _var (name and optional initial value)
    proc list_t {args} {
        uplevel [list _var "list" $args]
    }

    ##\brief Declare a dict-typed field
    # \param[in] args same arguments accepted by _var (name and optional initial value)
    proc dict_t {args} {
        uplevel [list _var "dict" $args]
    }

    ##\brief Declare an object-typed field (nested vanilla object)
    # \param[in] args same arguments accepted by _var (name and optional initial value)
    proc obj_t {args} {
        uplevel [list _var "object" $args]
    }

    ##\brief Declare a nested VOO class field
    proc class_t {args} {
        uplevel [list _var "class" $args]
    }

    ##\brief Enable public mode for declarations inside the provided body
    # \param[in] body script to execute with public accessors enabled
    # \return Result of executing body
    proc public {body} {
        uplevel $body
    }

    ##\brief Execute the provided body with private mode enabled (temporarily disables public accessors)
    # \param[in] body script to execute with private accessors
    # \return Result of executing body
    proc private {body} {
        uplevel {variable __voo_isPublicEnabled 0}
        try {
            uplevel $body
        } finally {
            uplevel {variable __voo_isPublicEnabled 1}
        }
    }

    ##\brief Build the body for a no-argument constructor
    # \return A script chunk used as constructor body that returns the class default object
    proc _buildConstructorNoArgsBody {} {
        return {
            variable __defaultObj
            return $__defaultObj;
        }
    }
    
    ##\brief Build the body for a constructor that accepts named args (-field value pairs)
    # \return A script chunk used as constructor body that applies named arguments to the default object
    proc _buildConstructorArgsBody {} {
        return {
            variable __defaultObj
            set obj $__defaultObj
            if {[catch {dict size $args}]} {
                error "Constructor argument must be a list of '-<field> <value>' pairs"
            }
            dict for {key value} $args {
                if {[string index $key 0] ne "-"} {
                    error "Constructor argument keys must start with '-', got '$key'"
                }
                set field [string range $key 1 end]
                set setter set.$field
                if {[info commands $setter] ne ""} {
                    $setter obj $value
                } else {
                    set setter my.set.$field
                    if {[info commands $setter] ne ""} {
                        $setter obj $value
                    } else {
                        error "Unknown field option: $field"
                    }
                }
            }
            return $obj
        }
    }

    ##\brief Build constructor parameter list and body for positional constructors
    # \return A list of two elements: argument names list and a body script that returns them as a list
    # \note For virtual classes, the concrete class namespace is embedded as a literal string at
    #       class-definition time (not looked up at runtime), producing:
    #           return [list ::ClassName $f1 $f2 ...]
    #       This avoids all runtime proc calls (class.defaultObj, set.*) and variable lookups,
    #       making virtual object creation as cheap as non-virtual.
    proc _buildConstructorParams {argList isVirtual classNs} {
        if {$classNs ne {} && [set ${classNs}::__voo_layout] eq "fieldpack"} {
            set body {
                variable __defaultObj
                set object $__defaultObj
            }
            set fieldIdx 0
            foreach arg $argList {
                append body "\nfieldpack::set object $fieldIdx \$$arg"
                incr fieldIdx
            }
            append body "\nreturn \$object"
            return [list $argList $body]
        }
        set spacedArgVarListStr {}
        foreach arg $argList {
            append spacedArgVarListStr "\$$arg "
        }
        if {$isVirtual} {
            # Read the normalized class namespace at definition time so subst embeds it
            # as a literal in the generated body - no runtime variable lookup required.
            set spacedArgVarListStr "{$classNs} $spacedArgVarListStr"
            set body [subst -nocommands {
                return [list $spacedArgVarListStr]
            }]
        } else {
            set body [subst -nocommands {
                return [list $spacedArgVarListStr]
            }]
        }
        return [list $argList $body]
    }

    ##\brief Define a constructor for the current class
    # \param[in] args Constructor declaration options and body
    # \note Supports -name, -noargs and -typed variants
    proc constructor {args} {
        set defaultArgs {}
        set optDict {}
        set numArgs [llength $args]
        for {set i 0} {$i < $numArgs} {incr i} {
            set arg [lindex $args $i]
            if {$arg eq "-name" || $arg eq "-noargs" || $arg eq "-typed"} {
                if {$i + 1 >= $numArgs} {
                    error "Constructor option '$arg' requires an argument"
                }
                dict set optDict $arg [lindex $args [incr i]]
            } else {
                lappend defaultArgs $arg
            }
        }

        # check valid option combinations
        if {[dict exists $optDict -name]} {
            if {[dict exists $optDict -noargs] || [dict exists $optDict -typed]} {
                error "Constructor cannot have -name option with -noargs or -typed options"
            }
        }
        if {[dict exists $optDict -noargs] && [dict exists $optDict -typed]} {
            error "Constructor cannot have both -noargs and -typed options"
        }
        
        if {[dict exists $optDict -name]} {
            set constructorName [dict get $optDict -name]
        } elseif {[dict exists $optDict -noargs]} {
            set constructorName "new()"
        } elseif {[dict exists $optDict -typed]} {
            set constructorName "new([join [dict get $optDict -typed] ,])"
        } else {
            set constructorName "new"
        }

        if {[dict exists $optDict -noargs]} {
            if {[llength $defaultArgs] != 0} {
                error "Invalid constructor definition, expected '?...? ?<body>?' for -noargs"
            }
            set argList {}
            set body [dict get $optDict -noargs]
        } else {
            if {[llength $defaultArgs] == 0} {
                set classNamespace [uplevel {namespace current}]
                set classFields [uplevel [list set ${classNamespace}::__fields]]
                set classIsVirtual [uplevel [list info exists ${classNamespace}::__voo_is_virtual_class]]
                if {$classIsVirtual} {
                    set classNamespace [uplevel [list set ${classNamespace}::__voo_class_namespace]]
                } elseif {[set ${classNamespace}::__voo_layout] eq "list"} {
                    set classNamespace {}
                }
                lassign [_buildConstructorParams $classFields $classIsVirtual $classNamespace] argList body
            } else {
                if {[llength $defaultArgs] != 2} {
                    error "Invalid constructor definition, expected '?...? ?<argList> <body>?'"
                }
                lassign $defaultArgs argList body
            }
        }

        uplevel [list proc $constructorName $argList $body]
        return
    }

    ##\brief Generate a getter procedure for a field
    # \param[in] methodName name of the generated getter (may include namespace prefix)
    # \param[in] fieldName name of the field to read
    proc getter {methodName fieldName {classNs {}} {fieldIdx {}}} {
        # implementation of getter definition
        if {$classNs eq {}} {
            set fieldIdx [uplevel [list set $fieldName]]
            set classNs [uplevel {namespace current}]
        }
        set isFieldpack [expr {[set ${classNs}::__voo_layout] eq "fieldpack"}]
        if {$isFieldpack} {
            set getterBody [subst -nocommands {
                return [fieldpack::get \$this $fieldIdx]
            }]
        } else {
            set getterBody [subst -nocommands {
                return [lindex \$this $fieldIdx]
            }]
        }
        proc ${classNs}::$methodName {this} [subst -nocommands {
            ##\\brief Getter for $fieldName
            # \\param\[in\] this class instance
            # \\return $fieldName value
            $getterBody
        }]
        return
    }

    ##\brief Generate a setter procedure for a field
    # \param[in] methodName name of the generated setter (may include namespace prefix)
    # \param[in] fieldName name of the field to write
    proc setter {methodName fieldName {classNs {}} {fieldIdx {}}} {
        # implementation of setter definition
        if {$classNs eq {}} {
            set fieldIdx [uplevel [list set $fieldName]]
            set classNs [uplevel {namespace current}]
        }
        set isFieldpack [expr {[set ${classNs}::__voo_layout] eq "fieldpack"}]
        if {$isFieldpack} {
            set setterBody [subst -nocommands {
                fieldpack::set this $fieldIdx \$value
            }]
        } else {
            set setterBody [subst -nocommands {
                lset this $fieldIdx \$value
            }]
        }
        proc ${classNs}::$methodName {thisVar value} [subst -nocommands {
            ##\\brief Setter for $fieldName
            # \\param\[in\] thisVar name of variable containing class instance
            # \\param\[in\] value new value for $fieldName
            upvar \$thisVar this
            $setterBody
        }]
        return
    }

    ##\brief Generate an updater procedure for a field (copy-on-write safe)
    # \param[in] methodName name of the generated updater (may include namespace prefix)
    # \param[in] fieldName name of the field to update by reference
    # \note The updater detaches the field to avoid unnecessary copying during updates
    proc updater {methodName fieldName {classNs {}} {fieldIdx {}}} {
        # implementation of updater definition
        if {$classNs eq {}} {
            set fieldIdx [uplevel [list set $fieldName]]
            set classNs [uplevel {namespace current}]
        }
        if {[set ${classNs}::__voo_layout] eq "fieldpack"} {
            proc ${classNs}::$methodName {thisVar tempVar body} [subst -nocommands {
                upvar \$thisVar this
                upvar \$tempVar temp
                fieldpack::update this $fieldIdx temp \$body
            }]
            return
        }
        proc ${classNs}::$methodName {thisVar tempVar body} [subst -nocommands {
            ##\\brief Update $fieldName by reference
            # \\param\[in\] thisVar name of variable containing class instance
            # \\param\[out\] tempVar name of variable to hold $fieldName during update
            # \\param\[in\] body script to execute with $fieldName in tempVar
            # \\note Avoids copy-on-write by detaching field during update
            upvar \$thisVar this
            upvar \$tempVar temp

            set temp [lindex \$this $fieldIdx]
            # break link with object to avoid copy-on-write
            lset this $fieldIdx {}
            try {
                uplevel \$body
            } finally {
                lset this $fieldIdx \$temp
                set temp {}
            }
        }]
    }

    ##\brief Declare a method in the current class namespace
    # \param[in] args Method declaration arguments: name, argList, body and options (-static, -upvar, -update, -override)
    proc method {args} {
        set className [uplevel {namespace current}]
        set isPublicEnabled [_getClassIsPublicEnabled [uplevel [list set ${className}::__voo_isPublicEnabled]]]
        set defaultArgs {}
        set optDict {}
        set numArgs [llength $args]
        for {set i 0} {$i < $numArgs} {incr i} {
            set arg [lindex $args $i]
            if {$arg eq "-static" || $arg eq "-upvar"} {
                dict set optDict $arg {}
            } elseif {$arg eq "-update"} {
                if {$i + 1 >= $numArgs} {
                    error "Method option '$arg' requires an argument"
                }
                dict set optDict $arg [lindex $args [incr i]]
            } elseif {$arg eq "-override"} {
                # Explicit override indicator
                dict set optDict $arg {}
            } elseif {$arg eq "-virtual"} {
                dict set optDict $arg {}
            } else {
                lappend defaultArgs $arg
            }
        }
        lassign $defaultArgs name argList body

        # check valid option combinations
        if {[dict exists $optDict -static]} {
            if {[dict exists $optDict -upvar] || [dict exists $optDict -update]} {
                error "Method cannot have both -static and -upvar or -update options"
            }
        }
        if {[dict exists $optDict -update]} {
            if {![dict exists $optDict -upvar]} {
                # automatically add -upvar if -update is specified
                dict set optDict -upvar {}
            }
        }

        set finalArgList {}
        set finalBody {}
        if {[dict exists $optDict -upvar]} {
            lappend finalArgList "thisVar" 
            append finalBody {
                upvar $thisVar this
            }
        } elseif {![dict exists $optDict -static]} {
            lappend finalArgList "this"
        }

        lappend finalArgList {*}$argList

        if {[dict exists $optDict -update]} {
            set updateFields [dict get $optDict -update]
            if {[llength $updateFields] == 0} {
                error "-update option requires at least one field name"
            }
            foreach field $updateFields {
                if {[catch {set fieldIdx [set ${className}::$field]}]} {
                    error "Field '$field' specified in -update option does not exist in class '$className'"
                }
            }
        }

        if {[dict exists $optDict -update] && [set ${className}::__voo_layout] eq "fieldpack"} {
            set updateBody $body
            foreach field [lreverse $updateFields] {
                set fieldIdx [set ${className}::$field]
                set updateBody [list fieldpack::update this $fieldIdx $field $updateBody]
            }
            append finalBody $updateBody
        } elseif {[dict exists $optDict -update]} {
            foreach field $updateFields {
                set fieldIdx [set ${className}::$field]
                append finalBody [subst -nocommands {
                    set $field [lindex \$this $fieldIdx]
                    lset this $fieldIdx {}
                }]
            }
            append finalBody {
                set __voo_update_active__internal 1
            }
            append finalBody "try \{"
            append finalBody $body
        } else {
            append finalBody $body
        }

        if {[dict exists $optDict -update] && [set ${className}::__voo_layout] ne "fieldpack"} {
            append finalBody "\} finally \{"
            foreach field $updateFields {
                set fieldIdx [set ${className}::$field]
                append finalBody [subst -nocommands {
                    lset this $fieldIdx \$$field
                }]
            }
            append finalBody {
                unset -nocomplain __voo_update_active__internal
            }
            append finalBody "\}"
        }

        if {!$isPublicEnabled} {
            set name "my.$name"
        }

        if {[dict exists $optDict -override]} {
            set parentNs [set ${className}::__parentClassNamespace]
            if {[info commands "${parentNs}::$name"] eq ""} {
                error "Method '$name' does not override any method in parent class '$parentNs'"
            }
            # If parent's method is virtual (has base.<name>), auto-promote this override
            # to a dispatcher so that deep inheritance dispatch works correctly
            if {[info exists ${className}::__voo_is_virtual_class] && \
                    [info commands "${parentNs}::base.$name"] ne ""} {
                dict set optDict -virtual {}
            }
        }

        if {[dict exists $optDict -virtual]} {
            if {![info exists ${className}::__voo_is_virtual_class]} {
                error "Method '$name' is declared -virtual but '[uplevel {namespace current}]' is not a virtual class"
            }
            if {[dict exists $optDict -static]} {
                error "Method '$name' cannot combine -virtual with -static"
            }
            # Register base.<name> with the original body for direct parent calls from subclasses.
            # For -update methods, make base.<name> borrow parent detached field locals when called
            # from inside another -update frame (e.g., Child::method -> Parent::base.method).
            set implementationBody $finalBody
            set baseBody $finalBody
            if {[dict exists $optDict -override] && [set ${className}::__voo_layout] eq "fieldpack"} {
                if {[dict exists $optDict -upvar]} {
                    set baseBody [format {tailcall %s::base.%s $thisVar} $parentNs $name]
                    foreach arg $argList {
                        append baseBody [format { $%s} $arg]
                    }
                } else {
                    set baseBody [format {tailcall %s::base.%s $this} $parentNs $name]
                    foreach arg $argList {
                        append baseBody [format { $%s} $arg]
                    }
                }
            }
            if {[dict exists $optDict -update] && [set ${className}::__voo_layout] ne "fieldpack"} {
                set baseBody {}
                append baseBody {
                    upvar $thisVar this
                }
                set updateFieldNum 0
                foreach field $updateFields {
                    set fieldIdx [set ${className}::$field]
                    append baseBody [subst -nocommands {
                        set __voo_borrow__$updateFieldNum 0
                        if {[uplevel {info exists __voo_update_active__internal}] && [uplevel [list info exists $field]]} {
                            set __voo_borrow__$updateFieldNum 1
                            upvar 1 $field $field
                        } else {
                            set $field [lindex \$this $fieldIdx]
                            lset this $fieldIdx {}
                        }
                    }]
                    incr updateFieldNum
                }
                append baseBody {
                    set __voo_update_active__internal 1
                }
                append baseBody "try \{"
                append baseBody $body
                append baseBody "\} finally \{"
                set updateFieldNum 0
                foreach field $updateFields {
                    set fieldIdx [set ${className}::$field]
                    append baseBody [subst -nocommands {
                        if {![set __voo_borrow__$updateFieldNum]} {
                            lset this $fieldIdx \$$field
                        }
                    }]
                    incr updateFieldNum
                }
                append baseBody {
                    unset -nocomplain __voo_update_active__internal
                }
                append baseBody "\}"
            }
            uplevel [list proc "base.$name" $finalArgList $baseBody]
            if {[dict exists $optDict -override] && [set ${className}::__voo_layout] eq "fieldpack"} {
                uplevel [list proc "__voo_impl.$name" $finalArgList $implementationBody]
            }
            # Build dispatch body: route to concrete class implementation at runtime.
            # Use tailcall so -upvar methods bind to the caller frame (not this dispatcher frame).
            if {[dict exists $optDict -upvar]} {
                set dispatchBody "upvar \$thisVar this\n"
                set thisDispatchArg "\$thisVar"
            } else {
                set dispatchBody {}
                set thisDispatchArg "\$this"
            }
            if {[set ${className}::__voo_layout] eq "fieldpack"} {
                append dispatchBody "set __voo_cls \[fieldpack::get_schema_name \$this\]\n"
            } else {
                append dispatchBody "set __voo_cls \[lindex \$this 0\]\n"
            }
            append dispatchBody "if \{\$__voo_cls ne \[namespace current\] && \[info commands \${__voo_cls}::$name\] ne {}\} \{\n"
            append dispatchBody "    tailcall \${__voo_cls}::$name $thisDispatchArg"
            foreach arg $argList {
                append dispatchBody " \$$arg"
            }
            append dispatchBody "\n\}\n"
            if {[dict exists $optDict -override] && [set ${className}::__voo_layout] eq "fieldpack"} {
                append dispatchBody "tailcall __voo_impl.$name $thisDispatchArg"
            } else {
                append dispatchBody "tailcall base.$name $thisDispatchArg"
            }
            foreach arg $argList {
                append dispatchBody " \$$arg"
            }
            set finalBody $dispatchBody
        }

        uplevel [list proc $name $finalArgList $finalBody]
        return
    }

    ##\brief Import one or more methods from parent class into the current (child) class namespace.
    # \param[in] methods List of method names (or a single method name) to import from parent.
    # \note Must be called inside a class declared with -extends. Methods are copied at class-definition time.
    proc importMethods {methods} {
        set classNs [uplevel {namespace current}]
        set parentNs [set ${classNs}::__parentClassNamespace]

        # Validate caller context and get parent namespace stored by -extends handling
        if {$parentNs eq ""} {
            error "importMethods can only be used inside a class declared with -extends"
        }

        # Normalize to a list of method names
        if {[string length [string trim $methods]] == 0} {
            return
        }
        if {[catch {llength $methods}]} {
            set methodList [list $methods]
        } else {
            set methodList $methods
        }

        foreach methodName $methodList {
            set fullMethodName "${parentNs}::$methodName"
            # Validate parent method exists
            if {[info commands $fullMethodName] eq ""} {
                error "Method '$methodName' not found in parent class '$parentNs'"
            }

            # Define a copy in the child namespace so unqualified calls resolve to child
            set argList [info args $fullMethodName]
            set body [info body $fullMethodName]
            uplevel [list proc $methodName $argList $body]
        }
        return
    }

    namespace export *
}

# provide the package
package provide voo $voo::version
