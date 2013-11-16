# What does it do?

Serves DNS zone files over [Multicast DNS](http://tools.ietf.org/html/rfc6762).


# How does it do it?

A UDP server built atop [CoreNetworking](http://github.com/keithduncan/CoreNetworking).


# What does it even meme?

Allows you to inject DNS responses into the Bonjour Multicast DNS server on your
local network using a zone file.

Configuration is handled by the `DNS_ZONE_FILE` environment variable. This
should be the path to a single zone file or to a directory of zone files.

The server can then be queried over multicast using [dns-sd](x-man-page://dns-sd).

The shared scheme included in the project serves the db.example.local. zone
which includes A and AAAA records for the example.local. host, these can be
queried using `dns-sd -G v4v6 example.local.`.

If you actually want to run this (why would you want to run this?) I'd recommend
using a [launchd](x-man-page://launchd.plist) job.


# Who even writes a DNS server?

Who doesn’t write a DNS server.
