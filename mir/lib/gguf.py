"""Optional, bounded GGUF metadata inspection; never read or allocate tensors."""

import os
import struct
import sys


def role(path):
    try:
        with open(path, "rb") as stream:
            # Leave unknown or oversized metadata selectable.
            # llama.cpp decides model compatibility.
            limit = min(os.fstat(stream.fileno()).st_size, 32 * 1024 * 1024)
            operations = 0
            endian = "<"

            def read(size):
                nonlocal operations
                operations += 1
                if operations > 500000 or size < 0 or stream.tell() + size > limit:
                    raise ValueError("Metadata inspection limit")
                data = stream.read(size)
                if len(data) != size:
                    raise ValueError("Truncated metadata")
                return data

            def number(fmt):
                return struct.unpack(endian + fmt, read(struct.calcsize(fmt)))[0]

            def skip(size):
                if size < 0 or stream.tell() + size > limit:
                    raise ValueError("Metadata inspection limit")
                stream.seek(size, 1)

            def string(keep=False):
                size = number("Q")
                if keep and size <= 4096:
                    return read(size).decode("utf-8")
                skip(size)
                return ""

            scalar_types = {0: "B", 1: "b", 2: "H", 3: "h", 4: "I", 5: "i",
                            6: "f", 7: "?", 10: "Q", 11: "q", 12: "d"}

            def value(kind, keep=False):
                if kind in scalar_types:
                    return number(scalar_types[kind])
                if kind == 8:
                    return string(keep)
                if kind != 9:
                    raise ValueError("Unknown metadata type")
                subtype, count = number("I"), number("Q")
                if subtype in scalar_types:
                    skip(struct.calcsize(scalar_types[subtype]) * count)
                elif subtype == 8 and count <= 100000:
                    for _ in range(count):
                        string()
                else:
                    raise ValueError("Unsupported metadata array")

            if read(4) != b"GGUF":
                return "unknown"
            version = read(4)
            if struct.unpack("<I", version)[0] not in (2, 3):
                endian = ">"
            if struct.unpack(endian + "I", version)[0] not in (2, 3):
                return "unknown"
            number("Q")  # Tensor count.
            count = number("Q")
            if count > 100000:
                return "unknown"
            result = "model"
            for _ in range(count):
                key = string(True)
                item = value(number("I"), key == "general.type")
                if key == "split.no" and isinstance(item, int) and item > 0:
                    result = "continuation"
                elif key == "general.type" and item in ("mmproj", "adapter"):
                    result = "component"
            return result
    except (OSError, ValueError, UnicodeError, struct.error):
        return "unknown"


if __name__ == "__main__":
    for filename in sys.stdin.buffer.read().split(b"\0"):
        if filename:
            sys.stdout.buffer.write(role(os.fsdecode(filename)).encode() + b"\0")
