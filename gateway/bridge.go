// Package gateway is an experimental, not Android-integrated, owner data plane.
package gateway

import (
    "encoding/binary"
    "errors"
    "io"
    "net/netip"
    "os"
    "sync"

    "golang.zx2c4.com/wireguard/tun"
)

// bridge is both a wireguard-go TUN and an io.ReadWriter for the netstack link.
// Only one authorized IPv4 source is admitted. Queues are bounded; overflow is
// packet loss, not a fallback to the host's network stack.
type bridge struct {
    source netip.Addr
    inbound chan []byte
    outbound chan []byte
    done chan struct{}
    events chan tun.Event
    once sync.Once
}
func newBridge(source netip.Addr) *bridge {
    b := &bridge{source: source, inbound: make(chan []byte, 256), outbound: make(chan []byte, 256), done: make(chan struct{}), events: make(chan tun.Event, 1)}
    b.events <- tun.EventUp
    return b
}
func (b *bridge) File() *os.File { return nil }
func (b *bridge) Name() (string, error) { return "nexalink", nil }
func (b *bridge) MTU() (int, error) { return 1280, nil }
func (b *bridge) BatchSize() int { return 1 }
func (b *bridge) Events() <-chan tun.Event { return b.events }
func (b *bridge) Close() error { b.once.Do(func() { close(b.done); close(b.events) }); return nil }

// Read returns response packets to WireGuard for encryption.
func (b *bridge) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
    select {
    case <-b.done: return 0, os.ErrClosed
    case p := <-b.outbound:
        if len(bufs) == 0 || len(sizes) == 0 || offset < 0 || offset > len(bufs[0]) || len(bufs[0])-offset < len(p) { return 0, io.ErrShortBuffer }
        sizes[0] = copy(bufs[0][offset:], p)
        return 1, nil
    }
}
// Write receives authenticated decrypted IP packets from wireguard-go. Fragments,
// IPv6 and protocols other than TCP/UDP are not supported by this prototype.
func (b *bridge) Write(bufs [][]byte, offset int) (int, error) {
    for _, buf := range bufs {
        if offset < 0 || offset > len(buf) { return 0, errors.New("invalid packet offset") }
        p := buf[offset:]
        if !b.accept(p) { continue }
        copyOfPacket := append([]byte(nil), p...)
        select { case <-b.done: return 0, os.ErrClosed; case b.inbound <- copyOfPacket: default: }
    }
    return len(bufs), nil
}
func (b *bridge) accept(p []byte) bool {
    if len(p) < 20 || len(p) > 1280 || p[0]>>4 != 4 { return false }
    headerLen := int(p[0]&15)*4
    if headerLen < 20 || headerLen > len(p) || int(binary.BigEndian.Uint16(p[2:4])) != len(p) { return false }
    if binary.BigEndian.Uint16(p[6:8]) & 0x3fff != 0 { return false } // no fragments
    if p[9] != 6 && p[9] != 17 { return false }
    src, ok := netip.AddrFromSlice(p[12:16]); return ok && src == b.source
}

// stackIO faces the gVisor link. Packet boundaries are preserved.
type stackIO struct { b *bridge }
func (s stackIO) Read(p []byte) (int, error) {
    select {
    case <-s.b.done: return 0, os.ErrClosed
    case pkt := <-s.b.inbound:
        if len(p) < len(pkt) { return 0, io.ErrShortBuffer }
        return copy(p, pkt), nil
    }
}
func (s stackIO) Write(p []byte) (int, error) {
    pkt := append([]byte(nil), p...)
    select { case <-s.b.done: return 0, os.ErrClosed; case s.b.outbound <- pkt: return len(p), nil; default: return 0, errors.New("response queue full") }
}
