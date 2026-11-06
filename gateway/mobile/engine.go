// Package mobile exposes the owner engine to gomobile. It is experimental and
// deliberately not accessible from Flutter until authorization and lifecycle
// integration have been reviewed and tested on devices.
package mobile

import (
    "context"
    "crypto/ecdh"
    "encoding/base64"
    "encoding/hex"
    "encoding/json"
    "errors"
    "fmt"
    "net"
    "net/netip"
    "strconv"
    "strings"
    "sync"
    "syscall"

    gateway "github.com/leoblanchart92-hub/NexaLink/gateway"
    "golang.zx2c4.com/wireguard/conn"
    "golang.zx2c4.com/wireguard/device"
)

// SocketBinder must synchronously protect and bind the unconnected descriptor
// to the explicitly selected cellular network. False means fail closed.
// The descriptor remains owned by Go; callers must not close it.
type SocketBinder interface { BindSocket(fd int32) bool }

type Engine struct {
    mu sync.Mutex
    binder SocketBinder
    gw *gateway.Gateway
    wg *device.Device
    port int32
}

func NewEngine(binder SocketBinder) (*Engine, error) {
    if binder == nil { return nil, errors.New("socket binder is required") }
    return &Engine{binder: binder}, nil
}

func bindFD(binder SocketBinder, fd uintptr) (ok bool) {
    defer func() { if recover() != nil { ok = false } }()
    if fd > 2147483647 { return false }
    return binder.BindSocket(int32(fd))
}

// The outbound connection is created by Go but bound before connect. No DNS
// resolution or fallback is permitted here: addr must be a numeric IPv4 address.
func dialer(binder SocketBinder) gateway.Dial {
    d := &net.Dialer{ControlContext: func(_ context.Context, network, _ string, c syscall.RawConn) error {
        if network != "tcp4" && network != "udp4" { return errors.New("unsupported network") }
        ok := false
        if err := c.Control(func(fd uintptr) { ok = bindFD(binder, fd) }); err != nil { return err }
        if !ok { return errors.New("cellular socket binding failed") }
        return nil
    }}
    return func(ctx context.Context, network, addr string) (net.Conn, error) {
        ap, err := netip.ParseAddrPort(addr)
        if err != nil || !ap.Addr().Is4() || (network != "tcp4" && network != "udp4") { return nil, errors.New("numeric IPv4 required") }
        return d.DialContext(ctx, network, addr)
    }
}

type peekBind interface {
    conn.Bind
    PeekLookAtSocketFd4() (int, error)
    PeekLookAtSocketFd6() (int, error)
}

type cellularBind struct { conn.Bind; binder SocketBinder }
func (b *cellularBind) Open(port uint16) (fns []conn.ReceiveFunc, actual uint16, err error) {
    // Android's StdNetBind exports PeekLookAtSocketFd4/6. Both must succeed;
    // no packets are sent before Open returns. Close on any failure or panic.
    defer func() {
        if recover() != nil { err = errors.New("WireGuard socket unavailable") }
        if err != nil { _ = b.Bind.Close(); fns = nil; actual = 0 }
    }()
    fns, actual, err = b.Bind.Open(port)
    if err != nil { return }
    p, ok := b.Bind.(peekBind)
    if !ok { err = errors.New("WireGuard bind cannot expose descriptors"); return }
    for _, get := range []func() (int, error){p.PeekLookAtSocketFd4, p.PeekLookAtSocketFd6} {
        fd, e := get()
        if e != nil || fd < 0 || !bindFD(b.binder, uintptr(fd)) { err = errors.New("WireGuard cellular binding failed"); return }
    }
    return
}

func decodeKey(s string) ([]byte, error) {
    key, err := base64.StdEncoding.Strict().DecodeString(s)
    if err != nil || len(key) != 32 { return nil, errors.New("invalid WireGuard key") }
    var any byte; for _, b := range key { any |= b }
    if any == 0 { return nil, errors.New("invalid WireGuard key") }
    return key, nil
}

// Start starts a *local* WireGuard endpoint and gateway for one guest. It does
// not mean a handshake or Internet connectivity exists. No secrets are logged.
func (e *Engine) Start(privateKey, guestPublicKey, guestAddress string, listenPort int32) (int32, error) {
    e.mu.Lock(); defer e.mu.Unlock()
    if e.wg != nil { return 0, errors.New("engine already running") }
    if listenPort < 0 || listenPort > 65535 { return 0, errors.New("invalid port") }
    local, err := decodeKey(privateKey); if err != nil { return 0, err }
    peer, err := decodeKey(guestPublicKey); if err != nil { return 0, err }
    private, err := ecdh.X25519().NewPrivateKey(local); if err != nil { return 0, errors.New("invalid private key") }
    if string(private.PublicKey().Bytes()) == string(peer) { return 0, errors.New("peer key matches local key") }
    ip, err := netip.ParseAddr(guestAddress)
    if err != nil || !ip.Is4() || !ip.IsPrivate() { return 0, errors.New("private guest IPv4 required") }
    gw, err := gateway.New(ip, dialer(e.binder), gateway.PublicIPv4); if err != nil { return 0, err }
    wg := device.NewDevice(gw.Tun(), &cellularBind{Bind: conn.NewDefaultBind(), binder: e.binder}, device.NewLogger(device.LogLevelSilent, ""))
    cleanup := func() { wg.Close(); gw.Close() }
    cfg := fmt.Sprintf("private_key=%s\nlisten_port=%d\npublic_key=%s\nallowed_ip=%s/32\n", hex.EncodeToString(local), listenPort, hex.EncodeToString(peer), ip.String())
    if err = wg.IpcSet(cfg); err != nil { cleanup(); return 0, errors.New("invalid WireGuard configuration") }
    if err = wg.Up(); err != nil { cleanup(); return 0, errors.New("could not start protected WireGuard endpoint") }
    state, err := wg.IpcGet()
    if err != nil { cleanup(); return 0, errors.New("could not read WireGuard state") }
    actual := int32(0)
    for _, line := range strings.Split(state, "\n") {
        if strings.HasPrefix(line, "listen_port=") { n, _ := strconv.ParseInt(strings.TrimPrefix(line, "listen_port="), 10, 32); actual = int32(n) }
    }
    if actual <= 0 || actual > 65535 { cleanup(); return 0, errors.New("WireGuard port unavailable") }
    e.wg, e.gw, e.port = wg, gw, actual
    return actual, nil
}

// Stop closes the tunnel and all flows. It is idempotent and must be called if
// cellular connectivity, consent, or authorization is lost.
func (e *Engine) Stop() {
    e.mu.Lock(); defer e.mu.Unlock()
    if e.wg == nil { return }
    e.wg.Close(); e.gw.Close(); e.wg = nil; e.gw = nil; e.port = 0
}

// StatusJSON reports local engine state and WG encrypted byte counters. A
// handshake is not proof of working Internet. No keys/endpoints are returned.
func (e *Engine) StatusJSON() (string, error) {
    e.mu.Lock(); defer e.mu.Unlock()
    s := struct { Running bool `json:"running"`; Port int32 `json:"port"`; Rx int64 `json:"rxBytes"`; Tx int64 `json:"txBytes"`; Handshake int64 `json:"lastHandshakeEpochSeconds"` }{Running: e.wg != nil, Port:e.port}
    if e.wg != nil {
        cfg, err := e.wg.IpcGet(); if err != nil { return "", errors.New("could not read WireGuard statistics") }
        for _, l := range strings.Split(cfg, "\n") {
            k, v, ok := strings.Cut(l, "="); if !ok { continue }
            n, _ := strconv.ParseInt(v, 10, 64)
            switch k { case "rx_bytes": s.Rx += n; case "tx_bytes": s.Tx += n; case "last_handshake_time_sec": if n > s.Handshake { s.Handshake = n } }
        }
    }
    data, _ := json.Marshal(s); return string(data), nil
}
