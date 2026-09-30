import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('resume request carries the appended ephemeral and proof', () {
    final codec = MessageCodec(clock: FakeClock());
    final request = ResumeSession(
      ticket: Uint8List.fromList(<int>[1, 2, 3]),
      clientNonce: Uint8List(32)..[0] = 4,
      bindingMac: Uint8List(32)..[0] = 5,
      clientEphemeral: Uint8List(32)..[0] = 6,
      capabilities: const Capabilities(Capabilities.mouse),
    );
    final decoded = codec.decode(codec.encode(request)) as ResumeSession;
    expect(decoded.ticket, request.ticket);
    expect(decoded.clientNonce, request.clientNonce);
    expect(decoded.bindingMac, request.bindingMac);
    expect(decoded.clientEphemeral, request.clientEphemeral);
    expect(decoded.capabilities.bits, request.capabilities.bits);
  });
}
