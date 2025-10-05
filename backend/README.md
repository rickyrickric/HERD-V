HERD-V Python backend

Flask app that accepts herd data (CSV or JSON) and runs hierarchical clustering (Ward's method).

Endpoints:
- POST /cluster?k=3&dendrogram=1 : accepts uploaded CSV in form-data `file` or JSON array in the request body. Returns cluster assignments, summaries, and optional dendrogram as base64.
- GET /health : health check

To run locally:
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
python app.py

