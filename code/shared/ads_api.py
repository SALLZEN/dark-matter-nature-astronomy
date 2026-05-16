"""Reusable ADS API helpers for the analysis-version notebooks."""

from __future__ import annotations

import json
import os
import time
from html import unescape
from pathlib import Path
from typing import Iterable, Iterator
from urllib.parse import urlencode
from zipfile import ZIP_DEFLATED, ZipFile

import requests
from bs4 import BeautifulSoup


SEARCH_URL = "https://api.adsabs.harvard.edu/v1/search/query"
METRICS_URL = "https://api.adsabs.harvard.edu/v1/metrics/detail"

DEFAULT_SEARCH_FIELDS = [
    "bibcode",
    "abstract",
    "year",
    "doctype",
    "arxiv_class",
]

DEFAULT_METRICS_TYPES = ["citations"]


def clean_html(text: str | None) -> str | None:
    if text is None or not isinstance(text, str):
        return text
    return BeautifulSoup(unescape(text), "html.parser").get_text()


def load_json(path: str | Path, default=None):
    path = Path(path)
    if not path.exists():
        return [] if default is None else default
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def save_json(data, path: str | Path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
    return path


def build_zip_archive(paths: Iterable[str | Path], archive_path: str | Path) -> Path:
    archive_path = Path(archive_path)
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(archive_path, "w", compression=ZIP_DEFLATED, compresslevel=9) as zf:
        for path in paths:
            path = Path(path)
            if path.exists():
                zf.write(path, arcname=path.name)
    return archive_path


def set_ads_token(token: str, env_var: str = "ADS_TOKEN") -> str:
    """Store an ADS API token for the current Python session."""
    token = (token or "").strip()
    if not token:
        raise ValueError("Provide a non-empty ADS API token.")
    os.environ[env_var] = token
    return token


def latest_record_year(records: Iterable[dict]) -> int | None:
    """Return the latest integer year present in a record list, if any."""
    years: list[int] = []
    for record in records:
        value = record.get("year") if isinstance(record, dict) else None
        try:
            if value not in (None, ""):
                years.append(int(value))
        except (TypeError, ValueError):
            continue
    return max(years) if years else None


def summarize_record_years(records: Iterable[dict]) -> dict[str, int] | None:
    """Return basic year coverage info for a record list."""
    years: list[int] = []
    for record in records:
        value = record.get("year") if isinstance(record, dict) else None
        try:
            if value not in (None, ""):
                years.append(int(value))
        except (TypeError, ValueError):
            continue
    if not years:
        return None
    return {
        "year_min": min(years),
        "year_max": max(years),
        "n_years": len(set(years)),
    }


def chunked(items: Iterable[str], size: int) -> Iterator[list[str]]:
    batch: list[str] = []
    for item in items:
        batch.append(item)
        if len(batch) >= size:
            yield batch
            batch = []
    if batch:
        yield batch


def build_phrase_query(
    phrase: str = "dark matter",
    *,
    year: int | None = None,
    fields: Iterable[str] | None = None,
) -> str:
    fields = list(fields or DEFAULT_SEARCH_FIELDS)
    query = f'full:"{phrase}"'
    if year is not None:
        query = f"{query} AND year:{year}"
    return urlencode(
        {
            "q": query,
            "fl": ",".join(fields),
            "sort": "date asc",
        }
    )


def build_year_query(year: int, phrase: str = "dark matter", fields: Iterable[str] | None = None) -> str:
    return build_phrase_query(phrase=phrase, year=year, fields=fields)


def _auth_headers(token: str) -> dict[str, str]:
    if not token:
        raise ValueError("ADS API token is required.")
    return {"Authorization": f"Bearer {token}"}


def query_ads_api(
    encoded_query: str,
    token: str,
    *,
    rows: int = 2000,
    start: int = 0,
    timeout: int = 60,
    max_retries: int = 5,
) -> list[dict]:
    """Page through the ADS search API and return the accumulated docs."""
    records: list[dict] = []
    retries = 0

    while True:
        response = requests.get(
            f"{SEARCH_URL}?{encoded_query}&rows={rows}&start={start}",
            headers=_auth_headers(token),
            timeout=timeout,
        )

        if response.status_code == 429 and retries < max_retries:
            retry_after = int(response.headers.get("Retry-After", 5))
            time.sleep(retry_after)
            retries += 1
            continue

        response.raise_for_status()
        docs = response.json().get("response", {}).get("docs", [])
        if not docs:
            break

        records.extend(docs)
        start += rows
        retries = 0

    return records


def merge_unique_records(*record_sets: Iterable[dict], key: str = "bibcode") -> list[dict]:
    """Merge record sets, keeping the last non-empty value seen for each key."""
    merged: dict[str, dict] = {}
    for record_set in record_sets:
        for record in record_set:
            record_key = record.get(key)
            if not record_key:
                continue
            current = merged.setdefault(record_key, {})
            for field, value in record.items():
                if value not in (None, "", [], {}):
                    current[field] = value
    return list(merged.values())


def fetch_metrics_for_bibcodes(
    bibcodes: Iterable[str],
    token: str,
    *,
    metric_types: Iterable[str] | None = None,
    batch_size: int = 100,
    timeout: int = 60,
    sleep_seconds: float = 0.2,
) -> dict:
    """Fetch ADS metrics/detail payloads keyed by bibcode."""
    results: dict = {}
    headers = _auth_headers(token)

    payload_types = list(metric_types or DEFAULT_METRICS_TYPES)

    for batch in chunked([b for b in bibcodes if b], batch_size):
        payload = {"bibcodes": batch}
        if payload_types:
            payload["types"] = payload_types

        response = requests.post(
            METRICS_URL,
            headers=headers,
            json=payload,
            timeout=timeout,
        )
        response.raise_for_status()
        payload = response.json()
        results.update(payload)
        time.sleep(sleep_seconds)

    return results


def fetch_missing_abstracts(
    records: list[dict],
    token: str,
    *,
    batch_size: int = 200,
    timeout: int = 60,
    max_retries: int = 5,
) -> list[dict]:
    """Fill in missing abstracts by querying bibcode batches from ADS search."""
    missing = [r.get("bibcode") for r in records if r.get("bibcode") and not r.get("abstract")]
    if not missing:
        return records

    fetched: dict[str, str | None] = {}
    headers = _auth_headers(token)

    for batch in chunked(missing, batch_size):
        query = urlencode(
            {
                "q": " OR ".join(f'bibcode:"{bib}"' for bib in batch),
                "fl": "bibcode,abstract",
                "rows": len(batch),
            }
        )

        retries = 0
        while True:
            response = requests.get(f"{SEARCH_URL}?{query}", headers=headers, timeout=timeout)
            if response.status_code == 429 and retries < max_retries:
                retry_after = int(response.headers.get("Retry-After", 5))
                time.sleep(retry_after)
                retries += 1
                continue
            response.raise_for_status()
            docs = response.json().get("response", {}).get("docs", [])
            for doc in docs:
                fetched[doc["bibcode"]] = clean_html(doc.get("abstract"))
            break

    hydrated = []
    for record in records:
        updated = dict(record)
        bibcode = updated.get("bibcode")
        if bibcode in fetched and not updated.get("abstract"):
            updated["abstract"] = fetched[bibcode]
        hydrated.append(updated)
    return hydrated


def flatten_metrics_dict(metrics_all: dict) -> list[dict]:
    """Flatten ADS metrics/detail JSON into one row per bibcode."""
    rows: list[dict] = []
    for bibcode, metrics in metrics_all.items():
        if bibcode == "skipped bibcodes":
            continue
        row = {"bibcode": bibcode}
        if not isinstance(metrics, dict):
            rows.append(row)
            continue
        for key, value in metrics.items():
            if isinstance(value, dict):
                for year_key, year_value in value.items():
                    row[f"{key}__{year_key}"] = year_value
            else:
                row[key] = value
        rows.append(row)
    return rows
