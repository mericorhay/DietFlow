---
title: DietFlow Privacy Policy
---

# DietFlow Privacy Policy

*Last updated 11 October 2026. Describes version 1.0.0, build 14 and later.*

DietFlow is an iPhone meal planner published by Meric Orhay. Contact the developer at
<mericorhayy@gmail.com> for privacy questions or requests. This policy covers the app, its
widgets and its optional online AI assistant. There is no account, advertising or advertising
tracking. We do not sell personal data.

## Plans and imports on your iPhone

Meal plans, meal completion, reminders, food exclusions, settings and cached recipes are stored
on your device. The widget reads a shared local copy. DietFlow has no cloud sync or backup
service of its own. Device backups you enable with Apple may include app data under your Apple
settings. Exporting a plan or contacting support shares the information you choose with the
destination you select.

Text recognition in photos and PDFs runs on the device. When available, Apple's on-device
language model can help read imported text. Original photos and PDFs are not uploaded to our
AI service. If you choose the online assistant to organise extracted text, that text follows
the AI process below. Ordinary manual planning and local imports do not require this sharing.

## Optional AI: OpenAI, through Cloudflare

The online AI provider is **OpenAI**, accessed through OpenAI's API. Our intermediary server is
a **Cloudflare Worker**. Requests and responses travel over HTTPS. The permission prompt names
OpenAI and explains the information involved before an AI request is made. Permission covers
the AI features below; only information needed for a feature you request is sent. You may
decline and continue using manual plans, local imports, widgets and reminders.

| Requested feature | Content sent to OpenAI via Cloudflare |
|---|---|
| Organise a plan | Text you submit, including text extracted locally if you choose to submit it, and output language |
| Create a plan | Number of days, meals per day, preferences you enter, and output language |
| Estimate nutrition | Selected meals' names, descriptions, portions and meal types, plus output language; temporary meal identifiers match answers to meals |
| Write a recipe | Selected meal's name, description and type, number of servings, foods you ask to avoid, and output language |

The server receives your IP address and routine connection information. Each app request also
carries a random installation identifier for abuse control; it is not your Apple Account or an
advertising identifier. The installation identifier is not included in the model prompt. Other
plans, unrelated notes, original photos and PDFs, payment credentials and Apple Account details
are not sent to OpenAI by these features. Do not include private medical details or other
people's personal information in free text.

We do not persist or log AI request or response content on our server. Technical diagnostics
include request paths, status/error codes, model names and aggregate counts/sizes. Cloudflare
processes network and security information to operate the service under its own policies.

OpenAI states that API content is not used to train its models by default unless the customer
opts in. Its default abuse monitoring logs may retain content for up to 30 days, with legal or
safety exceptions. We have not represented this service as Zero Data Retention. See
[OpenAI's API data controls](https://developers.openai.com/api/docs/guides/your-data) and
[privacy policy](https://openai.com/policies/privacy-policy/).

AI answers can be inaccurate. Nutrition values are estimates; recipes and food exclusions do
not guarantee allergy safety or medical suitability. Review outputs before relying on them.
The app can save accepted plans and nutrition locally and cache recipes locally for reuse.

## Optional usage analytics: PostHog

Starting with build 14, **Share Usage Data is off by default**, including on upgrades. If you
enable it in Settings, PostHog receives feature events, request outcomes, allowance counts,
purchase outcomes/tier, app language/version and routine device/app properties. It associates
events with a random persistent app identifier. These records are pseudonymous, not completely
anonymous. No meal names, plan content, food exclusions, photos, files or typed assistant text
are included in analytics events.

The app disables location enrichment and identified person profiles, automatic screen capture
and session replay. It does not use IDFA, advertising tracking or cross-app advertising
profiles. Network providers still receive IP addresses when connections are made. The configured
PostHog endpoint is in the United States; see
[PostHog's privacy policy](https://posthog.com/privacy).

Turning the switch off stops future analytics capture and transmission by the app. It does not
automatically delete events already received. Those events remain subject to the PostHog
project's retention settings or deletion following an applicable request. Contact us if you
want to request deletion; because the app has no account, we may need technical information
to identify the relevant installation without collecting unrelated identity documents.

## Purchases and service providers

Apple processes DietFlow Plus payments and subscriptions. The app checks StoreKit entitlements
to unlock Plus. We do not receive card details or Apple Account credentials. If analytics is
enabled, purchase outcomes and tier can be recorded as described above. Subscription management
and refunds are handled through Apple.

The processors involved are OpenAI for requested AI content, Cloudflare for the intermediary
service and network/security processing, PostHog for opted-in analytics, and Apple for purchases
and operating system services. These providers may process information outside your country,
including in the United States, subject to their applicable contractual safeguards and policies.
See [Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/).

## Retention, deletion and your choices

- Local plans remain until you delete them. **Delete All Data** removes plans, meal completion,
  day-start records and the local recipe cache. Some preferences remain until reset or the app
  is removed; device backups must be managed through Apple separately.
- A small local AI allowance ledger remains in the iPhone Keychain across reinstallations to
  prevent resetting allowances. It holds usage counts/period information, not meal content.
- Disable **Settings › Privacy › Send Assistant Text to OpenAI** to withdraw permission for
  future requests. The next AI request asks again; declining sends no request. This does not
  retroactively erase data already processed by a provider.
- Disable **Settings › Share Usage Data** to stop future analytics. No analytics sharing is
  required to use the app or buy Plus.
- For AI provider retention, the default and exceptions are stated above. Our service does not
  retain AI content; technical and security records are retained as needed for operation,
  troubleshooting, abuse prevention and applicable legal duties.
- Depending on your location, including the EU and Türkiye, applicable law may provide rights
  of access, correction, deletion, restriction, objection or complaint to a supervisory
  authority. Send requests to <mericorhayy@gmail.com>. We will assess the request and explain
  what we can identify, delete or help you request from a provider.

## Children and changes

DietFlow is not directed at children under 13, and we do not knowingly collect their personal
information. Contact us if you believe a child has provided information. Material changes to
this policy update the date and are described in app release notes. If AI sharing expands,
the app will request permission under the updated disclosure.

See also [Support](support) and [Terms of Use](terms).
