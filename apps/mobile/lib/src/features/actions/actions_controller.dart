import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';

final actionsControllerProvider = Provider<ActionsController>((ref) {
  return ActionsController(() => ref.read(clientProvider).valueOrNull);
});

final _catalogUpdatesProvider =
    StreamProvider.autoDispose<CommandCatalog>((ref) {
  final client = ref.watch(clientProvider).valueOrNull;
  return client?.messages
          .where((message) => message is CommandCatalog)
          .cast<CommandCatalog>() ??
      const Stream.empty();
});

final actionsCatalogProvider =
    Provider.autoDispose<List<CommandCatalogEntry>>((ref) {
  ref.watch(clientStateProvider);
  ref.watch(_catalogUpdatesProvider);
  return ref.watch(actionsControllerProvider).entries;
});

final actionsResultsProvider = StreamProvider.autoDispose<CommandResult>((ref) {
  final client = ref.watch(clientProvider).valueOrNull;
  return client?.messages
          .where((message) => message is CommandResult)
          .cast<CommandResult>() ??
      const Stream.empty();
});

final class ActionsController {
  const ActionsController(this._client);

  final RemoteLinkClient? Function() _client;

  List<CommandCatalogEntry> get entries =>
      _client()?.session?.commandCatalog?.entries ?? const [];

  Future<bool> run(String id) async {
    final client = _client();
    final catalog = client?.session?.commandCatalog;
    if (client == null ||
        !client.isConnected ||
        catalog == null ||
        !catalog.entries.any((entry) => entry.id == id)) {
      return false;
    }
    return client.send(RunCommand(commandId: id));
  }
}
