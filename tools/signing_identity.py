#!/usr/bin/env python3
"""The certificate to sign with, from the keychain: signing_identity.py KIND TEAM

KIND is "Apple Development" (a build on this Mac) or "Developer ID Application" (a release). Only a
certificate of TEAM counts, read from the certificate itself, never another team's, such as an
employer's. Of those, the one that runs longest: a renewed certificate has the same name as the old
one, so codesign gets the SHA-1 fingerprint. Prints "SHA1<tab>NAME", or nothing if there's none.
"""
import re
import subprocess
import sys


def identities(kind: str) -> list[tuple[str, str]]:
    """Valid signing identities of that kind: (fingerprint, name)."""
    out = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True).stdout
    return [(h, n) for h, n in re.findall(r'\)\s+([0-9A-F]{40})\s+"([^"]+)"', out) if n.startswith(kind + ":")]


def certificates(name: str) -> dict[str, str]:
    """Every certificate with that name, by fingerprint, as PEM."""
    out = subprocess.run(["security", "find-certificate", "-a", "-Z", "-p", "-c", name], capture_output=True, text=True).stdout
    return {h: pem for h, pem in re.findall(r"SHA-1 hash: ([0-9A-F]{40})\s+(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)", out, re.S)}


def details(pem: str) -> tuple[str, str]:
    """The team (OU) and the expiry, as openssl gives them."""
    out = subprocess.run(["openssl", "x509", "-noout", "-subject", "-enddate", "-nameopt", "sep_multiline"],
                         input=pem, capture_output=True, text=True).stdout
    team = re.search(r"^\s*OU=(\S+)\s*$", out, re.M)
    end = re.search(r"^notAfter=(.+)$", out, re.M)
    return (team.group(1) if team else ""), (end.group(1).strip() if end else "")


def main(kind: str, team: str) -> int:
    from datetime import datetime
    best = None
    for fingerprint, name in identities(kind):
        pem = certificates(name).get(fingerprint)
        if not pem:
            continue
        owner, end = details(pem)
        if owner != team:
            continue
        until = datetime.strptime(end.replace("  ", " "), "%b %d %H:%M:%S %Y %Z")
        if best is None or until > best[0]:
            best = (until, fingerprint, name)
    if best:
        print(f"{best[1]}\t{best[2]}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
