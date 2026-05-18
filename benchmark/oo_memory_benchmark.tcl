#!/usr/bin/env tclsh

# Memory benchmark helper for isolated-process measurements.
# Designed to be run as one framework per tclsh process.

proc usage {} {
    puts "Usage: tclsh oo_memory_benchmark.tcl --framework {cpp|voo|tcloo|itcl} ?options?"
    puts ""
    puts "Options:"
    puts "  --count N             Number of objects to create (default: 100000)"
    puts "  --cpp-lib PATH        Path to VOO C++ shared library (required for cpp)"
    puts "  --voo-package NAME    VOO package name for package require (default: voo)"
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
set voo_package voo
set itcl_package itcl
set hold 1

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
        --voo-package {
            incr i
            set voo_package [lindex $argv $i]
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

if {$framework eq "cpp"} {
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
    if {$cpp_lib eq "" || ![file exists $cpp_lib]} {
        error "--cpp-lib is required for framework cpp"
    }
    load $cpp_lib Point
}

switch -- $framework {
    voo {
        require_package_or_die $voo_package
        define_voo_point_class
        set objects {}
        for {set n 0} {$n < $count} {incr n} {
            lappend objects [::VooPoint::new 1.0 2.0 "bench" 1 1]
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
puts "pid=[pid]"
puts "vmrss_kb=[current_rss_kb]"
puts "objects_list_length=[llength $objects]"

if {$hold} {
    puts "Press Enter to exit (use this pause to inspect with htop)."
    flush stdout
    gets stdin
}
