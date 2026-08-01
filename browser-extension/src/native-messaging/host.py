#!/usr/bin/env python3
import sys
import json
import struct
import urllib.request
import urllib.parse
import urllib.error

# Read a message from stdin and decode it.
def read_message():
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length or len(raw_length) < 4:
        sys.exit(0)
    message_length = struct.unpack('@I', raw_length)[0]
    message = sys.stdin.buffer.read(message_length).decode('utf-8')
    return json.loads(message)

# Send a message to stdout.
def send_message(message):
    encoded = json.dumps(message).encode('utf-8')
    sys.stdout.buffer.write(struct.pack('@I', len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()

def main():
    while True:
        try:
            msg = read_message()
            msg_type = msg.get("type")
            if msg_type == "STATUS":
                try:
                    req = urllib.request.Request("http://127.0.0.1:16235/status")
                    with urllib.request.urlopen(req, timeout=1) as response:
                        res = json.loads(response.read().decode('utf-8'))
                        send_message({
                            "running": True,
                            "locked": res.get("locked", True),
                            "unlocked": res.get("unlocked", False)
                        })
                except Exception:
                    send_message({
                        "running": False,
                        "locked": True,
                        "unlocked": False
                    })
            elif msg_type == "GET_ITEMS":
                origin = msg.get("origin", "")
                try:
                    url = f"http://127.0.0.1:16235/items?origin={urllib.parse.quote(origin)}"
                    req = urllib.request.Request(url)
                    with urllib.request.urlopen(req, timeout=1) as response:
                        res = json.loads(response.read().decode('utf-8'))
                        send_message({
                            "success": True,
                            "locked": res.get("locked", False),
                            "items": res.get("items", [])
                        })
                except Exception as e:
                    send_message({
                        "success": False,
                        "locked": True,
                        "items": [],
                        "error": str(e)
                    })
            else:
                send_message({"error": "Unknown message type"})
        except Exception:
            sys.exit(0)

if __name__ == '__main__':
    main()
