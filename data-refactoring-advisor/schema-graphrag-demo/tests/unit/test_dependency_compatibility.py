# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

from pathlib import Path

import networkx as nx
import pytest
from streamlit.testing.v1 import AppTest

from src.nl2sql.sql_validator import extract_table_references, is_valid_sql


@pytest.mark.parametrize(
    ("sql", "valid"),
    [
        ("SELECT NVL(s.name, 'Unknown') FROM students s FETCH FIRST 5 ROWS ONLY", True),
        ("SELECT * FROM", False),
        ("", False),
    ],
)
def test_oracle_sql_validation(sql, valid):
    result, error = is_valid_sql(sql)
    assert result is valid
    assert bool(error) is not valid


def test_table_references_resolve_aliases_and_duplicates():
    sql = """
        SELECT s.id FROM students s
        JOIN enrollments e ON e.student_id = s.id
        JOIN students mentor ON mentor.id = s.mentor_id
    """
    assert extract_table_references(sql) == ["ENROLLMENTS", "STUDENTS"]


def test_louvain_separates_disconnected_table_groups(monkeypatch):
    monkeypatch.setenv("ADB_PASSWORD", "unit-test")
    from src.graph.community_detector import detect_communities

    graph = nx.Graph()
    graph.add_weighted_edges_from(
        [("STUDENTS", "ENROLLMENTS", 1.0), ("ACCOUNTS", "PAYMENTS", 1.0)]
    )
    partition = detect_communities(graph)
    assert set(partition) == set(graph)
    assert partition["STUDENTS"] == partition["ENROLLMENTS"]
    assert partition["ACCOUNTS"] == partition["PAYMENTS"]
    assert partition["STUDENTS"] != partition["ACCOUNTS"]


def test_settings_load_dotenv_and_environment_override(tmp_path, monkeypatch):
    monkeypatch.setenv("ADB_PASSWORD", "unit-test")
    from src.config import Settings

    env_file = tmp_path / ".env"
    env_file.write_text("ADB_PASSWORD=from-file\nTOP_K_RETRIEVAL=12\n")
    monkeypatch.delenv("TOP_K_RETRIEVAL", raising=False)
    settings = Settings(_env_file=env_file)
    assert settings.adb_password == "unit-test"
    assert settings.top_k_retrieval == 12


def test_streamlit_landing_page_renders():
    entrypoint = Path(__file__).resolve().parents[2] / "app" / "streamlit_app.py"
    app = AppTest.from_file(str(entrypoint)).run(timeout=15)
    assert not app.exception
    assert app.title[0].value == "SchemaRAG Demo"
    assert app.sidebar.success[0].value == "Select a page above."
