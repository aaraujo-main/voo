#!/usr/bin/env tclsh

# Memory benchmark helper for isolated-process measurements.
# Designed to be run as one framework per tclsh process.

proc usage {} {
    puts "Usage: tclsh oo_memory_benchmark.tcl --framework {cpp|voo|tcloo|itcl} ?options?"
    puts ""
    puts "Options:"
    puts "  --count N             Number of objects to create (default: 100000)"
    puts "  --cpp-lib PATH        Path to VOO C++ shared library (required for cpp)"
    puts "  --class-schema NAME   VOO class fixture: point, scalar10, scalar20, or nested (default: point)"
    puts "  --voo-layout NAME     VOO layout: list or fieldpack (default: list)"
    puts "  --voo-package NAME    VOO package name for package require (default: voo)"
    puts "  --fieldpack-package NAME"
    puts "                        FieldPack package name for fieldpack layout (default: fieldpack)"
    puts "  --itcl-package NAME   Itcl package name for package require (default: itcl)"
    puts "  --hold                Wait for Enter before exit (default: on)"
    puts "  --no-hold             Exit immediately after printing stats"
    puts "  --help                Show this help"
}

proc require_package_or_die {name {alt ""}} {
    if {[catch {package require $name}]} {
        if {$alt ne "" && ![catch {package require $alt}]} {
            return
        }
        error "Failed to package require $name"
    }
}

proc shared_library_extension {} {
    # sharedlibextension isn't available in Jim Tcl
    if {![catch {info sharedlibextension} extension]} {
        return $extension
    }
    switch -- $::tcl_platform(platform) {
        windows { return .dll }
        default { return .so }
    }
}

proc current_rss_kb {} {
    set status_file [format "/proc/%d/status" [pid]]
    if {![file exists $status_file]} {
        return "unknown"
    }
    set f [open $status_file r]
    set data [read $f]
    close $f

    foreach line [split $data "\n"] {
        if {[string match "VmRSS:*" $line]} {
            return [lindex $line 1]
        }
    }
    return "unknown"
}

proc validate_voo_layout {layout} {
    if {$layout ni {list fieldpack}} {
        error "Unsupported VOO layout '$layout'; expected list or fieldpack"
    }
    return $layout
}

proc validate_class_schema {class_kind} {
    if {$class_kind ni {point scalar10 scalar20 nested}} {
        error "Unsupported VOO class '$class_kind'; expected point, scalar10, scalar20, or nested"
    }
    return $class_kind
}

proc define_voo_point_class {layout} {
    catch {namespace delete ::VooPoint}

    voo::class ::VooPoint -layout $layout {
        public {
            double_t x 0.0
            double_t y 0.0
            string_t name "point"
            int_t id 0
            bool_t active 1
        }

        method distance {} {
            set dx [get.x $this]
            set dy [get.y $this]
            return [expr {sqrt($dx * $dx + $dy * $dy)}]
        }
    }
}

proc define_voo_scalar10_class {layout} {
    catch {namespace delete ::VooScalar}

    voo::class ::VooScalar -layout $layout {
        public {
            int_t int0 0
            double_t double0 0.0
            bool_t bool0 0
            int_t int1 1
            double_t double1 1.0
            bool_t bool1 1
            int_t int2 2
            double_t double2 2.0
            bool_t bool2 0
            int_t int3 3
        }
    }
}

proc define_voo_scalar_class {layout} {
    catch {namespace delete ::VooScalar}

    voo::class ::VooScalar -layout $layout {
        public {
            int_t int0 0
            double_t double0 0.0
            bool_t bool0 0
            int_t int1 1
            double_t double1 1.0
            bool_t bool1 1
            int_t int2 2
            double_t double2 2.0
            bool_t bool2 0
            int_t int3 3
            double_t double3 3.0
            bool_t bool3 1
            int_t int4 4
            double_t double4 4.0
            bool_t bool4 0
            int_t int5 5
            double_t double5 5.0
            bool_t bool5 1
            int_t int6 6
            double_t double6 6.0
            bool_t bool6 0
            int_t int7 7
            double_t double7 7.0
            bool_t bool7 1
        }
    }
}

proc define_voo_nested_classes {layout} {
    foreach class_name {VooNestedChild VooNested} {
        catch {namespace delete ::$class_name}
    }

    voo::class ::VooNestedChild -layout $layout {
        public {
            int_t value 0
            double_t weight 0.0
            string_t label child
        }
    }

    voo::class ::VooNested -layout $layout {
        public {
            class_t -slice ::VooNestedChild child0 [::VooNestedChild::new()]
            class_t -slice ::VooNestedChild child1 [::VooNestedChild::new()]
            class_t -slice ::VooNestedChild child2 [::VooNestedChild::new()]
        }
    }
}

proc define_voo_class {layout class_kind} {
    switch -- $class_kind {
        point { define_voo_point_class $layout }
        scalar10 { define_voo_scalar10_class $layout }
        scalar20 { define_voo_scalar_class $layout }
        nested { define_voo_nested_classes $layout }
    }
}

proc new_voo_object {class_kind} {
    switch -- $class_kind {
        point { return [::VooPoint::new 1.0 2.0 "bench" 1 1] }
        scalar10 { return [::VooScalar::new 0 0.0 0 1 1.0 1 2 2.0 0 3] }
        scalar20 { return [::VooScalar::new 0 0.0 0 1 1.0 1 2 2.0 0 3 3.0 1 4 4.0 0 5 5.0 1 6 6.0 0 7 7.0 1] }
        nested {
            set child0 [::VooNestedChild::new 0 0.0 "child0"]
            set child1 [::VooNestedChild::new 1 1.0 "child1"]
            set child2 [::VooNestedChild::new 2 2.0 "child2"]
            return [::VooNested::new $child0 $child1 $child2]
        }
    }
}

proc define_tcloo_point_class {} {
    catch {::TclooPoint destroy}

    oo::class create ::TclooPoint {
        variable x y name id active

        constructor {{x_ 0.0} {y_ 0.0} {name_ "point"} {id_ 0} {active_ 1}} {
            my variable x y name id active
            set x $x_
            set y $y_
            set name $name_
            set id $id_
            set active $active_
        }

        method getX {} {
            my variable x
            return $x
        }

        method setX {value} {
            my variable x
            set x $value
        }
    }
}

proc define_itcl_point_class {} {
    catch {itcl::delete class ::ItclPoint}

    itcl::class ::ItclPoint {
        public variable x 0.0
        public variable y 0.0
        public variable name "point"
        public variable id 0
        public variable active 1

        constructor {{x_ 0.0} {y_ 0.0} {name_ "point"} {id_ 0} {active_ 1}} {
            set x $x_
            set y $y_
            set name $name_
            set id $id_
            set active $active_
        }

        method getX {} { return $x }
        method setX {value} { set x $value }
    }
}

set framework ""
set count 100000
set cpp_lib ""
set class_schema point
set voo_layout list
set voo_package voo
set fieldpack_package fieldpack
set itcl_package itcl
set hold 1
set is_jimtcl [catch {info sharedlibextension}]

set project_root [file join [file dirname [info script]] ..]
if {[lsearch -exact $auto_path $project_root] < 0} {
    lappend auto_path $project_root
}

set i 0
while {$i < [llength $argv]} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --help {
            usage
            exit 0
        }
        --framework {
            incr i
            set framework [lindex $argv $i]
        }
        --count {
            incr i
            set count [lindex $argv $i]
        }
        --cpp-lib {
            incr i
            set cpp_lib [lindex $argv $i]
        }
        --class-schema {
            incr i
            set class_schema [lindex $argv $i]
        }
        --voo-layout {
            incr i
            set voo_layout [lindex $argv $i]
        }
        --voo-package {
            incr i
            set voo_package [lindex $argv $i]
        }
        --fieldpack-package {
            incr i
            set fieldpack_package [lindex $argv $i]
        }
        --itcl-package {
            incr i
            set itcl_package [lindex $argv $i]
        }
        --hold {
            set hold 1
        }
        --no-hold {
            set hold 0
        }
        default {
            error "Unknown argument: $arg"
        }
    }
    incr i
}

if {$framework eq ""} {
    error "--framework is required"
}

validate_voo_layout $voo_layout
validate_class_schema $class_schema

if {$framework in {tcloo itcl} && $class_schema ne "point"} {
    error "--class-schema is only supported with framework voo"
}

if {$framework eq "cpp"} {
    if {$is_jimtcl} {
        error "C++ benchmark library must be built against Jim Tcl for framework cpp"
    }
    if {$cpp_lib eq ""} {
        # Jim Tcl lacks info sharedlibextension; avoid normalizing absent paths.
        set candidates [list \
            [file join [file dirname [info script]] .. .. build-bench benchmark voopoint_cpp_bench[shared_library_extension]] \
            [file join [file dirname [info script]] .. .. build benchmark voopoint_cpp_bench[shared_library_extension]] \
            [file join [file dirname [info script]] .. voopoint_cpp_bench[shared_library_extension]]]
        foreach c $candidates {
            if {[file exists $c]} {
                set cpp_lib $c
                break
            }
        }
    }
    if {$cpp_lib eq "" || ![file exists $cpp_lib]} {
        error "--cpp-lib is required for framework cpp"
    }
    load $cpp_lib Point
}

switch -- $framework {
    voo {
        if {$voo_layout eq "fieldpack"} {
            require_package_or_die $fieldpack_package
        }
        require_package_or_die $voo_package
        define_voo_class $voo_layout $class_schema
        set objects {}
        for {set n 0} {$n < $count} {incr n} {
            lappend objects [new_voo_object $class_schema]
        }
    }
    tcloo {
        package require TclOO
        define_tcloo_point_class
        set objects {}
        for {set n 0} {$n < $count} {incr n} {
            lappend objects [::TclooPoint new 1.0 2.0 "bench" 1 1]
        }
    }
    itcl {
        require_package_or_die $itcl_package Itcl
        define_itcl_point_class
        set objects {}
        for {set n 0} {$n < $count} {incr n} {
            lappend objects [::ItclPoint #auto 1.0 2.0 "bench" 1 1]
        }
    }
    cpp {
        set objects {}
        for {set n 0} {$n < $count} {incr n} {
            lappend objects [::CppVooPoint::new 1.0 2.0 "bench" 1 1]
        }
    }
    default {
        error "Unsupported framework: $framework"
    }
}

puts "framework=$framework"
puts "count=$count"
if {$framework eq "voo"} {
    puts "class_schema=$class_schema"
    puts "voo_layout=$voo_layout"
}
puts "pid=[pid]"
puts "vmrss_kb=[current_rss_kb]"
puts "objects_list_length=[llength $objects]"

if {$hold} {
    puts "Press Enter to exit (use this pause to inspect with htop)."
    flush stdout
    gets stdin
}
