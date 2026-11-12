(() => {
    try {
        const bytes = new Uint8Array(__in);
        const text = new TextDecoder().decode(bytes);
        const nl = text.indexOf('\n');
        const a = nl < 0 ? text : text.slice(0, nl);
        const b = nl < 0 ? undefined : text.slice(nl + 1);
        const props = [ 'href', 'protocol', 'username', 'password', 'host', 'hostname', 'port', 'pathname', 'search', 'hash' ];

        try { URL.canParse(a, b); } catch (e) { /* bad args */ }
        try { URL.parse(a, b); } catch (e) { /* bad args */ }
        try {
            const u = new URL(a, b);
            for (const p of props) { void u[p]; }
            void u.origin;
            String(u);
            JSON.stringify(u);
            const other = b ?? a;
            for (const p of props) {
                try { u[p] = other; } catch (e) { /* readonly or invalid */ }
                void u.href;
            }
            u.searchParams.append('k', a);
            u.searchParams.sort();
            void u.search;
            new URL(u.href);
        } catch (e) { /* TypeError: invalid URL */ }
        try {
            const sp = new URLSearchParams(a);
            sp.append(a, b ?? '');
            sp.set('x', a);
            sp.has(a);
            sp.getAll(a);
            sp.delete(a);
            sp.sort();
            [ ...sp ];
            String(sp);
        } catch (e) { /* ignore */ }
    } catch (e) { /* ignore */ }
    globalThis.__done = true;
})();
