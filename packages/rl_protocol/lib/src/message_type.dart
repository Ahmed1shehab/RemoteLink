/// Every message the protocol can carry, keyed by a stable 16-bit wire code.
///
/// Codes are grouped by subsystem so that a capture is readable at a glance and
/// so that routing can switch on the high byte:
///
/// ```text
/// 0x00xx  session control     handshake, keepalive, errors
/// 0x01xx  pairing and trust
/// 0x02xx  pointer input
/// 0x03xx  keyboard input
/// 0x04xx  clipboard
/// 0x05xx  media transport
/// 0x06xx  screen streaming
/// 0x07xx  file transfer
/// 0x08xx  system and power
/// 0x09xx  device management
/// 0x0Axx  presentation
/// 0x0Bxx  gamepad
/// ```
///
/// Codes are append-only and never reused: a value that shipped keeps its
/// meaning forever, and a retired message becomes `reserved` rather than being
/// recycled. This is what lets an old client talk to a new server safely.
enum MessageType {
  // ── 0x00xx session control ────────────────────────────────────────────────
  /// Client → server. Opens a connection: supported versions, ephemeral key.
  clientHello(0x0001),

  /// Server → client. Selects a version, returns the server's ephemeral key.
  serverHello(0x0002),

  /// Either direction. Completes the handshake with a transcript MAC.
  handshakeFinish(0x0003),

  /// Liveness probe carrying the sender's monotonic timestamp.
  ping(0x0004),

  /// Echo of a [ping], used to measure round-trip time.
  pong(0x0005),

  /// Acknowledgement of a frame that set `FrameFlags.requiresAck`.
  ack(0x0006),

  /// Structured error. May or may not be followed by a close.
  error(0x0007),

  /// Graceful shutdown with a reason code.
  close(0x0008),

  /// Server → client. Grants a ticket for 0-RTT session resumption.
  resumptionTicket(0x0009),

  /// Client → server. Presents a previously granted resumption ticket.
  resumeSession(0x000A),

  // ── 0x01xx pairing and trust ──────────────────────────────────────────────
  /// Client → server. Requests to begin pairing.
  pairRequest(0x0101),

  /// Server → client. Pairing accepted; user must now compare the SAS.
  pairChallenge(0x0102),

  /// Client → server. User confirmed the short authentication string.
  pairConfirm(0x0103),

  /// Server → client. Pairing succeeded; both sides persist the peer key.
  pairComplete(0x0104),

  /// Either direction. Pairing was rejected, timed out, or rate-limited.
  pairReject(0x0105),

  /// Either direction. Revokes an existing trust relationship.
  unpair(0x0106),

  // ── 0x02xx pointer input ──────────────────────────────────────────────────
  /// Relative cursor movement. The highest-frequency message in the protocol.
  mouseMove(0x0201),

  /// Absolute cursor position in normalised `[0,1]` screen coordinates.
  mouseMoveAbsolute(0x0202),

  /// Button press or release.
  mouseButton(0x0203),

  /// Wheel or two-finger scroll, in lines and in pixels.
  mouseScroll(0x0204),

  /// Pinch-zoom magnification delta.
  gestureZoom(0x0205),

  /// Two-finger rotation delta in degrees.
  gestureRotate(0x0206),

  /// Multi-finger swipe, mapped to OS gestures (Mission Control, Task View).
  gestureSwipe(0x0207),

  /// Stylus/pen event with pressure and tilt.
  penInput(0x0208),

  // ── 0x03xx keyboard input ─────────────────────────────────────────────────
  /// Key press or release identified by USB HID usage code.
  keyEvent(0x0301),

  /// Unicode text injection, bypassing keycode translation entirely.
  textInput(0x0302),

  /// Named shortcut resolved by the desktop (`copy`, `taskManager`, …).
  namedShortcut(0x0303),

  /// Absolute modifier state, sent to resynchronise after focus loss.
  modifierState(0x0304),

  // ── 0x04xx clipboard ──────────────────────────────────────────────────────
  /// A clipboard change happened locally; here is the content.
  clipboardUpdate(0x0401),

  /// Ask the peer for its current clipboard.
  clipboardRequest(0x0402),

  /// Enable or disable automatic clipboard mirroring for this session.
  clipboardSyncToggle(0x0403),

  // ── 0x05xx media transport ────────────────────────────────────────────────
  /// Play, pause, next, previous, stop.
  mediaCommand(0x0501),

  /// Absolute or relative volume change, or mute toggle.
  volumeCommand(0x0502),

  /// Server → client. Now-playing metadata for the remote's display.
  mediaState(0x0503),

  /// Display brightness change, where the OS exposes it.
  brightnessCommand(0x0504),

  // ── 0x06xx screen streaming ───────────────────────────────────────────────
  /// Client → server. Start streaming with the given quality parameters.
  screenStreamStart(0x0601),

  /// Client → server. Stop streaming.
  screenStreamStop(0x0602),

  /// Server → client. One encoded video frame.
  screenFrame(0x0603),

  /// Client → server. Adjust bitrate, FPS, or scale mid-stream.
  screenConfigure(0x0604),

  /// Server → client. Monitor topology and DPI.
  ///
  /// The only implemented code in this range; the four above still decode as
  /// opaque bytes until screen streaming lands. It is here rather than with
  /// pointer input because the layout it describes is the same layout a stream
  /// would send, and splitting it would have meant two sources of truth.
  screenTopology(0x0605),

  /// Server → client. Where the pointer is, on its own.
  ///
  /// Separate from [screenFrame] because the two move at completely different
  /// rates and sizes. The capture APIs do not composite the cursor, so it has
  /// to travel beside the picture — but carrying it *inside* the picture meant
  /// a pointer moving across a still desk re-sent the whole encoded frame to
  /// say the arrow had moved four pixels. Measured on this desk: 213,622 bytes
  /// against 34, and 102 Mbps against 16 kbps to animate a cursor at 60 Hz.
  screenCursor(0x0606),

  // ── 0x07xx file transfer ──────────────────────────────────────────────────
  /// Announces an incoming file: name, size, hash.
  fileOffer(0x0701),

  /// Accepts an offer, optionally resuming from a byte offset.
  fileAccept(0x0702),

  /// One chunk of file data.
  fileChunk(0x0703),

  /// Transfer finished; carries the final hash for verification.
  fileComplete(0x0704),

  /// Either side aborts an in-flight transfer.
  fileAbort(0x0705),

  // ── 0x08xx system and power ───────────────────────────────────────────────
  /// Shutdown, restart, sleep, lock, log out.
  powerCommand(0x0801),

  /// Launch an application by identifier or path.
  launchApplication(0x0802),

  /// Open a URL in the default browser.
  openUrl(0x0803),

  /// Run a user-defined command from the allow-list.
  runCommand(0x0804),

  /// Server → client. Host telemetry: battery, CPU, volume, uptime.
  systemStatus(0x0805),

  // ── 0x09xx device management ──────────────────────────────────────────────
  /// Either direction. Full peer description after a successful handshake.
  deviceInfo(0x0901),

  /// Rename the peer as it appears in the other side's device list.
  deviceRename(0x0902),

  /// Server → client. Permission tier granted to this session.
  permissionGrant(0x0903),

  /// Client → server. Request an elevated permission tier.
  permissionRequest(0x0904),

  // ── 0x0Axx presentation ───────────────────────────────────────────────────
  /// Advance or retreat a slide.
  slideCommand(0x0A01),

  /// Move or toggle the on-screen laser pointer.
  laserPointer(0x0A02),

  /// Blank or unblank the presentation display.
  presentationBlank(0x0A03),

  // ── 0x0Bxx gamepad ────────────────────────────────────────────────────────
  /// Virtual controller state: sticks, triggers, buttons.
  gamepadState(0x0B01),

  /// Gyroscope and accelerometer readings for motion control.
  motionState(0x0B02),

  // ── 0x0Cxx phone control ──────────────────────────────────────────────────
  /// Desktop → phone. Requests to start streaming the phone's screen.
  phoneControlStart(0x0C01),

  /// Desktop → phone. Requests to stop an active screen stream.
  phoneControlStop(0x0C02),

  /// Phone → desktop. One encoded video frame from the phone's screen.
  phoneControlFrame(0x0C03),

  /// Desktop → phone. Tap/touch at normalised coordinates.
  phoneControlPointer(0x0C04),

  /// Desktop → phone. Swipe/scroll event.
  phoneControlScroll(0x0C05),

  /// Desktop → phone. Back/home navigation action.
  phoneControlNavigation(0x0C06),

  /// Desktop → phone. Text input.
  phoneControlTextInput(0x0C07),

  // ── fallback ──────────────────────────────────────────────────────────────
  /// Any code this build does not recognise.
  ///
  /// Receiving an unknown type is **not** an error. A newer peer may send
  /// messages we have never heard of; the session layer logs and drops them,
  /// which is precisely what makes minor protocol additions non-breaking.
  unknown(0xFFFF);

  const MessageType(this.code);

  /// Stable 16-bit wire identifier.
  final int code;

  static final Map<int, MessageType> _byCode = <int, MessageType>{
    for (final type in MessageType.values)
      if (type != MessageType.unknown) type.code: type,
  };

  /// Resolves a wire code, returning [unknown] rather than throwing.
  static MessageType fromCode(int code) => _byCode[code] ?? MessageType.unknown;

  /// Subsystem byte, for routing and metrics bucketing.
  int get subsystem => (code >> 8) & 0xFF;

  /// Whether this message may be processed before the handshake completes.
  ///
  /// Everything else is dropped on an unauthenticated connection. Keeping this
  /// list explicit — rather than inferring it from the subsystem — means adding
  /// a message can never accidentally widen the pre-auth attack surface.
  bool get allowedUnauthenticated => switch (this) {
        MessageType.clientHello ||
        MessageType.serverHello ||
        MessageType.handshakeFinish ||
        MessageType.resumeSession ||
        MessageType.error ||
        MessageType.close =>
          true,
        _ => false,
      };

  /// Whether losing this message would leave the peers inconsistent.
  ///
  /// Lossy messages (cursor deltas, video frames, gyro samples) are eligible
  /// for the unreliable UDP channel and for coalescing under backpressure;
  /// reliable ones are not.
  bool get isLossy => switch (this) {
        MessageType.mouseMove ||
        MessageType.mouseMoveAbsolute ||
        MessageType.gestureZoom ||
        MessageType.gestureRotate ||
        MessageType.penInput ||
        MessageType.screenFrame ||
        MessageType.screenCursor ||
        MessageType.gamepadState ||
        MessageType.motionState ||
        MessageType.laserPointer ||
        MessageType.phoneControlFrame ||
        MessageType.phoneControlPointer ||
        MessageType.phoneControlScroll =>
          true,
        _ => false,
      };
}
