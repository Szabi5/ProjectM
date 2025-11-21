# scripts/api_server.py
from flask import Flask, request, jsonify
import json
import sys
import os

# --- Import Financial Engine ---
try:
    from amortization_engine import process_request
except ImportError as e:
    print("="*50)
    print("FATAL ERROR: Could not import 'amortization_engine.py'.")
    print(f"Details: {e}")
    print("\nHave you installed all dependencies? Try running:")
    print("pip install pandas")
    print("="*50)
    sys.exit(1)
except Exception as e:
    print(f"An unknown error occurred during import: {e}")
    sys.exit(1)


# --- Flask Application Setup ---
app = Flask(__name__)
HOST = '0.0.0.0' 
PORT = 5000

@app.route('/calculate', methods=['POST'])
def calculate():
    """
    Handles all mortgage calculation requests from the Flutter app.
    """
    if not request.is_json:
        return jsonify({"error": "Invalid Content-Type. Must be application/json."}), 400

    try:
        data = request.json
        script = data.get('script', '')
        
        #
        # --- THIS IS THE FIX ---
        # We now get 'data' as a dictionary directly, NOT a JSON string.
        #
        data_dict = data.get('data', {}) 

        # --- DEBUGGING LINES ---
        print("="*40)
        print(f"SCRIPT RECEIVED: {script}")
        print(f"DATA DICT RECEIVED: {data_dict}")
        print("="*40)
        # --- END OF DEBUGGING LINES ---

        # We pass the DICTIONARY directly to process_request
        response_data = process_request(script, data_dict) 
        
        response_dict = json.loads(response_data)
        
        return jsonify(response_dict) 

    except Exception as e:
        print(f"Server calculation error: {e}")
        return jsonify({
            "error": f"Python Server Calculation Error: {str(e)}",
        }), 500

#
# The 'if __name__ == "__main__":' block has been removed
# as Gunicorn (in the Dockerfile) will run the 'app' variable directly.
#