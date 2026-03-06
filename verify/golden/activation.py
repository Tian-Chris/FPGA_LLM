from .common import int16

def relu_golden(x):
    x = int16(x)
    if x < 0:
      return 0
    return x