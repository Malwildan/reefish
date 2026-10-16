// Local-only server for checking the compiled Flutter web artifact.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../build/web');
const mime = { '.html':'text/html', '.js':'text/javascript', '.json':'application/json',
  '.wasm':'application/wasm', '.svg':'image/svg+xml', '.png':'image/png',
  '.woff2':'font/woff2', '.ttf':'font/ttf', '.css':'text/css' };
http.createServer((request, response) => {
  let file;
  try { file = path.resolve(root, '.' + decodeURIComponent(new URL(request.url, 'http://localhost').pathname)); }
  catch { response.writeHead(400).end(); return; }
  if (file !== root && !file.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
  if (file === root) file = path.join(root, 'index.html');
  fs.stat(file, (error, stat) => {
    if (error || !stat.isFile()) { response.writeHead(404).end(); return; }
    response.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-store' });
    fs.createReadStream(file).pipe(response);
  });
}).listen(4195, '127.0.0.1', () => console.log('Built preview: http://127.0.0.1:4195'));
