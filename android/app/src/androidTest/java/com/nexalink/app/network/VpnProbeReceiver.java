package com.nexalink.app.network;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.RouteInfo;
import android.os.Bundle;
import android.os.SystemClock;
import android.os.Process;
import android.system.ErrnoException;
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
            String phase = "network";
            try {
                if (intent.getBooleanExtra("expectStopped", false)) {
                    ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
                    long deadline = SystemClock.elapsedRealtime() + 4000;
                    boolean gone = false;
                    do {
                        Network active = cm.getActiveNetwork();
                        NetworkCapabilities caps = active == null ? null : cm.getNetworkCapabilities(active);
                        if (caps == null || !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) { gone = true; break; }
                        Thread.sleep(50);
                    } while (SystemClock.elapsedRealtime() < deadline);
                    result.putBoolean("vpnGone", gone);
                    return;
                }
                {
                    ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
                    long deadline = SystemClock.elapsedRealtime() + 4000;
                    boolean ready = false;
                    do {
                        Network active = cm.getActiveNetwork();
                        NetworkCapabilities caps = active == null ? null : cm.getNetworkCapabilities(active);
                        LinkProperties links = active == null ? null : cm.getLinkProperties(active);
                        if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && links != null) {
                            for (RouteInfo route : links.getRoutes()) {
                                if (route.matches(InetAddress.getByName("198.18.0.1"))) { ready = true; break; }
                            }
                            if (ready) {
                                Log.i("NexaLinkVPN", "Test UID VPN handle=" + active.getNetworkHandle());
                                break;
                            }
                        }
                        Thread.sleep(50);
                    } while (SystemClock.elapsedRealtime() < deadline);
                    result.putBoolean("vpnReady", ready);
                    if (!ready) throw new IllegalStateException("VPN is not active for test UID");
                }
                phase = "socket";
                try (DatagramSocket socket = new DatagramSocket()) {
                byte[] bytes = {1, 2, 3};
                phase = "send";
                socket.send(new DatagramPacket(bytes, bytes.length,
                        InetAddress.getByName("198.18.0.1"), 5555));
                result.putBoolean("sent", true);
                if (intent.getBooleanExtra("expectEcho", false)) {
                    phase = "receive";
                    socket.setSoTimeout(4500);
                    byte[] reply = new byte[128];
                    DatagramPacket response = new DatagramPacket(reply, reply.length);
                    socket.receive(response);
                    result.putBoolean("echo", response.getLength() == 3 &&
                            reply[0] == 1 && reply[1] == 2 && reply[2] == 3 &&
                            response.getAddress().equals(InetAddress.getByName("198.18.0.1")) &&
                            response.getPort() == 5555);
                }
                Log.i("NexaLinkVPN", "Test APK UID sent routed UDP probe");
                }
            } catch (Exception failure) {
                int errno = 0;
                for (Throwable cause = failure; cause != null; cause = cause.getCause()) {
                    if (cause instanceof ErrnoException) { errno = ((ErrnoException) cause).errno; break; }
                }
                result.putString("error", phase + ":" + failure.getClass().getSimpleName() + ":errno=" + errno);
                Log.w("NexaLinkVPN", "Test APK UID probe failed at " + phase + ": " + failure.getClass().getSimpleName() + ", errno=" + errno);
            } finally {
                pending.setResultExtras(result);
                pending.finish();
            }
        }, "vpn-test-probe").start();
    }
}
