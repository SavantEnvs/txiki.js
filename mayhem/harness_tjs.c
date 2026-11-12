/*
 * In-process libFuzzer harness for txiki.js. A fresh runtime is created per input; the fuzz bytes
 * enter only as an ArrayBuffer (`__in`) that a fixed driver script (mayhem/drivers/<target>.js, selected
 * at build time through DRIVER_FILE) feeds to one Web API. The input is never evaluated as host
 * code, and the driver calls no fs/process/network API, so the guest cannot reach the host.
 */
#include <stddef.h>
#include <stdint.h>

#include <quickjs.h>
#include <uv.h>

#include "private.h"
#include "tjs.h"

static const char driver[] = {
#embed DRIVER_FILE
    , 0
};

int LLVMFuzzerInitialize(int *argc, char ***argv) {
    TJS_Initialize(*argc, *argv);
    return 0;
}

static int driver_done(JSContext *ctx, JSValue global) {
    JSValue v = JS_GetPropertyStr(ctx, global, "__done");
    int done = JS_ToBool(ctx, v);
    JS_FreeValue(ctx, v);
    return done;
}

static void clear_exception(JSContext *ctx) {
    if (JS_HasException(ctx)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
    }
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    TJSRuntime *qrt = TJS_NewRuntime();
    JSContext *ctx = TJS_GetJSContext(qrt);
    JSRuntime *jsrt = JS_GetRuntime(ctx);
    uv_loop_t *loop = TJS_GetLoop(qrt);

    /* Let uv_loop_alive() reflect real work only (TJS_Run does the same). */
    uv_unref((uv_handle_t *) &qrt->stop);

    JSValue global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "__in", JS_NewArrayBufferCopy(ctx, data, size));

    JSValue ret = JS_Eval(ctx, driver, sizeof(driver) - 1, "<fuzz-driver>", JS_EVAL_TYPE_GLOBAL);
    JS_FreeValue(ctx, ret);
    clear_exception(ctx);

    while (!driver_done(ctx, global)) {
        tjs__execute_jobs(ctx);
        if (JS_HasException(ctx)) {
            break;
        }
        if (driver_done(ctx, global)) {
            break;
        }
        int pending = JS_IsJobPending(jsrt);
        if (!pending && !uv_loop_alive(loop)) {
            break;
        }
        uv_run(loop, pending ? UV_RUN_NOWAIT : UV_RUN_ONCE);
    }
    clear_exception(ctx);

    JS_FreeValue(ctx, global);
    TJS_FreeRuntime(qrt);
    return 0;
}
