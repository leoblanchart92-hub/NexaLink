// Test-only loopback peer for Android emulator integration tests. It is never
// included in the Android AAR or APK. No host Internet traffic is forwarded.
package main

import (
    "crypto/ecdh"
    "encoding/binary"
    "encoding/hex"
    "fmt"
    "log"
    "net"
    "net/netip"
    "os"
    "strings"
    "sync"
    "sync/atomic"

    "golang.zx2c4.com/wireguard/conn"
    "golang.zx2c4.com/wireguard/device"
    "golang.zx2c4.com/wireguard/tun"
    "golang.zx2c4.com/wireguard/tun/netstack"
)

// The peer's memory TUN is independent of Android's TUN. Its counters prove
// only transfers at the peer boundary. Correlation uses the public test payload
// after decryption; encrypted WireGuard datagrams cannot carry that identifier.
type countedTun struct { tun.Device; reads atomic.Uint64; writes atomic.Uint64 }
func cycleID(payload []byte) string {
    if (len(payload) != 9 && len(payload) != 11) || !strings.HasPrefix(string(payload), "cycle:") { return "unavailable" }
    for _, c := range payload[6:9] { if c < '0' || c > '9' { return "unavailable" } }
    id := string(payload[6:9])
    if len(payload) == 11 { if payload[9] != ':' || (payload[10] != 'A' && payload[10] != 'B') { return "unavailable" }; id += string(payload[9:]) }
    return id
}
func packetCycle(packet []byte) string {
    if len(packet) < 28 || packet[0] >> 4 != 4 || packet[9] != 17 { return "unavailable" }
    ihl := int(packet[0] & 15) * 4
    if ihl < 20 || len(packet) < ihl+8 { return "unavailable" }
    size := int(binary.BigEndian.Uint16(packet[ihl+4:ihl+6]))
    if size < 8 || size > len(packet)-ihl { return "unavailable" }
    return cycleID(packet[ihl+8:ihl+size])
}
func (c *countedTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
    n, err := c.Device.Read(bufs, sizes, offset)
    for i := 0; i < n; i++ {
        count := c.reads.Add(1)
        if sizes[i] >= 0 && offset >= 0 && offset+sizes[i] <= len(bufs[i]) {
            log.Printf("peer tun read cycle=%s count=%d", packetCycle(bufs[i][offset:offset+sizes[i]]), count)
        }
    }
    return n, err
}
func (c *countedTun) Write(bufs [][]byte, offset int) (int, error) {
    n, err := c.Device.Write(bufs, offset)
    for i := 0; i < n && i < len(bufs); i++ {
        count := c.writes.Add(1)
        if offset >= 0 && offset <= len(bufs[i]) { log.Printf("peer tun write cycle=%s count=%d", packetCycle(bufs[i][offset:]), count) }
    }
    return n, err
}

// A deliberately loopback-only WireGuard bind: this diagnostic does not open
// a listening service on a network interface of the CI host.
type endpoint struct { addr netip.AddrPort }
func (e *endpoint) ClearSrc() {}
func (e *endpoint) SrcToString() string { return "127.0.0.1" }
func (e *endpoint) DstToString() string { return e.addr.String() }
func (e *endpoint) DstToBytes() []byte { return []byte(e.addr.String()) }
func (e *endpoint) DstIP() netip.Addr { return e.addr.Addr() }
func (e *endpoint) SrcIP() netip.Addr { return netip.MustParseAddr("127.0.0.1") }
type loopbackBind struct { mu sync.Mutex; socket *net.UDPConn; rx atomic.Uint64; tx atomic.Uint64 }
func (b *loopbackBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
    b.mu.Lock(); defer b.mu.Unlock()
    if b.socket != nil { return nil, 0, conn.ErrBindAlreadyOpen }
    c, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127,0,0,1), Port: int(port)})
    if err != nil { return nil, 0, err }
    b.socket = c
    receive := func(packets [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
        n, addr, err := c.ReadFromUDPAddrPort(packets[0]); if err != nil { return 0, err }
        if n > 0 { log.Printf("peer wire rx cycle=unavailable type=%d bytes=%d count=%d", packets[0][0], n, b.rx.Add(1)) }
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
        if len(p) > 0 { log.Printf("peer wire tx cycle=unavailable type=%d bytes=%d count=%d", p[0], len(p), b.tx.Add(1)) }
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
    wg := device.NewDevice(&countedTun{Device: tun}, &loopbackBind{}, device.NewLogger(device.LogLevelSilent, "")); defer wg.Close()
    config := fmt.Sprintf("private_key=%s\nlisten_port=38673\npublic_key=%s\nallowed_ip=10.77.0.2/32\n", hex.EncodeToString(ownerPrivate), hex.EncodeToString(guestPrivate.PublicKey().Bytes()))
    if err = wg.IpcSet(config); err != nil { log.Fatal("fixture configuration failed") }
    if err = wg.Up(); err != nil { log.Fatal("fixture startup failed: ", err) }
    echo, err := stack.ListenUDPAddrPort(netip.MustParseAddrPort("198.18.0.1:5555")); if err != nil { log.Fatal(err) }
    defer echo.Close()
    fmt.Println("READY loopback-only WireGuard test peer")
    buf := make([]byte, 2048)
    for {
        n, addr, err := echo.ReadFrom(buf); if err != nil { fmt.Fprintln(os.Stderr, "echo stopped"); return }
        cycle := cycleID(buf[:n])
        log.Printf("peer decrypted UDP cycle=%s packets=1 bytes=%d", cycle, n)
        if _, err = echo.WriteTo(buf[:n], addr); err != nil { log.Print("echo write failed: ", err) } else { log.Printf("peer echo sent cycle=%s packets=1", cycle) }
    }
}
