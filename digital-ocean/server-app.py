import json
import os
import requests
from bs4 import BeautifulSoup
from flask import Flask, jsonify, request
from datetime import datetime

# Initialize Flask app
app = Flask(__name__)

# Config
DATA_DIR = os.environ.get('DATA_DIR', './data')
JSON_FILE = os.environ.get('JSON_FILE', 'scraped_data.json')
TARGET_URL = os.environ.get('TARGET_URL', 'https://example.com/table-page')

# Ensure data directory exists
os.makedirs(DATA_DIR, exist_ok=True)

def get_json_path():
    """Returns the full path to the JSON data file"""
    return os.path.join(DATA_DIR, JSON_FILE)

def scrape_and_save_data():
    """
    Scrape data from the target website and save to disk.
    Can be called both by the cronjob and via API.
    """
    try:
        # Fetch the webpage
        response = requests.get(TARGET_URL)
        response.raise_for_status()
        
        # Parse HTML
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # Find the table - modify selector based on actual HTML structure
        table = soup.select_one('table')  # Adjust selector as needed
        
        if not table:
            return {
                "success": False,
                "error": "Table not found"
            }
            
        # Extract data from table
        data = []
        rows = table.select('tr')
        
        # Get headers
        headers = [th.text.strip() for th in rows[0].select('th')]
        
        # Get data rows
        for row in rows[1:]:
            cells = row.select('td')
            if cells:
                row_data = {headers[i]: cell.text.strip() 
                           for i, cell in enumerate(cells) if i < len(headers)}
                data.append(row_data)
        
        # Add timestamp for logging purposes
        timestamp = datetime.now().isoformat()
        result = {
            "data": data,
            "metadata": {
                "scraped_at": timestamp,
                "record_count": len(data)
            }
        }
        
        # Save to file
        with open(get_json_path(), 'w') as f:
            json.dump(result, f, indent=2)
        
        return {
            "success": True,
            "message": "Data scraped and saved",
            "record_count": len(data),
            "timestamp": timestamp
        }
        
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }

# CLI handler for cronjob
def cli_scraper():
    """Function to be called from command line for cron jobs"""
    result = scrape_and_save_data()
    print(json.dumps(result))
    return result

# HTTP endpoint for manual triggering (optional)
@app.route('/scrape', methods=['GET'])
def scrape_data_endpoint():
    result = scrape_and_save_data()
    if not result.get("success", False):
        return jsonify(result), 500
    return jsonify(result)

@app.route('/data', methods=['POST'])
def get_filtered_data():
    try:
        # Get filter parameters
        filters = request.json if request.is_json else {}
        
        # Read data from disk
        if not os.path.exists(get_json_path()):
            return jsonify({
                "error": "No data available. Run the scraper first."
            }), 404
            
        with open(get_json_path(), 'r') as f:
            file_content = json.load(f)
            data = file_content.get("data", [])
            metadata = file_content.get("metadata", {})
        
        # Apply filters
        if filters:
            filtered_data = []
            for item in data:
                match = True
                for key, value in filters.items():
                    if key in item and item[key] != value:
                        match = False
                        break
                if match:
                    filtered_data.append(item)
            data = filtered_data
            
        return jsonify({
            "data": data,
            "count": len(data),
            "metadata": metadata
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# For command line execution (used by cron)
if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'scrape':
        cli_scraper()
    else:
        # For development server
        app.run(host='0.0.0.0', port=5000, debug=False)
