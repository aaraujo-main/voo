#!/usr/bin/env tclsh
# Comprehensive VOO API behavior tests derived from README.md

set scriptDir [file dirname [file normalize [info script]]]
source [file join $scriptDir .. voo.tcl]

set ::TEST_PASS 0
set ::TEST_FAIL 0

proc _resetClass {name} {
    if {[namespace exists ::$name]} {
        namespace delete ::$name
    }
}

proc assert_true {exprValue {msg "assert_true failed"}} {
    if {!$exprValue} {
        error $msg
    }
}

proc assert_equal {actual expected {msg ""}} {
    if {$actual ne $expected} {
        if {$msg eq ""} {
            set msg "expected '$expected', got '$actual'"
        }
        error $msg
    }
}

proc assert_almost_equal {actual expected {eps 1e-6} {msg ""}} {
    if {[expr {abs($actual - $expected)}] > $eps} {
        if {$msg eq ""} {
            set msg "expected $expected +/- $eps, got $actual"
        }
        error $msg
    }
}

proc assert_throws {script {pattern *}} {
    set rc [catch {uplevel 1 $script} err]
    if {!$rc} {
        error "expected error, but command succeeded"
    }
    if {![string match $pattern $err]} {
        error "error '$err' does not match pattern '$pattern'"
    }
}

proc run_test {name body} {
    puts -nonewline "- $name ... "
    if {[catch {uplevel 1 $body} err opts]} {
        incr ::TEST_FAIL
        puts "FAIL"
        puts "  $err"
    } else {
        incr ::TEST_PASS
        puts "PASS"
    }
}

# ----------------------------------------------------------------------------
# voo::isVooClass
# ----------------------------------------------------------------------------
run_test "isVooClass detects VOO and non-VOO namespaces" {
    _resetClass Demo
    voo::class Demo { int_t x 0 }
    assert_equal [voo::isVooClass Demo] 1
    assert_equal [voo::isVooClass ::Demo] 1
    assert_equal [voo::isVooClass NotAClass] 0

    namespace eval PlainNs { variable foo 1 }
    assert_equal [voo::isVooClass PlainNs] 0
    namespace delete ::PlainNs
}

# ----------------------------------------------------------------------------
# voo::class + inheritance + virtual classes
# ----------------------------------------------------------------------------
run_test "voo::class basic usage" {
    _resetClass Person
    voo::class Person {
        public {
            string_t name "unknown"
            int_t age 0
        }
        method greet {} {
            return "Hello, I'm [get.name $this]"
        }
    }

    set p [Person::new "Alice" 30]
    assert_equal [Person::greet $p] "Hello, I'm Alice"
}

run_test "voo::class virtual + extends" {
    _resetClass Shape
    _resetClass Circle

    voo::class Shape -virtual {
        method area -virtual {} { return 0.0 }
    }
    voo::class Circle -extends Shape {
        public { double_t radius 1.0 }
        method area -override {} {
            return [expr {3.14159 * [get.radius $this] ** 2}]
        }
    }

    set s [Circle::new 5.0]
    assert_almost_equal [Shape::area $s] 78.53975 1e-5
}

# ----------------------------------------------------------------------------
# Field types + public/private
# ----------------------------------------------------------------------------
run_test "field types with static and private" {
    _resetClass Config
    voo::class Config {
        public {
            string_t host "localhost"
            int_t port 8080
            bool_t verbose 0
            list_t tags [list]
            dict_t metadata [dict create]
            obj_t nested {}
            int_t -static instanceCount 0
        }
        private {
            string_t secret "token"
        }
    }

    set c [Config::new()]
    assert_equal [Config::get.host $c] localhost
    assert_equal [Config::get.port $c] 8080
    assert_equal [Config::get.verbose $c] 0
    assert_equal [Config::get.tags $c] {}
    assert_equal [Config::get.metadata $c] {}
    assert_equal [Config::get.nested $c] {}
    assert_equal [Config::my.get.secret $c] token

    assert_equal [Config::class.get.instanceCount] 0
    Config::class.set.instanceCount 7
    assert_equal [Config::class.get.instanceCount] 7
}

run_test "public and private method naming" {
    _resetClass Account
    voo::class Account {
        string_t id ""
        public {
            string_t owner ""
            method ownerLabel {} {
                return "Owner: [get.owner $this]"
            }
        }
        private {
            double_t balance 0.0
            method rawBalance {} {
                return [my.get.balance $this]
            }
        }
    }

    set a [Account::new "A-1" "Alice" 0.0]
    assert_equal [Account::ownerLabel $a] "Owner: Alice"
    assert_equal [Account::my.rawBalance $a] 0.0
}

# ----------------------------------------------------------------------------
# constructor API
# ----------------------------------------------------------------------------
run_test "constructor options and generated constructor names" {
    _resetClass Color
    voo::class Color {
        public {
            int_t r 0
            int_t g 0
            int_t b 0
        }

        constructor {r g b} {
            return [list $r $g $b]
        }

        constructor -noargs {
            variable __defaultObj
            return $__defaultObj
        }

        constructor -name new.args {args} {
            variable __defaultObj
            set obj $__defaultObj
            dict for {key value} $args {
                if {[string index $key 0] ne "-"} {
                    error "Constructor argument keys must start with '-', got '$key'"
                }
                set field [string range $key 1 end]
                set setter set.$field
                if {[info commands $setter] ne ""} {
                    $setter obj $value
                } else {
                    error "Unknown field option: $field"
                }
            }
            return $obj
        }

        constructor -name fromHex {hex} {
            set hex [string trimleft $hex "#"]
            scan [string range $hex 0 1] %x r
            scan [string range $hex 2 3] %x g
            scan [string range $hex 4 5] %x b
            return [list $r $g $b]
        }

        constructor -typed {int int int} {r g b} {
            return [list $r $g $b]
        }
    }

    assert_equal [Color::new 255 128 0] [list 255 128 0]
    assert_equal [Color::new()] [list 0 0 0]
    assert_equal [Color::new.args -r 255 -g 128 -b 0] [list 255 128 0]
    assert_equal [Color::fromHex #FF8000] [list 255 128 0]
    assert_equal [Color::new(int,int,int) 10 20 30] [list 10 20 30]
}

# ----------------------------------------------------------------------------
# method API options
# ----------------------------------------------------------------------------
run_test "method options default, -upvar, -update, -static" {
    _resetClass Vec2
    voo::class Vec2 {
        public {
            double_t x 0.0
            double_t y 0.0
            list_t tags [list]
        }

        method length {} {
            return [expr {sqrt([get.x $this]**2 + [get.y $this]**2)}]
        }

        method scale {factor} -upvar {
            set.x this [expr {[get.x $this] * $factor}]
            set.y this [expr {[get.y $this] * $factor}]
        }

        method appendTag {tag} -update {tags} {
            lappend tags $tag
        }

        method origin {} -static {
            return [new 0.0 0.0 [list]]
        }
    }

    set v [Vec2::new 3.0 4.0 [list]]
    assert_almost_equal [Vec2::length $v] 5.0

    Vec2::scale v 2.0
    assert_equal [Vec2::get.x $v] 6.0
    assert_equal [Vec2::get.y $v] 8.0

    Vec2::appendTag v scaled
    assert_equal [Vec2::get.tags $v] [list scaled]

    set o [Vec2::origin]
    assert_equal [Vec2::get.x $o] 0.0
    assert_equal [Vec2::get.y $o] 0.0
}

run_test "method -override and base.<name> polymorphism" {
    _resetClass Shape2
    _resetClass Circle2
    _resetClass ColoredCircle2

    voo::class Shape2 -virtual {
        method area -virtual {} { return 0.0 }
    }

    voo::class Circle2 -extends Shape2 {
        public { double_t radius 1.0 }
        method area -override {} {
            return [expr {3.14159 * [get.radius $this] ** 2}]
        }
    }

    voo::class ColoredCircle2 -extends Circle2 {
        public { string_t color red }
        method area -override {} {
            set parentArea [Circle2::base.area $this]
            return [expr {$parentArea * 1.1}]
        }
    }

    set s [ColoredCircle2::new 5.0 blue]
    assert_almost_equal [Shape2::area $s] [expr {3.14159 * 25 * 1.1}] 1e-5
}

run_test "method -virtual with -upvar dispatches by reference" {
    _resetClass VRoot
    _resetClass VChild

    voo::class VRoot -virtual {
        public { int_t n 0 }
        method bump {delta} -virtual -upvar {
            set.n this [expr {[get.n $this] + $delta}]
        }
    }

    voo::class VChild -extends VRoot {
        method bump {delta} -override -upvar {
            set.n this [expr {[get.n $this] + ($delta * 2)}]
        }
    }

    # Base implementation path (dispatch to base.bump) keeps by-reference semantics.
    set rootObj [VRoot::new 10]
    VRoot::bump rootObj 3
    assert_equal [VRoot::get.n $rootObj] 13

    # Child implementation path (dispatch to child method) keeps by-reference semantics.
    set childObj [VChild::new 10]
    VRoot::bump childObj 3
    assert_equal [VChild::get.n $childObj] 16
}

run_test "method -virtual with -update dispatches and updates fields" {
    _resetClass VUpdateRoot
    _resetClass VUpdateChild

    voo::class VUpdateRoot -virtual {
        public {
            int_t n 0
            list_t tags [list]
        }
        method mutate {delta tag} -virtual -update {n tags} {
            incr n $delta
            lappend tags "root:$tag"
        }
    }

    voo::class VUpdateChild -extends VUpdateRoot {
        method mutate {delta tag} -override -update {n tags} {
            incr n [expr {$delta * 2}]
            lappend tags "child:$tag"
        }
    }

    # Base implementation path keeps -update semantics.
    set rootObj [VUpdateRoot::new 10 [list]]
    VUpdateRoot::mutate rootObj 3 a
    assert_equal [VUpdateRoot::get.n $rootObj] 13
    assert_equal [VUpdateRoot::get.tags $rootObj] [list root:a]

    # Child implementation path keeps -update semantics via virtual dispatch.
    set childObj [VUpdateChild::new 10 [list]]
    VUpdateRoot::mutate childObj 3 b
    assert_equal [VUpdateChild::get.n $childObj] 16
    assert_equal [VUpdateChild::get.tags $childObj] [list child:b]
}

run_test "method -virtual with -update can call parent base.<name>" {
    _resetClass VBaseRoot
    _resetClass VBaseChild

    voo::class VBaseRoot -virtual {
        public {
            int_t n 0
            list_t tags [list]
        }
        method mutate {delta tag} -virtual -update {n tags} {
            incr n $delta
            lappend tags "root:$tag"
        }
    }

    voo::class VBaseChild -extends VBaseRoot {
        method mutate {delta tag} -override -update {n tags} {
            VBaseRoot::base.mutate this $delta $tag
            incr n 100
            lappend tags "child:$tag"
        }
    }

    set obj [VBaseChild::new 1 [list]]
    VBaseRoot::mutate obj 2 x
    assert_equal [VBaseChild::get.n $obj] 103
    assert_equal [VBaseChild::get.tags $obj] [list root:x child:x]
}

run_test "field names are namespace variables holding field indexes" {
    _resetClass FieldIndexDemo

    voo::class FieldIndexDemo {
        public {
            int_t first 0
        }
        private {
            string_t hidden secret
        }
        public {
            int_t myField 1
        }
    }

    assert_equal [namespace eval ::FieldIndexDemo {set first}] 0
    assert_equal [namespace eval ::FieldIndexDemo {set hidden}] 1
    assert_equal [namespace eval ::FieldIndexDemo {set myField}] 2
    assert_equal [FieldIndexDemo::class.fields] [list first hidden myField]
}

run_test "method variable disambiguates field index from similarly named args" {
    _resetClass NameDisambiguation

    voo::class NameDisambiguation {
        public {
            int_t id 0
            int_t myField 10
        }

        method setMyFieldByIndex {myField_} -upvar {
            variable myField
            lset this $myField $myField_
        }

        method setMyFieldByAccessor {value} -upvar {
            set.myField this $value
        }
    }

    set obj [NameDisambiguation::new 7 11]

    NameDisambiguation::setMyFieldByIndex obj 42
    assert_equal [NameDisambiguation::get.id $obj] 7
    assert_equal [NameDisambiguation::get.myField $obj] 42

    NameDisambiguation::setMyFieldByAccessor obj 55
    assert_equal [NameDisambiguation::get.myField $obj] 55
}

run_test "argument name collision with field index variable raises error" {
    _resetClass NameCollision

    voo::class NameCollision {
        public {
            int_t myField 0
        }

        method bad {myField} -upvar {
            variable myField
            lset this $myField $myField
        }
    }

    set obj [NameCollision::new 1]
    assert_throws {
        NameCollision::bad obj 9
    } {*variable "myField" already exists*}
}

# ----------------------------------------------------------------------------
# importMethods API
# ----------------------------------------------------------------------------
run_test "importMethods with list and single method" {
    _resetClass Base
    _resetClass ChildList
    _resetClass ChildSingle

    voo::class Base {
        method hello {} { return "hello" }
        method world {} { return "world" }
        method join {sep} {
            return "[hello $this]${sep}[world $this]"
        }
        method ping {} { return "ping" }
    }

    voo::class ChildList -extends Base {
        importMethods {hello world join}
    }

    voo::class ChildSingle -extends Base {
        importMethods ping
    }

    set c1 [ChildList::new]
    assert_equal [ChildList::hello $c1] hello
    assert_equal [ChildList::world $c1] world
    assert_equal [ChildList::join $c1 :] hello:world

    set c2 [ChildSingle::new]
    assert_equal [ChildSingle::ping $c2] ping
}

# ----------------------------------------------------------------------------
# manual getter/setter/updater API
# ----------------------------------------------------------------------------
run_test "manual getter/setter/updater generation" {
    _resetClass Item
    voo::class Item {
        public {
            string_t label ""
            list_t tags [list]
        }
        getter getLabel label
        setter setLabel label
        updater updateTags tags
    }

    set it [Item::new pen [list blue office]]
    assert_equal [Item::getLabel $it] pen
    Item::setLabel it marker
    assert_equal [Item::getLabel $it] marker
    set tmp SENTINEL
    Item::updateTags it tmp { lappend tmp stationery }
    assert_equal [Item::get.tags $it] [list blue office stationery]
    assert_equal $tmp {}
}

# ----------------------------------------------------------------------------
# generated accessors + generated constructors + introspection
# ----------------------------------------------------------------------------
run_test "generated accessors cover instance/static/private" {
    _resetClass Point
    voo::class Point {
        public {
            double_t x 0.0
            double_t y 0.0
            int_t -static count 0
        }
        private {
            string_t note "n/a"
        }
    }

    set p [Point::new.args -x 1.0 -y 2.0]
    assert_equal [Point::get.x $p] 1.0
    Point::set.x p 5.0
    Point::update.x p tmp { set tmp [expr {$tmp * 2}] }
    assert_equal [Point::get.x $p] 10.0

    assert_equal [Point::class.get.count] 0
    Point::class.set.count 10
    Point::class.update.count tmp { incr tmp }
    assert_equal [Point::class.get.count] 11

    assert_equal [Point::my.get.note $p] n/a
}

run_test "generated constructors and named partial override" {
    _resetClass Person2
    voo::class Person2 {
        public {
            string_t name "unknown"
            int_t age 0
        }
    }

    assert_equal [Person2::new Alice 30] [list Alice 30]
    assert_equal [Person2::new()] [list unknown 0]
    assert_equal [Person2::new.args -name Bob -age 25] [list Bob 25]
    assert_equal [Person2::new.args -name Carol] [list Carol 0]
}

run_test "class.defaultObj and class.fields incl. inheritance" {
    _resetClass Point2
    _resetClass ColorPoint2

    voo::class Point2 {
        public {
            double_t x 0.0
            double_t y 0.0
        }
    }
    assert_equal [Point2::class.defaultObj] [list 0.0 0.0]
    assert_equal [Point2::class.fields] [list x y]

    voo::class ColorPoint2 -extends Point2 {
        public { string_t color red }
    }
    assert_equal [ColorPoint2::class.fields] [list x y color]
    assert_equal [ColorPoint2::class.defaultObj] [list 0.0 0.0 red]
}

# ----------------------------------------------------------------------------
# selected error behavior checks used in README scenarios
# ----------------------------------------------------------------------------
run_test "override requires parent method" {
    _resetClass ParentX
    _resetClass ChildX

    voo::class ParentX { method ok {} { return ok } }
    assert_throws {
        voo::class ChildX -extends ParentX {
            method missing -override {} { return bad }
        }
    } "Method '*does not override any method*'"
}

run_test "duplicate voo class can be replaced with -overwrite" {
    _resetClass ReplaceClass

    voo::class ReplaceClass {
        public {
            int_t x 10
        }
        method label {} {
            return old
        }
    }

    assert_equal [ReplaceClass::label [ReplaceClass::new 10]] old

    voo::class ReplaceClass -overwrite {
        public {
            string_t name fresh
        }
        method label {} {
            return new
        }
    }

    set obj [ReplaceClass::new Bob]
    assert_equal [ReplaceClass::label $obj] new
    assert_equal [ReplaceClass::get.name $obj] Bob
    assert_throws {
        ReplaceClass::get.x $obj
    } "invalid command name*"
}

run_test "existing non-voo namespace FAILS to replace without -overwrite" {
    voo::class LegacyNs {
        public { int_t x 7 }
    }

    # Check that it throws an error because it exists and -overwrite is missing
    assert_throws {
        voo::class LegacyNs {
            public { int_t x 7 }
        }
    } "Class/Namespace 'LegacyNs' already exists. Use -overwrite to replace it."
}

puts ""
puts "Summary: $::TEST_PASS passed, $::TEST_FAIL failed"
if {$::TEST_FAIL > 0} {
    exit 1
}
exit 0
