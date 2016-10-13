import asyncdispatch
import asyncfile
import docopt
import marshal
import os
import sequtils
import strutils
import tables
import times

import docopt
import eternity
import host
import inifiles
import linux
import netutils
import oui
import ui


################################################################################
const NAME = "netwatch"
const VERSION = "1.0.0"
const CONFIG_FILE_PATH = "~"/".config"/"netwatch.ini"
const DOC = """
$1 $2 - live display of hosts seen in your network

Usage:
    $1 [-n <net>] [(-s <secs> | -S <secs>)] [-c <file>] [--passive]
    $1 (-h | --help)
    $1 (-v | --version)

Options:
    -n --network=<net>         Network to monitor in CIDR notation (e.g. 192.168.1.1/24)
    -s --scan-rate=<secs>      Seconds between scanning each host [default: 1]
    -S --scan-interval=<secs>  Total seconds between a full network scan
    -p --passive               Don't actively scan the network, only listen [default: False]
    -c --config=<file>         Ini file mapping labels to MAC addresses [default: $3]

    -h --help                  Show this screen.
    -v --version               Show version.

If --scan-interval is used a scan rate is calculated based on the number of
hosts in the network (number of hosts / scan interval = scan rate).
""".format( NAME, VERSION, CONFIG_FILE_PATH )


################################################################################
template `.`( args: Table[string, Value], key: string ): string =
    let x = $args["--" & key.replace("_", "-")]
    if x == "nil": "" else: x

proc select_network_interface( network: string ): Interface
proc prompt_for_default( interface_list: seq[Interface] ): int
proc sniffer_loop( host_table: OrderedTableRef[string, Host],
                   header: string,
                   mapping: OrderedTableRef[string, string] ) {.async.}

proc load_config_data( path: string ): IniFile
proc save_config_data( ini: IniFile,
                       host_table:OrderedTableRef[string, Host],
                       default_network: string  )


################################################################################
proc main() {.async.} =
    let start_time = epochTime()

    let args = docopt( DOC, version=VERSION )

    if has_needed_permissions() == false:
        echo( "You must run with superuser permissions." )
        quit( 1 )

    let ini = load_config_data( args.config )

    var network = if args.network != "": args.network
                  else: ini.find( "config", "default_network" )
    var iface = select_network_interface( network )
    # Correct CIDR network using data from interface
    network = network_for_interface( iface )

    let passive = parseBool( args.passive )
    let header = if passive: "Listening to $#..." % network
                 else: "Scanning $#..." % network
    var host_table = newOrderedTable[string, Host]()

    asyncCheck sniffer_loop( host_table, header, ini[network] )

    if not passive:
        let scan_rate = if args.scan_interval == "": parseFloat( args.scan_rate )
                        else: parseFloat( args.scan_interval ) / num_hosts( network ).float
        asyncCheck scan_network( network, iface, scan_rate )

    asyncCheck check_for_resize( host_table, header )

    await input_loop( host_table, header )

    save_config_data( ini, host_table=host_table, default_network=network  )

    echo( "Exiting - ran for $#." % humanize_max( epochTime() - start_time ) )
    quit( 0 )


proc select_network_interface( network: string ): Interface =
    let interface_list = interfaces()
    if network != "":
        result = interface_for_network( network, interface_list )

    # If the network was nil or we didn't find an interface for the network provided
    if result.name == nil:
        result = if len(interface_list) == 1: interface_list[0]
                 else: interface_list[ prompt_for_default( interface_list ) ]


proc prompt_for_default( interface_list: seq[Interface] ): int =
    var lines = newSeqOfCap[string]( len( interface_list ) )
    for i, iface in interface_list:
        lines.add(" $1. $2/$3 ($4)" % [$(i+1), iface.address, $netmask_to_cidr(iface.netmask), iface.name])

    result = prompt_table( header="\nPlease select a default interface to monitor:",
                           body=lines.join("\n"),
                           footer="Type the number of your choice" )


proc sniffer_loop( host_table: OrderedTableRef[string, Host],
                   header: string,
                   mapping: OrderedTableRef[string, string] ) {.async.} =
    let listener = setup_listener()

    var old_table = ""
    while true:
        let (mac_address, ip_address) = await get_new_host( listener )

        var host = host_table.mgetOrPut( mac_address, Host( label:"", mac:mac_address ) )
        host.ip = ip_address
        host.last_seen = getTime()
        let key = parseHexInt(mac_address.replace(":", "")[..5])
        host.oui = if key in oui_table: oui_table[key] else: ""
        if mapping != nil and host.label == nil or host.label == "":
            host.label = mapping.getOrDefault( mac_address )

        let table_string = render_table( host_table )
        if table_string != old_table:
            draw_table( table_string, header )
            old_table = table_string


proc load_config_data( path: string ): IniFile =
    result = newIniFile()
    let ini_file = expandTilde( path )
    let loaded_ok = result.loadIni( ini_file )
    if not loaded_ok and fileExists( ini_file ):
        echo( "\nWARNING: Could not load config file at: $1\n" % ini_file )
        echo( "Would you like to continue running netwatch?\n")
        let proceed = prompt( "If you select 'y' netwatch will attempt to " &
                              "replace the config file with new data",
                              default=false )
        if not proceed:
            quit(0)

    return result


proc save_config_data( ini: IniFile,
                       host_table:OrderedTableRef[string, Host],
                       default_network: string  ) =

    ini["config"]["default_network"] = default_network

    var mapping = ini[default_network]
    for mac, host in host_table:
        let label_is_empty = host.label == nil or host.label.strip() == ""

        if not label_is_empty:
            mapping[mac] = host.label

        elif label_is_empty and mapping.hasKey(mac):
            mapping.del(mac)

    writeFile( ini.filename, $ini )


################################################################################
when isMainModule:
    asyncCheck main()
    runForever()
