"""Relax Python 3.13+ strict X509 verification for TLS-intercepting proxies.

Python 3.13 turned on ssl.VERIFY_X509_STRICT by default, which rejects any
certificate lacking an Authority Key Identifier. A corporate proxy that
re-signs every site with such a CA makes each stdlib urlopen() fail with
"CERTIFICATE_VERIFY_FAILED: Missing Authority Key Identifier" while curl works.

Chain-of-trust verification stays on (the corporate CA still comes from
SSL_CERT_FILE); only the extra RFC 5280 strictness is dropped.
Installed into Hermes' pinned Python (~/.hermes/tools) by hermes/setup.sh Part 6 —
never into the system Python.
"""
import ssl

_orig = ssl.create_default_context


def _create_default_context(*args, **kwargs):
    ctx = _orig(*args, **kwargs)
    ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
    return ctx


ssl.create_default_context = _create_default_context
# http.client / urllib bind this name at import time, so patch it too.
ssl._create_default_https_context = _create_default_context
