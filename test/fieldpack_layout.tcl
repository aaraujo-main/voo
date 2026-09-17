#!/usr/bin/env tclsh

set root [file dirname [file dirname [file normalize [info script]]]]
load [file join $root fieldpack build fieldpack.so] Fieldpack
source [file join $root voo.tcl]

set ::TEST_PASS 0
set ::TEST_FAIL 0

proc _resetClass {name} {
    if {[info exists ::${name}::__defaultObj]} {
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
    if {[catch {uplevel 1 $body} err]} {
        incr ::TEST_FAIL
        puts "FAIL"
        puts "  $err"
    } else {
        incr ::TEST_PASS
        puts "PASS"
    }
}

run_test "layout defaults to list" {
    _resetClass TddListDefault
    voo::class TddListDefault { int_t value 1 }
    assert_equal [TddListDefault::class.layout] list
}

run_test "layout accepts list and fieldpack" {
    _resetClass TddExplicitList
    _resetClass TddFieldPack
    voo::class TddExplicitList -layout list { int_t value 1 }
    voo::class TddFieldPack -layout fieldpack { int_t value 1 }
    assert_equal [TddExplicitList::class.layout] list
    assert_equal [TddFieldPack::class.layout] fieldpack
}

run_test "layout rejects bad options" {
    assert_throws {voo::class TddMissing -layout} "*requires an argument*"
    assert_throws {voo::class TddBad -layout packed {}} "*expected list or fieldpack*"
    assert_throws {voo::class TddTwice -layout list -layout fieldpack {}} "*more than once*"
}

run_test "fieldpack layout requires extension" {
    set child [interp create]
    $child eval [list source [file join $root voo.tcl]]
    set code [$child eval {
        set auto_path {}
        catch {package forget fieldpack}
        catch {voo::class TddNeedsFieldPack -layout fieldpack { int_t value 1 }} message
        set message
    }]
    interp delete $child
    assert_true [string match "*requires FieldPack*" $code]
}

run_test "fieldpack class registers schema and metadata" {
    _resetClass TddSchema
    voo::class TddSchema -layout fieldpack {
        public {
            int_t i 1
            string_t name hello
            list_t tags {a b}
        }
    }
    assert_equal [TddSchema::class.fields] {i name tags}
    assert_equal [TddSchema::class.my.ownFieldTypes] {int string obj}
    assert_equal [TddSchema::class.my.ownFieldDefaults] {1 hello {a b}}
    assert_equal [TddSchema::class.fieldType i] int
    assert_equal [TddSchema::class.fieldType tags] list
    assert_equal [fieldpack::get_schema_name [TddSchema::class.defaultObj]] ::TddSchema
    assert_true [expr {[TddSchema::class.my.schemaId] ne {}}]
}

run_test "fieldpack getters return defaults" {
    set object [TddSchema::new()]
    assert_equal [TddSchema::get.i $object] 1
    assert_equal [TddSchema::get.name $object] hello
    assert_equal [TddSchema::get.tags $object] {a b}
}

run_test "fieldpack setter updates caller variable" {
    set object [TddSchema::new()]
    TddSchema::set.i object 9
    assert_equal [TddSchema::get.i $object] 9
}

run_test "fieldpack setter preserves copy on write" {
    set first [TddSchema::new()]
    set second $first
    TddSchema::set.i first 9
    assert_equal [TddSchema::get.i $first] 9
    assert_equal [TddSchema::get.i $second] 1
}

run_test "fieldpack positional constructor" {
    set object [TddSchema::new 7 sky {x y}]
    assert_equal [TddSchema::get.i $object] 7
    assert_equal [TddSchema::get.name $object] sky
    assert_equal [TddSchema::get.tags $object] {x y}
}

run_test "fieldpack named constructor" {
    set object [TddSchema::new.args -name blue -i 4]
    assert_equal [TddSchema::get.i $object] 4
    assert_equal [TddSchema::get.name $object] blue
    assert_equal [TddSchema::get.tags $object] {a b}
}

run_test "fieldpack inheritance derives schema" {
    _resetClass TddParent
    _resetClass TddChild
    voo::class TddParent -layout fieldpack { public { int_t parent 1 } }
    voo::class TddChild -layout fieldpack -extends TddParent { public { string_t child yes } }
    set object [TddChild::new 2 no]
    assert_equal [TddChild::get.parent $object] 2
    assert_equal [TddChild::get.child $object] no
    assert_equal [fieldpack::get_schema_name $object] ::TddChild
    assert_equal [TddChild::class.my.ownFieldTypes] {string}
    assert_equal [TddChild::class.fieldType parent] int
    assert_equal [TddChild::class.fieldType child] string
}

run_test "mixed layouts fail" {
    assert_throws {voo::class TddListChild -extends TddParent {}} "*parent uses layout*"
}

run_test "equivalent schema redeclaration reuses ID" {
    set oldId [TddSchema::class.my.schemaId]
    voo::class TddSchema -overwrite -layout fieldpack {
        public { int_t i 1; string_t name hello; list_t tags {a b} }
    }
    assert_equal [TddSchema::class.my.schemaId] $oldId
}

run_test "overwritten schema preserves existing objects" {
    set oldObject [TddSchema::new 12 old {legacy}]
    set oldId [TddSchema::class.my.schemaId]
    voo::class TddSchema -overwrite -layout fieldpack {
        public { int_t i 1; string_t name hello; list_t tags {a b}; bool_t active 1 }
    }
    assert_true [expr {[TddSchema::class.my.schemaId] ne $oldId}]
    assert_equal [fieldpack::get $oldObject 0] 12
    assert_equal [fieldpack::get $oldObject 1] old
    assert_equal [fieldpack::get $oldObject 2] legacy
}

run_test "fieldpack virtual dispatch uses schema name" {
    _resetClass TddVirtualBase
    _resetClass TddVirtualChild
    voo::class TddVirtualBase -layout fieldpack {
        method label -virtual {} { return base }
    }
    voo::class TddVirtualChild -layout fieldpack -extends TddVirtualBase {
        method label -override {} { return child }
    }
    set object [TddVirtualChild::new]
    assert_equal [TddVirtualBase::label $object] child
    assert_equal [TddVirtualChild::base.label $object] base
}

run_test "fieldpack direct update accessor" {
    set object [TddSchema::new()]
    TddSchema::update.i object temp { incr temp 4 }
    assert_equal [TddSchema::get.i $object] 5
    assert_equal $temp {}
}

run_test "fieldpack update accessor preserves copy on write" {
    set first [TddSchema::new()]
    set second $first
    TddSchema::update.i first temp { incr temp 4 }
    assert_equal [TddSchema::get.i $first] 5
    assert_equal [TddSchema::get.i $second] 1
    assert_equal $temp {}
}

run_test "fieldpack method update handles many fields" {
    _resetClass TddMethodUpdate
    voo::class TddMethodUpdate -layout fieldpack {
        public {
            int_t i 1
            int_t j 2
        }
        method bump {} -update {i j} {
            incr i 4
            incr j 5
        }
    }
    set object [TddMethodUpdate::new()]
    TddMethodUpdate::bump object
    assert_equal [TddMethodUpdate::get.i $object] 5
    assert_equal [TddMethodUpdate::get.j $object] 7
}

run_test "fieldpack method update writes back after error" {
    _resetClass TddErrorUpdate
    voo::class TddErrorUpdate -layout fieldpack {
        public { int_t value 1 }
        method fail {} -update value {
            set value 9
            error update-body-error
        }
    }
    set object [TddErrorUpdate::new()]
    assert_throws {TddErrorUpdate::fail object} "update-body-error"
    assert_equal [TddErrorUpdate::get.value $object] 9
}

run_test "fieldpack virtual base update" {
    _resetClass TddUpdateBase
    _resetClass TddUpdateChild
    voo::class TddUpdateBase -layout fieldpack {
        public { int_t value 1 }
        method bump {} -virtual -update value { incr value 2 }
    }
    voo::class TddUpdateChild -layout fieldpack -extends TddUpdateBase {
        method bump -override {} -update value { incr value 3 }
    }
    set object [TddUpdateChild::new()]
    TddUpdateBase::bump object
    assert_equal [TddUpdateChild::get.value $object] 4
    TddUpdateChild::base.bump object
    assert_equal [TddUpdateChild::get.value $object] 6
}

run_test "fieldpack nested fields support get set and update" {
    _resetClass TddNested
    _resetClass TddNestedChild
    voo::class TddNestedChild -layout fieldpack { public { int_t value 0 string_t label child } }
    set childSchema [TddNestedChild::class.my.schemaId]
    voo::class TddNested -layout fieldpack {
        public {
            class_t -slice ::TddNestedChild childSlice
            class_t -pack ::TddNestedChild childPack
        }
        method bump {} -update {childSlice childPack} {
            fieldpack::set childSlice 0 11
            fieldpack::set childPack 0 22
        }
    }
    set object [TddNested::new()]
    assert_equal [fieldpack::get_schema_id [TddNested::get.childSlice $object]] $childSchema
    assert_equal [fieldpack::get_schema_id [TddNested::get.childPack $object]] $childSchema
    assert_equal [TddNested::class.my.ownFieldTypes] [list [list slice ::TddNestedChild] [list pack ::TddNestedChild]]
    assert_equal [TddNested::class.fieldType childSlice] {class ::TddNestedChild}
    assert_equal [TddNested::class.fieldType childPack] {class ::TddNestedChild}
    TddNested::set.childSlice object [fieldpack::new $childSchema]
    TddNested::set.childPack object [fieldpack::new $childSchema]
    TddNested::update.childSlice object temp { fieldpack::set temp 0 7 }
    TddNested::update.childPack object temp { fieldpack::set temp 0 8 }
    assert_equal [fieldpack::get [TddNested::get.childSlice $object] 0] 7
    assert_equal [fieldpack::get [TddNested::get.childPack $object] 0] 8
    set copy $object
    TddNested::bump object
    assert_equal [fieldpack::get [TddNested::get.childSlice $object] 0] 11
    assert_equal [fieldpack::get [TddNested::get.childPack $object] 0] 22
    assert_equal [fieldpack::get [TddNested::get.childSlice $copy] 0] 7
    assert_equal [fieldpack::get [TddNested::get.childPack $copy] 0] 8
    assert_equal $temp {}
}

run_test "fieldpack class_t omitted default uses nested new()" {
    _resetClass TddNestedChild
    voo::class TddNestedChild -layout fieldpack {
        public { int_t value 0 string_t label child }
    }
    assert_equal [TddNestedChild::get.value [TddNestedChild::new()]] 0
    set object [TddNested::new()]
    assert_equal [TddNestedChild::get.value [TddNested::get.childSlice $object]] 0
    assert_equal [TddNestedChild::get.value [TddNested::get.childPack $object]] 0
}

run_test "fieldpack class_t accepts explicit nested defaults" {
    _resetClass TddNestedChild
    voo::class TddNestedChild -layout fieldpack {
        public { int_t value 0 string_t label child }
    }
    _resetClass TddExplicitNested
    voo::class TddExplicitNested -layout fieldpack {
        public {
            class_t -slice ::TddNestedChild childSlice [TddNestedChild::new 17]
            class_t -pack ::TddNestedChild childPack [TddNestedChild::new 23]
        }
    }

    set object [TddExplicitNested::new()]
    assert_equal [TddNestedChild::get.value [TddExplicitNested::get.childSlice $object]] 17
    assert_equal [TddNestedChild::get.value [TddExplicitNested::get.childPack $object]] 23

    set overridden [TddExplicitNested::new.args -childSlice [TddNestedChild::new 31]]
    assert_equal [TddNestedChild::get.value [TddExplicitNested::get.childSlice $overridden]] 31
    assert_equal [TddNestedChild::get.value [TddExplicitNested::get.childPack $overridden]] 23
}

run_test "fieldpack class_t empty default is not nested default" {
    _resetClass TddNestedChild
    voo::class TddNestedChild -layout fieldpack {
        public { int_t value 0 string_t label child }
    }
    assert_throws {voo::class TddEmptyNested -layout fieldpack {
        public { class_t -slice ::TddNestedChild child {} }
    }} "*Failed to convert to \"fieldpack::FieldPack\"*"
}

run_test "fieldpack nested class_t preserves obj fields" {
    _resetClass TddObjNestedChild
    _resetClass TddObjNestedContainer
    voo::class TddObjNestedChild -layout fieldpack {
        public {
            obj_t payload {}
            int_t value 3
        }
    }
    set positional [TddObjNestedChild::new {positional payload} 9]
    assert_equal [TddObjNestedChild::get.payload $positional] {positional payload}
    assert_equal [TddObjNestedChild::get.value $positional] 9
    set named [TddObjNestedChild::new.args -payload {named payload} -value 8]
    assert_equal [TddObjNestedChild::get.payload $named] {named payload}
    assert_equal [TddObjNestedChild::get.value $named] 8
    voo::class TddObjNestedContainer -layout fieldpack {
        public {
            class_t -slice ::TddObjNestedChild childSlice
            class_t -pack ::TddObjNestedChild childPack
        }
    }
    set object [TddObjNestedContainer::new()]
    assert_equal [TddObjNestedChild::get.payload [TddObjNestedContainer::get.childSlice $object]] {}
    assert_equal [TddObjNestedChild::get.payload [TddObjNestedContainer::get.childPack $object]] {}
    set slice [TddObjNestedContainer::get.childSlice $object]
    set pack [TddObjNestedContainer::get.childPack $object]
    TddObjNestedChild::set.payload slice {slice payload}
    TddObjNestedChild::set.payload pack {pack payload}
    TddObjNestedContainer::set.childSlice object $slice
    TddObjNestedContainer::set.childPack object $pack
    assert_equal [TddObjNestedChild::get.payload [TddObjNestedContainer::get.childSlice $object]] {slice payload}
    assert_equal [TddObjNestedChild::get.payload [TddObjNestedContainer::get.childPack $object]] {pack payload}
    set copy $object
    TddObjNestedContainer::update.childSlice object temp {
        TddObjNestedChild::set.payload temp {updated slice}
    }
    TddObjNestedContainer::update.childPack object temp {
        TddObjNestedChild::set.payload temp {updated pack}
    }
    assert_equal [TddObjNestedChild::get.payload [TddObjNestedContainer::get.childSlice $object]] {updated slice}
    assert_equal [TddObjNestedChild::get.payload [TddObjNestedContainer::get.childPack $object]] {updated pack}
    assert_equal [TddObjNestedChild::get.payload [TddObjNestedContainer::get.childSlice $copy]] {slice payload}
    assert_equal [TddObjNestedChild::get.payload [TddObjNestedContainer::get.childPack $copy]] {pack payload}
}

run_test "class_t uses obj layout for list classes" {
    _resetClass TddListChild
    _resetClass TddListContainer
    voo::class TddListChild { public { int_t value 3 } }
    voo::class TddListContainer {
        public { class_t -pack ::TddListChild child }
    }
    set object [TddListContainer::new()]
    set child [TddListContainer::get.child $object]
    assert_equal [TddListContainer::class.fieldType child] {class ::TddListChild}
    assert_equal [TddListChild::get.value $child] 3
    TddListChild::set.value child 9
    assert_equal [TddListChild::get.value $child] 9
}

run_test "class_t requires global class names" {
    assert_throws {voo::class TddRelativeNested {
        public { class_t TddListChild child }
    }} "*requires global class name starting with ::*"
}

run_test "fieldpack class_t rejects list child classes" {
    assert_throws {voo::class TddInvalidNested -layout fieldpack {
        public { class_t ::TddListChild child }
    }} "*requires nested class*fieldpack layout*"
}

run_test "fieldpack nested update writes back after error" {
    set object [TddNested::new()]
    assert_throws {TddNested::update.childSlice object temp {
        fieldpack::set temp 0 31
        error nested-update-body-error
    }} "nested-update-body-error"
    assert_equal [fieldpack::get [TddNested::get.childSlice $object] 0] 31
    assert_equal $temp {}
}

run_test "fieldpack nested class supports multiple slice defaults" {
    _resetClass TddMultipleSliceChild
    _resetClass TddMultipleSlice
    voo::class TddMultipleSliceChild -layout fieldpack {
        public {
            int_t value 0
            double_t weight 0.0
            string_t label child
        }
    }
    voo::class TddMultipleSlice -layout fieldpack {
        public {
            class_t -slice ::TddMultipleSliceChild child0 [TddMultipleSliceChild::new()]
            class_t -slice ::TddMultipleSliceChild child1 [TddMultipleSliceChild::new()]
            class_t -slice ::TddMultipleSliceChild child2 [TddMultipleSliceChild::new()]
        }
    }
    set object [TddMultipleSlice::new()]
    foreach field {child0 child1 child2} {
        assert_equal [TddMultipleSliceChild::get.value [TddMultipleSlice::get.$field $object]] 0
    }
}

puts "Summary: $::TEST_PASS passed, $::TEST_FAIL failed"
if {$::TEST_FAIL > 0} {
    exit 1
}
exit 0
