/// RemoteLink discovery, transport, and session management.
///
/// The layering, from the socket up:
///
/// ```text
/// RemoteLinkClient / RemoteLinkServer   reconnection, session registry
/// Session                               messages, heartbeat, RTT, coalescing
/// HandshakeDriver                       runs rl_crypto over a connection
/// FramedConnection                      length-prefixed records over TCP
/// dart:io Socket
/// ```
///
/// Discovery sits alongside rather than underneath: `UdpDiscoveryServer`
/// announces a computer, `UdpDiscoveryClient` finds one, and the address it
/// produces is what `RemoteLinkClient` dials.
library;

export 'src/discovery/beacon.dart';
export 'src/discovery/udp_discovery.dart';
export 'src/transfer/receiver.dart';
export 'src/transfer/sender.dart';
export 'src/transfer/storage.dart';
export 'src/transport/client.dart';
export 'src/transport/framed_connection.dart';
export 'src/transport/handshake_driver.dart';
export 'src/transport/reconnect.dart';
export 'src/transport/server.dart';
export 'src/transport/session.dart';
