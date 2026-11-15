"""Przekształcenia układów współrzędnych Morrowind ↔ Godot/glTF.

Morrowind (i NIF): prawoskrętny, oś Z w górę, +Y na północ, jednostka gry.
glTF 2.0 i Godot: prawoskrętny, oś Y w górę, -Z „do przodu”, metry.

Odwzorowanie osi (obrót o -90° wokół X, wyznacznik +1, nawinięcie trójkątów bez zmian):
    x_g =  x_mw
    y_g =  z_mw
    z_g = -y_mw
Skala: 1 m = 69.99125109 jednostek (stała OpenMW `Constants::UnitsPerMeter`, czyli 22.1 jedn./stopę
z oryginalnych założeń gry). Północ Morrowinda (+Y) staje się -Z Godota.
"""

from __future__ import annotations

import math

import numpy as np

UNITS_PER_METER = 69.99125109
SCALE = 1.0 / UNITS_PER_METER

# M: p_g = SCALE * M @ p_mw
M = np.array([[1.0, 0.0, 0.0],
              [0.0, 0.0, 1.0],
              [0.0, -1.0, 0.0]])
M_INV = M.T

CELL_SIZE = 8192  # jednostek na komórkę zewnętrzną


def pos_to_godot(p, scale: float = SCALE) -> np.ndarray:
    p = np.asarray(p, dtype=np.float64)
    return (p @ M.T) * scale


def pos_from_godot(p, scale: float = SCALE) -> np.ndarray:
    p = np.asarray(p, dtype=np.float64)
    return (p @ M) / scale


def dir_to_godot(v) -> np.ndarray:
    return np.asarray(v, dtype=np.float64) @ M.T


def rot_to_godot(R) -> np.ndarray:
    return M @ np.asarray(R, dtype=np.float64) @ M.T


def rot_from_godot(R) -> np.ndarray:
    return M.T @ np.asarray(R, dtype=np.float64) @ M


def _rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def _ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def _rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def mw_ref_rotation(rot) -> np.ndarray:
    """Macierz obrotu referencji (ESM Position.rot, radiany) w układzie Morrowinda.

    Zgodnie z konwencją silnika: kolejno obrót o -rz wokół Z, -ry wokół Y, -rx wokół X
    (obroty „zgodnie z ruchem wskazówek zegara”), czyli w zapisie kolumnowym R = Rx(-rx)·Ry(-ry)·Rz(-rz).
    """
    rx, ry, rz = rot
    return _rx(-rx) @ _ry(-ry) @ _rz(-rz)


def mw_ref_rotation_inverse(R) -> tuple:
    """Odwrotność `mw_ref_rotation`: macierz → (rx, ry, rz)."""
    R = np.asarray(R, dtype=np.float64)
    # R = Rx(a)·Ry(b)·Rz(c) z a=-rx, b=-ry, c=-rz
    sb = max(-1.0, min(1.0, R[0, 2]))
    b = math.asin(sb)
    if abs(sb) < 0.999999:
        a = math.atan2(-R[1, 2], R[2, 2])
        c = math.atan2(-R[0, 1], R[0, 0])
    else:
        a = math.atan2(R[2, 1], R[1, 1])
        c = 0.0
    return (-a, -b, -c)


def mat_to_quat(R) -> np.ndarray:
    """Macierz obrotu 3×3 → kwaternion (x, y, z, w) w konwencji glTF."""
    R = np.asarray(R, dtype=np.float64)
    tr = R[0, 0] + R[1, 1] + R[2, 2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        w = 0.25 * s
        x = (R[2, 1] - R[1, 2]) / s
        y = (R[0, 2] - R[2, 0]) / s
        z = (R[1, 0] - R[0, 1]) / s
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = math.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2
        w = (R[2, 1] - R[1, 2]) / s
        x = 0.25 * s
        y = (R[0, 1] + R[1, 0]) / s
        z = (R[0, 2] + R[2, 0]) / s
    elif R[1, 1] > R[2, 2]:
        s = math.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2
        w = (R[0, 2] - R[2, 0]) / s
        x = (R[0, 1] + R[1, 0]) / s
        y = 0.25 * s
        z = (R[1, 2] + R[2, 1]) / s
    else:
        s = math.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2
        w = (R[1, 0] - R[0, 1]) / s
        x = (R[0, 2] + R[2, 0]) / s
        y = (R[1, 2] + R[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w])
    q /= np.linalg.norm(q)
    if q[3] < 0:
        q = -q
    return q


def quat_to_mat(q) -> np.ndarray:
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def nif_quat_to_godot(wxyz) -> np.ndarray:
    """Kwaternion NIF (w, x, y, z) w układzie Morrowinda → (x, y, z, w) w układzie glTF.

    Obrót o kąt θ wokół osi a przechodzi w obrót o θ wokół M·a (M jest obrotem, det = +1).
    """
    w, x, y, z = (float(v) for v in wxyz)
    v = M @ np.array([x, y, z])
    q = np.array([v[0], v[1], v[2], w])
    n = np.linalg.norm(q)
    return q / n if n > 0 else np.array([0, 0, 0, 1.0])


def is_orthonormal(R, tol: float = 1e-3) -> bool:
    R = np.asarray(R, dtype=np.float64)
    return bool(np.allclose(R @ R.T, np.eye(3), atol=tol) and np.linalg.det(R) > 0)


def trs_matrix(t, R, s) -> np.ndarray:
    m = np.eye(4)
    m[:3, :3] = np.asarray(R, dtype=np.float64) * s
    m[:3, 3] = t
    return m


def ref_transform_to_godot(pos, rot, scale: float) -> dict:
    """Pozycja/obrót/skala referencji ESM → transform Godota (basis 3×3, origin)."""
    R = rot_to_godot(mw_ref_rotation(rot))
    return {"origin": pos_to_godot(pos).tolist(), "basis": (R * scale).tolist(), "quat": mat_to_quat(R).tolist(),
            "scale": scale}
