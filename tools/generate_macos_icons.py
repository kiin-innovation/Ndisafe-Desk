"""Render macOS build resources from the checked-in NDISafe vector logo.

Developer-only dependencies: Pillow and CairoSVG. Generated resources are committed.
"""

from io import BytesIO
from pathlib import Path
import xml.etree.ElementTree as ET

import cairosvg
from PIL import Image, ImageDraw


def main():
    root = Path(__file__).resolve().parents[1]
    source = root / "res/ndisafe_logo.svg"
    rendered = cairosvg.svg2png(url=str(source), output_width=1024, output_height=1024)
    logo = Image.open(BytesIO(rendered)).convert("RGBA")
    icon = Image.new("RGBA", (1024, 1024))
    ImageDraw.Draw(icon).rounded_rectangle((100, 100, 924, 924), radius=180, fill="white")
    icon.alpha_composite(logo)
    icon.save(root / "res/mac-icon.png")
    icon.save(root / "flutter/macos/Runner/AppIcon.icns", format="ICNS")

    # Menu-bar icons are templates: transparent padding and a single opaque color.
    tree = ET.parse(source)
    for node in tree.iter():
        if node.tag.endswith("style"):
            node.text = ".b,.c,.d{fill:#000000;}"
    tree.getroot().set("viewBox", "130 130 540 540")
    template = Image.open(BytesIO(cairosvg.svg2png(
        bytestring=ET.tostring(tree.getroot()), output_width=44, output_height=44
    ))).convert("RGBA")
    template.save(root / "res/mac-tray-dark-x2.png")
    light = Image.new("RGBA", template.size, "white")
    light.putalpha(template.getchannel("A"))
    light.save(root / "res/mac-tray-light-x2.png")


if __name__ == "__main__":
    main()
