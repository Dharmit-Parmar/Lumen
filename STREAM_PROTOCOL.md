# Lumen video stream protocol v1

The phone is the TCP server on port `5000`; the Mac is the client. The byte stream carries one message at a time. TCP may split a message across reads or combine several messages into one read, so receivers must read the full 16-byte header and then the declared payload length.

## Message header

All integer fields are unsigned and big-endian.

| Offset | Size | Field | Value / meaning |
| ---: | ---: | --- | --- |
| 0 | 2 | Magic | `0x4c 0x55` (`LU`) |
| 2 | 1 | Version | `1` |
| 3 | 4 | Payload length | Bytes after this 16-byte header; maximum `8,388,608` |
| 7 | 1 | Type | `1` config, `2` H.264 keyframe access unit, `3` H.264 delta access unit |
| 8 | 8 | Timestamp | Phone monotonic capture time in microseconds; `0` for config |

Reject and close the connection on an unknown version/type, wrong magic, empty payload, or payload length above the maximum. Do not attempt byte-by-byte resynchronization. A clean TCP reconnect starts a new stream.

## Config message (type 1)

Config is always the first message on every connection. Its payload is:

| Field | Size | Meaning |
| --- | ---: | --- |
| Codec | 1 | `1` = H.264 / AVC |
| Width | 2 | Encoded frame width in pixels |
| Height | 2 | Encoded frame height in pixels |
| FPS | 2 | Nominal integer frame rate |
| Rotation | 2 | Clockwise display rotation: `0`, `90`, `180`, or `270` degrees |
| Mirror | 1 | `0` = no mirror, `1` = mirrored horizontally |
| SPS length | 2 | SPS NAL byte count |
| SPS | variable | One raw SPS NAL, including its NAL header; no Annex-B start code |
| PPS length | 2 | PPS NAL byte count |
| PPS | variable | One raw PPS NAL, including its NAL header; no Annex-B start code |

The fixed config fields total 12 bytes, excluding the SPS and PPS NAL bytes. Reject zero dimensions/FPS, unsupported rotation/mirror values, missing SPS/PPS, or a config payload longer than 65,536 bytes. Version 1 carries one SPS and one PPS.

## Video messages (types 2 and 3)

The payload is exactly one complete H.264 access unit in Annex-B form. Every NAL unit, including the first, starts with the four-byte sequence `00 00 00 01`. Type 2 contains an IDR keyframe; type 3 contains a non-IDR access unit. Timestamps are monotonic microseconds from the phone's monotonic clock and represent capture time. They are not wall-clock time and are not directly comparable to the Mac clock.

The phone sends config, then requests an IDR frame. It must send that keyframe before any delta frame. After reconnect, the same handshake repeats. The Mac feeds every access unit to VideoToolbox in order and keeps only the newest decoded image for display.

## Transport behavior

- Use `TCP_NODELAY` on both ends. The phone binds to loopback at port `5000`; development connects through `adb forward tcp:5000 tcp:5000`. Loopback keeps the MVP service off the phone's Wi-Fi network.
- There is no in-band acknowledgement or error message. EOF or malformed input closes the connection; the Mac reconnects with backoff.
- A connected client that receives no config within one second is treated as a failed connection attempt.
- Do not drop an individual delta frame. If the phone cannot keep up with the socket, stop sending dependent frames and request a fresh keyframe before resuming.
- Config and frame payloads use the same maximum length from the header table; receivers must also enforce the smaller config limit.
