from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

try:
    import winreg
except ImportError:  # pragma: no cover - Windows-only tool
    winreg = None

from fontTools.ttLib import TTCollection, TTFont
from fontTools.varLib import instancer


FONT_REGISTRY = r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
WINDOWS_FONT_DIR = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts"
USER_FONT_DIR = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft" / "Windows" / "Fonts"


@dataclass(frozen=True)
class Face:
    path: Path
    index: int | None
    families: tuple[str, ...]
    subfamily: str
    full_name: str
    postscript_name: str
    weight: int
    italic: bool
    variable: bool
    axes: tuple[str, ...]


def normalize(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip().casefold()


def safe_name(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-") or "font"


def name_values(font: TTFont, name_id: int) -> list[str]:
    values: list[str] = []
    for record in font["name"].names:
        if record.nameID != name_id:
            continue
        try:
            value = record.toUnicode()
        except Exception:
            continue
        if value and value not in values:
            values.append(value)
    return values


def first_name(font: TTFont, *name_ids: int, default: str = "") -> str:
    for name_id in name_ids:
        values = name_values(font, name_id)
        if values:
            return values[0]
    return default


def font_weight(font: TTFont, style: str) -> int:
    if "OS/2" in font:
        return int(getattr(font["OS/2"], "usWeightClass", 400) or 400)
    text = style.casefold()
    if "black" in text:
        return 900
    if "bold" in text:
        return 700
    if "semibold" in text or "demibold" in text:
        return 600
    if "light" in text:
        return 300
    return 400


def font_italic(font: TTFont, style: str) -> bool:
    if "head" in font and getattr(font["head"], "macStyle", 0) & 0x02:
        return True
    if "OS/2" in font and getattr(font["OS/2"], "fsSelection", 0) & 0x01:
        return True
    return "italic" in style.casefold() or "oblique" in style.casefold()


def font_ext(font: TTFont) -> str:
    if "glyf" in font or "gvar" in font:
        return ".ttf"
    return ".otf"


def registry_font_files() -> list[Path]:
    files: list[Path] = []
    if winreg is None:
        return files

    roots = [
        (winreg.HKEY_LOCAL_MACHINE, WINDOWS_FONT_DIR),
        (winreg.HKEY_CURRENT_USER, USER_FONT_DIR),
    ]
    for root, base_dir in roots:
        try:
            key = winreg.OpenKey(root, FONT_REGISTRY)
        except OSError:
            continue
        try:
            count = winreg.QueryInfoKey(key)[1]
            for i in range(count):
                try:
                    _name, value, _kind = winreg.EnumValue(key, i)
                except OSError:
                    continue
                if not isinstance(value, str):
                    continue
                path = Path(os.path.expandvars(value))
                if not path.is_absolute():
                    path = base_dir / value
                if path.exists() and path.suffix.lower() in {".ttf", ".otf", ".ttc", ".otc"}:
                    files.append(path)
        finally:
            winreg.CloseKey(key)

    for base in (WINDOWS_FONT_DIR, USER_FONT_DIR):
        if base.exists():
            for pattern in ("*.ttf", "*.otf", "*.ttc", "*.otc"):
                files.extend(base.glob(pattern))

    unique: list[Path] = []
    seen: set[str] = set()
    for path in files:
        key = str(path).casefold()
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique


def inspect_file(path: Path) -> list[Face]:
    faces: list[Face] = []
    try:
        if path.suffix.lower() in {".ttc", ".otc"}:
            collection = TTCollection(str(path))
            fonts = list(enumerate(collection.fonts))
        else:
            fonts = [(None, TTFont(str(path), lazy=True))]
    except Exception:
        return faces

    for index, font in fonts:
        families = []
        for name_id in (16, 1):
            for value in name_values(font, name_id):
                if value not in families:
                    families.append(value)
        subfamily = first_name(font, 17, 2, default="Regular")
        full_name = first_name(font, 4, default=families[0] if families else path.stem)
        postscript = first_name(font, 6, default=safe_name(full_name))
        variable = "fvar" in font
        axes = tuple(axis.axisTag for axis in font["fvar"].axes) if variable else ()
        faces.append(
            Face(
                path=path,
                index=index,
                families=tuple(families),
                subfamily=subfamily,
                full_name=full_name,
                postscript_name=postscript,
                weight=font_weight(font, subfamily + " " + full_name),
                italic=font_italic(font, subfamily + " " + full_name),
                variable=variable,
                axes=axes,
            )
        )
    return faces


def scan_faces() -> list[Face]:
    faces: list[Face] = []
    for path in registry_font_files():
        faces.extend(inspect_file(path))
    return faces


def match_family(faces: Iterable[Face], family: str) -> list[Face]:
    wanted = normalize(family)
    matched = []
    for face in faces:
        if any(normalize(name) == wanted for name in face.families):
            matched.append(face)
    return matched


def load_font(face: Face) -> TTFont:
    if face.index is None:
        return TTFont(str(face.path))
    return TTFont(str(face.path), fontNumber=face.index)


def choose_face(faces: list[Face], weight: int, italic: bool, prefer_variable: bool = False) -> Face:
    candidates = [face for face in faces if face.italic == italic]
    if not candidates:
        candidates = faces[:]
    if not candidates:
        raise RuntimeError("No usable source faces were found.")

    def score(face: Face) -> tuple[int, int, int]:
        variable_penalty = 0 if (prefer_variable and face.variable) or (not prefer_variable and not face.variable) else 1
        return (variable_penalty, abs(face.weight - weight), 0 if "Regular" in face.subfamily else 1)

    return sorted(candidates, key=score)[0]


def variable_face(faces: list[Face]) -> Face | None:
    candidates = [face for face in faces if face.variable and not face.italic]
    if not candidates:
        return None
    with_wght = [face for face in candidates if "wght" in face.axes]
    return (with_wght or candidates)[0]


def clear_names(font: TTFont) -> None:
    remove = {1, 2, 3, 4, 6, 16, 17, 18, 21, 22, 25}
    font["name"].names = [record for record in font["name"].names if record.nameID not in remove]


def set_name(font: TTFont, name_id: int, value: str, lang_id: int = 0x0409) -> None:
    font["name"].setName(value, name_id, 3, 1, lang_id)
    font["name"].setName(value, name_id, 3, 10, lang_id)


def patch_metrics(font: TTFont, weight: int, italic: bool) -> None:
    if "OS/2" in font:
        font["OS/2"].usWeightClass = weight
        font["OS/2"].fsSelection &= ~(0x01 | 0x20 | 0x40)
        if italic:
            font["OS/2"].fsSelection |= 0x01
        if weight >= 700:
            font["OS/2"].fsSelection |= 0x20
        if weight == 400 and not italic:
            font["OS/2"].fsSelection |= 0x40
    if "head" in font:
        if italic:
            font["head"].macStyle |= 0x02
        else:
            font["head"].macStyle &= ~0x02
        if weight >= 700:
            font["head"].macStyle |= 0x01
        else:
            font["head"].macStyle &= ~0x01


def apply_synthetic_oblique(font: TTFont, angle_degrees: float = 11.0) -> bool:
    shear = math.tan(math.radians(angle_degrees))
    changed = False
    if "glyf" in font:
        glyf = font["glyf"]
        for glyph_name in font.getGlyphOrder():
            glyph = glyf[glyph_name]
            if glyph.isComposite():
                try:
                    glyph.expand(glyf)
                except Exception:
                    continue
            coordinates = getattr(glyph, "coordinates", None)
            if not coordinates:
                continue
            for index, (x, y) in enumerate(coordinates):
                coordinates[index] = (int(round(x + y * shear)), y)
            glyph.recalcBounds(glyf)
            changed = True

    if "post" in font:
        font["post"].italicAngle = -abs(angle_degrees)
    if "hhea" in font:
        font["hhea"].caretSlopeRise = 1000
        font["hhea"].caretSlopeRun = int(round(shear * 1000))
    return changed


def axis_location(font: TTFont, weight: int) -> dict[str, float]:
    if "fvar" not in font:
        return {}

    location: dict[str, float] = {}
    for axis in font["fvar"].axes:
        value = float(axis.defaultValue)
        if axis.axisTag == "wght":
            value = float(weight)
        # Keep the generated font's Windows-facing weight class at the
        # requested Segoe UI value, but do not ask the source VF for a value
        # outside its real design space.
        location[axis.axisTag] = max(float(axis.minValue), min(float(axis.maxValue), value))
    return location


def instantiate_if_needed(font: TTFont, weight: int) -> TTFont:
    location = axis_location(font, weight)
    if location:
        return instancer.instantiateVariableFont(font, location, inplace=False)
    return font


def make_font(
    face: Face,
    family: str,
    subfamily: str,
    full_name: str,
    postscript_name: str,
    weight: int,
    italic: bool,
    keep_variable: bool = False,
    typographic_family: str | None = None,
    typographic_subfamily: str | None = None,
    zh_family: str | None = None,
    zh_full_name: str | None = None,
    synthetic_oblique: bool = False,
) -> TTFont:
    font = load_font(face)
    if not keep_variable:
        font = instantiate_if_needed(font, weight)
    if synthetic_oblique:
        apply_synthetic_oblique(font)

    clear_names(font)
    set_name(font, 1, family)
    set_name(font, 2, subfamily)
    set_name(font, 3, f"{full_name}; Windows System Font Modifier")
    set_name(font, 4, full_name)
    set_name(font, 6, postscript_name)
    if typographic_family:
        set_name(font, 16, typographic_family)
    if typographic_subfamily:
        set_name(font, 17, typographic_subfamily)
    if zh_family:
        set_name(font, 1, zh_family, 0x0804)
    if zh_full_name:
        set_name(font, 4, zh_full_name, 0x0804)
    patch_metrics(font, weight, italic)
    font["name"].names.sort(key=lambda r: (r.nameID, r.platformID, r.platEncID, r.langID))
    return font


def save_font(font: TTFont, out_dir: Path, filename: str) -> str:
    path = out_dir / filename
    font.save(str(path))
    return filename


def build(source_family: str, out_dir: Path, manifest: Path) -> None:
    faces = match_family(scan_faces(), source_family)
    if not faces:
        raise SystemExit(f"Installed font family not found: {source_family}")

    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = "WSFM-" + hashlib.sha1(source_family.encode("utf-8")).hexdigest()[:8]
    generated: dict[str, str] = {}
    files: list[str] = []

    vf = variable_face(faces)
    prefer_variable_for_static = vf is not None
    variable_source = vf is not None
    variable_axes = list(vf.axes) if vf else []
    synthetic_oblique: list[str] = []
    synthetic_oblique_metadata_only: list[str] = []

    def static_font(
        key: str,
        family: str,
        subfamily: str,
        full: str,
        ps: str,
        weight: int,
        italic: bool,
        typo_family: str | None = None,
        typo_subfamily: str | None = None,
        zh_family: str | None = None,
        zh_full: str | None = None,
    ) -> TTFont:
        face = choose_face(faces, weight, italic, prefer_variable=prefer_variable_for_static)
        make_oblique = italic and not face.italic
        font = make_font(
            face,
            family,
            subfamily,
            full,
            ps,
            weight,
            italic,
            keep_variable=False,
            typographic_family=typo_family,
            typographic_subfamily=typo_subfamily,
            zh_family=zh_family,
            zh_full_name=zh_full,
            synthetic_oblique=make_oblique,
        )
        if make_oblique:
            if "glyf" in font:
                synthetic_oblique.append(key)
            else:
                synthetic_oblique_metadata_only.append(key)
        return font

    specs = [
        ("segoe_regular", "Segoe UI", "Regular", "Segoe UI", "SegoeUI", 400, False, None, None),
        ("segoe_italic", "Segoe UI", "Italic", "Segoe UI Italic", "SegoeUI-Italic", 400, True, None, None),
        ("segoe_bold", "Segoe UI", "Bold", "Segoe UI Bold", "SegoeUI-Bold", 700, False, None, None),
        ("segoe_bold_italic", "Segoe UI", "Bold Italic", "Segoe UI Bold Italic", "SegoeUI-BoldItalic", 700, True, None, None),
        ("segoe_semibold", "Segoe UI Semibold", "Regular", "Segoe UI Semibold", "SegoeUI-Semibold", 600, False, "Segoe UI", "Semibold"),
        ("segoe_semibold_italic", "Segoe UI Semibold", "Italic", "Segoe UI Semibold Italic", "SegoeUI-SemiboldItalic", 600, True, "Segoe UI", "Semibold Italic"),
        ("segoe_light", "Segoe UI Light", "Regular", "Segoe UI Light", "SegoeUI-Light", 300, False, "Segoe UI", "Light"),
        ("segoe_light_italic", "Segoe UI Light", "Italic", "Segoe UI Light Italic", "SegoeUI-LightItalic", 300, True, "Segoe UI", "Light Italic"),
        ("segoe_semilight", "Segoe UI Semilight", "Regular", "Segoe UI Semilight", "SegoeUI-Semilight", 350, False, "Segoe UI", "Semilight"),
        ("segoe_semilight_italic", "Segoe UI Semilight", "Italic", "Segoe UI Semilight Italic", "SegoeUI-SemilightItalic", 350, True, "Segoe UI", "Semilight Italic"),
        ("segoe_black", "Segoe UI Black", "Regular", "Segoe UI Black", "SegoeUI-Black", 900, False, "Segoe UI", "Black"),
        ("segoe_black_italic", "Segoe UI Black", "Italic", "Segoe UI Black Italic", "SegoeUI-BlackItalic", 900, True, "Segoe UI", "Black Italic"),
    ]

    for key, family, subfamily, full, ps, weight, italic, typo_family, typo_subfamily in specs:
        font = static_font(key, family, subfamily, full, ps, weight, italic, typo_family, typo_subfamily)
        filename = f"{prefix}-{key}{font_ext(font)}"
        generated[key] = save_font(font, out_dir, filename)
        files.append(filename)

    if vf:
        vf_font = make_font(
            vf,
            "Segoe UI Variable",
            "Regular",
            "Segoe UI Variable",
            "SegoeUIVariable",
            400,
            False,
            keep_variable=True,
            typographic_family="Segoe UI Variable",
            typographic_subfamily="Regular",
        )
    else:
        vf_font = static_font("segoe_variable", "Segoe UI Variable", "Regular", "Segoe UI Variable", "SegoeUIVariable", 400, False)

    vf_filename = f"{prefix}-segoe_variable{font_ext(vf_font)}"
    generated["segoe_variable"] = save_font(vf_font, out_dir, vf_filename)
    files.append(vf_filename)

    def yahei_font(
        key: str,
        family: str,
        subfamily: str,
        full: str,
        ps: str,
        weight: int,
        typo_family: str | None,
        typo_subfamily: str | None,
        zh_family: str | None,
        zh_full: str | None,
    ) -> TTFont:
        return static_font(key, family, subfamily, full, ps, weight, False, typo_family, typo_subfamily, zh_family, zh_full)

    collections = [
        (
            "msyh_regular",
            "Microsoft YaHei & Microsoft YaHei UI (TrueType)",
            f"{prefix}-msyh.ttc",
            [
                ("Microsoft YaHei", "Regular", "Microsoft YaHei", "MicrosoftYaHei", 400, None, None, "微软雅黑", "微软雅黑"),
                ("Microsoft YaHei UI", "Regular", "Microsoft YaHei UI", "MicrosoftYaHeiUI", 400, None, None, None, None),
            ],
        ),
        (
            "msyh_bold",
            "Microsoft YaHei Bold & Microsoft YaHei UI Bold (TrueType)",
            f"{prefix}-msyhbd.ttc",
            [
                ("Microsoft YaHei", "Bold", "Microsoft YaHei Bold", "MicrosoftYaHei-Bold", 700, None, None, "微软雅黑", "微软雅黑 Bold"),
                ("Microsoft YaHei UI", "Bold", "Microsoft YaHei UI Bold", "MicrosoftYaHeiUI-Bold", 700, None, None, None, None),
            ],
        ),
        (
            "msyh_light",
            "Microsoft YaHei Light & Microsoft YaHei UI Light (TrueType)",
            f"{prefix}-msyhl.ttc",
            [
                ("Microsoft YaHei Light", "Regular", "Microsoft YaHei Light", "MicrosoftYaHeiLight", 300, "Microsoft YaHei", "Light", "微软雅黑 Light", "微软雅黑 Light"),
                ("Microsoft YaHei UI Light", "Regular", "Microsoft YaHei UI Light", "MicrosoftYaHeiUILight", 300, "Microsoft YaHei UI", "Light", None, None),
            ],
        ),
    ]

    font_registry = {
        "Segoe UI (TrueType)": generated["segoe_regular"],
        "Segoe UI Italic (TrueType)": generated["segoe_italic"],
        "Segoe UI Bold (TrueType)": generated["segoe_bold"],
        "Segoe UI Bold Italic (TrueType)": generated["segoe_bold_italic"],
        "Segoe UI Semibold (TrueType)": generated["segoe_semibold"],
        "Segoe UI Semibold Italic (TrueType)": generated["segoe_semibold_italic"],
        "Segoe UI Light (TrueType)": generated["segoe_light"],
        "Segoe UI Light Italic (TrueType)": generated["segoe_light_italic"],
        "Segoe UI Semilight (TrueType)": generated["segoe_semilight"],
        "Segoe UI Semilight Italic (TrueType)": generated["segoe_semilight_italic"],
        "Segoe UI Black (TrueType)": generated["segoe_black"],
        "Segoe UI Black Italic (TrueType)": generated["segoe_black_italic"],
        "Segoe UI Variable (TrueType)": generated["segoe_variable"],
    }

    for key, registry_name, filename, face_specs in collections:
        collection = TTCollection()
        collection.fonts = [yahei_font(key, *spec) for spec in face_specs]
        collection.save(str(out_dir / filename))
        generated[key] = filename
        files.append(filename)
        font_registry[registry_name] = filename

    data = {
        "source_family": source_family,
        "files": sorted(files),
        "generated_files": generated,
        "font_registry": font_registry,
        "font_substitutes": [
            "Segoe UI",
            "Segoe UI Variable",
            "Segoe UI Variable Display",
            "Segoe UI Variable Text",
            "Segoe UI Light",
            "Segoe UI Semilight",
            "Segoe UI Semibold",
            "Segoe UI Bold",
            "Segoe UI Black",
            "Microsoft YaHei",
            "Microsoft YaHei UI",
            "Microsoft YaHei Light",
            "Microsoft YaHei UI Light",
            "Microsoft YaHei Bold",
            "Microsoft YaHei UI Bold",
            "微软雅黑",
            "微软雅黑 UI",
            "微软雅黑 Light",
            "微软雅黑 UI Light",
            "微软雅黑 Bold",
            "微软雅黑 UI Bold",
            "MS Shell Dlg",
            "MS Shell Dlg 2",
        ],
        "build_strategy": "static-system-entries",
        "synthetic_oblique": sorted(set(synthetic_oblique)),
        "synthetic_oblique_metadata_only": sorted(set(synthetic_oblique_metadata_only)),
        "variable_source": variable_source,
        "variable_axes": variable_axes,
    }
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Built {len(files)} generated fonts in {out_dir}")
    print("Segoe UI and Microsoft YaHei system entries use static generated fonts.")
    if variable_source:
        print(f"Segoe UI Variable uses a real variable source with axes: {', '.join(variable_axes)}")
    else:
        print("Warning: no variable source face was found; Segoe UI Variable uses a static fallback.")
    if synthetic_oblique:
        print(f"Synthetic oblique generated for: {', '.join(sorted(set(synthetic_oblique)))}")
    if synthetic_oblique_metadata_only:
        print(f"Warning: oblique metadata only for: {', '.join(sorted(set(synthetic_oblique_metadata_only)))}")


def list_fonts(variable_only: bool) -> None:
    grouped: dict[str, dict[str, object]] = {}
    for face in scan_faces():
        for family in face.families:
            entry = grouped.setdefault(family, {"files": set(), "variable": False, "axes": set()})
            entry["files"].add(str(face.path))
            if face.variable:
                entry["variable"] = True
                entry["axes"].update(face.axes)

    for family in sorted(grouped, key=str.casefold):
        entry = grouped[family]
        if variable_only and not entry["variable"]:
            continue
        vf = "VF" if entry["variable"] else "--"
        axes = ",".join(sorted(entry["axes"])) if entry["axes"] else ""
        print(f"{vf:2}  {family}  {axes}")


def verify() -> None:
    if winreg is None:
        raise SystemExit("This command only works on Windows.")
    key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, FONT_REGISTRY)
    names = [
        "Segoe UI (TrueType)",
        "Segoe UI Variable (TrueType)",
        "Microsoft YaHei & Microsoft YaHei UI (TrueType)",
    ]
    for name in names:
        try:
            value, _kind = winreg.QueryValueEx(key, name)
        except OSError:
            print(f"{name}: missing")
            continue
        print(f"{name}: {value}")
        path = Path(value)
        if not path.is_absolute():
            path = WINDOWS_FONT_DIR / value
        if path.exists():
            faces = inspect_file(path)
            for face in faces[:2]:
                marker = "VF" if face.variable else "static"
                axes = ",".join(face.axes)
                print(f"  {marker} family={face.families[:2]} axes={axes}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Windows system font surrogate files from installed fonts.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    list_parser = sub.add_parser("list", help="List installed font families.")
    list_parser.add_argument("--variable-only", action="store_true")

    build_parser = sub.add_parser("build", help="Build generated surrogate fonts.")
    build_parser.add_argument("--source-family", required=True)
    build_parser.add_argument("--out-dir", required=True, type=Path)
    build_parser.add_argument("--manifest", required=True, type=Path)

    sub.add_parser("verify", help="Inspect current Windows mappings.")

    args = parser.parse_args()
    if args.cmd == "list":
        list_fonts(args.variable_only)
    elif args.cmd == "build":
        build(args.source_family, args.out_dir, args.manifest)
    elif args.cmd == "verify":
        verify()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
