set bitfile "E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit"
set logfile "E:/Xylinx/EO_IR_HD_SDI_panorama_base/program_loop_panorama_base_runtime.log"
set success_delay_ms 500
set failure_delay_ms 2000

proc ts {} {
    return [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
}

proc log_line {fh msg} {
    set line "[ts] $msg"
    puts $line
    puts $fh $line
    flush $fh
}

set fh [open $logfile a]
fconfigure $fh -buffering line
log_line $fh "Starting programming loop"
log_line $fh "Bitfile: $bitfile"

set iter 0
while {1} {
    incr iter
    set start_ms [clock milliseconds]
    if {[catch {
        catch {close_hw_target}
        catch {disconnect_hw_server}
        catch {close_hw_manager}

        open_hw_manager
        connect_hw_server
        open_hw_target

        set dev [lindex [get_hw_devices] 0]
        if {$dev eq ""} {
            error "No hardware devices found"
        }

        current_hw_device $dev
        refresh_hw_device $dev
        set_property PROGRAM.FILE $bitfile $dev
        program_hw_devices $dev
        refresh_hw_device $dev
    } err opts]} {
        set elapsed [expr {[clock milliseconds] - $start_ms}]
        log_line $fh "ITER=$iter RESULT=FAIL ELAPSED_MS=$elapsed ERROR={$err}"
        after $failure_delay_ms
    } else {
        set elapsed [expr {[clock milliseconds] - $start_ms}]
        log_line $fh "ITER=$iter RESULT=PASS ELAPSED_MS=$elapsed"
        after $success_delay_ms
    }
}
