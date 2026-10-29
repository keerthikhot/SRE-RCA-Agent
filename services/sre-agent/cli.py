#!/usr/bin/env python3
"""CLI utility for running the AI SRE Agent directly from your terminal or cron jobs."""
import sys
import argparse
import json
import agent
import report
import mailer
import tools

def main():
    parser = argparse.ArgumentParser(description="AI SRE Agent - Root Cause Analysis (RCA)")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # Command: scan
    scan_p = subparsers.add_parser("scan", help="Scan cluster for failing/restarting pods")

    # Command: rca
    rca_p = subparsers.add_parser("rca", help="Diagnose cluster and generate RCA report")
    rca_p.add_argument("--question", "-q", default="Investigate failing pods in the cluster and create an RCA", help="Investigation goal")
    rca_p.add_argument("--email", "-e", nargs="+", help="Email recipient(s) to send the RCA report to")

    # Command: test-email
    email_p = subparsers.add_parser("test-email", help="Send a test email with HTML attachment")
    email_p.add_argument("--to", required=True, nargs="+", help="Recipient email address(es)")

    args = parser.parse_args()

    if args.command == "scan":
        print("==> Scanning allowlisted namespaces for issues...")
        issues = tools.scan_cluster_for_issues()
        if issues:
            print(f"[!] Found {len(issues)} unhealthy pod(s):")
            print(json.dumps(issues, indent=2))
        else:
            print("[✓] All pods are healthy and running.")

    elif args.command == "rca":
        print(f"==> Investigating: {args.question}")
        rca_data = agent.investigate_and_rca(args.question)
        filename, html_page = report.render_rca(rca_data)
        print(f"\n[✓] Generated RCA Report: {filename}")
        print(f"    Severity: {rca_data.get('severity')}")
        print(f"    Title:    {rca_data.get('title')}")
        print(f"    Root Cause: {rca_data.get('root_cause')}")

        if args.email:
            print(f"==> Sending email notification to {args.email} with HTML attachment...")
            res = mailer.send_rca_email(
                args.email,
                f"[{rca_data.get('severity')}] {rca_data.get('title')}",
                report.email_body(rca_data),
                html_page,
                filename
            )
            print(f"[✓] Email result: {res}")

    elif args.command == "test-email":
        print(f"==> Sending test verification email to {args.to}...")
        test_rca = {
            "title": "Email Delivery Verification",
            "severity": "SEV4",
            "confidence": "high",
            "affected_services": ["order-service", "product-service"],
            "stakeholder_summary": "Verification test confirming email transmission and HTML report attachment.",
            "root_cause": "Manual test trigger.",
            "resolution": ["Check your inbox and verify the attachment."],
            "prevention": ["Ready for production alerts."]
        }
        filename, html_page = report.render_rca(test_rca)
        res = mailer.send_rca_email(
            args.to,
            "[TEST] SRE Agent Verification Email",
            report.email_body(test_rca),
            html_page,
            filename
        )
        print(f"[✓] Result: {res}")

    else:
        parser.print_help()

if __name__ == "__main__":
    main()

