import 'package:libserialport/libserialport.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

late SerialPort _modem;
late ServerSocket _ss;
late Socket _tcp;
bool bNetConnected = false;
void main(List<String> arguments) async {  
  /// create the socket/serial connections and set up handlers  
  var serial = ''; // default
  if(arguments.isNotEmpty) {
    serial = arguments.first;
    //print("serial:$serial");
  }
  var speed = 115200; // default
  if(arguments.length > 1) {
    speed = int.parse(arguments.elementAt(1));
  }
  var port = '19798'; // default
  if(arguments.length > 2) {
    port = arguments.elementAt(2);
    //print("port: $_port");
  }  
  // connect to the serial first. if no serial,
  // can decide whether or not to proceed or fail with error
  await getSerial(serial, speed);
  // serial connected to start listening on configured TCP port
  startTcpServer(int.parse(port));    
  Timer.periodic(Duration(seconds:10), (t) { watchDog(serial, speed); });
}

/// Use watchDog() to check the serial connection and
/// re-establish if necessary.
void watchDog(String serial, int speed){ 
  print('Watchdog...'); 
  if(_modem.isOpen) { return; }
  else {
    // try to re-connect to the serial device
    print('Re-connect to serial...');
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
// a running container via a socket.
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
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
      _modem = SerialPort('/dev/$address'); // i.e. ttyACM0
      open = _modem.openReadWrite();
      _modem.config = spc;        
    } else {
      // essentially Windows is the only other viable candidate ATM
      // print('Windows Port: $address');
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
      },
      onError: (error) {
            print('Serial Port Error: ${error.toString()}');
            reader.close();
            _modem.close();
            // Timer(const Duration(seconds: 2), () {
            //   getModem(_modemAddress);
            // });
          },
          onDone: (){
            print('Serial Port Done');
            reader.close();
            _modem.close();
            // Timer(const Duration(seconds: 2), () {
            //   getModem(_modemAddress);
            // });
          },
          cancelOnError: false
      );
    } 
    else {
      print("$address: NOT OPEN!");
      _modem.dispose();
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
  print("Serial To TCP: ${String.fromCharCodes(data)}");
  if(bNetConnected) {
    _tcp.write(data); // for String data
    // or _tcp.write(lines); // for binary data
    //await _tcp.drain();
  }
}

/// Write TCP data to the Serial Port, but only if the
/// serial port is currently open.
Future<void> handleTCPPortData(Uint8List data) async {
  //print("TCP To Serial: ${String.fromCharCodes(data)}");
  if(_modem.isOpen) {
    _modem.write(data);
    _modem.drain();
  }
}

void getTcp(Socket client) {
    _tcp = client;
    _tcp.setOption(SocketOption.tcpNoDelay, true);
    bNetConnected = true;
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
