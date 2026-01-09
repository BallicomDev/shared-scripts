#!/usr/bin/env python3
"""Fetch GitHub issue data with attachments"""

import argparse
import json
import logging
import os
import re
import sys
import time
import urllib.request
import urllib.error
from functools import wraps
from pathlib import Path
from typing import Dict, Any, Optional, List, Callable
from html.parser import HTMLParser


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


# Retry configuration
MAX_RETRIES = 5
INITIAL_RETRY_DELAY = 1  # seconds
RETRY_BACKOFF_MULTIPLIER = 2


def retry_on_transient_errors(func: Callable) -> Callable:
    """
    Decorator to retry function on transient HTTP errors with exponential backoff.

    Retries on:
    - HTTP 502 Bad Gateway
    - HTTP 503 Service Unavailable
    - HTTP 504 Gateway Timeout
    - Network/connection errors (URLError)

    Uses exponential backoff: 1s, 2s, 4s, 8s, 16s
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        last_exception = None
        retry_delay = INITIAL_RETRY_DELAY

        for attempt in range(1, MAX_RETRIES + 1):
            try:
                return func(*args, **kwargs)

            except urllib.error.HTTPError as e:
                # Only retry on transient server errors
                if e.code in (502, 503, 504):
                    last_exception = e
                    if attempt < MAX_RETRIES:
                        logger.warning(
                            f"Transient error ({e.code} {e.reason}) on attempt {attempt}/{MAX_RETRIES}. "
                            f"Retrying in {retry_delay}s..."
                        )
                        time.sleep(retry_delay)
                        retry_delay *= RETRY_BACKOFF_MULTIPLIER
                        continue
                    else:
                        logger.error(
                            f"Max retries ({MAX_RETRIES}) reached for transient error {e.code}. "
                            f"Giving up."
                        )
                else:
                    # For non-transient HTTP errors (401, 403, 404, etc.), don't retry
                    raise

            except urllib.error.URLError as e:
                # Retry on network/connection errors (timeouts, connection refused, etc.)
                last_exception = e
                if attempt < MAX_RETRIES:
                    logger.warning(
                        f"Network error ({e.reason}) on attempt {attempt}/{MAX_RETRIES}. "
                        f"Retrying in {retry_delay}s..."
                    )
                    time.sleep(retry_delay)
                    retry_delay *= RETRY_BACKOFF_MULTIPLIER
                    continue
                else:
                    logger.error(
                        f"Max retries ({MAX_RETRIES}) reached for network error. "
                        f"Giving up."
                    )

            except Exception:
                # For other exceptions, don't retry
                raise

        # If we exhausted all retries, raise the last exception
        raise last_exception

    return wrapper


class AttachmentExtractor(HTMLParser):
    """Extract attachment URLs from HTML content"""

    def __init__(self):
        super().__init__()
        self.attachments: List[Dict[str, Any]] = []
        self._current_img_attrs: Optional[Dict[str, str]] = None

    def handle_starttag(self, tag, attrs):
        """Process HTML start tags to extract attachments"""
        attrs_dict = dict(attrs)

        if tag == 'img':
            # Extract image URLs from <img src="...">
            src = attrs_dict.get('src', '')
            if self._is_attachment_url(src):
                attachment = {
                    'url': src,
                    'filename': self._extract_filename(src),
                    'file_type': self._extract_file_type(src),
                    'dimensions': self._extract_dimensions(attrs_dict),
                    'tag_type': 'img'
                }
                self.attachments.append(attachment)

        elif tag == 'a':
            # Extract file URLs from <a href="...">
            href = attrs_dict.get('href', '')
            if self._is_attachment_url(href):
                attachment = {
                    'url': href,
                    'filename': self._extract_filename(href),
                    'file_type': self._extract_file_type(href),
                    'dimensions': None,  # Links don't have dimensions
                    'tag_type': 'a'
                }
                self.attachments.append(attachment)

    def _is_attachment_url(self, url: str) -> bool:
        """Check if URL is a GitHub attachment URL"""
        if not url:
            return False

        # Check for GitHub attachment domains
        attachment_domains = [
            'user-attachments.githubusercontent.com',
            'private-user-images.githubusercontent.com',
            'github-production-user-asset',  # Newer GitHub asset URLs
        ]

        return any(domain in url for domain in attachment_domains)

    def _extract_filename(self, url: str) -> str:
        """Extract filename from URL path"""
        # Match UUID-style filename with extension before JWT parameters
        match = re.search(r'/([a-f0-9-]+\.[\w]+)(?:\?|$)', url)
        if match:
            return match.group(1)

        # Fallback: extract anything after last slash before query params
        match = re.search(r'/([^/?]+)(?:\?|$)', url)
        if match:
            return match.group(1)

        return 'unknown_file'

    def _extract_file_type(self, url: str) -> str:
        """Detect file type from URL extension"""
        # Extract extension from filename
        filename = self._extract_filename(url)
        match = re.search(r'\.(\w+)$', filename)
        if match:
            ext = match.group(1).lower()
            return ext

        return 'unknown'

    def _extract_dimensions(self, attrs: Dict[str, str]) -> Optional[Dict[str, int]]:
        """Extract image dimensions from img tag attributes"""
        width = attrs.get('width')
        height = attrs.get('height')

        if width or height:
            dimensions = {}
            if width:
                try:
                    dimensions['width'] = int(width)
                except ValueError:
                    pass
            if height:
                try:
                    dimensions['height'] = int(height)
                except ValueError:
                    pass
            return dimensions if dimensions else None

        return None


def extract_attachments_from_html(html_content: str) -> List[Dict[str, Any]]:
    """Extract attachment URLs from HTML content"""
    if not html_content:
        return []

    parser = AttachmentExtractor()
    try:
        parser.feed(html_content)
    except Exception as e:
        logger.warning(f"Failed to parse HTML content: {e}")
        return []

    return parser.attachments


class IssueDataFetcher:
    """Fetches GitHub issue data including attachments"""

    def __init__(self, repo: str, issue_number: int, output_dir: str, github_token: str):
        """Initialize the issue data fetcher"""
        self.repo = repo
        self.issue_number = issue_number
        self.output_dir = Path(output_dir)
        self.github_token = github_token.strip()  # Strip whitespace from token

        # Parse repository owner and name
        parts = repo.split('/')
        if len(parts) != 2:
            raise ValueError(f"Invalid repository format: {repo}. Expected OWNER/REPO")
        self.owner = parts[0]
        self.repo_name = parts[1]

        # Define output directory structure
        self.attachments_dir = self.output_dir / "attachments"
        self.issue_attachments_dir = self.attachments_dir / "issue"
        self.comments_attachments_dir = self.attachments_dir / "comments"

    def validate_inputs(self) -> None:
        """Validate input arguments"""
        logger.info("Validating inputs...")

        # Validate repository format
        if not self.owner or not self.repo_name:
            raise ValueError(f"Invalid repository format: {self.repo}")

        # Validate issue number
        if self.issue_number <= 0:
            raise ValueError(f"Issue number must be positive: {self.issue_number}")

        # Validate GitHub token
        if not self.github_token or len(self.github_token.strip()) < 10:
            raise ValueError("GitHub token is required and must be valid")

        logger.info(f"✓ Repository: {self.repo}")
        logger.info(f"✓ Issue number: {self.issue_number}")
        logger.info(f"✓ Output directory: {self.output_dir}")

    def create_output_directories(self) -> None:
        """Create output directory structure"""
        logger.info("Creating output directory structure...")

        try:
            # Create main output directory
            self.output_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"✓ Created: {self.output_dir}")

            # Create attachments directory
            self.attachments_dir.mkdir(exist_ok=True)
            logger.info(f"✓ Created: {self.attachments_dir}")

            # Create issue attachments directory
            self.issue_attachments_dir.mkdir(exist_ok=True)
            logger.info(f"✓ Created: {self.issue_attachments_dir}")

            # Create comments attachments directory
            self.comments_attachments_dir.mkdir(exist_ok=True)
            logger.info(f"✓ Created: {self.comments_attachments_dir}")

        except OSError as e:
            logger.error(f"Failed to create directory structure: {e}")
            raise

    @retry_on_transient_errors
    def fetch_issue_html(self, repo: str, issue_number: int, github_token: str) -> Dict[str, Any]:
        """Fetch issue data from GitHub API with body_html format"""
        url = f"https://api.github.com/repos/{repo}/issues/{issue_number}"

        try:
            # Create request with authentication and full+json accept header
            req = urllib.request.Request(url)
            req.add_header("Accept", "application/vnd.github.full+json")
            req.add_header("Authorization", f"token {github_token}")
            req.add_header("User-Agent", "github-issue-fetcher")

            logger.info(f"Fetching issue from: {url}")

            # Make API call
            with urllib.request.urlopen(req, timeout=30) as response:
                issue_data = json.loads(response.read().decode('utf-8'))
                logger.info(f"✓ Successfully fetched issue #{issue_number}")
                return issue_data

        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8') if e.fp else "No error details"

            if e.code == 401:
                raise RuntimeError(
                    f"Authentication failed (401): Invalid GitHub token. "
                    f"Please check your token has valid credentials."
                ) from e
            elif e.code == 403:
                raise RuntimeError(
                    f"Forbidden (403): Access denied. Your token may lack required permissions "
                    f"or you may have hit rate limits. Details: {error_body}"
                ) from e
            elif e.code == 404:
                raise RuntimeError(
                    f"Not found (404): Issue #{issue_number} does not exist in {repo}, "
                    f"or you don't have access to this repository."
                ) from e
            else:
                raise RuntimeError(
                    f"HTTP error {e.code}: {e.reason}. Details: {error_body}"
                ) from e

        except urllib.error.URLError as e:
            raise RuntimeError(
                f"Network error: Failed to connect to GitHub API. "
                f"Please check your internet connection. Details: {e.reason}"
            ) from e

        except json.JSONDecodeError as e:
            raise RuntimeError(
                f"Invalid JSON response from GitHub API: {e}"
            ) from e

        except Exception as e:
            raise RuntimeError(
                f"Unexpected error fetching issue data: {e}"
            ) from e

    @retry_on_transient_errors
    def _fetch_comments_page(self, api_url: str, github_token: str) -> tuple:
        """Fetch a single page of comments from GitHub API (with retry logic)"""
        # Create request with authentication and full+json accept header
        request = urllib.request.Request(api_url)
        request.add_header('Authorization', f'token {github_token}')
        request.add_header('Accept', 'application/vnd.github.full+json')
        request.add_header('User-Agent', 'github-issue-fetcher')

        # Make API request
        with urllib.request.urlopen(request, timeout=30) as response:
            # Parse JSON response
            comments_data = json.loads(response.read().decode('utf-8'))

            # Check for Link header for pagination
            link_header = response.headers.get('Link', '')
            has_next_page = 'rel="next"' in link_header

            return comments_data, has_next_page

    def fetch_comments_html(self, repo: str, issue_number: int, github_token: str) -> List[Dict[str, Any]]:
        """Fetch all comments for an issue with HTML body included"""
        logger.info(f"Fetching comments for issue #{issue_number}...")

        all_comments = []
        page = 1
        per_page = 100  # GitHub's max per_page value

        while True:
            # Build API URL with pagination
            api_url = f"https://api.github.com/repos/{repo}/issues/{issue_number}/comments"
            api_url += f"?per_page={per_page}&page={page}"

            logger.info(f"Fetching comments page {page}...")

            try:
                # Fetch page (with automatic retry on transient errors)
                comments_data, has_next_page = self._fetch_comments_page(api_url, github_token)

                # If empty, we've reached the end
                if not comments_data:
                    logger.info(f"No more comments (page {page} was empty)")
                    break

                # Extract comment data
                for comment in comments_data:
                    body_html = comment.get('body_html', '')

                    # Extract attachments from comment body_html
                    attachments = extract_attachments_from_html(body_html)

                    comment_info = {
                        'comment_id': comment['id'],
                        'author': comment['user']['login'] if comment.get('user') else 'ghost',
                        'created_at': comment['created_at'],
                        'body': comment.get('body', ''),
                        'body_html': body_html,
                        '_attachments': attachments
                    }
                    all_comments.append(comment_info)

                logger.info(f"✓ Fetched {len(comments_data)} comments from page {page}")

                # Check if there are more pages
                if not has_next_page:
                    logger.info(f"✓ All comments fetched (no more pages)")
                    break

                # Move to next page
                page += 1

            except urllib.error.HTTPError as e:
                error_body = e.read().decode('utf-8') if e.fp else 'No error body'
                logger.error(f"GitHub API error: {e.code} {e.reason}")
                logger.error(f"Error body: {error_body}")
                raise RuntimeError(f"Failed to fetch comments: HTTP {e.code} - {e.reason}") from e
            except urllib.error.URLError as e:
                logger.error(f"Network error: {e.reason}")
                raise RuntimeError(f"Failed to fetch comments: {e.reason}") from e
            except json.JSONDecodeError as e:
                logger.error(f"Failed to parse API response: {e}")
                raise RuntimeError(f"Invalid JSON response from GitHub API") from e

        logger.info(f"✓ Total comments fetched: {len(all_comments)}")
        return all_comments

    def fetch_issue_data(self) -> Dict[str, Any]:
        """Fetch issue data from GitHub API"""
        logger.info("Fetching issue data from GitHub API...")

        try:
            # Fetch issue with body_html format
            issue_data = self.fetch_issue_html(self.repo, self.issue_number, self.github_token)

            # Extract and log key metadata
            logger.info(f"  Title: {issue_data.get('title', 'N/A')}")
            logger.info(f"  State: {issue_data.get('state', 'N/A')}")
            logger.info(f"  Author: {issue_data.get('user', {}).get('login', 'N/A')}")
            logger.info(f"  Created: {issue_data.get('created_at', 'N/A')}")
            logger.info(f"  Updated: {issue_data.get('updated_at', 'N/A')}")

            # Extract labels
            labels = issue_data.get('labels', [])
            label_names = [label.get('name', '') for label in labels]
            logger.info(f"  Labels: {', '.join(label_names) if label_names else 'None'}")

            # Check for body_html field
            if 'body_html' in issue_data:
                logger.info("  ✓ body_html field present (contains JWT-authenticated attachment URLs)")

                # Extract attachments from body_html
                body_html = issue_data.get('body_html', '')
                attachments = extract_attachments_from_html(body_html)

                if attachments:
                    logger.info(f"  ✓ Found {len(attachments)} attachment(s) in issue body:")
                    for idx, att in enumerate(attachments, 1):
                        dims_str = ""
                        if att['dimensions']:
                            dims_str = f" [{att['dimensions'].get('width', '?')}x{att['dimensions'].get('height', '?')}]"
                        logger.info(f"    {idx}. {att['filename']} ({att['file_type']}{dims_str})")
                else:
                    logger.info("  No attachments found in issue body")

                # Store attachments in issue_data for later use
                issue_data['_attachments'] = attachments

            else:
                logger.warning("  ⚠ body_html field missing (may not be able to download attachments)")

            return issue_data

        except RuntimeError:
            # Re-raise RuntimeError from fetch_issue_html with clear context
            raise
        except Exception as e:
            raise RuntimeError(f"Failed to fetch issue data: {e}") from e

    def format_file_size(self, size_bytes: int) -> str:
        """Format file size in human-readable format"""
        if size_bytes < 1024:
            return f"{size_bytes} B"
        elif size_bytes < 1024 * 1024:
            return f"{size_bytes / 1024:.1f} KB"
        elif size_bytes < 1024 * 1024 * 1024:
            return f"{size_bytes / (1024 * 1024):.1f} MB"
        else:
            return f"{size_bytes / (1024 * 1024 * 1024):.1f} GB"

    @retry_on_transient_errors
    def _download_file(self, url: str) -> bytes:
        """Download file from URL (with retry logic)"""
        with urllib.request.urlopen(url, timeout=30) as response:
            return response.read()

    def download_attachment(self, url: str, output_path: Path) -> Dict[str, Any]:
        """Download a single attachment from a JWT-authenticated URL"""
        try:
            logger.info(f"  Downloading: {output_path.name}")

            # Create parent directories if needed
            output_path.parent.mkdir(parents=True, exist_ok=True)

            # Download file with timeout and automatic retry on transient errors
            # Note: JWT tokens are embedded in URL, no additional auth headers needed
            file_data = self._download_file(url)

            # Write file to disk
            with open(output_path, 'wb') as f:
                f.write(file_data)

            # Calculate file size
            file_size_bytes = len(file_data)
            file_size_human = self.format_file_size(file_size_bytes)

            # Extract file type from filename
            file_type = output_path.suffix.lstrip('.').lower() if output_path.suffix else 'unknown'

            # Truncate URL for logging (remove JWT parameters)
            source_url_short = url.split('?')[0] if '?' in url else url

            logger.info(f"    ✓ Downloaded {output_path.name} ({file_size_human})")

            return {
                'source_url': source_url_short,
                'file_type': file_type,
                'file_size': file_size_human,
                'file_size_bytes': file_size_bytes,
                'file_location': str(output_path.absolute()),
                'filename': output_path.name,
                'success': True,
                'error': None
            }

        except urllib.error.HTTPError as e:
            error_msg = f"HTTP {e.code}: {e.reason}"
            logger.error(f"    ✗ Failed to download {output_path.name}: {error_msg}")
            return {
                'source_url': url.split('?')[0] if '?' in url else url,
                'file_type': 'unknown',
                'file_size': '0 B',
                'file_size_bytes': 0,
                'file_location': str(output_path.absolute()),
                'filename': output_path.name,
                'success': False,
                'error': error_msg
            }

        except urllib.error.URLError as e:
            error_msg = f"Network error: {e.reason}"
            logger.error(f"    ✗ Failed to download {output_path.name}: {error_msg}")
            return {
                'source_url': url.split('?')[0] if '?' in url else url,
                'file_type': 'unknown',
                'file_size': '0 B',
                'file_size_bytes': 0,
                'file_location': str(output_path.absolute()),
                'filename': output_path.name,
                'success': False,
                'error': error_msg
            }

        except TimeoutError as e:
            error_msg = "Download timed out (30 seconds)"
            logger.error(f"    ✗ Failed to download {output_path.name}: {error_msg}")
            return {
                'source_url': url.split('?')[0] if '?' in url else url,
                'file_type': 'unknown',
                'file_size': '0 B',
                'file_size_bytes': 0,
                'file_location': str(output_path.absolute()),
                'filename': output_path.name,
                'success': False,
                'error': error_msg
            }

        except OSError as e:
            error_msg = f"Filesystem error: {e}"
            logger.error(f"    ✗ Failed to download {output_path.name}: {error_msg}")
            return {
                'source_url': url.split('?')[0] if '?' in url else url,
                'file_type': 'unknown',
                'file_size': '0 B',
                'file_size_bytes': 0,
                'file_location': str(output_path.absolute()),
                'filename': output_path.name,
                'success': False,
                'error': error_msg
            }

        except Exception as e:
            error_msg = f"Unexpected error: {e}"
            logger.error(f"    ✗ Failed to download {output_path.name}: {error_msg}")
            return {
                'source_url': url.split('?')[0] if '?' in url else url,
                'file_type': 'unknown',
                'file_size': '0 B',
                'file_size_bytes': 0,
                'file_location': str(output_path.absolute()),
                'filename': output_path.name,
                'success': False,
                'error': error_msg
            }

    def download_attachments(self, issue_data: Dict[str, Any]) -> Dict[str, Any]:
        """Download all attachments from issue and comments"""
        logger.info("\n" + "=" * 60)
        logger.info("Downloading attachments...")
        logger.info("=" * 60)

        total_attachments = 0
        downloaded_count = 0
        failed_count = 0
        total_size_bytes = 0
        download_metadata = []

        # Download issue body attachments
        issue_attachments = issue_data.get('_attachments', [])
        if issue_attachments:
            logger.info(f"\nDownloading {len(issue_attachments)} attachment(s) from issue body...")

            for idx, attachment in enumerate(issue_attachments, 1):
                url = attachment['url']
                filename = attachment['filename']
                output_path = self.issue_attachments_dir / filename

                logger.info(f"\n  [{idx}/{len(issue_attachments)}] {filename}")

                # Download attachment
                metadata = self.download_attachment(url, output_path)
                download_metadata.append({
                    'source': 'issue',
                    'source_id': self.issue_number,
                    **metadata
                })

                if metadata['success']:
                    downloaded_count += 1
                    total_size_bytes += metadata['file_size_bytes']
                else:
                    failed_count += 1

                total_attachments += 1

        # Download comment attachments
        comments = issue_data.get('_comments', [])
        if comments:
            for comment_idx, comment in enumerate(comments, 1):
                comment_attachments = comment.get('_attachments', [])
                if not comment_attachments:
                    continue

                comment_id = comment['comment_id']
                logger.info(f"\nDownloading {len(comment_attachments)} attachment(s) from comment #{comment_idx} (ID: {comment_id})...")

                # Create comment-specific directory
                comment_dir = self.comments_attachments_dir / str(comment_id)

                for idx, attachment in enumerate(comment_attachments, 1):
                    url = attachment['url']
                    filename = attachment['filename']
                    output_path = comment_dir / filename

                    logger.info(f"\n  [{idx}/{len(comment_attachments)}] {filename}")

                    # Download attachment
                    metadata = self.download_attachment(url, output_path)
                    download_metadata.append({
                        'source': 'comment',
                        'source_id': comment_id,
                        **metadata
                    })

                    if metadata['success']:
                        downloaded_count += 1
                        total_size_bytes += metadata['file_size_bytes']
                    else:
                        failed_count += 1

                    total_attachments += 1

        # Store download metadata in issue_data
        issue_data['_download_metadata'] = download_metadata

        # Summary statistics
        total_size_human = self.format_file_size(total_size_bytes)

        logger.info("\n" + "=" * 60)
        logger.info("Download Summary:")
        logger.info("=" * 60)
        logger.info(f"  Total attachments: {total_attachments}")
        logger.info(f"  Downloaded: {downloaded_count}")
        logger.info(f"  Failed: {failed_count}")
        logger.info(f"  Total size: {total_size_human}")

        if failed_count > 0:
            logger.warning(f"\n  ⚠ {failed_count} download(s) failed. Check logs above for details.")

        return {
            'total_attachments': total_attachments,
            'downloaded': downloaded_count,
            'failed': failed_count,
            'total_size': total_size_human,
            'total_size_bytes': total_size_bytes
        }

    def format_datetime(self, iso_timestamp: str) -> str:
        """Format ISO 8601 timestamp to human-readable format"""
        from datetime import datetime

        try:
            # Parse ISO timestamp
            dt = datetime.fromisoformat(iso_timestamp.replace('Z', '+00:00'))

            # Format as readable string
            return dt.strftime("%B %d, %Y at %I:%M %p UTC")
        except Exception:
            # Fallback: return original string if parsing fails
            return iso_timestamp

    def format_dimensions(self, dimensions: Optional[Dict[str, int]]) -> str:
        """Format image dimensions for display"""
        if not dimensions:
            return "N/A"

        width = dimensions.get('width', '?')
        height = dimensions.get('height', '?')
        return f"{width}x{height}"

    def generate_manifest(self, issue_data: Dict[str, Any]) -> str:
        """Generate LLM-friendly markdown manifest from issue data"""
        lines = []

        # Issue Header
        lines.append(f"# Issue #{self.issue_number}: {issue_data.get('title', 'N/A')}")
        lines.append("")
        lines.append("## Issue Metadata")
        lines.append("")
        lines.append(f"- **Repository:** {self.repo}")
        lines.append(f"- **Issue Number:** #{self.issue_number}")
        lines.append(f"- **State:** {issue_data.get('state', 'N/A')}")
        lines.append(f"- **Created:** {self.format_datetime(issue_data.get('created_at', ''))}")
        lines.append(f"- **Updated:** {self.format_datetime(issue_data.get('updated_at', ''))}")

        # Author
        user = issue_data.get('user', {})
        author = user.get('login', 'N/A') if user else 'N/A'
        lines.append(f"- **Author:** @{author}")

        # Labels
        labels = issue_data.get('labels', [])
        if labels:
            label_names = [label.get('name', '') for label in labels]
            lines.append(f"- **Labels:** {', '.join(label_names)}")
        else:
            lines.append("- **Labels:** None")

        lines.append("")

        # Issue Body
        lines.append("## Issue Body")
        lines.append("")
        body = issue_data.get('body', '')
        if body:
            lines.append(body)
        else:
            lines.append("*No description provided*")
        lines.append("")

        # Issue Attachments
        download_metadata = issue_data.get('_download_metadata', [])
        issue_attachments = [meta for meta in download_metadata if meta.get('source') == 'issue']

        if issue_attachments:
            lines.append("## Issue Attachments")
            lines.append("")
            lines.append("| File | Type | Size | Dimensions | Uploaded By | Location |")
            lines.append("|------|------|------|------------|-------------|----------|")

            for meta in issue_attachments:
                filename = meta.get('filename', 'unknown')
                file_type = meta.get('file_type', 'unknown')
                file_size = meta.get('file_size', '0 B')
                file_location = meta.get('file_location', 'N/A')

                # Get dimensions from original attachment metadata if available
                # Prioritize attachments with dimensions (img tags) over those without (a tags)
                dimensions = "N/A"
                issue_attachments_list = issue_data.get('_attachments', [])
                for att in issue_attachments_list:
                    if att['filename'] == filename:
                        att_dims = att.get('dimensions')
                        if att_dims:
                            dimensions = self.format_dimensions(att_dims)
                            break
                        elif dimensions == "N/A":
                            dimensions = self.format_dimensions(att_dims)

                lines.append(f"| {filename} | {file_type} | {file_size} | {dimensions} | @{author} | `{file_location}` |")

            lines.append("")

        # Comments Section
        comments = issue_data.get('_comments', [])
        if comments:
            lines.append(f"## Comments ({len(comments)})")
            lines.append("")

            for idx, comment in enumerate(comments, 1):
                comment_id = comment.get('comment_id', 'unknown')
                comment_author = comment.get('author', 'ghost')
                comment_created = self.format_datetime(comment.get('created_at', ''))
                comment_body = comment.get('body', '')

                lines.append(f"### Comment #{idx}")
                lines.append("")
                lines.append(f"- **Author:** @{comment_author}")
                lines.append(f"- **Posted:** {comment_created}")
                lines.append(f"- **Comment ID:** {comment_id}")
                lines.append("")
                lines.append("**Content:**")
                lines.append("")
                if comment_body:
                    lines.append(comment_body)
                else:
                    lines.append("*No content*")
                lines.append("")

                # Comment Attachments
                comment_attachments = [meta for meta in download_metadata if meta.get('source') == 'comment' and meta.get('source_id') == comment_id]

                if comment_attachments:
                    lines.append("**Attachments:**")
                    lines.append("")
                    lines.append("| File | Type | Size | Dimensions | Location |")
                    lines.append("|------|------|------|------------|----------|")

                    for meta in comment_attachments:
                        filename = meta.get('filename', 'unknown')
                        file_type = meta.get('file_type', 'unknown')
                        file_size = meta.get('file_size', '0 B')
                        file_location = meta.get('file_location', 'N/A')

                        # Get dimensions from comment attachment metadata
                        # Prioritize attachments with dimensions (img tags) over those without (a tags)
                        dimensions = "N/A"
                        comment_attachments_list = comment.get('_attachments', [])
                        for att in comment_attachments_list:
                            if att['filename'] == filename:
                                att_dims = att.get('dimensions')
                                if att_dims:
                                    dimensions = self.format_dimensions(att_dims)
                                    break
                                elif dimensions == "N/A":
                                    dimensions = self.format_dimensions(att_dims)

                        lines.append(f"| {filename} | {file_type} | {file_size} | {dimensions} | `{file_location}` |")

                    lines.append("")

                lines.append("---")
                lines.append("")

        # Summary Section
        lines.append("## Summary")
        lines.append("")
        lines.append(f"- **Total Comments:** {len(comments)}")

        # Calculate attachment statistics
        total_attachments = len(download_metadata)
        successful_downloads = len([m for m in download_metadata if m.get('success', False)])
        failed_downloads = len([m for m in download_metadata if not m.get('success', False)])

        # Count by file type
        file_types = {}
        for meta in download_metadata:
            if meta.get('success', False):
                file_type = meta.get('file_type', 'unknown')
                file_types[file_type] = file_types.get(file_type, 0) + 1

        # Calculate total size
        total_size_bytes = sum(meta.get('file_size_bytes', 0) for meta in download_metadata if meta.get('success', False))
        total_size_human = self.format_file_size(total_size_bytes)

        lines.append(f"- **Total Attachments:** {total_attachments}")
        lines.append(f"- **Successfully Downloaded:** {successful_downloads}")
        if failed_downloads > 0:
            lines.append(f"- **Failed Downloads:** {failed_downloads}")

        if file_types:
            file_type_summary = ', '.join([f"{count} {ftype}" for ftype, count in sorted(file_types.items())])
            lines.append(f"- **File Types:** {file_type_summary}")

        lines.append(f"- **Total Size:** {total_size_human}")
        lines.append("")

        # Footer
        lines.append("---")
        lines.append("")
        lines.append(f"*Generated by fetch-issue-complete.py on {self.format_datetime(issue_data.get('updated_at', ''))}*")

        return '\n'.join(lines)

    def save_manifest(self, issue_data: Dict[str, Any]) -> None:
        """Generate and save manifest.md file"""
        manifest_file = self.output_dir / "manifest.md"
        logger.info(f"Generating manifest: {manifest_file}...")

        try:
            manifest_content = self.generate_manifest(issue_data)

            with open(manifest_file, 'w', encoding='utf-8') as f:
                f.write(manifest_content)

            logger.info(f"✓ Saved: {manifest_file}")
        except OSError as e:
            logger.error(f"Failed to save manifest: {e}")
            raise

    def save_issue_data(self, issue_data: Dict[str, Any]) -> None:
        """Save issue data to JSON file"""
        output_file = self.output_dir / "issue.json"
        logger.info(f"Saving issue data to {output_file}...")

        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(issue_data, f, indent=2, ensure_ascii=False)
            logger.info(f"✓ Saved: {output_file}")
        except OSError as e:
            logger.error(f"Failed to save issue data: {e}")
            raise

    def run(self) -> None:
        """Main execution flow"""
        try:
            # Step 1: Validate inputs
            self.validate_inputs()

            # Step 2: Create output directories
            self.create_output_directories()

            # Step 3: Fetch issue data
            issue_data = self.fetch_issue_data()

            # Step 4: Fetch comments
            logger.info("\n" + "=" * 60)
            comments = self.fetch_comments_html(self.repo, self.issue_number, self.github_token)

            if comments:
                logger.info(f"\n✓ Fetched {len(comments)} comment(s)")

                # Log attachment information for each comment
                total_comment_attachments = 0
                for idx, comment in enumerate(comments, 1):
                    attachments = comment.get('_attachments', [])
                    if attachments:
                        logger.info(f"\n  Comment #{idx} (ID: {comment['comment_id']}) has {len(attachments)} attachment(s):")
                        for att_idx, att in enumerate(attachments, 1):
                            dims_str = ""
                            if att['dimensions']:
                                dims_str = f" [{att['dimensions'].get('width', '?')}x{att['dimensions'].get('height', '?')}]"
                            logger.info(f"    {att_idx}. {att['filename']} ({att['file_type']}{dims_str})")
                        total_comment_attachments += len(attachments)

                if total_comment_attachments > 0:
                    logger.info(f"\n  ✓ Total attachments in comments: {total_comment_attachments}")
                else:
                    logger.info("\n  No attachments found in comments")

                # Add comments to issue_data
                issue_data['_comments'] = comments

            else:
                logger.info("\n  No comments on this issue")

            # Step 5: Download attachments
            issue_attachments = len(issue_data.get('_attachments', []))
            comment_attachments = sum(len(c.get('_attachments', [])) for c in comments)
            total_attachments = issue_attachments + comment_attachments

            if total_attachments > 0:
                download_stats = self.download_attachments(issue_data)
            else:
                logger.info("\n" + "=" * 60)
                logger.info("No attachments to download")
                logger.info("=" * 60)
                download_stats = {
                    'total_attachments': 0,
                    'downloaded': 0,
                    'failed': 0,
                    'total_size': '0 B',
                    'total_size_bytes': 0
                }

            # Step 6: Save issue data and manifest
            logger.info("\n" + "=" * 60)
            self.save_issue_data(issue_data)
            self.save_manifest(issue_data)

            # Summary
            logger.info("=" * 60)
            logger.info("SUCCESS: Issue data fetched and saved")
            logger.info("=" * 60)
            logger.info(f"Summary:")
            logger.info(f"  Issue: #{self.issue_number}")
            logger.info(f"  Comments: {len(comments)}")
            logger.info(f"  Attachments in issue: {issue_attachments}")
            logger.info(f"  Attachments in comments: {comment_attachments}")
            logger.info(f"  Total attachments: {total_attachments}")
            if total_attachments > 0:
                logger.info(f"  Downloaded: {download_stats['downloaded']}")
                logger.info(f"  Failed: {download_stats['failed']}")
                logger.info(f"  Total size: {download_stats['total_size']}")
            logger.info(f"\nOutput:")
            logger.info(f"  JSON: {self.output_dir / 'issue.json'}")
            logger.info(f"  Manifest: {self.output_dir / 'manifest.md'}")
            if download_stats['downloaded'] > 0:
                logger.info(f"  Attachments: {self.attachments_dir}")

        except Exception as e:
            logger.error(f"Fatal error: {e}")
            raise


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(
        description="Fetch complete GitHub issue data with attachments",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --repo owner/repo --issue 123 --output-dir /tmp/issue-123 --github-token TOKEN
        """
    )

    parser.add_argument(
        '--repo',
        type=str,
        required=True,
        help='Repository in format OWNER/REPO (e.g., owner/repo)'
    )

    parser.add_argument(
        '--issue',
        type=int,
        required=True,
        help='Issue number (integer)'
    )

    parser.add_argument(
        '--output-dir',
        type=str,
        required=True,
        help='Directory to store issue data and attachments'
    )

    parser.add_argument(
        '--github-token',
        type=str,
        required=True,
        help='GitHub personal access token (or use GITHUB_TOKEN env var)'
    )

    return parser.parse_args()


def main() -> int:
    """Main entry point"""
    try:
        # Parse command-line arguments
        args = parse_arguments()

        logger.info("=" * 60)
        logger.info("GitHub Issue Data Fetcher - Foundation")
        logger.info("=" * 60)

        # Create fetcher instance
        fetcher = IssueDataFetcher(
            repo=args.repo,
            issue_number=args.issue,
            output_dir=args.output_dir,
            github_token=args.github_token
        )

        # Run the fetcher
        fetcher.run()

        return 0

    except ValueError as e:
        logger.error(f"Invalid argument: {e}")
        return 1
    except OSError as e:
        logger.error(f"Filesystem error: {e}")
        return 3
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
