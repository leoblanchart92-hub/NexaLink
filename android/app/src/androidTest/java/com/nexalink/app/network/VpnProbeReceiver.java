package com.nexalink.app.network;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Process;
import android.util.Log;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;

/** Standalone test APK process: deliberately has no Kotlin or app dependencies. */
public final class VpnProbeReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        final PendingResult pending = goAsync();
        new Thread(() -> {
            Bundle result = new Bundle();
            result.putInt("uid", Process.myUid());
            try (DatagramSocket socket = new DatagramSocket()) {
                byte[] bytes = {1, 2, 3};
                socket.send(new DatagramPacket(bytes, bytes.length,
                        InetAddress.getByName("198.18.0.1"), 5555));
                result.putBoolean("sent", true);
                if (intent.getBooleanExtra("expectEcho", false)) {
                    socket.setSoTimeout(8000);
                    byte[] reply = new byte[128];
                    DatagramPacket response = new DatagramPacket(reply, reply.length);
                    socket.receive(response);
                    result.putBoolean("echo", response.getLength() == 3 &&
                            reply[0] == 1 && reply[1] == 2 && reply[2] == 3 &&
                            response.getAddress().equals(InetAddress.getByName("198.18.0.1")) &&
                            response.getPort() == 5555);
                }
                Log.i("NexaLinkVPN", "Test APK UID sent routed UDP probe");
            } catch (Exception failure) {
                result.putString("error", failure.getClass().getSimpleName());
                Log.w("NexaLinkVPN", "Test APK UID probe failed: " + failure.getClass().getSimpleName());
            } finally {
                pending.setResultExtras(result);
                pending.finish();
            }
        }, "vpn-test-probe").start();
    }
}
