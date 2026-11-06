package mobile

import (
    "context"
    "encoding/base64"
    "errors"
    "net"
    "strings"
    "testing"

    "golang.zx2c4.com/wireguard/conn"
)

type binder struct { calls []int32; allow bool }
func (b *binder) BindSocket(fd int32) bool { b.calls = append(b.calls, fd); return b.allow }
type fakeBind struct { closed bool; fail6 bool }
func (f *fakeBind) Open(p uint16) ([]conn.ReceiveFunc,uint16,error) { return nil, 1234, nil }
func (f *fakeBind) Close() error { f.closed = true; return nil }
func (f *fakeBind) SetMark(uint32) error { return nil }
func (f *fakeBind) Send([][]byte,conn.Endpoint) error { return nil }
func (f *fakeBind) ParseEndpoint(string) (conn.Endpoint,error) { return nil,nil }
func (f *fakeBind) BatchSize() int { return 1 }
func (f *fakeBind) PeekLookAtSocketFd4() (int,error) { return 10,nil }
func (f *fakeBind) PeekLookAtSocketFd6() (int,error) { if f.fail6 { return -1,errors.New("no socket") }; return 11,nil }

func TestProtectedBindFailClosed(t *testing.T) {
    for _, tc := range []struct {allow,fail6,want bool}{{true,false,true},{false,false,false},{true,true,false}} {
        raw:=&fakeBind{fail6:tc.fail6}; cb:=&binder{allow:tc.allow}; b:=&cellularBind{Bind:raw,binder:cb}
        _,_,err:=b.Open(0); if (err==nil)!=tc.want {t.Fatalf("unexpected error %v",err)}
        if !tc.want && !raw.closed {t.Fatal("failed bind must close sockets")}
        if tc.want && (len(cb.calls)!=2 || raw.closed) {t.Fatal("both sockets must be protected")}
    }
}
func TestLifecycleAndConfigurationErrors(t *testing.T) {
    if _,err:=NewEngine(nil); err==nil {t.Fatal("nil binder accepted")}
    cb:=&binder{allow:false}; e,err:=NewEngine(cb); if err!=nil {t.Fatal(err)}
    key:=base64.StdEncoding.EncodeToString([]byte(strings.Repeat("a",32)))
    other:=base64.StdEncoding.EncodeToString([]byte(strings.Repeat("b",32)))
    for _, tc:=range []struct {priv,pub,ip string; port int32}{{"bad",other,"10.77.0.2",0},{key,other,"8.8.8.8",0},{key,other,"10.77.0.2",-1}} {
        if _,err:=e.Start(tc.priv,tc.pub,tc.ip,tc.port); err==nil {t.Fatal("invalid configuration accepted")}
    }
    // On a non-Android host, the bind cannot expose both Android descriptors.
    if _,err:=e.Start(key,other,"10.77.0.2",0); err==nil { e.Stop(); t.Fatal("unprotected endpoint started") }
    e.Stop(); e.Stop()
    status,err:=e.StatusJSON(); if err!=nil || !strings.Contains(status,`"running":false`) {t.Fatalf("unexpected status %s %v",status,err)}
}
func TestDialerFailsClosed(t *testing.T) {
    listener,err:=net.Listen("tcp4","127.0.0.1:0"); if err!=nil {t.Fatal(err)}; defer listener.Close()
    b:=&binder{allow:false}; c,err:=dialer(b)(context.Background(),"tcp4",listener.Addr().String()); if err==nil {c.Close(); t.Fatal("unbound dial succeeded")}; if len(b.calls)!=1 {t.Fatal("binder not invoked")}
    if _,err:=dialer(b)(context.Background(),"tcp4","example.com:80"); err==nil {t.Fatal("hostname unexpectedly resolved")}
}
