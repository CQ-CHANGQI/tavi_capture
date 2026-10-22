#!/usr/bin/env python3
"""Publish mock LCM preview + joint data so the Flutter app can be tested.

The packets are built by hand with the Python standard library, exactly like
LCM's `udpm://` wire format:

    short: magic(4) seq(4) channel\\0 payload
    long:  magic(4) seq(4) total(4) offset(4) num(2) count(2) [channel\\0] chunk

The channel name is written only into fragment 0, like lcm_udpm.c / lcm-java.

No `lcm` package, no `lcm-gen`, no Pillow/ffmpeg: the default frame is a
bundled real 640x360 JPEG (`tool/frame_360p.jpg`), and `--image` can send a
different JPEG/PNG instead.

Examples
--------
    # 4 cameras x 20 joints, same shape as the Compose app's real data
    python3 tool/mock_publisher.py --host 127.0.0.1

    # robot LAN / tablet: multicast, pick the Wi-Fi interface explicitly
    python3 tool/mock_publisher.py --interface 192.168.1.23

    # 3 publish rounds (chunked preview_package_t frames)
    python3 tool/mock_publisher.py --host 127.0.0.1 --count 3

    # send a real camera frame; it is sliced into 1200-byte fragments
    python3 tool/mock_publisher.py --image /tmp/frame.jpg --width 1280 --height 720
"""

from __future__ import annotations

import argparse
import math
import multiprocessing
import socket
import struct
import sys
import time
from pathlib import Path

MAGIC_SHORT = 0x4C433032  # "LC02"
MAGIC_LONG = 0x4C433033  # "LC03"
FINGERPRINT = b"\x00" * 8  # the app skips it; a real one is a type hash
PREVIEW_FRAGMENT_PAYLOAD = 1200  # camera_preview.cpp chunk size
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ZERO_ROW = b"\x00" * (128 * 8)

DEFAULT_CAMERAS = ("cam_head", "cam_chest", "cam_left", "cam_right")
DEFAULT_IMAGE = Path(__file__).resolve().with_name("frame_360p.jpg")
JOINT_GROUPS = (("left", 7), ("right", 7), ("body", 4), ("head", 2))


def lcm_string(value: str) -> bytes:
    """int32 length (including NUL) + UTF-8 bytes + NUL."""
    raw = value.encode("utf-8")
    return struct.pack(">i", len(raw) + 1) + raw + b"\x00"


def preview_packages(
    stream_id: int, message_id: int, image: bytes
) -> list[bytes]:
    """Split one encoded frame the way camera_preview.cpp does: 1200-byte
    preview_package_t fragments, one LCM message per fragment.

    The payload is opaque: JPEG on the robot, PNG for the built-in mock.
    """
    total = len(image)
    count = (total + PREVIEW_FRAGMENT_PAYLOAD - 1) // PREVIEW_FRAGMENT_PAYLOAD
    return [
        b"".join(
            (
                FINGERPRINT,
                struct.pack(">q", message_id),
                struct.pack(">i", stream_id),
                struct.pack(">i", index),
                struct.pack(">i", count),
                struct.pack(">i", total),
                struct.pack(">i", len(chunk)),
                chunk,
            )
        )
        for index, chunk in enumerate(
            image[offset : offset + PREVIEW_FRAGMENT_PAYLOAD]
            for offset in range(0, total, PREVIEW_FRAGMENT_PAYLOAD)
        )
    ]


def joint_names(count: int) -> list[str]:
    """Realistic names first (7+7+4+2 = 20), then generic padding."""
    names: list[str] = []
    for prefix, size in JOINT_GROUPS:
        names += [f"{prefix}_joint{i}/position" for i in range(1, size + 1)]
    if count > len(names):
        names += [
            f"joint_{i}/position" for i in range(len(names) + 1, count + 1)
        ]
    return names[:count]


def joint_payload(timestamp_ns: int, joints: int = 20) -> bytes:
    """One `joint_batch_t` frame with `joints` state/command values."""
    names = "\n".join(joint_names(joints))
    state_names = [names] + [""] * 9
    command_names = [names] + [""] * 9
    timestamps = [timestamp_ns] + [0] * 9
    state_counts = [joints] + [0] * 9
    command_counts = [joints] + [0] * 9

    t = timestamp_ns / 1e9
    state = [
        math.sin(2 * math.pi * 0.5 * t + i * 0.5) for i in range(joints)
    ] + [0.0] * (128 - joints)
    command = [
        0.6 * math.sin(2 * math.pi * 0.5 * t + i * 0.5 + 0.3)
        for i in range(joints)
    ] + [0.0] * (128 - joints)

    parts = [
        FINGERPRINT,
        struct.pack(">i", 1),  # num_frames
        struct.pack(">10q", *timestamps),
    ]
    parts += [lcm_string(name) for name in state_names]
    parts += [lcm_string(name) for name in command_names]
    parts.append(struct.pack(">10i", *state_counts))
    parts.append(struct.pack(">10i", *command_counts))
    parts.append(struct.pack(">128d", *state))
    parts += [ZERO_ROW] * 9
    parts.append(struct.pack(">128d", *command))
    parts += [ZERO_ROW] * 9
    return b"".join(parts)


class Sender:
    def __init__(self, host: str, port: int, *, interface: str | None) -> None:
        self.address = (host, port)
        self.sequence = 0
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
        try:
            self.sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
        except OSError:
            pass
        if interface:
            self.sock.setsockopt(
                socket.IPPROTO_IP,
                socket.IP_MULTICAST_IF,
                socket.inet_aton(interface),
            )

    def send(self, channel: str, payload: bytes) -> None:
        self.sequence = (self.sequence + 1) & 0x7FFFFFFF
        channel_bytes = channel.encode("utf-8")
        # macOS caps UDP datagrams at ~9216 bytes (net.inet.udp.maxdgram), and
        # the joint payload is ~21 KB. Fragment well below that so the same
        # command works on macOS, Linux and Windows. Real LCM uses 64 KiB.
        chunk_size = 8000
        needs_fragments = len(payload) + len(channel_bytes) + 1 > chunk_size

        if not needs_fragments:
            packet = (
                struct.pack(">Ii", MAGIC_SHORT, self.sequence)
                + channel_bytes
                + b"\x00"
                + payload
            )
            self.sock.sendto(packet, self.address)
            return

        chunks = [
            payload[i : i + chunk_size]
            for i in range(0, len(payload), chunk_size)
        ]
        for number, chunk in enumerate(chunks):
            header = struct.pack(
                ">Iiiihh",
                MAGIC_LONG,
                self.sequence,
                len(payload),
                number * chunk_size,
                number,
                len(chunks),
            )
            # Real LCM writers (lcm_udpm.c / lcm-java) carry the channel name
            # only in fragment 0; later fragments are raw data after the
            # 20-byte header.
            channel_part = channel_bytes + b"\x00" if number == 0 else b""
            self.sock.sendto(header + channel_part + chunk, self.address)

    def close(self) -> None:
        self.sock.close()


def image_size(data: bytes, fallback: tuple[int, int]) -> tuple[int, int]:
    if data.startswith(PNG_SIGNATURE) and len(data) >= 24:
        return struct.unpack(">II", data[16:24])
    if data.startswith(b"\xff\xd8"):
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            i += 2
            if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
                continue
            segment = struct.unpack(">H", data[i : i + 2])[0]
            if marker in (
                0xC0,
                0xC1,
                0xC2,
                0xC3,
                0xC5,
                0xC6,
                0xC7,
                0xC9,
                0xCA,
                0xCB,
                0xCD,
                0xCE,
                0xCF,
            ):
                height, width = struct.unpack(">HH", data[i + 3 : i + 7])
                return width, height
            i += segment
    return fallback



def _camera_worker(
    camera: str,
    stream_id: int,
    image: bytes,
    host: str,
    port: int,
    interface: str | None,
    preview_hz: float,
    count: int,
) -> None:
    """Send one camera's frames; one process per camera."""
    sender = Sender(host, port, interface=interface)
    channel = f"/preview/cameras/{camera}"
    started = time.monotonic()
    rounds = 0
    try:
        while count == 0 or rounds < count:
            for package in preview_packages(stream_id, time.time_ns(), image):
                sender.send(channel, package)
            rounds += 1
            target = started + rounds / preview_hz
            delay = target - time.monotonic()
            if delay > 0:
                time.sleep(delay)
    except KeyboardInterrupt:
        pass
    finally:
        sender.close()


def _joint_worker(
    host: str,
    port: int,
    interface: str | None,
    joint_hz: float,
    joints: int,
    count: int,
) -> None:
    """Send joint batches in their own process."""
    sender = Sender(host, port, interface=interface)
    started = time.monotonic()
    rounds = 0
    try:
        while count == 0 or rounds < count:
            sender.send(
                "/preview/joint_batch", joint_payload(time.time_ns(), joints)
            )
            rounds += 1
            target = started + rounds / joint_hz
            delay = target - time.monotonic()
            if delay > 0:
                time.sleep(delay)
    except KeyboardInterrupt:
        pass
    finally:
        sender.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Publish mock LCM preview_package_t (1200 B fragments, camera_preview.cpp style) + joint_batch_t traffic."
    )
    parser.add_argument(
        "--host",
        default="239.255.76.67",
        help="multicast group, or 127.0.0.1 for a same-machine test",
    )
    parser.add_argument("--port", type=int, default=7667)
    parser.add_argument(
        "--cameras",
        default=",".join(DEFAULT_CAMERAS),
        help="comma-separated camera names",
    )
    parser.add_argument(
        "--joints",
        type=int,
        default=20,
        help="number of joint state/command values (1-128)",
    )
    parser.add_argument(
        "--interface",
        help="local IP used for outgoing multicast (multi-NIC hosts)",
    )
    parser.add_argument("--preview-hz", type=float, default=15.0)
    parser.add_argument("--joint-hz", type=float, default=15.0)
    parser.add_argument(
        "--count",
        type=int,
        default=0,
        help="frames/batches per worker; 0 means forever",
    )
    parser.add_argument(
        "--image",
        help="JPEG/PNG to send instead of the bundled tool/frame_360p.jpg",
    )
    parser.add_argument(
        "--single-process",
        action="store_true",
        help="send all cameras and joint from one process (old behavior)",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=640,
        help="fallback width if the image header cannot be parsed",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=360,
        help="fallback height if the image header cannot be parsed",
    )
    args = parser.parse_args()

    if args.preview_hz <= 0:
        parser.error("--preview-hz must be > 0")
    if args.count < 0:
        parser.error("--count must be >= 0")
    if not 1 <= args.joints <= 128:
        parser.error("--joints must be between 1 and 128")

    cameras = [c.strip() for c in args.cameras.split(",") if c.strip()]
    if not cameras:
        parser.error("--cameras must contain at least one name")

    image_path = Path(args.image) if args.image else DEFAULT_IMAGE
    try:
        image = image_path.read_bytes()
    except OSError as exc:
        parser.error(f"cannot read image {image_path}: {exc}")
    width, height = image_size(image, (args.width, args.height))
    frames_by_camera = {camera: [image] for camera in cameras}

    joint_channel = "/preview/joint_batch"
    joint_every = max(1, round(args.preview_hz / max(args.joint_hz, 1e-9)))

    single = args.single_process or len(cameras) == 1
    print(
        f"LCM mock -> {args.host}:{args.port}\n"
        f"  cameras {len(cameras)}: {', '.join(cameras)}\n"
        f"  preview {width}x{height}  {args.preview_hz:g} Hz  "
        f"(chunked 1200B, {len(image) // 1000} KB/frame)\n"
        f"  joint   {joint_channel}  {args.joints} values  "
        f"{args.joint_hz:g} Hz\n"
        f"  mode    {'single-process' if single else f'{len(cameras)} camera workers + 1 joint worker'}\n"
        f"  rounds  {args.count or 'infinite'}",
        flush=True,
    )

    if not single:
        procs = []
        try:
            for index, camera in enumerate(cameras):
                proc = multiprocessing.Process(
                    target=_camera_worker,
                    args=(
                        camera,
                        index,
                        image,
                        args.host,
                        args.port,
                        args.interface,
                        args.preview_hz,
                        args.count,
                    ),
                )
                proc.start()
                procs.append(proc)
            proc = multiprocessing.Process(
                target=_joint_worker,
                args=(
                    args.host,
                    args.port,
                    args.interface,
                    args.joint_hz,
                    args.joints,
                    args.count,
                ),
            )
            proc.start()
            procs.append(proc)
            for proc in procs:
                proc.join()
        except KeyboardInterrupt:
            for proc in procs:
                proc.terminate()
            for proc in procs:
                proc.join()
            return 130
        return 1 if any(proc.exitcode not in (0, None) for proc in procs) else 0

    sender = Sender(args.host, args.port, interface=args.interface)
    rounds = 0
    sent_joint = 0
    started = time.monotonic()
    try:
        while args.count == 0 or rounds < args.count:
            timestamp_ns = time.time_ns()
            for index, camera in enumerate(cameras):
                frames = frames_by_camera[camera]
                image = frames[rounds % len(frames)]
                channel = f"/preview/cameras/{camera}"
                for package in preview_packages(index, timestamp_ns, image):
                    sender.send(channel, package)
                # A 150 KB frame is ~125 datagrams; give the receiver a moment
                # to drain before the next camera's burst. Small frames do not
                # need it (keeps the 1200 Hz stress test usable).
                if len(image) > 100_000:
                    time.sleep(0.001)
            if rounds % joint_every == 0:
                sender.send(
                    joint_channel, joint_payload(timestamp_ns, args.joints)
                )
                sent_joint += 1

            rounds += 1
            target = started + rounds / args.preview_hz
            delay = target - time.monotonic()
            if delay > 0:
                time.sleep(delay)
    except KeyboardInterrupt:
        pass
    finally:
        sender.close()

    print(
        f"sent {rounds} rounds ({rounds * len(cameras)} preview), "
        f"{sent_joint} joint",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
