import json
import sys
from pathlib import Path


REPORT_PATH = Path("security/zap/zap-report.json")
HIGH_CRITICAL_PATH = Path("security/zap/high-critical-found.txt")
MEDIUM_PATH = Path("security/zap/medium-summary.md")


def load_report():
    if not REPORT_PATH.exists():
        print(f"ERROR: No existe {REPORT_PATH}")
        sys.exit(1)

    with REPORT_PATH.open("r", encoding="utf-8") as file:
        return json.load(file)


def collect_alerts(report):
    alerts = []

    for site in report.get("site", []):
        site_name = site.get("@name", "unknown")

        for alert in site.get("alerts", []):
            risk_code = int(alert.get("riskcode", 0))
            alert_name = alert.get(
                "alert",
                alert.get("name", "Unknown alert"),
            )

            for instance in alert.get("instances", []):
                alerts.append(
                    {
                        "site": site_name,
                        "name": alert_name,
                        "risk_code": risk_code,
                        "risk_desc": alert.get(
                            "riskdesc",
                            "",
                        ),
                        "method": instance.get(
                            "method",
                            "",
                        ),
                        "uri": instance.get(
                            "uri",
                            "",
                        ),
                    }
                )

    return alerts


def main():
    report = load_report()
    alerts = collect_alerts(report)

    high_critical = [
        alert
        for alert in alerts
        if alert["risk_code"] >= 3
    ]

    medium = [
        alert
        for alert in alerts
        if alert["risk_code"] == 2
    ]

    HIGH_CRITICAL_PATH.write_text(
        "\n".join(
            f'{a["risk_desc"]} | {a["name"]} | '
            f'{a["method"]} {a["uri"]}'
            for a in high_critical
        ),
        encoding="utf-8",
    )

    medium_lines = [
        "# ZAP - Alertas MEDIUM",
        "",
    ]

    for alert in medium:
        medium_lines.extend(
            [
                f'## {alert["name"]}',
                f'- Riesgo: {alert["risk_desc"]}',
                f'- Sitio: {alert["site"]}',
                f'- Método: {alert["method"]}',
                f'- URI: {alert["uri"]}',
                "",
            ]
        )

    MEDIUM_PATH.write_text(
        "\n".join(medium_lines),
        encoding="utf-8",
    )

    print(f"Total alertas: {len(alerts)}")
    print(f"HIGH/CRITICAL: {len(high_critical)}")
    print(f"MEDIUM: {len(medium)}")

    if high_critical:
        print("\nHIGH/CRITICAL encontrados:")
        for alert in high_critical:
            print(
                f'- {alert["risk_desc"]}: '
                f'{alert["name"]} '
                f'{alert["method"]} '
                f'{alert["uri"]}'
            )
    else:
        print("\nPASS: no hay alertas HIGH/CRITICAL")

    if medium:
        print(
            "\nMEDIUM detectadas: "
            "se generará GitHub Issue."
        )
    else:
        print("\nNo hay alertas MEDIUM.")

    # Este script no falla todavía.
    # El workflow hará el gate después de
    # crear el Issue MEDIUM.
    sys.exit(0)


if __name__ == "__main__":
    main()