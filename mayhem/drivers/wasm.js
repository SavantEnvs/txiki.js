(async () => {
    try {
        const bytes = new Uint8Array(__in);
        try { WebAssembly.validate(bytes); } catch (e) { /* invalid is expected */ }
        const mod = new WebAssembly.Module(bytes);
        const build = (bigint) => {
            const imports = {};
            for (const imp of WebAssembly.Module.imports(mod)) {
                const ns = imports[imp.module] ??= {};
                if (imp.kind === 'function') {
                    ns[imp.name] = () => (bigint ? 0n : 0);
                } else if (imp.kind === 'global') {
                    ns[imp.name] = bigint ? 0n : 0;
                } else if (imp.kind === 'memory') {
                    ns[imp.name] = new WebAssembly.Memory({ initial: 1, maximum: 16 });
                }
            }
            return imports;
        };
        let inst;
        try {
            inst = new WebAssembly.Instance(mod, build(false));
        } catch (e) {
            inst = new WebAssembly.Instance(mod, build(true));
        }
        let n = 0;
        for (const [ , v ] of Object.entries(inst.exports)) {
            if (typeof v === 'function' && n++ < 16) {
                const args = (big) => Array.from({ length: v.length }, () => (big ? 0n : 0));
                try { v(...args(false)); } catch (e) { try { v(...args(true)); } catch (e2) { /* trap */ } }
            } else if (v instanceof WebAssembly.Memory) {
                try { new Uint8Array(v.buffer).fill(1, 0, 16); v.grow(1); } catch (e) { /* limit */ }
            } else if (v instanceof WebAssembly.Table) {
                try { v.get(0); v.grow(1); } catch (e) { /* limit */ }
            } else if (v instanceof WebAssembly.Global) {
                try { void v.value; } catch (e) { /* type */ }
            }
        }
    } catch (e) {
        /* compile/link/runtime errors are the expected outcome for most inputs */
    }
    globalThis.__done = true;
})();
