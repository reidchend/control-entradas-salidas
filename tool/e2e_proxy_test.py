# Prueba end-to-end del camino nativo -> proxy -> PostgreSQL.
#
# Levanta `tool/server.py` contra una base real y lo consume con
# `HttpSqlSession`, la misma clase que usan las apps Windows y Android en
# modo proxy. Así se verifica el contrato completo: cabecera del token,
# forma del JSON y que el resultado vuelve en el formato que espera
# `SqlResult`.
#
# Uso: tool/venv/bin/python tool/e2e_proxy_test.py

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = 8791
TOKEN = "token-e2e-local"
DB = os.environ["E2E_DATABASE_URL"]

DART_TEST = r'''
import 'dart:io';

import 'package:control_entradas_salidas/core/data/http_sql_session.dart';
import 'package:control_entradas_salidas/core/data/sql_session.dart';

Future<void> main(List<String> args) async {
  final url = args[0];
  final token = args[1];
  var fallos = 0;

  void check(String nombre, bool ok, [String detalle = '']) {
    print('${ok ? 'PASA' : 'FALLA'}  $nombre${detalle.isEmpty ? '' : ' -> $detalle'}');
    if (!ok) fallos++;
  }

  // 1. SELECT
  final s = HttpSqlSession(baseUrl: '$url/proxy-sql', token: token);
  final r = await s.execute('SELECT 2 + 2 AS suma');
  check('SELECT numérico', r.rows.isNotEmpty && '${r.rows.first['suma']}' == '4',
      '${r.rows}');

  // 2. Transaccion con commit
  await s.runTx((tx) async {
    await tx.execute("CREATE TEMP TABLE t_e2e (id int)");
    await tx.execute('INSERT INTO t_e2e VALUES (7)');
    final dentro = await tx.execute('SELECT id FROM t_e2e');
    check('lectura dentro de la transaccion',
        dentro.rows.isNotEmpty && '${dentro.rows.first['id']}' == '7');
  });
  check('commit sin error', true);

  // 3. Transaccion que revienta por dentro: runTx tiene que hacer rollback y
  //    volver a lanzar, sin dejar la sesion colgada.
  try {
    await s.runTx((tx) async {
      await tx.execute("CREATE TEMP TABLE t_e2e2 (id int)");
      await tx.execute('INSERT INTO t_e2e2 VALUES (8)');
      throw StateError('fallo a proposito');
    });
    check('rollback automatico ante error', false, 'no relanzo');
  } on StateError catch (e) {
    check('rollback automatico ante error', e.message == 'fallo a proposito');
  }

  // 4. Error de SQL vuelve como excepción, no como crash
  try {
    await s.execute('SELECT * FROM tabla_que_no_existe_xyz');
    check('SQL inválido lanza error', false, 'no lanzó');
  } catch (e) {
    check('SQL inválido lanza error', true, e.toString().split('\n').first);
  }

  // 5. Token incorrecto rechazado
  final malo = HttpSqlSession(baseUrl: '$url/proxy-sql', token: 'incorrecto');
  try {
    await malo.execute('SELECT 1');
    check('token inválido rechazado', false, 'ejecutó igual');
  } catch (e) {
    check('token inválido rechazado', true);
  }

  // 6. Sin token rechazado
  final sinToken = HttpSqlSession(baseUrl: '$url/proxy-sql');
  try {
    await sinToken.execute('SELECT 1');
    check('sin token rechazado', false, 'ejecutó igual');
  } catch (_) {
    check('sin token rechazado', true);
  }

  exit(fallos == 0 ? 0 : 1);
}
'''


def post(path, body, token=None, expect=200):
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}{path}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    if token:
        req.add_header("X-Proxy-Token", token)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def main():
    env = dict(os.environ, DATABASE_URL=DB, PROXY_SQL_TOKEN=TOKEN)
    server = subprocess.Popen(
        [sys.executable, os.path.join(ROOT, "tool", "server.py"),
         str(PORT), "build/web"],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=ROOT,
    )
    try:
        # Espera a que el puerto responda.
        for _ in range(40):
            try:
                urllib.request.urlopen(
                    f"http://127.0.0.1:{PORT}/proxy-sql", data=b"{}",
                    timeout=2)
                break
            except urllib.error.HTTPError:
                break  # ya responde (401 o 400)
            except Exception:
                time.sleep(0.25)

        # El proxy debe estar cerrado sin token.
        status, body = post("/proxy-sql", {"action": "execute",
                                           "sql": "SELECT 1"})
        print(f"{'PASA' if status == 401 else 'FALLA'}  proxy cierra sin token "
              f"-> {status} {body.get('error', '')}")
        rc = 0 if status == 401 else 1

        # Y abrir con el token correcto.
        status, body = post("/proxy-sql",
                            {"action": "execute", "sql": "SELECT 1"}, TOKEN)
        ok = status == 200 and body.get("rows") is not None
        print(f"{'PASA' if ok else 'FALLA'}  proxy acepta token -> {status}")
        rc |= 0 if ok else 1

        # Ahora el lado Dart.
        test_file = os.path.join(ROOT, "tool", "e2e_proxy_client.dart")
        with open(test_file, "w") as fh:
            fh.write(DART_TEST)
        proc = subprocess.run(
            ["dart", "run", test_file,
             f"http://127.0.0.1:{PORT}", TOKEN],
            capture_output=True, text=True, cwd=ROOT,
        )
        print(proc.stdout)
        if proc.returncode != 0:
            print(proc.stderr[-3000:])
            rc = 1
        os.remove(test_file)
    finally:
        server.terminate()
        server.wait(timeout=10)

    print("TODO OK" if rc == 0 else "HUBO FALLOS")
    sys.exit(rc)


if __name__ == "__main__":
    main()
