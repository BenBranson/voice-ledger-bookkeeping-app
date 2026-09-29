"""HTML -> PDF with WeasyPrint. Layout only; the HTML already contains every
number and every chart (as static SVG). Network access is refused: only
file:// paths inside the allowed roots and inline data: URIs load.

Usage: render_pdf.py <input.html> <output.pdf> <allowed-root> [<allowed-root> ...]
"""
import os
import sys

from urllib.parse import unquote

from weasyprint import HTML
from weasyprint.urls import URLFetcher


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: render_pdf.py <input.html> <output.pdf> <allowed-root>...", file=sys.stderr)
        return 64
    source, target, *roots = sys.argv[1:]
    roots = [os.path.realpath(r) for r in roots]

    class LocalOnlyFetcher(URLFetcher):
        def fetch(self, url, headers=None):
            if url.startswith("file://"):
                path = os.path.realpath(unquote(url[len("file://"):].split("?")[0]))
                if not any(path == r or path.startswith(r + os.sep) for r in roots):
                    raise ValueError("Blocked file outside the report folders")
            elif not url.startswith("data:"):
                raise ValueError("Blocked non-local resource")
            return super().fetch(url, headers)

    HTML(filename=source, url_fetcher=LocalOnlyFetcher(allowed_protocols=("file", "data"))).write_pdf(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
