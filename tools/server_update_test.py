#!/usr/bin/env python3
"""Gate A `srvupdate` (#320): tools/server_kit/update_server.py against a fake
GitHub release on 127.0.0.1, signed with a throw-away key (openssl), the
signature checked by the real game (Godot --verify-update with that key).

  python3 tools/server_update_test.py --godot "<godot> --headless --path <repo>"

Cases: --check sees the update; a tampered archive, a missing .sig and an
archive whose VERSION.txt disagrees with the tag are refused with the install
untouched; the good one installs (server.cfg kept, old files in
_update/previous, exec bits); a second run and an older release are "up to
date". Prints SRVUPDATE-TEST ok (...) / SRVUPDATE-TEST FAIL ...; exit 0 / 1.
"""
import argparse, functools, http.server, io, json, os, shutil, subprocess, sys, tarfile, tempfile, threading

HERE = os.path.dirname(os.path.abspath(__file__))
UPDATER = os.path.join(HERE, "server_kit", "update_server.py")
ASSET = "TracerfallServer-linux.tar.gz"


def fake_bin(version):
    return "#!/bin/sh\necho \"Tracerfall %s\"\n" % version


def make_archive(path, version, binary_version=None):
    files = {
        "VERSION.txt": (version + "\n", 0o644),
        "TracerfallServer.x86_64": (fake_bin(binary_version or version), 0o755),
        "start-server.sh": ("#!/bin/sh\necho new %s\n" % version, 0o755),
        "server.cfg.example": ("name = example\n", 0o644),
    }
    with tarfile.open(path, "w:gz") as t:
        for name, (text, mode) in files.items():
            data = text.encode()
            ti = tarfile.TarInfo("TracerfallServer/" + name)
            ti.size = len(data)
            ti.mode = mode
            t.addfile(ti, io.BytesIO(data))


def sign(key, path):
    subprocess.run(["openssl", "dgst", "-sha256", "-sign", key, "-out", path + ".sig", path], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    args = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="srvupdate-")
    bad = []
    try:
        key, pub = os.path.join(tmp, "k.pem"), os.path.join(tmp, "pub.pem")
        subprocess.run(["openssl", "genrsa", "-out", key, "2048"], check=True, capture_output=True)
        subprocess.run(["openssl", "rsa", "-in", key, "-pubout", "-out", pub], check=True, capture_output=True)
        web = os.path.join(tmp, "web")
        os.makedirs(web)
        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *a):
                pass
        handler = functools.partial(Quiet, directory=web)
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d/" % srv.server_address[1]

        inst = os.path.join(tmp, "TracerfallServer")
        os.makedirs(inst)
        for name, text, mode in (("VERSION.txt", "1.0.0\n", 0o644), ("TracerfallServer.x86_64", fake_bin("1.0.0"), 0o755),
                                 ("start-server.sh", "#!/bin/sh\necho old\n", 0o755), ("server.cfg", "name = keep me\n", 0o644)):
            with open(os.path.join(inst, name), "w") as f:
                f.write(text)
            os.chmod(os.path.join(inst, name), mode)

        def release(tag, version=None, with_sig=True, tamper=False, binary_version=None):
            for f in os.listdir(web):
                os.remove(os.path.join(web, f))
            arc = os.path.join(web, ASSET)
            make_archive(arc, version or tag, binary_version)
            sign(key, arc)
            if tamper:
                with open(arc, "ab") as f:
                    f.write(b"\0tampered")
            assets = [{"name": ASSET, "size": os.path.getsize(arc), "browser_download_url": base + ASSET}]
            if with_sig:
                assets.append({"name": ASSET + ".sig", "size": os.path.getsize(arc + ".sig"), "browser_download_url": base + ASSET + ".sig"})
            with open(os.path.join(web, "latest.json"), "w") as f:
                json.dump({"tag_name": "v" + tag, "assets": assets}, f)

        def run(*extra):
            r = subprocess.run([sys.executable, UPDATER, "--dir", inst, "--api-url", base + "latest.json",
                                "--godot", args.godot, "--pubkey", pub] + list(extra), capture_output=True, text=True, timeout=300)
            return r.returncode, r.stdout + r.stderr

        def version():
            return open(os.path.join(inst, "VERSION.txt")).read().strip()

        def expect(label, rc_want, text_want, ver_want):
            def check(rc, out):
                if rc != rc_want or text_want not in out or version() != ver_want:
                    bad.append("%s: rc=%d want %d, version %s want %s, out=%s" % (label, rc, rc_want, version(), ver_want, out.strip().replace("\n", " | ")[-300:]))
            return check

        release("9.9.9")
        expect("check", 10, "UPDATE available: 9.9.9", "1.0.0")(*run("--check"))
        release("9.9.9", tamper=True)
        expect("tampered", 1, "signature check failed", "1.0.0")(*run())
        release("9.9.9", with_sig=False)
        expect("no-sig", 1, "refusing an unsigned update", "1.0.0")(*run())
        release("9.9.9", version="9.9.8")
        expect("version-mismatch", 1, "the download says it is 9.9.8", "1.0.0")(*run())
        release("9.9.9", binary_version="1.0.0")
        expect("binary-version", 1, "the new server program reports", "1.0.0")(*run())
        if os.path.exists(os.path.join(inst, "_update", "previous", "VERSION.txt")):
            bad.append("a refused update left files in _update/previous")
        release("9.9.9")
        expect("install", 0, "UPDATE installed 9.9.9 (was 1.0.0)", "9.9.9")(*run())
        if open(os.path.join(inst, "server.cfg")).read() != "name = keep me\n":
            bad.append("server.cfg changed")
        prev = os.path.join(inst, "_update", "previous", "VERSION.txt")
        if not os.path.exists(prev) or open(prev).read().strip() != "1.0.0":
            bad.append("old files not kept in _update/previous")
        if not os.access(os.path.join(inst, "TracerfallServer.x86_64"), os.X_OK) or not os.access(os.path.join(inst, "start-server.sh"), os.X_OK):
            bad.append("exec bit lost")
        if "new 9.9.9" not in open(os.path.join(inst, "start-server.sh")).read():
            bad.append("start-server.sh not replaced")
        expect("again", 0, "UPDATE up to date: installed 9.9.9", "9.9.9")(*run())
        release("0.5.0")
        expect("older", 0, "UPDATE up to date", "9.9.9")(*run())
        srv.shutdown()
    except Exception as e:
        bad.append("error: %r" % e)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if bad:
        print("SRVUPDATE-TEST FAIL " + " || ".join(bad))
        return 1
    print("SRVUPDATE-TEST ok (check, tampered / unsigned / wrong-version / wrong-binary refused, install keeps server.cfg + backup, up to date x2)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
