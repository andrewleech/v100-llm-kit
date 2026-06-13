# todo-api

A tiny Flask REST API for managing an in-memory todo list. Single file, `app.py`.

## Endpoints
- `GET /todos` — return the list of todos as JSON.
- `POST /todos` — append the JSON body as a new todo, returns it with 201.

## Run
`python app.py` — serves on port 5000. Depends on Flask (`requirements.txt`).

## Notes
Storage is a plain in-memory list, so todos reset on restart. No database, no auth.
