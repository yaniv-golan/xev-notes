# Make.com Setup Guide

This guide walks you through setting up the 6 Make.com scenarios that connect xev-cli to your Evernote account. Allow ~15 minutes.

## Prerequisites

- **Make.com account** on Core plan or above (API/webhook features require a paid plan)
- **Evernote account** with notes you want to access
- **xev-cli** installed (the `xev-cli/bin/xev-cli` script in this repo)

## Overview

You'll import 6 scenario blueprints into Make.com. Each scenario is a simple pipeline:

```
Webhook trigger → Evernote action → Webhook response
```

The scenarios:

| Scenario | What it does |
|----------|-------------|
| xev-search | Search notes by query |
| xev-get | Get a single note by ID |
| xev-notebooks | List all notebooks |
| xev-create | Create a new note |
| xev-update | Update an existing note |
| xev-append | Append content to a note |

---

## Step 1: Connect Evernote to Make.com

1. Log into Make.com
2. Go to **Connections** (left sidebar)
3. Click **Add connection** → search for **Evernote**
4. Follow the OAuth flow to authorize Make.com with your Evernote account
5. Name the connection (e.g., "My Evernote")

## Step 2: Import Blueprints

For each of the 6 blueprint files in `make/blueprints/`:

1. In Make.com, click **Create a new scenario**
2. Click the **"..."** menu (top right) → **Import Blueprint**
3. Paste the contents of the blueprint JSON file (e.g., `make/blueprints/xev-get.json`)
4. Click **Save**

Repeat for all 6 files:
- `xev-search.json`
- `xev-get.json`
- `xev-notebooks.json`
- `xev-create.json`
- `xev-update.json`
- `xev-append.json`

## Step 3: Configure Each Scenario

After importing, each scenario needs 3 things configured: the Evernote connection, the webhook, and the scheduling. Go through each scenario:

### 3a. Connect Evernote

1. Click the **Evernote module** (the green circle)
2. In the **Connection** dropdown, select your Evernote connection from Step 1
3. Click **Save**

### 3b. Set Up the Webhook

1. Click the **Webhooks module** (the red circle, module 1)
2. Click **Add** next to the Webhook dropdown
3. Name it (e.g., "xev-get")
4. Click **Save** — Make.com generates a webhook URL
5. **Copy the webhook URL** — you'll need it later

### 3c. Set Scheduling to "Immediately"

This is critical — without this, webhooks queue data instead of responding synchronously.

1. Click **Options** (top right of the scenario page) → **Scheduling**
2. Set it to **"Immediately as data arrives"**
3. Save

### 3d. Determine Webhook Data Structure

Each webhook needs to learn what data it receives:

1. Click the Webhooks module → click **"Redetermine data structure"**
2. Make.com will show "Waiting for data..."
3. Open a terminal and send the sample payload (see table below)
4. Make.com should show "Successfully determined"
5. Click **Save**

**Sample payloads** (run these from your terminal while Make.com is listening):

```bash
# xev-search
curl -X POST -H "Content-Type: application/json" \
  -d '{"query":"test","limit":3}' \
  "YOUR_SEARCH_WEBHOOK_URL"

# xev-get
curl -X POST -H "Content-Type: application/json" \
  -d '{"note_id":"test-id"}' \
  "YOUR_GET_WEBHOOK_URL"

# xev-notebooks
curl -X POST -H "Content-Type: application/json" \
  -d '{}' \
  "YOUR_NOTEBOOKS_WEBHOOK_URL"

# xev-create
curl -X POST -H "Content-Type: application/json" \
  -d '{"title":"test","notebook_id":"test","content":"test","escape_html":false}' \
  "YOUR_CREATE_WEBHOOK_URL"

# xev-update
curl -X POST -H "Content-Type: application/json" \
  -d '{"note_id":"test","title":"test","content_enml":"test"}' \
  "YOUR_UPDATE_WEBHOOK_URL"

# xev-append
curl -X POST -H "Content-Type: application/json" \
  -d '{"note_id":"test","content_enml":"test"}' \
  "YOUR_APPEND_WEBHOOK_URL"
```

## Step 4: Scenario-Specific Configuration

### xev-search and xev-notebooks

These scenarios use an **Array Aggregator** between Evernote and the Webhook Response. After importing:

1. Click the **Array Aggregator** module
2. Set **Source Module** to **"Evernote - Search for notes"**
3. Under **Aggregated fields**, click the dropdown and check **"Select All"**
4. Click **Save**

For **xev-notebooks** specifically:
- Click the Evernote module
- Set **Search query** to `*`
- Set **Maximum number of returned notes** to `20` (higher values cause timeouts)

### xev-search

- Click the Evernote module
- Set **Search query** to `{{1.query}}`
- Set **Maximum number of returned notes** to `{{1.limit}}`

### xev-get

- Click the Evernote module
- Set **Select a note** to "Enter ID manually"
- Set **Note ID** to `{{1.note_id}}`

### xev-create

- Click the Evernote module
- **Notebook**: turn on the **Map** toggle, then enter `{{1.notebook_id}}`
- **Title**: `{{1.title}}`
- **Content**: `{{1.content}}`
- Scroll down → **Escape HTML characters**: **No**

### xev-update

- Click the Evernote module
- Set **Select a note** to "Enter ID manually"
- **Note ID**: `{{1.note_id}}`
- **Title**: `{{1.title}}`
- **Content**: `{{1.content_enml}}`
- **Escape HTML characters**: **No**
- **Update a reminder**: **Update** (keeps existing reminder unchanged)

### xev-append

- Click the Evernote module
- Set **Select a note** to "Enter ID manually"
- **Note ID**: `{{1.note_id}}`
- **Content**: `{{1.content_enml}}`
- **Escape HTML characters**: **No**

## Step 5: Set Webhook Response Bodies

Each scenario's **Webhook Response** module needs its body configured.

### xev-get

1. Click Webhook Response module
2. Click in the **Body** field
3. Open the picker (click in the field) → click **"Evernote — Get a note [bundle]"** pill
4. Save

To see the bundle in the picker, you may need to do a **Run Once** first (see Step 6).

### xev-search and xev-notebooks

1. Click Webhook Response module
2. Set Body to the **"Flow Control — Array aggregator [bundle]"** pill from the picker
3. Save

### xev-create

1. Click Webhook Response module
2. Set Body to the **"Evernote — Create a note [bundle]"** pill from the picker
3. If the pill isn't available, do a Run Once first (Step 6), then set it

### xev-update and xev-append

These Evernote modules don't return output data. Set the Body to:

**xev-update**: `{"id": "{{1.note_id}}", "title": "{{1.title}}"}`

**xev-append**: `{"id": "{{1.note_id}}"}`

## Step 6: Test with Run Once

For scenarios where the picker doesn't show module outputs (Step 5), use **Run Once**:

1. Click **"Run once"** at the bottom of the scenario editor
2. Send the sample payload from Step 3d (use a real note ID for xev-get)
3. Check that all modules show green checkmarks
4. Now go back and set the Webhook Response body (the picker will show the output fields)
5. Save

## Step 7: Activate Scenarios

1. For each scenario, toggle the **Active** switch ON (top right of the scenario page)
2. If prompted about unprocessed data, click **"Delete old data"**

## Step 8: Configure xev-cli

Run the configuration wizard:

```bash
./xev-cli/bin/xev-cli config setup
```

It will prompt for:
- **Make.com zone** (e.g., `eu2.make.com` — check your Make.com URL)
- **Webhook API key** (optional — press Enter to skip)
- **6 webhook URLs** — paste each URL you copied in Step 3b

## Step 9: Verify

```bash
# Check config
./xev-cli/bin/xev-cli config check

# Test search
./xev-cli/bin/xev-cli search "test" --limit 3 --output human

# Test notebooks
./xev-cli/bin/xev-cli notebooks --output human

# Test get (use a note ID from search results)
./xev-cli/bin/xev-cli get <note-id> --format markdown
```

---

## Troubleshooting

### "Accepted" response / TIMEOUT error

The scenario is queuing data instead of processing immediately. Fix the scheduling:
- Open the scenario → **Options** (top right) → **Scheduling** → set to **"Immediately as data arrives"**
- Deactivate and reactivate the scenario

### "Scenario failed to complete" / HTTP 500

Check the scenario's **History** tab in Make.com for the actual error:
- **RATE_LIMIT_REACHED**: Wait the specified number of seconds before retrying
- **ENML_VALIDATION**: The content contains HTML elements or attributes that Evernote doesn't allow
- **BundleValidationError**: A required field is missing in the Evernote module configuration

### Array Aggregator "Source node is not set"

Click the Array Aggregator module → set Source Module to the Evernote module.

### Webhook Response returns just a number (e.g., "2")

Don't type `{{2}}` manually in the body field — Make.com resolves it to the module number. Instead, use the picker to click the module's output bundle pill.

### Empty objects in search results `[{},{},{}]`

The Array Aggregator isn't configured to pass through fields. Click it → under **Aggregated fields** → check **"Select All"**.

### Notebooks timeout

Reduce the maximum number of returned notes to 20 or lower in the Evernote Search module.
