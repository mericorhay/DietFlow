# DietFlow — App Store Connect brief

This is everything needed to set up DietFlow in App Store Connect and write its store pages.
It is written to be handed to an assistant: the facts are here, the fields are listed in the
order App Store Connect asks for them, and anything that is a decision for the developer is
marked **DECIDE**.

Rules for whoever fills this in:

- Use only what is in this brief. If a field needs a fact that is not here, leave it and list it
  under "Open questions" at the end of your answer. Do not invent features, numbers or claims.
- Write every piece of store text in three languages: English (U.S.), Turkish and Spanish (Spain).
  They are separate texts written for each market, not translations of one another.
- Respect each field's character limit and report the count beside each text.
- Never ask for, type or store passwords, verification codes or API keys. Signing in to App Store
  Connect is done by the developer.

---

## 1. What the app is

**DietFlow** is an iPhone app that puts a meal plan on the Home Screen. You set the plan once; a
widget then shows what to eat now and what comes next, moving through the day by itself.

The problem it solves: people who follow a plan — from a dietitian, from a programme, or one they
wrote — have it as a PDF, a photo or a long message, and have to dig it out before every meal. With
DietFlow they never open anything: the widget on the Home Screen already shows the next meal and
its time.

The developer built it for their own use, following a keto plan.

### What it does

**The widget (the point of the app)**

- Small, medium and large Home Screen widgets, and two Lock Screen widgets (rectangular and inline).
- Shows the meal that is on now or coming next, its time, and the meal after it. The large widget
  shows the whole day.
- Moves on by itself. When a meal's time comes it stays in front for an hour (adjustable from 30
  minutes to 2 hours), then the next meal takes its place. After the day's last meal it shows
  tomorrow's first. Nothing has to be tapped and the app does not have to be opened.
- A countdown in the hour before a meal ("in 15 min").
- Colour and tone are the person's choice: ten colours and four backgrounds (automatic, soft,
  bold, dark). Lock Screen widgets use iOS's own colours.
- An optional Done button on the medium and large widgets, off by default.

**Getting a plan in**

- Type it in: a plan is a run of days (1 to 366), each with its meals; it can repeat (the same
  week every week) or run once.
- Paste text: a list copied from a message, a note, ChatGPT or Claude. Read on the device.
- A photo or a PDF of a list: the text is recognised on the device.
- A file: `.mealplan` or JSON.
- Whatever the source, the plan is shown for review before it is saved.
- Plans can be shared as `.mealplan` files.

**The assistant (DietFlow Plus)**

- *Organize Any List*: paste a diet list exactly as it is — out of order, with typos, mixed with
  greetings and prices — and the assistant sorts it into days and meals. It copies; it does not
  invent meals.
- *Write Me a Plan*: say how you want to eat (for example "keto, about 1800 kcal, no fish, quick
  breakfasts"), choose 1 to 30 days and 2 to 6 meals a day, and it writes the plan.
- It writes everyday meal plans. It is not medical advice, and the app says so before a plan is
  asked for.

**Day to day**

- A Today screen with the day's meals in order.
- Optional reminders at meal times (at the time, or 10, 30 or 60 minutes before), with Done and
  Skip buttons on the notification.
- Siri and Shortcuts: "What's my next meal", "Mark my meal done", "Add a meal", "Import Plan".
- Each meal can carry a time, a type (breakfast, snack, lunch, dinner, other), a name, details, a
  portion, calories, protein, carbohydrates, fat and notes. Calories can be shown in kcal or kJ.
- English, Turkish and Spanish.

### What it is not — do not claim any of this

- It is not a calorie counter or food tracker. It has no food database and no barcode scanner.
- It does not promise weight loss or any health result. No "lose X kg", no before/after.
- It gives no medical or nutritional advice and does not replace a dietitian or a doctor.
- It has no account, no sign-in and no sync between devices. There is no Android version, no
  iPad version, no Apple Watch app and no Mac app.
- It has no recipes and no shopping list.
- Do not say "no data is collected" or "nothing leaves your phone". See section 6.

---

## 2. Identity

| | |
|---|---|
| Bundle ID | `com.orhay.dietflow` |
| Widget extension bundle ID | `com.orhay.dietflow.widget` |
| App Group | `group.com.orhay.dietflow` |
| Apple Developer Team ID | `XYB3NLV654` |
| SKU | `dietflow-ios` (**DECIDE**: any unique string) |
| Platform | iPhone only. Not iPad, not Mac, not Vision. |
| Minimum iOS | 26.0 |
| Version | 1.0.0 |
| Primary language | English (U.S.) |
| Localizations | English (U.S.), Turkish, Spanish (Spain) |
| Primary category | Health & Fitness |
| Secondary category | Food & Drink |
| Price | Free, with in-app purchases |
| Availability | All countries and regions (**DECIDE**) |
| Copyright | `2026 <developer's legal name>` (**DECIDE**) |
| Source code | https://github.com/mericorhay/DietFlow (public) |

### Names per language (30 characters at most)

| Language | Name | Characters |
|---|---|---|
| English (U.S.) | `Meal Planner Widget: DietFlow` | 29 |
| Turkish | `Diyet Listesi Widget: DietFlow` | 30 |
| Spanish | `Plan de Comidas: DietFlow` | 25 |

The Turkish name starts with "Diyet Listesi" on purpose: in the Turkish App Store that exact
phrase is what people type, and the apps that rank first for it are weak. Keep it.

---

## 3. Store text to write

Write each of these in all three languages. Limits are Apple's.

| Field | Limit | Notes |
|---|---|---|
| Subtitle | 30 | Do not repeat words already in the name. |
| Promotional text | 170 | Can be changed without a new version. |
| Description | 4,000 | See the structure below. |
| Keywords | 100 | Comma-separated, no spaces after commas. Do not repeat words from the name or subtitle. Singular or plural, not both. No competitor names. |
| What's New | 4,000 | For 1.0: one or two plain sentences. |

### Description structure

1. Two or three sentences on the problem and the answer: the plan is always on the Home Screen.
2. The widget: sizes, that it moves on by itself, colours.
3. Getting a plan in: type, paste, photo, PDF, file.
4. The assistant, clearly marked as part of DietFlow Plus.
5. Reminders, Siri and Shortcuts.
6. What is free and what is in DietFlow Plus (section 4).
7. The subscription terms and the two links, which Apple requires in the description of an app
   with auto-renewable subscriptions. Use this wording, translated:

   > DietFlow Plus is available as a monthly subscription with a 7-day free trial, a yearly
   > subscription, or a one-time lifetime purchase. Payment is charged to your Apple Account at
   > confirmation of purchase. Subscriptions renew automatically unless cancelled at least 24
   > hours before the end of the current period. Manage or cancel in Settings › Apple Account ›
   > Subscriptions.
   >
   > Privacy Policy: https://mericorhay.github.io/DietFlow/privacy
   > Terms of Use (EULA): https://mericorhay.github.io/DietFlow/terms

Tone: plain, concrete, second person. No exclamation marks, no emoji, no "revolutionary", no
"AI-powered" as a headline. Say what the thing does.

### What people search for (from the developer's own keyword research)

- **Turkey**: "diyet listesi" and "diyet programı" are searched and are won by small apps on title
  match alone. Generic words — "kalori sayacı", "diyet takibi" — are held by large apps (fatsecret,
  Yazio, Lifie); do not spend keyword space on them. Useful: `diyet programı`, `öğün`, `yemek planı`,
  `keto`, `ketojenik`, `diyetisyen`, `öğün hatırlatıcı`, `beslenme`.
- **United States**: "meal planner" and "diet plan" are held by very large apps. The opening is
  "meal reminder" and "meal schedule": the leader there has not been updated in a long time.
  Useful: `meal reminder`, `meal schedule`, `diet plan`, `keto`, `meal prep`, `eating schedule`,
  `dietitian`, `meal tracker`.
- Nobody searches "meal plan widget". The widget belongs in the name and the screenshots, not in
  the keyword field.
- **Spain / Latin America**: no research was done. Use the Spanish equivalents and say so in your
  open questions.

---

## 4. DietFlow Plus — in-app purchases to create

Create one subscription group and three products. Product IDs are fixed in the app's code and
must match exactly.

**Subscription group**: reference name `DietFlow Plus`. Both subscriptions go in it at the same
level (they are the same service for different lengths of time).

| | Monthly | Yearly | Lifetime |
|---|---|---|---|
| Type | Auto-renewable subscription | Auto-renewable subscription | Non-consumable |
| Product ID | `com.orhay.dietflow.plus.monthly` | `com.orhay.dietflow.plus.yearly` | `com.orhay.dietflow.plus.lifetime` |
| Reference name | DietFlow Plus Monthly | DietFlow Plus Yearly | DietFlow Plus Lifetime |
| Duration | 1 month | 1 year | — |
| Price (U.S.) | $3.99 | $24.99 (**DECIDE**: the developer said "25 dollars"; $24.99 or $25.00) | $34.99 |
| Introductory offer | Free trial, 7 days, new subscribers, all territories | None | — |
| Other territories | Apple's automatic equivalents (**DECIDE**: a lower manual price for Turkey) | same | same |
| Family Sharing | **DECIDE** | **DECIDE** | **DECIDE** |

For each product write, in all three languages, a **display name** and a **description** within
the limits App Store Connect shows beside the fields. Suggested English:

| Product | Display name | Description |
|---|---|---|
| Monthly | DietFlow Plus Monthly | The plan assistant and unlimited plans |
| Yearly | DietFlow Plus Yearly | The plan assistant and unlimited plans |
| Lifetime | DietFlow Plus Lifetime | Pay once: the assistant and unlimited plans |

Each product also needs a **review screenshot** (the Plus screen from the app; the developer
supplies it) and **review notes**. Review notes for all three:

> DietFlow Plus unlocks two things: the plan assistant (Settings › Import Plan › "Organize Any
> List" and "Write Me a Plan") beyond the two free requests a month, and keeping more than one plan. The Plus screen is
> shown once on first launch and can be opened from Settings › Get DietFlow Plus.

### What is free and what is paid

| | Free | DietFlow Plus |
|---|---|---|
| Plans kept at the same time | 1 | Any number |
| Assistant requests | 2 a calendar month | 60 a billing month |
| Every widget, every colour and tone | Yes | Yes |
| Typing, pasting, photo, PDF and file import | Yes | Yes |
| Reminders, Siri and Shortcuts | Yes | Yes |

A request that fails is not counted. On Plus the allowance starts again on the person's own
billing day, not on the first of the month.

---

## 5. Links

| Field | Value |
|---|---|
| Privacy Policy URL | https://mericorhay.github.io/DietFlow/privacy |
| Terms of Use (EULA) | https://mericorhay.github.io/DietFlow/terms |
| Support URL | https://mericorhay.github.io/DietFlow/support |
| Marketing URL | https://mericorhay.github.io/DietFlow/ (optional) |
| License agreement | Keep Apple's standard EULA selected in App Store Connect. The Terms of Use page builds on it and adds the subscription and assistant terms; link it in the description, as above. |

All four pages are live, published from the repository's `docs/` folder by GitHub Pages. The same
three links are inside the app: on the DietFlow Plus screen, and under Settings › About.

The support page's contact is the repository's public issue tracker. **DECIDE**: add a support
email address to `docs/support.md`, `docs/privacy.md` and `docs/terms.md` if one should be given;
Apple expects a way to reach the developer, and a privacy request should not have to be public.

---

## 6. App Privacy (the "nutrition label")

**Data used to track you**: none. The app does not track, has no advertising and does not use the
advertising identifier.

**Data collected**, all of it *not linked to the user's identity* and *not used for tracking*:

| Data type (App Store Connect's name) | Why | Purpose to select |
|---|---|---|
| Usage Data › Product Interaction | Anonymous usage events: which features are used, where a limit is reached | Analytics |
| Purchases › Purchase History | Whether a DietFlow Plus purchase was started, completed or cancelled, as an anonymous event | Analytics |
| Identifiers › Device ID | A random identifier created on the phone, used by the analytics service and to rate-limit the assistant. Not the device's real identifier, not linked to an Apple Account | Analytics, App Functionality |
| User Content › Other User Content | The text a person hands to the assistant (a diet list, or what they want to eat). Sent to the developer's server and from there to OpenAI to produce the plan, after the person agrees in the app; not stored by the developer | App Functionality |

**DECIDE**: a diet list can be read as health information. The cautious answer is to also declare
*Health & Fitness › Health* with the purpose App Functionality, not linked, not tracking. Raise
this with the developer rather than choosing silently.

Facts behind the answers, for any follow-up question the form asks:

- Meal plans, what is marked done, reminders and settings are stored on the phone only.
- Analytics goes to PostHog. It is on by default and can be turned off in the app (Settings ›
  Share Anonymous Usage Data). There is no session replay and no screen or tap recording. Events
  never contain meal names, plan names, notes or pasted text.
- The assistant's text goes to the developer's Cloudflare Worker and from there to an AI model
  provider. The Worker does not store or log it.
- Purchases go through Apple; the developer receives no name or payment details.
- There is no account, so there is no account deletion flow. Settings › Delete All Data removes
  everything from the phone.

---

## 7. Age rating, compliance and the rest

**Age rating questionnaire**: answer every content question "None". The expected result is the
lowest rating. Facts for the questions that are not about content:

- No user-to-user messaging, chat or social features. No user-generated content shown to others.
- No unrestricted web access. No gambling, contests or loot boxes.
- It has an AI assistant, with one job: turning a person's own text into a meal plan. It is not an
  open-ended chatbot and it does not answer questions.
- Its subject is meal planning, which is health and wellness. It does not give medical or
  treatment information and says so in the app. If the form asks about medical or wellness
  content, answer truthfully from these facts and list the question in your open questions.
- Not made for kids.

**Export compliance**: the app uses only standard HTTPS. `ITSAppUsesNonExemptEncryption` is set to
`NO` in the build, so no question should appear; if one does, the answer is that it uses no
non-exempt encryption.

**Content rights**: it contains no third-party content.

**Advertising identifier**: not used.

**Sign-in required**: no. No demo account is needed.

**Digital Services Act (EU)**: **DECIDE**. To be available in the EU the developer must declare
trader status in App Store Connect. Selling a subscription makes the developer a trader, and a
trader's address, phone number and email are shown on the product page. Only the developer can enter this.

**Agreements, tax and banking**: the Paid Applications agreement must be active or the in-app
purchases will not load. The developer already sells other apps under this account, so it should
be; check that its status is Active.

---

## 7a. The AI, said plainly

Apple's guideline 5.1.2(i) asks an app to say clearly when personal data is shared with a third
party's AI and to get explicit permission first. DietFlow does both, and the store pages should
say the same thing the app does:

- **Which AI**: the assistant uses **OpenAI's GPT models**, through OpenAI's API. Name OpenAI in
  the description wherever the assistant is described, in the notes for App Review, and in the
  App Privacy answers. Do not write "our AI" or "AI service" without the name.
- **Permission**: the first time the assistant is used, the app shows an alert, "Send this to
  OpenAI?", saying the text goes through our server to OpenAI and is not stored by DietFlow.
  Nothing is sent before the person taps Allow. It can be withdrawn in Settings › Privacy › Send
  Assistant Text to OpenAI.
- **On the device**: where the iPhone has Apple Intelligence, pasted and scanned plans are read
  by Apple's on-device model. Nothing leaves the phone for that, so it needs no permission, but
  the Privacy screen and the privacy policy mention it.
- **Not medical advice**: the assistant's screen, the Terms of Use and the privacy policy all say
  so, and every plan is shown for review before it is saved (guideline 1.4.1).

## 8. Notes for App Review

Put this in *App Review Information › Notes*, in English:

> DietFlow puts a meal plan on the Home Screen. No account or sign-in is needed.
>
> First launch: the DietFlow Plus screen is shown once as an introduction. It can be closed with
> the X or "Continue with the Free Version"; everything except the limits below then works free.
>
> To see the app working: tap Create Plan, add a few meals with times around the current time,
> then add the widget (long-press the Home Screen › Edit › Add Widget › DietFlow). The widget shows
> the meal that is on now or next and moves on by itself; nothing needs tapping.
>
> DietFlow Plus (monthly with a 7-day free trial, yearly, or lifetime) adds the plan assistant
> beyond two free requests a month and keeping more than one plan. The assistant is in Import
> Plan (Settings › Import Plan, or the menu on the Plan tab): "Organize Any List" and "Write Me
> a Plan". It needs a network connection: the
> text is sent to our server and from there to OpenAI (GPT models, via OpenAI's API) to produce the plan, after the person agrees to an in-app alert that names OpenAI, which is shown for review
> before it is saved. It writes everyday meal plans and states that it is not medical advice.
>
> Anonymous usage data is shared by default and can be turned off in Settings › Share Anonymous
> Usage Data. The app does not track and shows no advertising.
>
> Restore Purchases is on the Plus screen and in Settings.

Contact name, phone and email for App Review: **DECIDE** (the developer's).

---

## 9. Screenshots

The developer captures these from a TestFlight build; an assistant cannot make them.

- Required: iPhone 6.9-inch (1320 × 2868 or 1290 × 2796 pixels, portrait), 3 to 10 images, in each
  of the three languages. No iPad set, because the app is iPhone only.
- Suggested order, with a short caption above each in the language of the listing:
  1. A Home Screen with the medium widget showing the next meal. Caption: your plan, always in
     front of you.
  2. The large widget with the whole day.
  3. The Widgets tab with the colour swatches and a coloured widget. Caption: your colours.
  4. Import: paste, photo, PDF. Caption: any list you already have.
  5. The assistant turning a messy list into days and meals. Caption marked "DietFlow Plus".
  6. "Write Me a Plan" with a 30-day plan in review. Caption marked "DietFlow Plus".
  7. The Today screen.
  8. The Lock Screen widget.
- Captions follow the same rules as the description: no health claims, no promises.
- The same Plus-screen image is used as the review screenshot for the three in-app purchases.

---

## 10. Order of work in App Store Connect

1. **Apps › +** New App: iOS, the English name, primary language English (U.S.), the bundle ID,
   the SKU, Full Access.
2. **App Information**: categories, content rights, age rating, the Turkish and Spanish
   localizations with their names and subtitles.
3. **Pricing and Availability**: Free; territories.
4. **App Privacy**: the privacy policy URL, then the data types from section 6.
5. **Subscriptions**: the group, the two subscriptions, prices, the 7-day free trial on monthly,
   localizations, review screenshot and notes.
6. **In-App Purchases**: the lifetime non-consumable, price, localizations, review screenshot and
   notes.
7. **Version 1.0.0**: promotional text, description, keywords, support URL, screenshots, What's
   New, App Review notes and contact, in all three languages.
8. Attach the in-app purchases to the version (first submission: they are reviewed with the app).
9. Select the build once one has been uploaded, then submit.

---

## 11. Not done yet — outside App Store Connect

These block a real submission and are the developer's to do. Do not attempt them.

| What | State |
|---|---|
| Signing: App IDs, App Group, two App Store provisioning profiles, repository secrets | Not done |
| A TestFlight build | None uploaded yet |
| The assistant's server (Cloudflare Worker) deployed, with its secrets | Not deployed. Without it the build has no assistant, and the store text must not promise one |
| The PostHog project key added to the build | Not added. Without it nothing is shared, and the privacy answers about analytics should wait |
| GitHub Pages turned on, so the privacy policy URL works | On: privacy, terms and support pages are live |
| Purchases tested in the sandbox | Not tested |

**The store pages must describe the build that is submitted.** If the first build goes out
without the assistant, remove the assistant from the description, the screenshots, the
in-app purchase descriptions and the privacy answers, and DietFlow Plus is then only "more than
one plan".

---

## 12. What to hand back

1. Every text from sections 3 and 4, in three languages, each with its character count.
2. The answers for sections 6 and 7 as a checklist in the order the forms ask.
3. A list of every **DECIDE** item with what you assumed.
4. Open questions: anything a form asked that this brief does not answer.
