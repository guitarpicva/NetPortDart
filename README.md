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

TODO: Needs a watchdog on the serial connection to re-make the link
if it fails or goes away.

To start the program, call the resulting compiled filename with up to two parameters.
See the main() function for more explanation and defaults.

0) serial port name.  COM5 or ttyACM0, etc. (no path to *nix devices)
1) TCP port to listen on for the TCP Server side
