# Quota CN (Qoder CN)

The Agent Wallet account is named **Quota CN** as requested. It monitors the
Qoder CN desktop account and is inserted after OpenCode Go until manually reordered.

The current desktop application uses a different endpoint from the older Qoder
website integration in CodexBar:

- `GET https://openapi.qoder.com.cn/sash/api/v2/me/usage`
- Authorization: its saved bearer token; `Cosy-ClientType: 10`.
- Local credential: `Library/Application Support/com.qodercn.app.stable/auth.v1.dat`.
- Electron safe-storage keychain service: `Qoder CN App Safe Storage`.

Only the token is imported into `Pulse/qoder-cn-session.dat`, using the existing
LocalSecrets encryption and owner-only file permissions. The master safe-storage
key is never persisted by Agent Wallet. LocalSecrets derives its encryption key
from the machine ID: this protects copied files but is not equivalent to Keychain
access control against other processes running as the same user.

The session survives relaunches for at most seven days, is bound to the hash of
Qoder's encrypted login file, and is invalidated on HTTP 401/403. Account changes
and logout prevent reuse. Qoder remains responsible for renewing its own login.
Background reads use both `LAContext.interactionNotAllowed` and Keychain's UI-fail
policy. Only the explicit **Connect Qoder CN** button allows an authorization
prompt. A failed silent read reports that connection is needed, never pops up.

`qoder.svg` is the actual template image loaded by LobeIconStore. Its paths come
from the official wordmark used at qoder.com.cn:
https://img.alicdn.com/imgextra/i2/O1CN016fdrcQ26TiDCreYYo_!!6000000007663-55-tps-105-26.svg
Only the symbol is retained; the wordmark text is omitted. A PNG with the same
basename is not used by this SVG-only renderer.

The response's `qoderUsage.userQuota` reports `used` and `total`; remaining is
`max(0, total - used)`. `300 / 300` means used 100%, remaining 0. Add-on credits
remain a separate window. `expiresAt` provides the plan's reset date; a guessed
30-day duration is used only for sorting, never for elapsed-time calculations.

Regression checks: `swift test --filter WalletConnectionTests`.
An explicitly opt-in live check is available with `AGENT_WALLET_LIVE_CHECK=1`;
it prints only state, balance and usage fraction, never tokens or response bodies.
