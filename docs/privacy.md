---
title: DietFlow Privacy Policy
---

# DietFlow Privacy Policy

*Last updated 6 October 2026.*

DietFlow ("Meal Planner Widget: DietFlow") is a meal plan app for iPhone, published by its
developer ("we"). This page says what happens to what you put into it, who else
is involved, and what you can do about it.

In short: your plan stays on your iPhone. Two things can leave it, and each has its own switch:
text you give the assistant, which goes to OpenAI, and anonymous usage data, which goes to PostHog.

## What stays on your iPhone

Your meal plans, what you mark as done or skipped, your reminders and your settings are stored on
your iPhone, in the app and its widgets. They are not sent to us. DietFlow has no account, no
sign-in and no advertising.

Reading a plan from pasted text, a file, a photo or a PDF happens on your iPhone. Where your
iPhone has Apple Intelligence, the text is read by Apple's on-device language model; text in
photos and PDFs is recognised by iOS's on-device text recognition. Neither sends anything to us.

## The assistant: which AI, and where your text goes

The assistant puts an untidy list in order or writes a new plan. It is the only part of the app
that sends what you type anywhere.

- **The AI is OpenAI's.** The assistant uses OpenAI's GPT models through OpenAI's API.
- **Nothing is sent until you agree.** The first time you use the assistant, the app tells you the
  text will be sent to OpenAI and asks for your permission. You can withdraw it at any time in
  *Settings › Privacy › Send Assistant Text to OpenAI*; the app then asks again before sending.
- **The route.** The text goes from your iPhone to our server (a Cloudflare Worker), which passes
  it to OpenAI and returns the plan. Our server exists so that no OpenAI key is inside the app.
- **What is sent.** The text you entered, or for a new plan the number of days, meals per day and
  what you wrote about how you eat. Nothing else from the app is included: not your other plans,
  not your name, not your location.
- **What we keep.** We do not store or log the text. Our server keeps only technical records:
  status codes, sizes, counts and timing.
- **A random identifier.** To limit misuse, each request carries a random identifier created when
  the app was installed. It is not linked to your name, your Apple Account or your device's own
  identifiers.
- **What OpenAI does with it.** OpenAI processes the text to produce the answer, under its own
  terms. OpenAI states that it does not use data sent through its API to train its models, and
  that it may keep API data for a limited period (up to 30 days) to monitor for abuse. See
  [OpenAI's privacy policy](https://openai.com/policies/privacy-policy/).

Do not put anything in a request that you would not want processed this way, such as other
people's names or details of a medical condition. The assistant writes everyday meal plans; it
does not give medical advice.

## Anonymous usage data

To help improve the app, DietFlow shares anonymous usage data with PostHog, an analytics service.
It is on by default; turn it off at any time in *Settings › Share Anonymous Usage Data*, and
nothing more is sent.

What is shared:

- which features are used (a plan was imported, the assistant was used, a reminder setting
  changed), with counts such as how many days and meals a plan has;
- where a limit was reached, and whether a purchase was started, completed or cancelled;
- that the app was opened, installed or updated, its version and its language.

What is never shared: the names of your meals or plans, your notes, anything you paste or type,
photos, or files.

The data is tied to a random number created on your iPhone. It is not linked to your name, your
Apple Account or your device's own identifiers, and it is not used for advertising or to follow
you across other apps or websites.

## Purchases

DietFlow Plus is bought through the App Store. Apple handles the payment; we do not receive your
name, your payment details or your Apple Account. The app asks the App Store on your iPhone
whether a purchase is active.

## Who else is involved

| Company | What for | What it receives |
|---|---|---|
| OpenAI | The assistant's AI | The text you give the assistant, after you agree |
| Cloudflare | Runs our server | The same text in transit, and your IP address, as any web request does |
| PostHog | Anonymous usage data | The events listed above, tied to a random number |
| Apple | Payments, and the on-device model | Purchases; nothing from the app's content |

We do not sell your data, and we do not share it with anyone else.

## How long things are kept

- On your iPhone: until you delete them or the app.
- Assistant text: not kept by us. OpenAI may keep it for the period it states, above.
- Anonymous usage data: held by PostHog for its standard retention period, then deleted.

## Your choices and rights

- Deleting a plan removes it from your iPhone. *Settings › Delete All Data* removes everything.
- Deleting the app removes its data, apart from a small counter of how much of the assistant's
  allowance was used, which is kept in your iPhone's Keychain so that reinstalling does not reset
  it. It holds numbers only.
- Turn off the assistant's sharing or the usage data at any time, in Settings.
- Depending on where you live (for example under the GDPR or Türkiye's KVKK), you may have the
  right to ask what data about you is held, to have it corrected or deleted, and to object to its
  use. Because nothing we hold is linked to your identity, we will usually need the random
  identifier from your app to find anything. Write to us at the address below.

## Children

DietFlow is not directed at children under 13, and we do not knowingly collect data from them.

## Changes

If this policy changes in a way that matters, the date at the top changes and the app's update
notes say so.

## Contact

Questions about this policy, or a request about your data: write to <mericorhayy@gmail.com>. See also the
[support page](support).

See also the [Terms of Use](terms).
