#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==========================================
# CONFIGURATION: Change your county code here
# ==========================================
COUNTY_CODE="37"

# Target URL dynamically updated with the county code
URL="https://public.cdpehs.com/KYEnvPBL/(S(5orzccy1md4zjqgkqkbxvhvf))/VW_PUBLIC_EST_INSP/ShowVW_PUBLIC_EST_INSPTable.aspx?COUNTY=${COUNTY_CODE}"
COOKIE_FILE="cookies.txt"
HTML_FILE="initial_page.html"
RESPONSE_FILE="response_data.txt"
OUTPUT_CSV="inspections_county_${COUNTY_CODE}.csv"

echo "Step 1: Visiting page to fetch cookies and initial HTML for County ${COUNTY_CODE}..."
curl -s -L -c "$COOKIE_FILE" "$URL" -o "$HTML_FILE"

echo "Step 2: Extracting __VIEWSTATE and __VIEWSTATEGENERATOR..."

# Helper function to URL-encode strings using Python
urlencode() {
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote_with_keep(''))" "$1" 2>/dev/null || \
    perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$1"
}

# Extract raw ViewState values from the HTML inputs
RAW_VIEWSTATE=$(grep -oP 'id="__VIEWSTATE" value="\K[^"]+' "$HTML_FILE" || true)
RAW_GENERATOR=$(grep -oP 'id="__VIEWSTATEGENERATOR" value="\K[^"]+' "$HTML_FILE" || true)

if [ -z "$RAW_VIEWSTATE" ]; then
    echo "Error: Could not retrieve __VIEWSTATE from the page. Check if the site is down or blocking requests."
    exit 1
fi

# URL encode the extracted payloads
ENCODED_VIEWSTATE=$(urlencode "$RAW_VIEWSTATE")
ENCODED_GENERATOR=$(urlencode "$RAW_GENERATOR")

echo "Successfully extracted and encoded ViewState!"

# Clean up initial HTML file
rm -f "$HTML_FILE"

echo "Step 3: Performing the POST request with the fresh payloads..."

curl "$URL" \
  -b "$COOKIE_FILE" \
  -c "$COOKIE_FILE" \
  --compressed \
  -s \
  -X POST \
  -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:152.0) Gecko/20100101 Firefox/152.0' \
  -H 'Accept: */*' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Accept-Encoding: gzip, deflate, br, zstd' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H 'X-MicrosoftAjax: Delta=true' \
  -H 'Cache-Control: no-cache' \
  -H 'Content-Type: application/x-www-form-urlencoded; charset=utf-8' \
  -H 'Origin: https://public.cdpehs.com' \
  -H 'Connection: keep-alive' \
  -H "Referer: ${URL}" \
  -H 'Sec-Fetch-Dest: empty' \
  -H 'Sec-Fetch-Mode: cors' \
  -H 'Sec-Fetch-Site: same-origin' \
  -H 'Priority: u=0' \
  -H 'TE: trailers' \
  --data-raw "ctl00%24scriptManager1=ctl00%24PageContent%24UpdatePanel1%7Cctl00%24PageContent%24VW_PUBLIC_EST_INSPPagination%24_PageSizeButton&ctl00_scriptManager1_HiddenField=%3B%3BAjaxControlToolkit%2C%20Version%3D4.1.7.607%2C%20Culture%3Dneutral%2C%20PublicKeyToken%3D28f01b0e84b6d53e%3Aen-US%3Afc974eef-02bb-4a84-98bd-02b839b496d1%3Af2c8e708%3Ade1feab2%3A720a52bf%3Af9cec9bc%3A589eaa30%3A698129cf%3A7a92f56c%3B&ctl00%24pageLeftCoordinate=&ctl00%24pageTopCoordinate=&isd_geo_location=%3Clocation%3E%0A%3Clatitude%3E0%3C%2Flatitude%3E%0A%3Clongitude%3E0%3C%2Flongitude%3E%0A%3Cunit%3Emeters%3C%2Funit%3E%0A%3Cerror%3ELOCATION_ERROR_DISABLED%3C%2Ferror%3E%0A%3C%2Flocation%3E%0A&ctl00%24PageContent%24PREMISE_NAMEFilter=&ctl00%24PageContent%24ZipCodeFilter=&ctl00%24PageContent%24INSP_SCOREFilter=&ctl00%24PageContent%24PREMISE_ADDRESS1Filter=&ctl00%24PageContent%24PREMISE_CITYFilter=&ctl00%24PageContent%24VW_PUBLIC_EST_INSPPagination%24_CurrentPage=1&ctl00%24PageContent%24VW_PUBLIC_EST_INSPPagination%24_PageSize=9999&ctl00%24PageContent%24VW_PUBLIC_EST_INSPTableControl_PostbackTracker=&hiddenInputToUpdateATBuffer_CommonToolkitScripts=1&__EVENTTARGET=ctl00%24PageContent%24VW_PUBLIC_EST_INSPPagination%24_PageSizeButton&__EVENTARGUMENT=&__VIEWSTATE=${ENCODED_VIEWSTATE}&__VIEWSTATEGENERATOR=${ENCODED_GENERATOR}&__ASYNCPOST=true&" \
  -o "$RESPONSE_FILE"

echo "Step 4: Parsing response and cleaning data into CSV..."

# Inline python parser block (using only standard libraries)
python3 - <<EOF
import re
import csv
from html.parser import HTMLParser

class ASPNetTableParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows = []
        self.current_row = []
        self.in_td = False
        self.current_td_data = []
        self.current_a_onmouseover = None

    def handle_starttag(self, tag, attrs):
        if tag == 'tr':
            self.current_row = []
        elif tag == 'td':
            self.in_td = True
            self.current_td_data = []
            self.current_a_onmouseover = None
        elif tag == 'a' and self.in_td:
            attrs_dict = dict(attrs)
            if 'onmouseover' in attrs_dict:
                self.current_a_onmouseover = attrs_dict['onmouseover']

    def handle_data(self, data):
        if self.in_td:
            self.current_td_data.append(data)

    def handle_endtag(self, tag):
        if tag == 'td':
            self.in_td = False
            text = "".join(self.current_td_data).strip()
            text = text.replace('\\xa0', '').replace('&nbsp;', '')
            self.current_row.append((text, self.current_a_onmouseover))
        elif tag == 'tr':
            if self.current_row:
                self.rows.append(self.current_row)

# Read raw server response
with open("$RESPONSE_FILE", "r", encoding="utf-8", errors="ignore") as f:
    raw_content = f.read()

# Feed raw response to parser
parser = ASPNetTableParser()
parser.feed(raw_content)

banned_words = {
    "first page", "previous page", "next page", "last page", 
    "page size", "items", "page", "refresh", "reset filters", 
    "pdf report", "microsoft word report", "export to excel", "export to csv"
}

output_data = []

for row in parser.rows:
    if len(row) >= 5:
        name = row[0][0].strip()
        addr = row[1][0].strip()
        city = row[2][0].strip()
        
        # 1. Skip completely blank names
        if not name:
            continue
            
        # 2. Drop the text search filter boxes
        name_lower = name.lower()
        if "(contains)" in name_lower or "(equals)" in name_lower or "contains" in name_lower:
            continue
        if "(contains)" in city.lower() or "(contains)" in addr.lower():
            continue
            
        # 3. Drop navigational elements
        if name_lower in banned_words:
            continue
            
        last_date = row[3][0].strip()
        last_score = row[4][0].strip()
        
        follow_date = row[5][0].strip() if len(row) > 5 else ""
        follow_score = row[6][0].strip() if len(row) > 6 else ""

        # Extract hidden Javascript tooltips for violation items
        notes = []
        for cell_text, onmouseover in row:
            if onmouseover:
                match = re.search(r"detailRolloverPopup\s*\([^,]+,\s*[^,]+,\s*'([^']+)'", onmouseover)
                if match:
                    ul_content = match.group(1)
                    li_items = re.findall(r"<li>(.*?)</li>", ul_content, re.IGNORECASE)
                    notes.extend([item.strip() for item in li_items if item.strip()])
        
        clean_notes = "; ".join(notes)
        output_data.append([name, addr, city, last_date, last_score, follow_date, follow_score, clean_notes])

# 4. Target the trailing repeat anomaly exclusively at the end of the file.
while len(output_data) > 1 and output_data[-1] == output_data[-2]:
    output_data.pop()

# Write final clean dataset to CSV
headers = ["Premise Name", "Premise Address 1", "Premise City", "Last Insp Date", "Last Insp Score", "Follow Insp Date", "Follow Insp Score", "Notes"]
with open("$OUTPUT_CSV", "w", newline="", encoding="utf-8") as csv_file:
    writer = csv.writer(csv_file, quoting=csv.QUOTE_ALL)
    writer.writerow(headers)
    writer.writerows(output_data)

EOF

echo "Success! The data was extracted, cleaned, and saved to: $OUTPUT_CSV"

# Cleanup temporary scratchpads
rm -f "$RESPONSE_FILE" "$COOKIE_FILE"
