#!/usr/bin/env python3
"""Send a local file to the short-lived Notion upload URL from notion-create-file-upload.

    python3 notion_upload.py <upload_url> '<upload_headers as JSON>' <file> [--field file]

Prints Notion's JSON response. Its markdown_source goes in the page content.
"""

import argparse
import json
import mimetypes
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("headers", help="the upload_headers object, as JSON")
    parser.add_argument("file", type=Path)
    parser.add_argument("--field", default="file")
    args = parser.parse_args()

    boundary = uuid.uuid4().hex
    content_type = mimetypes.guess_type(args.file.name)[0] or "application/octet-stream"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{args.field}"; filename="{args.file.name}"\r\n'
        f"Content-Type: {content_type}\r\n\r\n"
    ).encode() + args.file.read_bytes() + f"\r\n--{boundary}--\r\n".encode()

    headers = json.loads(args.headers)
    headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    request = urllib.request.Request(args.url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            print(response.read().decode())
    except urllib.error.HTTPError as error:
        print(f"HTTP {error.code}: {error.read().decode()}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
