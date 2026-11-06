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
    "testing"
    "time"

    "golang.org/x/net/dns/dnsmessage"
    wgconn "golang.zx2c4.com/wireguard/conn"
    "golang.zx2c4.com/wireguard/device"
    "golang.zx2c4.com/wireguard/tun/netstack"
)

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
    go func() { for { c, e := tcpListener.Accept(); if e != nil { return }; go func() { defer c.Close(); _ = c.SetDeadline(time.Now().Add(10*time.Second)); size := make([]byte, 2); if _, e := io.ReadFull(c,size); e != nil { return }; l:=int(binary.BigEndian.Uint16(size)); buf:=make([]byte,l); if _, e := io.ReadFull(c,buf); e != nil { return }; out:=buf; if string(buf)==string(query) { out=response }; binary.BigEndian.PutUint16(size,uint16(len(out))); _,_=c.Write(append(size,out...)) }() } }()
    go func() { buf:=make([]byte,65535); for { n, addr, e := udpListener.ReadFrom(buf); if e != nil { return }; out:=buf[:n]; if string(out)==string(query) { out=response }; _,_=udpListener.WriteTo(out,addr) } }()
    dialer := &net.Dialer{}
    // Only this isolated test permits loopback. Production policy must reject it.
    g, err := New(netip.MustParseAddr("10.77.0.2"), dialer.DialContext, func(ip netip.Addr, port uint16) bool { return ip == netip.MustParseAddr("127.0.0.1") }); if err != nil { t.Fatal(err) }
    defer g.Close()
    ownerPrivate, ownerPublic := keypair(t); guestPrivate, guestPublic := keypair(t)
    logger := device.NewLogger(device.LogLevelSilent, "")
    owner := device.NewDevice(g.Tun(), wgconn.NewDefaultBind(), logger); defer owner.Close()
    if err := owner.IpcSet(fmt.Sprintf("private_key=%s\nlisten_port=0\npublic_key=%s\nallowed_ip=10.77.0.2/32\n", ownerPrivate, guestPublic)); err != nil { t.Fatal(err) }
    if err := owner.Up(); err != nil { t.Fatal(err) }
    settings, err := owner.IpcGet(); if err != nil { t.Fatal(err) }
    port := ""; for _, line := range strings.Split(settings,"\n") { if strings.HasPrefix(line,"listen_port=") { port=strings.TrimPrefix(line,"listen_port=") } }; if port=="" || port=="0" { t.Fatalf("missing port") }
    guestTun, guestNet, err := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("10.77.0.2")}, nil, 1280); if err != nil { t.Fatal(err) }
    guest := device.NewDevice(guestTun, wgconn.NewDefaultBind(), logger); defer guest.Close()
    if err := guest.IpcSet(fmt.Sprintf("private_key=%s\npublic_key=%s\nallowed_ip=0.0.0.0/0\nendpoint=127.0.0.1:%s\npersistent_keepalive_interval=25\n", guestPrivate, ownerPublic, port)); err != nil { t.Fatal(err) }
    if err := guest.Up(); err != nil { t.Fatal(err) }

    tcpExchange := func(payload, want []byte) {
        t.Helper(); ctx,cancel:=context.WithTimeout(context.Background(), 15*time.Second); defer cancel()
        c,e:=guestNet.DialContext(ctx,"tcp",tcpListener.Addr().String()); if e!=nil { t.Fatal(e) }; defer c.Close(); _=c.SetDeadline(time.Now().Add(10*time.Second))
        hdr:=make([]byte,2); binary.BigEndian.PutUint16(hdr,uint16(len(payload))); if _,e=c.Write(append(hdr,payload...)); e!=nil {t.Fatal(e)}
        if _,e=io.ReadFull(c,hdr); e!=nil {t.Fatal(e)}; out:=make([]byte,int(binary.BigEndian.Uint16(hdr))); if _,e=io.ReadFull(c,out); e!=nil {t.Fatal(e)}; if string(out)!=string(want) {t.Fatal("incorrect TCP response")}
    }
    udpExchange := func(payload, want []byte) {
        t.Helper(); c,e:=guestNet.DialContext(context.Background(),"udp",udpListener.LocalAddr().String()); if e!=nil {t.Fatal(e)}; defer c.Close(); _=c.SetDeadline(time.Now().Add(10*time.Second)); if _,e=c.Write(payload); e!=nil {t.Fatal(e)}; buf:=make([]byte,4096); n,e:=c.Read(buf); if e!=nil {t.Fatal(e)}; if string(buf[:n])!=string(want) {t.Fatal("incorrect UDP response")}
    }
    tcpExchange([]byte("tcp-payload"),[]byte("tcp-payload"))
    udpExchange([]byte("udp-payload"),[]byte("udp-payload"))
    tcpExchange(query,response)
    udpExchange(query,response)
    var parsed dnsmessage.Message; if e:=parsed.Unpack(response); e!=nil || !parsed.Response || len(parsed.Answers)!=1 { t.Fatalf("invalid DNS response: %v",e) }
}
