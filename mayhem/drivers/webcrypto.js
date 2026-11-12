(async () => {
    try {
        const b = new Uint8Array(__in);
        if (b.length < 3) {
            return;
        }
        const subtle = crypto.subtle;
        const fmts = [ 'raw', 'pkcs8', 'spki', 'jwk' ];
        const E = (name, namedCurve) => ({ name, namedCurve });
        const H = (name) => ({ name, hash: 'SHA-256' });
        const algs = [
            { name: 'AES-GCM' }, { name: 'AES-CBC' }, { name: 'AES-CTR' }, { name: 'AES-KW' },
            H('HMAC'), H('RSA-OAEP'), H('RSASSA-PKCS1-v1_5'), H('RSA-PSS'),
            E('ECDSA', 'P-256'), E('ECDSA', 'P-384'), E('ECDSA', 'P-521'),
            E('ECDH', 'P-256'), E('ECDH', 'P-384'), E('ECDH', 'P-521'),
            { name: 'Ed25519' }, { name: 'X25519' }, { name: 'PBKDF2' }, { name: 'HKDF' },
        ];
        const usages = {
            'AES-GCM': [ [ 'encrypt', 'decrypt', 'wrapKey', 'unwrapKey' ] ],
            'AES-CBC': [ [ 'encrypt', 'decrypt', 'wrapKey', 'unwrapKey' ] ],
            'AES-CTR': [ [ 'encrypt', 'decrypt', 'wrapKey', 'unwrapKey' ] ],
            'AES-KW': [ [ 'wrapKey', 'unwrapKey' ] ],
            'HMAC': [ [ 'sign', 'verify' ] ],
            'RSA-OAEP': [ [ 'decrypt', 'unwrapKey' ], [ 'encrypt', 'wrapKey' ] ],
            'RSASSA-PKCS1-v1_5': [ [ 'sign' ], [ 'verify' ] ],
            'RSA-PSS': [ [ 'sign' ], [ 'verify' ] ],
            'ECDSA': [ [ 'sign' ], [ 'verify' ] ],
            'ECDH': [ [ 'deriveBits', 'deriveKey' ], [] ],
            'Ed25519': [ [ 'sign' ], [ 'verify' ] ],
            'X25519': [ [ 'deriveBits', 'deriveKey' ], [] ],
            'PBKDF2': [ [ 'deriveBits', 'deriveKey' ] ],
            'HKDF': [ [ 'deriveBits', 'deriveKey' ] ],
        };
        const fmt = fmts[b[0] & 3];
        const op = b[0] >> 2;
        const alg = algs[b[1] % algs.length];
        const data = b.subarray(2);
        const half = data.length >> 1;
        let keyData = data;

        if (fmt === 'jwk') {
            try { keyData = JSON.parse(new TextDecoder().decode(data)); } catch (e) { return; }
        }

        let key = null;

        for (const u of usages[alg.name]) {
            try {
                key = await subtle.importKey(fmt, keyData, alg, true, u);
                break;
            } catch (e) { /* wrong usage set or malformed key */ }
        }

        const sub = (x, y) => data.subarray(x, y);
        const iv = sub(0, 16);
        const params = {
            'AES-GCM': { name: 'AES-GCM', iv: sub(0, 12), additionalData: sub(12, 20), tagLength: 128 },
            'AES-CBC': { name: 'AES-CBC', iv },
            'AES-CTR': { name: 'AES-CTR', counter: iv, length: 64 },
            'AES-KW': { name: 'AES-KW' },
            'RSA-OAEP': { name: 'RSA-OAEP', label: sub(0, 4) },
            'HMAC': { name: 'HMAC' },
            'RSASSA-PKCS1-v1_5': { name: 'RSASSA-PKCS1-v1_5' },
            'RSA-PSS': { name: 'RSA-PSS', saltLength: 16 },
            'ECDSA': { name: 'ECDSA', hash: 'SHA-256' },
            'Ed25519': { name: 'Ed25519' },
        }[alg.name];

        if (key) {
            const attempt = async (f) => { try { await f(); } catch (e) { /* expected */ } };

            switch (op % 8) {
                case 0:
                    for (const f of fmts) { await attempt(() => subtle.exportKey(f, key)); }
                    break;
                case 1:
                    await attempt(() => subtle.sign(params, key, data));
                    break;
                case 2:
                    await attempt(() => subtle.verify(params, key, sub(0, half), sub(half)));
                    break;
                case 3:
                    await attempt(() => subtle.encrypt(params, key, sub(16)));
                    break;
                case 4:
                    await attempt(() => subtle.decrypt(params, key, sub(16)));
                    break;
                case 5:
                    if (alg.name === 'PBKDF2') {
                        await attempt(() => subtle.deriveBits({ name: 'PBKDF2', salt: sub(0, 8), iterations: 2, hash: 'SHA-256' }, key, 256));
                    } else if (alg.name === 'HKDF') {
                        await attempt(() => subtle.deriveBits({ name: 'HKDF', salt: sub(0, 8), info: sub(8, 16), hash: 'SHA-256' }, key, 256));
                    } else {
                        await attempt(() => subtle.deriveBits({ name: alg.name, public: key }, key, 256));
                    }
                    break;
                case 6:
                    await attempt(() => subtle.wrapKey('raw', key, key, params ?? alg));
                    await attempt(() => subtle.unwrapKey('raw', sub(0), key, params ?? alg, { name: 'AES-GCM' }, true, [ 'encrypt' ]));
                    break;
                default:
                    for (const h of [ 'SHA-1', 'SHA-256', 'SHA-384', 'SHA-512' ]) {
                        await attempt(() => subtle.digest(h, data));
                    }
                    break;
            }
        }
    } catch (e) { /* ignore */ }
})().finally(() => { globalThis.__done = true; });
