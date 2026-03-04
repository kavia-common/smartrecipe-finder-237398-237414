const express = require('express');
const path = require('path');
const fs = require('fs');

// Database clients
const { Pool } = require('pg');
const mysql = require('mysql2/promise');
const sqlite3 = require('sqlite3').verbose();
const { MongoClient } = require('mongodb');

const app = express();
app.use((req, res, next) => {
  // Set headers to allow embedding in iframes
  res.setHeader('X-Frame-Options', 'ALLOWALL');
  res.setHeader('Content-Security-Policy', "frame-ancestors *;");

  // CORS headers
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,PATCH,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type,Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(204);
  }
  next();
});
app.use(express.static(path.join(__dirname, 'public')));

// Load environment variables from .env files
function loadEnvFiles() {
  const envFiles = ['postgres', 'mysql', 'sqlite', 'mongodb'];
  const allEnvVars = {};
  
  envFiles.forEach(dbType => {
    const filePath = `${dbType}.env`;
    if (!fs.existsSync(filePath)) return;
    
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      let varsLoaded = 0;
      
      content.split('\n').forEach(line => {
        const trimmed = line.trim();
        if (trimmed && trimmed.startsWith('export ')) {
          const exportLine = trimmed.substring(7);
          const [key, ...valueParts] = exportLine.split('=');
          if (key && valueParts.length > 0) {
            let value = valueParts.join('=');
            if ((value.startsWith('"') && value.endsWith('"')) || 
                (value.startsWith("'") && value.endsWith("'"))) {
              value = value.slice(1, -1);
            }
            allEnvVars[key] = value;
            varsLoaded++;
          }
        }
      });
      
      console.log(`✓ ${filePath} loaded (${varsLoaded} variables)`);
    } catch (error) {
      console.log(`✗ Error loading ${filePath}:`, error.message);
    }
  });
  
  return { ...process.env, ...allEnvVars };
}

const env = loadEnvFiles();

// Database configuration builder
const dbConfigBuilders = {
  postgres: (env) => env.POSTGRES_URL ? {
    host: 'localhost',
    port: env.POSTGRES_PORT || 5432,
    user: env.POSTGRES_USER || 'postgres',
    password: env.POSTGRES_PASSWORD || '',
    database: env.POSTGRES_DB || 'postgres'
  } : null,
  
  mysql: (env) => env.MYSQL_URL ? {
    host: 'localhost',
    port: env.MYSQL_PORT || 3306,
    user: env.MYSQL_USER || 'root',
    password: env.MYSQL_PASSWORD || '',
    database: env.MYSQL_DB || 'mysql'
  } : null,
  
  sqlite: (env) => env.SQLITE_DB ? { path: env.SQLITE_DB } : null,
  
  mongodb: (env) => env.MONGODB_URL ? {
    url: env.MONGODB_URL,
    database: env.MONGODB_DB || 'test'
  } : null
};

// Build configurations
const configs = Object.entries(dbConfigBuilders).reduce((acc, [db, builder]) => {
  acc[db] = builder(env);
  return acc;
}, {});

// Base Database adapter
class DatabaseAdapter {
  constructor(type, config) {
    this.type = type;
    this.config = config;
  }
  
  async testConnection() {
    throw new Error('Not implemented');
  }
  
  async getTables() {
    throw new Error('Not implemented');
  }
  
  async getData(table, limit) {
    throw new Error('Not implemented');
  }
  
  // Helper for consistent table format
  formatTableResult(rows, columnName = 'table_name') {
    return rows.map(row => ({
      table_name: typeof row === 'object' ? (row[columnName] || Object.values(row)[0]) : row
    }));
  }
}

// SQL-based adapter base class
class SQLAdapter extends DatabaseAdapter {
  async execute(query) {
    throw new Error('Not implemented');
  }
  
  async testConnection() {
    await this.execute('SELECT 1');
  }
  
  getTableQuery() {
    throw new Error('Not implemented');
  }
  
  getDataQuery(table, limit) {
    throw new Error('Not implemented');
  }
  
  async getTables() {
    const rows = await this.execute(this.getTableQuery());
    return this.formatTableResult(rows);
  }
  
  async getData(table, limit) {
    return await this.execute(this.getDataQuery(table, limit));
  }
}

// PostgreSQL adapter
class PostgresAdapter extends SQLAdapter {
  async execute(query) {
    const pool = new Pool(this.config);
    try {
      const result = await pool.query(query);
      return result.rows;
    } finally {
      await pool.end();
    }
  }
  
  getTableQuery() {
    return "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'";
  }
  
  getDataQuery(table, limit) {
    return `SELECT * FROM "${table}" LIMIT ${limit}`;
  }
}

// MySQL adapter
class MySQLAdapter extends SQLAdapter {
  async execute(query) {
    const connection = await mysql.createConnection(this.config);
    try {
      const [rows] = await connection.execute(query);
      return rows;
    } finally {
      await connection.end();
    }
  }
  
  getTableQuery() {
    return 'SHOW TABLES';
  }
  
  getDataQuery(table, limit) {
    return `SELECT * FROM \`${table}\` LIMIT ${limit}`;
  }
}

// SQLite adapter
class SQLiteAdapter extends SQLAdapter {
  execute(query) {
    return new Promise((resolve, reject) => {
      const db = new sqlite3.Database(this.config.path);
      db.all(query, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
        db.close();
      });
    });
  }
  
  async testConnection() {
    if (!fs.existsSync(this.config.path)) {
      throw new Error('SQLite database file not found');
    }
  }
  
  getTableQuery() {
    return "SELECT name as table_name FROM sqlite_master WHERE type='table'";
  }
  
  getDataQuery(table, limit) {
    return `SELECT * FROM "${table}" LIMIT ${limit}`;
  }
}

// MongoDB adapter
class MongoDBAdapter extends DatabaseAdapter {
  async withClient(callback) {
    const client = new MongoClient(this.config.url);
    try {
      await client.connect();
      const db = client.db(this.config.database);
      return await callback(db);
    } finally {
      await client.close();
    }
  }
  
  async testConnection() {
    await this.withClient(() => {});
  }
  
  async getTables() {
    return await this.withClient(async (db) => {
      const collections = await db.listCollections().toArray();
      return this.formatTableResult(collections, 'name');
    });
  }
  
  async getData(table, limit) {
    return await this.withClient(async (db) => {
      return await db.collection(table).find({}).limit(limit).toArray();
    });
  }
}

// Adapter factory
const adapterClasses = {
  postgres: PostgresAdapter,
  mysql: MySQLAdapter,
  sqlite: SQLiteAdapter,
  mongodb: MongoDBAdapter
};

// Create database adapters
const adapters = Object.entries(configs).reduce((acc, [db, config]) => {
  acc[db] = config ? new adapterClasses[db](db, config) : null;
  return acc;
}, {});

// Test database connections
async function testConnections() {
  const available = [];
  
  for (const [name, adapter] of Object.entries(adapters)) {
    if (!adapter) {
      console.log(`- ${name}: not configured`);
      continue;
    }
    
    try {
      console.log(`Testing ${name} connection...`);
      await adapter.testConnection();
      available.push(name);
      console.log(`✓ ${name} connection successful`);
    } catch (error) {
      console.log(`✗ ${name} connection failed: ${error.message}`);
      if (name === 'mysql' && adapter.config) {
        console.log(`  MySQL config: ${JSON.stringify(adapter.config, null, 2)}`);
      }
    }
  }
  
  return available;
}

// Generic API handler
async function handleApiRequest(req, res, operation) {
  try {
    const adapter = adapters[req.params.db];
    if (!adapter) {
      throw new Error(`${req.params.db} not configured`);
    }
    
    const result = await operation(adapter);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
}

// API Routes
app.get('/api/databases', async (req, res) => {
  const available = await testConnections();
  res.json(available);
});

app.get('/api/:db/tables', (req, res) => 
  handleApiRequest(req, res, adapter => adapter.getTables())
);

app.get('/api/:db/tables/:table/data', (req, res) => 
  handleApiRequest(req, res, adapter => {
    const limit = parseInt(req.query.limit) || 50;
    return adapter.getData(req.params.table, limit);
  })
);

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Environment info
const envInfo = {
  PostgreSQL: 'POSTGRES_URL, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, POSTGRES_PORT',
  MySQL: 'MYSQL_URL, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB, MYSQL_PORT',
  SQLite: 'SQLITE_DB',
  MongoDB: 'MONGODB_URL, MONGODB_DB'
};

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Database viewer running on http://localhost:${PORT}`);
  console.log('\nEnvironment variables expected:');
  Object.entries(envInfo).forEach(([db, vars]) => {
    console.log(`${db}: ${vars}`);
  });
});
