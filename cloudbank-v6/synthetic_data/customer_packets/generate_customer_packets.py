#!/usr/bin/env python3
"""Generate CloudBank customer packet PDFs and manifests.

The generated PDFs use simple PDF vector drawing commands so they look like
forms, statements, and pay records without requiring external dependencies.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PAGE_WIDTH = 612
PAGE_HEIGHT = 792

NAVY = (0.10, 0.18, 0.30)
BLUE = (0.16, 0.36, 0.58)
TEAL = (0.10, 0.42, 0.42)
GREEN = (0.22, 0.49, 0.32)
AMBER = (0.70, 0.44, 0.13)
RED = (0.66, 0.20, 0.20)
GRAY = (0.35, 0.38, 0.42)
LIGHT_GRAY = (0.94, 0.95, 0.96)
MID_GRAY = (0.78, 0.80, 0.82)
WHITE = (1.0, 1.0, 1.0)
BLACK = (0.0, 0.0, 0.0)


def pdf_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def color(value: tuple[float, float, float]) -> str:
    return f"{value[0]:.3f} {value[1]:.3f} {value[2]:.3f}"


def dollars(value: int | float) -> str:
    return f"${value:,.2f}"


def token_tail(value: str) -> str:
    return "".join(ch for ch in value if ch.isalnum())[-7:]


def text(
    commands: list[str],
    x: float,
    y: float,
    value: str,
    size: int = 9,
    fill: tuple[float, float, float] = BLACK,
    font: str = "F1",
) -> None:
    commands.append(f"{color(fill)} rg")
    commands.append(f"BT /{font} {size} Tf {x:.1f} {y:.1f} Td ({pdf_escape(value)}) Tj ET")


def rect(
    commands: list[str],
    x: float,
    y: float,
    w: float,
    h: float,
    fill: tuple[float, float, float] | None = None,
    stroke: tuple[float, float, float] | None = BLACK,
    width: float = 0.6,
) -> None:
    if fill and stroke:
        commands.append(f"{color(fill)} rg {color(stroke)} RG {width:.2f} w {x:.1f} {y:.1f} {w:.1f} {h:.1f} re B")
    elif fill:
        commands.append(f"{color(fill)} rg {x:.1f} {y:.1f} {w:.1f} {h:.1f} re f")
    elif stroke:
        commands.append(f"{color(stroke)} RG {width:.2f} w {x:.1f} {y:.1f} {w:.1f} {h:.1f} re S")


def line(
    commands: list[str],
    x1: float,
    y1: float,
    x2: float,
    y2: float,
    stroke: tuple[float, float, float] = MID_GRAY,
    width: float = 0.5,
) -> None:
    commands.append(f"{color(stroke)} RG {width:.2f} w {x1:.1f} {y1:.1f} m {x2:.1f} {y2:.1f} l S")


def checkbox(commands: list[str], x: float, y: float, label: str, checked: bool = False) -> None:
    rect(commands, x, y, 8, 8, fill=None, stroke=GRAY, width=0.7)
    if checked:
        line(commands, x + 1.5, y + 4, x + 3.5, y + 1.5, stroke=NAVY, width=1.1)
        line(commands, x + 3.5, y + 1.5, x + 7.0, y + 7.0, stroke=NAVY, width=1.1)
    text(commands, x + 13, y + 1, label, 8, GRAY)


def field_box(commands: list[str], x: float, y: float, w: float, h: float, label: str, value: str) -> None:
    rect(commands, x, y, w, h, fill=WHITE, stroke=MID_GRAY, width=0.5)
    text(commands, x + 6, y + h - 11, label.upper(), 6, GRAY)
    text(commands, x + 6, y + 8, value, 9, BLACK)


def section_title(commands: list[str], y: float, title: str, accent: tuple[float, float, float] = BLUE) -> None:
    rect(commands, 40, y, 532, 18, fill=accent, stroke=None)
    text(commands, 48, y + 5, title.upper(), 9, WHITE)


def header(
    commands: list[str],
    title: str,
    subtitle: str,
    right_label: str,
    accent: tuple[float, float, float] = NAVY,
) -> None:
    rect(commands, 32, 724, 548, 48, fill=accent, stroke=None)
    text(commands, 48, 752, title, 17, WHITE)
    text(commands, 49, 735, subtitle, 9, WHITE)
    rect(commands, 426, 738, 136, 20, fill=WHITE, stroke=None)
    text(commands, 436, 744, right_label, 8, accent)
    rect(commands, 32, 704, 548, 14, fill=LIGHT_GRAY, stroke=None)
    text(commands, 48, 708, "CloudBank document intake packet", 7, GRAY)


def barcode(commands: list[str], x: float, y: float, value: str, accent: tuple[float, float, float] = GRAY) -> None:
    seed = sum(ord(ch) for ch in value)
    cursor = x
    for i in range(26):
        width = 1.0 + ((seed + i * 7) % 3) * 0.7
        height = 16 + ((seed + i * 5) % 5)
        rect(commands, cursor, y, width, height, fill=accent, stroke=None)
        cursor += width + 1.6


def footer(commands: list[str], application_id: str, doc_code: str) -> None:
    line(commands, 40, 40, 572, 40, stroke=MID_GRAY, width=0.4)
    text(commands, 42, 25, f"CloudBank {doc_code} | {application_id} | data_classification=restricted_customer", 6, GRAY)
    barcode(commands, 470, 18, f"{application_id}-{doc_code}", MID_GRAY)


def employer_footer(commands: list[str], employer: str, ref: str) -> None:
    line(commands, 40, 40, 572, 40, stroke=MID_GRAY, width=0.4)
    text(commands, 42, 25, f"{employer} payroll record | ref {ref}", 6, GRAY)
    barcode(commands, 486, 18, f"{employer}-{ref}", MID_GRAY)


def status_badge(commands: list[str], x: float, y: float, label: str, fill: tuple[float, float, float]) -> None:
    rect(commands, x, y, 132, 22, fill=fill, stroke=None)
    text(commands, x + 9, y + 7, label, 9, WHITE)


def table(
    commands: list[str],
    x: float,
    y_top: float,
    col_widths: list[float],
    row_h: float,
    headers: list[str],
    rows: list[list[str]],
    header_fill: tuple[float, float, float] = NAVY,
    border: tuple[float, float, float] = MID_GRAY,
    font_size: int = 8,
) -> float:
    total_w = sum(col_widths)
    rect(commands, x, y_top - row_h, total_w, row_h, fill=header_fill, stroke=border, width=0.5)
    cursor_x = x
    for i, head in enumerate(headers):
        text(commands, cursor_x + 5, y_top - row_h + 5, head.upper(), 7, WHITE)
        if i:
            line(commands, cursor_x, y_top, cursor_x, y_top - row_h * (len(rows) + 1), stroke=border)
        cursor_x += col_widths[i]
    y = y_top - row_h
    for idx, row in enumerate(rows):
        y -= row_h
        fill = (0.98, 0.985, 0.99) if idx % 2 == 0 else WHITE
        rect(commands, x, y, total_w, row_h, fill=fill, stroke=border, width=0.4)
        cursor_x = x
        for i, value in enumerate(row):
            text(commands, cursor_x + 5, y + 5, value, font_size, BLACK)
            cursor_x += col_widths[i]
    return y


def simple_grid(
    commands: list[str],
    x: float,
    y_top: float,
    col_widths: list[float],
    row_h: float,
    rows: list[list[str]],
    border: tuple[float, float, float] = MID_GRAY,
    font_size: int = 8,
) -> float:
    total_w = sum(col_widths)
    y = y_top
    for row in rows:
        y -= row_h
        rect(commands, x, y, total_w, row_h, fill=WHITE, stroke=border, width=0.35)
        cursor_x = x
        for i, value in enumerate(row):
            text(commands, cursor_x + 5, y + 5, value, font_size, BLACK)
            if i:
                line(commands, cursor_x, y + row_h, cursor_x, y, stroke=border, width=0.35)
            cursor_x += col_widths[i]
    return y


def build_pdf(page_streams: list[str]) -> bytes:
    objects: list[bytes] = []
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    page_ids = [4 + i * 2 for i in range(len(page_streams))]
    kids = " ".join(f"{page_id} 0 R" for page_id in page_ids)
    objects.append(f"<< /Type /Pages /Kids [{kids}] /Count {len(page_streams)} >>".encode("ascii"))
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    for index, stream in enumerate(page_streams):
        content_id = 5 + index * 2
        stream_bytes = stream.encode("latin-1", errors="replace")
        page = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PAGE_WIDTH} {PAGE_HEIGHT}] "
            f"/Resources << /Font << /F1 3 0 R >> >> /Contents {content_id} 0 R >>"
        )
        content = (
            f"<< /Length {len(stream_bytes)} >>\nstream\n".encode("ascii")
            + stream_bytes
            + b"endstream"
        )
        objects.append(page.encode("ascii"))
        objects.append(content)

    output = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for number, body in enumerate(objects, start=1):
        offsets.append(len(output))
        output.extend(f"{number} 0 obj\n".encode("ascii"))
        output.extend(body)
        output.extend(b"\nendobj\n")

    xref_offset = len(output)
    output.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    output.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        output.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    output.extend(
        (
            f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref_offset}\n%%EOF\n"
        ).encode("ascii")
    )
    return bytes(output)


def write_pdf(path: Path, commands: list[str]) -> None:
    path.write_bytes(build_pdf(["\n".join(commands) + "\n"]))


SCENARIOS = [
    {
        "slug": "app_apr_001_elena_parker",
        "application_id": "APP-APR-001",
        "workflow_id": "WF-APP-APR-001",
        "scenario_id": "SCN-FAST-APPROVAL-001",
        "expected_outcome": "APPROVED",
        "applicant_id": "APL-CB-APR-001",
        "name": "Elena Parker",
        "address": "4107 Vellum Creek Pass, Orinwell, CX 49012",
        "phone": "555-0101",
        "email": "elena.parker@example.invalid",
        "age_band": "35-44",
        "employer": "Novereign Systems Cooperative",
        "employer_address": "88 Larkspur Foundry Loop, Dovewick, CX 49110",
        "job_title": "Operations Systems Analyst",
        "tenure": "42 months",
        "income_type": "Salaried employment",
        "stated_income": 7200,
        "verified_income": 7200,
        "existing_debt": 850,
        "proposed_payment": 514,
        "dti": "18.9%",
        "requested_amount": 16000,
        "term": "36 months",
        "purpose": "DEBT_CONSOLIDATION",
        "risk_band": "CB-A",
        "identity_outcome": "IDENTITY_VERIFIED",
        "jurisdiction_code": "CX",
        "jurisdiction_status": "ENABLED",
        "disclosure_status": "ACCEPTED",
        "data_classification": "restricted_customer",
        "employment_status": "ACTIVE",
        "tenure_band": "12_PLUS_MONTHS",
        "document_validation_status": "PASS",
        "income_consistency_result": "CONSISTENT_WITHIN_10_PERCENT",
        "extraction_confidence": "HIGH",
        "pay_frequency": "BIWEEKLY",
        "recent_delinquency_indicator": "NONE",
        "bankruptcy_indicator": "NONE",
        "fraud_signal": "NONE",
        "payment_calculation_status": "CALCULATED",
        "apr": "10.49%",
        "documents": [
            "loan_application.pdf",
            "applicant_disclosures_and_consent.pdf",
            "identity_verification_summary.pdf",
            "address_jurisdiction_verification.pdf",
            "income_evidence_validation.pdf",
            "pay_statement_novereign_systems.pdf",
            "deposit_summary_cloudbank.pdf",
            "liability_schedule.pdf",
            "payment_calculation_summary.pdf",
        ],
        "validation_issues": [],
        "policy_evidence": ["CBPL-100-S3-C01", "CBPL-120-S5-C01", "CBPL-130-S5-C01", "CBPL-140-S3-C01"],
    },
    {
        "slug": "app_mr_002_maya_chen",
        "application_id": "APP-MR-002",
        "workflow_id": "WF-APP-MR-002",
        "scenario_id": "SCN-MANUAL-REVIEW-002",
        "expected_outcome": "MANUAL_REVIEW",
        "applicant_id": "APL-CB-MR-002",
        "name": "Maya Chen",
        "address": "2208 Quartzleaf Way, Brindlewick, CX 49018",
        "phone": "555-0102",
        "email": "maya.chen@example.invalid",
        "age_band": "25-34",
        "employer": "Lumenfield Care Studio",
        "employer_address": "712 Mistvalley Arcade, Pelhamere, CX 49118",
        "job_title": "Care Coordination Lead",
        "tenure": "13 months",
        "income_type": "Salaried employment",
        "stated_income": 6400,
        "verified_income": 5135,
        "pay_statement_income": 6600,
        "existing_debt": 1850,
        "proposed_payment": 610,
        "dti": "47.9%",
        "requested_amount": 18000,
        "term": "48 months",
        "purpose": "DEBT_CONSOLIDATION",
        "risk_band": "CB-B",
        "identity_outcome": "IDENTITY_VERIFIED",
        "jurisdiction_code": "CX",
        "jurisdiction_status": "ENABLED",
        "disclosure_status": "ACCEPTED",
        "data_classification": "restricted_customer",
        "employment_status": "ACTIVE",
        "tenure_band": "12_PLUS_MONTHS",
        "document_validation_status": "REVIEW",
        "income_consistency_result": "INCONSISTENT_OVER_20_PERCENT",
        "extraction_confidence": "LOW",
        "pay_frequency": "BIWEEKLY",
        "recent_delinquency_indicator": "NONE",
        "bankruptcy_indicator": "NONE",
        "fraud_signal": "NONE",
        "payment_calculation_status": "CALCULATED",
        "apr": "15.99%",
        "documents": [
            "loan_application.pdf",
            "applicant_disclosures_and_consent.pdf",
            "identity_verification_summary.pdf",
            "address_jurisdiction_verification.pdf",
            "income_evidence_validation.pdf",
            "earnings_statement_lumenfield.pdf",
            "account_activity_summary.pdf",
            "liability_schedule.pdf",
            "payment_calculation_summary.pdf",
            "income_clarification_request.pdf",
        ],
        "validation_issues": [
            "pay_statement_and_deposit_difference_over_10_percent",
            "document_extraction_confidence_below_auto_threshold",
        ],
        "policy_evidence": ["CBPL-120-S4-C01", "CBPL-130-S3-C01", "CBPL-150-S2-C01", "CBPL-160-S3-C01"],
    },
    {
        "slug": "app_rej_003_daniel_rojas",
        "application_id": "APP-REJ-003",
        "workflow_id": "WF-APP-REJ-003",
        "scenario_id": "SCN-REJECTION-003",
        "expected_outcome": "REJECTED",
        "applicant_id": "APL-CB-REJ-003",
        "name": "Daniel Rojas",
        "address": "907 Emberwell Row, Caldrin, CX 49024",
        "phone": "555-0103",
        "email": "daniel.rojas@example.invalid",
        "age_band": "45-54",
        "employer": "Kestrel Hollow Trade Desk",
        "employer_address": "3408 Fablequartz Lane, Merrinport, CX 49124",
        "job_title": "Independent Materials Broker",
        "tenure": "Variable",
        "income_type": "Self-employment",
        "stated_income": 9200,
        "verified_income": 2100,
        "existing_debt": 3200,
        "proposed_payment": 1040,
        "dti": "201.9%",
        "requested_amount": 30000,
        "term": "48 months",
        "purpose": "OTHER_CONSUMER_PURPOSE",
        "risk_band": "CB-X",
        "identity_outcome": "IDENTITY_VERIFIED",
        "jurisdiction_code": "CX",
        "jurisdiction_status": "ENABLED",
        "disclosure_status": "ACCEPTED",
        "data_classification": "restricted_customer",
        "employment_status": "SELF_EMPLOYED",
        "tenure_band": "VARIABLE",
        "document_validation_status": "FAIL",
        "income_consistency_result": "INSUFFICIENT_STABLE_RECURRING_EVIDENCE",
        "extraction_confidence": "MEDIUM",
        "pay_frequency": "VARIABLE",
        "recent_delinquency_indicator": "NONE",
        "bankruptcy_indicator": "NONE",
        "fraud_signal": "NONE",
        "payment_calculation_status": "CALCULATED",
        "apr": "NO_OFFER",
        "documents": [
            "loan_application.pdf",
            "applicant_disclosures_and_consent.pdf",
            "identity_verification_summary.pdf",
            "address_jurisdiction_verification.pdf",
            "income_evidence_validation.pdf",
            "contractor_income_statement.pdf",
            "account_activity_summary.pdf",
            "liability_schedule.pdf",
            "payment_calculation_summary.pdf",
        ],
        "validation_issues": [
            "verified_income_below_required_capacity",
            "dti_exceeds_hard_reject_threshold",
            "unsupported_income_for_automatic_processing",
        ],
        "policy_evidence": ["CBPL-130-S4-C01", "CBPL-160-S4-C01"],
    },
    {
        "slug": "app_opfail_004_priya_natarajan",
        "application_id": "APP-OPFAIL-004",
        "workflow_id": "WF-APP-OPFAIL-004",
        "scenario_id": "SCN-OPERATIONAL-FAILURE-004",
        "expected_outcome": "FAILED_RETRYABLE_RECOVERED",
        "recovered_decision": "APPROVED",
        "applicant_id": "APL-CB-OPF-004",
        "name": "Priya Natarajan",
        "address": "3182 Silverfen Mews, Asterwick, CX 49031",
        "phone": "555-0104",
        "email": "priya.natarajan@example.invalid",
        "age_band": "35-44",
        "employer": "Sablecrest Logistics Bureau",
        "employer_address": "909 Verdant Alloy Terrace, New Harrowell, CX 49131",
        "job_title": "Routing Program Manager",
        "tenure": "64 months",
        "income_type": "Salaried employment",
        "stated_income": 7800,
        "verified_income": 7800,
        "existing_debt": 1200,
        "proposed_payment": 704,
        "dti": "24.4%",
        "requested_amount": 22000,
        "term": "48 months",
        "purpose": "HOME_IMPROVEMENT",
        "risk_band": "CB-A",
        "identity_outcome": "IDENTITY_VERIFIED",
        "jurisdiction_code": "CX",
        "jurisdiction_status": "ENABLED",
        "disclosure_status": "ACCEPTED",
        "data_classification": "restricted_customer",
        "employment_status": "ACTIVE",
        "tenure_band": "12_PLUS_MONTHS",
        "document_validation_status": "PASS_AFTER_RETRY",
        "income_consistency_result": "CONSISTENT_WITHIN_10_PERCENT",
        "extraction_confidence": "HIGH_AFTER_RETRY",
        "pay_frequency": "BIWEEKLY",
        "recent_delinquency_indicator": "NONE",
        "bankruptcy_indicator": "NONE",
        "fraud_signal": "NONE",
        "payment_calculation_status": "CALCULATED",
        "apr": "11.49%",
        "documents": [
            "loan_application.pdf",
            "applicant_disclosures_and_consent.pdf",
            "identity_verification_summary.pdf",
            "address_jurisdiction_verification.pdf",
            "income_evidence_validation.pdf",
            "pay_statement_sablecrest.pdf",
            "deposit_summary_cloudbank.pdf",
            "liability_schedule.pdf",
            "payment_calculation_summary.pdf",
            "document_receipt.pdf",
        ],
        "validation_issues": ["temporary_document_processing_timeout_recovered"],
        "policy_evidence": ["CBPL-150-S6-C01", "CBPL-170-S5-C01"],
    },
    {
        "slug": "app_risk_005_jordan_brooks",
        "application_id": "APP-RISK-005",
        "workflow_id": "WF-APP-RISK-005",
        "scenario_id": "SCN-RISK-SIGNAL-005",
        "expected_outcome": "MANUAL_REVIEW",
        "applicant_id": "APL-CB-RSK-005",
        "name": "Jordan Brooks",
        "address": "6609 North Lattice Row, Vireo Falls, CX 49042",
        "phone": "555-0105",
        "email": "jordan.brooks@example.invalid",
        "age_band": "25-34",
        "employer": "Copperline Ledger Works",
        "employer_address": "4510 Meadowglass Yard, Orinwell, CX 49142",
        "job_title": "Billing Operations Specialist",
        "tenure": "28 months",
        "income_type": "Salaried employment",
        "stated_income": 6200,
        "verified_income": 6200,
        "existing_debt": 1200,
        "proposed_payment": 396,
        "dti": "25.7%",
        "requested_amount": 12000,
        "term": "36 months",
        "purpose": "MAJOR_PURCHASE",
        "risk_band": "CB-B",
        "identity_outcome": "IDENTITY_NEEDS_REVIEW",
        "jurisdiction_code": "CX",
        "jurisdiction_status": "ENABLED_NEAR_BOUNDARY",
        "disclosure_status": "ACCEPTED",
        "data_classification": "restricted_customer",
        "employment_status": "ACTIVE",
        "tenure_band": "12_PLUS_MONTHS",
        "document_validation_status": "REVIEW",
        "income_consistency_result": "CONSISTENT_WITHIN_10_PERCENT",
        "extraction_confidence": "HIGH",
        "pay_frequency": "BIWEEKLY",
        "recent_delinquency_indicator": "NONE",
        "bankruptcy_indicator": "NONE",
        "fraud_signal": "UNRESOLVED_SHARED_ATTRIBUTE_SIGNAL",
        "payment_calculation_status": "CALCULATED",
        "apr": "16.49%",
        "documents": [
            "loan_application.pdf",
            "applicant_disclosures_and_consent.pdf",
            "identity_verification_summary.pdf",
            "address_jurisdiction_verification.pdf",
            "income_evidence_validation.pdf",
            "pay_statement_copperline.pdf",
            "deposit_summary_cloudbank.pdf",
            "liability_schedule.pdf",
            "payment_calculation_summary.pdf",
            "relationship_signal_summary.pdf",
        ],
        "validation_issues": ["shared_device_and_address_signal_requires_review"],
        "policy_evidence": ["CBPL-110-S4-C01", "CBPL-150-S3-C01", "CBPL-170-S4-C01"],
    },
]


def draw_form_application(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Personal Loan Application", s["application_id"], NAVY)
    status_badge(c, 432, 680, "SUBMITTED", BLUE)

    section_title(c, 672, "Applicant information")
    field_box(c, 40, 632, 170, 34, "Applicant name", s["name"])
    field_box(c, 220, 632, 120, 34, "Applicant ID", s["applicant_id"])
    field_box(c, 350, 632, 90, 34, "Phone", s["phone"])
    field_box(c, 450, 632, 122, 34, "Email", s["email"])
    field_box(c, 40, 588, 360, 34, "Residential address", s["address"])
    field_box(c, 410, 588, 162, 34, "Age band", s["age_band"])

    section_title(c, 560, "Loan request")
    field_box(c, 40, 520, 122, 34, "Requested amount", dollars(s["requested_amount"]))
    field_box(c, 172, 520, 112, 34, "Requested term", s["term"])
    field_box(c, 294, 520, 278, 34, "Purpose code", s["purpose"])
    purposes = ["DEBT_CONSOLIDATION", "HOME_IMPROVEMENT", "MAJOR_PURCHASE", "MEDICAL_EXPENSE", "OTHER_CONSUMER_PURPOSE"]
    x = 44
    y = 496
    for i, purpose in enumerate(purposes):
        checkbox(c, x, y, purpose, purpose == s["purpose"])
        y -= 15
        if i == 2:
            x = 312
            y = 496

    section_title(c, 438, "Employment and income")
    field_box(c, 40, 398, 214, 34, "Employer or payer", s["employer"])
    field_box(c, 264, 398, 168, 34, "Position or role", s["job_title"])
    field_box(c, 442, 398, 130, 34, "Current tenure", s["tenure"])
    field_box(c, 40, 354, 170, 34, "Income source", s["income_type"])
    field_box(c, 220, 354, 160, 34, "Stated monthly income", dollars(s["stated_income"]))
    field_box(c, 390, 354, 182, 34, "Existing obligations", dollars(s["existing_debt"]))

    section_title(c, 320, "Eligibility and classification")
    field_box(c, 40, 280, 126, 30, "Jurisdiction code", s["jurisdiction_code"])
    field_box(c, 176, 280, 178, 30, "Jurisdiction status", s["jurisdiction_status"])
    field_box(c, 364, 280, 208, 30, "Data classification", s["data_classification"])
    field_box(c, 40, 238, 160, 30, "Disclosure consent", s["disclosure_status"])
    field_box(c, 210, 238, 160, 30, "Application status", "SUBMITTED")
    field_box(c, 380, 238, 192, 30, "Policy version", "2026.0")

    section_title(c, 200, "Certification")
    rect(c, 40, 92, 532, 94, fill=WHITE, stroke=MID_GRAY)
    checkbox(c, 54, 166, "Required disclosures and verification consent accepted", True)
    checkbox(c, 54, 146, "Income, identity, address, and purpose may be verified", True)
    checkbox(c, 54, 126, "Information submitted for permitted consumer purpose", True)
    line(c, 54, 104, 260, 104, stroke=GRAY)
    line(c, 326, 104, 520, 104, stroke=GRAY)
    text(c, 54, 90, "Applicant signature", 7, GRAY)
    text(c, 326, 90, "Date", 7, GRAY)
    footer(c, s["application_id"], "LOAN-APP")
    return c


def draw_identity_summary(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Identity Verification Summary", s["application_id"], TEAL)
    fill = GREEN if s["identity_outcome"] == "IDENTITY_VERIFIED" else AMBER
    status_badge(c, 426, 672, s["identity_outcome"], fill)

    section_title(c, 672, "Verification result", TEAL)
    field_box(c, 40, 632, 170, 34, "Applicant", s["name"])
    field_box(c, 220, 632, 154, 34, "Applicant ID", s["applicant_id"])
    field_box(c, 384, 632, 188, 34, "Outcome", s["identity_outcome"])
    field_box(c, 40, 588, 170, 34, "Government ID token", f"GOVTOK-{s['application_id'].replace('APP-', '')}")
    field_box(c, 220, 588, 154, 34, "Address token", f"ADDR-{token_tail(s['applicant_id'])}")
    field_box(c, 384, 588, 188, 34, "Phone token", f"PHN-{s['phone'].replace('-', '')}")
    field_box(c, 40, 544, 170, 30, "Email token", f"EMAIL-{token_tail(s['email'])}")
    field_box(c, 220, 544, 154, 30, "Document metadata", "Complete")
    field_box(c, 384, 544, 188, 30, "Data classification", s["data_classification"])

    section_title(c, 512, "Evidence checklist", TEAL)
    checks = [
        ("Name token present", True),
        ("Date-of-birth band present", True),
        ("Address token present", True),
        ("Phone token present", True),
        ("Email token present", True),
        ("Document metadata complete", s["identity_outcome"] == "IDENTITY_VERIFIED"),
    ]
    x, y = 56, 486
    for idx, (label, checked) in enumerate(checks):
        checkbox(c, x, y, label, checked)
        y -= 22
        if idx == 2:
            x, y = 330, 486

    section_title(c, 390, "Processing notes", TEAL)
    rect(c, 40, 286, 532, 94, fill=WHITE, stroke=MID_GRAY)
    text(c, 54, 358, "Identifier values are tokenized before storage in operating systems.", 8, BLACK)
    text(c, 54, 340, "No raw government identifier is included in this packet.", 8, BLACK)
    text(c, 54, 322, "Status values are produced by deterministic identity verification controls.", 8, BLACK)
    text(c, 54, 304, "Any unresolved identity evidence routes to additional review before final action.", 8, BLACK)
    footer(c, s["application_id"], "IDV-SUMMARY")
    return c


def draw_disclosures_and_consent(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Applicant Disclosures and Consent", s["application_id"], NAVY)
    status_badge(c, 426, 672, "CONSENT RECORDED", GREEN)
    field_box(c, 40, 654, 190, 34, "Applicant", s["name"])
    field_box(c, 240, 654, 150, 34, "Applicant ID", s["applicant_id"])
    field_box(c, 400, 654, 172, 34, "Consent date", "2026-04-27")

    section_title(c, 618, "Required application disclosures", NAVY)
    rect(c, 40, 468, 532, 134, fill=WHITE, stroke=MID_GRAY)
    items = [
        "Credit application certification",
        "Electronic records and communications",
        "Income, employment, identity, and address verification",
        "Permitted consumer-purpose certification",
        "Privacy and data-classification acknowledgement",
    ]
    y = 574
    for item in items:
        checkbox(c, 58, y, item, True)
        y -= 22

    section_title(c, 430, "Consent summary", NAVY)
    field_box(c, 40, 390, 150, 30, "Disclosure status", s["disclosure_status"])
    field_box(c, 200, 390, 166, 30, "Data classification", s["data_classification"])
    field_box(c, 376, 390, 196, 30, "Evidence timestamp", "2026-04-27T09:12:00")
    rect(c, 40, 286, 532, 84, fill=LIGHT_GRAY, stroke=MID_GRAY)
    text(c, 54, 346, "The applicant authorized CloudBank to validate submitted information for this application.", 8, BLACK)
    text(c, 54, 328, "Consent is stored as a structured decision fact and does not determine credit outcome by itself.", 8, BLACK)
    text(c, 54, 310, "The submitted loan purpose is recorded exactly as provided on the application.", 8, BLACK)
    footer(c, s["application_id"], "DISCLOSURE-CONSENT")
    return c


def draw_address_jurisdiction_verification(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Address and Jurisdiction Verification", s["application_id"], BLUE)
    fill = AMBER if "BOUNDARY" in s["jurisdiction_status"] else GREEN
    status_badge(c, 426, 672, s["jurisdiction_status"], fill)
    field_box(c, 40, 654, 220, 34, "Applicant", s["name"])
    field_box(c, 270, 654, 302, 34, "Residential address", s["address"])

    section_title(c, 618, "Jurisdiction evidence", BLUE)
    field_box(c, 40, 578, 126, 30, "Jurisdiction code", s["jurisdiction_code"])
    field_box(c, 176, 578, 178, 30, "Jurisdiction status", s["jurisdiction_status"])
    field_box(c, 364, 578, 208, 30, "Address token", f"ADDR-{token_tail(s['applicant_id'])}")
    field_box(c, 40, 536, 160, 30, "Address evidence", "Residential")
    field_box(c, 210, 536, 160, 30, "Routing result", "Eligible" if s["jurisdiction_code"] == "CX" else "Review")
    field_box(c, 380, 536, 192, 30, "Evidence age", "Current")

    section_title(c, 498, "Verification map reference", BLUE)
    rect(c, 40, 314, 532, 166, fill=(0.96, 0.98, 1.0), stroke=MID_GRAY)
    for x in range(68, 548, 48):
        line(c, x, 328, x, 464, stroke=(0.84, 0.88, 0.92), width=0.4)
    for y in range(340, 456, 28):
        line(c, 54, y, 558, y, stroke=(0.84, 0.88, 0.92), width=0.4)
    rect(c, 132, 364, 118, 56, fill=(0.82, 0.92, 0.86), stroke=GREEN)
    rect(c, 366, 350, 132, 70, fill=(0.98, 0.92, 0.78), stroke=AMBER)
    text(c, 150, 390, "ENABLED CX AREA", 8, GREEN)
    text(c, 382, 388, "BOUNDARY REVIEW AREA", 8, AMBER)
    rect(c, 252 if "BOUNDARY" not in s["jurisdiction_status"] else 468, 394, 9, 9, fill=RED, stroke=WHITE)
    text(c, 54, 294, "Map reference is tokenized and intended for routing support only.", 8, GRAY)
    footer(c, s["application_id"], "ADDRESS-JURISDICTION")
    return c


def draw_income_evidence_validation(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Income Evidence Validation", s["application_id"], TEAL)
    fill = GREEN if s["document_validation_status"].startswith("PASS") else AMBER if s["document_validation_status"] == "REVIEW" else RED
    status_badge(c, 426, 672, s["document_validation_status"], fill)
    pay_income = s.get("pay_statement_income", s["verified_income"])
    if pay_income:
        diff_pct = abs(pay_income - s["verified_income"]) / pay_income * 100
    else:
        diff_pct = 0

    field_box(c, 40, 654, 190, 34, "Applicant", s["name"])
    field_box(c, 240, 654, 150, 34, "Income source type", s["income_type"])
    field_box(c, 400, 654, 172, 34, "Employment status", s["employment_status"])
    field_box(c, 40, 610, 150, 30, "Tenure band", s["tenure_band"])
    field_box(c, 200, 610, 166, 30, "Pay frequency", s["pay_frequency"])
    field_box(c, 376, 610, 196, 30, "Extraction confidence", s["extraction_confidence"])

    section_title(c, 572, "Income comparison", TEAL)
    rows = [
        ["Stated monthly income", dollars(s["stated_income"]), "Application"],
        ["Pay document monthly income", dollars(pay_income), "Employer evidence"],
        ["Verified monthly income", dollars(s["verified_income"]), "Account/evidence average"],
        ["Difference from pay document", f"{diff_pct:.1f}%", s["income_consistency_result"]],
    ]
    y = table(c, 40, 550, [210, 130, 190], 24, ["Fact", "Value", "Source or result"], rows, TEAL, font_size=7)

    section_title(c, y - 32, "Document validation", TEAL)
    validation_rows = [
        ["Document validation status", s["document_validation_status"]],
        ["Income consistency result", s["income_consistency_result"]],
        ["Evidence timestamp", "2026-04-27T09:18:00"],
        ["Data classification", s["data_classification"]],
    ]
    y = simple_grid(c, 40, y - 54, [220, 310], 22, validation_rows, font_size=8)
    rect(c, 40, y - 66, 532, 46, fill=LIGHT_GRAY, stroke=MID_GRAY)
    text(c, 54, y - 40, "The decision service must use verified income for capacity calculations.", 8, BLACK)
    footer(c, s["application_id"], "INCOME-VALIDATION")
    return c


def draw_payment_calculation_summary(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Payment Calculation Summary", s["application_id"], GRAY)
    fill = GREEN if s["payment_calculation_status"] == "CALCULATED" and s["apr"] != "NO_OFFER" else RED if s["apr"] == "NO_OFFER" else AMBER
    status_badge(c, 426, 672, s["payment_calculation_status"], fill)
    field_box(c, 40, 654, 190, 34, "Applicant", s["name"])
    field_box(c, 240, 654, 150, 34, "Risk band", s["risk_band"])
    field_box(c, 400, 654, 172, 34, "Policy version", "2026.0")

    section_title(c, 618, "Calculation inputs", GRAY)
    rows = [
        ["Requested amount", dollars(s["requested_amount"])],
        ["Evaluated amount", dollars(s["requested_amount"]) if s["apr"] != "NO_OFFER" else "No offer"],
        ["Requested term", s["term"]],
        ["APR", s["apr"]],
        ["Proposed monthly payment", dollars(s["proposed_payment"])],
        ["Calculation timestamp", "2026-04-27T09:21:00"],
    ]
    y = simple_grid(c, 40, 596, [230, 300], 24, rows, font_size=8)

    section_title(c, y - 32, "Capacity inputs", GRAY)
    rows = [
        ["Verified gross monthly income", dollars(s["verified_income"])],
        ["Existing monthly debt", dollars(s["existing_debt"])],
        ["Total with proposed payment", dollars(s["existing_debt"] + s["proposed_payment"])],
        ["Policy DTI", s["dti"]],
        ["Recent delinquency indicator", s["recent_delinquency_indicator"]],
        ["Bankruptcy indicator", s["bankruptcy_indicator"]],
    ]
    y = simple_grid(c, 40, y - 54, [230, 300], 22, rows, font_size=8)
    rect(c, 40, y - 66, 532, 46, fill=LIGHT_GRAY, stroke=MID_GRAY)
    text(c, 54, y - 40, "Payment and DTI values are deterministic decision facts, not generated by an AI assistant.", 8, BLACK)
    footer(c, s["application_id"], "PAYMENT-CALC")
    return c


def draw_pay_statement(s: dict, subtitle: str, style: str, accent: tuple[float, float, float]) -> list[str]:
    c: list[str] = []
    pay_income = s.get("pay_statement_income", s["verified_income"])
    period_gross = round(pay_income * 12 / 26, 2)
    withholding = round(period_gross * 0.19, 2)
    benefits = round(period_gross * 0.05, 2)
    net_pay = round(period_gross - withholding - benefits, 2)
    ytd_gross = round(pay_income * 4, 2)

    if style == "vertical":
        rect(c, 32, 724, 90, 48, fill=accent, stroke=None)
        text(c, 47, 752, "PAY", 18, WHITE)
        text(c, 46, 735, "ADVICE", 9, WHITE)
        text(c, 140, 754, s["employer"], 15, BLACK)
        text(c, 140, 737, subtitle, 9, GRAY)
        field_box(c, 420, 732, 150, 30, "Employee ref", f"EMP-{token_tail(s['applicant_id'])}")
        line(c, 32, 716, 580, 716, stroke=accent, width=2)
        field_box(c, 40, 668, 160, 30, "Employee", s["name"])
        field_box(c, 210, 668, 150, 30, "Period ending", "2026-04-24")
        field_box(c, 370, 668, 202, 30, "Role", s["job_title"])
        rect(c, 40, 608, 532, 38, fill=(0.96, 0.98, 0.96), stroke=GREEN)
        text(c, 54, 632, "NET PAY", 8, GREEN)
        text(c, 132, 623, dollars(net_pay), 18, GREEN)
        text(c, 320, 632, "MONTHLYIZED GROSS", 8, GRAY)
        text(c, 432, 623, dollars(pay_income), 18, BLACK)
    elif style == "split":
        rect(c, 32, 724, 548, 34, fill=WHITE, stroke=accent, width=1.2)
        rect(c, 32, 724, 170, 34, fill=accent, stroke=None)
        text(c, 46, 738, s["employer"], 11, WHITE)
        text(c, 218, 738, subtitle, 13, BLACK)
        text(c, 462, 738, f"EMP-{token_tail(s['applicant_id'])}", 8, accent)
        rect(c, 32, 644, 228, 60, fill=(0.99, 0.97, 0.93), stroke=MID_GRAY)
        rect(c, 276, 644, 304, 60, fill=(0.94, 0.96, 0.98), stroke=MID_GRAY)
        text(c, 46, 684, "EMPLOYEE", 7, GRAY)
        text(c, 46, 666, s["name"], 13, BLACK)
        text(c, 46, 652, s["job_title"], 8, GRAY)
        text(c, 294, 684, "PAY PERIOD", 7, GRAY)
        text(c, 294, 666, "2026-04-11 to 2026-04-24", 10, BLACK)
        text(c, 448, 684, "NET PAY", 7, GREEN)
        text(c, 448, 662, dollars(net_pay), 18, GREEN)
    elif style == "minimal":
        rect(c, 32, 724, 548, 48, fill=WHITE, stroke=BLACK, width=1)
        text(c, 48, 752, s["employer"], 15, BLACK)
        text(c, 49, 735, subtitle, 9, GRAY)
        text(c, 438, 752, "PAYROLL ADVICE", 9, BLACK)
        text(c, 438, 735, f"Ref EMP-{token_tail(s['applicant_id'])}", 8, GRAY)
        line(c, 32, 716, 580, 716, stroke=BLACK, width=0.8)
        field_box(c, 40, 668, 160, 30, "Employee", s["name"])
        field_box(c, 210, 668, 150, 30, "Pay date", "2026-04-24")
        field_box(c, 370, 668, 202, 30, "Payment method", "Direct deposit")
        rect(c, 414, 612, 158, 36, fill=WHITE, stroke=BLACK, width=0.9)
        text(c, 426, 634, "Net payment", 8, GRAY)
        text(c, 426, 619, dollars(net_pay), 15, BLACK)
    earnings_rows = [
        ["Regular earnings", "86.67", dollars(period_gross), dollars(ytd_gross)],
        ["Supplemental allowance", "0.00", "$0.00", "$0.00"],
        ["Gross earnings", "", dollars(period_gross), dollars(ytd_gross)],
    ]
    if style == "contract":
        earnings_rows = [
            ["Submitted invoices", "2", "$4,000.00", "$16,000.00"],
            ["Paid invoices", "1", dollars(s["verified_income"]), "$8,400.00"],
            ["Recurring contract evidence", "", "Unavailable", "Unavailable"],
        ]
    if style == "vertical":
        section_title(c, 570, "Pay detail", accent)
        y = simple_grid(c, 40, 548, [215, 90, 100, 105], 21, [["Regular earnings", "86.67", dollars(period_gross), dollars(ytd_gross)], ["Gross earnings", "", dollars(period_gross), dollars(ytd_gross)], ["Estimated withholding", "", f"-{dollars(withholding)}", f"-{dollars(round(withholding * 8, 2))}"], ["Benefit deductions", "", f"-{dollars(benefits)}", f"-{dollars(round(benefits * 8, 2))}"]], font_size=8)
        text(c, 45, 552, "Description", 7, GRAY)
        text(c, 260, 552, "Units", 7, GRAY)
        text(c, 350, 552, "Current", 7, GRAY)
        text(c, 450, 552, "YTD", 7, GRAY)
        section_title(c, y - 32, "Employer information", accent)
        field_box(c, 40, y - 80, 330, 34, "Employer address", s["employer_address"])
        field_box(c, 382, y - 80, 190, 34, "Monthlyized gross", dollars(pay_income))
        employer_footer(c, s["employer"], f"EMP-{token_tail(s['applicant_id'])}")
        return c

    if style == "split":
        section_title(c, 608, "Current period earnings", accent)
        left_y = table(c, 40, 586, [178, 86, 86], 21, ["Earning type", "Hours", "Amount"], [["Base salary", "86.67", dollars(period_gross)], ["Allowance", "0.00", "$0.00"], ["Gross pay", "", dollars(period_gross)]], accent, font_size=7)
        rect(c, 316, 608, 256, 18, fill=GRAY, stroke=None)
        text(c, 324, 613, "TAXES AND DEDUCTIONS", 9, WHITE)
        right_y = table(c, 316, 586, [150, 86], 21, ["Deduction", "Amount"], [["Estimated withholding", dollars(withholding)], ["Benefit deductions", dollars(benefits)], ["Total deductions", dollars(withholding + benefits)]], GRAY, font_size=7)
        y = min(left_y, right_y)
        rect(c, 40, y - 72, 532, 46, fill=(0.96, 0.97, 0.99), stroke=MID_GRAY)
        text(c, 54, y - 45, f"Employer address: {s['employer_address']}", 8, BLACK)
        text(c, 386, y - 45, f"Monthlyized gross: {dollars(pay_income)}", 8, BLACK)
        employer_footer(c, s["employer"], f"EMP-{token_tail(s['applicant_id'])}")
        return c

    if style == "minimal":
        rows = [
            ["EARNINGS", "", ""],
            ["Regular earnings", "Current", dollars(period_gross)],
            ["Gross pay", "Current", dollars(period_gross)],
            ["DEDUCTIONS", "", ""],
            ["Estimated withholding", "Current", dollars(withholding)],
            ["Benefit deductions", "Current", dollars(benefits)],
        ]
        y = simple_grid(c, 40, 590, [260, 110, 160], 24, rows, border=GRAY)
        rect(c, 40, y - 56, 532, 34, fill=LIGHT_GRAY, stroke=GRAY)
        text(c, 52, y - 35, f"Employer address: {s['employer_address']}", 8, BLACK)
        employer_footer(c, s["employer"], f"EMP-{token_tail(s['applicant_id'])}")
        return c

    rect(c, 32, 724, 548, 48, fill=WHITE, stroke=accent, width=1.1)
    rect(c, 32, 724, 144, 48, fill=accent, stroke=None)
    text(c, 48, 752, "PAYROLL", 15, WHITE)
    text(c, 48, 735, "STATEMENT", 9, WHITE)
    text(c, 194, 752, s["employer"], 15, BLACK)
    text(c, 194, 735, subtitle, 9, GRAY)
    field_box(c, 420, 732, 150, 30, "Employee ref", f"EMP-{token_tail(s['applicant_id'])}")
    line(c, 32, 716, 580, 716, stroke=accent, width=2)
    field_box(c, 40, 654, 180, 34, "Employee", s["name"])
    field_box(c, 230, 654, 180, 34, "Pay period ending", "2026-04-24")
    field_box(c, 420, 654, 152, 34, "Department", "Operations")
    field_box(c, 40, 610, 180, 34, "Position", s["job_title"])
    field_box(c, 230, 610, 180, 34, "Payment method", "Direct deposit")
    rect(c, 432, 608, 140, 36, fill=(0.90, 0.96, 0.94), stroke=GREEN)
    text(c, 444, 630, "NET PAY", 8, GREEN)
    text(c, 444, 614, dollars(net_pay), 15, GREEN)

    section_title(c, 570, "Earnings", accent)
    y = table(c, 40, 548, [190, 80, 120, 120], 22, ["Description", "Units", "Current", "YTD"], earnings_rows, accent)

    section_title(c, y - 32, "Deductions", accent)
    deduction_rows = [
        ["Estimated withholding", dollars(withholding), dollars(round(withholding * 8, 2))],
        ["Benefit deductions", dollars(benefits), dollars(round(benefits * 8, 2))],
        ["Total deductions", dollars(withholding + benefits), dollars(round((withholding + benefits) * 8, 2))],
    ]
    y = table(c, 40, y - 54, [250, 130, 130], 22, ["Description", "Current", "YTD"], deduction_rows, accent)

    section_title(c, y - 32, "Employer information", accent)
    field_box(c, 40, y - 80, 260, 34, "Employer address", s["employer_address"])
    field_box(c, 310, y - 80, 122, 34, "Employee ref", f"EMP-{token_tail(s['applicant_id'])}")
    field_box(c, 442, y - 80, 130, 34, "Monthlyized gross", dollars(pay_income))
    employer_footer(c, s["employer"], f"EMP-{token_tail(s['applicant_id'])}")
    return c


def draw_deposit_summary(s: dict, inconsistent: bool = False) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Account Activity Summary", s["application_id"], BLUE)
    monthly = s["verified_income"]
    if inconsistent:
        deposits = [1765.00, 1690.00, 1680.00]
    else:
        first = round(monthly / 3, 2)
        second = round(monthly / 3, 2)
        third = round(monthly - first - second, 2)
        deposits = [first, second, third]
    total_credits = round(sum(deposits), 2)
    total_debits = 2650.00 if s["existing_debt"] > 1500 else 1425.00
    opening = 2380.00
    ending = round(opening + total_credits - total_debits, 2)

    field_box(c, 40, 654, 180, 34, "Account holder", s["name"])
    field_box(c, 230, 654, 154, 34, "Account token", f"ACCT-{token_tail(s['applicant_id'])}")
    field_box(c, 394, 654, 178, 34, "Statement window", "2026-03-01 to 2026-04-30")

    section_title(c, 618, "Account summary", BLUE)
    summary = [
        ("Opening balance", dollars(opening)),
        ("Total credits", dollars(total_credits)),
        ("Total debits", dollars(total_debits)),
        ("Ending balance", dollars(ending)),
    ]
    x = 40
    for label, value in summary:
        rect(c, x, 560, 124, 46, fill=(0.95, 0.98, 1.0), stroke=MID_GRAY)
        text(c, x + 8, 588, label.upper(), 6, GRAY)
        text(c, x + 8, 570, value, 13, NAVY)
        x += 136

    section_title(c, 522, "Transaction activity", BLUE)
    rows = [
        ["2026-03-08", f"Payroll credit {s['employer'][:18]}", dollars(deposits[0]), "", dollars(opening + deposits[0])],
        ["2026-03-22", "Recurring household debit", "", "$712.00", dollars(opening + deposits[0] - 712)],
        ["2026-04-05", f"Payroll credit {s['employer'][:18]}", dollars(deposits[1]), "", dollars(opening + deposits[0] - 712 + deposits[1])],
        ["2026-04-18", "Installment obligation", "", "$463.00", dollars(opening + deposits[0] - 712 + deposits[1] - 463)],
        ["2026-04-22", f"Payroll credit {s['employer'][:18]}", dollars(deposits[2]), "", dollars(ending)],
    ]
    y = table(c, 40, 500, [72, 204, 86, 86, 72], 22, ["Date", "Description", "Credit", "Debit", "Balance"], rows, BLUE, font_size=7)
    rect(c, 40, y - 50, 532, 34, fill=LIGHT_GRAY, stroke=MID_GRAY)
    text(c, 52, y - 30, "Only tokenized account references are displayed in this report.", 8, GRAY)
    footer(c, s["application_id"], "ACCOUNT-ACTIVITY")
    return c


def draw_liability_schedule(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Liability Schedule", s["application_id"], GRAY)
    field_box(c, 40, 654, 190, 34, "Applicant", s["name"])
    field_box(c, 240, 654, 150, 34, "Verified income", dollars(s["verified_income"]))
    field_box(c, 400, 654, 172, 34, "Policy DTI", s["dti"])
    section_title(c, 618, "Monthly obligations", GRAY)
    rows = [
        ["Housing or lease obligation", dollars(round(s["existing_debt"] * 0.45)), "Applicant disclosed"],
        ["Installment obligations", dollars(round(s["existing_debt"] * 0.35)), "Applicant disclosed"],
        ["Revolving minimum obligations", dollars(round(s["existing_debt"] * 0.20)), "Applicant disclosed"],
        ["Proposed CloudBank payment", dollars(s["proposed_payment"]), "Calculated"],
    ]
    y = table(c, 40, 596, [250, 120, 160], 24, ["Category", "Monthly amount", "Source"], rows, GRAY)
    rect(c, 350, y - 60, 222, 42, fill=(0.96, 0.96, 0.96), stroke=MID_GRAY)
    text(c, 364, y - 34, f"Total obligations with proposed payment: {dollars(s['existing_debt'] + s['proposed_payment'])}", 9, BLACK)
    footer(c, s["application_id"], "LIABILITY-SCHEDULE")
    return c


def draw_clarification_request(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Income Clarification Request", s["application_id"], AMBER)
    status_badge(c, 430, 672, "ADDITIONAL REVIEW", AMBER)
    field_box(c, 40, 654, 190, 34, "Applicant", s["name"])
    field_box(c, 240, 654, 150, 34, "Applicant ID", s["applicant_id"])
    field_box(c, 400, 654, 172, 34, "Request date", "2026-04-27")
    section_title(c, 618, "Requested information", AMBER)
    rect(c, 40, 484, 532, 118, fill=WHITE, stroke=MID_GRAY)
    checkbox(c, 58, 574, "Current pay statement or employer verification", True)
    checkbox(c, 58, 548, "Updated account activity summary", True)
    checkbox(c, 58, 522, "Explanation for income timing difference", True)
    text(c, 58, 498, "The submitted pay statement and account activity summary do not align within automatic processing tolerance.", 8, BLACK)
    section_title(c, 440, "Reviewer notes", AMBER)
    rect(c, 40, 318, 532, 106, fill=LIGHT_GRAY, stroke=MID_GRAY)
    text(c, 54, 398, "A reviewer may request additional evidence before the workflow continues.", 8, BLACK)
    text(c, 54, 380, "The final reason code must come from deterministic workflow state and decision facts.", 8, BLACK)
    footer(c, s["application_id"], "INCOME-CLARIFICATION")
    return c


def draw_document_receipt(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Document Receipt", s["application_id"], TEAL)
    field_box(c, 40, 654, 190, 34, "Applicant", s["name"])
    field_box(c, 240, 654, 150, 34, "Received documents", "4")
    field_box(c, 400, 654, 172, 34, "Processing status", "Queued")
    section_title(c, 618, "Intake checklist", TEAL)
    rows = [
        ["Loan application", "Received", "2026-04-27 09:14"],
        ["Identity packet", "Received", "2026-04-27 09:15"],
        ["Pay statement", "Received", "2026-04-27 09:15"],
        ["Deposit summary", "Received", "2026-04-27 09:16"],
    ]
    y = table(c, 40, 596, [220, 120, 190], 24, ["Document", "Status", "Timestamp"], rows, TEAL)
    rect(c, 40, y - 72, 532, 54, fill=(0.93, 0.98, 0.98), stroke=MID_GRAY)
    text(c, 54, y - 42, "A workflow retry may be used when document processing does not complete within the expected interval.", 8, BLACK)
    footer(c, s["application_id"], "DOCUMENT-RECEIPT")
    return c


def draw_relationship_signal(s: dict) -> list[str]:
    c: list[str] = []
    header(c, "CloudBank", "Relationship Signal Summary", s["application_id"], AMBER)
    status_badge(c, 430, 672, "ADDITIONAL REVIEW", AMBER)
    field_box(c, 40, 654, 190, 34, "Applicant ID", s["applicant_id"])
    field_box(c, 240, 654, 150, 34, "Signal category", "Shared attributes")
    field_box(c, 400, 654, 172, 34, "Signal severity", "Low")
    section_title(c, 618, "Signal details", AMBER)
    rows = [
        ["Device token", "Shared with one recent application", "Review"],
        ["Address token", "Shared token near jurisdiction boundary", "Review"],
        ["Income evidence", "Complete", "No issue"],
        ["Identity evidence", "Additional verification needed", "Review"],
    ]
    y = table(c, 40, 596, [150, 260, 120], 24, ["Signal", "Observation", "Action"], rows, AMBER, font_size=7)
    rect(c, 40, y - 70, 532, 52, fill=LIGHT_GRAY, stroke=MID_GRAY)
    text(c, 54, y - 40, "This signal is not a denial reason and does not establish fraud.", 8, BLACK)
    text(c, 54, y - 56, "The workflow requires a reviewer to confirm whether the shared attributes are expected.", 8, BLACK)
    footer(c, s["application_id"], "RELATIONSHIP-SIGNAL")
    return c


def draw_contractor_income(s: dict) -> list[str]:
    c: list[str] = []
    rect(c, 32, 724, 548, 48, fill=WHITE, stroke=AMBER, width=1.1)
    rect(c, 32, 724, 170, 48, fill=AMBER, stroke=None)
    text(c, 48, 752, "CONTRACTOR", 14, WHITE)
    text(c, 48, 735, "STATEMENT", 9, WHITE)
    text(c, 220, 752, s["employer"], 15, BLACK)
    text(c, 220, 735, "Contractor Income Statement", 9, GRAY)
    field_box(c, 426, 732, 144, 30, "Reference", f"CNT-{token_tail(s['applicant_id'])}")
    line(c, 32, 716, 580, 716, stroke=AMBER, width=2)
    field_box(c, 40, 654, 190, 34, "Recipient", s["name"])
    field_box(c, 240, 654, 150, 34, "Statement window", "2026-01-01 to 2026-04-30")
    field_box(c, 400, 654, 172, 34, "Recurring evidence", "Unavailable")
    section_title(c, 618, "Receipts", AMBER)
    rows = [
        ["January", "$2,400.00", "Verified"],
        ["February", "$1,900.00", "Verified"],
        ["March", "$2,000.00", "Verified"],
        ["April", "$2,100.00", "Verified"],
        ["Monthly average", dollars(s["verified_income"]), "Calculated"],
    ]
    y = table(c, 40, 596, [170, 160, 200], 24, ["Period", "Amount", "Status"], rows, AMBER)
    rect(c, 40, y - 70, 532, 52, fill=(1.0, 0.97, 0.91), stroke=MID_GRAY)
    text(c, 54, y - 40, "Submitted evidence does not establish stable recurring self-employment income.", 8, BLACK)
    text(c, 54, y - 56, "Additional documentation may be required when capacity policy is not satisfied.", 8, BLACK)
    employer_footer(c, s["employer"], f"CNT-{token_tail(s['applicant_id'])}")
    return c


def expected_facts(s: dict) -> dict:
    return {
        "apr": s["apr"],
        "bankruptcyIndicator": s["bankruptcy_indicator"],
        "dataClassification": s["data_classification"],
        "disclosureStatus": s["disclosure_status"],
        "documentValidationStatus": s["document_validation_status"],
        "statedGrossMonthlyIncome": s["stated_income"],
        "verifiedGrossMonthlyIncome": s["verified_income"],
        "existingMonthlyDebt": s["existing_debt"],
        "proposedMonthlyPayment": s["proposed_payment"],
        "debtToIncome": s["dti"],
        "employmentStatus": s["employment_status"],
        "extractionConfidence": s["extraction_confidence"],
        "fraudSignal": s["fraud_signal"],
        "incomeConsistencyResult": s["income_consistency_result"],
        "jurisdictionCode": s["jurisdiction_code"],
        "jurisdictionStatus": s["jurisdiction_status"],
        "paymentCalculationStatus": s["payment_calculation_status"],
        "payFrequency": s["pay_frequency"],
        "requestedAmount": s["requested_amount"],
        "requestedTerm": s["term"],
        "purposeCode": s["purpose"],
        "recentDelinquencyIndicator": s["recent_delinquency_indicator"],
        "riskBand": s["risk_band"],
        "identityOutcome": s["identity_outcome"],
        "tenureBand": s["tenure_band"],
    }


def packet_manifest(s: dict) -> dict:
    return {
        "applicantId": s["applicant_id"],
        "applicationId": s["application_id"],
        "workflowId": s["workflow_id"],
        "scenarioId": s["scenario_id"],
        "expectedOutcome": s["expected_outcome"],
        "recoveredDecision": s.get("recovered_decision"),
        "applicantName": s["name"],
        "documents": s["documents"],
        "expectedExtractionFacts": expected_facts(s),
        "validationIssues": s["validation_issues"],
        "policyEvidenceHints": s["policy_evidence"],
        "policyAlignment": policy_alignment(s),
        "dataSafety": {
            "generatedNonProductionValues": True,
            "usesReservedContactPatterns": True,
            "containsRawGovernmentIdentifier": False,
            "containsRawAccountNumber": False,
        },
    }


def policy_alignment(s: dict) -> dict:
    return {
        "cbpl100Eligibility": {
            "ageBandPresent": True,
            "identityRecordPresent": True,
            "residentialAddressPresent": True,
            "jurisdictionEligible": s["jurisdiction_code"] == "CX",
            "incomeEvidencePresent": True,
            "permittedPurpose": s["purpose"] in {
                "DEBT_CONSOLIDATION",
                "HOME_IMPROVEMENT",
                "MAJOR_PURCHASE",
                "MEDICAL_EXPENSE",
                "HOUSEHOLD_EXPENSE",
                "MOVING_EXPENSE",
                "OTHER_CONSUMER_PURPOSE",
            },
            "disclosuresAccepted": s["disclosure_status"] == "ACCEPTED",
            "dataClassificationPresent": s["data_classification"] == "restricted_customer",
        },
        "cbpl120Income": {
            "verifiedIncomeMeetsMinimum": s["verified_income"] >= 2500,
            "incomeConsistencyResult": s["income_consistency_result"],
            "employmentStatus": s["employment_status"],
            "tenureBand": s["tenure_band"],
            "documentValidationStatus": s["document_validation_status"],
        },
        "cbpl130Capacity": {
            "dti": s["dti"],
            "hardRejectCapacityRule": s["expected_outcome"] == "REJECTED",
            "recentDelinquencyIndicator": s["recent_delinquency_indicator"],
            "bankruptcyIndicator": s["bankruptcy_indicator"],
        },
        "cbpl150Routing": {
            "expectedOutcome": s["expected_outcome"],
            "manualReviewSignals": [issue for issue in s["validation_issues"] if "review" in issue or "confidence" in issue],
            "operationalRecovery": s.get("recovered_decision") is not None,
        },
    }


def write_packet(s: dict) -> None:
    packet_dir = ROOT / s["slug"]
    packet_dir.mkdir(parents=True, exist_ok=True)
    for old_pdf in packet_dir.glob("*.pdf"):
        old_pdf.unlink()
    write_pdf(packet_dir / "loan_application.pdf", draw_form_application(s))
    write_pdf(packet_dir / "applicant_disclosures_and_consent.pdf", draw_disclosures_and_consent(s))
    write_pdf(packet_dir / "identity_verification_summary.pdf", draw_identity_summary(s))
    write_pdf(packet_dir / "address_jurisdiction_verification.pdf", draw_address_jurisdiction_verification(s))
    write_pdf(packet_dir / "income_evidence_validation.pdf", draw_income_evidence_validation(s))

    if s["application_id"] == "APP-APR-001":
        write_pdf(packet_dir / "pay_statement_novereign_systems.pdf", draw_pay_statement(s, "Employee Pay Statement", "salary", BLUE))
        write_pdf(packet_dir / "deposit_summary_cloudbank.pdf", draw_deposit_summary(s))
        write_pdf(packet_dir / "liability_schedule.pdf", draw_liability_schedule(s))
        write_pdf(packet_dir / "payment_calculation_summary.pdf", draw_payment_calculation_summary(s))
    elif s["application_id"] == "APP-MR-002":
        write_pdf(packet_dir / "earnings_statement_lumenfield.pdf", draw_pay_statement(s, "Earnings Statement", "vertical", TEAL))
        write_pdf(packet_dir / "account_activity_summary.pdf", draw_deposit_summary(s, inconsistent=True))
        write_pdf(packet_dir / "liability_schedule.pdf", draw_liability_schedule(s))
        write_pdf(packet_dir / "payment_calculation_summary.pdf", draw_payment_calculation_summary(s))
        write_pdf(packet_dir / "income_clarification_request.pdf", draw_clarification_request(s))
    elif s["application_id"] == "APP-REJ-003":
        write_pdf(packet_dir / "contractor_income_statement.pdf", draw_contractor_income(s))
        write_pdf(packet_dir / "account_activity_summary.pdf", draw_deposit_summary(s))
        write_pdf(packet_dir / "liability_schedule.pdf", draw_liability_schedule(s))
        write_pdf(packet_dir / "payment_calculation_summary.pdf", draw_payment_calculation_summary(s))
    elif s["application_id"] == "APP-OPFAIL-004":
        write_pdf(packet_dir / "pay_statement_sablecrest.pdf", draw_pay_statement(s, "Payroll Advice", "split", GREEN))
        write_pdf(packet_dir / "deposit_summary_cloudbank.pdf", draw_deposit_summary(s))
        write_pdf(packet_dir / "liability_schedule.pdf", draw_liability_schedule(s))
        write_pdf(packet_dir / "payment_calculation_summary.pdf", draw_payment_calculation_summary(s))
        write_pdf(packet_dir / "document_receipt.pdf", draw_document_receipt(s))
    elif s["application_id"] == "APP-RISK-005":
        write_pdf(packet_dir / "pay_statement_copperline.pdf", draw_pay_statement(s, "Employee Earnings Record", "minimal", AMBER))
        write_pdf(packet_dir / "deposit_summary_cloudbank.pdf", draw_deposit_summary(s))
        write_pdf(packet_dir / "liability_schedule.pdf", draw_liability_schedule(s))
        write_pdf(packet_dir / "payment_calculation_summary.pdf", draw_payment_calculation_summary(s))
        write_pdf(packet_dir / "relationship_signal_summary.pdf", draw_relationship_signal(s))

    (packet_dir / "packet_manifest.json").write_text(
        json.dumps(packet_manifest(s), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_readme() -> None:
    readme = """# CloudBank Customer Packet Corpus

This directory contains generated non-production customer document packets for the CloudBank personal loan workflow. The PDFs are intentionally realistic in structure and tone so document extraction, policy retrieval, workflow routing, and explanation services can be exercised with stable inputs.

The PDFs do not visibly mark themselves as generated artifacts. Runtime systems should rely on the manifests and repository context for safe handling, while treating the PDFs as ordinary customer-provided documents during extraction.

## Directory Layout

- `customer_packet_manifest.json`: corpus-level inventory and expected outcomes.
- `app_apr_001_elena_parker/`: fast approval packet.
- `app_mr_002_maya_chen/`: manual review packet for inconsistent income evidence.
- `app_rej_003_daniel_rojas/`: rejection packet for capacity and income support failure.
- `app_opfail_004_priya_natarajan/`: retryable operational failure packet with recovery.
- `app_risk_005_jordan_brooks/`: manual review packet for relationship-signal routing.

## Policy Coverage

Each packet includes customer-facing and CloudBank-generated intake evidence needed by the 2026.0 personal-loan policies:

- loan application with product purpose, requested amount, term, applicant, income, consent, jurisdiction, and data-classification facts;
- applicant disclosure and verification consent record;
- identity verification summary with tokenized identity, address, phone, email, and document metadata facts;
- address and jurisdiction verification;
- income evidence validation with employment status, tenure band, pay frequency, confidence, consistency, and verified-income facts;
- income source evidence, account activity, liability schedule, and payment calculation summary;
- scenario-specific review, recovery, or relationship-signal evidence where the expected outcome requires it.

Packet manifests include policy-alignment facts that explain why each scenario should resolve to `APPROVED`, `MANUAL_REVIEW`, `REJECTED`, or retryable recovery under the policy corpus.

## Data Safety

- Contact values use reserved patterns such as `555-01xx` phone numbers and `example.invalid` email addresses.
- Street names, localities, employers, identifiers, account tokens, and document references are invented.
- Documents avoid raw government identifiers, full account numbers, production credentials, and credit bureau artifacts.
- Do not ingest this README as customer-provided document content.
"""
    (ROOT / "README.md").write_text(readme, encoding="utf-8")


def write_corpus_manifest() -> None:
    manifest = {
        "corpusId": "CLOUDBANK-CUSTOMER-PACKETS-2026.0",
        "name": "CloudBank Customer Packet Corpus",
        "version": "2026.0",
        "generatedNonProductionValues": True,
        "pdfCustomerFacingMarkers": False,
        "scenarioCount": len(SCENARIOS),
        "scenarios": [
            {
                "slug": s["slug"],
                "applicantId": s["applicant_id"],
                "applicationId": s["application_id"],
                "workflowId": s["workflow_id"],
                "scenarioId": s["scenario_id"],
                "expectedOutcome": s["expected_outcome"],
                "recoveredDecision": s.get("recovered_decision"),
                "packetManifest": f"{s['slug']}/packet_manifest.json",
                "documents": [f"{s['slug']}/{doc}" for doc in s["documents"]],
            }
            for s in SCENARIOS
        ],
        "safetyRules": {
            "usesReservedPhoneNumbers": True,
            "usesReservedEmailDomain": "example.invalid",
            "containsRawGovernmentIdentifier": False,
            "containsRawAccountNumber": False,
            "containsCreditBureauArtifact": False,
        },
    }
    (ROOT / "customer_packet_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    for scenario in SCENARIOS:
        write_packet(scenario)
    write_readme()
    write_corpus_manifest()


if __name__ == "__main__":
    main()
