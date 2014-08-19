package require snit
package require serialport

snit::type grbl {
    option -mode -default 9600,n,8,1
    option -eol -default \n
    option -translation -default {crlf cr}
    option -port -default ""
    #option -command -default "" -configuremethod Configure-command
    # -inittimeout - wait for specified number of microseconds for banner and reset, if no banner
    option -inittimeout -default 3000 -type snit::integer

    component port
    delegate typemethod getPorts using {serialport getPorts}

    variable initBanner ""
    variable firmwareVersion ""
    # not empty if unable to find banner immediately after connection
    variable firmwareError ""


    variable lastResult ok

    # firmware parameters - "$$"
    # structure of parameters:
    # number {value parameterValue  desc parameterDesc}
    # number value - parameter value
    # number desc - parameter description
    variable parameters [dict create]

    # key - hook name
    # value - command prefix
    # hooks:
    #    eof - when EOF received, args - text before EOF
    #    init - when banner received, args - $firmwareVersion
    #    result - when ok or error received, args - ok or "error: ..."
    #    status - when result for "?" command returned, args - $status $mx $my $mz $wx $wy $wz
    #    default - when unknown message received, args - message
    variable hooks -array {}

    constructor args {
        set debug [from args -debug ""]

        $self configurelist $args

        install port using serialport %AUTO% \
            -port $options(-port) \
            -mode $options(-mode) \
            -eol $options(-eol) \
            -translation $options(-translation)

        if {$debug ne ""} {
            $port configure -debug $debug
        }

        set resetId [after $options(-inittimeout) [mymethod hardReset]]
        set disconnectId [after [expr {$options(-inittimeout) * 2}] [mymethod FirmwareError]]
        $port asyncReceive -command [mymethod ProcessResponse]
        vwait [myvar initBanner]

        after cancel $disconnectId
        after cancel $resetId

        if {$firmwareError ne ""} {
            return -code error $firmwareError
        }
    }


    destructor {
        if {$port ne ""} {
            $port destroy
        }
    }


    method FirmwareError {} {
        set firmwareError "firmware error: unable to find banner"
        set initBanner ""; # end of waiting for the banner
    }


    method firmwareVersion {} {
        return $firmwareVersion
    }


    method addHook {hookName command} {
        set hooks($hookName) $command
    }


    method removeHook {hookName} {
        unset hooks($hookName)
    }


    method ProcessResponse {} {
        set l [string trimright [$port receive] \r]

        if {[$port eof]} {
            if {[info exists hooks(eof)] && $hooks(eof) ne ""} {
                uplevel #0 [linsert $hooks(eof) end $l]
            }
        } else {
            # detect the type of answer and run situable hook
            switch -regexp -matchvar M -- $l {
                {^Grbl\s+(\S+)\s+\['\$' for help\]$} {
                    # read banner
                    set initBanner $l
                    set lastResult $l
                    set firmwareVersion [lindex $M 1]
                    if {[info exists hooks(init)] && $hooks(init) ne ""} {
                        uplevel #0 [linsert $hooks(init) end $firmwareVersion]
                    }
                }

                {^\$(\d+)=(\S+)\s+\((.+?)\)$} {
                    # read parameters
                    lassign $M -> n value desc
                    dict set parameters $n value $value
                    dict set parameters $n desc  $desc
                }

                {^ok$} -
                {^error:} {
                    set lastResult $l
                    if {[info exists hooks(result)] && $hooks(result)  ne ""} {
                        uplevel #0 [linsert $hooks(result) end $lastResult]
                    }
                }

                {^<(\w+),MPos:(-?\d+\.\d*),(-?\d+\.\d*),(-?\d+\.\d*),WPos:(-?\d+\.\d*),(-?\d+\.\d*),(-?\d+\.\d*)>$} {
                    if {[info exists hooks(status)] && $hooks(status) ne ""} {
                        lassign $M -> status mx my mz wx wy wz
                        uplevel #0 [linsert $hooks(status) end $status $mx $my $mz $wx $wy $wz]
                    }
                }

                default {
                    if {[info exists hooks(default)] && $hooks(default) ne ""} {
                        uplevel #0 [linsert $hooks(default) end $l]
                    }
                }
            }
        }
    }


    method commandStatus {} {
        return $lastResult
    }


    method waitStatus {} {
        vwait [myvar lastResult]
        return $lastResult
    }


    # todo: maybe return in hook "parameters"
    method parameters {} {
        set readParameters 1
        set parameters [dict create]

        $port sendline {$$}
        vwait [myvar lastResult]

        return $parameters
    }


    method parameter {name value} {
        $port sendline "\$$name=$value"
    }


    method status {} {
        $port send ?
    }


    method hardReset {} {
        # this was taken from arduino documentation
        # http://www.arduino.cc/
        $port configure -ttycontrol {dtr 0}
        after 500
        $port configure -ttycontrol {dtr 1}
    }


    method pause {} {
        $port send !
    }


    method continue {} {
        $port send ~
    }


    method stop {} {
        $port send \x18
    }


    delegate method * to port
}
