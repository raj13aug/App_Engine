from flask import Flask
app = Flask(__name__)

@app.route('/')
def root():
    return 'Hello World!'

# local-only
if __name__ == '__main__':
    import os
    app.run(debug=True, threaded=True, host='0.0.0.0',
            port=int(os.environ.get('PORT', 8080)))