# tiny flask todo api
from flask import Flask, jsonify, request
app = Flask(__name__)
todos = []

@app.route("/todos", methods=["GET"])
def list_todos():
    return jsonify(todos)

@app.route("/todos", methods=["POST"])
def add_todo():
    todos.append(request.json)
    return jsonify(request.json), 201

if __name__ == "__main__":
    app.run(port=5000)
