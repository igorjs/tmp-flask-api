#!/bin/bash

APP_DIR="/opt/web-scraper"

# Source the environment variables
if [ -f "$APP_DIR/.env" ]; then
  source "$APP_DIR/.env"
fi

# Run the scraper
echo "Running web scraper..."
"$APP_DIR/venv/bin/python" "$APP_DIR/app.py" scrape

echo "Done!"
