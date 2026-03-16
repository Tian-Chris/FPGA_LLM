"""Golden model for ReLU activation (INT16 -> INT16)."""


def relu_golden(x):
    """ReLU: max(0, x) for signed INT16 values."""
    return max(0, x)
