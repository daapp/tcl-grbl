#! /bin/sh
# -*- mode: Tcl ; -*- \
exec tclsh "$0" ${1+"$@"}

tcl::tm::path add ~/lib/tcl
tcl::tm::path add .
package require grbl


if {$argc == 1 } {
    set portName [lindex $argv 0]

    proc debug {port args} {
        puts "[clock format [clock seconds]]> [$port receive]"
    }

    set status ""

    puts "Ports: [grbl getPorts]"

    puts [clock format [clock seconds]]
    grbl a -port $portName -debug 0

    a addHook init [list apply {{args} {
        puts "HOOK init: $args"
    }}]

    a addHook result [list apply {{args} {
        puts "HOOK result: $args"
    }}]

    a addHook status [list apply {{args} {
        set ::status [lindex $args 0]
        puts "HOOK status: $args"
    }}]

    a addHook default [list apply {{args} {
        puts "HOOK default: [lindex $args 0]"
    }}]

    puts "Grbl version is [a firmwareVersion]"
    puts "Parameters:"
    dict for {n p} [a parameters] {
        dict with p {
            puts "$n = $value  $desc"
        }
    }


    a status

    puts "send \$"
    a sendline {$}
    puts "wait status"
    a waitStatus
    puts "end of waitStatus"

    a sendline g1x10y15z20f1000
    while 1 {
        after 500
        a status
        vwait status
        if {$status eq "Idle"} {
            break
        }
    }
    a pause

    a status
    puts "wait 3"

    after 3000
    a continue

    puts "end wait"

    puts "stop"
    a stop

    a status
    vwait forever

} else {
    puts stderr "Usage: $argv0 serial-port"
    exit 1
}
