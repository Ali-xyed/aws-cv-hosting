
import os
import json
import time
import base64
import boto3

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET"]
PREFIX = os.environ.get("PREFIX", "site/").strip("/") + "/"


def response(status, body, content_type="text/plain; charset=utf-8",
             is_base64=False):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": content_type,
            "Cache-Control": "no-cache"
        },
        "body": body,
        "isBase64Encoded": is_base64
    }


def lambda_handler(event, context):
    start = time.perf_counter()
    path = event.get("rawPath") or event.get("path") or "/"
    status = 500

    try:
        routes = {
            "/": ("index.html", "text/html; charset=utf-8"),
            "/index.html": ("index.html", "text/html; charset=utf-8"),
            "/style.css": ("style.css", "text/css; charset=utf-8"),
            "/cv.pdf": ("cv.pdf", "application/pdf")
        }

        if path not in routes:
            result = response(404, "404 Not Found")
            status = 404
        else:
            filename, content_type = routes[path]
            key = PREFIX + filename

            obj = s3.get_object(Bucket=BUCKET, Key=key)
            data = obj["Body"].read()

            if filename == "index.html":
                marker = b"{{HOSTED_ON}}"
                replacement = (
                    f"Lambda - {context.function_name}".encode("utf-8")
                )
                data = data.replace(marker, replacement)

            if filename == "cv.pdf":
                body = base64.b64encode(data).decode("ascii")
                result = response(
                    200, body, content_type, is_base64=True
                )
            else:
                result = response(
                    200, data.decode("utf-8"), content_type
                )

            status = 200

    except Exception as exc:
        # Avoid returning internal AWS details to public visitors.
        print(json.dumps({
            "error": str(exc),
            "path": path
        }))
        result = response(500, "Internal Server Error")
        status = 500

    finally:
        print(json.dumps({
            "fn": context.function_name,
            "path": path,
            "status": status,
            "ms": round((time.perf_counter() - start) * 1000, 2)
        }))

    return result
