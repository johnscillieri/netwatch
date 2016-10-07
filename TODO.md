# TODO

## Future Work

In rough priority order I guess...

  * Implement a non-root mode (no raw socket or ARP scanning)
      * TCP connect or ping scan when in active mode
      * Poll ARP table
  * OS X support
  * Windows support
  * Handle large host tables better (e.g. a whole /24 shows up)
    * Allow smaller CIDR networks to be used?
    * Allow specification of a range? (how does this change default_network?)
  * Should we resolve DNS names if the host is unlabeled?
      * Color blue if unlabeled
  * Should we alert on an IP address change?
      * Store list of last 10 changes w/time?
      * e.g. Serenity changed from 1.2.3.4 to 1.2.3.5 on 6/9 @ 12:45
  * Split the view to show logs of events?
