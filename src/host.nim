import strutils
import times


################################################################################
type Host* = ref object of RootObj
    label*: string
    ip*: string
    mac*: string
    oui*: string
    last_seen*: Time

proc `$`*( h: Host ): string =
    "$#: $# ($#)" % [h.label, h.ip, h.mac]

