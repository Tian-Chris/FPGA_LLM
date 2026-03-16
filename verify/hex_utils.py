import os


def to_hex(val, width):
    mask = (1 << width) - 1
    return format(val & mask, "0{}x".format(width // 4))


def from_hex(s, width):
    val = int(s, 16)
    if val >= (1 << (width - 1)):
        val -= 1 << width
    return val


def write_hex_file(path, values, width):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for v in values:
            f.write(to_hex(v, width) + "\n")


def read_hex_file(path, width):
    values = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("//"):
                values.append(from_hex(line, width))
    return values


def write_matrix_hex(path, matrix, width):
    flat = []
    for row in matrix:
        flat.extend(row)
    write_hex_file(path, flat, width)


def read_matrix_hex(path, rows, cols, width):
    flat = read_hex_file(path, width)
    matrix = []
    for i in range(rows):
        matrix.append(flat[i * cols : i * cols + cols])
    return matrix
