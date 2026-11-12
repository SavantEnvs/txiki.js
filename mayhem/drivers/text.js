(() => {
    try {
        const b = new Uint8Array(__in);
        const flags = b.length ? b[0] : 0;
        const body = b.subarray(1);
        const cut = body.length ? (flags >> 2) % (body.length + 1) : 0;

        try {
            const td = new TextDecoder('utf-8', { fatal: Boolean(flags & 1), ignoreBOM: Boolean(flags & 2) });

            td.decode(body);
            td.decode(body.subarray(0, cut), { stream: true });
            td.decode(body.subarray(cut), { stream: true });
            td.decode();
        } catch (e) { /* fatal decode errors */ }

        const s = new TextDecoder().decode(body);
        const enc = new TextEncoder();

        enc.encode(s);
        enc.encodeInto(s, new Uint8Array(cut));
        try { atob(s); } catch (e) { /* invalid base64 */ }
        try { btoa(s); } catch (e) { /* non-latin1 */ }
        try { btoa(String.fromCharCode(...body.subarray(0, 4096))); } catch (e) { /* ignore */ }
        try { new TextDecoder(s.trim().slice(0, 32)); } catch (e) { /* unknown label */ }
    } catch (e) { /* ignore */ }
    globalThis.__done = true;
})();
