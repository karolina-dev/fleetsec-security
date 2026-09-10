import json
import sys
from pathlib import Path


DIRECT_DEPENDENCIES_FILE = Path(
    "security/scripts/direct-dependencies.txt"
)

TRIVY_REPORT = Path("trivy-sca.json")

DIRECT_THRESHOLD = 8.0
INDIRECT_THRESHOLD = 9.0


def load_direct_dependencies():
    with DIRECT_DEPENDENCIES_FILE.open(encoding="utf-8") as file:
        return {
            line.strip().lower()
            for line in file
            if line.strip()
        }


def load_trivy_report():
    with TRIVY_REPORT.open(encoding="utf-8") as file:
        return json.load(file)


def main():
    direct_dependencies = load_direct_dependencies()
    report = load_trivy_report()

    violations = []

    for result in report.get("Results", []):
        for package in result.get("Packages", []):
            package_name = package.get("Name", "").lower()

            dependency_type = (
                "direct"
                if package_name in direct_dependencies
                else "indirect"
            )

            threshold = (
                DIRECT_THRESHOLD
                if dependency_type == "direct"
                else INDIRECT_THRESHOLD
            )

            for vulnerability in package.get("Vulnerabilities", []):
                cvss = vulnerability.get("CVSS", {})

                scores = []

                for source in cvss.values():
                    score = source.get("V3Score")
                    if score is not None:
                        scores.append(float(score))

                if not scores:
                    continue

                score = max(scores)

                print(
                    f"{package.get('Name')} "
                    f"{package.get('Version')} | "
                    f"{dependency_type} | "
                    f"{vulnerability.get('VulnerabilityID')} | "
                    f"CVSS {score}"
                )

                if score >= threshold:
                    violations.append(
                        {
                            "package": package.get("Name"),
                            "version": package.get("Version"),
                            "type": dependency_type,
                            "vulnerability": vulnerability.get(
                                "VulnerabilityID"
                            ),
                            "cvss": score,
                            "threshold": threshold,
                        }
                    )

    if violations:
        print("\nSCA GATE: FAILED")

        for violation in violations:
            print(
                f"- {violation['package']} "
                f"{violation['vulnerability']} "
                f"CVSS {violation['cvss']} "
                f"({violation['type']}, "
                f"threshold {violation['threshold']})"
            )

        return 1

    print("\nSCA GATE: PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())