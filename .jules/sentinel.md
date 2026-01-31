## 2025-02-18 - RCE via Relative Path in LSP Server Command
**Vulnerability:** Defaulting `lsp-augment-server-script` to `"server.js"` allowed `lsp-mode` to execute a malicious `server.js` if one existed in the project root, because `node` was invoked with a relative path.
**Learning:** External process commands in Emacs plugins must use absolute paths to avoid untrusted search path vulnerabilities (CWE-427), especially when the command is generic like `node`.
**Prevention:** Use `(expand-file-name "../path/to/script" (file-name-directory load-file-name))` to resolve bundled scripts to absolute paths at load time.
