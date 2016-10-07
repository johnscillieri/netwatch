import asyncnet
import asyncdispatch
import net
import nativesockets
import posix
import strutils
import tables
import times

import host
import netutils


################################################################################
var AF_PACKET* {.importc, header: "<sys/socket.h>".}: cint
var SO_ATTACH_FILTER* {.importc, header: "<sys/socket.h>".}: cint
var ETH_P_ALL* {.importc, header: "<netinet/if_ether.h>".}: uint16
var ETH_P_ARP* {.importc, header: "<netinet/if_ether.h>".}: uint16
var ETH_P_IP* {.importc, header: "<netinet/if_ether.h>".}: uint16


################################################################################
type Ethernet {.packed.} = object
    dest: MAC
    source: MAC
    eth_type: uint16

type Arp {.packed.} = object
    htype: uint16
    ptype: uint16
    hlen: uint8
    plen: uint8
    oper: uint16
    # addresses
    sender_ha: MAC
    sender_pa: InAddr
    target_ha: MAC
    target_pa: InAddr

proc bytes[T]( packet: var T ): string =
    result = newString( sizeof( packet ) )
    copyMem( addr(result[0]), addr packet, sizeof( packet ) )

type SockAddr_ll* = object
    family: uint16
    protocol: uint16
    ifindex: uint32
    hatype: uint16
    pkttype: uint8
    halen: uint8
    `addr`: array[8, uint8]

type sock_filter = object
    code: uint16 # Filter code
    jt: uint8    # Jump true
    jf: uint8    # Jump false
    k: uint32    # Generic multi-use field

type sock_fprog = object
    len: uint16  # Number of filter blocks
    filter: ptr sock_filter


################################################################################
proc has_needed_permissions*(): bool =
    result = geteuid() == 0


proc attach( socket: SocketHandle, filter: var openarray[sock_filter] ): bool =
    ## Attach a BPF filter to a socket
    var filter_prog = sock_fprog( len:filter.len.uint16, filter:addr filter[0] )

    let set_ok = setsockopt( socket,
                             SOL_SOCKET,
                             SO_ATTACH_FILTER,
                             addr filter_prog,
                             sizeof(filter_prog).cuint )
    result = set_ok != -1


proc setup_listener*(): AsyncFD =
    var socket = newNativeSocket( domain=AF_PACKET,
                                  sockType=nativesockets.SOCK_RAW.cint,
                                  protocol=htons(ETH_P_ALL).cint )

    if socket == InvalidSocket:
        echo( "Got an error trying to create the raw socket: ",
              strerror( errno ) )
        quit( 1 )

    var filter = @[
        sock_filter( code:0x28, jt:0, jf:0, k:0x0000000c ),
        sock_filter( code:0x15, jt:0, jf:1, k:0x00000806 ),
        sock_filter( code:0x6, jt:0, jf:0, k:0x00040000 ),
        sock_filter( code:0x6, jt:0, jf:0, k:0x00000000 ),
    ]

    if not socket.attach( filter ) :
        echo( "Got an error trying to add the ARP filter to the raw socket: ",
              strerror( errno ) )
        close( socket )
        quit( 1 )

    result = socket.AsyncFD
    result.SocketHandle.setBlocking(false)
    register(result)


proc get_new_host*( socket: AsyncFD ): Future[tuple[mac_addr:string, ip_addr:string]] {.async.} =
    let buffer_size = sizeof( Ethernet ) + sizeof( Arp )

    var data = await socket.recv( buffer_size )
    # echo( "Got $1 bytes" % $data.len )

    let eth_packet = cast[ptr Ethernet](addr data[0])
    if  eth_packet.eth_type != htons( ETH_P_ARP ):
        echo( "Received wrong ethernet type: $1" % eth_packet.eth_type.int.toHex(4) );

    let arp_packet = cast[ptr Arp](addr data[sizeof(Ethernet)])
    let mac_address = $arp_packet.sender_ha
    let ip_address = $arp_packet.sender_pa
    result = ( mac_address, ip_address )



proc scan_host( host: string, handle: SocketHandle, sa_ll: ptr SockAddr, iface: Interface ) {.async.} =
    let broadcast_mac = [ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff ]
    var eth_packet = Ethernet( dest:broadcast_mac,
                               source:iface.mac,
                               eth_type:htons(ETH_P_ARP) )
    var arp_packet = Arp( htype: nativesockets.htons( 1.uint16 ),
                          ptype: nativesockets.htons( ETH_P_IP ),
                          hlen: 6,
                          plen: 4,
                          oper: nativesockets.htons( 1.uint16 ),
                          sender_ha: iface.mac,
                          sender_pa: InAddr( s_addr:inet_addr( iface.address ) ),
                          target_ha: [0, 0, 0, 0, 0, 0],
                          target_pa: InAddr( s_addr:inet_addr( host ) ) )

    var packet = eth_packet.bytes & arp_packet.bytes
    let send_result = handle.sendto( addr(packet[0]), len(packet), 0,
                                     sa_ll, Socklen(sizeof(SockAddr_ll)) )
    if send_result == -1:
        echo( "Error: ", strerror(errno) )
        quit( 1 )


proc scan_network*( network: string, iface: Interface , scan_rate: float ) {.async.} =
    var socket = newNativeSocket( domain=AF_PACKET,
                                  sockType=nativesockets.SOCK_RAW.cint,
                                  protocol=htons(ETH_P_ARP).cint )

    if socket == InvalidSocket:
        echo( "Got an error trying to create the raw socket: ", strerror( errno ) )
        quit( 1 )

    let asyncFD = socket.AsyncFD
    let handle = asyncFD.SocketHandle
    handle.setBlocking(false)
    register(asyncFD)

    var sa_ll = SockAddr_ll( family:AF_PACKET.uint16,
                             protocol: htons(ETH_P_ARP),
                             ifindex: if_nametoindex( iface.name ).uint32 )
    let addr_ptr = cast[ptr SockAddr](addr sa_ll)

    while true:
        for host in hosts( network ):
            asyncCheck scan_host( host, handle, addr_ptr, iface )
            await sleepAsync( int( scan_rate * 1000 ) )


################################################################################
proc main() {.async.} =
    let network = "192.168.1.2/27"
    let iface = interface_for_network( network, interfaces() )
    await scan_network( network, iface, 10 )
    quit( 0 )


when isMainModule:
    asyncCheck main()
    runForever()
