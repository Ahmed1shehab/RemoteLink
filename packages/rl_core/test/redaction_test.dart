import 'package:rl_core/rl_core.dart';
import 'package:test/test.dart';

void main() {
  group('LogRedactor table-driven tests', () {
    final redactor = LogRedactor(
      knownPeerNames: <String>{
        "Ahmed's MacBook Pro",
        'Living Room TV',
        'Pixel 9 Pro',
      },
      homeDirectories: <String>[
        '/Users/ahmed',
        '/home/developer',
        r'C:\Users\tester',
      ],
    );

    group('IP addresses', () {
      final ipCases = <({String description, String input, String expected})>[
        (
          description: 'IPv4 loopback',
          input: 'connected to 127.0.0.1:41234',
          expected: 'connected to [REDACTED_IP]:41234',
        ),
        (
          description: 'IPv4 LAN address',
          input: 'peer at 192.168.1.105:52000',
          expected: 'peer at [REDACTED_IP]:52000',
        ),
        (
          description: 'IPv4 public address',
          input: 'resolved address 203.0.113.19',
          expected: 'resolved address [REDACTED_IP]',
        ),
        (
          description: 'IPv6 loopback',
          input: 'listening on [::1]:8080',
          expected: 'listening on [REDACTED_IP]:8080',
        ),
        (
          description: 'IPv6 link-local with interface',
          input: 'host is fe80::1ff:fe23:4567:890a%en0',
          expected: 'host is [REDACTED_IP]',
        ),
        (
          description: 'IPv6 compressed global',
          input: 'contact 2001:db8::1 on port 443',
          expected: 'contact [REDACTED_IP] on port 443',
        ),
      ];

      for (final testCase in ipCases) {
        test(testCase.description, () {
          expect(redactor.redact(testCase.input), equals(testCase.expected));
        });
      }
    });

    group('MAC addresses', () {
      final macCases = <({String description, String input, String expected})>[
        (
          description: 'colon-separated lowercase',
          input: 'adapter mac=00:1a:2b:3c:4d:5e found',
          expected: 'adapter mac=[REDACTED_MAC] found',
        ),
        (
          description: 'colon-separated uppercase',
          input: 'WOL packet to AA:BB:CC:DD:EE:FF',
          expected: 'WOL packet to [REDACTED_MAC]',
        ),
        (
          description: 'hyphen-separated Windows',
          input: 'interface 00-14-22-01-23-45 active',
          expected: 'interface [REDACTED_MAC] active',
        ),
        (
          description: 'Cisco dotted 4-char groups',
          input: 'arp table entry 0014.2201.2345',
          expected: 'arp table entry [REDACTED_MAC]',
        ),
      ];

      for (final testCase in macCases) {
        test(testCase.description, () {
          expect(redactor.redact(testCase.input), equals(testCase.expected));
        });
      }
    });

    group('Device IDs', () {
      final idCases = <({String description, String input, String expected})>[
        (
          description: '26-character Crockford base32 ID',
          input: 'peer=T9PTJKQZWKGRRCYPBKH2ZNSZDV connected',
          expected: 'peer=[REDACTED_DEVICE_ID] connected',
        ),
        (
          description: 'standalone base32 ID',
          input: 'verified identity 01D3ABC4EFGHJKMNPQRSTVWXYZ',
          expected: 'verified identity [REDACTED_DEVICE_ID]',
        ),
        (
          description: 'short device ID with ellipsis',
          input: 'pairing with T9PTJ…NSZDV in progress',
          expected: 'pairing with [REDACTED_DEVICE_ID] in progress',
        ),
        (
          description: 'short device ID with dots',
          input: 'remote A1B2C...3D4E5 seen',
          expected: 'remote [REDACTED_DEVICE_ID] seen',
        ),
      ];

      for (final testCase in idCases) {
        test(testCase.description, () {
          expect(redactor.redact(testCase.input), equals(testCase.expected));
        });
      }
    });

    group('Cryptographic keys and tokens', () {
      final keyCases = <({String description, String input, String expected})>[
        (
          description: '44-char base64 public key',
          input:
              'staticPublicKey=V2hhdEFHcmVhdEtleVRvSGF2ZUluTG9nc0ZvclRlc3Rpbmc=',
          expected: 'staticPublicKey=[REDACTED_KEY]',
        ),
        (
          description: '43-char base64url unpadded public key',
          input: 'key: V2hhdEFHcmVhdEtleVRvSGF2ZUluTG9nc0ZvclRlc3Rpbmc',
          expected: 'key: [REDACTED_KEY]',
        ),
        (
          description: '64-character hex key digest',
          input:
              'sha256 digest 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
          expected: 'sha256 digest [REDACTED_KEY]',
        ),
        (
          description: 'explicit token field',
          input: 'ticket=abc123XYZ456def789_resumption_token',
          expected: 'ticket=[REDACTED_KEY]',
        ),
        (
          description: 'explicit secret field',
          input: 'secret="super_secret_auth_token_9999"',
          expected: 'secret="[REDACTED_KEY]"',
        ),
      ];

      for (final testCase in keyCases) {
        test(testCase.description, () {
          expect(redactor.redact(testCase.input), equals(testCase.expected));
        });
      }
    });

    group('Home directory file paths', () {
      final pathCases = <({String description, String input, String expected})>[
        (
          description: 'macOS explicit home directory file',
          input: 'reading /Users/ahmed/Documents/secret_notes.txt',
          expected: 'reading [REDACTED_PATH]',
        ),
        (
          description: 'generic macOS home subfolder',
          input:
              'cached in /Users/john_doe/Library/Application Support/RemoteLink',
          expected: 'cached in [REDACTED_PATH]',
        ),
        (
          description: 'Linux home directory path',
          input: 'saved to /home/developer/downloads/bundle.tar.gz',
          expected: 'saved to [REDACTED_PATH]',
        ),
        (
          description: 'Windows explicit home directory path',
          input: r'written to C:\Users\tester\Desktop\document.pdf',
          expected: 'written to [REDACTED_PATH]',
        ),
        (
          description: 'generic Windows user path',
          input: r'loaded from D:\Users\alice\data.bin',
          expected: 'loaded from [REDACTED_PATH]',
        ),
        (
          description: 'tilde path',
          input: 'config file at ~/.config/remotelink/keys.json',
          expected: 'config file at [REDACTED_PATH]',
        ),
      ];

      for (final testCase in pathCases) {
        test(testCase.description, () {
          expect(redactor.redact(testCase.input), equals(testCase.expected));
        });
      }
    });

    group('File names and transfer artifacts', () {
      final fileCases = <({String description, String input, String expected})>[
        (
          description: 'document pdf file name',
          input: 'offering quarterly_report_2026.pdf to peer',
          expected: 'offering [REDACTED_FILE] to peer',
        ),
        (
          description: 'image file name',
          input: 'transferred IMG_4096.JPEG successfully',
          expected: 'transferred [REDACTED_FILE] successfully',
        ),
        (
          description: 'zip archive file name',
          input: 'received backup.zip from client',
          expected: 'received [REDACTED_FILE] from client',
        ),
        (
          description: 'explicit fileName field',
          input: 'fileName="client_records.xlsx"',
          expected: 'fileName="[REDACTED_FILE]"',
        ),
        (
          description: 'explicit file field',
          input: 'file=presentation.pptx',
          expected: 'file=[REDACTED_FILE]',
        ),
        (
          description: 'preserves dart source file names in stack traces',
          input: 'at logging.dart:45:10 in package:rl_core/rl_core.dart',
          expected: 'at logging.dart:45:10 in package:rl_core/rl_core.dart',
        ),
      ];

      for (final testCase in fileCases) {
        test(testCase.description, () {
          expect(redactor.redact(testCase.input), equals(testCase.expected));
        });
      }
    });

    group('Peer names', () {
      final peerCases = <({String description, String input, String expected})>[
        (
          description: 'known desktop peer name',
          input: "handshake with Ahmed's MacBook Pro succeeded",
          expected: 'handshake with [REDACTED_PEER_NAME] succeeded',
        ),
        (
          description: 'known TV peer name',
          input: 'streaming to Living Room TV',
          expected: 'streaming to [REDACTED_PEER_NAME]',
        ),
        (
          description: 'known mobile peer name',
          input: 'disconnected from Pixel 9 Pro',
          expected: 'disconnected from [REDACTED_PEER_NAME]',
        ),
        (
          description: 'explicit peerName field',
          input: 'peerName="Work Laptop"',
          expected: 'peerName="[REDACTED_PEER_NAME]"',
        ),
      ];

      for (final testCase in peerCases) {
        test(testCase.description, () {
          expect(redactor.redact(testCase.input), equals(testCase.expected));
        });
      }
    });

    group('Clipboard contents', () {
      final clipCases = <({String description, String input, String expected})>[
        (
          description: 'explicit clipboard text line',
          input: 'clipboard text: my_confidential_token_123',
          expected: 'clipboard text: [REDACTED_CLIPBOARD]',
        ),
        (
          description: 'explicit clipboard field with quotes',
          input: 'clipboard="secret password"',
          expected: 'clipboard="[REDACTED_CLIPBOARD]"',
        ),
        (
          description: 'explicit clipboardText field',
          input: 'received clipboardText=ConfidentialInformation',
          expected: 'received clipboardText=[REDACTED_CLIPBOARD]',
        ),
      ];

      for (final testCase in clipCases) {
        test(testCase.description, () {
          expect(redactor.redact(testCase.input), equals(testCase.expected));
        });
      }
    });

    test('redactRecord cleans all fields and messages in LogRecord', () {
      final record = LogRecord(
        level: LogLevel.info,
        scope: 'transport.session',
        message: 'connected to 192.168.1.50 with peer Ahmed\'s MacBook Pro',
        time: DateTime.utc(2026, 9, 30),
        fields: <String, Object?>{
          'address': '192.168.1.50',
          'peer': const DeviceId('T9PTJKQZWKGRRCYPBKH2ZNSZDV'),
          'mac': MacAddress(<int>[0x00, 0x11, 0x22, 0x33, 0x44, 0x55]),
          'file': 'contract.pdf',
        },
        error: 'Failed to open /Users/ahmed/secret.key',
      );

      final redacted = redactor.redactRecord(record);

      expect(redacted.message, isNot(contains('192.168.1.50')));
      expect(redacted.message, contains('[REDACTED_IP]'));
      expect(redacted.message, contains('[REDACTED_PEER_NAME]'));

      expect(redacted.fields['address'], equals('[REDACTED_IP]'));
      expect(redacted.fields['peer'], equals('[REDACTED_DEVICE_ID]'));
      expect(redacted.fields['mac'], equals('[REDACTED_MAC]'));
      expect(redacted.fields['file'], equals('[REDACTED_FILE]'));

      expect(redacted.error, contains('[REDACTED_PATH]'));
      expect(redacted.error, isNot(contains('/Users/ahmed')));
    });
  });
}
