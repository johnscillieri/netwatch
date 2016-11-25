import asyncdispatch
import asyncfile
import os
import posix
import terminal
import termios
import strfmt
import strutils
import tables
import times

import eternity
import host


# Reset everything when we're done
system.addQuitProc(resetAttributes)


type WinSize = object
  row, col, xpixel, ypixel: cushort


proc terminal_height*(): int =
    const TIOCGWINSZ = 0x5413
    var size: WinSize
    discard ioctl(0, TIOCGWINSZ, addr size)
    result = size.row.int


proc hide_cursor() =
    stdout.write("\e[?25l")


proc show_cursor() =
    stdout.write("\e[?25h")


template assign_max_len( host: Host, field: untyped ) =
    max_tuple.field = if len(host.field) > max_tuple.field: len(host.field) else: max_tuple.field


proc render_table*( table: OrderedTableRef[string,Host],
                    highlight_row = -1 ): string =

    const REVERSE = "\e[" & $ord(styleReverse) & 'm'
    const RESET = "\e[0m"
    var lines = newSeqOfCap[string]( len( table ) )

    table.sort( proc( x, y: (string, Host) ): int = cmp( inet_addr( x[1].ip ), inet_addr( y[1].ip ) ) )

    # create a "max" list that holds the max width for each column
    var max_tuple = ( index:len("$1" % $len(table)),
                      label:len("Label"),
                      ip:len("IP Address"),
                      mac:len("MAC Address"),
                      oui:len("OUI"),
                      last_seen:0 )
    for mac, host in table:
        assign_max_len( host, label )
        assign_max_len( host, ip )
        assign_max_len( host, mac )
        assign_max_len( host, oui )

    lines.add( " {:>{}s}  {:{}s}   {:{}s}   {:{}s}   {:{}s}   {}".fmt( " ", $max_tuple.index,
                                                                       "Label", $max_tuple.label,
                                                                       "IP Address", $max_tuple.ip,
                                                                       "MAC Address", $max_tuple.mac,
                                                                       "OUI", $max_tuple.oui,
                                                                       "Last Seen" ) )
    var row = 0
    for mac, host in table:
        row += 1
        let last_seen = getTime() - host.last_seen
        let last_seen_text = if last_seen < 60: "<1m" else: humanize_max( last_seen )
        if row == highlight_row:
            let index = " {:>{}s}. ".fmt( $row, $max_tuple.index )
            let label = "{:{}s}   ".fmt( host.label, $max_tuple.label )
            let rest = "{:{}s}   {:{}s}   {:{}s}   {}".fmt( host.ip, $max_tuple.ip,
                                                            host.mac, $max_tuple.mac,
                                                            host.oui, $max_tuple.oui,
                                                            last_seen_text )
            lines.add( index & REVERSE & label & RESET & rest )
        else:
            lines.add( " {:>{}s}. {:{}s}   {:{}s}   {:{}s}   {:{}s}   {}".fmt( $row, $max_tuple.index,
                                                                               host.label, $max_tuple.label,
                                                                               host.ip, $max_tuple.ip,
                                                                               host.mac, $max_tuple.mac,
                                                                               host.oui, $max_tuple.oui,
                                                                               last_seen_text ) )

    result = lines.join("\n")


proc draw_table*( table: string, header: string, footer = "" ) =

    stdout.eraseScreen()
    setCursorPos( 0, 0 )
    styledEcho( header )

    stdout.cursorDown( count=1 )
    styledEcho( table )

    # Five is one row for header, spacer, table header, spacer after table, and
    # then the line to print on.
    let height = terminal_height()
    let move_down = if countLines(table) >= height-5: height
                    else: height - (countLines(table) + 5)

    stdout.cursorDown( count=move_down )
    if footer == "":
        styledEcho( "Press 1-$# to assign a label. Press q to quit." % $countLines(table) )
    else:
        styledEcho( "", footer )


proc getch_async*(): Future[char] {.async.} =
    ## Read a single character from the terminal, blocking until it is entered.
    ## The character is not printed to the terminal. This is not available for
    ## Windows.
    let fd = getFileHandle(stdin)
    var oldMode: Termios
    discard fd.tcgetattr(addr oldMode)
    var mode: Termios
    discard fd.tcgetattr(addr mode)
    mode.c_iflag = mode.c_iflag and not Cflag(BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    mode.c_cflag = (mode.c_cflag and not Cflag(CSIZE or PARENB)) or CS8
    mode.c_lflag = mode.c_lflag and not Cflag(ECHO or ICANON or IEXTEN or ISIG)
    mode.c_cc[VMIN] = 1.cuchar
    mode.c_cc[VTIME] = 0.cuchar
    discard fd.tcsetattr(TCSAFLUSH, addr mode)
    var file = openAsync("/dev/stdin", fmRead)
    result = (await file.read(1))[0]
    discard fd.tcsetattr(TCSADRAIN, addr oldMode)


proc check_for_resize*( table: OrderedTableRef[string,Host], header:string, sleep_interval_secs = 1 ) {.async.} =
    var old_height = terminal_height()
    while true:
        let new_height = terminal_height()
        if old_height != new_height:
            draw_table( render_table( table ), header=header )
            old_height = new_height
        await sleepAsync( sleep_interval_secs * 1000 )


proc input_loop*( host_table: OrderedTableRef[string, Host], header:string ) {.async.} =

    const letters = {'a'..'z', 'A'..'Z', ' ', chr(39), '-', '_', '?', '.' }
    const numbers = {'0'..'9'}
    const enter_key = chr(13)
    const escape_key = chr(27)
    const backspace_key = chr(127)

    hide_cursor()

    var selected_row = -1
    var host: Host
    var prev_label: string
    var footer = ""
    while true:
        let key = if selected_row == -1: await getch_async() else: getch()
        #echo("You typed: ", ord(key), " selected row: ", selected_row )

        if selected_row == -1 and key == 'q':
            show_cursor()
            break

        elif key in numbers:
            # If row has been selected and other characters have been typed,
            # handle key just like a letter
            if selected_row != -1 and prev_label != host.label:
                host.label &= $key

            else:
                if selected_row == -1:
                    selected_row = parseInt($key)

                elif selected_row != -1 and prev_label == host.label:
                    selected_row = parseInt( $selected_row & $key )

                if selected_row > len( host_table ):
                    selected_row = -1
                    continue

                # Get host for row
                var i = 0
                for cur_mac, cur_host in host_table:
                    if (i+1) == selected_row:
                        host = cur_host
                        break
                    i += 1
                prev_label = host.label
                footer = "Type your new label. Press enter to save and escape to revert."

        elif selected_row == -1:
            continue # short circuit any other key when no row is selected

        elif key == enter_key:
            selected_row = -1
            footer = ""

        elif key == escape_key:
            host.label = prev_label
            selected_row = -1
            footer = ""

        elif key == backspace_key:
            if host.label == nil: host.label = ""
            host.label = host.label[.. (len(host.label)-2)]

        elif key in letters:
            if host.label == nil: host.label = ""
            host.label &= $key

        draw_table( render_table( host_table, selected_row ), header, footer )


proc prompt_table*( header, body, footer: string = "", default=1 ): int =
    if header != "": echo( header & "\n" )
    if body != "": echo( body )
    stdout.write( "\n" & footer & " (" & $default & ") > " )
    stdout.flushFile()
    let choice = stdin.readLine().strip()
    result = if choice != "": choice.parseInt()-1 else: default-1


proc prompt*( text: string, default=true ): bool =
    let default_text = if default: "Y/n" else: "y/N"
    while true:
        stdout.write( text & " (" & $default_text & ") > " )
        stdout.flushFile()
        let choice = stdin.readLine().strip()
        if choice == "":
            return default
        elif choice.toLowerAscii()[0] == 'y':
            return true
        elif choice.toLowerAscii()[0] == 'n':
            return false
        else:
            echo( "Invalid choice: '", choice, "' Please enter 'y' or 'n'" )


################################################################################
proc main() {.async.} =
    var table = newOrderedTable[string, Host]()
    table["04:32:12:44:53:dd"] = Host( label:"TV STB", ip:"192.168.10.100", mac:"04:32:12:44:53:dd", oui:"Cisco" )
    table["04:32:12:44:53:aa"] = Host( label:"Router", ip:"192.168.10.1", mac:"04:32:12:44:53:aa", oui:"Asus Inc." )
    table["04:32:12:44:53:cc"] = Host( label:"", ip:"192.168.10.65", mac:"04:32:12:44:53:cc", oui:"Dell" )
    table["04:32:12:44:53:bb"] = Host( label:"Wemo Light (Kitchen)", ip:"192.168.10.24", mac:"04:32:12:44:53:bb", oui:"Belkin Inc." )
    table["04:32:12:44:53:ee"] = Host( label:"Wemo Light (Lamp)", ip:"192.168.10.34", mac:"04:32:12:44:53:ee", oui:"Belkin Inc." )
    table["04:32:12:44:53:ff"] = Host( label:"", ip:"192.168.10.65", mac:"04:32:12:44:53:cc", oui:"Dell" )
    table["04:32:12:44:53:gg"] = Host( label:"Wemo Light (Kitchen)", ip:"192.168.10.24", mac:"04:32:12:44:53:bb", oui:"Belkin Inc." )
    table["04:32:12:44:53:hh"] = Host( label:"Wemo Light (Lamp)", ip:"192.168.10.34", mac:"04:32:12:44:53:ee", oui:"Belkin Inc." )
    table["04:32:12:44:53:ii"] = Host( label:"", ip:"192.168.10.65", mac:"04:32:12:44:53:cc", oui:"Dell" )
    table["04:32:12:44:53:jj"] = Host( label:"Wemo Light (Kitchen)", ip:"192.168.10.24", mac:"04:32:12:44:53:bb", oui:"Belkin Inc." )
    table["04:32:12:44:53:kk"] = Host( label:"Wemo Light (Lamp)", ip:"192.168.10.34", mac:"04:32:12:44:53:ee", oui:"Belkin Inc." )
    table["04:32:12:44:53:ll"] = Host( label:"", ip:"192.168.10.65", mac:"04:32:12:44:53:cc", oui:"Dell" )
    table["04:32:12:44:53:mm"] = Host( label:"Wemo Light (Kitchen)", ip:"192.168.10.24", mac:"04:32:12:44:53:bb", oui:"Belkin Inc." )
    table["04:32:12:44:53:nn"] = Host( label:"Wemo Light (Lamp)", ip:"192.168.10.34", mac:"04:32:12:44:53:ee", oui:"Belkin Inc." )

    asyncCheck check_for_resize( table, "" )

    await input_loop( table, "" )
    quit(0)


when isMainModule:
    asyncCheck main()
    runForever()
