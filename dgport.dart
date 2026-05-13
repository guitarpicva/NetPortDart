import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:libserialport/libserialport.dart';

late SerialPort _serial;
// late RawDatagramSocket _udp; // listener for UDP datagrams
bool bNetConnected = false;
int _port = 19790;
String indata = ''; // global serial buffer

/// netport connects to a named serial device and transfers all data bi-directionally
/// to a TCP server socket.  Typical use case would be on a host which needs
/// data to flow to a container.
/// 
/// Optional input parameters are:
/// 1. serial port file - def. ttyACM0
/// 2. serial port speed (baud) [only 8N1 no flow control] - def. 19798
/// 3. TCP server socket port number - def. 19798
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
  _port = 19790; // default
  if(arguments.length > 2) {
    _port = int.parse(arguments.elementAt(2).toString());
    // print("port: $_port");
  }  
  // connect to the serial first. if no serial,
  // can decide whether or not to proceed or fail with error
  await getSerial(serial, speed);
  await createUdpListener('127.0.0.1', _port);
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
      if(address.startsWith("/dev/")) {
        address = address.substring(5);
      }
      _serial = SerialPort('/dev/$address'); // i.e. ttyACM0
      open = _serial.openReadWrite();
      _serial.config = spc;        
      spc.dtr = 1; // Windows is weird
    } else {
      // essentially Windows is the only other viable candidate ATM
      // print('Windows Port: $address');
      _serial = SerialPort(address); // i.e. COM23
      open = _serial.openReadWrite();   
      spc.dtr = 1; // Windows is weird
      _serial.config = spc;        
    }      
    if (open) {
      print("$address: OPEN!");
      final reader = SerialPortReader(_serial);
      reader.stream.listen((data) {        
        handleSerialPortData(data);        
      },
      onError: (error) {
            print('Serial Port Error: ${error.toString()}');
            reader.close();
            _serial.close();
            // Timer(const Duration(seconds: 2), () {
            //   getModem(_serialAddress);
            // });
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
    // connection to radio failed, so
    // tell the UI to open the configuration Drawer
    print('$address - SerialException: ${se.toString()}');   
    print("$address: NOT OPENED!");   
  }
  return;
}

/// Write Serial port data to the TCP Socket. but only if
/// a client is currently connected.
Future<void> handleSerialPortData(Uint8List data) async {
  // print("Serial To UDP: ${String.fromCharCodes(data)}");
  // gather data from the serial buffer
  indata += String.fromCharCodes(data as List<int>);
  // gather only the whole lines
  var sdata = indata.substring(0, indata.lastIndexOf('\r\n') + 2);
  // remove the whole lines from the global data buffer
  indata = indata.substring(indata.lastIndexOf('\r\n') + 2);
  // List<String> lines = [];
  // split the lines on CRLF
  var lines = sdata.split('\r\n');    
  // process each line adding back the CRLF to the datagram
  for(final line in lines) {    
    if(line.isEmpty) { continue; }
    print('$line\r\n');
    writeDatagram('$line\r\n'.codeUnits, '127.0.0.1', _port+1);
  }  
}

/// launch it to the specified address:port
void writeDatagram(List<int> data, String address, int port) {
  final int bindPort = 0;
  final inetaddr = InternetAddress(address);      
  // default to listen everywhere
  var bindaddr = InternetAddress.anyIPv4;
  // if loopback, then only bind to loopback
  if(inetaddr.isLoopback) {
    bindaddr = InternetAddress.loopbackIPv4;
  }    
  RawDatagramSocket.bind(bindaddr, bindPort)
  .then((RawDatagramSocket s) {
    // print('writeDatagram: ${String.fromCharCodes(data)}');
    if(inetaddr.isMulticast) { 
      s.multicastHops == 32; 
      // we don't want to re-process what  we have just sent
      s.multicastLoopback = false; 
    }      
    s.send(data, inetaddr, port);
    // final sent = s.send(data, inetaddr, port+1);
    // print('UDP or MC Send $address:$port ${data.length}:${String.fromCharCodes(data)}');      
    });
  }

/// Write TCP data to the Serial Port, but only if the
/// serial port is currently open.
Future<void> handleUDPPortData(Uint8List data) async {
  print("UDP To Serial: ${String.fromCharCodes(data)}");
  if(_serial.isOpen) {
    _serial.write(data);
    _serial.drain();
  }
}

Future<void> createUdpListener(String bindAddress, int port) async {
    print("build a UDP listener....$bindAddress:$port");
    final bindaddr = InternetAddress(bindAddress);
    var inetaddr = InternetAddress.anyIPv4;    
    if(bindaddr.isLoopback) {
      print('LIS: bind UDP listener to localhost');
      inetaddr = InternetAddress.loopbackIPv4;
    }
    RawDatagramSocket.bind(inetaddr, port, reuseAddress: true).then((socket) {
      socket.writeEventsEnabled = false; // listen only
      socket.listen((RawSocketEvent e) {
        switch (e) {
          case RawSocketEvent.read:
            var d = socket.receive(); // Datagram type
            if (d == null) {
              return;
            }
            handleUDPPortData(d.data);
            socket.writeEventsEnabled = false;
            break;
          case RawSocketEvent.write:
            break; // listen only
          case RawSocketEvent.closed:
            print('UDP Listener Disappeared...');
            break;
          default:
            print('UDP Listener Unknown Event...');
            break;
        }
      });
    });
  }