# Packaging Remote Link for release

Two scripts, one per desktop platform. Each builds, signs, and produces the
artifact a user downloads.

```bash
tool/package/macos.sh          # → build/release/Remote Link 1.0.0.dmg
pwsh tool/package/windows.ps1  # → build/release/RemoteLink-1.0.0-setup.exe
```

Both run unsigned without configuration, so a contributor with no certificate
can still produce a build. Both say what the user will see when they open an
unsigned one.

---

## Why signing is not paperwork here

macOS binds the **Accessibility** and **Screen Recording** grants to the code
signature. Those two permissions are the product: without them the phone can see
a computer it cannot touch and cannot watch. So:

- An **unsigned** build asks for both again after every rebuild.
- A build signed with a **different identity** asks once more, and looks to the
  user like the app forgot.
- A build signed with a **stable Developer ID** keeps them across updates.

On Windows the equivalent stake is quieter and larger. An unsigned installer
that writes a `Run` key and opens a listening socket is the exact shape of thing
endpoint protection is built to quarantine, and it will be — silently, on
somebody else's machine, with no message reaching you.

---

## macOS

### One-time setup

1. A **Developer ID Application** certificate in the login keychain. List what
   you have:

   ```bash
   security find-identity -v -p codesigning
   ```

2. A notarisation profile, stored once in the keychain so no password appears in
   a script or a CI log:

   ```bash
   xcrun notarytool store-credentials remotelink \
     --apple-id you@example.com \
     --team-id TEAMID \
     --password <app-specific-password>
   ```

   The password is an **app-specific password** from appleid.apple.com, not your
   Apple ID password.

### Every release

```bash
export RL_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export RL_NOTARY_PROFILE="remotelink"
tool/package/macos.sh
```

The script signs nested code before the bundle, staples the notarisation ticket
so the first launch works offline, and finishes by asking Gatekeeper the same
question a user's Mac will ask.

### The App Sandbox is off, deliberately

`apps/desktop/macos/Runner/Release.entitlements` carries no
`com.apple.security.app-sandbox`, and the reasoning is written out in that file.
The short version:

- The sandbox redirects `~/Library` into a per-app container, so the LaunchAgent
  that implements *start at login* was written somewhere `launchd` never reads.
  The feature reported success and had never once worked.
- An app that posts keyboard and mouse events into other applications is the
  category the sandbox exists to prevent, and the Mac App Store — the only
  channel that requires a sandbox — does not accept such apps anyway.

What replaces it is the hardened runtime, notarisation, and two permissions the
user grants by hand and can revoke at any time.

**Migration.** Application support moved out of the container to
`~/Library/Application Support/RemoteLink`. Anyone who ran a sandboxed build
pairs their phones once more. There is no automatic migration, because copying
an identity key between locations is a worse idea than pairing again.

---

## Windows

### One-time setup

1. A code-signing certificate in `Cert:\CurrentUser\My`. Find its thumbprint:

   ```powershell
   Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
   ```

2. [Inno Setup 6](https://jrsoftware.org/isdl.php).

### Every release

```powershell
$env:RL_SIGN_THUMBPRINT = '<thumbprint>'
pwsh tool/package/windows.ps1
```

The installer is per-user and needs no elevation: the app needs none to run, and
asking for administrator trains people to grant it to a program that accepts
input from the network.

It offers two boxes, both on by default:

- **Start when I sign in** — writes the same `Run` value the app's own setting
  writes, with the same `--minimised` flag, so the two describe one thing.
- **Allow through Windows Firewall (private networks)** — created at install
  rather than at first launch, because a firewall prompt appears behind the
  app's own window, gets dismissed by reflex, and leaves a companion the phone
  cannot reach with nothing on screen saying why. Private profile only.

> **Not yet run on Windows.** These scripts were written on macOS from the
> documented behaviour of `signtool`, `ISCC` and `netsh`. The first person to
> run them should expect to correct something.

---

## Updates

There is no update check, and adding one is a decision rather than a task.

This product's entire security posture is that it never talks to the internet:
no cloud, no account, no telemetry. A background update check contradicts that
in the most literal way available — it makes every installation phone a server
on a schedule, which is a beacon of exactly the sort the design promises not to
be.

The conservative version, when it is built, is a **manual** "check for updates"
button: it runs only when the user asks, and `docs/SECURITY.md` gains a
paragraph saying what it sends. Until then, releases are downloaded the way they
were found.

The version the user is running is shown in **Settings → About** on both apps,
so a support conversation can start from a number rather than a guess.
