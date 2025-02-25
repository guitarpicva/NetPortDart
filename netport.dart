import 'package:libserialport/libserialport.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

late SerialPort _modem;
late ServerSocket _ss;
late Socket _tcp;
String serBuffer = '';
bool bNetConnected = false;
void main(List<String> arguments) {
  //print('NetPort!');
  
  /// create the socket/serial connections and set up handlers
  
  var serial = 'ttyACM0'; // default
  if(arguments.isNotEmpty) {
    serial = arguments.first;
    //print("serial:$serial");
  }
  var port = '19798'; // default
  if(arguments.length > 1) {
    port = arguments.elementAt(1);
    //print("port: $_port");
  }
  startTcpServer(int.parse(port));  
  getModem(serial);
}

/// Start the server process to listen on the any
/// ip address.
/// Automatically starts the client socket handler upon
/// new connection (one connection only)
Future<ServerSocket> startTcpServer(int port) async {
  var ss =
      await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
  _ss = ss;
  _ss.listen((client) {
    getTcp(client);
  });
  print('Server Socket started on port: $port');
  return ss;
}

Future<void> getModem(String address) async {
    try {
      bool open = false;
      var spc = SerialPortConfig();
      // seems to work fine at this speed, but slower also works
      spc.baudRate = 115200; 
      spc.bits = 8;
      spc.parity = 0;
      spc.stopBits = 1;
      spc.setFlowControl(SerialPortFlowControl.none);
      if (Platform.isLinux || Platform.isMacOS) {
        print('Linux Radio: $address');
        if(address.startsWith("/dev/")) {
          address = address.substring(5);
        }
        _modem = SerialPort('/dev/$address'); // i.e. ttyACM0
        open = _modem.openReadWrite();
        _modem.config = spc;        
      } else {
        // essentially Windows is the only other viable candidate ATM
        print('Windows Radio: $address');
        _modem = SerialPort(address); // i.e. COM23
        open = _modem.openReadWrite();   
        spc.dtr = 1; // Windows is weird
        _modem.config = spc;        
      }      
      if (open) {
        print("$address: OPEN!");
        final reader = SerialPortReader(_modem);
        reader.stream.listen((data) {
          handleSerialPortData(data);
        });
      } 
      else {
        print("$address: NOT OPEN!");
        _modem.dispose();
      }
    } catch (se) {
      // connection to radio failed, so
      // tell the UI to open the configuration Drawer
      print('SerialException: ${se.toString()} addr:$address');      
    }
    return; // _modem;
  }

/// Write Serial port data to the TCP Socket
Future<void> handleSerialPortData(Uint8List lines) async {
  print("TCP: ${String.fromCharCodes(lines)}");
  if(bNetConnected) {
    _tcp.write(String.fromCharCodes(lines)); // for String data
    // or _tcp.write(lines); // for binary data
    await _tcp.flush();
  }
}

/// Write TCP data to the Serial Port
Future<void> handleTCPPortData(Uint8List lines) async {
  print("Serial: ${String.fromCharCodes(lines)}");
  if(_modem.isOpen) {
    _modem.write(lines);
    _modem.drain();
  }
}

void getTcp(Socket client) {
    _tcp = client;
    _tcp.setOption(SocketOption.tcpNoDelay, true);
    bNetConnected = true;
    //String controlBuffer = '';
    print('Control client connected...');
    client.listen((Uint8List data) async {
        handleTCPPortData(data);            
    },
    cancelOnError: false,
    onError: (error) {
      print('Control client error: $error');
    },
    onDone: () {
      print('Control client finished...');
      client.close();
      bNetConnected = false;
    });
  }