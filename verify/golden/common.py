"""Common fixed-point helpers matching RTL conventions."""


def clamp(val, lo, hi):
    if val < lo:
        return lo
    if val > hi:
        return hi
    return val


def int8(val):
    """Wrap to signed 8-bit range."""
    val = val & 0xFF
    return val - 256 if val >= 128 else val


def int16(val):
    """Wrap to signed 16-bit range."""
    val = val & 0xFFFF
    return val - 65536 if val >= 32768 else val


def int32(val):
    """Wrap to signed 32-bit range."""
    val = val & 0xFFFFFFFF
    return val - (1 << 32) if val >= (1 << 31) else val


def uint32(val):
    """Wrap to unsigned 32-bit range."""
    return val & 0xFFFFFFFF


def saturate_int16(val):
    """Saturate a wider value to signed 16-bit [-32768, 32767]."""
    return clamp(val, -32768, 32767)


def saturate_int8(val):
    """Saturate a wider value to signed 8-bit [-128, 127]."""
    return clamp(val, -128, 127)


def arithmetic_right_shift(val, shift, width=32):
    """Arithmetic right shift matching Verilog >>>."""
    mask = (1 << width) - 1
    val = val & mask
    if val >= (1 << (width - 1)):
        val -= 1 << width
    return val >> shift
