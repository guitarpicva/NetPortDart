import 'dart:async';
// import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:libserialport/libserialport.dart';

late SerialPort _serial;
late ServerSocket _ss;
late Socket _tcp; // single TCP connection allowed by default
bool bNetConnected = false;
/// TCP port number for the network side
int _port = 19790;
/// Input buffer FROM the serial port
String indata = '';

/// netport connects to a named serial device and transfers all data bi-directionally
/// to a TCP server socket.  Typical use case would be on a host which needs
/// data to flow to a container where Docker host networking is not available.
/// 
/// Optional input parameters are:
/// 1. serial port file - def. ttyACM0
/// 2. serial port speed (baud) [only 8N1 no flow control] - def. 115200
/// 3. TCP server socket port number - def. 19790
void main(List<String> arguments) async {  
  /// create the socket/serial connections and set up handlers  
  var serial = 'ttyACM0';
  if(arguments.isNotEmpty) {
    serial = arguments.first;
    //print("serial:$serial");
  }
  var speed = 115200; // default
  if(arguments.length > 1) {
    speed = int.parse(arguments.elementAt(1));
  }
  // _port = 19790; // default
  if(arguments.length > 2) {
    _port = int.parse(arguments.elementAt(2).toString());
    // print("port: $_port");
  }  
  // connect to the serial first. if no serial,
  // can decide whether or not to proceed or fail with error
  await getSerial(serial, speed);
  // start the TCP server socket to handle one client
  // connection.
  await startTcpServer(_port);  
  Timer.periodic(Duration(seconds:10), (t) { watchDog(serial, speed); });
}

/// Use watchDog() to check the serial connection and
/// re-establish if necessary.
void watchDog(String serial, int speed){ 
  // print('Watchdog...'); 
  try{
    if(_serial.isOpen) { return; }
    else {
      // try to re-connect to the serial device
      print('Re-connect to serial...');
      getSerial(serial, speed);
    }  
  }
  catch(sererr) {
    print(sererr.toString());
    getSerial(serial, speed);
  }
}

/// Start the server process to listen on the any ip address.
/// Automatically starts the client socket handler upon
/// new connection (one connection only).
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// Consider limiting this to the Docker IP space if
// used for Docker.  NetPort would live on the host
// machine, in order to link the ASCII port into
// a running container via a TCP socket.
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
Future<ServerSocket> startTcpServer(int port) async {
  var ss =
      await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
  _ss = ss;
  _ss.listen((client) {
    getTcp(client);
  });
  // print('Server Socket started on port: $port');
  return ss;
}

Future<void> getSerial(String address, int speed) async {
  try {
    bool open = false;
    var spc = SerialPortConfig();
    // seems to work fine at this speed, but slower also works
    spc.baudRate = speed; 
    spc.bits = 8;
    spc.parity = 0;
    spc.stopBits = 1;
    spc.setFlowControl(SerialPortFlowControl.none);
    if (Platform.isLinux || Platform.isMacOS) {
      // print('Linux Port: $address');
      // This seems silly to remove the path then put it back on, 
      // but I think there may be different paths for MacOS that don't conform
      // to '/dev/', so this is where to make that work.
      if(address.startsWith("/dev/")) {
        address = address.substring(5);
      }
      _serial = SerialPort('/dev/$address'); // i.e. ttyACM0
      // END This seems silly
      open = _serial.openReadWrite();
      _serial.config = spc;        
      spc.dtr = 1; // Windows is weird
    } 
    else {
      // essentially Windows is the only other viable candidate ATM
      // print('Windows Port: $address');
      _serial = SerialPort(address); // i.e. COM23
      open = _serial.openReadWrite();   
      spc.dtr = 1; // Windows is weird
      _serial.config = spc;        
    }      
    if (open) {
      // print("$address: OPEN!");
      final reader = SerialPortReader(_serial);
      reader.stream.listen((data) async {
        handleSerialPortData(data);
      },
      onError: (error) {
            print('Serial Port Error: ${error.toString()}');
            // Close the reader and serial port and re-open later to recover
            reader.close();
            _serial.close();
            Timer(const Duration(seconds: 2), () {
              getSerial(address, speed);
            });
          },
      onDone: (){
        print('Serial Port Done');
        reader.close();
        _serial.close();
      },
      cancelOnError: false
      );
              
    } 
    else {
      print("$address: NOT OPEN!");
      _serial.dispose();
    }
    spc.dispose();
  } 
  catch (se) {
    // connection to radio failed, so mayvbe tell a UI to open the configuration
    print('$address - SerialException: ${se.toString()}');   
    print("$address: NOT OPENED!");   
  }
  return;
}

/// Write Serial port data to the TCP Socket. but only if
/// a client is currently connected.
Future<void> handleSerialPortData(Uint8List data) async {
  // print("Serial: ${String.fromCharCodes(data)}");  
  // gather data from the serial buffer
  indata += String.fromCharCodes(data as List<int>);
  // Wait until at least a full line has arrived, but this is not REQUIRED
  // each read could be handled since it's simply a stream of data from one
  // port to the other.

  // In this line based case, send only the fully received lines, saving
  // and partial lines for their final parts.
  if(!indata.contains('\r\n')) { 
    return;
  }
  // gather only the whole lines including the line end CRLF
  final idx = indata.lastIndexOf('\r\n') + 2;
  var sdata = indata.substring(0, idx);
  // remove the whole lines from the global data buffer
  indata = indata.substring(idx);
  // Split the resulting list of lines on CRLF
  var lines = sdata.split('\r\n');    
  // Process each line adding back the CRLF to the datagram
  for(final line in lines) {
    if(line.trim().isEmpty) { continue; }
    if(bNetConnected) {
      _tcp.write('${line.trim()}\r\n'); // Add back CRLF for String data
      await _tcp.flush();
    }
  }
  // ALTERNATE method, to pass all serial port data activity directly to the
  // TCP socket regardless of content.
  //_tcp.write(data.toList());
  //_tcp.flush();
  // END ALTERNATE method
}

void getTcp(Socket client) {
    _tcp = client;
    _tcp.setOption(SocketOption.tcpNoDelay, true);
    bNetConnected = true;
    print('TCP client connected...');
    _tcp.listen((Uint8List data) async {            
      handleTCPPortData(data);            
    },
    cancelOnError: false,
    onError: (error) {
      print('TCP client error: $error');
    },
    onDone: () {
      print('TCP client finished...');
      _tcp.close();
      bNetConnected = false;
    });
  }

/// Write TCP data to the Serial Port, but only if the
/// serial port is currently open.
Future<void> handleTCPPortData(Uint8List data) async {
  // A possible case for String data using the LineSplitter
  // LineSplitter ls = LineSplitter();
  // List<String> sls = ls.convert(String.fromCharCodes(data));
  // if(_serial.isOpen) {
  //   for(String s in sls) {
  //     _serial.write(s);
  //     _serial.drain();
  //    }
  // }
  // //print("TCP To Serial: ${String.fromCharCodes(data)}");
  // print('Line Splitter: $sls');
  // Otherwise, just senda ll data events through to the TCP socket
  if(_serial.isOpen) {
    _serial.write(data);
    _serial.drain();
  }
}
