# Zaptilo WhatsApp for Salesforce

> Send WhatsApp Business messages directly from Salesforce — templates, free-form, bulk campaigns, Flow-triggered automations. Powered by [Zaptilo](https://zaptilo.ai)'s pay-as-you-go WhatsApp Business API.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zaptilo](https://img.shields.io/badge/powered_by-Zaptilo.ai-d97706)](https://zaptilo.ai)
[![Salesforce API](https://img.shields.io/badge/Salesforce-API_60.0-00a1e0)](https://developer.salesforce.com)

## What it does

| Feature | Where |
|---|---|
| **Send WhatsApp** Quick Action | On Contact, Lead, Case, Opportunity, Account records |
| **Template messages** with merge fields | Pick from synced WhatsApp templates, fill variables from record data |
| **Free-form messages** (24h window aware) | Allowed when an open conversation exists; auto-falls-back to template otherwise |
| **Triggered messages from Flow** | Invocable Apex `Zaptilo.sendTemplate()` — works in Flow, Process Builder, Apex Trigger |
| **Bulk send from list view** | Select Contacts/Leads, fire as a Zaptilo campaign (planned in v0.3) |
| **Inbound replies → Tasks** | Webhook from Zaptilo creates a Task per incoming message, threaded on the record (planned in v0.2) |
| **Compliance gate** | `Do_Not_WhatsApp__c` checkbox on Contact / Lead — every send checks this first |
| **Message log** | Every send and inbound is recorded on `WhatsApp_Message__c` |

## Requirements

- Salesforce Enterprise / Performance / Unlimited / Developer Edition
- Salesforce API version 60.0 or higher
- A Zaptilo account ([sign up free at zaptilo.ai](https://web.zaptilo.ai/signup))
- An approved WhatsApp Business number on Zaptilo

## Install (unmanaged package)

Coming soon — install URL will be added once v0.1 is signed off.

For now, deploy from source:

```bash
sf org login web -a zaptilo-dev
sf project deploy start --source-dir force-app --target-org zaptilo-dev
sf org assign permset --name Zaptilo_User --target-org zaptilo-dev
```

## Setup (after install)

1. Open **App Launcher → Zaptilo Settings** in your org
2. Paste your Zaptilo API token (find it at [web.zaptilo.ai](https://web.zaptilo.ai) → Settings → API Keys)
3. Pick a default WABA / phone number
4. Save

The "Send WhatsApp" Quick Action is now active on Contact pages.

## Roadmap

| Version | Scope |
|---|---|
| **v0.1** (in progress) | Settings, Contact Quick Action with template send, message log |
| **v0.2** | Flow invocable, free-form (24h-aware) send, opt-out gate, inbound webhook → Task |
| **v0.3** | Bulk send from list view, activity history LWC on record pages |
| **v0.4** | Package as install URL, distribute via GitHub release |
| **v1.0** | AppExchange submission (managed package + Security Review) |

## Support

- Email: [connect@zaptilo.ai](mailto:connect@zaptilo.ai)
- Docs: [zaptilo.ai/getting-started](https://zaptilo.ai/getting-started)
- Issues: GitHub Issues on this repo

## License

MIT — see [LICENSE](LICENSE).
