# Netwatch

[![Build Status](https://travis-ci.org/johnscillieri/netwatch.svg?branch=master)](https://travis-ci.org/johnscillieri/netwatch)

A simple and efficient network monitor to display a live table of
hosts in your network.

Netwatch can run passively (only _watching_ for new hosts) or it can actively
scan (the default) to ensure you don't miss a single machine.

## Download

The latest release of netwatch is 1.0.0.

[Click here to download!](https://github.com/johnscillieri/netwatch/releases/download/v1.0.0/netwatch)

## Why netwatch?

I wanted a tool that cleanly shows all the devices in my network and the last
time they were seen. I also wanted to label the hosts in the table so that as
they drop on and off the network I only had to identify them once.

I didn't want to rely on updated external configurations like DNS names for
labels (names like android-ajs14kja2lskd aren't helpful...) or separate tools
like nmap for scanning.

Hitting refresh on my router's host table wasn't a good option either (ain't
nobody got time for that).

## Usage

    ./netwatch -h

    netwatch 1.0.0 - live display of hosts seen in your network

    Usage:
        netwatch [-n <net>] [(-s <secs> | -S <secs>)] [-c <file>] [--passive]
        netwatch (-h | --help)
        netwatch (-v | --version)

    Options:
        -n --network=<net>         Network to monitor in CIDR notation (e.g. 192.168.1.1/24)
        -s --scan-rate=<secs>      Seconds between scanning each host [default: 1]
        -S --scan-interval=<secs>  Total seconds between a full network scan
        -p --passive               Don't actively scan the network, only listen [default: False]
        -c --config=<file>         Ini file mapping labels to MAC addresses [default: ~/.config/netwatch.ini]

        -h --help                  Show this screen.
        -v --version               Show version.

To start, run:

    sudo ./netwatch

Currently netwatch needs to be run via sudo because it uses raw sockets for its
active and passive scanning.

On your first run if you don't specify a network and you have more than one
network interface, you'll be prompted with a menu like this:

    Please select a default interface to monitor:

    1. 192.168.1.6/24 (eth0)
    2. 172.17.0.1/16 (docker0)

    Type the number of your choice (1) >

Once you choose a network (or if you only have one), the main netwatch U/I will
display and hosts will begin appearing:

    Scanning 192.168.1.0/24...

       Label         IP Address      MAC Address         OUI           Last Seen
    1. Router        192.168.1.1     00:7f:28:c2:e5:af   Actiontec     <1m
    2. Serenity      192.168.1.6     00:24:e8:00:06:b6   Dell          <1m
    3.               192.168.1.23    ec:1a:59:ea:4b:6d   Belkin        <1m
    4. IP-STB1       192.168.1.100   f4:5f:d4:20:c9:c4   Cisco SPVTG   3m

    Press 1-4 to assign a label. Press q to quit.

Press the number next to the device to label that device.

To speed up or slow down the scanning use the `--scan-rate` option. A
`--scan-rate=5` for example means one packet will go out every 5 seconds looking
for the next host in the network.

If you'd rather think in terms of your whole network (say you want to scan the
whole /24 network every minute), netwatch provides the convenience option
`--scan-interval` to do so. Using a `--scan-interval=60` for example means
netwatch will ensure the whole network gets scanned every 60 seconds. A
`--scan-interval=60` equates to using a `--scan-rate=0.24` for the /24 in
this example without you having to do the math.

The `--passive` flag is useful for cases where you don't want to actively scan
your network (say in a corporate environment where you're not the security guy
or where you're using another scanning tool already) but still want the pretty
table and host labeling of netwatch.

## How it works

Netwatch creates a raw socket, listens for ARP packets, and records the sender
MAC & IP address. When actively scanning it also continuously sends out ARP
request packets for hosts in the provided network. This allows netwatch to see
hosts blocking ICMP (everybody's got to ARP) but it also means it won't see
hosts outside its gateway router. In the future I might look into adding other
active and passive protocols (ICMP, DNS, mDNS, etc) if there's interest.

### netwatch.ini

Device labels are stored in a file called `netwatch.ini` that looks basically
like this:

    [192.168.1.0/24]
    00:24:e8:00:f0:0b = Serenity
    00:24:e8:00:ff:fe = TV STB

    [172.17.0.0/16]

    [config]
    default_network = 192.168.1.0/24


By default this file is stored in `~/.config/netwatch.ini` unless specified on
the command line. That file is rewritten with the current labels when netwatch
exits.

The config section currently has only one entry `default_network`. This stores
the last monitored network and is read as the default if `--network` isn't
provided on the command line.

### OUI Lookup

The OUI database (built into netwatch) comes from:

    http://linuxnet.ca/ieee/oui/nmap-mac-prefixes

Big thanks to everyone at linuxnet.ca, you are awesome!

## Installing netwatch

Just download and copy it somewhere in your path. It's a stand-alone static
binary so it should run from anywhere.

## Building netwatch

### Requirements

* Docker (for the Alpine Linux + Nim build environment)
* make
* UPX (for packing the release builds)

### Build Targets

* `make` - make all targets including stripped & UPX-packed final release
* `make release` - build the release version (not stripped or UPX-packed)
* `make debug` - build a debug version of netwatch
* `make docker` - build the Docker build environment

You can pass a `-j2` to speed things up a little, but it's mostly to make
`debug` and `release` build at the same time. Nim doesn't support parallelized
builds at the moment (that I know of).

## License

netwatch - Copyright (C) 2016  John Scillieri

See the LICENSE.txt file for more information.


