#!/usr/bin/env python3
"""UDP latency proxy for network tests (#266, tools/hosthits_test.gd).

Sits between game clients and a server and delays every datagram, each way,
by --delay-ms (+ up to --jitter-ms of random extra, order preserved), so a
headless match on one machine plays like one over the internet: ENet and the
game's own round-trip probes measure about 2 x delay.

    python3 tools/udp_lag_proxy.py --listen 27001 --to 127.0.0.1:27000 \
        --delay-ms 60 --jitter-ms 8 [--seed 1] [--secs 300]

Clients connect to the --listen port; each client address gets its own
upstream socket to the server. Stops after --secs (or on SIGTERM).
"""
import argparse
import asyncio
import random
import signal
import sys


class _Upstream(asyncio.DatagramProtocol):
    def __init__(self, proxy, client_addr):
        self.proxy = proxy
        self.client_addr = client_addr
        self.transport = None
        self.last_t = 0.0

    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, addr):
        # server -> client
        self.last_t = self.proxy.schedule(self.last_t, self.proxy.down.sendto, data, self.client_addr)


class _Proxy(asyncio.DatagramProtocol):
    def __init__(self, loop, target, delay, jitter, rng):
        self.loop = loop
        self.target = target
        self.delay = delay
        self.jitter = jitter
        self.rng = rng
        self.down = None
        self.clients = {}   # addr -> [upstream protocol, last scheduled t, pending packets]

    def connection_made(self, transport):
        self.down = transport

    def schedule(self, last_t, fn, *args):
        t = self.loop.time() + self.delay + self.rng.random() * self.jitter
        t = max(t, last_t + 0.00001)   # never reorder
        self.loop.call_at(t, self._safe, fn, *args)
        return t

    @staticmethod
    def _safe(fn, *args):
        try:
            fn(*args)
        except Exception:
            pass

    def datagram_received(self, data, addr):
        # client -> server
        c = self.clients.get(addr)
        if c is None:
            c = [None, 0.0, []]
            self.clients[addr] = c
            self.loop.create_task(self._open(addr, c))
        if c[0] is None or c[0].transport is None:
            c[2].append(data)
            return
        c[1] = self.schedule(c[1], c[0].transport.sendto, data)

    async def _open(self, addr, c):
        _, proto = await self.loop.create_datagram_endpoint(
            lambda: _Upstream(self, addr), remote_addr=self.target)
        c[0] = proto
        for data in c[2]:
            c[1] = self.schedule(c[1], proto.transport.sendto, data)
        c[2].clear()


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", type=int, required=True)
    ap.add_argument("--to", required=True, help="host:port of the server")
    ap.add_argument("--delay-ms", type=float, default=50.0)
    ap.add_argument("--jitter-ms", type=float, default=0.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--secs", type=float, default=600.0)
    a = ap.parse_args()
    host, port = a.to.rsplit(":", 1)
    loop = asyncio.get_running_loop()
    proxy = _Proxy(loop, (host, int(port)), a.delay_ms / 1000.0, a.jitter_ms / 1000.0, random.Random(a.seed))
    await loop.create_datagram_endpoint(lambda: proxy, local_addr=("127.0.0.1", a.listen))
    print("LAGPROXY listening on %d -> %s delay=%.0fms jitter=%.0fms" % (a.listen, a.to, a.delay_ms, a.jitter_ms), flush=True)
    stop = loop.create_future()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: stop.done() or stop.set_result(None))
    try:
        await asyncio.wait_for(stop, timeout=a.secs)
    except asyncio.TimeoutError:
        pass


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
