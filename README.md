# NetPortDart
Dart implementation of a serial to tcp wedge.

Connect an RS-232 serial device to a TCP Server Socket bi-directionally.

Dart dependency is "libserialport"

This is a straighforward (read "un-polished") example to send all data from the
serial port to the TCP server's connected client TCP socket.

One could do the same with UDP or Domain sockets as well.
