from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import pandas as pd
import numpy as np
from io import BytesIO
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from scipy.cluster.hierarchy import linkage, fcluster, dendrogram
# Avoid heavy sklearn dependency on the host by using a small local scaler
# from sklearn.preprocessing import StandardScaler

app = Flask(__name__)
CORS(app)

# Expected columns
EXPECTED_COLS = [
    'ID','Breed','Age','Weight_kg','Milk_Yield','Fertility_Score',
    'Rumination_Minutes_Per_Day','Ear_Temperature_C','Parasite_Load_Index',
    'Fecal_Egg_Count','Respiration_Rate_BPM','Forage_Quality_Index',
    'Vaccination_Up_To_Date','Movement_Score','Remaining_Months'
]

# Simple recommendation mapping based on cluster means
def recommend_for_cluster(summary):
    recs = []
    # high parasite
    if summary['Parasite_Load_Index'] > 3.5 or summary['Fecal_Egg_Count'] > 200:
        recs.append('Consider deworming and fecal testing')
    # low movement
    if summary['Movement_Score'] < 4:
        recs.append('Increase pasture rotation and monitor mobility')
    # low milk
    if summary['Milk_Yield'] < 15:
        recs.append('Review nutrition and milking protocol')
    # high temp
    if summary['Ear_Temperature_C'] > 39.0:
        recs.append('Inspect for fever/infection; check shelter and water')
    if not recs:
        recs.append('Normal indicators — continue routine management')
    return '; '.join(recs)

# Preprocessing: encode Breed and Vaccination_Up_To_Date
def preprocess(df):
    df = df.copy()
    # ensure all expected cols exist
    for c in EXPECTED_COLS:
        if c not in df.columns:
            df[c] = np.nan
    # simple encoding: breed -> category codes
    df['Breed'] = df['Breed'].astype('category').cat.codes
    df['Vaccination_Up_To_Date'] = df['Vaccination_Up_To_Date'].map({True:1, False:0, 'True':1,'False':0,'true':1,'false':0}).fillna(0)
    # numeric cols
    num_cols = [c for c in EXPECTED_COLS if c not in ['ID','Breed','Vaccination_Up_To_Date']]
    # Ensure numeric conversion
    for c in num_cols:
        df[c] = pd.to_numeric(df[c], errors='coerce')
    # Fill missing with column median
    medians = df[num_cols].median()
    df[num_cols] = df[num_cols].fillna(medians)
    # Basic standardization (mean 0, std 1). Avoid zero-std columns.
    means = df[num_cols].mean()
    stds = df[num_cols].std().replace(0, 1)
    df[num_cols] = (df[num_cols] - means) / stds
    # Return df and a small dict with scaling params (for possible future use)
    scaler = {'means': means.to_dict(), 'stds': stds.to_dict()}
    return df, scaler

@app.route('/cluster', methods=['POST'])
def cluster_endpoint():
    # Accept JSON or file
    if 'file' in request.files:
        file = request.files['file']
        df = pd.read_csv(file)
    else:
        data = request.get_json()
        if not data:
            return jsonify({'error':'No data provided'}), 400
        df = pd.DataFrame(data)
    # validate schema
    missing = [c for c in ['ID','Breed'] if c not in df.columns]
    if missing:
        return jsonify({'error':'Missing columns', 'missing': missing}), 400
    # keep original
    original = df.copy()
    proc_df, scaler = preprocess(df)
    # use numeric cols for clustering
    features = [c for c in proc_df.columns if c not in ['ID']]
    X = proc_df[features].values
    # hierarchical clustering
    Z = linkage(X, method='ward')
    # choose number of clusters heuristically; here 3
    k = int(request.args.get('k', 3))
    labels = fcluster(Z, k, criterion='maxclust')
    original['cluster'] = labels
    # compute summaries
    summaries = []
    for cluster_id in sorted(original['cluster'].unique()):
        members = original[original['cluster']==cluster_id]
        # compute means on raw numeric columns (best-effort)
        numeric = members.select_dtypes(include=[np.number])
        means = numeric.mean().to_dict()
        means['count'] = len(members)
        means['cluster_id'] = int(cluster_id)
        means['recommendation'] = recommend_for_cluster(means)
        summaries.append(means)
    # optional dendrogram image
    include_dendro = request.args.get('dendrogram', '0') in ['1','true','True']
    dendro_bytes = None
    if include_dendro:
        fig = plt.figure(figsize=(8,6))
        dendrogram(Z, no_labels=True)
        buf = BytesIO()
        plt.tight_layout()
        fig.savefig(buf, format='png')
        plt.close(fig)
        buf.seek(0)
        dendro_bytes = buf.read()
    # response
    resp = {
        'clusters': original[['ID','cluster']].to_dict(orient='records'),
        'summaries': summaries
    }
    if dendro_bytes:
        # return as multipart? for simplicity, return base64
        import base64
        resp['dendrogram_base64'] = base64.b64encode(dendro_bytes).decode('ascii')
    return jsonify(resp)

@app.route('/health')
def health():
    return jsonify({'status':'ok'})

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
