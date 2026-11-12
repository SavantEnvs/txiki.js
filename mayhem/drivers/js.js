(() => {
    try {
        const text = new TextDecoder().decode(new Uint8Array(__in));
        const nl = text.indexOf('\n');
        const a = nl < 0 ? text : text.slice(0, nl);
        const rest = nl < 0 ? '' : text.slice(nl + 1);

        try { new Function(text); } catch (e) { /* SyntaxError */ }
        try { new Function('a', 'b', rest); } catch (e) { /* SyntaxError */ }
        try { JSON.parse(text); } catch (e) { /* SyntaxError */ }
        try {
            const re = new RegExp(a, rest.slice(0, 8));
            re.exec('abcABC123 é中\n');
            'xyz'.replace(re, '$1');
        } catch (e) { /* bad pattern */ }
    } catch (e) { /* ignore */ }
    globalThis.__done = true;
})();
