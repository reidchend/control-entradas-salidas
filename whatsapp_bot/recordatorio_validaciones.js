/**
 * Recordatorio de compras sin validar.
 *
 * Antes vivía en la app Flutter: eran timers que solo corrían con la app
 * abierta, así que un aviso podía perderse si nadie tenía la app abierta a
 * la hora del envío. Ahora lo hace el bot, que es el proceso que está
 * siempre encendido en la PC servidor (y el único que puede mandar por
 * WhatsApp de todas formas).
 *
 * Dos disparadores:
 *   1. Tanda nueva: al aparecer una entrada nueva se espera 30 min por si
 *      llegan más compras de la misma tanda y se avisa una sola vez con
 *      todo lo pendiente.
 *   2. Cierre del día: desde las 19:00, una vez por día, mientras queden
 *      pendientes.
 *
 * El switch de Configuración > Sistema (`recordatorio_validaciones`) manda:
 * si está apagado no se envía nada. Las marcas se guardan en `pos_settings`
 * con las mismas claves que usaba la app, así que un equipo con una versión
 * vieja abierta no duplica el mensaje.
 */

const fs = require('fs');
const path = require('path');

const K_ENABLED = 'recordatorio_validaciones';
const K_ULTIMO_TS = 'recordatorio_validaciones_ultimo_ts';
const K_FIJO_FECHA = 'recordatorio_validaciones_fijo_fecha';
const K_PLANTILLA = 'recordatorio_validaciones_plantilla';
const K_FORMATO_ITEM = 'recordatorio_validaciones_formato_item';
const K_NOTA_TANDA = 'recordatorio_validaciones_nota_tanda';
const K_NOTA_FIJA = 'recordatorio_validaciones_nota_fija';
const K_NOTA_MANUAL = 'recordatorio_validaciones_nota_manual';

// Textos por defecto: los mismos que tenía el mensaje fijo antes de que se
// pudiera editar desde el panel. Si una clave no existe en pos_settings se
// usa el default; si existe vacía se respeta el vacío (ej. sin nota).
const PLANTILLA_DEFECTO =
    '⏰ *HAY COMPRAS SIN VALIDAR* ({cantidad})\n\n' +
    'Esperan validación:\n{detalle}\n\n' +
    '{nota}\n\n' +
    '_Lycoris bot_';
const FORMATO_ITEM_DEFECTO = '• {producto}: {cantidad} — {motivo}';
const NOTA_TANDA_DEFECTO = 'Nueva compra registrada hace 30 min.';
const NOTA_FIJA_DEFECTO = 'Recordatorio del cierre del día (19:00).';
const NOTA_MANUAL_DEFECTO = 'Recordatorio manual desde el panel.';

/** Reemplaza `{clave}` por su valor. Deja intactos los placeholders
 *  desconocidos para que un error de tipeo se note en el mensaje. */
function reemplazar(texto, valores) {
    let salida = texto;
    for (const [clave, valor] of Object.entries(valores)) {
        salida = salida.split(`{${clave}}`).join(valor == null ? '' : valor);
    }
    return salida;
}

function ahoraLocal() {
    const d = new Date();
    const dos = (n) => String(n).padStart(2, '0');
    return {
        fecha: `${d.getFullYear()}-${dos(d.getMonth() + 1)}-${dos(d.getDate())}`,
        hora: `${dos(d.getHours())}:${dos(d.getMinutes())}`,
    };
}

const INTERVALO_POLL_MS = 2 * 60 * 1000;
const DEBOUNCE_MS = 30 * 60 * 1000;
const REINTENTO_MS = 10 * 60 * 1000;
const GUARD_DUPLICADOS_MS = 25 * 60 * 1000;
const HORA_AVISO_FIJO = 19;

/** Lee KEY=VALUE de un .env sin dependencias externas. */
function leerEnv(ruta) {
    const valores = {};
    try {
        const contenido = fs.readFileSync(ruta, 'utf8');
        for (const linea of contenido.split(/\r?\n/)) {
            const limpia = linea.trim();
            if (!limpia || limpia.startsWith('#') || !limpia.includes('=')) {
                continue;
            }
            const i = limpia.indexOf('=');
            const clave = limpia.slice(0, i).trim();
            const valor = limpia
                .slice(i + 1)
                .trim()
                .replace(/^['"]|['"]$/g, '');
            if (clave) valores[clave] = valor;
        }
    } catch (_) {
        // El archivo no existe: se usa solo el entorno.
    }
    return valores;
}

/** DATABASE_URL del entorno o de los .env locales (mismo criterio que tool/server.py). */
function resolverDatabaseUrl() {
    const candidatos = [
        process.env.DATABASE_URL_UNPOOLED,
        process.env.DATABASE_URL,
    ];
    for (const url of candidatos) {
        if (url) return url;
    }
    const archivos = [
        path.join(__dirname, '.env'),
        path.join(__dirname, '..', '.env.local'),
    ];
    for (const archivo of archivos) {
        const env = leerEnv(archivo);
        const url = env.DATABASE_URL_UNPOOLED || env.DATABASE_URL;
        if (url) return url;
    }
    return null;
}

function fechaLocal(ahora) {
    const p = (v) => String(v).padStart(2, '0');
    return `${ahora.getFullYear()}-${p(ahora.getMonth() + 1)}-${p(ahora.getDate())}`;
}

class RecordatorioValidaciones {
    constructor(bot, pool) {
        this.bot = bot;
        this.pool = pool;
        this.pollTimer = null;
        this.debounceTimer = null;
        this.reintentoTimer = null;
        this.maxIdVisto = null;
        this.enviando = false;
    }

    iniciar() {
        this.detener();
        this.pollTimer = setInterval(() => this.poll(), INTERVALO_POLL_MS);
        this.poll();
    }

    detener() {
        if (this.pollTimer) clearInterval(this.pollTimer);
        if (this.debounceTimer) clearTimeout(this.debounceTimer);
        if (this.reintentoTimer) clearTimeout(this.reintentoTimer);
        this.pollTimer = null;
        this.debounceTimer = null;
        this.reintentoTimer = null;
    }

    async poll() {
        try {
            const habilitado = await this.getSetting(K_ENABLED);
            if (['0', 'false', 'off'].includes((habilitado || '').toLowerCase())) {
                if (this.debounceTimer) clearTimeout(this.debounceTimer);
                if (this.reintentoTimer) clearTimeout(this.reintentoTimer);
                this.debounceTimer = null;
                this.reintentoTimer = null;
                return;
            }

            const stats = await this.pool.query(
                "SELECT COUNT(*)::int AS n, COALESCE(MAX(id), 0)::int AS max_id " +
                "FROM movimientos WHERE tipo = 'entrada' AND factura_id IS NULL"
            );
            if (stats.rows.length === 0) return;
            const n = stats.rows[0].n || 0;
            const maxId = stats.rows[0].max_id || 0;

            if (this.maxIdVisto === null) {
                // Primer poll tras arrancar el bot: se anota el estado actual
                // para no avisar por compras que ya estaban pendientes antes
                // de que el bot arrancara. El aviso fijo de las 19:00 las cubre.
                this.maxIdVisto = maxId;
                return;
            }

            const ahora = new Date();
            const hoy = fechaLocal(ahora);
            if (n > 0 && ahora.getHours() >= HORA_AVISO_FIJO &&
                (await this.getSetting(K_FIJO_FECHA)) !== hoy) {
                const ultimo = Date.parse(await this.getSetting(K_ULTIMO_TS) || '');
                const avisoReciente = !Number.isNaN(ultimo) &&
                    (Date.now() - ultimo) < GUARD_DUPLICADOS_MS;
                if (avisoReciente) {
                    // Otra tanda (o una app vieja) acaba de avisar de lo mismo.
                    await this.setSetting(K_FIJO_FECHA, hoy);
                } else if (await this.enviar({ esFijo: true })) {
                    await this.setSetting(K_FIJO_FECHA, hoy);
                }
            }

            if (maxId > this.maxIdVisto && !this.debounceTimer) {
                this.debounceTimer = setTimeout(() => {
                    this.debounceTimer = null;
                    this.enviarTanda();
                }, DEBOUNCE_MS);
            }
            // Se anota aunque haya debounce en curso: las entradas que lleguen
            // durante la espera entran al mensaje (se arma al enviar).
            this.maxIdVisto = maxId;
        } catch (error) {
            console.error('[recordatorio] poll error:', error.message);
        }
    }

    async enviarTanda() {
        if (await this.enviar({ esFijo: false }) === 'retry') {
            if (!this.reintentoTimer) {
                this.reintentoTimer = setTimeout(() => {
                    this.reintentoTimer = null;
                    this.enviarTanda();
                }, REINTENTO_MS);
            }
        }
    }

    /**
     * Devuelve 'sent' | 'empty' | 'duplicate' | 'retry'.
     * 'retry' = hay pendientes pero no se pudo enviar (bot desconectado,
     * error de red, etc.); no se marca nada para volver a intentar.
     */
    async enviar({ esFijo }) {
        if (this.enviando) return 'retry';
        this.enviando = true;
        try {
            if (!(await this.estaHabilitado())) return 'empty';

            const pendientes = await this.entradasPendientes();
            if (pendientes.length === 0) return 'empty';

            if (!esFijo) {
                const ultimo = Date.parse(await this.getSetting(K_ULTIMO_TS) || '');
                if (!Number.isNaN(ultimo) &&
                    (Date.now() - ultimo) < GUARD_DUPLICADOS_MS) {
                    return 'duplicate';
                }
            }

            if (!this.bot.isConnected()) {
                console.log('[recordatorio] WhatsApp no conectado; se reintentará');
                return 'retry';
            }

            await this.bot.sendToGroup(
                await this.armarMensaje(pendientes, esFijo ? 'fijo' : 'tanda')
            );
            await this.setSetting(K_ULTIMO_TS, new Date().toISOString());
            console.log(`[recordatorio] avisado (${pendientes.length} pendientes, ` +
                `fijo=${esFijo})`);
            return 'sent';
        } catch (error) {
            console.error('[recordatorio] envío error:', error.message);
            return 'retry';
        } finally {
            this.enviando = false;
        }
    }

    /**
     * Envío manual desde el panel: manda ahora lo que esté pendiente, sin
     * mirar el switch ni las marcas de duplicado (es una acción explícita).
     * No actualiza `ultimo_ts`, así el flujo automático sigue igual.
     */
    async enviarAhora() {
        if (this.enviando) {
            throw new Error('Ya hay un envío en curso; probá en unos segundos.');
        }
        this.enviando = true;
        try {
            const pendientes = await this.entradasPendientes();
            if (pendientes.length === 0) return { enviadas: 0 };
            if (!this.bot.isConnected()) {
                throw new Error('WhatsApp no conectado');
            }
            await this.bot.sendToGroup(
                await this.armarMensaje(pendientes, 'manual')
            );
            return { enviadas: pendientes.length };
        } finally {
            this.enviando = false;
        }
    }

    async entradasPendientes() {
        const { rows } = await this.pool.query(
            'SELECT m.id, m.cantidad, m.peso_total, m.motivo_no_validacion, ' +
            'm.almacen, p.nombre, p.unidad_medida, p.es_pesable ' +
            'FROM movimientos m ' +
            'LEFT JOIN productos p ON p.id = m.producto_id ' +
            "WHERE m.tipo = 'entrada' AND m.factura_id IS NULL " +
            'ORDER BY m.fecha_movimiento DESC'
        );
        return rows.map((r) => ({
            nombre: r.nombre || '',
            motivo: (r.motivo_no_validacion || '').trim(),
            almacen: r.almacen || '',
            cantidadTexto: this.cantidadTexto(r),
        }));
    }

    cantidadTexto(row) {
        const cantidad = Number(row.cantidad) || 0;
        const peso = Number(row.peso_total) || 0;
        if (row.es_pesable && peso > 0) return `${peso.toFixed(3)} kg`;
        return `${cantidad.toFixed(0)} ${row.unidad_medida || ''}`.trim();
    }

    async armarMensaje(pendientes, tipo) {
        const texto = await this.obtenerTexto();
        const nota = tipo === 'fijo'
            ? texto.notaFija
            : tipo === 'manual' ? texto.notaManual : texto.notaTanda;
        const detalle = pendientes
            .map((e) => reemplazar(texto.formatoItem, {
                producto: e.nombre,
                cantidad: e.cantidadTexto,
                motivo: e.motivo || 'sin motivo anotado',
                almacen: e.almacen || '',
            }))
            .join('\n');
        const { fecha, hora } = ahoraLocal();
        return reemplazar(texto.plantilla, {
            cantidad: String(pendientes.length),
            detalle,
            nota,
            fecha,
            hora,
        });
    }

    /**
     * Textos editables desde el panel. Una clave inexistente usa el default;
     * una clave vacía se respeta (para poder dejar, por ejemplo, la nota en
     * blanco).
     */
    async obtenerTexto() {
        const [plantilla, formatoItem, notaTanda, notaFija, notaManual] =
            await Promise.all([
                this.getSetting(K_PLANTILLA, { trim: false }),
                this.getSetting(K_FORMATO_ITEM, { trim: false }),
                this.getSetting(K_NOTA_TANDA, { trim: false }),
                this.getSetting(K_NOTA_FIJA, { trim: false }),
                this.getSetting(K_NOTA_MANUAL, { trim: false }),
            ]);
        return {
            plantilla: plantilla === null ? PLANTILLA_DEFECTO : plantilla,
            formatoItem: formatoItem === null
                ? FORMATO_ITEM_DEFECTO : formatoItem,
            notaTanda: notaTanda === null ? NOTA_TANDA_DEFECTO : notaTanda,
            notaFija: notaFija === null ? NOTA_FIJA_DEFECTO : notaFija,
            notaManual: notaManual === null
                ? NOTA_MANUAL_DEFECTO : notaManual,
        };
    }

    async guardarTexto({ plantilla, formatoItem, notaTanda, notaFija, notaManual }) {
        const limpiar = (v) => String(v).replace(/\r\n/g, '\n');
        const texto = {
            plantilla: limpiar(plantilla),
            formatoItem: limpiar(formatoItem),
            notaTanda: limpiar(notaTanda),
            notaFija: limpiar(notaFija),
            notaManual: limpiar(notaManual),
        };
        await Promise.all([
            this.setSetting(K_PLANTILLA, texto.plantilla),
            this.setSetting(K_FORMATO_ITEM, texto.formatoItem),
            this.setSetting(K_NOTA_TANDA, texto.notaTanda),
            this.setSetting(K_NOTA_FIJA, texto.notaFija),
            this.setSetting(K_NOTA_MANUAL, texto.notaManual),
        ]);
        return texto;
    }

    textosPorDefecto() {
        return {
            plantilla: PLANTILLA_DEFECTO,
            formatoItem: FORMATO_ITEM_DEFECTO,
            notaTanda: NOTA_TANDA_DEFECTO,
            notaFija: NOTA_FIJA_DEFECTO,
            notaManual: NOTA_MANUAL_DEFECTO,
        };
    }

    async estaHabilitado() {
        const valor = await this.getSetting(K_ENABLED);
        return !['0', 'false', 'off'].includes((valor || '').toLowerCase());
    }

    /**
     * Cambia el switch desde el panel. Al apagar corta los avisos ya
     * programados; al prender toma el estado actual como línea base para no
     * avisar por lo que ya estaba pendiente.
     */
    async definirHabilitado(habilitado) {
        await this.setSetting(K_ENABLED, habilitado ? '1' : '0');
        if (!habilitado) {
            if (this.debounceTimer) clearTimeout(this.debounceTimer);
            if (this.reintentoTimer) clearTimeout(this.reintentoTimer);
            this.debounceTimer = null;
            this.reintentoTimer = null;
        } else {
            this.maxIdVisto = null;
            this.poll();
        }
        return habilitado;
    }

    async getSetting(key, { trim = true } = {}) {
        try {
            const { rows } = await this.pool.query(
                'SELECT value FROM pos_settings WHERE key = $1', [key]
            );
            if (rows.length === 0) return null;
            const valor = rows[0].value || '';
            return trim ? valor.trim() : valor;
        } catch (error) {
            console.error(`[recordatorio] no se pudo leer ${key}:`, error.message);
            return null;
        }
    }

    async setSetting(key, value) {
        // Propaga el error: los endpoints del panel deben poder avisar que no
        // se guardó (antes se lo tragaba y el panel mostraba éxito falso).
        await this.pool.query(
            'INSERT INTO pos_settings (key, value) VALUES ($1, $2) ' +
            'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value',
            [key, value]
        );
    }
}

/**
 * Arranca el servicio si hay DATABASE_URL disponible. Si falta `pg` o la URL,
 * el bot sigue funcionando para los demás envíos y solo se desactiva este
 * recordatorio (con un log claro).
 */
function iniciarRecordatorioValidaciones(bot) {
    const url = resolverDatabaseUrl();
    if (!url) {
        console.warn('[recordatorio] sin DATABASE_URL; recordatorio desactivado. ' +
            'Agregala al .env del bot (ver .env.example).');
        return null;
    }

    let Pool;
    try {
        ({ Pool } = require('pg'));
    } catch (_) {
        console.warn("[recordatorio] falta el paquete 'pg'; ejecutá npm install " +
            'en whatsapp_bot/. Recordatorio desactivado.');
        return null;
    }

    const pool = new Pool({ connectionString: url, max: 2 });
    pool.on('error', (error) => {
        console.error('[recordatorio] error del pool:', error.message);
    });

    const servicio = new RecordatorioValidaciones(bot, pool);
    servicio.iniciar();
    console.log('[recordatorio] activo (30 min por tanda y 19:00 fijo).');
    return servicio;
}

module.exports = { iniciarRecordatorioValidaciones, RecordatorioValidaciones };
