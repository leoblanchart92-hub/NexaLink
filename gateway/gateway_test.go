package gateway

import (
    "context"
    "crypto/ecdh"
    "crypto/rand"
    "encoding/binary"
    "encoding/hex"
    "fmt"
    "io"
    "net"
    "net/netip"
    "strings"
    "sync/atomic"
    "testing"
    "time"

    "golang.org/x/net/dns/dnsmessage"
    wgconn "golang.zx2c4.com/wireguard/conn"
    "golang.zx2c4.com/wireguard/device"
    "golang.zx2c4.com/wireguard/tun"
    "golang.zx2c4.com/wireguard/tun/netstack"
)

// This decorator measures actual packet transfers at each WireGuard TUN
// boundary; it does not inject packets or alter the data path.
type countedTun struct {
    tun.Device
    reads atomic.Uint64
    writes atomic.Uint64
}
func (c *countedTun) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
    n, err := c.Device.Read(bufs, sizes, offset)
    if n > 0 { c.reads.Add(uint64(n)) }
    return n, err
}
func (c *countedTun) Write(bufs [][]byte, offset int) (int, error) {
    n, err := c.Device.Write(bufs, offset)
    if n > 0 { c.writes.Add(uint64(n)) }
    return n, err
}

func TestPacketAndPolicy(t *testing.T) {
    source := netip.MustParseAddr("10.77.0.2")
    b := newBridge(source); defer b.Close()
    p := make([]byte, 28); p[0] = 0x45; binary.BigEndian.PutUint16(p[2:4], uint16(len(p))); p[9] = 17; copy(p[12:16], source.AsSlice())
    if !b.accept(p) { t.Fatal("valid packet dropped") }
    p[12] = 11; if b.accept(p) { t.Fatal("spoofed source accepted") }; p[12] = 10
    p[6] = 0x20; if b.accept(p) { t.Fatal("fragment accepted") }; p[6] = 0
    p[9] = 1; if b.accept(p) { t.Fatal("ICMP accepted") }; p[9] = 17
    p[0] = 0x60; if b.accept(p) { t.Fatal("IPv6 accepted") }; p[0] = 0x45
    binary.BigEndian.PutUint16(p[2:4], 999); if b.accept(p) { t.Fatal("wrong length accepted") }
    for _, s := range []string{"127.0.0.1", "10.0.0.1", "100.64.0.1", "169.254.1.1", "192.168.1.1", "224.0.0.1", "::1"} {
        if PublicIPv4(netip.MustParseAddr(s), 53) { t.Fatalf("%s allowed", s) }
    }
    if !PublicIPv4(netip.MustParseAddr("1.1.1.1"), 53) { t.Fatal("public destination blocked") }
    if _, err := New(source, nil, PublicIPv4); err == nil { t.Fatal("dialer must be explicit") }
}

func keypair(t *testing.T) (string,string) {
    t.Helper(); k, err := ecdh.X25519().GenerateKey(rand.Reader); if err != nil { t.Fatal(err) }
    return hex.EncodeToString(k.Bytes()), hex.EncodeToString(k.PublicKey().Bytes())
}

func dnsMessage(t *testing.T) ([]byte, []byte) {
    t.Helper()
    n := dnsmessage.MustNewName("example.test.")
    q, err := (&dnsmessage.Message{Header: dnsmessage.Header{ID: 0x1234, RecursionDesired: true}, Questions: []dnsmessage.Question{{Name: n, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET}}}).Pack()
    if err != nil { t.Fatal(err) }
    a, err := (&dnsmessage.Message{Header: dnsmessage.Header{ID: 0x1234, Response: true, RecursionAvailable: true}, Questions: []dnsmessage.Question{{Name: n, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET}}, Answers: []dnsmessage.Resource{{Header: dnsmessage.ResourceHeader{Name: n, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET, TTL: 30}, Body: &dnsmessage.AResource{A: [4]byte{1,2,3,4}}}}}).Pack()
    if err != nil { t.Fatal(err) }
    return q, a
}

func TestWireGuardTCPUDPDNSRoundTrip(t *testing.T) {
    // Real UDP WireGuard encryption/handshake, in-process netstacks, and real
    // loopback TCP/UDP sockets. No root, Internet or Android device involved.
    query, response := dnsMessage(t)
    tcpListener, err := net.Listen("tcp4", "127.0.0.1:0"); if err != nil { t.Fatal(err) }; defer tcpListener.Close()
    udpListener, err := net.ListenPacket("udp4", "127.0.0.1:0"); if err != nil { t.Fatal(err) }; defer udpListener.Close()
    closedUpstream := make(chan struct{}, 1)
    go func() { for { c, e := tcpListener.Accept(); if e != nil { return }; go func() { defer c.Close(); _ = c.SetDeadline(time.Now().Add(10*time.Second)); size := make([]byte, 2); if _, e := io.ReadFull(c,size); e != nil { return }; l:=int(binary.BigEndian.Uint16(size)); buf:=make([]byte,l); if _, e := io.ReadFull(c,buf); e != nil { return }; out:=buf; if string(buf)==string(query) { out=response }; binary.BigEndian.PutUint16(size,uint16(len(out))); _,_=c.Write(append(size,out...)); if string(buf)=="hold" { _,_=io.Copy(io.Discard,c); closedUpstream <- struct{}{} } }() } }()
    go func() { buf:=make([]byte,65535); for { n, addr, e := udpListener.ReadFrom(buf); if e != nil { return }; out:=buf[:n]; if string(out)==string(query) { out=response }; _,_=udpListener.WriteTo(out,addr) } }()
    dialer := &net.Dialer{}
    // Synthetic remote IP traverses the stacks, while this test-only dialer
    // redirects strictly to local servers. Never used by the Android application.
    dial := func(ctx context.Context, network, addr string) (net.Conn, error) {
        host, port, e := net.SplitHostPort(addr)
        if e != nil || host != "1.1.1.1" { return nil, fmt.Errorf("unexpected destination") }
        var want string
        if network == "tcp4" { want = tcpListener.Addr().String() } else if network == "udp4" { want = udpListener.LocalAddr().String() } else { return nil, fmt.Errorf("unexpected network") }
        _, expectedPort, _ := net.SplitHostPort(want)
        if port != expectedPort { return nil, fmt.Errorf("unexpected port") }
        return dialer.DialContext(ctx, network, want)
    }
    g, err := New(netip.MustParseAddr("10.77.0.2"), dial, func(ip netip.Addr, port uint16) bool { return ip == netip.MustParseAddr("1.1.1.1") }); if err != nil { t.Fatal(err) }
    defer g.Close()
    ownerPrivate, ownerPublic := keypair(t); guestPrivate, guestPublic := keypair(t)
    logger := device.NewLogger(device.LogLevelSilent, "")
    ownerTun := &countedTun{Device: g.Tun()}
    owner := device.NewDevice(ownerTun, wgconn.NewDefaultBind(), logger); defer owner.Close()
    if err := owner.IpcSet(fmt.Sprintf("private_key=%s\nlisten_port=0\npublic_key=%s\nallowed_ip=10.77.0.2/32\n", ownerPrivate, guestPublic)); err != nil { t.Fatal(err) }
    if err := owner.Up(); err != nil { t.Fatal(err) }
    settings, err := owner.IpcGet(); if err != nil { t.Fatal(err) }
    port := ""; for _, line := range strings.Split(settings,"\n") { if strings.HasPrefix(line,"listen_port=") { port=strings.TrimPrefix(line,"listen_port=") } }; if port=="" || port=="0" { t.Fatalf("missing port") }
    guestTun, guestNet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.77.0.2")}, nil, 1280); if err != nil { t.Fatal(err) }
    countedGuest := &countedTun{Device: guestTun}
    guest := device.NewDevice(countedGuest, wgconn.NewDefaultBind(), logger); defer guest.Close()
    if err := guest.IpcSet(fmt.Sprintf("private_key=%s\npublic_key=%s\nallowed_ip=0.0.0.0/0\nendpoint=127.0.0.1:%s\npersistent_keepalive_interval=25\n", guestPrivate, ownerPublic, port)); err != nil { t.Fatal(err) }
    if err := guest.Up(); err != nil { t.Fatal(err) }

    _, tcpPort, _ := net.SplitHostPort(tcpListener.Addr().String())
    _, udpPort, _ := net.SplitHostPort(udpListener.LocalAddr().String())
    tcpTarget, udpTarget := net.JoinHostPort("1.1.1.1", tcpPort), net.JoinHostPort("1.1.1.1", udpPort)
    tcpExchange := func(payload, want []byte) {
        t.Helper(); ctx,cancel:=context.WithTimeout(context.Background(), 15*time.Second); defer cancel()
        c,e:=guestNet.DialContext(ctx,"tcp",tcpTarget); if e!=nil { t.Fatal(e) }; defer c.Close(); _=c.SetDeadline(time.Now().Add(10*time.Second))
        hdr:=make([]byte,2); binary.BigEndian.PutUint16(hdr,uint16(len(payload))); if _,e=c.Write(append(hdr,payload...)); e!=nil {t.Fatal(e)}
        if _,e=io.ReadFull(c,hdr); e!=nil {t.Fatal(e)}; out:=make([]byte,int(binary.BigEndian.Uint16(hdr))); if _,e=io.ReadFull(c,out); e!=nil {t.Fatal(e)}; if string(out)!=string(want) {t.Fatal("incorrect TCP response")}
    }
    udpExchange := func(payload, want []byte) {
        t.Helper(); c,e:=guestNet.DialContext(context.Background(),"udp",udpTarget); if e!=nil {t.Fatal(e)}; defer c.Close(); _=c.SetDeadline(time.Now().Add(10*time.Second)); if _,e=c.Write(payload); e!=nil {t.Fatal(e)}; buf:=make([]byte,4096); n,e:=c.Read(buf); if e!=nil {t.Fatal(e)}; if string(buf[:n])!=string(want) {t.Fatal("incorrect UDP response")}
    }
    // Wrong public key: encrypted packets cannot traverse the owner's peer.
    badPrivate, _ := keypair(t)
    badTun, badNet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.77.0.2")}, nil, 1280); if err != nil { t.Fatal(err) }
    bad := device.NewDevice(badTun, wgconn.NewDefaultBind(), logger)
    if err := bad.IpcSet(fmt.Sprintf("private_key=%s\npublic_key=%s\nallowed_ip=0.0.0.0/0\nendpoint=127.0.0.1:%s\n", badPrivate, ownerPublic, port)); err != nil { t.Fatal(err) }
    if err := bad.Up(); err != nil { t.Fatal(err) }
    badSocket, err := badNet.DialContext(context.Background(), "udp", udpTarget); if err != nil { t.Fatal(err) }
    _ = badSocket.SetDeadline(time.Now().Add(500*time.Millisecond))
    if _, err := badSocket.Write([]byte("unauthorized")); err != nil { t.Fatal(err) }
    buf := make([]byte,128); if _, err := badSocket.Read(buf); err == nil { t.Fatal("unauthorized peer received response") }
    _ = badSocket.Close(); bad.Close()
    if ownerTun.writes.Load() != 0 { t.Fatal("unauthorized peer reached owner TUN") }

    tcpExchange([]byte("tcp-payload"),[]byte("tcp-payload"))
    udpExchange([]byte("udp-payload"),[]byte("udp-payload"))
    tcpExchange(query,response)
    udpExchange(query,response)
    if ownerTun.reads.Load() == 0 || ownerTun.writes.Load() == 0 || countedGuest.reads.Load() == 0 || countedGuest.writes.Load() == 0 {
        t.Fatalf("missing TUN packet direction: owner read=%d write=%d guest read=%d write=%d",
            ownerTun.reads.Load(), ownerTun.writes.Load(), countedGuest.reads.Load(), countedGuest.writes.Load())
    }
    t.Logf("TUN packets owner read=%d write=%d guest read=%d write=%d", ownerTun.reads.Load(), ownerTun.writes.Load(), countedGuest.reads.Load(), countedGuest.writes.Load())
    var parsed dnsmessage.Message; if e:=parsed.Unpack(response); e!=nil || !parsed.Response || len(parsed.Answers)!=1 { t.Fatalf("invalid DNS response: %v",e) }
    // Closing the gateway must actively close a live outgoing socket.
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second); defer cancel()
    held, err := guestNet.DialContext(ctx, "tcp", tcpTarget); if err != nil { t.Fatal(err) }
    _ = held.SetDeadline(time.Now().Add(5*time.Second))
    if _, err := held.Write([]byte{0,4,'h','o','l','d'}); err != nil { t.Fatal(err) }
    ack := make([]byte,6); if _, err := io.ReadFull(held, ack); err != nil { t.Fatal(err) }
    g.Close()
    select { case <-closedUpstream: case <-time.After(5*time.Second): t.Fatal("gateway left upstream socket open") }
    _ = held.Close()
}
