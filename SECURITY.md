# Security

Do not commit subscription URLs, fallback proxy credentials, local state files, or logs.

The installer stores an optional fallback proxy in:

```text
~/.local/state/clash-recover/fallback-proxy
```

Use unauthenticated local or private-network fallback proxies only. Authenticated proxy URLs are rejected by the installer and runtime parser.

If you find a credential leak or command injection issue, open a private advisory on GitHub instead of filing a public issue.
