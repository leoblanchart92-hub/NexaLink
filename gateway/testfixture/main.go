// Test-only loopback peer for Android emulator integration tests. It is never
// included in the Android AAR or APK. No host Internet traffic is forwarded.
package main

import (
    "crypto/ecdh"
    "encoding/hex"
    "fmt"
    "log"
    "net"
    "net/netip"
    "os"
    "strings"
    "sync"

    "golang.zx2c4.com/wireguard/conn"
    "golang.zx2c4.com/wireguard/device"
    "golang.zx2c4.com/wireguard/tun/netstack"
)

// A deliberately loopback-only WireGuard bind: this diagnostic does not open
// a listening service on a network interface of the CI host.
type endpoint struct { addr netip.AddrPort }
func (e *endpoint) ClearSrc() {}
func (e *endpoint) SrcToString() string { return "127.0.0.1" }
func (e *endpoint) DstToString() string { return e.addr.String() }
func (e *endpoint) DstToBytes() []byte { return []byte(e.addr.String()) }
func (e *endpoint) DstIP() netip.Addr { return e.addr.Addr() }
func (e *endpoint) SrcIP() netip.Addr { return netip.MustParseAddr("127.0.0.1") }
type loopbackBind struct { mu sync.Mutex; socket *net.UDPConn }
func (b *loopbackBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
    b.mu.Lock(); defer b.mu.Unlock()
    if b.socket != nil { return nil, 0, conn.ErrBindAlreadyOpen }
    c, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127,0,0,1), Port: int(port)})
    if err != nil { return nil, 0, err }
    b.socket = c
    receive := func(packets [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
        n, addr, err := c.ReadFromUDPAddrPort(packets[0]); if err != nil { return 0, err }
        if n > 0 { log.Printf("peer wire rx type=%d bytes=%d", packets[0][0], n) }
        sizes[0] = n; eps[0] = &endpoint{addr}; return 1, nil
    }
    return []conn.ReceiveFunc{receive}, uint16(c.LocalAddr().(*net.UDPAddr).Port), nil
}
func (b *loopbackBind) Close() error {
    b.mu.Lock(); defer b.mu.Unlock()
    if b.socket == nil { return nil }
    err := b.socket.Close(); b.socket = nil; return err
}
func (b *loopbackBind) SetMark(uint32) error { return nil }
func (b *loopbackBind) Send(bufs [][]byte, ep conn.Endpoint) error {
    e, ok := ep.(*endpoint); if !ok || !e.addr.Addr().IsLoopback() { return conn.ErrWrongEndpointType }
    b.mu.Lock(); defer b.mu.Unlock()
    if b.socket == nil { return net.ErrClosed }
    for _, p := range bufs {
        if _, err := b.socket.WriteToUDPAddrPort(p, e.addr); err != nil { return err }
        if len(p) > 0 { log.Printf("peer wire tx type=%d bytes=%d", p[0], len(p)) }
    }
    return nil
}
func (*loopbackBind) ParseEndpoint(s string) (conn.Endpoint, error) {
    a, err := netip.ParseAddrPort(s); if err != nil { return nil, err }; return &endpoint{a}, nil
}
func (*loopbackBind) BatchSize() int { return 1 }

func main() {
    // Fixed, public test vectors only: never use these keys outside this test.
    ownerPrivate := []byte(strings.Repeat("b", 32))
    guestPrivate, err := ecdh.X25519().NewPrivateKey([]byte(strings.Repeat("a", 32))); if err != nil { log.Fatal(err) }
    tun, stack, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("198.18.0.1")}, nil, 1280); if err != nil { log.Fatal(err) }
    wg := device.NewDevice(tun, &loopbackBind{}, device.NewLogger(device.LogLevelSilent, "")); defer wg.Close()
    config := fmt.Sprintf("private_key=%s\nlisten_port=38673\npublic_key=%s\nallowed_ip=10.77.0.2/32\n", hex.EncodeToString(ownerPrivate), hex.EncodeToString(guestPrivate.PublicKey().Bytes()))
    if err = wg.IpcSet(config); err != nil { log.Fatal("fixture configuration failed") }
    if err = wg.Up(); err != nil { log.Fatal("fixture startup failed: ", err) }
    echo, err := stack.ListenUDPAddrPort(netip.MustParseAddrPort("198.18.0.1:5555")); if err != nil { log.Fatal(err) }
    defer echo.Close()
    fmt.Println("READY loopback-only WireGuard test peer")
    buf := make([]byte, 2048)
    for {
        n, addr, err := echo.ReadFrom(buf); if err != nil { fmt.Fprintln(os.Stderr, "echo stopped"); return }
        log.Printf("peer decrypted UDP packets=1 bytes=%d", n)
        if _, err = echo.WriteTo(buf[:n], addr); err != nil { log.Print("echo write failed: ", err) } else { log.Print("peer echo sent packets=1") }
    }
}
