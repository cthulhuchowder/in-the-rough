# Hosting a dedicated server

The server is the same Godot project exported headless. It is server-authoritative and runs many
rooms at once. A player hosts a room and gets a 6-character code; friends join with the code (or a
Steam invite). Each room has its own physics world, course seed and up to 8 players; the server
simulates every ball, keeps score and moves everyone to the next hole once all players still in
the room have finished. Clients send only lobby actions and shots.

- Protocol: Godot high-level multiplayer over ENet, **UDP 7777**.
- Channel 0 reliable (join, shots, scores, holes); channel 1 unreliable ball snapshots at 30 Hz.
- Tunables: `game/data/net.tres` (port, snapshot rate, prediction window, interpolation delay).

## 1. Point the client at your server

Clients connect to `default_address` in `game/data/net.tres`. It ships as `127.0.0.1` (a server
on the same machine). Set it to your server's address (a VPN IP, a public IP or a hostname) and
export the client again. For testing you can override it at launch:
`InTheRough.exe -- --address 203.0.113.10 --port 7777`.

## 2. Build the Linux server

With Godot 4.7.2 and its export templates installed, from the repo root:

```sh
cd game
godot --headless --export-release "Linux Server" ../server/build/in-the-rough-server.x86_64
```

Run it once by hand to check it starts:

```sh
./server/build/in-the-rough-server.x86_64 --headless --server --port 7777
```

It should print `golf server: UDP 7777, 9 holes per round`.

## 3. Install it as a systemd service

Tested on Debian 12 (a VM or container is fine). Copy the binary and `server/golf-server.service`
to the server, then as root:

```sh
adduser --system --group --home /var/lib/golf --shell /usr/sbin/nologin golf
install -d -o root -g root -m 755 /opt/golf
install -o root -g root -m 755 in-the-rough-server.x86_64 /opt/golf/in-the-rough-server.x86_64
install -o root -g root -m 644 golf-server.service /etc/systemd/system/golf-server.service
systemctl daemon-reload
systemctl enable --now golf-server
systemctl status golf-server --no-pager
```

Follow the log with `journalctl -u golf-server -f` (rooms created and closed, joins, leaves, hole
results, round ends). If it fails to start with a missing library, run the binary by hand as above
to see the error, and `ldd /opt/golf/in-the-rough-server.x86_64` to list what's missing.

The unit runs the server as the unprivileged `golf` user with a read-only filesystem except
`/var/lib/golf`, and restarts it if it exits.

### Updating

Copy the new binary over, then:

```sh
install -o root -g root -m 755 in-the-rough-server.x86_64 /opt/golf/in-the-rough-server.x86_64
systemctl restart golf-server
```

Client and server must come from the same build: the network protocol changes between versions.
The server prints its version at start (`golf server: UDP 7777, 9 holes per round, version 0.3.0+…`);
a client on another version is told "Server is on a different version (server X, game Y)".

## 4. Let players reach it

Pick one:

- **Tailscale (or another mesh VPN), easiest and private.** Install Tailscale on the server and
  share the machine with your friends (Tailscale admin console → the machine → Share). Use its
  Tailscale IP as `default_address`. Nothing needs port forwarding. If the server runs a firewall,
  allow UDP 7777 on the `tailscale0` interface.
- **Port forwarding, open to the internet.** Forward **UDP 7777** on your router to the server and
  allow it in the server's firewall (e.g. `ufw allow 7777/udp`). Use your public IP or a (dynamic)
  DNS name as `default_address`. Anyone with the address can connect, so keep the server updated.

## Options

`--port N` (default 7777) · `--holes N` holes per round (default 9 from `net.tres`) ·
`--profiles PATH` where players' coins and items are saved (the unit uses `/var/lib/golf/profiles.json`,
the one folder it may write to) ·
`--exit-when-done` quit after the first round ends · `--report PATH` write that scorecard as JSON
(the last two are for tests). To change them, edit `ExecStart` in
`/etc/systemd/system/golf-server.service`, then `systemctl daemon-reload && systemctl restart golf-server`.
