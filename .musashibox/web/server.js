const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 6340;

const TODO_DIR = path.join(__dirname, '..', 'todo');
const ARCHIVE_DIR = path.join(TODO_DIR, 'archives');
const WORKLOG_DIR = path.join(__dirname, '..', 'worklog');

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Parse todo filename into structured data
// Format: {YYYYmmdd}_{HHMM}_{TODO_TITLE}_{TODO_TYPE}_{TODO_STATUS}.md
function parseTodoFilename(filename) {
  const base = filename.replace(/\.md$/, '');
  const parts = base.split('_');
  if (parts.length < 5) return null;

  const date = parts[0];
  const time = parts[1];
  const status = parts[parts.length - 1];
  const todoType = parts[parts.length - 2];
  const title = parts.slice(2, parts.length - 2).join('_');

  return {
    filename,
    date,
    time,
    title,
    todoType,
    status,
    datetime: `${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6, 8)} ${time.slice(0, 2)}:${time.slice(2, 4)}`,
  };
}

// Build new filename from parsed todo with updated fields
function buildTodoFilename(parsed) {
  return `${parsed.date}_${parsed.time}_${parsed.title}_${parsed.todoType}_${parsed.status}.md`;
}

// Find worklogs matching a todo by date, time, title, and todoType
function findWorklogs(todo) {
  try {
    const files = fs.readdirSync(WORKLOG_DIR);
    const prefix = `${todo.date}_${todo.time}_${todo.title}_${todo.todoType}`;
    return files.filter(f => f.endsWith('.md') && f.replace(/\.md$/, '') === prefix);
  } catch {
    return [];
  }
}

function listTodosFromDir(dir) {
  try {
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.md'));
    return files
      .map(parseTodoFilename)
      .filter(Boolean)
      .map(todo => {
        todo.worklogs = findWorklogs(todo);
        return todo;
      })
      .sort((a, b) => {
        const da = a.date + a.time;
        const db = b.date + b.time;
        return db.localeCompare(da);
      });
  } catch (err) {
    return [];
  }
}

// POST /api/todos - Create a new todo
app.post('/api/todos', (req, res) => {
  const { title, todoType, status, content } = req.body;
  const validTypes = ['THINK', 'PLAN', 'DEVELOP'];
  const validStatuses = ['pending', 'inprogress', 'done', 'completed'];

  if (!title || !validTypes.includes(todoType)) {
    return res.status(400).json({ error: 'title and valid todoType (THINK/PLAN/DEVELOP) are required' });
  }

  const st = validStatuses.includes(status) ? status : 'pending';
  const now = new Date();
  const date = now.getFullYear().toString()
    + (now.getMonth() + 1).toString().padStart(2, '0')
    + now.getDate().toString().padStart(2, '0');
  const time = now.getHours().toString().padStart(2, '0')
    + now.getMinutes().toString().padStart(2, '0');

  const safeTitle = title.replace(/[^a-zA-Z0-9_]/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '');
  const filename = `${date}_${time}_${safeTitle}_${todoType}_${st}.md`;
  const filepath = path.join(TODO_DIR, filename);

  try {
    fs.writeFileSync(filepath, content || '', 'utf-8');
    res.json({ success: true, filename });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/todos - List all todos
app.get('/api/todos', (req, res) => {
  try {
    const todos = listTodosFromDir(TODO_DIR);
    res.json(todos);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/archives - List archived todos
app.get('/api/archives', (req, res) => {
  try {
    const todos = listTodosFromDir(ARCHIVE_DIR);
    res.json(todos);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/archives/:filename - Get archived todo content
app.get('/api/archives/:filename', (req, res) => {
  const filepath = path.join(ARCHIVE_DIR, req.params.filename);
  if (!filepath.startsWith(ARCHIVE_DIR)) return res.status(400).json({ error: 'Invalid path' });
  try {
    const content = fs.readFileSync(filepath, 'utf-8');
    const parsed = parseTodoFilename(req.params.filename);
    res.json({ ...parsed, content });
  } catch (err) {
    res.status(404).json({ error: 'Not found' });
  }
});

// POST /api/todos/:filename/archive - Move todo to archives
app.post('/api/todos/:filename/archive', (req, res) => {
  const oldPath = path.join(TODO_DIR, req.params.filename);
  if (!oldPath.startsWith(TODO_DIR)) return res.status(400).json({ error: 'Invalid path' });
  try {
    if (!fs.existsSync(ARCHIVE_DIR)) fs.mkdirSync(ARCHIVE_DIR, { recursive: true });
    const newPath = path.join(ARCHIVE_DIR, req.params.filename);
    fs.renameSync(oldPath, newPath);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/archives/:filename/restore - Restore archived todo
app.post('/api/archives/:filename/restore', (req, res) => {
  const oldPath = path.join(ARCHIVE_DIR, req.params.filename);
  if (!oldPath.startsWith(ARCHIVE_DIR)) return res.status(400).json({ error: 'Invalid path' });
  try {
    const newPath = path.join(TODO_DIR, req.params.filename);
    fs.renameSync(oldPath, newPath);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/todos/:filename - Get todo content
app.get('/api/todos/:filename', (req, res) => {
  const filepath = path.join(TODO_DIR, req.params.filename);
  if (!filepath.startsWith(TODO_DIR)) return res.status(400).json({ error: 'Invalid path' });
  try {
    const content = fs.readFileSync(filepath, 'utf-8');
    const parsed = parseTodoFilename(req.params.filename);
    res.json({ ...parsed, content });
  } catch (err) {
    res.status(404).json({ error: 'Not found' });
  }
});

// PUT /api/todos/:filename - Update todo content
app.put('/api/todos/:filename', (req, res) => {
  const filepath = path.join(TODO_DIR, req.params.filename);
  if (!filepath.startsWith(TODO_DIR)) return res.status(400).json({ error: 'Invalid path' });
  try {
    const { content } = req.body;
    if (typeof content !== 'string') return res.status(400).json({ error: 'content is required' });
    fs.writeFileSync(filepath, content, 'utf-8');
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/todos/:filename/status - Change todo status (renames file)
app.patch('/api/todos/:filename/status', (req, res) => {
  const { status } = req.body;
  const validStatuses = ['pending', 'inprogress', 'done', 'completed'];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({ error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
  }

  const oldPath = path.join(TODO_DIR, req.params.filename);
  if (!oldPath.startsWith(TODO_DIR)) return res.status(400).json({ error: 'Invalid path' });

  const parsed = parseTodoFilename(req.params.filename);
  if (!parsed) return res.status(400).json({ error: 'Invalid filename format' });

  parsed.status = status;
  const newFilename = buildTodoFilename(parsed);
  const newPath = path.join(TODO_DIR, newFilename);

  try {
    fs.renameSync(oldPath, newPath);
    res.json({ success: true, filename: newFilename });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/worklogs/:filename - Get worklog content
app.get('/api/worklogs/:filename', (req, res) => {
  const filepath = path.join(WORKLOG_DIR, req.params.filename);
  if (!filepath.startsWith(WORKLOG_DIR)) return res.status(400).json({ error: 'Invalid path' });
  try {
    const content = fs.readFileSync(filepath, 'utf-8');
    res.json({ filename: req.params.filename, content });
  } catch (err) {
    res.status(404).json({ error: 'Not found' });
  }
});

app.listen(PORT, () => {
  console.log(`MusashiBox Web running on http://localhost:${PORT}`);
});
