import json
import os
import boto3
import requests
from bs4 import BeautifulSoup
from flask import Flask, jsonify, request
from flask_lambda import FlaskLambda

# Initialize Flask app
app = FlaskLambda(__name__)

# Config
S3_BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', 'your-bucket-name')
S3_JSON_KEY = os.environ.get('S3_JSON_KEY', 'scraped_data.json')
TARGET_URL = os.environ.get('TARGET_URL', 'https://example.com/table-page')

# Initialize S3 client
s3_client = boto3.client('s3')

def scrape_and_save_data():
    """
    Scrape data from the target website and save to S3.
    Can be called both by the scheduled event and via API.
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
        
        # Save to S3
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=S3_JSON_KEY,
            Body=json.dumps(data),
            ContentType='application/json'
        )
        
        return {
            "success": True,
            "message": "Data scraped and saved to S3",
            "record_count": len(data)
        }
        
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }

# CloudWatch scheduled event handler (cronjob)
def scheduled_scraper(event, context):
    """
    Lambda handler for scheduled events from CloudWatch.
    """
    print("Scheduled scraper triggered")
    result = scrape_and_save_data()
    print(f"Scraping result: {json.dumps(result)}")
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
        
        # Get data from S3
        response = s3_client.get_object(
            Bucket=S3_BUCKET_NAME,
            Key=S3_JSON_KEY
        )
        
        data = json.loads(response['Body'].read().decode('utf-8'))
        
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
            "count": len(data)
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# For local testing
if __name__ == '__main__':
    app.run(debug=True)
