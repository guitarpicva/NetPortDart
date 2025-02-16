# NetPortDart
Dart implementation of a serial to tcp wedge.

Connect an RS-232 serial device to a TCP Server Socket bi-directionally.
NOTE: in Linux the libserialport0 package should be installed (Debian and
derivatives) and a proper symlink created from /lib/x86_64-linux-gnu/libserialport.so
to the file /lib/x86_64-linux-gnu/libserialport.so.0.1.0
~~~
cd /lib/x86_64-linux-gnu
sudo ln -s libserialport.so libserialport.so.0.1.0
~~~
Dart dependency is "libserialport"

This is a straighforward (read "un-polished") example to send all data from the
serial port to the TCP server's connected client TCP socket (and back!).

One could do the same with UDP or Domain sockets as well.
