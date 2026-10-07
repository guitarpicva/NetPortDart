# NetPortDart
Dart implementation of a serial to tcp wedge.

Connect an RS-232 serial device to a TCP Server Socket bi-directionally.

NOTE: This has been adjusted to ONLY function for CRLF delimited lines
for ASCII text.  If you need to deal with binary serial data, then
adjust handleSerialPortData() and/or handleTCPPortData() functions accordingly.

Dependency is "libserialport-dev" (Debian, etc.) or the Windows libserialport.dll library.

This is a straighforward example to send all data from the
serial port to the TCP server's connected client TCP socket (and back!).

A UDP implementation is shown in dgport.dart.

To start the program, call the resulting compiled filename with up to three parameters.
See the main() function for more explanation and defaults.

0) serial port name.  COM5 or ttyACM0, etc. (ttyACM0 def. and no path to *nix devices)
1) serial port baud rate (def. 115200, or 57600, etc, etc.) with 8N1 No Flow Control params
2) TCP port to listen on for the TCP Server side (19790 def.)
