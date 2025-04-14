#!/bin/bash

# Configuration
APP_NAME="web-scraper"
APP_DIR="/opt/$APP_NAME"
USER="$USER"
DATA_DIR="/var/lib/$APP_NAME/data"
LOG_DIR="/var/log/$APP_NAME"
ENV_FILE="$APP_DIR/.env"
TARGET_URL="https://example.com/table-page"
PORT=5000
CRON_SCHEDULE="0 0 * * *"  # Daily at midnight

# Ensure script exits on any error
set -e

echo "Starting setup process for $APP_NAME..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Create application user if doesn't exist
if ! id "$USER" &>/dev/null; then
  echo "Creating user $USER..."
  useradd -m -s /bin/bash $USER
fi

# Create directories
echo "Creating directories..."
mkdir -p $APP_DIR
mkdir -p $DATA_DIR
mkdir -p $LOG_DIR

# Install dependencies
echo "Installing system dependencies..."
apt-get update
apt-get install -y python3 python3-pip python3-venv

# Copy application files
echo "Copying application files..."
cp app.py $APP_DIR/
cp requirements.txt $APP_DIR/

# Create virtual environment
echo "Setting up Python environment..."
cd $APP_DIR
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
deactivate

# Create .env file
echo "Creating environment configuration..."
cat > $ENV_FILE << EOL
DATA_DIR=$DATA_DIR
JSON_FILE=scraped_data.json
TARGET_URL=$TARGET_URL
FLASK_APP=app.py
FLASK_ENV=production
EOL

# Set up the systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/$APP_NAME.service << EOL
[Unit]
Description=$APP_NAME Web Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/venv/bin"
EnvironmentFile=$ENV_FILE
ExecStart=$APP_DIR/venv/bin/gunicorn --workers=2 --bind=0.0.0.0:$PORT app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

# Set up cron job for scraping
echo "Setting up cron job..."
CRON_COMMAND="$APP_DIR/venv/bin/python $APP_DIR/app.py scrape >> $LOG_DIR/scrape.log 2>&1"
CRON_ENTRY="$CRON_SCHEDULE $USER $CRON_COMMAND"

# Add to crontab
echo "$CRON_ENTRY" > /etc/cron.d/$APP_NAME
chmod 0644 /etc/cron.d/$APP_NAME

# Fix permissions
echo "Setting permissions..."
chown -R $USER:$USER $APP_DIR
chown -R $USER:$USER $DATA_DIR
chown -R $USER:$USER $LOG_DIR
chmod 755 $APP_DIR/app.py

# Start the service
echo "Starting service..."
systemctl daemon-reload
systemctl enable $APP_NAME.service
systemctl start $APP_NAME.service
systemctl status $APP_NAME.service

echo "Setup completed successfully!"
echo "Web service running at http://localhost:$PORT"
echo "Data is stored in $DATA_DIR"
echo "Scraping job runs at $CRON_SCHEDULE"
