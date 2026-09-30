import '../../app/l10n.dart';
import 'transfer_model.dart';

String describeTransferFailure(
        AppLocalizations l10n, TransferFailure failure, String peerName) =>
    switch (failure) {
      TransferFailure.timedOut => l10n.transferFailureTimedOut,
      TransferFailure.hashMismatch => l10n.transferFailureHashMismatch,
      TransferFailure.noSpace => l10n.transferFailureNoSpace,
      TransferFailure.noSpaceOnPeer => l10n.transferFailureNoSpaceOnPeer,
      TransferFailure.chunkRefused => l10n.transferFailureChunkRefused,
      TransferFailure.cancelledByPeer =>
        l10n.transferFailureCancelledByPeer(bidiIsolate(peerName)),
      TransferFailure.cancelledByYou => l10n.transferFailureCancelledByYou,
      TransferFailure.declinedByPeer =>
        l10n.transferFailureDeclinedByPeer(bidiIsolate(peerName)),
      TransferFailure.declinedByYou => l10n.transferFailureDeclinedByYou,
      TransferFailure.connectionLost => l10n.transferFailureConnectionLost,
      TransferFailure.deviceDisconnected =>
        l10n.transferFailureDeviceDisconnected,
      TransferFailure.ioError => l10n.transferFailureIoError,
      TransferFailure.receiverUnavailable =>
        l10n.transferFailureReceiverUnavailable,
      TransferFailure.storageUnavailable =>
        l10n.transferFailureStorageUnavailable,
      TransferFailure.couldNotComplete => l10n.transferFailureCouldNotComplete,
      TransferFailure.couldNotAccept => l10n.transferFailureCouldNotAccept,
      TransferFailure.retryFailed => l10n.transferFailureRetryFailed,
      TransferFailure.exportCancelled => l10n.exportCancelled,
      TransferFailure.exportPermissionDenied => l10n.exportPermissionDenied,
      TransferFailure.exportFailed => l10n.exportFailed,
    };
