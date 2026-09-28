# Postfix relay for Microsoft 365 (Exchange Online connector)

A minimal Postfix container that accepts mail from your devices/apps and
forwards it to Exchange Online through the
[SMTP relay connector](https://learn.microsoft.com/en-us/exchange/mail-flow-best-practices/how-to-set-up-a-multifunction-device-or-application-to-send-email-using-microsoft-365-or-office-365#smtp-relay-configure-a-connector-to-relay-email-from-your-device-or-application-through-microsoft-365-or-office-365)
(Option 3 in that article). No SMTP AUTH is used.

## Exchange Online side

Create a connector in the Exchange admin center (Mail flow > Connectors):

- From: **Your organization's email server**, To: **Office 365**
- Authenticate the sender by **one** of:
  - **IP address**: the public egress IP of the host running this container, or
  - **Certificate**: a publicly trusted cert whose subject/SAN matches one of your
    accepted domains. Mount it and set `POSTFIX_SMTP_TLS_CERT_FILE` / `POSTFIX_SMTP_TLS_KEY_FILE`.
- Sender addresses must belong to a domain accepted in your tenant.
- Outbound TCP 25 must be open from the host to `<domain>.mail.protection.outlook.com`
  (many ISPs and cloud providers block it).

## Run

```sh
cp env.example .env      # set RELAY_DOMAIN at minimum
docker compose up -d --build
docker compose logs -f
```

Test from a client inside `POSTFIX_MYNETWORKS`:

```sh
swaks --server <host>:25 --from you@contoso.com --to someone@example.com
```

## Configuration

Any environment variable named `POSTFIX_<NAME>` is written to `main.cf` as the
lowercased parameter `<name>`. Variables can come from `docker run -e`, compose
`environment:`/`env_file:` (your `.env`), or a shell-style file mounted at
`/config/relay.env` (quote values containing spaces there).

| Variable | Default |
|---|---|
| `RELAY_DOMAIN` | **required** |
| `M365_HOST` | `<domain-with-dashes>.mail.protection.outlook.com` |
| `POSTFIX_RELAYHOST` | `[$M365_HOST]:25` |
| `POSTFIX_SMTPD_RECIPIENT_RESTRICTIONS` | `permit_mynetworks,reject_unauth_destination` |
| `POSTFIX_MYNETWORKS` | loopback + RFC1918 ranges (tighten this) |
| `POSTFIX_MYHOSTNAME` | container hostname |
| `POSTFIX_SMTP_TLS_SECURITY_LEVEL` | `encrypt` |

### Changing `smtpd_recipient_restrictions`

Set it in `.env`:

```
POSTFIX_SMTPD_RECIPIENT_RESTRICTIONS=permit_mynetworks,reject_unauth_destination
```

Or one-off: `docker run -e POSTFIX_SMTPD_RECIPIENT_RESTRICTIONS="..." ...`

Restrictions are evaluated in order and the first match wins, so put `reject`/`check_*`
rules **before** `permit_mynetworks`. Example that only allows recipients
listed in a regexp map:

`config/recipient_access.regexp`
```
/@contoso\.com$/    OK
/@partner\.example$/ OK
/./                 REJECT Recipient domain not allowed
```

`.env`
```
POSTFIX_SMTPD_RECIPIENT_RESTRICTIONS=check_recipient_access regexp:/config/recipient_access.regexp,permit_mynetworks,reject_unauth_destination
```

(mount `./config:/config:ro`; regexp maps need no `postmap`.)

Note that `smtpd_relay_restrictions` (Postfix default: `permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination`)
is evaluated first; recipient restrictions can only narrow what it allows. Override it with
`POSTFIX_SMTPD_RELAY_RESTRICTIONS` if needed.

## Security notes

- This is an open relay for anything inside `POSTFIX_MYNETWORKS`. Don't publish port 25
  to the internet, and narrow `POSTFIX_MYNETWORKS` to your actual client subnets.
- `smtp_tls_security_level=encrypt` enforces TLS but doesn't verify the Microsoft cert
  name; use `POSTFIX_SMTP_TLS_SECURITY_LEVEL=verify` if you want strict verification
  (the default match rule checks the certificate against the smart host name).
