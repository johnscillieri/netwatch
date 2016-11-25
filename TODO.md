# TODO

## v1.2.0
* Fix packet filter to actually use subnet mask
* Don't change user-supplied network range to broadest possible for interface
* Handle large host tables better (e.g. when a whole /24 shows up)
  * Allow smaller CIDR networks to be specified?
  * Allow specification of a range? (how does this change default_network?)

## Future Work

In rough priority order I guess...

  * Implement a non-root mode (no raw socket or ARP scanning)
      * TCP connect or ping scan when in active mode
      * Poll ARP table
  * OS X support
  * Windows support
  * Should we alert on an IP address change?
      * Store list of last 10 changes w/time?
      * e.g. Serenity changed from 1.2.3.4 to 1.2.3.5 on 6/9 @ 12:45
  * Split the view to show logs of events?
