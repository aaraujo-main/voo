# Vanilla Tcl Object Orientation (voo) package
namespace eval voo {
    # package version
    variable version 1.0.1

    ##\brief Check if a namespace is a valid voo class
    # \param[in] namespaceName the namespace to check
    # \return 1 if valid voo class, 0 otherwise
    proc isVooClass {namespaceName} {
        if {![uplevel [list namespace exists $namespaceName]]} {
            return 0
        }
        return [expr {[uplevel [list namespace eval $namespaceName {
            info exists __defaultObj
        }]]}]
    }

    ##\brief Declare a new voo class namespace and process its class body
    # \param[in] args Arguments for class declaration: <className> <body> and optional -extends parent, -virtual, -overwrite
    # \note Creates the class namespace, imports parent fields/methods when using -extends,
    #       and registers constructors and exports
    proc class {args} {
        set optDict {}
        set defaultArgs {}
        set numArgs [llength $args]
        for {set i 0} {$i < $numArgs} {incr i} {
            set arg [lindex $args $i]
            if {$arg eq "-extends"} {
                if {$i + 1 >= $numArgs} {
                    error "Constructor option '$arg' requires an argument"
                }
                dict set optDict $arg [lindex $args [incr i]]
            } elseif {$arg eq "-virtual" || $arg eq "-v"} {
                dict set optDict "-virtual" {}
            } elseif {$arg eq "-overwrite"} {
                dict set optDict "-overwrite" {}
            } else {
                lappend defaultArgs $arg
            }
        }
        lassign $defaultArgs className body

        set classExists [uplevel [list namespace exists $className]]
        if {$classExists} {
            if {![dict exists $optDict -overwrite]} {
                error "Class/Namespace '$className' already exists. Use -overwrite to replace it."
            }
            uplevel [list namespace delete $className]
        }

        set vooNs [namespace current]
        # create the namespace for the class
        uplevel [list namespace eval $className [subst -nocommands {
            namespace path [list $vooNs]
            variable __defaultObj {}
            variable __fields {}
            variable __tmp_isPublicEnabled 1
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
        }]

        if {[dict exists $optDict -virtual] && [dict exists $optDict -extends]} {
            error "voo::class: cannot use -virtual with -extends; child classes inherit virtual automatically from a -virtual parent"
        }

        if {[dict exists $optDict -virtual]} {
            set normalizedClassName [uplevel [list namespace eval $className {namespace current}]]
            uplevel [list namespace eval $className [list variable __voo_is_virtual_class 1]]
            uplevel [list namespace eval $className [list variable __voo_class_namespace $normalizedClassName]]
            # Pre-populate __defaultObj with namespace tag at index 0 BEFORE field declarations
            # so that _getClassCurrNumFields returns 1 for the first field declared
            uplevel [list namespace eval $className [list set __defaultObj [list $normalizedClassName]]]
        }

        # variable __parentClassNamespace {}
        if {[dict exists $optDict -extends]} {
            set parentClassName [dict get $optDict -extends]

            if {![uplevel [list namespace exists $parentClassName]]} {
                error "Parent class '$parentClassName' does not exist."
            }

            # check if parent class exists
            if {![uplevel [list namespace eval $parentClassName {info exists __defaultObj}]]} {
                error "Parent class '$parentClassName' is not a valid voo class."
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
            uplevel [list namespace eval $className [list set __defaultObj $parentDefaultObj]]

            # if parent is virtual, update namespace tag at index 0 to child's namespace
            set parentIsVirtual [uplevel [list namespace eval $parentClassName {info exists __voo_is_virtual_class}]]
            if {$parentIsVirtual} {
                set normalizedChildName [uplevel [list namespace eval $className {namespace current}]]
                uplevel [list namespace eval $className \
                    [list set __defaultObj [lreplace $parentDefaultObj 0 0 $normalizedChildName]]]
                uplevel [list namespace eval $className [list variable __voo_is_virtual_class 1]]
                uplevel [list namespace eval $className [list variable __voo_class_namespace $normalizedChildName]]
            }

            # import parent's field index variables by copying actual index values from parent
            set parentFields [${parentClassName}::class.fields]
            foreach field $parentFields {
                set fieldIdx [uplevel [list namespace eval $parentClassName [list set $field]]]
                uplevel [list namespace eval $className [list variable $field $fieldIdx]]
                uplevel [list namespace eval $className [list lappend __fields $field]]
            }

            # import parent's acessors in child class with namespace import
            uplevel [list namespace eval $className [subst -nocommands {
                namespace import ${parentClassName}::get.*
                namespace import ${parentClassName}::set.*
                namespace import ${parentClassName}::update.*
            }]]
        }

        uplevel [list namespace eval $className $body]

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
            unset __tmp_isPublicEnabled
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
    proc _getClassCurrNumFields {} {
        return [uplevel 2 {llength $__defaultObj}]
    }

    ##\brief Check whether public mode is enabled during class body parsing
    # \return 1 if public mode is enabled, 0 otherwise
    proc _getClassIsPublicEnabled {} {
        return [uplevel 2 {set __tmp_isPublicEnabled}]
    }

    ##\brief Declare getter/setter/updater accessors for a class field
    # \param[in] fieldName name of the field
    # \param[in] isPublic boolean whether accessors are public
    # \param[in] isStatic boolean whether field is static (class-level)
    proc _declareFieldAcessors {fieldName isPublic isStatic} {
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
            uplevel 2 [list proc $getterName {} [subst -nocommands {
                variable $fieldName
                return $$fieldName
            }]]

            uplevel 2 [list proc $setterName {value} [subst -nocommands {
                variable $fieldName
                set $fieldName "\$value"
            }]]

            uplevel 2 [list proc $updaterName {tempVar body} [subst -nocommands {
                variable $fieldName
                upvar "\$tempVar" temp
                set temp $$fieldName
                # break link with class variable to avoid copy-on-write
                set $fieldName {}
                try {
                    uplevel \$body
                } finally {
                    set $fieldName "\$temp"
                }
            }]]
        } else {
            uplevel 2 [list getter $getterName $fieldName]
            uplevel 2 [list setter $setterName $fieldName]
            uplevel 2 [list updater $updaterName $fieldName]
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
    # \return Raises an error if the field already exists
    # \note Uses __fields for instance fields and fully-qualified namespace lookup for static
    #       fields to avoid false positives from global variables with the same name
    proc _validateFieldDoesNotExist {fieldName} {
        # Check instance fields tracked in __fields (class-scoped, no global bleed)
        if {$fieldName in [uplevel 2 {set __fields}]} {
            error "Field name '$fieldName' already exists in the class."
        }
        # Check static fields via fully-qualified namespace variable; info exists ::Ns::var
        # only matches that exact namespace variable, never a same-named global
        set classNs [uplevel 2 {namespace current}]
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

        if {[llength $defaultArgs] == 2} {
            lassign $defaultArgs name initVal
        } else {
            lassign $defaultArgs name
            set initVal [_getDefaultValueByType $type]
        }

        _validateFieldName $name
        _validateFieldDoesNotExist $name
        _validateVarValueByType $type $initVal

        if {[dict exists $optDict -static]} {
            # static field
            uplevel [list variable $name $initVal]
        } else {
            set currNumFields [_getClassCurrNumFields]
            uplevel [list variable $name $currNumFields]
            uplevel [list lappend __defaultObj $initVal]
            uplevel [list lappend __fields $name]
        }

        set isPublicEnabled [_getClassIsPublicEnabled]
        _declareFieldAcessors $name $isPublicEnabled [dict exists $optDict -static]
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
        uplevel {variable __tmp_isPublicEnabled 0}
        try {
            uplevel $body
        } finally {
            uplevel {variable __tmp_isPublicEnabled 1}
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
    proc _buildConstructorParams {} {
        set argList [uplevel 2 {set __fields}]
        set isVirtual [uplevel 2 {info exists __voo_is_virtual_class}]
        set spacedArgVarListStr {}
        foreach arg $argList {
            append spacedArgVarListStr "\$$arg "
        }
        if {$isVirtual} {
            # Read the normalized class namespace at definition time so subst embeds it
            # as a literal in the generated body - no runtime variable lookup required.
            set classNs [uplevel 2 {set __voo_class_namespace}]
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
                lassign [_buildConstructorParams] argList body
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
    proc getter {methodName fieldName} {
        # implementation of getter definition
        set fieldIdx [uplevel [list set $fieldName]]
        uplevel [subst -nocommands {
            ##\\brief Getter for $fieldName
            # \\param\[in\] this class instance
            # \\return $fieldName value
            proc $methodName {this} {
                return [lindex \$this $fieldIdx]
            }
        }]
        return
    }

    ##\brief Generate a setter procedure for a field
    # \param[in] methodName name of the generated setter (may include namespace prefix)
    # \param[in] fieldName name of the field to write
    proc setter {methodName fieldName} {
        # implementation of setter definition
        set fieldIdx [uplevel [list set $fieldName]]
        uplevel [subst -nocommands {
            ##\\brief Setter for $fieldName
            # \\param\[in\] thisVar name of variable containing class instance
            # \\param\[in\] value new value for $fieldName
            proc $methodName {thisVar value} {
                upvar \$thisVar this
                lset this $fieldIdx \$value
            }
        }]
        return
    }

    ##\brief Generate an updater procedure for a field (copy-on-write safe)
    # \param[in] methodName name of the generated updater (may include namespace prefix)
    # \param[in] fieldName name of the field to update by reference
    # \note The updater detaches the field to avoid unnecessary copying during updates
    proc updater {methodName fieldName} {
        # implementation of updater definition
        set fieldIdx [uplevel [list set $fieldName]]
        uplevel [subst -nocommands {
            ##\\brief Update $fieldName by reference
            # \\param\[in\] thisVar name of variable containing class instance
            # \\param\[out\] tempVar name of variable to hold $fieldName during update
            # \\param\[in\] body script to execute with $fieldName in tempVar
            # \\note Avoids copy-on-write by detaching field during update
            proc $methodName {thisVar tempVar body} {
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
            }
        }]
    }

    ##\brief Declare a method in the current class namespace
    # \param[in] args Method declaration arguments: name, argList, body and options (-static, -upvar, -update, -override)
    proc method {args} {
        set isPublicEnabled [_getClassIsPublicEnabled]
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

        set className [uplevel {namespace current}]
        
        if {[dict exists $optDict -update]} {
            set updateFields [dict get $optDict -update]
            if {[llength $updateFields] == 0} {
                error "-update option requires at least one field name"
            }
            foreach field $updateFields {
                try {
                  set fieldIdx [uplevel [list set $field]]
                } trap {} {} {
                    error "Field '$field' specified in -update option does not exist in class '$className'"
                }
                append finalBody [subst -nocommands {
                    set $field [lindex \$this $fieldIdx]
                    lset this $fieldIdx {}
                }]
            }
            append finalBody {
                set __voo_update_active__internal 1
            }
            append finalBody "try \{"
        }
        append finalBody $body

        if {[dict exists $optDict -update]} {
            append finalBody "\} finally \{"
            foreach field $updateFields {
                set fieldIdx [uplevel [list set $field]]
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
            set parentNs [uplevel {set __parentClassNamespace}]
            if {[info commands "${parentNs}::$name"] eq ""} {
                error "Method '$name' does not override any method in parent class '$parentNs'"
            }
            # If parent's method is virtual (has base.<name>), auto-promote this override
            # to a dispatcher so that deep inheritance dispatch works correctly
            if {[uplevel {info exists __voo_is_virtual_class}] && \
                    [info commands "${parentNs}::base.$name"] ne ""} {
                dict set optDict -virtual {}
            }
        }

        if {[dict exists $optDict -virtual]} {
            if {![uplevel {info exists __voo_is_virtual_class}]} {
                error "Method '$name' is declared -virtual but '[uplevel {namespace current}]' is not a virtual class"
            }
            if {[dict exists $optDict -static]} {
                error "Method '$name' cannot combine -virtual with -static"
            }
            # Register base.<name> with the original body for direct parent calls from subclasses.
            # For -update methods, make base.<name> borrow parent detached field locals when called
            # from inside another -update frame (e.g., Child::method -> Parent::base.method).
            set baseBody $finalBody
            if {[dict exists $optDict -update]} {
                set baseBody {}
                append baseBody {
                    upvar $thisVar this
                }
                set updateFieldNum 0
                foreach field $updateFields {
                    set fieldIdx [uplevel [list set $field]]
                    append baseBody [subst -nocommands {
                        set __voo_borrow__$updateFieldNum 0
                        if {[uplevel 1 {info exists __voo_update_active__internal}] && [uplevel 1 [list info exists $field]]} {
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
                    set fieldIdx [uplevel [list set $field]]
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
            # Build dispatch body: route to concrete class implementation at runtime.
            # Use tailcall so -upvar methods bind to the caller frame (not this dispatcher frame).
            if {[dict exists $optDict -upvar]} {
                set dispatchBody "upvar \$thisVar this\n"
                set thisDispatchArg "\$thisVar"
            } else {
                set dispatchBody {}
                set thisDispatchArg "\$this"
            }
            append dispatchBody "set __voo_cls \[lindex \$this 0\]\n"
            append dispatchBody "if \{\$__voo_cls ne \[namespace current\] && \[info commands \${__voo_cls}::$name\] ne {}\} \{\n"
            append dispatchBody "    tailcall \${__voo_cls}::$name $thisDispatchArg"
            foreach arg $argList {
                append dispatchBody " \$$arg"
            }
            append dispatchBody "\n\}\n"
            append dispatchBody "tailcall base.$name $thisDispatchArg"
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
        set parentNs [uplevel {set __parentClassNamespace}]

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
