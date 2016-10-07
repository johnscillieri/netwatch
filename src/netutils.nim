import math
import nativesockets
import net
import posix
import strutils

type MAC* = array[ 6, uint8 ]

converter to_mac*( parts: array[6, int] ): MAC =
    [ parts[0].uint8, parts[1].uint8,
      parts[2].uint8, parts[3].uint8,
      parts[4].uint8, parts[5].uint8 ]

proc `$`*( address: MAC ): string =
    result = "$1:$2:$3:$4:$5:$6".format( address[0].int.toHex(2),
                                         address[1].int.toHex(2),
                                         address[2].int.toHex(2),
                                         address[3].int.toHex(2),
                                         address[4].int.toHex(2),
                                         address[5].int.toHex(2) ).tolower()

proc InAddr*( ip_address: string ): InAddr =
    InAddr(s_addr:inet_addr(ip_address))

proc `+`*( addr1, addr2: InAddr ): InAddr =
    result = InAddr( s_addr:( addr1.s_addr + addr2.s_addr ) )

proc `+`*( addr1: InAddr, x: int ): InAddr =
    result = InAddr( s_addr:( addr1.s_addr + InAddrScalar(htonl(x.uint32)) ) )

proc `and`*( addr1: InAddr, addr2: InAddrT ): InAddr =
    result = InAddr( s_addr:( addr1.s_addr and addr2 ) )

proc `and`*( addr1: InAddrT, addr2: InAddr ): InAddr =
    result = addr2 and addr1

proc `<=`*( addr1: InAddr, addr2: InAddr ): bool =
    result = ntohl(addr1.s_addr) <= ntohl(addr2.s_addr)

proc `not`*( in_addr: InAddr ): InAddr =
    result = InAddr( s_addr:not in_addr.s_addr )

proc `$`*( in_addr: InAddr ): string =
    result = $inet_ntoa( in_addr )

proc cidr_to_netmask*( prefix: range[0..32] ): InAddr =
    let mask = 0xffffffff shl (32 - prefix)
    result = InAddr( s_addr: htonl( mask.uint32 ) )

proc netmask_to_cidr*( netmask: string ): int =
    let mask_addr = inet_addr( netmask )
    let num_hosts = (not ntohl(mask_addr)).int64 + 1.int64
    result = 32 - log2( num_hosts.float64 ).int

proc network_address*( cidr_address: string ): InAddr =
    let pair = cidr_address.split("/")
    let address = inet_addr( pair[0] )
    let netmask = cidr_to_netmask( parseInt( pair[1] ) )
    result = address and netmask

proc netmask*( cidr_address: string ): InAddr =
    let pair = cidr_address.split("/")
    result = cidr_to_netmask( parseInt( pair[1] ) )

proc num_hosts*( cidr_address: string ): int =
    result = 2^( 32 - parseInt( cidr_address.split("/")[1] ) )

iterator hosts*( cidr_address: string ): string =
    let start = network_address( cidr_address )
    # Don't include the network & broadcast address
    # (thats why it goes from 1 to -2)
    for offset in 1..num_hosts( cidr_address )-2:
        yield $(start + offset)

proc `in`*( ip: InAddr, cidr_address: string ): bool =
    let network = cidr_address.network_address
    let broadcast = network + (cidr_address.num_hosts - 1)
    return ip >= network and ip <= broadcast


###############################################################################
type Interface* = object of RootObj
    name*: string
    address*: string
    broadcast*: string
    netmask*: string
    mac*: MAC


type ifaddrs = object
    pifaddrs: ref ifaddrs # Next item in list
    ifa_name: cstring # Name of interface
    ifa_flags: uint   # Flags from SIOCGIFFLAGS
    ifa_addr: ref SockAddr_in  # Address of interface
    ifa_netmask: ref SockAddr_in # Netmask of interface
    ifu_broadaddr: ref SockAddr_in # Broadcast address of interface
    ifa_data: pointer # Address-specific data


var AF_INET* {.importc, header: "<sys/socket.h>".}: cint
var IFF_UP* {.importc, header: "<net/if.h>".}: cint
var IFF_LOOPBACK* {.importc, header: "<net/if.h>".}: cint
var SIOCGIFHWADDR* {.importc, header: "<sys/socket.h>".}: cint


proc getifaddrs( ifap: var ref ifaddrs ): int
    {.header: "<ifaddrs.h>", importc: "getifaddrs".}


proc freeifaddrs( ifap: ref ifaddrs ): void
    {.header: "<ifaddrs.h>", importc: "freeifaddrs".}


proc `$`( address: ref Sockaddr_in ): string =
    if address == nil:
        result = ""
    else:
        result = $inet_ntoa( address.sin_addr )


proc mac_address*( adapter_name: string ): MAC =
    type ifreq = object
        ifr_name: array[16, char]
        ifru_hwaddr: SockAddr

    let s = newSocket();
    var data: ifreq
    var name = newString( 16 )
    name = adapter_name
    copyMem(addr data.ifr_name, addr( name[0] ), len( adapter_name ) )
    let ret_code = ioctl(FileHandle(s.getfd), SIOCGIFHWADDR.uint, addr data)
    close(s)

    if ret_code != -1:
        copyMem( addr result[0], addr data.ifru_hwaddr.sa_data, sizeof(MAC) )


proc interfaces*(): seq[Interface] =
    var interfaces : ref ifaddrs
    var current : ref ifaddrs
    let ret_code = getifaddrs( interfaces )
    if ret_code == -1:
        echo( "getifaddrs error: ", strerror( errno ) )
        return nil

    current = interfaces

    result = newSeq[Interface]()
    while current != nil:
        let interface_up = (current.ifa_flags and IFF_UP.uint) > 0.uint
        let is_inet4 = current.ifa_addr.sin_family == AF_INET
        let is_not_loopback = (current.ifa_flags and IFF_LOOPBACK.uint) == 0
        if interface_up and is_inet4 and is_not_loopback:
            result.add( Interface( name: $current.ifa_name,
                                   address: $current.ifa_addr,
                                   broadcast: $current.ifu_broadaddr,
                                   netmask: $current.ifa_netmask,
                                   mac: mac_address( $current.ifa_name ) ) )

        current = current.pifaddrs

    freeifaddrs( interfaces )


proc network_for_interface*( iface: Interface ): string =
    let cidr_range = netmask_to_cidr( iface.netmask )
    let net_addr = network_address( iface.address & "/" & $cidr_range )
    result = $net_addr & "/" & $cidr_range


proc interface_for_network*( network: string, interface_list: seq[Interface] ): Interface =
    var safe_network = network
    if len( safe_network.split("/") ) == 1:
        safe_network &= "/24" # default to a /24
    let cidr_range = safe_network.split("/")[1].strip()
    let net_addr = network_address( safe_network )
    let real_network = $net_addr & "/" & cidr_range
    for i in interface_list:
        if InAddr(i.address) in real_network:
            return i


################################################################################
when isMainModule:

    let address = "192.168.1.0/24"

    for iface in interfaces():
        echo( iface )
        let in_network = InAddr(iface.address) in address
        echo( "Address $1 in range $2: $3" % [iface.address, address, $in_network] )
    echo( "" )

    let net_addr = network_address( address )
    let mask = netmask( address )
    echo( net_addr, " / ", mask )
    let max_ip = not mask + net_addr
    echo( max_ip )
    echo( "" )

    for i in 0..32:
        let mask = cidr_to_netmask( i )
        echo( i, ": ", mask, " - ", netmask_to_cidr( $mask ) )
    echo( "" )

    for host in hosts( address ):
        echo( host )
