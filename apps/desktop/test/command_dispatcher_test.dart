import 'package:flutter_test/flutter_test.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'support/fakes.dart';

void main() {
  group('CommandDispatcher DeviceRename', () {
    test('applies valid DeviceRename and calls onDeviceRename callback', () {
      DeviceRename? receivedCommand;
      final dispatcher = createTestDispatcher(
        onDeviceRename: (command) {
          receivedCommand = command;
        },
      );

      final result = dispatcher.dispatch(
        const DeviceRename('My Pixel 9'),
        PermissionTier.standard,
      );

      expect(result, isTrue);
      expect(dispatcher.appliedCount, 1);
      expect(dispatcher.deniedCount, 0);
      expect(dispatcher.unsupportedCount, 0);
      expect(receivedCommand, isNotNull);
      expect(receivedCommand!.name, 'My Pixel 9');
    });

    test('normalises name in valid DeviceRename to Unicode NFC', () {
      DeviceRename? receivedCommand;
      final dispatcher = createTestDispatcher(
        onDeviceRename: (command) {
          receivedCommand = command;
        },
      );

      // Decomposed 'e' + combining acute
      final result = dispatcher.dispatch(
        const DeviceRename('e\u0301lise-phone'),
        PermissionTier.standard,
      );

      expect(result, isTrue);
      expect(receivedCommand!.name, 'élise-phone');
      expect(receivedCommand!.name.codeUnits.first, 0x00E9);
    });

    test('rejects invalid DeviceRename and leaves stored name untouched', () {
      String storedName = 'Original iPhone Name';
      var renameCalled = false;

      final dispatcher = createTestDispatcher(
        onDeviceRename: (command) {
          renameCalled = true;
          storedName = command.name;
        },
      );

      final invalidNames = <String>[
        '',
        '   ',
        '\t',
        '\n',
        'Phone\nName',
        'Phone\r\nName',
        'Phone\x00Name',
        'Phone\x1B[31mName\x1B[0m',
        'Phone\u200BName',
        '\uFEFFPhone',
        '\u2800',
        'A' * 65,
      ];

      for (final invalid in invalidNames) {
        renameCalled = false;
        final result = dispatcher.dispatch(
          DeviceRename(invalid),
          PermissionTier.standard,
        );

        expect(result, isFalse, reason: 'Expected "$invalid" to be rejected');
        expect(renameCalled, isFalse,
            reason: 'Handler must NOT be called for "$invalid"');
        expect(storedName, 'Original iPhone Name',
            reason: 'Stored name must remain untouched for "$invalid"');
      }

      expect(dispatcher.appliedCount, 0);
    });

    test('permits valid DeviceRename across all permission tiers', () {
      final tiers = <PermissionTier>[
        PermissionTier.readOnly,
        PermissionTier.standard,
        PermissionTier.extended,
        PermissionTier.admin,
      ];

      for (var i = 0; i < tiers.length; i++) {
        final tier = tiers[i];
        DeviceRename? received;
        final dispatcher = createTestDispatcher(
          onDeviceRename: (command) {
            received = command;
          },
        );

        final result = dispatcher.dispatch(
          DeviceRename('Tier Test $i'),
          tier,
        );

        expect(result, isTrue,
            reason: 'DeviceRename should be allowed at tier ${tier.name}');
        expect(received?.name, 'Tier Test $i');
        expect(dispatcher.appliedCount, 1);
        expect(dispatcher.deniedCount, 0);
      }
    });
  });
}
