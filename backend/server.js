const express = require("express");
const cors = require("cors");
const mysql = require("mysql2/promise");

const app = express();
const PORT = process.env.PORT || 3001;

const {
  DB_HOST = "db",
  DB_USER = "root",
  DB_PASSWORD = "admin123",
  DB_NAME = "tienda_perritos",
  DB_PORT = 3306,
} = process.env;

app.use(cors());
app.use(express.json());

let pool;

async function waitForDb(retries = 15, delay = 2000) {
  for (let i = 0; i < retries; i++) {
    try {
      const testPool = mysql.createPool({
        host: DB_HOST,
        user: DB_USER,
        password: DB_PASSWORD,
        port: DB_PORT,
        waitForConnections: true,
        connectionLimit: 1,
      });
      await testPool.query("SELECT 1");
      await testPool.end();
      console.log(`Conexion a MySQL lista en ${DB_HOST}:${DB_PORT}`);
      return;
    } catch (err) {
      console.log(`Esperando MySQL (intento ${i + 1}/${retries})...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw new Error(`No se pudo conectar a MySQL despues de ${retries} intentos`);
}

async function initDb() {
  try {
    await waitForDb();
    pool = mysql.createPool({
      host: DB_HOST,
      user: DB_USER,
      password: DB_PASSWORD,
      database: DB_NAME,
      port: DB_PORT,
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0,
    });
    console.log("Pool de conexiones MySQL inicializado.");
  } catch (err) {
    console.error("Error al inicializar pool de MySQL:", err);
    process.exit(1);
  }
}

// Helper para manejar errores
function handleError(res, error, message = "Error interno del servidor") {
  console.error(error);
  res.status(500).json({ message });
}

// Obtener todos los productos
app.get("/api/productos", async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT id, nombre, descripcion, precio, stock FROM productos ORDER BY id DESC");
    res.json(rows);
  } catch (err) {
    handleError(res, err, "No se pudieron obtener los productos.");
  }
});

// Obtener un producto por ID
app.get("/api/productos/:id", async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await pool.query("SELECT id, nombre, descripcion, precio, stock FROM productos WHERE id = ?", [id]);
    if (rows.length === 0) {
      return res.status(404).json({ message: "Producto no encontrado." });
    }
    res.json(rows[0]);
  } catch (err) {
    handleError(res, err, "No se pudo obtener el producto.");
  }
});

// Crear un nuevo producto
app.post("/api/productos", async (req, res) => {
  const { nombre, descripcion, precio, stock } = req.body;

  if (!nombre || precio == null || stock == null) {
    return res.status(400).json({ message: "Nombre, precio y stock son obligatorios." });
  }

  try {
    const [result] = await pool.query(
      "INSERT INTO productos (nombre, descripcion, precio, stock) VALUES (?, ?, ?, ?)",
      [nombre, descripcion || null, precio, stock]
    );
    const nuevoId = result.insertId;
    const [rows] = await pool.query("SELECT id, nombre, descripcion, precio, stock FROM productos WHERE id = ?", [nuevoId]);
    res.status(201).json(rows[0]);
  } catch (err) {
    handleError(res, err, "No se pudo crear el Producto.");
  }
});

// Actualizar un producto
app.put("/api/productos/:id", async (req, res) => {
  const { id } = req.params;
  const { nombre, descripcion, precio, stock } = req.body;

  if (!nombre || precio == null || stock == null) {
    return res.status(400).json({ message: "Nombre, Precio y Stock son obligatorios." });
  }

  try {
    const [result] = await pool.query(
      "UPDATE productos SET nombre = ?, descripcion = ?, precio = ?, stock = ? WHERE id = ?",
      [nombre, descripcion || null, precio, stock, id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ message: "Producto no encontrado." });
    }

    const [rows] = await pool.query("SELECT id, nombre, descripcion, precio, stock FROM productos WHERE id = ?", [id]);
    res.json(rows[0]);
  } catch (err) {
    handleError(res, err, "No se pudo actualizar el Producto.");
  }
});

// Eliminar un producto
app.delete("/api/productos/:id", async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await pool.query("DELETE FROM productos WHERE id = ?", [id]);
    if (result.affectedRows === 0) {
      return res.status(404).json({ message: "Producto no encontrado." });
    }
    res.json({ message: "Producto eliminado correctamente." });
  } catch (err) {
    handleError(res, err, "No se pudo eliminar el Producto.");
  }
});

// Endpoint de salud
app.get("/api/health", (req, res) => {
  res.json({ status: "ok", message: "Backend de tienda de perritos en ejecución." });
});

// Iniciar servidor
app.listen(PORT, async () => {
  console.log(`Servidor backend escuchando en puerto ${PORT}`);
  await initDb();
});
