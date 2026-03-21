# shellcheck shell=bash
# convert.sh — ENML ↔ markdown/text conversion

# Check if pandoc is available
xev_check_pandoc() {
  command -v pandoc >/dev/null 2>&1
}

# Convert ENML to markdown via pre-process → pandoc → post-process
# Reads from stdin, writes to stdout
xev_enml_to_markdown() {
  if ! xev_check_pandoc; then
    # Fallback to text mode
    xev_enml_to_text
    return
  fi

  sed 's/<?xml[^?]*?>//' | \
  sed 's/<!DOCTYPE[^>]*>//' | \
  sed 's/<en-note>//g; s/<\/en-note>//g' | \
  sed -E 's/<en-todo checked="true"\/>/- [x] /g' | \
  sed -E 's/<en-todo checked="false"\/>/- [ ] /g' | \
  sed -E 's/<en-media[^>]*type="([^"]*)"[^>]*\/>/\n[Attachment: \1]\n/g' | \
  sed 's/<en-crypt>[^<]*<\/en-crypt>/[Encrypted content]/g' | \
  perl -0pe 's/<div[^>]*display\s*:\s*none[^>]*>.*?<\/div>//gs' | \
  perl -0pe 's/<div[^>]*--en-calendarBlock[^>]*>.*?(?=<\/div>\s*<(?!div))/\n/gs' | \
  sed -E 's/<div[^>]*--en-richlink[^>]*>/<p>/g' | \
  sed 's/<div><br\/><\/div>/<p><\/p>/g' | \
  sed 's/<div[^>]*>/<p>/g' | \
  sed 's/<\/div>/<\/p>/g' | \
  sed -E 's/<span[^>]*>//g; s/<\/span>//g' | \
  pandoc -f html -t gfm --wrap=auto 2>/dev/null | \
  sed 's/\\\$/$/g' | \
  sed 's/\\\|/|/g' | \
  sed -E 's/\[([^]]*)\]\{\.underline\}/__\1__/g' | \
  sed 's/\\- \\\[x\\\]/- [x]/g; s/\\- \\\[ \\\]/- [ ]/g' | \
  sed 's/\\\[x\\\]/[x]/g; s/\\\[ \\\]/[ ]/g'
}

# Convert ENML to plain text (strip all tags)
# Note: When called from xev-cli, prefer using Make.com's pre-stripped Content field instead
xev_enml_to_text() {
  sed 's/<[^>]*>//g' | \
  sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&#39;/'"'"'/g' | \
  sed '/^[[:space:]]*$/d'
}

# Convert markdown to ENML-safe HTML wrapped in en-note envelope
# Reads from stdin, writes to stdout
xev_markdown_to_enml() {
  if ! xev_check_pandoc; then
    echo "Error: pandoc is required for creating/updating notes" >&2
    return 1
  fi

  local html
  html=$(pandoc -f markdown -t html 2>/dev/null)

  # Sanitize: strip elements not in ENML allowlist
  # MVP allowlist covers pandoc markdown→HTML output
  html=$(echo "$html" | sed -E '
    s/<div[^>]*>//g; s/<\/div>//g;
    s/<section[^>]*>//g; s/<\/section>//g;
    s/<span[^>]*>//g; s/<\/span>//g;
    s/<img[^>]*\/>//g;
    s/ class="[^"]*"//g;
    s/ id="[^"]*"//g;
  ')

  # Wrap in ENML envelope
  printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note>%s</en-note>' "$html"
}
