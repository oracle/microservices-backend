#!/usr/bin/env python3
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

"""Author the checked-in demo PDFs. Requires reportlab; never run during intake."""

import json
from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parent
APPLICATION = json.loads((ROOT / "application.json").read_text())
EMPLOYER = "Novereign Systems Cooperative"


def document(path, title, fields, company=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(path), pagesize=letter, invariant=1)
    pdf.setTitle(title)
    pdf.setAuthor("CloudBank synthetic demo corpus")
    pdf.setFillColor(HexColor("#143b4a"))
    pdf.setFont("Helvetica-Bold", 17)
    pdf.drawString(54, 744, company or title)
    if company:
        pdf.setFont("Helvetica-Bold", 14)
        pdf.drawString(54, 718, title)
    pdf.setStrokeColor(HexColor("#cbdcde"))
    pdf.line(54, 700, 558, 700)
    y = 680
    for label, value in fields:
        pdf.setFillColor(HexColor("#55707a"))
        pdf.setFont("Helvetica-Bold", 8)
        pdf.drawString(54, y, label)
        pdf.setFillColor(HexColor("#20343d"))
        pdf.setFont("Helvetica", 11)
        pdf.drawString(54, y - 15, str(value))
        y -= 39
    pdf.setFillColor(HexColor("#55707a"))
    pdf.setFont("Helvetica", 8)
    pdf.drawString(54, 38, "Synthetic non-production demo data | CloudBank AI")
    pdf.save()


def loan_fields(employer):
    applicant, loan = APPLICATION["applicant"], APPLICATION["loan"]
    address = applicant["address"]
    return [
        ("APPLICANT NAME", applicant["displayName"]),
        ("AGE BAND", applicant["ageBand"]),
        ("RESIDENTIAL ADDRESS", f'{address["addressLine"]}, {address["locality"]} {address["postalCode"]}, {address["countryCode"]}'),
        ("PHONE", "555-0199"),
        ("EMAIL", "smoke.applicant@example.invalid"),
        ("REQUESTED AMOUNT", f'${loan["requestedAmount"]:,.2f}'),
        ("REQUESTED TERM", f'{loan["requestedTermMonths"]} months'),
        ("PURPOSE CODE", loan["purposeCode"]),
        ("EMPLOYER OR PAYER", employer),
        ("POSITION OR ROLE", "Operations Systems Analyst"),
        ("CURRENT TENURE", "42 months"),
        ("INCOME SOURCE", "Salaried employment"),
        ("STATED MONTHLY INCOME", "$7,200.00"),
        ("EXISTING OBLIGATIONS", "$850.00"),
    ]


if __name__ == "__main__":
    document(ROOT / "loan_application.pdf", "Personal Loan Application", loan_fields(EMPLOYER))
    document(ROOT / "pay_statement_novereign_systems.pdf", "Pay Statement", [
        ("EMPLOYEE", APPLICATION["applicant"]["displayName"]),
        ("POSITION", "Operations Systems Analyst"),
        ("PAY PERIOD", "2026-01-01 through 2026-01-31"),
        ("PAY FREQUENCY", "MONTHLY"),
        ("MONTHLYIZED GROSS", "$7,200.00"),
        ("NET PAY", "$5,400.00"),
    ], company=EMPLOYER)
    document(ROOT / "manual-review" / "loan_application.pdf", "Personal Loan Application",
             loan_fields("Lumenfield Analytics"))
