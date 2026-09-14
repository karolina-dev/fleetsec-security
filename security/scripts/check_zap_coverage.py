import json
import sys
from pathlib import Path
from urllib.request import urlopen

import yaml


OPENAPI_URL = "http://127.0.0.1:8000/openapi.json"
SITES_TREE_PATH = Path("security/zap/sites-tree.yaml")
MIN_COVERAGE = 80.0
ZAP_BASE_URL = "http://host.docker.internal:8000"


def load_openapi():
    with urlopen(OPENAPI_URL) as response:
        return json.load(response)


def load_sites_tree():
    with SITES_TREE_PATH.open("r", encoding="utf-8") as file:
        return yaml.safe_load(file)


def get_openapi_endpoints(spec):
    endpoints = set()

    for path, methods in spec.get("paths", {}).items():
        for method in methods:
            if method.lower() in {
                "get",
                "post",
                "put",
                "patch",
                "delete",
                "head",
                "options",
            }:
                normalized_path = path.rstrip("/") or "/"
                endpoints.add((method.upper(), normalized_path))

    return endpoints


def walk_sites_tree(node, found):
    if not isinstance(node, dict):
        return

    url = node.get("url")
    method = node.get("method")

    if url and method:
        found.add(
            (
                method.upper(),
                url.rstrip("/") or "/",
            )
        )

    for child in node.get("children", []):
        walk_sites_tree(child, found)


def get_zap_endpoints(sites_tree):
    found = set()

    for node in sites_tree:
        walk_sites_tree(node, found)

    return found


def main():
    if not SITES_TREE_PATH.exists():
        print(f"ERROR: No existe {SITES_TREE_PATH}")
        sys.exit(1)

    openapi = load_openapi()
    sites_tree = load_sites_tree()

    openapi_endpoints = get_openapi_endpoints(openapi)
    zap_endpoints = get_zap_endpoints(sites_tree)

    zap_routes = {
        (
            method,
            url.replace(ZAP_BASE_URL, "").rstrip("/") or "/",
        )
        for method, url in zap_endpoints
    }

    covered = set()

    for method, path in openapi_endpoints:
        if (method, path) in zap_routes:
            covered.add((method, path))

    total = len(openapi_endpoints)
    covered_count = len(covered)

    coverage = (covered_count / total * 100) if total else 0

    print(f"OpenAPI endpoints: {total}")
    print(f"Covered endpoints: {covered_count}")
    print(f"Coverage: {coverage:.2f}%")
    print(f"Minimum required: {MIN_COVERAGE:.2f}%")

    print("\nCovered:")
    for method, path in sorted(covered):
        print(f"  {method:6} {path}")

    missing = openapi_endpoints - covered

    if missing:
        print("\nMissing:")
        for method, path in sorted(missing):
            print(f"  {method:6} {path}")

    if coverage < MIN_COVERAGE:
        print("\nFAIL: cobertura OpenAPI inferior al 80%")
        sys.exit(1)

    print("\nPASS: cobertura OpenAPI cumple el mínimo requerido")


if __name__ == "__main__":
    main()