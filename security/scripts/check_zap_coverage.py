import sys
from pathlib import Path
from urllib.parse import urlparse

import httpx
import yaml


OPENAPI_URL = "http://127.0.0.1:8000/openapi.json"
SITES_TREE_PATH = Path("security/zap/sites-tree.yaml")
MIN_COVERAGE = 80.0


def load_openapi():
    response = httpx.get(
        OPENAPI_URL,
        timeout=10.0,
    )
    response.raise_for_status()

    return response.json()


def load_sites_tree():
    with SITES_TREE_PATH.open(
        "r",
        encoding="utf-8",
    ) as file:
        return yaml.load(
            file,
            Loader=yaml.BaseLoader,
        )


def normalize_path(path):
    return path.rstrip("/") or "/"


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
                endpoints.add(
                    (
                        method.upper(),
                        normalize_path(path),
                    )
                )

    return endpoints


def walk_sites_tree(node, found):
    if not isinstance(node, dict):
        return

    url = node.get("url")
    method = node.get("method")

    if url and method:
        parsed = urlparse(str(url))

        found.add(
            (
                str(method).upper(),
                normalize_path(parsed.path),
            )
        )

    children = node.get("children", [])

    if isinstance(children, list):
        for child in children:
            walk_sites_tree(child, found)


def get_zap_endpoints(sites_tree):
    found = set()

    if isinstance(sites_tree, list):
        for node in sites_tree:
            walk_sites_tree(node, found)
    else:
        walk_sites_tree(sites_tree, found)

    return found


def path_matches_template(template, concrete):
    template_parts = [
        part for part in template.split("/")
        if part
    ]

    concrete_parts = [
        part for part in concrete.split("/")
        if part
    ]

    if len(template_parts) != len(concrete_parts):
        return False

    for template_part, concrete_part in zip(
        template_parts,
        concrete_parts,
    ):
        if (
            template_part.startswith("{")
            and template_part.endswith("}")
        ):
            continue

        if template_part != concrete_part:
            return False

    return True


def is_endpoint_covered(
    method,
    openapi_path,
    zap_routes,
):
    for zap_method, zap_path in zap_routes:
        if zap_method != method:
            continue

        if path_matches_template(
            openapi_path,
            zap_path,
        ):
            return True

    return False


def main():
    if not SITES_TREE_PATH.exists():
        print(
            f"ERROR: No existe {SITES_TREE_PATH}"
        )
        sys.exit(1)

    openapi = load_openapi()
    sites_tree = load_sites_tree()

    openapi_endpoints = get_openapi_endpoints(
        openapi
    )

    zap_endpoints = get_zap_endpoints(
        sites_tree
    )

    covered = set()

    for method, path in openapi_endpoints:
        if is_endpoint_covered(
            method,
            path,
            zap_endpoints,
        ):
            covered.add(
                (
                    method,
                    path,
                )
            )

    total = len(openapi_endpoints)
    covered_count = len(covered)

    coverage = (
        covered_count / total * 100
        if total
        else 0
    )

    print(
        f"OpenAPI endpoints: {total}"
    )
    print(
        f"Covered endpoints: {covered_count}"
    )
    print(
        f"Coverage: {coverage:.2f}%"
    )
    print(
        f"Minimum required: "
        f"{MIN_COVERAGE:.2f}%"
    )

    print("\nCovered:")

    for method, path in sorted(covered):
        print(
            f"  {method:6} {path}"
        )

    missing = (
        openapi_endpoints - covered
    )

    if missing:
        print("\nMissing:")

        for method, path in sorted(
            missing
        ):
            print(
                f"  {method:6} {path}"
            )

    if coverage < MIN_COVERAGE:
        print(
            "\nFAIL: cobertura OpenAPI "
            "inferior al 80%"
        )
        sys.exit(1)

    print(
        "\nPASS: cobertura OpenAPI "
        "cumple el mínimo requerido"
    )


if __name__ == "__main__":
    main()