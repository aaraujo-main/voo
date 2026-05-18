#!/usr/bin/env tclsh

proc usage {} {
    puts "Usage: tclsh oo_time_benchmark.tcl ?options?"
    puts ""
    puts "Options:"
    puts "  --iterations N        Number of timed iterations per benchmark (default: 1000)"
    puts "  --cpp-lib PATH        Path to VOO C++ shared library (Point_Init provider)"
    puts "  --frameworks LIST     Space-separated frameworks among: cpp voo tcloo itcl"
    puts "  --voo-package NAME    VOO package name for package require (default: voo)"
    puts "  --itcl-package NAME   Itcl package name for package require (default: itcl)"
    puts "  --help                Show this help"
}

proc profile {body times} {
    uplevel 1 $body
    return [uplevel 1 [list time $body $times]]
}

proc avg_us {time_result} {
    return [expr {[lindex $time_result 0] + 0.0}]
}

proc fmt_us {value} {
    if {$value eq "N/A"} {
        return $value
    }
    return [format "%.3f" $value]
}

proc require_package_or_die {name {alt ""}} {
    if {[catch {package require $name}]} {
        if {$alt ne "" && ![catch {package require $alt}]} {
            return
        }
        error "Failed to package require $name"
    }
}

proc define_voo_point_class {} {
    catch {rename ::VooPoint {}}
    catch {namespace delete ::VooPoint}

    voo::class ::VooPoint {
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

        method distance {} {
            my variable x y
            return [expr {sqrt($x * $x + $y * $y)}]
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
        method distance {} { return [expr {sqrt($x * $x + $y * $y)}] }
    }
}

namespace eval ::declbench {
    variable voo_counter 0
    variable tcloo_counter 0
    variable itcl_counter 0
}

proc decl_voo_once {} {
    variable ::declbench::voo_counter
    incr ::declbench::voo_counter
    set cls ::VooDecl${::declbench::voo_counter}

    voo::class $cls {
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

proc decl_tcloo_once {} {
    variable ::declbench::tcloo_counter
    incr ::declbench::tcloo_counter
    set cls ::TclooDecl${::declbench::tcloo_counter}

    oo::class create $cls {
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

        method distance {} {
            my variable x y
            return [expr {sqrt($x * $x + $y * $y)}]
        }
    }
}

proc decl_itcl_once {} {
    variable ::declbench::itcl_counter
    incr ::declbench::itcl_counter
    set cls ::ItclDecl${::declbench::itcl_counter}

    itcl::class $cls {
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
        method distance {} { return [expr {sqrt($x * $x + $y * $y)}] }
    }
}

proc benchmark_cpp {iterations cpp_lib} {
    if {$cpp_lib eq ""} {
        error "--cpp-lib is required when benchmarking framework 'cpp'"
    }
    if {![file exists $cpp_lib]} {
        error "C++ benchmark library not found: $cpp_lib"
    }

    if {[catch {load $cpp_lib Point} err]} {
        if {[string first "already loaded" $err] < 0} {
            error "Failed to load C++ benchmark library: $err"
        }
    }

    set result(create_explicit) [avg_us [profile {
        set __obj [::CppVooPoint::new 1.0 2.0 "bench" 1 1]
    } $iterations]]

    set result(create_default) [avg_us [profile {
        set __obj [::CppVooPoint::new()]
    } $iterations]]

    set cpp_obj [::CppVooPoint::new 1.0 2.0 "bench" 1 1]

    set result(setter) [avg_us [profile {
        ::CppVooPoint::set.x cpp_obj 3.14
    } $iterations]]

    set result(getter) [avg_us [profile {
        set __sink [::CppVooPoint::get.x $cpp_obj]
    } $iterations]]

    set result(class_declaration) "N/A"
    return [array get result]
}

proc benchmark_voo {iterations} {
    define_voo_point_class

    set result(create_explicit) [avg_us [profile {
        set __obj [::VooPoint::new 1.0 2.0 "bench" 1 1]
    } $iterations]]

    set result(create_default) [avg_us [profile {
        set __obj [::VooPoint::new()]
    } $iterations]]

    set voo_obj [::VooPoint::new 1.0 2.0 "bench" 1 1]

    set result(setter) [avg_us [profile {
        ::VooPoint::set.x voo_obj 3.14
    } $iterations]]

    set result(getter) [avg_us [profile {
        set __sink [::VooPoint::get.x $voo_obj]
    } $iterations]]

    set result(class_declaration) [avg_us [profile {
        decl_voo_once
    } $iterations]]

    return [array get result]
}

proc benchmark_tcloo {iterations} {
    define_tcloo_point_class

    set result(create_explicit) [avg_us [profile {
        set __obj [::TclooPoint new 1.0 2.0 "bench" 1 1]
    } $iterations]]

    set result(create_default) [avg_us [profile {
        set __obj [::TclooPoint new]
    } $iterations]]

    set tcloo_obj [::TclooPoint new 1.0 2.0 "bench" 1 1]

    set result(setter) [avg_us [profile {
        $tcloo_obj setX 3.14
    } $iterations]]

    set result(getter) [avg_us [profile {
        set __sink [$tcloo_obj getX]
    } $iterations]]

    set result(class_declaration) [avg_us [profile {
        decl_tcloo_once
    } $iterations]]

    return [array get result]
}

proc benchmark_itcl {iterations} {
    define_itcl_point_class

    set result(create_explicit) [avg_us [profile {
        set __obj [::ItclPoint #auto 1.0 2.0 "bench" 1 1]
    } $iterations]]

    set result(create_default) [avg_us [profile {
        set __obj [::ItclPoint #auto]
    } $iterations]]

    set itcl_obj [::ItclPoint #auto 1.0 2.0 "bench" 1 1]

    set result(setter) [avg_us [profile {
        $itcl_obj setX 3.14
    } $iterations]]

    set result(getter) [avg_us [profile {
        set __sink [$itcl_obj getX]
    } $iterations]]

    set result(class_declaration) [avg_us [profile {
        decl_itcl_once
    } $iterations]]

    return [array get result]
}

set iterations 1000
set cpp_lib ""
set frameworks {voo tcloo itcl}
set voo_package voo
set itcl_package itcl

set i 0
while {$i < [llength $argv]} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --help {
            usage
            exit 0
        }
        --iterations {
            incr i
            set iterations [lindex $argv $i]
        }
        --cpp-lib {
            incr i
            set cpp_lib [lindex $argv $i]
        }
        --frameworks {
            incr i
            set frameworks [lindex $argv $i]
        }
        --voo-package {
            incr i
            set voo_package [lindex $argv $i]
        }
        --itcl-package {
            incr i
            set itcl_package [lindex $argv $i]
        }
        default {
            error "Unknown argument: $arg"
        }
    }
    incr i
}

if {$cpp_lib eq ""} {
    set candidates [list \
        [file normalize [file join [file dirname [info script]] .. .. build-bench benchmark voopoint_cpp_bench[info sharedlibextension]]] \
        [file normalize [file join [file dirname [info script]] .. .. build benchmark voopoint_cpp_bench[info sharedlibextension]]] \
        [file normalize [file join [file dirname [info script]] .. voopoint_cpp_bench[info sharedlibextension]]]]
    foreach c $candidates {
        if {[file exists $c]} {
            set cpp_lib $c
            break
        }
    }
}

if {[lsearch -exact $frameworks tcloo] >= 0} {
    package require TclOO
}
if {[lsearch -exact $frameworks voo] >= 0} {
    require_package_or_die $voo_package
}
if {[lsearch -exact $frameworks itcl] >= 0} {
    require_package_or_die $itcl_package Itcl
}

array set results {}

foreach fw $frameworks {
    switch -- $fw {
        cpp {
            array set r [benchmark_cpp $iterations $cpp_lib]
        }
        voo {
            array set r [benchmark_voo $iterations]
        }
        tcloo {
            array set r [benchmark_tcloo $iterations]
        }
        itcl {
            array set r [benchmark_itcl $iterations]
        }
        default {
            error "Unsupported framework '$fw'"
        }
    }

    foreach k {create_explicit create_default setter getter class_declaration} {
        set results($k,$fw) $r($k)
    }
}

set ordered_frameworks {cpp voo tcloo itcl}
set present_frameworks {}
foreach fw $ordered_frameworks {
    if {[lsearch -exact $frameworks $fw] >= 0} {
        lappend present_frameworks $fw
    }
}

array set labels {
    create_explicit "Object Creation (Explicit)"
    create_default "Object Creation (Default)"
    setter "Setter"
    getter "Getter"
    class_declaration "Class Declaration"
}

array set fw_label {
    cpp "VOO C++"
    voo "VOO"
    tcloo "TclOO"
    itcl "Itcl"
}

puts "Benchmark results (microseconds per iteration)"
puts "iterations: $iterations"
if {[lsearch -exact $present_frameworks cpp] >= 0} {
    puts "cpp_lib: $cpp_lib"
}

set row_fmt "%-30s"
foreach fw $present_frameworks {
    append row_fmt " | %16s"
}

set sep "------------------------------"
foreach fw $present_frameworks {
    append sep "+------------------"
}

puts ""
puts [format $row_fmt "Category" {*}[lmap fw $present_frameworks {set fw_label($fw)}]]
puts $sep

foreach key {create_explicit create_default setter getter class_declaration} {
    set vals {}
    foreach fw $present_frameworks {
        lappend vals [fmt_us $results($key,$fw)]
    }
    puts [format $row_fmt $labels($key) {*}$vals]
}

if {[lsearch -exact $present_frameworks cpp] >= 0} {
    puts ""
    puts "Note: VOO C++ class declaration is compile-time; runtime class declaration is shown as N/A."
}
