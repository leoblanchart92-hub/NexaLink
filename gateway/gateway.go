package gateway

import (
    "context"
    "errors"
    "io"
    "net"
    "net/netip"
    "sync"
    "time"

    "github.com/xjasonlyu/tun2socks/v2/core"
    "github.com/xjasonlyu/tun2socks/v2/core/adapter"
    "github.com/xjasonlyu/tun2socks/v2/core/device/iobased"
    "golang.zx2c4.com/wireguard/tun"
    "gvisor.dev/gvisor/pkg/tcpip/stack"
)

// Dial is required and must bind/protect the socket before connecting on Android.
// The caller owns that enforcement; there is deliberately no default dialer.
type Dial func(context.Context, string, string) (net.Conn, error)
type Policy func(netip.Addr, uint16) bool

type Gateway struct {
    bridge *bridge
    stack *stack.Stack
    link *iobased.Endpoint
    dial Dial
    allow Policy
    ctx context.Context
    cancel context.CancelFunc
    mu sync.Mutex
    closed bool
    active map[net.Conn]struct{}
    flows int
    wg sync.WaitGroup
    once sync.Once
}

// New handles one peer and one fixed source IP; multi-peer identity/isolation is
// deliberately out of scope. IP payloads are meaningful only after WireGuard
// cryptokey routing has authenticated the sender.
func New(source netip.Addr, dial Dial, allow Policy) (*Gateway, error) {
    if !source.Is4() || dial == nil || allow == nil { return nil, errors.New("IPv4 source, protected dialer and destination policy required") }
    ctx, cancel := context.WithCancel(context.Background())
    g := &Gateway{bridge: newBridge(source), dial: dial, allow: allow, ctx: ctx, cancel: cancel, active: make(map[net.Conn]struct{})}
    ep, err := iobased.New(stackIO{g.bridge}, 1280, 0)
    if err != nil { cancel(); return nil, err }
    g.link = ep
    g.stack, err = core.CreateStack(&core.Config{LinkEndpoint: ep, TransportHandler: g})
    if err != nil { g.bridge.Close(); cancel(); return nil, err }
    return g, nil
}

// Tun is handed to wireguard-go. It must never be exposed as an unauthenticated
// packet entry point. WireGuard peer allowed_ip must match source /32.
func (g *Gateway) Tun() tun.Device { return g.bridge }

// Limit accepted flows and retain every socket so shutdown cancels active I/O.
func (g *Gateway) add(c net.Conn) bool {
    g.mu.Lock(); defer g.mu.Unlock()
    if g.closed || g.flows >= 128 { c.Close(); return false }
    g.flows++; g.active[c] = struct{}{}; g.wg.Add(1); return true
}
func (g *Gateway) addRemote(c net.Conn) bool {
    g.mu.Lock(); defer g.mu.Unlock()
    if g.closed { c.Close(); return false }
    g.active[c] = struct{}{}; return true
}
func (g *Gateway) finish(in, out net.Conn) {
    in.Close(); if out != nil { out.Close() }
    g.mu.Lock(); delete(g.active, in); if out != nil { delete(g.active, out) }; g.flows--; g.mu.Unlock(); g.wg.Done()
}
func (g *Gateway) target(ipBytes []byte, port uint16) (string, bool) {
    ip, ok := netip.AddrFromSlice(ipBytes)
    if !ok || !ip.Is4() || port == 0 || !g.allow(ip, port) { return "", false }
    return netip.AddrPortFrom(ip, port).String(), true
}
func (g *Gateway) HandleTCP(c adapter.TCPConn) {
    if !g.add(c) { return }
    go func() {
        var remote net.Conn
        defer func() { g.finish(c, remote) }()
        id := c.ID(); addr, ok := g.target(id.LocalAddress.AsSlice(), id.LocalPort); if !ok { return }
        ctx, cancel := context.WithTimeout(g.ctx, 10*time.Second); defer cancel()
        conn, err := g.dial(ctx, "tcp4", addr); if err != nil { return }
        remote = conn; if !g.addRemote(remote) { return }
        relayTCP(c, remote)
    }()
}
func (g *Gateway) HandleUDP(c adapter.UDPConn) {
    if !g.add(c) { return }
    go func() {
        var remote net.Conn
        defer func() { g.finish(c, remote) }()
        id := c.ID(); addr, ok := g.target(id.LocalAddress.AsSlice(), id.LocalPort); if !ok { return }
        ctx, cancel := context.WithTimeout(g.ctx, 10*time.Second); defer cancel()
        conn, err := g.dial(ctx, "udp4", addr); if err != nil { return }
        remote = conn; if !g.addRemote(remote) { return }
        relayUDP(c, remote)
    }()
}

func relayTCP(a, b net.Conn) {
    results := make(chan error, 2)
    transfer := func(dst, src net.Conn) {
        buf := make([]byte, 32*1024)
        for {
            _ = src.SetReadDeadline(time.Now().Add(2*time.Minute))
            n, err := src.Read(buf)
            if n > 0 { if _, e := dst.Write(buf[:n]); e != nil { results <- e; return } }
            if err != nil {
                if errors.Is(err, io.EOF) { if w, ok := dst.(interface{ CloseWrite() error }); ok { _ = w.CloseWrite() } }
                results <- err; return
            }
        }
    }
    go transfer(a, b); go transfer(b, a)
    err := <-results
    if errors.Is(err, io.EOF) {
        select { case <-results: return; case <-time.After(30*time.Second): }
    }
    _ = a.Close(); _ = b.Close(); <-results
}

func relayUDP(a adapter.UDPConn, b net.Conn) {
    done := make(chan struct{}, 2)
    go func() { defer func(){ done <- struct{}{} }(); buf := make([]byte, 65535); for { _ = a.SetReadDeadline(time.Now().Add(60*time.Second)); n, _, err := a.ReadFrom(buf); if err != nil { return }; if _, err = b.Write(buf[:n]); err != nil { return }; _ = b.SetReadDeadline(time.Now().Add(60*time.Second)) } }()
    go func() { defer func(){ done <- struct{}{} }(); buf := make([]byte, 65535); for { _ = b.SetReadDeadline(time.Now().Add(60*time.Second)); n, err := b.Read(buf); if err != nil { return }; if _, err = a.WriteTo(buf[:n], nil); err != nil { return }; _ = a.SetReadDeadline(time.Now().Add(60*time.Second)) } }()
    <-done; _ = a.Close(); _ = b.Close(); <-done
}

func (g *Gateway) Close() {
    g.once.Do(func() {
        g.mu.Lock(); g.closed = true; g.cancel(); for c := range g.active { _ = c.Close() }; g.mu.Unlock()
        _ = g.bridge.Close()
        g.stack.Close(); g.link.Close(); g.link.Wait(); g.wg.Wait()
    })
}

// PublicIPv4 blocks common local, carrier-grade, documentation, benchmark,
// multicast and reserved ranges. It is a starting policy, not a complete security audit.
func PublicIPv4(ip netip.Addr, port uint16) bool {
    if !ip.Is4() || port == 0 || !ip.IsGlobalUnicast() { return false }
    for _, cidr := range []string{"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4"} {
        if netip.MustParsePrefix(cidr).Contains(ip) { return false }
    }
    return true
}
