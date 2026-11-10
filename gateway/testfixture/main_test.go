package main

import (
    "encoding/binary"
    "testing"
)

func TestCycleIdentifiersInPeerPackets(t *testing.T) {
    for _, test := range []struct{ payload, want string }{
        {"cycle:016", "016"}, {"cycle:016:A", "016:A"}, {"cycle:016:B", "016:B"},
        {"cycle:016:C", "unavailable"}, {"cycle:xx6:A", "unavailable"}, {"private", "unavailable"},
    } {
        if got := cycleID([]byte(test.payload)); got != test.want { t.Errorf("payload %q: got %q, want %q", test.payload, got, test.want) }
        packet := make([]byte, 28+len(test.payload))
        packet[0], packet[9] = 0x45, 17
        binary.BigEndian.PutUint16(packet[24:26], uint16(8+len(test.payload)))
        copy(packet[28:], test.payload)
        if got := packetCycle(packet); got != test.want { t.Errorf("packet %q: got %q, want %q", test.payload, got, test.want) }
    }
    if packetCycle([]byte{0x45}) != "unavailable" { t.Error("truncated packet accepted") }
}
