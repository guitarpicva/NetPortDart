import 'package:netport/netport.dart' as netport;
import 'package:libserialport/libserialport.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

late SerialPort _modem;
late ServerSocket _ss;
late Socket _tcp;
String serBuffer = '';
bool b_NetConnected = false;
void main(List<String> arguments) {
  print('NetPort!');
  /// create the socket/serial to the modem/controller and set up handlers
  startTcpServer(19798);  

  getModem("ttyACM0");
}

/// Start the control server process to listen on the chosen
  /// ip address and port passed from the command line
  /// Automatically starts the client socket handler upon
  /// new connection (one connection only)
  Future<ServerSocket> startTcpServer(int port) async {
    var ss =
        await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
    _ss = ss;
    ss.listen((client) {
      getTcp(client);
    });
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
        print('Linux Radio:$address');
        _modem = SerialPort('/dev/$address');
        open = _modem.openReadWrite();
        _modem.config = spc;        
      } else {
        // essentially Windows is the only other viable candidate ATM
        print('Windows Radio:$address');
        _modem = SerialPort(address); // i.e. COM23
        _modem.config = spc;
        open = _modem.openReadWrite();        
      }      
      if (open) {
        print("$address: OPEN!");
        final reader = SerialPortReader(_modem);
        reader.stream.listen((data) {
          // serBuffer += String.fromCharCodes(data);
          // //print("serBuffer: $data");
          // if(serBuffer.contains("\r\n")) {
          //   //print("run handler: $serBuffer");
          //   int endex = serBuffer.lastIndexOf("\r\n") + 2;
          //   String lines = serBuffer.substring(0, endex);
            handleAsciiPortData(data);
            // serBuffer = serBuffer.substring(endex);
          // }
        });
      } else {
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

void handleAsciiPortData(Uint8List lines) {
  print(String.fromCharCodes(lines));
  if(b_NetConnected) {
    _tcp.write(lines);
    _tcp.flush();
  }
}

void handleTCPPortData(Uint8List lines) {
  print(String.fromCharCodes(lines));
  if(_modem.isOpen) {
    _modem.write(lines);
    _modem.drain();
  }
}

void getTcp(Socket client) {
    _tcp = client;
    _tcp.setOption(SocketOption.tcpNoDelay, true);
    b_NetConnected = true;
    //String controlBuffer = '';
    // print('Control client waiting for data...');
    client.listen(
        (Uint8List data) async {
          // controlBuffer += String.fromCharCodes(data);
          // if(controlBuffer.contains("\n")) {
            handleTCPPortData(data);            
          // }
        },
        cancelOnError: false,
        onError: (error) {
          print('Control client error: $error');
        },
        onDone: () {
          print('Control client finished...');
          client.close();
          b_NetConnected = false;
        });
  }