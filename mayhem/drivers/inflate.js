(async () => {
    try {
        const b = new Uint8Array(__in);
        if (b.length < 2) {
            return;
        }
        const fmt = [ 'gzip', 'deflate', 'deflate-raw' ][b[0] % 3];
        const body = b.subarray(2);
        const cut = body.length ? b[1] % (body.length + 1) : 0;
        const ds = new DecompressionStream(fmt);
        const w = ds.writable.getWriter();
        const r = ds.readable.getReader();

        w.closed.catch(() => {});
        r.closed.catch(() => {});

        const reading = (async () => {
            let total = 0;

            for (;;) {
                const { done, value } = await r.read();

                if (done) {
                    break;
                }
                total += value.length;
                if (total > (1 << 24)) {
                    await r.cancel();
                    break;
                }
            }
        })().catch(() => {});

        try {
            await w.write(body.slice(0, cut));
            await w.write(body.slice(cut));
            await w.close();
        } catch (e) { /* corrupt stream */ }
        await reading;
    } catch (e) { /* ignore */ }
})().finally(() => { globalThis.__done = true; });
